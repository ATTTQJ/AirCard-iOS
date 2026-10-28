import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

struct WebClipView: View {
    @EnvironmentObject private var app: AppViewModel
    @StateObject private var model = WebClipViewModel()
    @AppStorage("webclip.draft.bundle") private var bundleID = ""
    @AppStorage("webclip.draft.title") private var title = ""
    @State private var photo: PhotosPickerItem?
    @State private var png: Data?
    @State private var importing = false
    @State private var showFiles = false
    @State private var showConfirm = false
    @State private var showRefreshConfirm = false
    @State private var showHistory = false
    @State private var showHelp = false
    @State private var lastSubmittedBundle: String?
    @FocusState private var editing: Bool

    private var supported: Bool {
        WebClipSpec.supportsTesting(on: ProcessInfo.processInfo.operatingSystemVersion)
    }
    private var spec: WebClipSpec? { try? WebClipSpec(bundleID: bundleID, title: title) }
    private var otherOperationRunning: Bool {
        app.cardFlashPhase == .running || app.passthmFlashPhase == .running ||
        app.tendiesFlashPhase == .running || app.pairingPhase == .pairing || app.isDetectingContainer
    }
    private var blockedReason: String? {
        if !supported { return "当前系统未开放写入，仅可预览；测试版本为 iOS 27.0.1。" }
        if model.isRunning || otherOperationRunning { return "另一项设备操作仍在进行，请等待结束。" }
        if !app.hasPairingFile { return "请先到首页完成本机配对。" }
        if !app.vpnUp { return "请先连接 LocalDevVPN，再返回此页面。" }
        if importing { return "正在处理图片，请稍候。" }
        if png == nil { return "先选择一张图片作为图标。" }
        if bundleID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "填写要打开的 App 的 Bundle ID。" }
        if spec == nil { return "请检查 App 标识和图标名称。" }
        if lastSubmittedBundle == spec?.bundleID { return "此 App 本次已尝试写入，请先查看桌面和写入记录。" }
        return nil
    }

    var body: some View {
        NavigationStack {
            Form {
                previewSection
                imageSection
                targetSection
                readinessSection
                if model.mayRefresh {
                    Section("下一步") {
                        Label("写入接口返回成功，桌面效果待检查", systemImage: "checkmark.circle")
                        Button("刷新桌面并检查图标") { showRefreshConfirm = true }
                        Text("也可以手动重启。请检查是否打开正确 App、是否出现快捷指令提示，以及重启后图标是否保留。")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
                Section {
                    Text(LocalizedStringKey(model.status)).font(.footnote).foregroundStyle(.secondary)
                    Button("查看测试说明与移除方法") { showHelp = true }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("图标主题")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showHistory = true } label: { Label("写入记录", systemImage: "clock.arrow.circlepath") }
                        .accessibilityIdentifier("webclip.history")
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("完成") { editing = false }
                }
            }
            .safeAreaInset(edge: .bottom) { actionBar }
            .onAppear { app.refreshNetworkStatus(); app.refreshPairingFile() }
            .task(id: photo) {
                guard let photo else { return }
                importing = true
                defer { importing = false }
                do {
                    guard let data = try await photo.loadTransferable(type: Data.self) else { throw WebClipError.invalidImage }
                    try Task.checkCancellation()
                    png = try WebClipEngine.iconPNG(from: data)
                } catch is CancellationError { } catch { model.error = error.localizedDescription }
            }
            .fileImporter(isPresented: $showFiles, allowedContentTypes: [.image]) { result in
                do {
                    let url = try result.get()
                    let scoped = url.startAccessingSecurityScopedResource()
                    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                    let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                    guard size <= 25 * 1024 * 1024 else { throw WebClipError.invalidImage }
                    png = try WebClipEngine.iconPNG(from: Data(contentsOf: url))
                } catch { model.error = error.localizedDescription }
            }
            .confirmationDialog("新增测试图标？", isPresented: $showConfirm, titleVisibility: .visible) {
                Button("确认新增一个图标") {
                    guard blockedReason == nil, let png, let spec else { return }
                    lastSubmittedBundle = spec.bundleID
                    Task { await model.install(bundleID: spec.bundleID, title: spec.title, png: png, app: app) }
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("将为 \(bundleID) 新增独立图标。此方式尚未通过实机验证；请确认已有备份，再进行单图标测试。")
            }
            .confirmationDialog("刷新桌面会中断当前界面", isPresented: $showRefreshConfirm, titleVisibility: .visible) {
                Button("刷新桌面") { RespringHelper.triggerNeoSpring() }
                Button("取消", role: .cancel) {}
            } message: { Text("刷新使用 NeoSpring，也可以稍后手动重启手机。") }
            .alert("WebClip 提示", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
                Button("好") { model.error = nil }
            } message: { Text(LocalizedStringKey(model.error ?? "")) }
            .sheet(isPresented: $showHistory) { historySheet }
            .sheet(isPresented: $showHelp) { helpSheet }
        }
    }

    private var previewSection: some View {
        Section {
            VStack(spacing: 14) {
                HStack {
                    Label("WebClip · 实验功能", systemImage: "testtube.2").font(.caption.weight(.semibold))
                    Spacer()
                    Text("iOS 27.0.1").font(.caption.monospaced())
                }.foregroundStyle(.secondary)
                VStack(spacing: 8) {
                    Group {
                        if let png, let image = UIImage(data: png) {
                            Image(uiImage: image).resizable().scaledToFill()
                        } else {
                            Image(systemName: "photo.badge.plus").font(.system(size: 32)).foregroundStyle(.blue)
                                .frame(maxWidth: .infinity, maxHeight: .infinity).background(.background)
                        }
                    }
                    .frame(width: 76, height: 76)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .accessibilityLabel("桌面图标预览")
                    Text(title.isEmpty ? " " : title).font(.caption).lineLimit(2)
                }
                .frame(maxWidth: .infinity).padding(.vertical, 20)
                .background(LinearGradient(colors: [.blue.opacity(0.16), .purple.opacity(0.12)], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 20))
                Text("创建一个打开 App 的桌面书签，保留原 App。首次请只测试一个图标。")
                    .font(.footnote).foregroundStyle(.secondary)
            }.padding(.vertical, 6)
        }
    }

    private var imageSection: some View {
        Section("1 · 选择图标") {
            PhotosPicker(selection: $photo, matching: .images) {
                Label("从相册选择", systemImage: "photo")
            }.disabled(importing)
            Button { showFiles = true } label: { Label("从文件选择", systemImage: "folder") }
                .disabled(importing)
            if importing { ProgressView("正在处理图片…") }
            if png != nil {
                Button("移除所选图片", role: .destructive) { png = nil; photo = nil }
            }
        } footer: {
            Text("图片居中裁剪为正方形；透明区域使用白底。可先在相册中裁剪到满意的位置。")
        }
    }

    private var targetSection: some View {
        Section("2 · 关联 App") {
            VStack(alignment: .leading, spacing: 6) {
                Text("App 标识（Bundle ID）").font(.caption).foregroundStyle(.secondary)
                TextField("例如 com.tencent.xin", text: $bundleID)
                    .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.asciiCapable)
                    .focused($editing).accessibilityIdentifier("webclip.bundleID")
            }
            TextField("桌面名称（留空则隐藏名称）", text: $title).focused($editing)
                .accessibilityIdentifier("webclip.title")
            if !bundleID.isEmpty, spec == nil {
                Label("标识应类似 com.example.app；名称最多 80 字，不能包含换行。", systemImage: "exclamationmark.circle")
                    .font(.caption).foregroundStyle(.orange)
            }
            DisclosureGroup("不知道 Bundle ID？") {
                Text("这是 App 的唯一标识，不是网址或 App 名称。此版本无法读取已安装 App 列表，请填写目标 App 的真实标识；自签 App 请查看签名工具中的 Bundle ID。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    private var readinessSection: some View {
        Section("3 · 检查设备") {
            readiness("系统为 iOS 27.0.1", ready: supported)
            readiness("已导入本机配对文件", ready: app.hasPairingFile)
            readiness("已检测到本地 VPN", ready: app.vpnUp)
            if !app.hasPairingFile || !app.vpnUp {
                Button("前往首页设置配对与 VPN") { editing = false; app.selectedTab = .pairing }
            }
            Button("重新检查连接") { app.refreshNetworkStatus(); app.refreshPairingFile() }
        } footer: {
            Text("准备状态只检查前置条件，不代表此设备上的写入一定成功。")
        }
    }

    private func readiness(_ title: LocalizedStringKey, ready: Bool) -> some View {
        Label(title, systemImage: ready ? "checkmark.circle.fill" : "circle")
            .foregroundStyle(ready ? Color.green : Color.secondary)
            .accessibilityValue(ready ? "已准备" : "未准备")
    }

    private var actionBar: some View {
        VStack(spacing: 8) {
            if let reason = blockedReason {
                Text(LocalizedStringKey(reason)).font(.caption).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            }
            Button {
                editing = false
                showConfirm = true
            } label: {
                Label("新增一个测试图标", systemImage: "plus.app.fill")
                    .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent).disabled(blockedReason != nil)
            .accessibilityIdentifier("webclip.install")
        }
        .padding(.horizontal).padding(.vertical, 10).background(.bar)
    }

    private var historySheet: some View {
        NavigationStack {
            List {
                if model.receipts.isEmpty {
                    ContentUnavailableView("暂无写入记录", systemImage: "clock", description: Text("尝试新增图标后，这里会保留结果，方便检查和排查问题。"))
                }
                ForEach(model.receipts) { receipt in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(receipt.spec.title.isEmpty ? receipt.spec.bundleID : receipt.spec.title).font(.headline)
                        Text(receipt.spec.bundleID).font(.caption).textSelection(.enabled)
                        Text(LocalizedStringKey(receipt.status)).font(.subheadline)
                        Text(receipt.createdAt, format: .dateTime.year().month().day().hour().minute()).font(.caption).foregroundStyle(.secondary)
                        DisclosureGroup("排查信息") {
                            Text(receipt.spec.targetPath).font(.system(.caption2, design: .monospaced)).textSelection(.enabled)
                        }
                    }
                }
            }
            .navigationTitle("写入记录").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { showHistory = false } } }
        }
    }

    private var helpSheet: some View {
        NavigationStack {
            List {
                Section("首次使用") {
                    Text("先备份设备，再到首页设置配对文件与 LocalDevVPN。返回图标主题，选择图片、填写真实 Bundle ID，预览后新增一个测试图标。")
                }
                Section("写入后检查") {
                    Text("写入成功只表示接口返回成功。刷新桌面或重启后，检查图标是否出现、能否打开正确 App、是否显示快捷指令提示，以及重启后是否保留。")
                }
                Section("如何移除") {
                    Text("长按新增图标，尝试删除书签；不要删除原 App。若图标没有出现或无法删除，保留写入记录用于排查，不要连续重复写入。")
                }
                Section("当前限制") {
                    Text("目前仅测试 iOS 27.0.1 的单图标流程，暂不支持整包主题或批量替换。未通过实机验证，不能保证没有数据风险。")
                }
            }
            .navigationTitle("WebClip 使用说明").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { showHelp = false } } }
        }
    }
}
