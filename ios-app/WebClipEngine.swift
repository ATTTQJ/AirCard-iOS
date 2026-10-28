import Foundation
import Combine
import UIKit
import AirliftFFI

private final class WebClipLogBuffer {
    private let lock = NSLock()
    private var entries: [String] = []
    func append(_ line: String) {
        lock.lock(); defer { lock.unlock() }
        entries.append(line)
        if entries.count > 1000 { entries.removeFirst() }
    }
    var lines: [String] {
        lock.lock(); defer { lock.unlock() }
        return entries
    }
}

private struct WebClipAttemptFailure: LocalizedError {
    let message: String
    let lines: [String]
    var errorDescription: String? { message }
}

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

    /// Explicit diagnostic, separate from icon installation. Writes a random canary,
    /// recovers its exact bytes, and asks the existing core to clean up afterwards.
    static func verifyDirectory(pairingPath: String) async throws -> String {
        guard WebClipSpec.supportsTesting(on: ProcessInfo.processInfo.operatingSystemVersion) else {
            throw WebClipError.unsupportedOS
        }
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
            queue.async {
                let buffer = WebClipLogBuffer()
                var jsonPointer: UnsafeMutablePointer<CChar>?
                var errorPointer: UnsafeMutablePointer<CChar>?
                let rc = pairingPath.withCString { pairing in
                    WebClipSpec.targetParent.withCString { target in
                        al_exploit_run(pairing, target, { context, message in
                            guard let context, let message else { return }
                            Unmanaged<WebClipLogBuffer>.fromOpaque(context).takeUnretainedValue().append(String(cString: message))
                        }, Unmanaged.passUnretained(buffer).toOpaque(), &jsonPointer, &errorPointer)
                    }
                }
                let json = jsonPointer.map { String(cString: $0) }
                let error = errorPointer.map { String(cString: $0) }
                if let pointer = jsonPointer { al_string_free(pointer) }
                if let pointer = errorPointer { al_string_free(pointer) }
                // Some core builds return JSON even if its ok field is false.
                // The exact readback fields, not rc alone, determine the verdict.
                let object = json.flatMap { $0.data(using: .utf8) }
                    .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
                let exact = object?["exactBytesRecovered"] as? Bool == true
                let cleaned = object?["cleanupComplete"] as? Bool == true
                let verdict = rc == 0 && exact ? "目录字节读回验证通过；尚未验证书签注册。" : "目录读回未确认；请停止新增图标并保留此报告。"
                let cleanup = cleaned ? "核心库报告临时文件清理完成。" : "临时文件清理未确认，请保留报告排查。"
                let report = ([verdict, cleanup, json ?? error ?? "未返回结构化结果"] + buffer.lines).joined(separator: "\n")
                continuation.resume(returning: report)
            }
        }
    }

    static func install(spec: WebClipSpec, png: Data, pairingPath: String) async throws -> [String] {
        // Validate again at the device boundary, independent of the UI.
        guard WebClipSpec.supportsTesting(on: ProcessInfo.processInfo.operatingSystemVersion) else {
            throw WebClipError.unsupportedOS
        }
        _ = try WebClipSpec(bundleID: spec.bundleID, title: spec.title, id: spec.id)
        guard FileManager.default.fileExists(atPath: pairingPath) else { throw WebClipError.noPairing }
        guard UIImage(data: png) != nil, png.count < 1024 * 1024 else { throw WebClipError.invalidImage }

        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[String], Error>) in
            queue.async {
                do {
                    let stage = FileManager.default.temporaryDirectory
                        .appendingPathComponent("webclip-stage-\(UUID().uuidString)", isDirectory: true)
                    try FileManager.default.createDirectory(at: stage, withIntermediateDirectories: false)
                    defer { try? FileManager.default.removeItem(at: stage) }
                    try spec.plistData().write(to: stage.appendingPathComponent("Info.plist"), options: .atomic)
                    try png.write(to: stage.appendingPathComponent("icon.png"), options: .atomic)
                    let logBuffer = WebClipLogBuffer()
                    var errorPointer: UnsafeMutablePointer<CChar>?
                    let rc = pairingPath.withCString { pairing in
                        stage.path.withCString { source in
                            WebClipSpec.targetParent.withCString { parent in
                                spec.folderName.withCString { destination in
                                    al_exploit_inject_folder(pairing, source, parent, destination, { context, message in
                                        guard let context, let message else { return }
                                        Unmanaged<WebClipLogBuffer>.fromOpaque(context).takeUnretainedValue()
                                            .append(String(cString: message))
                                    }, Unmanaged.passUnretained(logBuffer).toOpaque(), &errorPointer)
                                }
                            }
                        }
                    }
                    let message = errorPointer.map { String(cString: $0) }
                    if let pointer = errorPointer { al_string_free(pointer) }
                    guard rc == 0 else {
                        throw WebClipAttemptFailure(message: message ?? "AirLift 写入失败（代码 \(rc)）。可能留下部分书签文件，请先检查桌面。", lines: logBuffer.lines)
                    }
                    continuation.resume(returning: logBuffer.lines)
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
    @Published var blockedBundleID: String?
    @Published var directoryReport = UserDefaults.standard.string(forKey: "webclip.directoryReport")
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
        app.refreshNetworkStatus()
        guard app.vpnUp else { error = "请先连接 LocalDevVPN，再返回此页面。"; return }
        guard WebClipSpec.supportsTesting(on: ProcessInfo.processInfo.operatingSystemVersion) else {
            error = WebClipError.unsupportedOS.localizedDescription; return
        }
        do {
            let spec = try WebClipSpec(bundleID: bundleID, title: title)
            guard blockedBundleID != spec.bundleID else { return }
            blockedBundleID = spec.bundleID
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
                let lines = try await WebClipEngine.install(spec: spec, png: png, pairingPath: PairingController.pairingFilePath())
                update(spec.id, status: "写入接口返回成功，桌面效果未验证", diagnostic: lines.joined(separator: "\n"))
                status = "写入接口已返回成功。请刷新桌面后检查图标；这不代表系统已识别或启动验证通过。"
                mayRefresh = true
            } catch {
                let failure = error as? WebClipAttemptFailure
                let detail = ([error.localizedDescription] + (failure?.lines ?? [])).joined(separator: "\n")
                if let failure, WebClipConnectionFailure.isBeforeWrite(failure.message) {
                    blockedBundleID = nil
                    update(spec.id, status: "设备连接失败，未开始写入", diagnostic: detail)
                    status = "请检查本地 VPN、目标 IP 和本机配对文件，再手动重试。"
                    self.error = "未能连接设备服务，尚未开始写入 WebClip。请关闭其他 VPN，连接 LocalDevVPN，再到首页检查目标 IP 和配对文件。无需仅为此连接 Wi-Fi。备用地址的超时不代表检测到了 Wi-Fi；原始错误已保存在写入记录中。"
                } else {
                    update(spec.id, status: "失败或结果不确定，请检查桌面", diagnostic: detail)
                    status = "操作未完成，未自动重试。请保留记录并先检查桌面。"
                    self.error = detail
                }
            }
        } catch { self.error = error.localizedDescription }
    }

    func verifyDirectory(app: AppViewModel) async {
        guard !isRunning, !app.webClipIsRunning,
              app.cardFlashPhase != .running, app.passthmFlashPhase != .running,
              app.tendiesFlashPhase != .running, app.pairingPhase != .pairing,
              !app.isDetectingContainer else { error = WebClipError.busy.localizedDescription; return }
        app.refreshNetworkStatus()
        guard app.hasPairingFile, app.vpnUp else { error = "请先完成配对并连接 LocalDevVPN。"; return }
        isRunning = true
        app.webClipIsRunning = true
        let previousIdle = UIApplication.shared.isIdleTimerDisabled
        UIApplication.shared.isIdleTimerDisabled = true
        defer {
            isRunning = false
            app.webClipIsRunning = false
            UIApplication.shared.isIdleTimerDisabled = previousIdle
        }
        do {
            app.syncTargetHostsToRust()
            directoryReport = try await WebClipEngine.verifyDirectory(pairingPath: PairingController.pairingFilePath())
            UserDefaults.standard.set(directoryReport, forKey: "webclip.directoryReport")
        } catch { self.error = error.localizedDescription }
    }

    private func update(_ id: UUID, status: String, diagnostic: String? = nil) {
        if let index = receipts.firstIndex(where: { $0.id == id }) {
            receipts[index].status = status
            receipts[index].diagnostic = diagnostic
            save()
        }
    }
}
