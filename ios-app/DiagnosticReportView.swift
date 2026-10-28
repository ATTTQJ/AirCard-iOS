import SwiftUI
import UniformTypeIdentifiers

struct DiagnosticTextDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.plainText] }
    var text: String
    init(text: String) { self.text = text }
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents,
              let text = String(data: data, encoding: .utf8) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.text = text
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}

/// Export does not depend on VPN, pairing, or device access.
struct DiagnosticReportActions: View {
    let report: String
    @State private var showingReport = false

    var body: some View {
        Button { showingReport = true } label: {
            Label("查看、复制或保存完整报告", systemImage: "doc.text")
        }
        .accessibilityIdentifier("webclip.openReport")
        .sheet(isPresented: $showingReport) {
            DiagnosticReportView(report: report)
        }
    }
}

struct DiagnosticReportView: View {
    let report: String
    @Environment(\.dismiss) private var dismiss
    @State private var exporting = false
    @State private var notice: LocalizedStringKey?
    @State private var exportError: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                Text(verbatim: report)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .accessibilityIdentifier("webclip.fullReport")
            }
            .navigationTitle("完整诊断报告")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 10) {
                    if let notice { Text(notice).font(.caption).foregroundStyle(.secondary) }
                    Button {
                        UIPasteboard.general.string = report
                        notice = "完整报告已复制，可以返回聊天粘贴。"
                    } label: {
                        Label("复制完整报告", systemImage: "doc.on.doc")
                            .frame(maxWidth: .infinity)
                    }
                    .accessibilityIdentifier("webclip.copyReport")
                    .buttonStyle(.borderedProminent)
                    Button {
                        exporting = true
                    } label: {
                        Label("保存为 TXT 文件", systemImage: "folder")
                            .frame(maxWidth: .infinity)
                    }
                    .accessibilityIdentifier("webclip.saveReport")
                    .buttonStyle(.bordered)
                }
                .padding().background(.bar)
            }
            .fileExporter(isPresented: $exporting,
                          document: DiagnosticTextDocument(text: report),
                          contentType: .plainText,
                          defaultFilename: "WebClip-Diagnostic-Report") { result in
                switch result {
                case .success: notice = "报告文件已保存。"
                case .failure(let error): exportError = error.localizedDescription
                }
            }
            .alert("保存报告失败", isPresented: Binding(get: { exportError != nil }, set: { if !$0 { exportError = nil } })) {
                Button("好") { exportError = nil }
            } message: {
                Text(exportError ?? "")
            }
        }
    }
}
