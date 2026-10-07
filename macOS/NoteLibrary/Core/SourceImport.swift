import Foundation
import AppKit
import PDFKit
import Vision
import UniformTypeIdentifiers
import ImageIO
import CryptoKit

final class SourceImportControl: @unchecked Sendable {
    private let lock = NSLock()
    private var request: VNRequest?
    private var cancelled = false
    private var progressText: String?
    var progress: String? { lock.lock(); defer { lock.unlock() }; return progressText }
    func report(_ value: String?) { lock.lock(); if !cancelled { progressText = value }; lock.unlock() }
    func checkCancellation() throws {
        try Task.checkCancellation()
        lock.lock(); let stopped = cancelled; lock.unlock()
        if stopped { throw CancellationError() }
    }
    func register(_ request: VNRequest?) throws {
        lock.lock(); let stopped = cancelled; self.request = request; lock.unlock()
        if stopped { request?.cancel(); throw CancellationError() }
    }
    func cancel() { lock.lock(); cancelled = true; let active = request; lock.unlock(); active?.cancel() }
}

struct SourceSection: Codable, Equatable { var title: String; var text: String }
struct SourceDocument: Codable, Equatable {
    var format: String
    var sections: [SourceSection]
    var pageCount: Int? = nil
    var usedOCR = false
    var notice: String? = nil
    var extractionVersion: Int? = nil
    var text: String { sections.map { ($0.title.isEmpty ? "" : "## " + $0.title + "\n") + $0.text }.joined(separator: "\n\n") }
}

extension SourceAsset {
    var isImage: Bool { document == nil && SourceImport.imageExtensions.contains((filename as NSString).pathExtension.lowercased()) }
    var formatLabel: String { document?.format ?? (filename as NSString).pathExtension.uppercased() }
    var icon: String {
        switch (filename as NSString).pathExtension.lowercased() {
        case "pdf": return "doc.richtext"
        case "ppt", "pptx": return "rectangle.on.rectangle"
        case "xlsx", "csv", "tsv": return "tablecells"
        case "md", "markdown": return "text.alignleft"
        default: return isImage ? "photo" : "doc.text"
        }
    }
    var detail: String {
        var parts = [formatLabel]
        if let count = document?.pageCount { parts.append("\(count) 页") }
        if let byteCount { parts.append(ByteCountFormatter.string(fromByteCount: Int64(byteCount), countStyle: .file)) }
        return parts.joined(separator: " · ")
    }
}

enum SourceImport {
    static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "heic", "heif", "webp", "tif", "tiff", "gif", "bmp"]
    static let documentExtensions = ["pdf", "docx", "doc", "pptx", "ppt", "md", "markdown", "txt", "rtf", "csv", "tsv", "xlsx", "odt", "html", "htm"]
    static let extractionVersion = 2
    static let maxCharacters = 120_000
    static let maxRequestCharacters = 180_000
    static let supportedDescription = "图片、PDF、Word、PowerPoint、Markdown、文本与表格"
    static var contentTypes: [UTType] { [.image] + documentExtensions.compactMap { UTType(filenameExtension: $0) } }
    static func validateContext(_ sources: [SourceAsset]) throws {
        guard sources.reduce(0, { $0 + ($1.document?.text.count ?? 0) }) <= maxRequestCharacters else { throw failure("本轮原稿正文较多（超过 18 万字）。请分批整理，或在上下文中关闭历史附件后重试。") }
    }
    static func failure(_ message: String) -> AppFailure { AppFailure(message: message) }
    static func clean(_ text: String) -> String { text.replacingOccurrences(of: "\u{0}", with: "").replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n").trimmingCharacters(in: .whitespacesAndNewlines) }
    static func read(_ url: URL, control: SourceImportControl? = nil) throws -> (Data, SourceDocument?) {
        try control?.checkCancellation()
        let data = try readData(url)
        return (data, try document(data, extension: url.pathExtension.lowercased(), control: control))
    }
    /// Read and hash before parsing so importing an existing original does not repeat OCR.
    static func readData(_ url: URL) throws -> Data {
        try Task.checkCancellation()
        let ext = url.pathExtension.lowercased()
        guard imageExtensions.contains(ext) || documentExtensions.contains(ext) else { throw failure("暂不支持 .\(ext.isEmpty ? "无扩展名" : ext) 文件。可导入\(supportedDescription)。") }
        let scoped = url.startAccessingSecurityScopedResource(); defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        let maximum = imageExtensions.contains(ext) ? 30_000_000 : 100_000_000
        guard values.isRegularFile == true, let size = values.fileSize, size > 0, size <= maximum else { throw failure(imageExtensions.contains(ext) ? "图片需为非空文件，单张不超过 30 MB。" : "文档需为非空文件，单份不超过 100 MB。") }
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        guard data.count <= maximum else { throw failure("文件读取时大小发生变化，请重新导入。") }
        try Task.checkCancellation()
        return data
    }
    static func actualExtension(_ data: Data, declared ext: String) -> String {
        data.starts(with: Data("%PDF-".utf8)) ? "pdf" : ext
    }
    static func document(_ data: Data, extension ext: String, control: SourceImportControl? = nil) throws -> SourceDocument? {
        try Task.checkCancellation(); try control?.checkCancellation()
        let ext = actualExtension(data, declared: ext)
        if imageExtensions.contains(ext) { guard ImagePipeline.isReadable(data) else { throw failure("图片无法读取，请确认文件完整。") }; return nil }
        return try parse(data, extension: ext, control: control)
    }
    static func parse(_ data: Data, extension ext: String, control: SourceImportControl? = nil) throws -> SourceDocument {
        try Task.checkCancellation(); try control?.checkCancellation()
        var document: SourceDocument
        switch ext {
        case "pdf": document = try pdf(data, control: control)
        case "pptx": document = try presentation(OfficeArchive(data), control: control)
        case "ppt": document = try LegacyPowerPoint.read(data)
        case "docx": document = try word(OfficeArchive(data), control: control)
        case "xlsx": document = try spreadsheet(OfficeArchive(data))
        case "doc", "rtf", "odt":
            let type: NSAttributedString.DocumentType = ext == "doc" ? .docFormat : ext == "rtf" ? .rtf : .openDocument
            let text: String
            do { text = try NSAttributedString(data: data, options: [.documentType: type], documentAttributes: nil).string }
            catch { throw failure("文档无法读取；请解除密码保护，或另存为 DOCX、PDF 后导入。") }
            document = SourceDocument(format: ext.uppercased(), sections: [SourceSection(title: "", text: clean(text))], notice: "已提取文字；内嵌图片与复杂公式请对照原件，或另存为 PDF 识别。")
        case "html", "htm":
            // Strip markup locally; do not load a web view, scripts, remote images, or stylesheets.
            let html = try decodeText(data)
            let stripped = html.replacingOccurrences(of: "(?is)<(script|style|head)\\b[^>]*>.*?</\\1\\s*>", with: "", options: .regularExpression)
                .replacingOccurrences(of: "(?i)</?(?:p|div|h[1-6]|br|li|tr|table|section)\\b[^>]*>", with: "\n", options: .regularExpression)
                .replacingOccurrences(of: "(?i)</t[dh]\\s*>", with: "\t", options: .regularExpression)
                .replacingOccurrences(of: "<[^>]*>", with: "", options: .regularExpression)
            document = SourceDocument(format: "HTML", sections: [SourceSection(title: "", text: clean(decodeHTMLEntities(stripped)))], notice: "已提取本地文字和表格；外部图片与网页样式未读取。")
        default: document = SourceDocument(format: ["md", "markdown"].contains(ext) ? "Markdown" : ext.uppercased(), sections: [SourceSection(title: "", text: clean(try decodeText(data)))])
        }
        try Task.checkCancellation(); try control?.checkCancellation()
        document.sections = document.sections.map { SourceSection(title: $0.title, text: clean($0.text)) }
        guard document.sections.contains(where: { !$0.text.isEmpty }) else { throw failure("没有读到可整理的文字。请检查原件，或将图文内容导出为 PDF 后重试。") }
        guard document.text.count <= maxCharacters else { throw failure("这份文档文字较多（超过 12 万字），请按章节拆分后导入。原文件未改动。") }
        document.extractionVersion = extractionVersion
        return document
    }
    static func decodeText(_ data: Data) throws -> String {
        var encodings: [String.Encoding] = [.utf8]
        if data.starts(with: [0xff, 0xfe]) { encodings = [.utf16LittleEndian] }
        else if data.starts(with: [0xfe, 0xff]) { encodings = [.utf16BigEndian] }
        else {
            let gb = CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue))
            encodings.append(String.Encoding(rawValue: gb))
        }
        for encoding in encodings {
            if let text = String(data: data, encoding: encoding), !text.unicodeScalars.contains(where: { $0.value == 0 || ($0.value < 32 && ![9, 10, 13].contains($0.value)) }) { return text.trimmingCharacters(in: CharacterSet(charactersIn: "\u{feff}")) }
        }
        throw failure("文字编码无法识别，请另存为 UTF-8 或 UTF-16 文本后导入。")
    }
    static func decodeHTMLEntities(_ text: String) -> String {
        let names = ["amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": " ",
                     "times": "×", "divide": "÷", "minus": "−", "plusmn": "±", "le": "≤", "ge": "≥", "ne": "≠", "deg": "°", "pi": "π", "alpha": "α", "beta": "β", "sup2": "²", "sup3": "³"]
        guard let pattern = try? NSRegularExpression(pattern: "&(#(?:[xX][0-9a-fA-F]+|[0-9]+)|[a-zA-Z][a-zA-Z0-9]*);") else { return text }
        var output = text
        for match in pattern.matches(in: text, range: NSRange(text.startIndex..., in: text)).reversed() {
            guard let valueRange = Range(match.range(at: 1), in: text), let range = Range(match.range, in: output) else { continue }
            let key = String(text[valueRange])
            var replacement = names[key]
            if key.hasPrefix("#") {
                let hex = key.lowercased().hasPrefix("#x")
                if let value = UInt32(key.dropFirst(hex ? 2 : 1), radix: hex ? 16 : 10), let scalar = UnicodeScalar(value), value >= 32 || [9, 10, 13].contains(value) { replacement = String(scalar) }
            }
            if let replacement { output.replaceSubrange(range, with: replacement) }
        }
        return output
    }
    static func recognize(_ image: CGImage, control: SourceImportControl? = nil) throws -> String {
        try Task.checkCancellation()
        let request = VNRecognizeTextRequest(); request.recognitionLevel = .accurate
        request.recognitionLanguages = ["zh-Hans", "en-US"]; request.automaticallyDetectsLanguage = true; request.usesLanguageCorrection = true
        try control?.register(request)
        defer { try? control?.register(nil) }
        do { try VNImageRequestHandler(cgImage: image).perform([request]) }
        catch { try Task.checkCancellation(); throw error }
        try Task.checkCancellation()
        return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
    }
    private static func pdf(_ data: Data, control: SourceImportControl?) throws -> SourceDocument {
        guard let pdf = PDFDocument(data: data) else { throw failure("PDF 无法读取，请确认文件完整。") }
        guard !pdf.isLocked else { throw failure("这份 PDF 有密码保护，请解锁后另存并导入。") }
        guard pdf.pageCount > 0, pdf.pageCount <= 200 else { throw failure("PDF 每次最多读取 200 页，请按章节拆分。") }
        var sections: [SourceSection] = [], ocr = false, characters = 0, unread = 0
        for index in 0..<pdf.pageCount {
            try Task.checkCancellation(); try control?.checkCancellation()
            control?.report("第 \(index + 1)/\(pdf.pageCount) 页")
            // Drain page rendering and Vision objects after every page, not after the whole PDF.
            let result: (String, Bool) = try autoreleasepool {
                guard let page = pdf.page(at: index) else { throw failure("PDF 第 \(index + 1) 页无法读取。") }
                var text = clean(page.string ?? ""), recognized = false
                if let ref = page.pageRef, text.count < 30 || PDFImageScan.containsImages(ref) {
                    control?.report("识别第 \(index + 1)/\(pdf.pageCount) 页")
                    let scanned = clean(try recognize(renderPage(ref), control: control))
                    let merged = mergeRecognizedText(scanned, into: text)
                    recognized = merged != text; text = merged
                }
                return (text, recognized)
            }
            var text = result.0; ocr = ocr || result.1
            if text.isEmpty { unread += 1; text = "[此页未识别到文字，请查看原件中的图示或空白页]" }
            characters += text.count
            guard characters <= maxCharacters else { throw failure("PDF 正文超过 12 万字，请按章节拆分后导入。") }
            sections.append(SourceSection(title: "第 \(index + 1) 页", text: text))
        }
        guard unread < pdf.pageCount else { throw failure("PDF 未识别到可整理的文字，请检查扫描清晰度或上传原图。") }
        return SourceDocument(format: "PDF", sections: sections, pageCount: pdf.pageCount, usedOCR: ocr, notice: unread > 0 ? "\(unread) 页未识别到文字，图示请对照原件。" : ocr ? "含扫描识别内容，公式和图表请对照原件。" : "已提取文字；图示关系与复杂公式请对照原件。")
    }
    /// Keep the native text authoritative; OCR only supplies lines absent from it.
    /// Whitespace can vary in recognition, but punctuation and signs are significant.
    static func mergeRecognizedText(_ scanned: String, into native: String) -> String {
        guard !native.isEmpty else { return scanned }
        func key(_ text: String) -> String { text.filter { !$0.isWhitespace } }
        let existing = Set(native.components(separatedBy: .newlines).map(key))
        var seen = Set<String>()
        let additions = scanned.components(separatedBy: .newlines).filter {
            let value = key($0)
            return !value.isEmpty && !existing.contains(value) && seen.insert(value).inserted
        }
        return additions.isEmpty ? native : native + "\n\n图像补充识别：\n" + additions.joined(separator: "\n")
    }
    /// Scan used image operators, including inline images and nested Form XObjects.
    /// Text-only pages stay on the fast extraction path.
    private final class PDFImageScan {
        var found = false
        var depth = 0
        static func containsImages(_ page: CGPDFPage) -> Bool {
            let state = PDFImageScan()
            let stream = CGPDFContentStreamCreateWithPage(page)
            defer { CGPDFContentStreamRelease(stream) }
            state.scan(stream)
            return state.found
        }
        func scan(_ stream: CGPDFContentStreamRef) {
            guard !found else { return }
            guard depth < 16 else { found = true; return }
            depth += 1; defer { depth -= 1 }
            guard let table = CGPDFOperatorTableCreate() else { found = true; return }
            defer { CGPDFOperatorTableRelease(table) }
            CGPDFOperatorTableSetCallback(table, "EI") { _, info in
                guard let info else { return }
                Unmanaged<PDFImageScan>.fromOpaque(info).takeUnretainedValue().found = true
            }
            CGPDFOperatorTableSetCallback(table, "Do") { scanner, info in
                guard let info else { return }
                let state = Unmanaged<PDFImageScan>.fromOpaque(info).takeUnretainedValue()
                guard !state.found else { return }
                var name: UnsafePointer<CChar>?
                let parent = CGPDFScannerGetContentStream(scanner)
                guard CGPDFScannerPopName(scanner, &name), let name,
                      let object = CGPDFContentStreamGetResource(parent, "XObject", name) else { return }
                var child: CGPDFStreamRef?
                guard CGPDFObjectGetValue(object, .stream, &child), let child,
                      let dictionary = CGPDFStreamGetDictionary(child) else { return }
                var subtype: UnsafePointer<CChar>?
                guard CGPDFDictionaryGetName(dictionary, "Subtype", &subtype), let subtype else { return }
                if String(cString: subtype) == "Image" { state.found = true }
                else if String(cString: subtype) == "Form" {
                    var resources: CGPDFDictionaryRef?
                    CGPDFDictionaryGetDictionary(dictionary, "Resources", &resources)
                    let content = CGPDFContentStreamCreateWithStream(child, resources ?? dictionary, parent)
                    defer { CGPDFContentStreamRelease(content) }
                    state.scan(content)
                }
            }
            let scanner = CGPDFScannerCreate(stream, table, Unmanaged.passUnretained(self).toOpaque())
            defer { CGPDFScannerRelease(scanner) }
            if !CGPDFScannerScan(scanner) { found = true }
        }
    }
    /// Render bounded pixels directly, without an AppKit NSImage or screen-scale expansion.
    static func renderPage(_ page: CGPDFPage, maxPixelSize: Int = 2400) throws -> CGImage {
        let bounds = page.getBoxRect(.mediaBox)
        guard bounds.width.isFinite, bounds.height.isFinite, bounds.width > 0, bounds.height > 0 else { throw failure("PDF 页面尺寸无效，请检查原件。") }
        let rotated = abs(page.rotationAngle % 180) == 90
        let width = rotated ? bounds.height : bounds.width, height = rotated ? bounds.width : bounds.height
        let factor = CGFloat(max(1, min(maxPixelSize, 4000))) / max(width, height)
        let pixelsWide = max(1, Int((width * factor).rounded())), pixelsHigh = max(1, Int((height * factor).rounded()))
        guard let context = CGContext(data: nil, width: pixelsWide, height: pixelsHigh, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { throw failure("PDF 页面无法绘制，请拆分后重试。") }
        let rect = CGRect(x: 0, y: 0, width: pixelsWide, height: pixelsHigh)
        context.setFillColor(CGColor(gray: 1, alpha: 1)); context.fill(rect)
        // CGPDFPage's drawing transform scales down but does not reliably upscale.
        // Apply the pixel scale ourselves, then let it handle page origins and rotation.
        context.scaleBy(x: factor, y: factor)
        context.concatenate(page.getDrawingTransform(.mediaBox, rect: CGRect(x: 0, y: 0, width: width, height: height), rotate: 0, preserveAspectRatio: true))
        context.interpolationQuality = .high
        context.setShouldAntialias(true)
        context.drawPDFPage(page)
        guard let image = context.makeImage() else { throw failure("PDF 页面无法绘制。") }
        return image
    }
    private static func bodyText(_ node: DocumentXML) -> String {
        if ["del", "instrText"].contains(node.name) { return "" }
        if node.name == "oMath" { return "\\(" + mathText(node) + "\\)" }
        if node.name == "footnoteReference" { return "[脚注 " + (node.attributes["w:id"] ?? "?") + "]" }
        if node.name == "endnoteReference" { return "[尾注 " + (node.attributes["w:id"] ?? "?") + "]" }
        if node.name == "r", let alignment = node.children.first(where: { $0.name == "rPr" })?.all("vertAlign").first?.attributes["w:val"], ["superscript", "subscript"].contains(alignment) {
            return (alignment == "superscript" ? "^{" : "_{") + node.children.filter { $0.name != "rPr" }.map(bodyText).joined() + "}"
        }
        if ["t", "v"].contains(node.name) { return node.content }
        if node.name == "tab" { return "\t" }
        if ["br", "cr"].contains(node.name) { return "\n" }
        let content = node.children.map(bodyText).joined()
        if node.name == "tc" { return clean(content).replacingOccurrences(of: "\n", with: " / ") + "\t" }
        return content + (["p", "tr"].contains(node.name) ? "\n" : node.name == "tc" ? "\t" : "")
    }
    static func mathText(_ node: DocumentXML) -> String {
        func part(_ name: String) -> String { node.children.first { $0.name == name }.map(mathText) ?? "" }
        switch node.name {
        case "t": return node.content
        case "f": return "\\frac{" + part("num") + "}{" + part("den") + "}"
        case "sSup": return "{" + part("e") + "}^{" + part("sup") + "}"
        case "sSub": return "{" + part("e") + "}_{" + part("sub") + "}"
        case "sSubSup": return "{" + part("e") + "}_{" + part("sub") + "}^{" + part("sup") + "}"
        case "rad":
            let degree = part("deg")
            return "\\sqrt" + (degree.isEmpty ? "" : "[" + degree + "]") + "{" + part("e") + "}"
        case "oMath", "r", "e", "num", "den", "sup", "sub", "deg":
            return node.children.filter { !$0.name.hasSuffix("Pr") }.map(mathText).joined()
        default:
            return "[复杂公式结构请对照原件：" + node.all("t").map(\.content).joined(separator: " ") + "]"
        }
    }
    private static func word(_ archive: OfficeArchive, control: SourceImportControl?) throws -> SourceDocument {
        let body = try archive.xml("word/document.xml")
        var sections = [SourceSection(title: "正文", text: bodyText(body))]
        guard sections[0].text.count <= maxCharacters else { throw failure("文档正文超过 12 万字，请按章节拆分后导入。") }
        for name in ["footnotes", "endnotes"] where archive.entries["word/\(name).xml"] != nil {
            let root = try archive.xml("word/\(name).xml")
            let values = root.all(name == "footnotes" ? "footnote" : "endnote").filter { (Int($0.attributes["w:id"] ?? "-1") ?? -1) >= 0 && ($0.attributes["w:type"] == nil || $0.attributes["w:type"] == "normal") }
            let text = values.map { "[" + (name == "footnotes" ? "脚注 " : "尾注 ") + ($0.attributes["w:id"] ?? "?") + "] " + bodyText($0) }.joined(separator: "\n")
            if !clean(text).isEmpty { sections.append(SourceSection(title: name == "footnotes" ? "脚注" : "尾注", text: text)) }
        }
        var usedOCR = false
        let media = try archive.related(to: "word/document.xml")
        let ids = body.all("blip").compactMap { $0.attributes["r:embed"] }
        var images = DocumentImageText()
        let ocr = try images.read(ids.compactMap { media[$0] }, archive: archive, control: control)
        if !ocr.isEmpty { sections.append(SourceSection(title: "插图识别文字", text: ocr)); usedOCR = true }
        return SourceDocument(format: "DOCX", sections: sections, usedOCR: usedOCR, notice: usedOCR ? "插图文字为本机识别，版式、复杂公式与图表请对照原件。" : "已提取正文、表格和注释；版式、复杂公式与图示请对照原件。")
    }
    private static func presentation(_ archive: OfficeArchive, control: SourceImportControl?) throws -> SourceDocument {
        let presentation = try archive.xml("ppt/presentation.xml"), relationships = try archive.related(to: "ppt/presentation.xml")
        let ids = presentation.all("sldId").compactMap { $0.attributes["r:id"] }
        guard !ids.isEmpty, ids.count <= 200 else { throw failure("演示文稿每次最多读取 200 页，请拆分后导入。") }
        var sections: [SourceSection] = [], usedOCR = false, readable = false, characters = 0
        var images = DocumentImageText()
        for (index, id) in ids.enumerated() {
            try Task.checkCancellation()
            try control?.checkCancellation(); control?.report("第 \(index + 1)/\(ids.count) 页")
            let text: String = try autoreleasepool {
            guard let path = relationships[id] else { throw failure("第 \(index + 1) 页幻灯片缺失。") }
            let slide = try archive.xml(path), related = try archive.related(to: path)
            var text = bodyText(slide)
            for chartID in slide.all("chart").compactMap({ $0.attributes["r:id"] }) {
                if let chart = related[chartID] { text += "\n图表数据：\n" + (try archive.xml(chart)).all("v").map(\.content).joined(separator: " · ") }
            }
            let ocr = try images.read(slide.all("blip").compactMap { $0.attributes["r:embed"] }.compactMap { related[$0] }, archive: archive, control: control, prefix: "第 \(index + 1)/\(ids.count) 页 · ")
            if !ocr.isEmpty { text += "\n插图识别文字：\n" + ocr; usedOCR = true }
            if let notes = related.values.sorted().first(where: { $0.hasPrefix("ppt/notesSlides/") && $0.hasSuffix(".xml") }) {
                let shapes = try archive.xml(notes).all("sp").filter { shape in !shape.all("ph").contains { ["sldNum", "hdr", "ftr", "dt"].contains($0.attributes["type"] ?? "") } }
                let noteText = clean(shapes.map(bodyText).joined(separator: "\n"))
                if !noteText.isEmpty { text += "\n演讲者备注：\n" + noteText }
            }
            return text
            }
            if !clean(text).isEmpty { readable = true }
            sections.append(SourceSection(title: "第 \(index + 1) 页", text: clean(text).isEmpty ? "[此页没有可提取文字，请查看原件]" : text))
            characters += text.count
            guard characters <= maxCharacters else { throw failure("演示文稿文字超过 12 万字，请拆分后导入。") }
        }
        guard readable else { throw failure("演示文稿未识别到可整理的文字，请导出为 PDF 后重试。") }
        return SourceDocument(format: "PPTX", sections: sections, pageCount: ids.count, usedOCR: usedOCR, notice: "已提取文字、表格和备注；图表与动画请对照原件。")
    }
    private struct DocumentImageText {
        private var paths: [String: String] = [:]
        private var contents: [SHA256.Digest: String] = [:]
        mutating func read(_ sources: [String], archive: OfficeArchive, control: SourceImportControl?, prefix: String = "") throws -> String {
            var result: [String] = [], seen = Set<String>()
            let unique = sources.filter { seen.insert($0).inserted }
            guard unique.count <= 80 else { throw failure("文档包含较多插图，请拆分后导入。") }
            for (index, path) in unique.enumerated() {
                try Task.checkCancellation(); try control?.checkCancellation()
                if let text = paths[path] { if !text.isEmpty { result.append(text) }; continue }
                control?.report(prefix + "识别插图 \(index + 1)/\(unique.count)")
                let text: String = try autoreleasepool {
                    let data = try archive.read(path), digest = SHA256.hash(data: data)
                    if let cached = contents[digest] { return cached }
                    guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
                          let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
                          (properties[kCGImagePropertyPixelWidth] as? Int ?? 0) >= 120,
                          (properties[kCGImagePropertyPixelHeight] as? Int ?? 0) >= 80,
                          let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: 3200, kCGImageSourceShouldCacheImmediately: true] as CFDictionary) else { return "" }
                    let text = clean(try recognize(image, control: control)); contents[digest] = text
                    return text
                }
                paths[path] = text
                if !text.isEmpty { result.append(text) }
            }
            return result.joined(separator: "\n\n")
        }
    }
    private static func spreadsheet(_ archive: OfficeArchive) throws -> SourceDocument {
        let workbook = try archive.xml("xl/workbook.xml"), relations = try archive.related(to: "xl/workbook.xml")
        let strings = archive.entries["xl/sharedStrings.xml"] == nil ? [] : try archive.xml("xl/sharedStrings.xml").all("si").map { $0.all("t").map(\.content).joined() }
        let sheets = workbook.all("sheet")
        guard sheets.count <= 50 else { throw failure("工作簿包含超过 50 张表，请拆分后导入。") }
        var sections: [SourceSection] = [], characters = 0
        for sheet in sheets {
            try Task.checkCancellation()
            guard let id = sheet.attributes["r:id"], let path = relations[id] else { throw failure("工作表内容缺失。") }
            let rows = try archive.xml(path).all("row")
            guard rows.count <= 10_000 else { throw failure("单张工作表超过 1 万行，请筛选或拆分后导入。") }
            var text: [String] = []
            for row in rows {
                try Task.checkCancellation()
                let cells = row.children.filter { $0.name == "c" }.map { cell -> String in
                    let raw = cell.children.first { $0.name == "v" }?.content ?? ""
                    let type = cell.attributes["t"] ?? ""
                    let value: String
                    if type == "s", let index = Int(raw), strings.indices.contains(index) { value = strings[index] }
                    else if type == "inlineStr" { value = cell.all("t").map(\.content).joined() }
                    else if type == "b" { value = raw == "1" ? "TRUE" : "FALSE" }
                    else { value = raw }
                    let formula = cell.children.first { $0.name == "f" }?.content
                    let content = formula.map { value.isEmpty ? "公式：=" + $0 : value + "（公式：=" + $0 + "）" } ?? value
                    return (cell.attributes["r"] ?? "单元格") + ": " + content
                }
                if !cells.isEmpty {
                    let value = cells.joined(separator: " | "); characters += value.count + 1
                    guard characters <= maxCharacters else { throw failure("工作簿正文超过 12 万字，请筛选或拆分后导入。") }
                    text.append(value)
                }
            }
            sections.append(SourceSection(title: sheet.attributes["name"] ?? "工作表", text: text.joined(separator: "\n")))
        }
        return SourceDocument(format: "XLSX", sections: sections, notice: "保留单元格位置、公式与原始缓存值；日期和数值格式请对照原件，不重新计算。")
    }
}

/// Bound each text layout while preserving every original character and section.
struct SourceReadingSlice: Identifiable {
    var id: Int
    var section: Int
    var title: String
    var text: String
    var startsSection: Bool
    static func make(_ document: SourceDocument, limit: Int = 3000) throws -> [SourceReadingSlice] {
        var result: [SourceReadingSlice] = []
        let maximum = max(1, limit)
        for (sectionIndex, section) in document.sections.enumerated() {
            var start = section.text.startIndex, first = true
            repeat {
                try Task.checkCancellation()
                var end = section.text.index(start, offsetBy: maximum, limitedBy: section.text.endIndex) ?? section.text.endIndex
                if end < section.text.endIndex {
                    let lower = section.text.index(start, offsetBy: maximum / 2)
                    if let newline = section.text[lower..<end].lastIndex(of: "\n") { end = section.text.index(after: newline) }
                }
                result.append(SourceReadingSlice(id: result.count, section: sectionIndex, title: first ? section.title : "", text: String(section.text[start..<end]), startsSection: first))
                first = false; start = end
            } while start < section.text.endIndex
        }
        return result
    }
}
