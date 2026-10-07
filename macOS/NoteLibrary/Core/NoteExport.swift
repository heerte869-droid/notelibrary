import Foundation
import AppKit
import ImageIO
import UniformTypeIdentifiers
import zlib

enum NoteListOrder {
    static func sorted(_ notes: [Note], by order: String) -> [Note] {
        notes.sorted {
            if ($0.pinned == true) != ($1.pinned == true) { return $0.pinned == true }
            if order == "title" {
                let result = $0.title.localizedStandardCompare($1.title)
                if result != .orderedSame { return result == .orderedAscending }
            } else {
                let a = order == "created" ? $0.createdAt : $0.updatedAt
                let b = order == "created" ? $1.createdAt : $1.updatedAt
                if a != b { return a > b }
            }
            return $0.id < $1.id
        }
    }
}

enum NoteExportFormat: String, CaseIterable, Identifiable {
    case pdf, word, markdown, html
    var id: String { rawValue }
    var title: String { switch self { case .pdf: "PDF"; case .word: "Word"; case .markdown: "Markdown"; case .html: "HTML" } }
    var suffix: String { switch self { case .word: "docx"; case .markdown: "md"; default: rawValue } }
    var icon: String { switch self { case .pdf: "doc.richtext"; case .word: "doc.text"; case .markdown: "number"; case .html: "globe" } }
    var caption: String { switch self { case .pdf: "定稿与打印"; case .word: "继续编辑"; case .markdown: "迁移与整理"; case .html: "离线阅读" } }
    var explanation: String {
        switch self {
        case .pdf: "按页排版，保留文字、公式与图示。"
        case .word: "正文、表格和公式可继续编辑。"
        case .markdown: "保留 Markdown 与 LaTeX，图片随文件保存。"
        case .html: "图片与字体内嵌，离线也能完整阅读。"
        }
    }
    var contentType: UTType { switch self { case .pdf: .pdf; case .word: UTType(filenameExtension: "docx")!; case .markdown: UTType(filenameExtension: "md") ?? .plainText; case .html: .html } }
}
enum ExportPaper: String, CaseIterable, Identifiable {
    case letter, a4
    var id: String { rawValue }
    var title: String { self == .a4 ? "A4" : "Letter" }
    var size: CGSize { self == .a4 ? CGSize(width: 595.28, height: 841.89) : CGSize(width: 612, height: 792) }
}
struct NoteExportOptions: Equatable {
    var paper: ExportPaper = .letter
    var includeSources = true
    var pageNumbers = true
}
struct ExportImage {
    var data: Data
    var width: Int
    var height: Int
    var ext = "png"
    var mime: String { ext == "jpg" ? "image/jpeg" : "image/png" }
    var dataURI: String { "data:\(mime);base64," + data.base64EncodedString() }
}
struct NoteExportContent {
    var note: Note
    var location: String
    var sourceNames: [String: String]
    var images: [String: ExportImage]
    static func prepare(note: Note, location: String, sourceNames: [String: String], assetURLs: [String: URL], diagrams: [String: ExportImage]) throws -> Self {
        var images = diagrams
        for block in note.blocks where block.kind == .image {
            try Task.checkCancellation()
            guard let id = block.assetID, let url = assetURLs[id] else { throw AppFailure(message: "图片“\(block.text)”的原件不可用，请恢复原件后再导出。") }
            if images[id] != nil { continue }
            images[id] = try autoreleasepool {
                guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
                      let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
                      let width = props[kCGImagePropertyPixelWidth] as? Int, let height = props[kCGImagePropertyPixelHeight] as? Int,
                      width > 0, height > 0, width * height <= 80_000_000,
                      let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: max(width, height)] as CFDictionary)
                else { throw AppFailure(message: "图片“\(block.text)”无法读取，导出未完成。") }
                let data = NSMutableData()
                guard let target = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else { throw AppFailure(message: "无法准备导出图片。") }
                CGImageDestinationAddImage(target, image, nil)
                guard CGImageDestinationFinalize(target) else { throw AppFailure(message: "导出图片编码失败。") }
                return ExportImage(data: data as Data, width: image.width, height: image.height)
            }
        }
        for block in note.blocks where block.kind == .diagram {
            guard let diagram = block.diagram, images[block.id] != nil else { throw AppFailure(message: "图示“\(block.text)”不完整，导出未完成。") }
            try diagram.validate()
        }
        return Self(note: note, location: location, sourceNames: sourceNames, images: images)
    }
    func references(_ block: ContentBlock) -> [String] { block.citations.filter { sourceNames[$0] == nil } }
    var sources: [String] { Array(NSOrderedSet(array: note.sourceIDs.compactMap { sourceNames[$0] })) as? [String] ?? [] }
    static func safeFilename(_ title: String) -> String {
        let cleaned = title.components(separatedBy: CharacterSet(charactersIn: "/\\:\n\r\t\0")).joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        let short = String(cleaned.prefix(80)).trimmingCharacters(in: CharacterSet(charactersIn: ". "))
        return short.isEmpty ? "笔记" : short
    }
}

struct ExportTextRun {
    var text: String
    var bold = false
    var italic = false
    var code = false
    var link: String?
}
enum ExportMarkup {
    static func xml(_ value: String) -> String {
        String(value.unicodeScalars.filter { $0.value == 9 || $0.value == 10 || $0.value == 13 || $0.value >= 32 })
            .replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;").replacingOccurrences(of: "'", with: "&apos;")
    }
    static func runs(_ text: String) -> [ExportTextRun] {
        guard let value = try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) else { return [.init(text: text)] }
        return value.runs.map { run in
            let intent = run.inlinePresentationIntent ?? []
            let link = run.link.flatMap { ["http", "https", "mailto"].contains($0.scheme?.lowercased() ?? "") ? $0.absoluteString : nil }
            return .init(text: String(value[run.range].characters), bold: intent.contains(.stronglyEmphasized), italic: intent.contains(.emphasized), code: intent.contains(.code), link: link)
        }
    }
    static func inline(_ text: String) -> String {
        runs(text).map { run in
            var value = xml(run.text).replacingOccurrences(of: "\n", with: "<br>")
            if run.code { value = "<code>\(value)</code>" }
            if run.italic { value = "<em>\(value)</em>" }
            if run.bold { value = "<strong>\(value)</strong>" }
            if let link = run.link { value = "<a href=\"\(xml(link))\">\(value)</a>" }
            return value
        }.joined()
    }
    static func paragraphs(_ text: String, css: String = "") -> String {
        text.components(separatedBy: "\n\n").filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.map { "<p\(css.isEmpty ? "" : " class='\(css)'")>\(inline($0))</p>" }.joined()
    }
}

enum NoteExportHTML {
    static func document(_ content: NoteExportContent, options: NoteExportOptions) -> String {
        let escape = ExportMarkup.xml, inline = ExportMarkup.inline
        var body = "<header><p class='location'>\(escape(content.location))</p><h1>\(escape(content.note.title))</h1>"
        if !content.note.tags.isEmpty { body += "<p class='tags'>\(content.note.tags.map(escape).joined(separator: " · "))</p>" }
        body += "</header>"
        for (index, block) in content.note.blocks.enumerated() {
            let heading = inline(block.text), detail = ExportMarkup.paragraphs(block.detail)
            switch block.kind {
            case .heading: body += "<h2>\(heading)</h2>\(detail)"
            case .paragraph: body += ExportMarkup.paragraphs(block.text) + detail
            case .bullet: body += "<ul><li>\(heading)\(detail)</li></ul>"
            case .term, .callout: body += "<h3>\(heading)</h3>\(detail)"
            case .formula: body += "<div class='formula' id='formula-\(index)' data-block='\(escape(block.id))'>\(escape(block.text))</div>\(detail)"
            case .table:
                body += block.text.isEmpty ? "" : "<h3>\(heading)</h3>"
                if let first = block.rows.first {
                    let columns = max(1, block.rows.map(\.count).max() ?? 1)
                    let widths = WordNoteExport.columnWidths(block.rows, total: 10000)
                    let cols = "<colgroup>" + widths.map { "<col style='width:\(Double($0) / 100)%'>" }.joined() + "</colgroup>"
                    body += "<table>" + cols + "<thead><tr>" + (0..<columns).map { "<th>\(inline($0 < first.count ? first[$0] : ""))</th>" }.joined() + "</tr></thead><tbody>"
                    for row in block.rows.dropFirst() { body += "<tr>" + (0..<columns).map { "<td>\(inline($0 < row.count ? row[$0] : ""))</td>" }.joined() + "</tr>" }
                    body += "</tbody></table>"
                }
                body += detail
            case .diagram:
                if let diagram = block.diagram { body += "<figure><h3>\(heading)</h3><div class='diagram'>\(diagram.svg(title: block.text))</div></figure>\(detail)" }
            case .image:
                if let id = block.assetID, let image = content.images[id] { body += "<figure><img src='\(image.dataURI)' alt='\(escape(block.text))'><figcaption>\(heading)</figcaption></figure>\(detail)" }
            case .example: body += "<h3>\(heading)</h3>\(detail)"
            }
            if options.includeSources {
                let refs = content.references(block)
                if !refs.isEmpty { body += "<p class='reference'>" + refs.map { value in
                    if let url = URL(string: value), ["http", "https"].contains(url.scheme?.lowercased() ?? "") { return "<a href='\(escape(value))'>\(escape(value))</a>" }
                    return escape(value)
                }.joined(separator: "<br>") + "</p>" }
            }
        }
        if options.includeSources && !content.sources.isEmpty { body += "<section class='sources'><h2>来源</h2><ul>" + content.sources.map { "<li>\(escape($0))</li>" }.joined() + "</ul></section>" }
        return shell(body: body, title: content.note.title, paper: options.paper)
    }
    static func shell(body: String, title: String, paper: ExportPaper) -> String {
        let width = (paper.size.width - 96) * 4 / 3
        return """
        <!doctype html><html lang="zh-CN"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><meta http-equiv="Content-Security-Policy" content="default-src 'none'; script-src 'unsafe-inline' notelibrary-math:; style-src 'unsafe-inline' notelibrary-math:; font-src notelibrary-math: data:; img-src data:"><title>\(ExportMarkup.xml(title))</title><link rel="stylesheet" href="notelibrary-math://bundle/katex.min.css"><style>
        *{box-sizing:border-box}html{background:#fff;color:#202422}body{margin:0;font-family:Arial,'PingFang SC','Hiragino Sans GB','Microsoft YaHei',sans-serif;font-size:15px;line-height:1.75;overflow-wrap:break-word}main{max-width:\(width)px;margin:auto;padding:0}header{margin:0 0 28px}h1,h2,h3{color:#000;line-height:1.4;break-after:avoid;page-break-after:avoid;font-weight:600}h1{font-size:30px;margin:10px 0 14px}h2{font-size:22px;margin:30px 0 12px}h3{font-size:17px;margin:22px 0 9px}p{margin:0 0 12px;orphans:3;widows:3}ul{padding-left:23px;margin:8px 0 16px}li{margin:5px 0}li p{margin:8px 0}.location,.tags{font-size:12px;color:#6a726e}.location{margin:0}.tags{margin:10px 0 0}.reference,figcaption{font-size:12px;color:#616b65;line-height:1.6;overflow-wrap:anywhere}.reference{margin-top:8px}a{color:#176b59;text-decoration:underline}code{font-size:.92em;font-family:Menlo,monospace}blockquote{margin:18px 0 18px 18px;color:#46504a}figure{margin:20px 0;break-inside:avoid;page-break-inside:avoid}figure h3{margin-top:0}figcaption{margin-top:9px;text-align:center}figure img{display:block;max-width:100%;max-height:540px;width:auto;height:auto;margin:auto}.diagram svg{display:block;width:100%;height:auto;max-height:420px}table{border-collapse:collapse;width:100%;margin:12px 0 18px;font-size:13.3px;line-height:1.65;table-layout:fixed}th,td{break-inside:avoid;page-break-inside:avoid;border:1px solid #d9d9d9;padding:9px 11px;text-align:left;vertical-align:middle;overflow-wrap:anywhere}th{background:#edf2f5;color:#17232b;font-weight:600}tbody tr:nth-child(even){background:#f7f9fa}thead{display:table-header-group}tr{break-inside:avoid;page-break-inside:avoid}.formula{font-size:17px;margin:18px 0;break-inside:avoid;page-break-inside:avoid;text-align:center}.formula .katex-display{margin:0}.sources{margin-top:30px}.sources h2{font-size:17px}.sources li{font-size:12px;color:#616b65}@media print{html,body{background:white}body{padding:0}main{max-width:none}a{color:#176b59}*{-webkit-print-color-adjust:exact}}@media screen{body{padding:28px}}
        </style><script src="notelibrary-math://bundle/katex.min.js"></script></head><body><main>\(body)</main><script>
        (async()=>{try{for(const el of document.querySelectorAll('.formula')){const tex=el.textContent;katex.render(tex,el,{displayMode:true,throwOnError:true,trust:false,strict:'ignore',maxExpand:1000,output:'htmlAndMathml'});el.dataset.tex=tex;}await document.fonts.ready;await Promise.all(Array.from(document.images).map(i=>i.decode().catch(()=>{throw Error('图片无法显示')})));for(const el of document.querySelectorAll('.formula')){const inner=el.querySelector('.katex-html');const ratio=el.clientWidth/Math.max(inner?.scrollWidth||el.scrollWidth,1);if(ratio<1)el.style.fontSize=(17*ratio)+'px';}void document.body.offsetHeight;window.webkit.messageHandlers.exportReady.postMessage({ready:true,height:document.body.scrollHeight});}catch(e){window.webkit.messageHandlers.exportReady.postMessage({error:'公式或图片排版失败：'+e.message});}})();
        </script></body></html>
        """
    }
    static func portable(renderedHTML: String, resources: URL) throws -> String {
        var css = try String(contentsOf: resources.appendingPathComponent("katex.min.css"), encoding: .utf8)
        css = css.replacingOccurrences(of: #",url\(fonts/[^)]+\.(?:woff|ttf)\) format\("[^"]+"\)"#, with: "", options: .regularExpression)
        let regex = try NSRegularExpression(pattern: #"url\((?:['"]?)(fonts/[^)'" ]+)(?:['"]?)\)"#)
        for match in regex.matches(in: css, range: NSRange(css.startIndex..., in: css)).reversed() {
            guard let range = Range(match.range, in: css), let pathRange = Range(match.range(at: 1), in: css) else { continue }
            let data = try Data(contentsOf: resources.appendingPathComponent(String(css[pathRange])))
            let ext = resources.appendingPathComponent(String(css[pathRange])).pathExtension
            css.replaceSubrange(range, with: "url(data:font/\(ext);base64,\(data.base64EncodedString()))")
        }
        var html = renderedHTML
        html = html.replacingOccurrences(of: #"<script\b[\s\S]*?</script>"#, with: "", options: .regularExpression)
        html = html.replacingOccurrences(of: #"<link\b[^>]*>"#, with: "", options: .regularExpression)
        html = html.replacingOccurrences(of: "</head>", with: "<style>\(css)</style></head>")
        html = html.replacingOccurrences(of: #"script-src 'unsafe-inline' notelibrary-math:;"#, with: "script-src 'none';")
        return "<!doctype html>" + html
    }
}

struct MarkdownExportPackage {
    var text: String
    var files: [String: Data]
}
enum NoteExportMarkdown {
    static func package(_ content: NoteExportContent, options: NoteExportOptions, folder: String) -> MarkdownExportPackage {
        var files: [String: Data] = [:], lines = ["# " + content.note.title.replacingOccurrences(of: "\n", with: " "), ""]
        func assetLink(_ image: ExportImage, index: Int) -> String {
            let filename = String(format: "figure-%02d.%@", index + 1, image.ext); files[filename] = image.data
            return (folder + "/" + filename).addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? filename
        }
        for (i, b) in content.note.blocks.enumerated() {
            switch b.kind {
            case .heading: lines += ["## " + b.text, "", b.detail]
            case .term, .callout: lines += ["### " + b.text, "", b.detail]
            case .bullet: lines += ["- " + b.text.replacingOccurrences(of: "\n", with: "\n  "), "", b.detail]
            case .formula: lines += ["$$", b.text, "$$", "", b.detail]
            case .table:
                if !b.text.isEmpty { lines += ["### " + b.text, ""] }
                let count = b.rows.map(\.count).max() ?? 0
                for (j, row) in b.rows.enumerated() {
                    let cells = (0..<count).map { index -> String in
                        (index < row.count ? row[index] : "").replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "|", with: "\\|").replacingOccurrences(of: "\n", with: "<br>")
                    }
                    lines.append("| " + cells.joined(separator: " | ") + " |")
                    if j == 0 { lines.append("| " + Array(repeating: "---", count: count).joined(separator: " | ") + " |") }
                }
                lines += ["", b.detail]
            case .image, .diagram:
                let key = b.kind == .diagram ? b.id : b.assetID ?? ""
                if let image = content.images[key] { lines += ["![" + b.text.replacingOccurrences(of: "[", with: "\\[").replacingOccurrences(of: "]", with: "\\]") + "](" + assetLink(image, index: i) + ")", "", b.detail] }
            case .example: lines += ["### " + b.text, "", b.detail]
            default: lines += [b.text, "", b.detail]
            }
            if options.includeSources { lines += content.references(b).map { "\n来源：" + $0 } }
            lines.append("")
        }
        if options.includeSources && !content.sources.isEmpty { lines += ["## 来源", ""] + content.sources.map { "- " + $0 } }
        return .init(text: lines.joined(separator: "\n").replacingOccurrences(of: #"\n{4,}"#, with: "\n\n\n", options: .regularExpression) + "\n", files: files)
    }
    static func write(_ content: NoteExportContent, options: NoteExportOptions, to url: URL) throws {
        let folder = NoteExportContent.safeFilename(url.deletingPathExtension().lastPathComponent) + "-assets-" + UUID().uuidString.lowercased()
        let package = package(content, options: options, folder: folder)
        let directory = url.deletingLastPathComponent().appendingPathComponent(folder, isDirectory: true)
        var createdDirectory = false
        do {
            if !package.files.isEmpty {
                guard !FileManager.default.fileExists(atPath: directory.path) else { throw AppFailure(message: "导出目录已存在，请重试。") }
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
                createdDirectory = true
                for (name, data) in package.files { try data.write(to: directory.appendingPathComponent(name), options: .atomic) }
            }
            try Task.checkCancellation()
            try package.text.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            if createdDirectory { try? FileManager.default.removeItem(at: directory) }
            throw error
        }
    }
}

// A minimal OPC ZIP writer: compressed images stay compressed; XML remains UTF-8.
enum ExportArchive {
    static func data(_ files: [String: Data]) throws -> Data {
        var output = Data(), directory = Data()
        func number(_ value: UInt32, bytes: Int, to data: inout Data) { for i in 0..<bytes { data.append(UInt8(truncatingIfNeeded: value >> (i * 8))) } }
        for name in files.keys.sorted() {
            try Task.checkCancellation()
            guard !name.hasPrefix("/"), !name.split(separator: "/").contains(".."), let body = files[name], body.count < Int(UInt32.max) else { throw AppFailure(message: "导出文件过大或路径无效。") }
            let filename = Data(name.utf8), offset = UInt32(output.count), size = UInt32(body.count)
            let crc = body.withUnsafeBytes { UInt32(crc32(0, $0.bindMemory(to: Bytef.self).baseAddress, uInt(body.count))) }
            number(0x04034b50, bytes: 4, to: &output)
            for n: UInt32 in [20, 0x800, 0, 0, 0x21] { number(n, bytes: 2, to: &output) }
            for n in [crc, size, size] { number(n, bytes: 4, to: &output) }
            number(UInt32(filename.count), bytes: 2, to: &output); number(0, bytes: 2, to: &output); output.append(filename); output.append(body)
            number(0x02014b50, bytes: 4, to: &directory)
            for n: UInt32 in [20, 20, 0x800, 0, 0, 0x21] { number(n, bytes: 2, to: &directory) }
            for n in [crc, size, size] { number(n, bytes: 4, to: &directory) }
            for n: UInt32 in [UInt32(filename.count), 0, 0, 0, 0] { number(n, bytes: 2, to: &directory) }
            number(0, bytes: 4, to: &directory); number(offset, bytes: 4, to: &directory); directory.append(filename)
        }
        let offset = UInt32(output.count); output.append(directory)
        number(0x06054b50, bytes: 4, to: &output)
        for n: UInt32 in [0, 0, UInt32(files.count), UInt32(files.count)] { number(n, bytes: 2, to: &output) }
        number(UInt32(directory.count), bytes: 4, to: &output); number(offset, bytes: 4, to: &output); number(0, bytes: 2, to: &output)
        return output
    }
}
