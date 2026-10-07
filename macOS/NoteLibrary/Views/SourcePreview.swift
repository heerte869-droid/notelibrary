import SwiftUI
import AppKit
import Quartz

struct SourceAttachmentCard: View {
    @EnvironmentObject private var model: AppModel
    let id: String
    var removable = false
    private var asset: SourceAsset? { model.asset(id) }
    var body: some View {
        HStack(spacing: 4) {
            Button { model.selectedSourceID = id } label: {
                HStack(spacing: 9) {
                    if asset?.isImage == true, let url = model.assetURL(id) {
                        SourceImageView(url: url, revision: asset?.digest ?? "", maxPixelSize: 96, contentMode: .fill).frame(width: 38, height: 38).clipped().clipShape(RoundedRectangle(cornerRadius: 7))
                    } else {
                        Image(systemName: asset?.icon ?? "doc.text").font(.system(size: 18)).foregroundStyle(Theme.accent)
                            .frame(width: 38, height: 38).background(Theme.accent.opacity(0.075), in: RoundedRectangle(cornerRadius: 8))
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(asset?.displayName ?? "原稿不可用").font(.system(size: 11, weight: .medium)).lineLimit(1).truncationMode(.middle)
                        Text(asset?.detail ?? "文件缺失").font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(1)
                    }.frame(width: 142, alignment: .leading)
                }.padding(6).contentShape(Rectangle())
            }.buttonStyle(FeedbackStyle(compact: true)).disabled(asset == nil).help("预览原稿")
                .accessibilityLabel("预览原稿：" + (asset?.displayName ?? "文件缺失"))
            if removable { QuietIconButton(icon: "xmark", label: "移除附件 " + (asset?.displayName ?? "")) { model.attachments.removeAll { $0 == id } }.padding(.trailing, 4) }
        }.background(Theme.background, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.border.opacity(0.65), lineWidth: 1).allowsHitTesting(false))
    }
}

struct SourcePreview: View {
    @EnvironmentObject private var model: AppModel
    let id: String
    @State private var mode: String?
    private var asset: SourceAsset? { model.asset(id) }
    private var canPreviewOriginal: Bool { ["pdf", "docx", "doc", "rtf", "odt"].contains(((asset?.filename ?? "") as NSString).pathExtension.lowercased()) }
    private var selectedMode: String { mode ?? (canPreviewOriginal ? "original" : "text") }
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Image(systemName: asset?.icon ?? "doc.text").foregroundStyle(Theme.accent)
                VStack(alignment: .leading, spacing: 4) {
                    Text(asset?.displayName ?? "原稿").font(.system(size: 14, weight: .semibold)).lineLimit(1).truncationMode(.middle)
                    Text(asset?.detail ?? "文件不可用").font(.system(size: 10)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                if asset?.document != nil, canPreviewOriginal {
                    Picker("预览内容", selection: Binding(get: { selectedMode }, set: { mode = $0 })) { Text("原件").tag("original"); Text("提取内容").tag("text") }.pickerStyle(.segmented).frame(width: 150).labelsHidden()
                }
                if let url = model.assetURL(id) {
                    QuietIconButton(icon: "folder", label: "在访达中显示原件") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                }
                QuietIconButton(icon: "xmark", label: "关闭原稿预览") { model.selectedSourceID = nil }
            }.padding(20)
            Divider()
            if let asset, let url = model.assetURL(id) {
                if selectedMode == "text", let document = asset.document {
                    ScrollView { SourceDocumentContent(document: document).padding(24) }
                } else if asset.isImage {
                    ZoomableSourceImage(url: url, revision: asset.digest).frame(maxWidth: .infinity, maxHeight: .infinity)
                } else { SourceQuickLook(url: url).frame(maxWidth: .infinity, maxHeight: .infinity) }
                if let notice = asset.document?.notice {
                    Divider()
                    Label(notice, systemImage: "info.circle").font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1).help(notice).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 20).padding(.vertical, 12)
                }
            } else { ContentUnavailableView("原稿暂不可用", systemImage: "doc.questionmark", description: Text("请检查文件是否仍保存在资料库中。")) }
        }.frame(width: min(830, (NSScreen.main?.visibleFrame.width ?? 1000) - 80), height: min(680, (NSScreen.main?.visibleFrame.height ?? 800) - 90))
            .background(Theme.panel)
    }
}

struct SourceDocumentContent: View {
    let document: SourceDocument
    var fontSize: CGFloat = 13
    @State private var slices: [SourceReadingSlice] = []
    var body: some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(slices) { slice in
                VStack(alignment: .leading, spacing: 10) {
                    if !slice.title.isEmpty {
                        Text(slice.title).font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.accent)
                    }
                    Text(slice.text)
                        .font(.system(size: fontSize, design: ["Markdown", "XLSX", "CSV", "TSV"].contains(document.format) ? .monospaced : .default))
                        .textSelection(.enabled).lineSpacing(5).frame(maxWidth: .infinity, alignment: .leading)
                }.padding(.top, slice.startsSection && slice.id > 0 ? 24 : 0)
            }
        }.task(id: document) {
            let source = document
            let result = try? await ImagePipeline.offMain { try SourceReadingSlice.make(source) }
            guard !Task.isCancelled else { return }
            slices = result ?? []
        }
    }
}

struct SourceQuickLook: NSViewRepresentable {
    let url: URL
    func makeNSView(context: Context) -> QLPreviewView { let view = QLPreviewView(frame: .zero, style: .normal)!; view.autostarts = true; view.previewItem = url as NSURL; return view }
    func updateNSView(_ view: QLPreviewView, context: Context) { if (view.previewItem as? NSURL) != url as NSURL { view.previewItem = url as NSURL } }
    static func dismantleNSView(_ view: QLPreviewView, coordinator: ()) { view.previewItem = nil; view.close() }
}
