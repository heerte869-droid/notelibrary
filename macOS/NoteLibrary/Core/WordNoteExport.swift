import Foundation

// Converts the semantic MathML produced by the bundled KaTeX renderer into editable Office Math.
enum ExportOfficeMath {
    static func convert(_ mathML: String) throws -> String {
        let tree = try DocumentXML.parse(Data(mathML.utf8))
        guard let math = tree.all("math").first else { throw AppFailure(message: "公式缺少数学结构，无法导出 Word。") }
        return "<m:oMathPara><m:oMathParaPr><m:jc m:val=\"center\"/></m:oMathParaPr><m:oMath>\(try node(math))</m:oMath></m:oMathPara>"
    }
    private static func node(_ n: DocumentXML) throws -> String {
        let children = n.children.filter { $0.name != "annotation" && $0.name != "annotation-xml" }
        func all() throws -> String { try children.map(node).joined() }
        func child(_ i: Int) throws -> String { guard i < children.count else { throw AppFailure(message: "公式结构不完整，Word 导出未完成。") }; return try node(children[i]) }
        func run(_ text: String, normal: Bool = false) -> String { "<m:r>\(normal ? "<m:rPr><m:sty m:val=\"p\"/></m:rPr>" : "")<m:t xml:space=\"preserve\">\(ExportMarkup.xml(text))</m:t></m:r>" }
        switch n.name {
        case "math", "mrow", "mstyle", "mpadded", "semantics": return try all()
        case "mi", "mn", "mo", "mtext", "ms": return run(n.content, normal: n.name == "mtext" || n.attributes["mathvariant"] == "normal")
        case "mspace": return run(" ", normal: true)
        case "mfrac": return "<m:f><m:num>\(try child(0))</m:num><m:den>\(try child(1))</m:den></m:f>"
        case "msqrt": return "<m:rad><m:radPr><m:degHide m:val=\"1\"/></m:radPr><m:deg/><m:e>\(try all())</m:e></m:rad>"
        case "mroot": return "<m:rad><m:deg>\(try child(1))</m:deg><m:e>\(try child(0))</m:e></m:rad>"
        case "msub": return "<m:sSub><m:e>\(try child(0))</m:e><m:sub>\(try child(1))</m:sub></m:sSub>"
        case "msup": return "<m:sSup><m:e>\(try child(0))</m:e><m:sup>\(try child(1))</m:sup></m:sSup>"
        case "msubsup": return "<m:sSubSup><m:e>\(try child(0))</m:e><m:sub>\(try child(1))</m:sub><m:sup>\(try child(2))</m:sup></m:sSubSup>"
        case "munder": return "<m:limLow><m:e>\(try child(0))</m:e><m:lim>\(try child(1))</m:lim></m:limLow>"
        case "mover":
            if n.attributes["accent"] == "true", children.count > 1 { return "<m:acc><m:accPr><m:chr m:val=\"\(ExportMarkup.xml(children[1].content))\"/></m:accPr><m:e>\(try child(0))</m:e></m:acc>" }
            return "<m:limUpp><m:e>\(try child(0))</m:e><m:lim>\(try child(1))</m:lim></m:limUpp>"
        case "munderover": return "<m:limUpp><m:e><m:limLow><m:e>\(try child(0))</m:e><m:lim>\(try child(1))</m:lim></m:limLow></m:e><m:lim>\(try child(2))</m:lim></m:limUpp>"
        case "mtable":
            let rows = children.filter { $0.name == "mtr" || $0.name == "mlabeledtr" }
            let count = max(1, rows.map { $0.children.count }.max() ?? 1)
            let rowElements: [String] = try rows.map { row -> String in
                let cells: [String] = try (0..<count).map { i -> String in
                    let content: String
                    if i < row.children.count { content = try node(row.children[i]) }
                    else { content = "" }
                    return "<m:e>\(content)</m:e>"
                }
                return "<m:mr>\(cells.joined())</m:mr>"
            }
            let rowsXML = rowElements.joined()
            return "<m:m><m:mPr><m:mcs><m:mc><m:mcPr><m:count m:val=\"\(count)\"/><m:mcJc m:val=\"center\"/></m:mcPr></m:mc></m:mcs></m:mPr>\(rowsXML)</m:m>"
        case "mtd": return try all()
        case "mfenced": return "<m:d><m:dPr><m:begChr m:val=\"\(ExportMarkup.xml(n.attributes["open"] ?? "("))\"/><m:endChr m:val=\"\(ExportMarkup.xml(n.attributes["close"] ?? ")"))\"/></m:dPr><m:e>\(try all())</m:e></m:d>"
        case "mphantom": return "<m:phant><m:phantPr><m:show m:val=\"0\"/></m:phantPr><m:e>\(try all())</m:e></m:phant>"
        case "menclose": return "<m:borderBox><m:e>\(try all())</m:e></m:borderBox>"
        case "annotation", "annotation-xml": return ""
        default: throw AppFailure(message: "此公式的 \(n.name) 结构暂不能转换为 Word；可先导出 PDF 保留排版。")
        }
    }
}

struct WordNoteExport {
    private var files: [String: Data] = [:]
    private var relationships: [String] = []
    private var nextID = 1
    private let content: NoteExportContent
    private let options: NoteExportOptions
    private let mathML: [String: String]
    init(content: NoteExportContent, options: NoteExportOptions, mathML: [String: String]) { self.content = content; self.options = options; self.mathML = mathML }
    static let w = "http://schemas.openxmlformats.org/wordprocessingml/2006/main"
    static let r = "http://schemas.openxmlformats.org/officeDocument/2006/relationships"
    static let m = "http://schemas.openxmlformats.org/officeDocument/2006/math"
    static let xmlHeader = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>"
    private var pageWidth: Int { Int((options.paper.size.width - 96) * 20) }
    private mutating func relation(type: String, target: String, external: Bool = false) -> String {
        let id = "rId\(nextID)"; nextID += 1
        relationships.append("<Relationship Id=\"\(id)\" Type=\"\(Self.r)/\(type)\" Target=\"\(ExportMarkup.xml(target))\"\(external ? " TargetMode=\"External\"" : "")/>")
        return id
    }
    private mutating func runs(_ text: String) -> String {
        ExportMarkup.runs(text).map { value in
            var attributes = ""
            if value.bold { attributes += "<w:b/>" }
            if value.italic { attributes += "<w:i/>" }
            if value.code { attributes += "<w:rFonts w:ascii=\"Menlo\" w:hAnsi=\"Consolas\"/>" }
            if value.link != nil { attributes += "<w:color w:val=\"176B59\"/><w:u w:val=\"single\"/>" }
            var result = "<w:r><w:rPr>\(attributes)</w:rPr>" + value.text.components(separatedBy: "\n").map { "<w:t xml:space=\"preserve\">\(ExportMarkup.xml($0))</w:t>" }.joined(separator: "<w:br/>") + "</w:r>"
            if let link = value.link { let id = relation(type: "hyperlink", target: link, external: true); result = "<w:hyperlink r:id=\"\(id)\">\(result)</w:hyperlink>" }
            return result
        }.joined()
    }
    private mutating func paragraph(_ text: String, style: String = "Normal", extra: String = "") -> String {
        "<w:p><w:pPr><w:pStyle w:val=\"\(style)\"/>\(extra)</w:pPr>\(runs(text))</w:p>"
    }
    private mutating func paragraphs(_ text: String, style: String = "Normal", extra: String = "") -> String {
        text.components(separatedBy: "\n\n").filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.map { paragraph($0, style: style, extra: extra) }.joined()
    }
    private mutating func image(_ value: ExportImage, alt: String) -> String {
        let path = "media/image-\(nextID).\(value.ext)"; files["word/" + path] = value.data
        let id = relation(type: "image", target: path)
        let width = min(Double(pageWidth) / 20, Double(value.width) * 0.75)
        let scale = min(width / Double(value.width), 365 / Double(value.height))
        let cx = Int(Double(value.width) * scale * 12700), cy = Int(Double(value.height) * scale * 12700)
        return """
        <w:p><w:pPr><w:spacing w:before="180" w:after="120"/><w:jc w:val="center"/><w:keepNext/></w:pPr><w:r><w:drawing><wp:inline distT="0" distB="0" distL="0" distR="0"><wp:extent cx="\(cx)" cy="\(cy)"/><wp:docPr id="\(nextID)" name="Figure \(nextID)" descr="\(ExportMarkup.xml(alt))"/><wp:cNvGraphicFramePr><a:graphicFrameLocks noChangeAspect="1"/></wp:cNvGraphicFramePr><a:graphic><a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/picture"><pic:pic><pic:nvPicPr><pic:cNvPr id="\(nextID)" name="Figure" descr="\(ExportMarkup.xml(alt))"/><pic:cNvPicPr/></pic:nvPicPr><pic:blipFill><a:blip r:embed="\(id)"/><a:stretch><a:fillRect/></a:stretch></pic:blipFill><pic:spPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="\(cx)" cy="\(cy)"/></a:xfrm><a:prstGeom prst="rect"><a:avLst/></a:prstGeom></pic:spPr></pic:pic></a:graphicData></a:graphic></wp:inline></w:drawing></w:r></w:p>
        """
    }
    static func columnWidths(_ rows: [[String]], total: Int) -> [Int] {
        let count = max(1, rows.map(\.count).max() ?? 1)
        let weights = (0..<count).map { c -> Double in
            let length = rows.map { c < $0.count ? $0[c].count : 0 }.max() ?? 1
            return min(3.5, max(1, sqrt(Double(length)) / 3))
        }
        let sum = weights.reduce(0, +)
        var widths = weights.map { Int(Double(total) * $0 / sum) }
        widths[count - 1] += total - widths.reduce(0, +)
        return widths
    }
    private mutating func table(_ rows: [[String]]) -> String {
        guard !rows.isEmpty else { return "" }
        let widths = Self.columnWidths(rows, total: pageWidth)
        let borders = ["top", "left", "bottom", "right", "insideH", "insideV"].map { "<w:\($0) w:val=\"single\" w:sz=\"4\" w:color=\"D9D9D9\"/>" }.joined()
        var xml = "<w:tbl><w:tblPr><w:tblW w:w=\"\(pageWidth)\" w:type=\"dxa\"/><w:tblBorders>\(borders)</w:tblBorders><w:tblLayout w:type=\"fixed\"/><w:tblCellMar><w:top w:w=\"120\" w:type=\"dxa\"/><w:left w:w=\"140\" w:type=\"dxa\"/><w:bottom w:w=\"120\" w:type=\"dxa\"/><w:right w:w=\"140\" w:type=\"dxa\"/></w:tblCellMar></w:tblPr><w:tblGrid>" + widths.map { "<w:gridCol w:w=\"\($0)\"/>" }.joined() + "</w:tblGrid>"
        for (i, row) in rows.enumerated() {
            xml += "<w:tr><w:trPr><w:cantSplit/>" + (i == 0 ? "<w:tblHeader/>" : "") + "</w:trPr>"
            for (c, width) in widths.enumerated() {
                let fill = i == 0 ? "EDF2F5" : i % 2 == 0 ? "F7F9FA" : "FFFFFF"
                xml += "<w:tc><w:tcPr><w:tcW w:w=\"\(width)\" w:type=\"dxa\"/><w:shd w:fill=\"\(fill)\"/><w:vAlign w:val=\"center\"/></w:tcPr>"
                xml += paragraph(c < row.count ? row[c] : "", style: i == 0 ? "TableHeading" : "TableText") + "</w:tc>"
            }
            xml += "</w:tr>"
        }
        return xml + "</w:tbl>" + paragraph("", extra: "<w:spacing w:after=\"120\" w:line=\"40\"/>")
    }
    mutating func data() throws -> Data {
        _ = relation(type: "styles", target: "styles.xml")
        _ = relation(type: "numbering", target: "numbering.xml")
        _ = relation(type: "settings", target: "settings.xml")
        var body = paragraph(content.location, style: "Subtitle") + paragraph(content.note.title, style: "Title")
        if !content.note.tags.isEmpty { body += paragraph(content.note.tags.joined(separator: " · "), style: "Subtitle") }
        for block in content.note.blocks {
            try Task.checkCancellation()
            switch block.kind {
            case .heading: body += paragraph(block.text, style: "Heading1") + paragraphs(block.detail)
            case .term, .callout, .example: body += paragraph(block.text, style: "Heading2") + paragraphs(block.detail)
            case .paragraph: body += paragraphs(block.text) + paragraphs(block.detail)
            case .bullet: body += paragraph(block.text, extra: "<w:numPr><w:ilvl w:val=\"0\"/><w:numId w:val=\"1\"/></w:numPr>") + paragraphs(block.detail, extra: "<w:ind w:left=\"360\"/>")
            case .formula:
                guard let math = mathML[block.id] else { throw AppFailure(message: "公式尚未排版，请稍后重试。") }
                body += "<w:p><w:pPr><w:pStyle w:val=\"Equation\"/></w:pPr>\(try ExportOfficeMath.convert(math))</w:p>" + paragraphs(block.detail)
            case .table: if !block.text.isEmpty { body += paragraph(block.text, style: "Heading2") }; body += table(block.rows) + paragraphs(block.detail)
            case .diagram, .image:
                let key = block.kind == .diagram ? block.id : block.assetID ?? ""
                guard let value = content.images[key] else { throw AppFailure(message: "缺少图片或图示，Word 导出未完成。") }
                if block.kind == .diagram { body += paragraph(block.text, style: "Heading2") }
                body += image(value, alt: block.diagram?.accessibleDescription ?? block.text)
                body += paragraph(block.text, style: "Caption") + paragraphs(block.detail)
            }
            if options.includeSources { body += content.references(block).map { paragraph($0, style: "Caption") }.joined() }
        }
        if options.includeSources && !content.sources.isEmpty { body += paragraph("来源", style: "Heading1") + content.sources.map { paragraph($0, style: "Caption") }.joined() }
        var footer = ""
        if options.pageNumbers {
            let id = relation(type: "footer", target: "footer1.xml"); footer = "<w:footerReference w:type=\"default\" r:id=\"\(id)\"/>"
            files["word/footer1.xml"] = Data((Self.xmlHeader + "<w:ftr xmlns:w=\"\(Self.w)\"><w:p><w:pPr><w:jc w:val=\"center\"/><w:pStyle w:val=\"Caption\"/></w:pPr><w:fldSimple w:instr=\"PAGE\"><w:r><w:t>1</w:t></w:r></w:fldSimple></w:p></w:ftr>").utf8)
        }
        body += "<w:sectPr>\(footer)<w:pgSz w:w=\"\(Int(options.paper.size.width * 20))\" w:h=\"\(Int(options.paper.size.height * 20))\"/><w:pgMar w:top=\"960\" w:right=\"960\" w:bottom=\"960\" w:left=\"960\" w:header=\"360\" w:footer=\"420\" w:gutter=\"0\"/></w:sectPr>"
        files["word/document.xml"] = Data((Self.xmlHeader + "<w:document xmlns:w=\"\(Self.w)\" xmlns:r=\"\(Self.r)\" xmlns:m=\"\(Self.m)\" xmlns:wp=\"http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing\" xmlns:a=\"http://schemas.openxmlformats.org/drawingml/2006/main\" xmlns:pic=\"http://schemas.openxmlformats.org/drawingml/2006/picture\"><w:body>\(body)</w:body></w:document>").utf8)
        files["word/styles.xml"] = Data(Self.styles.utf8)
        files["word/settings.xml"] = Data((Self.xmlHeader + "<w:settings xmlns:w=\"\(Self.w)\" xmlns:m=\"\(Self.m)\"><w:defaultTabStop w:val=\"720\"/><w:updateFields w:val=\"true\"/><w:compat><w:compatSetting w:name=\"compatibilityMode\" w:uri=\"http://schemas.microsoft.com/office/word\" w:val=\"15\"/></w:compat><m:mathPr><m:mathFont m:val=\"Cambria Math\"/></m:mathPr></w:settings>").utf8)
        files["word/numbering.xml"] = Data((Self.xmlHeader + "<w:numbering xmlns:w=\"\(Self.w)\"><w:abstractNum w:abstractNumId=\"0\"><w:multiLevelType w:val=\"singleLevel\"/><w:lvl w:ilvl=\"0\"><w:start w:val=\"1\"/><w:numFmt w:val=\"bullet\"/><w:lvlText w:val=\"•\"/><w:lvlJc w:val=\"left\"/><w:pPr><w:tabs><w:tab w:val=\"num\" w:pos=\"360\"/></w:tabs><w:ind w:left=\"360\" w:hanging=\"240\"/></w:pPr></w:lvl></w:abstractNum><w:num w:numId=\"1\"><w:abstractNumId w:val=\"0\"/></w:num></w:numbering>").utf8)
        files["word/_rels/document.xml.rels"] = Data((Self.xmlHeader + "<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\">" + relationships.joined() + "</Relationships>").utf8)
        files["_rels/.rels"] = Data((Self.xmlHeader + "<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\"><Relationship Id=\"rId1\" Type=\"\(Self.r)/officeDocument\" Target=\"word/document.xml\"/></Relationships>").utf8)
        let parts = ["document": "document.main", "styles": "styles", "numbering": "numbering", "settings": "settings"]
        var types = Self.xmlHeader + "<Types xmlns=\"http://schemas.openxmlformats.org/package/2006/content-types\"><Default Extension=\"rels\" ContentType=\"application/vnd.openxmlformats-package.relationships+xml\"/><Default Extension=\"xml\" ContentType=\"application/xml\"/><Default Extension=\"png\" ContentType=\"image/png\"/><Default Extension=\"jpg\" ContentType=\"image/jpeg\"/>"
        for key in parts.keys.sorted() { types += "<Override PartName=\"/word/\(key).xml\" ContentType=\"application/vnd.openxmlformats-officedocument.wordprocessingml.\(parts[key]!).xml\"/>" }
        if options.pageNumbers { types += "<Override PartName=\"/word/footer1.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.wordprocessingml.footer+xml\"/>" }
        // Word's part content types use +xml, not .xml.
        types = types.replacingOccurrences(of: ".xml\"/>", with: "+xml\"/>")
        files["[Content_Types].xml"] = Data((types + "</Types>").utf8)
        return try ExportArchive.data(files)
    }
    private static var styles: String {
        func style(_ id: String, name: String, size: Int, before: Int, after: Int, extra: String = "", bold: Bool = false, color: String = "202422") -> String {
            "<w:style w:type=\"paragraph\" w:styleId=\"\(id)\"\(id == "Normal" ? " w:default=\"1\"" : "")><w:name w:val=\"\(name)\"/>\(id == "Normal" ? "" : "<w:basedOn w:val=\"Normal\"/>")<w:next w:val=\"Normal\"/><w:qFormat/><w:pPr><w:spacing w:before=\"\(before)\" w:after=\"\(after)\" w:line=\"340\" w:lineRule=\"auto\"/><w:widowControl/>\(extra)</w:pPr><w:rPr><w:sz w:val=\"\(size)\"/><w:szCs w:val=\"\(size)\"/><w:color w:val=\"\(color)\"/>\(bold ? "<w:b/>" : "")</w:rPr></w:style>"
        }
        return Self.xmlHeader + "<w:styles xmlns:w=\"\(w)\"><w:docDefaults><w:rPrDefault><w:rPr><w:rFonts w:ascii=\"Arial\" w:hAnsi=\"Arial\" w:eastAsia=\"PingFang SC\"/><w:sz w:val=\"23\"/><w:lang w:val=\"en-US\" w:eastAsia=\"zh-CN\"/></w:rPr></w:rPrDefault><w:pPrDefault><w:pPr><w:widowControl/></w:pPr></w:pPrDefault></w:docDefaults>" +
        style("Normal", name: "Normal", size: 23, before: 0, after: 160) +
        style("Title", name: "Title", size: 46, before: 100, after: 280, extra: "<w:keepNext/><w:keepLines/>", bold: true, color: "000000") +
        style("Subtitle", name: "Subtitle", size: 19, before: 0, after: 100, extra: "<w:keepNext/>", color: "66706A") +
        style("Heading1", name: "heading 1", size: 34, before: 360, after: 160, extra: "<w:keepNext/><w:keepLines/><w:outlineLvl w:val=\"0\"/>", bold: true, color: "000000") +
        style("Heading2", name: "heading 2", size: 27, before: 240, after: 100, extra: "<w:keepNext/><w:keepLines/><w:outlineLvl w:val=\"1\"/>", bold: true, color: "000000") +
        style("TableText", name: "Table Text", size: 20, before: 0, after: 0) +
        style("TableHeading", name: "Table Heading", size: 20, before: 0, after: 0, bold: true) +
        style("Caption", name: "Caption", size: 19, before: 0, after: 160, color: "66706A") +
        style("Equation", name: "Equation", size: 23, before: 180, after: 200, extra: "<w:keepLines/><w:jc w:val=\"center\"/>") + "</w:styles>"
    }
}
