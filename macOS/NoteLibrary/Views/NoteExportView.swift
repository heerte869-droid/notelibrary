import SwiftUI
import AppKit
import WebKit
import PDFKit

struct RenderedNoteExport {
    let pdf: Data
    let html: String
    let mathML: [String: String]
    let pageCount: Int
}

@MainActor final class NoteExportRenderer: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
    private var browser: WKWebView?
    private var ready: CheckedContinuation<Void, Error>?
    private var watchdog: Task<Void, Never>?
    func render(_ content: NoteExportContent, options: NoteExportOptions) async throws -> RenderedNoteExport {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.setURLSchemeHandler(MathAssets(), forURLScheme: "notelibrary-math")
        configuration.userContentController.add(self, name: "exportReady")
        let width = (options.paper.size.width - 96) * 4 / 3 + 56
        let web = WKWebView(frame: NSRect(x: 0, y: 0, width: width, height: 960), configuration: configuration)
        browser = web; web.navigationDelegate = self
        // Keep layout in a private, never-shown window; the export sheet stays responsive.
        let host = NSWindow(contentRect: web.frame, styleMask: .borderless, backing: .buffered, defer: false)
        host.isReleasedWhenClosed = false; host.contentView = web
        defer {
            watchdog?.cancel(); watchdog = nil
            web.configuration.userContentController.removeScriptMessageHandler(forName: "exportReady")
            web.navigationDelegate = nil; web.stopLoading(); host.contentView = nil; host.close(); browser = nil
        }
        try await withCheckedThrowingContinuation { continuation in
            ready = continuation
            web.loadHTMLString(NoteExportHTML.document(content, options: options), baseURL: URL(string: "notelibrary-math://bundle/"))
            watchdog = Task { [weak self] in
                try? await Task.sleep(for: .seconds(30))
                if !Task.isCancelled { self?.finish(AppFailure(message: "排版等待超时，请重试。")) }
            }
        }
        try Task.checkCancellation()
        let result = try await web.evaluateJavaScript("({html:document.documentElement.outerHTML, math:Array.from(document.querySelectorAll('.formula')).map(el=>({id:el.dataset.block,xml:el.querySelector('math').outerHTML}))})") as? [String: Any]
        guard let html = result?["html"] as? String, let math = result?["math"] as? [[String: String]], let resources = Bundle.main.resourceURL?.appendingPathComponent("KaTeX") else { throw AppFailure(message: "无法准备导出内容。") }
        let formulas = Dictionary(uniqueKeysWithValues: math.compactMap { row -> (String, String)? in guard let id = row["id"], let xml = row["xml"] else { return nil }; return (id, xml) })
        let portable = try await Task.detached(priority: .userInitiated) { try NoteExportHTML.portable(renderedHTML: html, resources: resources) }.value
        try Task.checkCancellation()
        guard let scriptURL = Bundle.main.resourceURL?.appendingPathComponent("ExportLayout/paginate.js") else { throw AppFailure(message: "分页组件不可用。") }
        let script = try String(contentsOf: scriptURL, encoding: .utf8)
        _ = try await web.evaluateJavaScript(script + ";null;")
        web.setFrameSize(CGSize(width: options.paper.size.width * 4 / 3, height: 1060))
        let rawPages: Any = try await withCheckedThrowingContinuation { continuation in
            web.callAsyncJavaScript("return await window.NoteExportPaginate(html,width,height,numbers);", arguments: ["html": portable, "width": options.paper.size.width * 4 / 3, "height": options.paper.size.height * 4 / 3, "numbers": options.pageNumbers], in: nil, in: .page) { continuation.resume(with: $0) }
        }
        let rectangles = (rawPages as? String).flatMap { $0.data(using: .utf8) }.flatMap { try? JSONDecoder().decode([[String: Double]].self, from: $0) }
        guard let rectangles, !rectangles.isEmpty, rectangles.count <= 400 else { throw AppFailure(message: "分页未完成，或笔记超过 400 页；请分篇导出。") }
        let output = NSMutableData()
        var media = CGRect(origin: .zero, size: options.paper.size)
        guard let consumer = CGDataConsumer(data: output as CFMutableData), let context = CGContext(consumer: consumer, mediaBox: &media, nil) else { throw AppFailure(message: "无法创建 PDF 页面。") }
        var links: [(Int, CGRect, URL)] = []
        for (index, rect) in rectangles.enumerated() {
            try Task.checkCancellation()
            guard let x = rect["x"], let y = rect["y"], let w = rect["width"], let h = rect["height"], w > 0, h > 0 else { throw AppFailure(message: "分页尺寸无效。") }
            let configuration = WKPDFConfiguration(); configuration.rect = CGRect(x: x, y: y, width: w, height: h)
            let bytes: Data = try await withCheckedThrowingContinuation { continuation in web.createPDF(configuration: configuration) { continuation.resume(with: $0) } }
            guard let single = PDFDocument(data: bytes), single.pageCount == 1, let page = single.page(at: 0), let reference = page.pageRef else { throw AppFailure(message: "PDF 页面生成失败。") }
            context.beginPDFPage(nil)
            context.saveGState(); context.concatenate(reference.getDrawingTransform(.mediaBox, rect: media, rotate: 0, preserveAspectRatio: false)); context.drawPDFPage(reference); context.restoreGState(); context.endPDFPage()
            let bounds = page.bounds(for: .mediaBox), sx = media.width / bounds.width, sy = media.height / bounds.height
            for annotation in page.annotations {
                if let url = annotation.url ?? (annotation.action as? PDFActionURL)?.url {
                    let a = annotation.bounds
                    links.append((index, CGRect(x: (a.minX-bounds.minX)*sx, y: (a.minY-bounds.minY)*sy, width: a.width*sx, height: a.height*sy), url))
                }
            }
        }
        context.closePDF()
        guard let document = PDFDocument(data: output as Data) else { throw AppFailure(message: "PDF 无法完成封装。") }
        document.documentAttributes = [PDFDocumentAttribute.titleAttribute: content.note.title, PDFDocumentAttribute.creatorAttribute: "NoteLibrary"]
        for (index, rect, url) in links { let annotation = PDFAnnotation(bounds: rect, forType: .link, withProperties: nil); annotation.url = url; document.page(at: index)?.addAnnotation(annotation) }
        guard let data = document.dataRepresentation() else { throw AppFailure(message: "PDF 无法保存。") }
        return .init(pdf: data, html: portable, mathML: formulas, pageCount: rectangles.count)
    }
    func cancel() { browser?.stopLoading(); browser?.loadHTMLString("", baseURL: nil); finish(CancellationError()) }
    private func finish(_ error: Error? = nil) {
        guard let continuation = ready else { return }; ready = nil; watchdog?.cancel()
        if let error { continuation.resume(throwing: error) } else { continuation.resume() }
    }
    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let value = message.body as? [String: Any] else { return }
        if let error = value["error"] as? String { finish(AppFailure(message: error)) }
        else if value["ready"] as? Bool == true { finish() }
    }
    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        decisionHandler(["about", "notelibrary-math"].contains(action.request.url?.scheme ?? "") ? .allow : .cancel)
    }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { finish(error) }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { finish(error) }
}

@MainActor final class NoteExportState: ObservableObject {
    @Published var content: NoteExportContent?
    @Published var rendered: RenderedNoteExport?
    @Published var busy = true
    @Published var saving = false
    @Published var failure: String?
    @Published var savedURL: URL?
    private var renderer: NoteExportRenderer?
    private var generation = UUID()
    var ready: Bool { rendered != nil && !busy && !saving }
    func prepare(note: Note, model: AppModel, options: NoteExportOptions) async {
        let token = UUID(); generation = token
        busy = true; failure = nil; savedURL = nil
        do {
            try await Task.sleep(for: .milliseconds(120))
            try Task.checkCancellation()
            if content == nil {
                var diagrams: [String: ExportImage] = [:]
                for block in note.blocks where block.kind == .diagram {
                    guard let diagram = block.diagram else { throw AppFailure(message: "图示“\(block.text)”缺少数据。") }
                    try diagram.validate()
                    let image = ImageRenderer(content: StudyDiagramView(diagram: diagram).environment(\.colorScheme, .light).frame(width: StudyDiagram.width, height: StudyDiagram.height))
                    image.scale = 3
                    guard let cg = image.cgImage else { throw AppFailure(message: "图示无法绘制。") }
                    let rep = NSBitmapImageRep(cgImage: cg)
                    guard let png = rep.representation(using: .png, properties: [:]) else { throw AppFailure(message: "图示无法编码。") }
                    diagrams[block.id] = ExportImage(data: png, width: cg.width, height: cg.height)
                }
                let sources = Dictionary(uniqueKeysWithValues: model.library.assets.map { ($0.id, $0.displayName) })
                let urls = Dictionary(uniqueKeysWithValues: model.library.assets.compactMap { asset -> (String, URL)? in model.assetURL(asset.id).map { (asset.id, $0) } })
                let location = model.location(note), preparedDiagrams = diagrams
                let prepared = try await Task.detached(priority: .userInitiated) { try NoteExportContent.prepare(note: note, location: location, sourceNames: sources, assetURLs: urls, diagrams: preparedDiagrams) }.value
                try Task.checkCancellation(); guard generation == token else { return }; content = prepared
            }
            guard let content else { return }
            let current = NoteExportRenderer(); renderer = current
            let output = try await current.render(content, options: options)
            try Task.checkCancellation(); guard generation == token else { return }
            rendered = output; busy = false; renderer = nil
        } catch is CancellationError { if generation == token { busy = false } }
        catch { if generation == token { failure = error.localizedDescription; busy = false; rendered = nil } }
    }
    func cancel() { generation = UUID(); renderer?.cancel(); renderer = nil; busy = false }
    func save(format: NoteExportFormat, options: NoteExportOptions, window: NSWindow?) async {
        guard ready, let content, let rendered else { return }
        saving = true; failure = nil
        defer { saving = false }
        let panel = NSSavePanel(); panel.allowedContentTypes = [format.contentType]
        panel.nameFieldStringValue = NoteExportContent.safeFilename(content.note.title) + "." + format.suffix
        panel.canCreateDirectories = true; panel.title = "导出 " + format.title; panel.prompt = "导出"
        let response: NSApplication.ModalResponse = await withCheckedContinuation { continuation in
            if let window { panel.beginSheetModal(for: window) { continuation.resume(returning: $0) } }
            else { panel.begin { continuation.resume(returning: $0) } }
        }
        guard response == .OK, let url = panel.url else { return }
        saving = true; failure = nil; savedURL = nil
        do {
            try await Task.detached(priority: .userInitiated) {
                switch format {
                case .pdf: try rendered.pdf.write(to: url, options: .atomic)
                case .html: try rendered.html.write(to: url, atomically: true, encoding: .utf8)
                case .markdown: try NoteExportMarkdown.write(content, options: options, to: url)
                case .word:
                    var document = WordNoteExport(content: content, options: options, mathML: rendered.mathML)
                    try document.data().write(to: url, options: .atomic)
                }
            }.value
            savedURL = url
        } catch { failure = "导出未完成：" + error.localizedDescription }
        saving = false
    }
}

struct NoteExportView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduced
    let note: Note
    @StateObject private var state = NoteExportState()
    @State private var format: NoteExportFormat = .pdf
    @State private var options = NoteExportOptions()
    @State private var revision = 0
    @State private var window: NSWindow?
    private var taskID: String { "\(options.paper.rawValue)-\(options.includeSources)-\(options.pageNumbers)-\(revision)" }
    private var paginated: Bool { format == .pdf || format == .word }
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("导出笔记").font(.system(size: 21, weight: .semibold))
                    Text(note.title).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1).help(note.title)
                }
                Spacer()
                QuietIconButton(icon: "xmark", label: "关闭导出") { state.cancel(); dismiss() }.keyboardShortcut(.cancelAction).disabled(state.saving)
            }.padding(.horizontal, 24).padding(.vertical, 19)
            Rectangle().fill(Theme.border).frame(height: 1)
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(spacing: 5) { ForEach(NoteExportFormat.allCases) { item in formatButton(item) } }
                    Rectangle().fill(Theme.border).frame(height: 1).padding(.horizontal, 4)
                    VStack(alignment: .leading, spacing: 16) {
                        if paginated {
                            HStack {
                                Text("纸张").font(.system(size: 11)).foregroundStyle(.secondary)
                                Spacer()
                                ChoicePicker(title: "导出纸张", selection: options.paper.rawValue, options: ExportPaper.allCases.map { ChoiceOption(id: $0.rawValue, title: $0.title) }) { if let paper = ExportPaper(rawValue: $0) { options.paper = paper } }
                            }
                            check("显示页码", value: $options.pageNumbers)
                        }
                        check("附上来源", value: $options.includeSources)
                    }.padding(.horizontal, 5).disabled(state.busy || state.saving)
                    Spacer(minLength: 0)
                }.padding(16).frame(width: 208).background(Theme.background.opacity(0.55))
                Rectangle().fill(Theme.border).frame(width: 1)
                VStack(spacing: 0) {
                    HStack {
                        Text(format == .markdown ? "Markdown 内容" : format == .word ? "内容预览" : "导出预览").font(.system(size: 12, weight: .medium))
                        Spacer()
                        if let rendered = state.rendered, paginated { Text("\(rendered.pageCount) 页预览").font(.system(size: 10)).foregroundStyle(.secondary).monospacedDigit() }
                    }.padding(.horizontal, 20).frame(height: 42)
                    ZStack {
                        if let rendered = state.rendered {
                            if paginated { ExportPDFPreview(data: rendered.pdf) }
                            else if format == .html { ExportHTMLPreview(html: rendered.html) }
                            else if let content = state.content {
                                ScrollView { Text(NoteExportMarkdown.package(content, options: options, folder: "笔记-assets").text).font(.system(size: 12, design: .monospaced)).lineSpacing(5).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding(24) }.background(Theme.panel)
                            }
                        } else { Theme.background }
                        if state.busy {
                            Theme.panel.opacity(0.8)
                            VStack(spacing: 12) { ProgressView().controlSize(.small); Text("正在准备排版…").font(.system(size: 12)).foregroundStyle(.secondary) }
                        } else if state.rendered == nil, let failure = state.failure {
                            VStack(spacing: 16) { Image(systemName: "doc.badge.ellipsis").font(.system(size: 27)).foregroundStyle(.secondary); Text(failure).font(.system(size: 12)).multilineTextAlignment(.center); ActionButton(title: "重新准备", icon: "arrow.clockwise") { revision += 1 } }.padding(36)
                        }
                    }.frame(maxWidth: .infinity, maxHeight: .infinity).clipped()
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
            Rectangle().fill(Theme.border).frame(height: 1)
            HStack(spacing: 14) {
                if state.saving { ProgressView().controlSize(.small); Text("正在保存…").font(.system(size: 11)).foregroundStyle(.secondary) }
                else if let url = state.savedURL {
                    Label("已导出", systemImage: "checkmark.circle.fill").font(.system(size: 11)).foregroundStyle(Theme.accent)
                    Button("在 Finder 中显示") { NSWorkspace.shared.activateFileViewerSelecting([url]) }.font(.system(size: 11)).buttonStyle(FeedbackStyle(compact: true))
                } else {
                    Text(state.failure ?? format.explanation).font(.system(size: 11)).foregroundStyle(state.failure == nil ? Color.secondary : .red).lineLimit(2)
                        .help(format == .word ? "预览展示内容与版式；Word 的分页会随字体和软件略有变化。" : format.explanation)
                }
                Spacer(minLength: 10)
                ActionButton(title: "导出 " + format.title + "…", icon: "square.and.arrow.up", primary: true) { Task { await state.save(format: format, options: options, window: window) } }.disabled(!state.ready).keyboardShortcut(.defaultAction).accessibilityIdentifier("export-save")
            }.padding(.horizontal, 24).frame(height: 66)
        }.frame(width: min(920, (NSScreen.main?.visibleFrame.width ?? 1200) - 90), height: min(710, (NSScreen.main?.visibleFrame.height ?? 900) - 110))
            .background(Theme.panel).background(ExportWindowReader { window = $0 })
            .task(id: taskID) { await state.prepare(note: note, model: model, options: options) }
            .onDisappear { state.cancel() }.interactiveDismissDisabled(state.saving)
    }
    private func formatButton(_ item: NoteExportFormat) -> some View {
        Button {
            withAnimation(reduced || model.library.settings.reduceMotion ? nil : .easeOut(duration: 0.13)) { format = item }
            state.savedURL = nil; if state.rendered != nil { state.failure = nil }
        } label: {
            HStack(spacing: 11) {
                Image(systemName: item.icon).font(.system(size: 19, weight: .regular)).frame(width: 26)
                VStack(alignment: .leading, spacing: 4) { Text(item.title).font(.system(size: 13, weight: .semibold)); Text(item.caption).font(.system(size: 10)).foregroundStyle(.secondary) }
                Spacer(minLength: 0)
                if format == item { Image(systemName: "checkmark").font(.system(size: 10, weight: .semibold)) }
            }.foregroundStyle(format == item ? Theme.accent : .primary).padding(.horizontal, 12).frame(height: 62).contentShape(Rectangle())
        }.buttonStyle(FeedbackStyle(selected: format == item)).disabled(state.saving).accessibilityIdentifier("export-format-" + item.rawValue).accessibilityAddTraits(format == item ? .isSelected : [])
    }
    private func check(_ title: String, value: Binding<Bool>) -> some View {
        Button { value.wrappedValue.toggle() } label: {
            HStack(spacing: 8) { Image(systemName: value.wrappedValue ? "checkmark.square.fill" : "square").font(.system(size: 14)).foregroundStyle(value.wrappedValue ? Theme.accent : .secondary); Text(title).font(.system(size: 11)); Spacer() }.frame(height: 26).contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityLabel(title).accessibilityValue(value.wrappedValue ? "已开启" : "已关闭")
    }
}

private struct ExportWindowReader: NSViewRepresentable {
    var found: (NSWindow?) -> Void
    func makeNSView(context: Context) -> WindowView { let view = WindowView(); view.found = found; return view }
    func updateNSView(_ view: WindowView, context: Context) { view.found = found }
    final class WindowView: NSView {
        var found: (NSWindow?) -> Void = { _ in }
        override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); DispatchQueue.main.async { self.found(self.window) } }
    }
}
private struct ExportPDFPreview: NSViewRepresentable {
    let data: Data
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> PDFView {
        let view = PDFView(); view.autoScales = true; view.displayMode = .singlePageContinuous; view.displayDirection = .vertical
        view.backgroundColor = NSColor.windowBackgroundColor; view.displaysPageBreaks = true; view.pageBreakMargins = NSEdgeInsets(top: 14, left: 16, bottom: 14, right: 16)
        return view
    }
    func updateNSView(_ view: PDFView, context: Context) {
        guard context.coordinator.data != data else { return }; context.coordinator.data = data
        view.document = PDFDocument(data: data); view.autoScales = true
    }
    final class Coordinator { var data: Data? }
}
private struct ExportHTMLPreview: NSViewRepresentable {
    let html: String
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration(); config.websiteDataStore = .nonPersistent(); config.defaultWebpagePreferences.allowsContentJavaScript = false
        let view = WKWebView(frame: .zero, configuration: config); view.navigationDelegate = context.coordinator; return view
    }
    func updateNSView(_ view: WKWebView, context: Context) { if context.coordinator.html != html { context.coordinator.html = html; view.loadHTMLString(html, baseURL: nil) } }
    final class Coordinator: NSObject, WKNavigationDelegate {
        var html = ""
        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) { decisionHandler(action.request.url?.scheme == "about" ? .allow : .cancel) }
    }
}
