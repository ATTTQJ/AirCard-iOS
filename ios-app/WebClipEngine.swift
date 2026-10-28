import Foundation
import Combine
import UIKit
import AirliftFFI

/// Uses the existing AirCard transport. Never invokes backup/restore or writes a
/// SpringBoard layout database. New UUID directories avoid replacing old clips.
enum WebClipEngine {
    private static let queue = DispatchQueue(label: "com.atttqj.aircard.webclip", qos: .userInitiated)

    static func iconPNG(from data: Data) throws -> Data {
        guard data.count <= 25 * 1024 * 1024,
              let image = UIImage(data: data), image.size.width > 0, image.size.height > 0 else {
            throw WebClipError.invalidImage
        }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let size = CGSize(width: 180, height: 180)
        let rendered = UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            let scale = max(size.width / image.size.width, size.height / image.size.height)
            let width = image.size.width * scale
            let height = image.size.height * scale
            image.draw(in: CGRect(x: (180 - width) / 2, y: (180 - height) / 2, width: width, height: height))
        }
        guard let png = rendered.pngData() else { throw WebClipError.invalidImage }
        return png
    }

    static func install(spec: WebClipSpec, png: Data, pairingPath: String) async throws {
        // Validate again at the device boundary, independent of the UI.
        guard WebClipSpec.supportsTesting(on: ProcessInfo.processInfo.operatingSystemVersion) else {
            throw WebClipError.unsupportedOS
        }
        _ = try WebClipSpec(bundleID: spec.bundleID, title: spec.title, id: spec.id)
        guard FileManager.default.fileExists(atPath: pairingPath) else { throw WebClipError.noPairing }
        guard UIImage(data: png) != nil, png.count < 1024 * 1024 else { throw WebClipError.invalidImage }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async {
                do {
                    let stage = FileManager.default.temporaryDirectory
                        .appendingPathComponent("webclip-stage-\(UUID().uuidString)", isDirectory: true)
                    try FileManager.default.createDirectory(at: stage, withIntermediateDirectories: false)
                    defer { try? FileManager.default.removeItem(at: stage) }
                    try spec.plistData().write(to: stage.appendingPathComponent("Info.plist"), options: .atomic)
                    try png.write(to: stage.appendingPathComponent("icon.png"), options: .atomic)
                    var errorPointer: UnsafeMutablePointer<CChar>?
                    let rc = pairingPath.withCString { pairing in
                        stage.path.withCString { source in
                            WebClipSpec.targetParent.withCString { parent in
                                spec.folderName.withCString { destination in
                                    al_exploit_inject_folder(pairing, source, parent, destination, nil, nil, &errorPointer)
                                }
                            }
                        }
                    }
                    let message = errorPointer.map { String(cString: $0) }
                    if let pointer = errorPointer { al_string_free(pointer) }
                    guard rc == 0 else {
                        throw WebClipError.transport(message ?? "AirLift 写入失败（代码 \(rc)）。可能留下部分书签文件，请先检查桌面。")
                    }
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}

@MainActor
final class WebClipViewModel: ObservableObject {
    @Published var receipts: [WebClipReceipt] = []
    @Published var status = "准备好图标后，可先预览再写入。"
    @Published var error: String?
    @Published var isRunning = false
    @Published var mayRefresh = false
    private let storageKey = "atttqj.webclips.receipts.v1"

    init() {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let saved = try? JSONDecoder().decode([WebClipReceipt].self, from: data) {
            receipts = saved
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(receipts) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    func install(bundleID: String, title: String, png: Data, app: AppViewModel) async {
        guard !isRunning, !app.webClipIsRunning,
              app.cardFlashPhase != .running, app.passthmFlashPhase != .running,
              app.tendiesFlashPhase != .running, app.pairingPhase != .pairing,
              !app.isDetectingContainer else { error = WebClipError.busy.localizedDescription; return }
        guard app.hasPairingFile else { error = WebClipError.noPairing.localizedDescription; return }
        guard app.vpnUp else { error = "请先连接 LocalDevVPN，再返回此页面。"; return }
        guard WebClipSpec.supportsTesting(on: ProcessInfo.processInfo.operatingSystemVersion) else {
            error = WebClipError.unsupportedOS.localizedDescription; return
        }
        do {
            let spec = try WebClipSpec(bundleID: bundleID, title: title)
            // Save the receipt BEFORE the write. A killed app must not lose the
            // identity of an operation which may already have changed the device.
            receipts.insert(WebClipReceipt(spec: spec, createdAt: Date(), status: "已开始，结果待确认"), at: 0)
            save()
            isRunning = true
            app.webClipIsRunning = true
            mayRefresh = false
            error = nil
            status = "正在新增一个 WebClip。请保持应用在前台，等待操作结束。"
            let previousIdleSetting = UIApplication.shared.isIdleTimerDisabled
            UIApplication.shared.isIdleTimerDisabled = true
            defer {
                UIApplication.shared.isIdleTimerDisabled = previousIdleSetting
                isRunning = false
                app.webClipIsRunning = false
            }
            app.syncTargetHostsToRust()
            do {
                try await WebClipEngine.install(spec: spec, png: png, pairingPath: PairingController.pairingFilePath())
                update(spec.id, status: "写入接口返回成功，桌面效果未验证")
                status = "写入接口已返回成功。请刷新桌面后检查图标；这不代表系统已识别或启动验证通过。"
                mayRefresh = true
            } catch {
                update(spec.id, status: "失败或结果不确定，请检查桌面")
                status = "操作未完成，未自动重试。请保留记录并先检查桌面。"
                self.error = error.localizedDescription
            }
        } catch { self.error = error.localizedDescription }
    }

    private func update(_ id: UUID, status: String) {
        if let index = receipts.firstIndex(where: { $0.id == id }) {
            receipts[index].status = status
            save()
        }
    }
}
