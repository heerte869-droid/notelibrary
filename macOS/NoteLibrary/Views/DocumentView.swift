import SwiftUI
import WebKit
import AppKit
import UniformTypeIdentifiers

@MainActor final class DocumentWebState: ObservableObject {
    @Published var ready = false
    @Published var failure: String?
    weak var webView: WKWebView?
    func exportPDF(title: String) {
        guard ready, let webView else { return }
        let panel = NSSavePanel(); panel.allowedContentTypes = [.pdf]; panel.nameFieldStringValue = title + ".pdf"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let info = NSPrintInfo.shared.copy() as! NSPrintInfo
        info.topMargin = 42; info.bottomMargin = 42; info.leftMargin = 42; info.rightMargin = 42
        info.horizontalPagination = .fit; info.jobDisposition = .save
        info.dictionary()[NSPrintInfo.AttributeKey.jobSavingURL] = url
        let operation = webView.printOperation(with: info)
        operation.showsPrintPanel = false; operation.showsProgressPanel = false
        if !operation.run() { failure = "PDF 没有完成保存，请重试。" }
    }
    func printDocument() {
        guard ready, let webView else { return }
        let info = NSPrintInfo.shared.copy() as! NSPrintInfo
        info.topMargin = 42; info.bottomMargin = 42; info.leftMargin = 42; info.rightMargin = 42
        info.horizontalPagination = .fit
        let operation = webView.printOperation(with: info)
        operation.showsPrintPanel = true; operation.showsProgressPanel = true; operation.run()
    }
}

struct FormulaView: View {
    let formula: String
    let fontSize: Double
    @Environment(\.colorScheme) var colorScheme
    @State private var height: CGFloat = 70
    @StateObject private var state = DocumentWebState()
    var body: some View {
        LocalDocumentWebView(html: NoteHTML.formula(formula, size: fontSize, dark: colorScheme == .dark), height: $height, state: state)
            .frame(height: height).clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(alignment: .topTrailing) { QuietIconButton(icon: "doc.on.doc", label: "复制公式 LaTeX") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(formula, forType: .string) }.padding(3) }
            .accessibilityLabel("公式：" + formula)
    }
}

struct LocalDocumentWebView: NSViewRepresentable {
    let html: String
    var height: Binding<CGFloat>? = nil
    @ObservedObject var state: DocumentWebState
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        config.setURLSchemeHandler(MathAssets(), forURLScheme: "notelibrary-math")
        config.userContentController.add(context.coordinator, name: "layout")
        let view = WKWebView(frame: .zero, configuration: config)
        view.setValue(false, forKey: "drawsBackground")
        view.navigationDelegate = context.coordinator
        state.webView = view
        if height != nil { context.coordinator.installScrollRouting(view) }
        return view
    }
    func updateNSView(_ view: WKWebView, context: Context) {
        context.coordinator.parent = self
        guard context.coordinator.lastHTML != html else { return }
        context.coordinator.lastHTML = html
        DispatchQueue.main.async { state.ready = false }
        view.loadHTMLString(html, baseURL: URL(string: "notelibrary-math://bundle/"))
    }
    static func dismantleNSView(_ view: WKWebView, coordinator: Coordinator) { coordinator.removeScrollRouting(); view.configuration.userContentController.removeScriptMessageHandler(forName: "layout"); view.navigationDelegate = nil }
    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        var parent: LocalDocumentWebView
        var lastHTML = ""
        private var wheelMonitor: Any?
        private var verticalGesture = false
        func installScrollRouting(_ view: WKWebView) {
            wheelMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self, weak view] event in
                guard let self, let view, event.window === view.window, view.window != nil,
                      !view.isHiddenOrHasHiddenAncestor, view.visibleRect.contains(view.convert(event.locationInWindow, from: nil)),
                      let hit = view.window?.contentView?.hitTest(event.locationInWindow), hit === view || hit.isDescendant(of: view),
                      let outer = view.enclosingScrollView else { return event }
                let ended = event.phase.contains(.ended) || event.phase.contains(.cancelled) || event.momentumPhase.contains(.ended)
                let vertical = InlineScrollPolicy.forwardVertical(x: event.scrollingDeltaX, y: event.scrollingDeltaY, shift: event.modifierFlags.contains(.shift))
                guard vertical || (self.verticalGesture && ended) else { return event }
                self.verticalGesture = !ended
                outer.scrollWheel(with: event)
                return nil
            }
        }
        func removeScrollRouting() { if let wheelMonitor { NSEvent.removeMonitor(wheelMonitor) }; wheelMonitor = nil }
        deinit { if let wheelMonitor { NSEvent.removeMonitor(wheelMonitor) } }
        init(_ parent: LocalDocumentWebView) { self.parent = parent }
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let size = message.body as? Double, size.isFinite else { return }
            DispatchQueue.main.async { self.parent.height?.wrappedValue = max(50, min(1600, ceil(size))); self.parent.state.ready = true }
        }
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            let scheme = navigationAction.request.url?.scheme ?? ""
            decisionHandler(["about", "notelibrary-math"].contains(scheme) ? .allow : .cancel)
        }
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { parent.state.failure = "排版暂时无法显示：" + error.localizedDescription }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { parent.state.failure = "排版暂时无法显示：" + error.localizedDescription }
    }
}

final class MathAssets: NSObject, WKURLSchemeHandler {
    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        guard let url = urlSchemeTask.request.url, let base = Bundle.main.resourceURL?.appendingPathComponent("KaTeX"), !url.path.contains("..") else { urlSchemeTask.didFailWithError(URLError(.badURL)); return }
        let path = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let file = base.appendingPathComponent(path)
        guard ["js", "css", "woff2"].contains(file.pathExtension), let data = try? Data(contentsOf: file) else { urlSchemeTask.didFailWithError(URLError(.fileDoesNotExist)); return }
        let type = file.pathExtension == "js" ? "application/javascript" : file.pathExtension == "css" ? "text/css" : "font/woff2"
        urlSchemeTask.didReceive(URLResponse(url: url, mimeType: type, expectedContentLength: data.count, textEncodingName: file.pathExtension == "woff2" ? nil : "utf-8"))
        urlSchemeTask.didReceive(data); urlSchemeTask.didFinish()
    }
    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {}
}

@MainActor enum NoteHTML {
    static func escape(_ text: String) -> String { text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;") }
    static func paragraphs(_ text: String) -> String { escape(text).replacingOccurrences(of: "\n", with: "<br>") }
    static func shell(body: String, css: String) -> String {
        """
        <!doctype html><html lang="zh-CN"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><meta http-equiv="Content-Security-Policy" content="default-src 'none'; script-src 'unsafe-inline' notelibrary-math:; style-src 'unsafe-inline' notelibrary-math:; font-src notelibrary-math:; img-src data:"><link rel="stylesheet" href="notelibrary-math://bundle/katex.min.css"><style>*{box-sizing:border-box}body{margin:0;font-family:-apple-system,BlinkMacSystemFont,sans-serif;line-height:1.8;color:#1c2724}img{max-width:100%}.math{overflow-x:auto;overflow-y:hidden}table{width:100%;border-collapse:collapse;font-size:13px}td,th{padding:10px;border:1px solid #dde4e1;text-align:left}th{background:#eef4f1}h1,h2,h3{line-height:1.4}h1{font-size:28px}h2{font-size:21px;margin:36px 0 14px}h3{font-size:17px}section,figure{margin:22px 0}figure{page-break-inside:avoid}.term{border-left:3px solid #347d6c;padding:8px 18px;background:#f4f8f6}.muted{color:#66736d;font-size:11px}.source{font-size:11px;overflow-wrap:anywhere}\(css)</style><script src="notelibrary-math://bundle/katex.min.js"></script></head><body>\(body)<script>document.querySelectorAll('.math').forEach(el=>{let value=el.textContent;try{katex.render(value,el,{displayMode:true,throwOnError:false,trust:false,strict:'warn',maxExpand:1000});}catch(e){el.textContent=value;}});const fitMath=()=>document.querySelectorAll('.fit-math').forEach(el=>{const base=Number(el.dataset.size);el.style.fontSize=base+'px';const ratio=el.clientWidth/Math.max(el.scrollWidth,1);if(ratio<1)el.style.fontSize=Math.max(12,base*ratio)+'px';});new ResizeObserver(fitMath).observe(document.documentElement);document.fonts.ready.then(fitMath);const report=()=>window.webkit.messageHandlers.layout.postMessage(document.body.scrollHeight);document.fonts.ready.then(report);new ResizeObserver(report).observe(document.body);window.addEventListener('load',report);</script></body></html>
        """
    }
    static func formula(_ formula: String, size: Double, dark: Bool) -> String {
        shell(body: "<div class='math fit-math' data-size='\(size)'>\(escape(formula))</div>", css: "body{font-size:\(size)px;padding:14px 42px 14px 18px;color:\(dark ? "#eeeeee" : "#24322c");background:\(dark ? "#272c2a" : "#f3f5f4")} .katex-display{margin:8px 0}")
    }
    static func document(_ note: Note, model: AppModel) -> String {
        var body = "<main><div class='muted'>\(escape(model.location(note)))</div><h1>\(escape(note.title))</h1>"
        for block in note.blocks {
            let text = paragraphs(block.text), detail = paragraphs(block.detail)
            switch block.kind {
            case .heading: body += "<h2>\(text)</h2>" + (detail.isEmpty ? "" : "<p>\(detail)</p>")
            case .bullet: body += "<ul><li>\(text)" + (detail.isEmpty ? "" : "<p>\(detail)</p>") + "</li></ul>"
            case .term, .callout: body += "<section class='term'><h3>\(text)</h3><div>\(detail)</div></section>"
            case .formula: body += "<section><div class='math'>\(escape(block.text))</div><p>\(detail)</p></section>"
            case .table:
                body += "<section><h3>\(text)</h3><table>"
                for (i,row) in block.rows.enumerated() { let tag = i == 0 ? "th" : "td"; body += "<tr>" + row.map { "<\(tag)>\(paragraphs($0))</\(tag)>" }.joined() + "</tr>" }
                body += "</table>" + (detail.isEmpty ? "" : "<p>\(detail)</p>") + "</section>"
            case .diagram:
                if let diagram = block.diagram { body += "<figure><h3>\(text)</h3>" + diagram.svg(title: block.text) + "<figcaption>\(detail)</figcaption></figure>" }
            case .image:
                if let id = block.assetID, let image = model.image(id), let data = image.tiffRepresentation, let rep = NSBitmapImageRep(data: data), let png = rep.representation(using: .png, properties: [:]) { body += "<figure><img alt='\(escape(block.text))' src='data:image/png;base64,\(png.base64EncodedString())'><figcaption class='muted'>\(text)</figcaption><p>\(detail)</p></figure>" }
            default: body += "<section>\(text)\(detail.isEmpty ? "" : "<p>" + detail + "</p>")</section>"
            }
            let references = block.citations.filter { model.asset($0) == nil }
            if !references.isEmpty { body += "<div class='source'>" + references.map(escape).joined(separator: "<br>") + "</div>" }
        }
        if !note.sourceIDs.isEmpty { body += "<hr><div class='muted'>原稿：" + note.sourceIDs.compactMap { model.asset($0)?.displayName }.map(escape).joined(separator: "、") + "</div>" }
        body += "</main>"
        return shell(body: body, css: "body{background:white}svg{width:100%;height:auto}main{max-width:760px;margin:auto;padding:44px;font-size:15px}@media print{main{padding:0;max-width:none}thead{display:table-header-group}tr{page-break-inside:avoid}h1,h2,h3{page-break-after:avoid}.term{page-break-inside:avoid}}")
    }
}

// Horizontal gestures remain inside wide formulas; vertical ones belong to the note.
enum InlineScrollPolicy {
    static func forwardVertical(x: CGFloat, y: CGFloat, shift: Bool) -> Bool { !shift && abs(y) > abs(x) && y != 0 }
}
