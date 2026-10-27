import SwiftUI
import PhotosUI

struct WebClipView: View {
    @EnvironmentObject private var app: AppViewModel
    @StateObject private var model = WebClipViewModel()
    @State private var bundleID = ""
    @State private var title = ""
    @State private var photo: PhotosPickerItem?
    @State private var png: Data?
    @State private var importing = false
    @State private var showConfirm = false
    @State private var showRefreshConfirm = false
    @State private var lastSubmittedBundle: String?

    private var supported: Bool {
        WebClipSpec.supportsTesting(on: ProcessInfo.processInfo.operatingSystemVersion)
    }
    private var valid: Bool { (try? WebClipSpec(bundleID: bundleID, title: title)) != nil && png != nil }
    private var otherOperationRunning: Bool {
        app.cardFlashPhase == .running || app.passthmFlashPhase == .running ||
        app.tendiesFlashPhase == .running || app.pairingPhase == .pairing || app.isDetectingContainer
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Label("实验功能 · iOS 27.0.1", systemImage: "testtube.2")
                    Text("新增可直接打开 App 的自定义桌面图标。此写入方式尚待实机验证，请先完成设备备份。")
                        .font(.footnote).foregroundStyle(.secondary)
                    if !supported {
                        Text("当前系统不是 27.0.1，写入已关闭。仍可预览图标。")
                            .foregroundStyle(.orange)
                    }
                }
                Section("目标 App") {
                    TextField("Bundle ID，例如 com.tencent.xin", text: $bundleID)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .keyboardType(.asciiCapable)
                    TextField("桌面名称（可留空）", text: $title)
                    Text("填写手机上已安装 App 的 Bundle ID。自签 App 可能使用修改后的 ID，请以签名工具显示的值为准。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("图标预览") {
                    PhotosPicker(selection: $photo, matching: .images) {
                        Label("从相册选择图标", systemImage: "photo")
                    }
                    if importing { ProgressView("正在处理图片…") }
                    if let png, let image = UIImage(data: png) {
                        HStack {
                            Spacer()
                            VStack(spacing: 8) {
                                Image(uiImage: image).resizable().frame(width: 72, height: 72)
                                    .clipShape(RoundedRectangle(cornerRadius: 16))
                                Text(title.trimmingCharacters(in: .whitespacesAndNewlines))
                                    .font(.caption).lineLimit(1)
                            }
                            .padding()
                            Spacer()
                        }
                        Text("图片将居中裁剪为正方形；透明区域使用白底。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Section {
                    if !app.hasPairingFile {
                        Button("先完成设备配对") { app.selectedTab = .pairing }
                    }
                    Button("新增一个测试图标") { showConfirm = true }
                        .disabled(!supported || !valid || !app.hasPairingFile || importing || otherOperationRunning || model.isRunning || lastSubmittedBundle == bundleID)
                    Text(model.status).font(.footnote).foregroundStyle(.secondary)
                    if lastSubmittedBundle == bundleID {
                        Text("此 App 本次已尝试写入。先检查桌面和记录，避免连续写入生成重复图标。重新打开应用后可再次测试。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Button("刷新桌面") { showRefreshConfirm = true }
                        .disabled(!model.mayRefresh || model.isRunning || otherOperationRunning)
                }
                Section("测试与移除") {
                    Text("写入后检查：图标是否显示、是否打开正确 App、是否出现快捷指令提示、重启后是否保留。")
                    Text("如果需要移除，先尝试长按新增图标并删除书签。不要删除原 App。若图标未显示，请保留下面的记录用于排查。")
                }.font(.footnote)
                if !model.receipts.isEmpty {
                    Section("写入记录") {
                        ForEach(model.receipts) { receipt in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(receipt.spec.title.isEmpty ? receipt.spec.bundleID : receipt.spec.title).font(.headline)
                                Text(receipt.status).font(.caption)
                                Text(receipt.createdAt, style: .date).font(.caption2)
                                Text(receipt.spec.targetPath).font(.system(.caption2, design: .monospaced))
                                    .textSelection(.enabled)
                            }
                        }
                    }
                }
            }
            .navigationTitle("WebClip 主题")
            .onChange(of: photo) { _, selection in
                Task {
                    importing = true
                    defer { importing = false }
                    do {
                        guard let selection, let data = try await selection.loadTransferable(type: Data.self) else { return }
                        png = try WebClipEngine.iconPNG(from: data)
                    } catch { model.error = error.localizedDescription }
                }
            }
            .confirmationDialog("新增测试图标？", isPresented: $showConfirm, titleVisibility: .visible) {
                Button("写入一个 WebClip") {
                    guard let png else { return }
                    let selectedBundle = bundleID
                    let selectedTitle = title
                    lastSubmittedBundle = selectedBundle
                    Task { await model.install(bundleID: selectedBundle, title: selectedTitle, png: png, app: app) }
                }
            } message: {
                Text("将为 \(bundleID) 新增一个独立图标。实验功能仍可能发生系统异常；请确认已有备份。")
            }
            .confirmationDialog("刷新桌面会中断当前界面", isPresented: $showRefreshConfirm, titleVisibility: .visible) {
                Button("使用 NeoSpring 刷新") { RespringHelper.triggerNeoSpring() }
            } message: {
                Text("你也可以先手动重启手机，再检查新增图标。")
            }
            .alert("WebClip 提示", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
                Button("好") { model.error = nil }
            } message: { Text(model.error ?? "") }
        }
    }
}
