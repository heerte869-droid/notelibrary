import XCTest
import AppKit
import PDFKit
import SwiftUI
@testable import NoteLibrary

final class ExportTests: XCTestCase {
    func testOldNotesDecodeWithoutPinAndPinPersists() throws {
        var note = Note(chapterID: "chapter", title: "旧笔记")
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONCoding.encoder.encode(note)) as? [String: Any])
        object.removeValue(forKey: "pinned")
        let decoded = try JSONCoding.decoder.decode(Note.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertNil(decoded.pinned)
        note.pinned = true
        XCTAssertEqual(try JSONCoding.decoder.decode(Note.self, from: JSONCoding.encoder.encode(note)).pinned, true)
    }
    func testPinPriorityRespectsSortAndStableTies() {
        var old = Note(id: "old", chapterID: "a", title: "Z", updatedAt: Date(timeIntervalSince1970: 1))
        let new = Note(id: "new", chapterID: "a", title: "A", updatedAt: Date(timeIntervalSince1970: 2))
        old.pinned = true
        XCTAssertEqual(NoteListOrder.sorted([new, old], by: "updated").map(\.id), ["old", "new"])
        XCTAssertEqual(NoteListOrder.sorted([new, old], by: "title").map(\.id), ["old", "new"])
        old.pinned = false
        XCTAssertEqual(NoteListOrder.sorted([new, old], by: "updated").map(\.id), ["new", "old"])
        var a = old; a.id = "first"
        XCTAssertEqual(NoteListOrder.sorted([old, a], by: "title").first?.id, "first")
    }
    func testDuplicateDoesNotInheritPinnedPosition() {
        var state = LibraryState(); var note = Note(chapterID: "c", title: "A"); note.pinned = true
        state.notes = [note]
        let copy = LibraryEdits.duplicate(note, state: &state)
        XCTAssertNil(copy.pinned); XCTAssertTrue(state.notes[0].pinned == true)
    }
    func testPinDoesNotBlockContentUndoOrDisappearAfterUndo() throws {
        let before = Note(chapterID: "c", title: "Before")
        var after = before; after.title = "After"; after.version += 1
        let receipt = ChangeReceipt(id: "r", title: "编辑", changes: [NoteDelta(before: before, after: after)], createdNotebookIDs: [], createdChapterIDs: [])
        var state = LibraryState(); state.notes = [after]; state.receipts = [receipt]
        state.notes[0].pinned = true
        let restored = try NoteEngine.undo(receiptID: "r", in: state)
        XCTAssertEqual(restored.notes[0].title, "Before")
        XCTAssertEqual(restored.notes[0].pinned, true)
        state.notes[0].blocks.append(.init(kind: .paragraph, text: "稍后的改动"))
        XCTAssertThrowsError(try NoteEngine.undo(receiptID: "r", in: state))
    }
    func testMarkdownAssetsAndTableDetailsStayPortable() {
        let image = ExportImage(data: Data([1, 2, 3]), width: 40, height: 20)
        let note = Note(chapterID: "c", title: "资料", blocks: [
            ContentBlock(kind: .table, text: "比较", detail: "表后说明", rows: [["A", "B"], ["x|y", "换行\n下一行"], ["短行"]]),
            ContentBlock(kind: .image, text: "示例 [1]", detail: "图后说明", assetID: "asset"),
            ContentBlock(kind: .formula, text: #"\frac{a}{b}"#, detail: "公式说明", citations: ["asset", "https://example.com/reference"])
        ], sourceIDs: ["asset"])
        let content = NoteExportContent(note: note, location: "资料库", sourceNames: ["asset": "原稿.png"], images: ["asset": image])
        let package = NoteExportMarkdown.package(content, options: .init(), folder: "a folder-assets")
        XCTAssertEqual(package.files.count, 1)
        XCTAssertTrue(package.text.contains("a%20folder-assets/figure-02.png"))
        for value in ["x\\|y", "换行<br>下一行", "表后说明", "图后说明", "公式说明", "原稿.png", "https://example.com/reference", "$$"] { XCTAssertTrue(package.text.contains(value), value) }
        XCTAssertFalse(package.text.contains("来源：asset"))
        let hidden = NoteExportMarkdown.package(content, options: .init(includeSources: false), folder: "assets")
        XCTAssertFalse(hidden.text.contains("原稿.png")); XCTAssertFalse(hidden.text.contains("example.com"))
    }
    func testHTMLRetainsBlocksEscapesAndRepeatsHeader() {
        let note = Note(chapterID: "c", title: "<script>标题</script>", blocks: [ContentBlock(kind: .heading, text: "标题", detail: "标题说明"), ContentBlock(kind: .table, text: "表", detail: "表说明", rows: [["字段", "描述"], ["<img src=x>", "内容"]]), ContentBlock(kind: .example, text: "例题", detail: "解答")])
        let html = NoteExportHTML.document(.init(note: note, location: "书 / 章", sourceNames: [:], images: [:]), options: .init())
        for value in ["<thead>", "标题说明", "表说明", "解答", "&lt;script&gt;", "&lt;img src=x&gt;", "document.fonts.ready", "page-break-after:avoid"] { XCTAssertTrue(html.contains(value), value) }
        XCTAssertFalse(html.contains("<img src=x>"))
    }
    func testWordUsesNativeStructuresAndValidPackageRelationships() throws {
        let formula = ContentBlock(kind: .formula, text: #"\frac{x^2}{\sqrt{y}}"#, detail: "公式解释")
        let note = Note(chapterID: "c", title: "导出校验", blocks: [ContentBlock(kind: .heading, text: "第一节", detail: "标题解释"), ContentBlock(kind: .table, text: "对比表", detail: "表格解释", rows: [["名", "解释"], ["项目", "**加粗**说明"]]), formula])
        let math = "<math><mfrac><msup><mi>x</mi><mn>2</mn></msup><msqrt><mi>y</mi></msqrt></mfrac></math>"
        var writer = WordNoteExport(content: .init(note: note, location: "书", sourceNames: [:], images: [:]), options: .init(), mathML: [formula.id: math])
        let zip = try OfficeArchive(writer.data())
        for path in zip.entries.keys where path.hasSuffix("xml") || path.hasSuffix("rels") { _ = try zip.xml(path) }
        let doc = try zip.xml("word/document.xml")
        XCTAssertEqual(doc.all("tblHeader").count, 1)
        XCTAssertEqual(doc.all("f").count, 1); XCTAssertEqual(doc.all("rad").count, 1)
        XCTAssertEqual(doc.all("sSup").count, 1)
        XCTAssertTrue(doc.content.contains("标题解释")); XCTAssertTrue(doc.content.contains("表格解释")); XCTAssertTrue(doc.content.contains("公式解释"))
        let types = try zip.xml("[Content_Types].xml").all("Override")
        XCTAssertTrue(types.allSatisfy { $0.attributes["ContentType"]?.hasSuffix("+xml") == true })
        XCTAssertNotNil(try zip.related(to: "word/document.xml")["rId1"])
        let widths = WordNoteExport.columnWidths([["序", "很长的说明很长的说明很长的说明"], ["1", "描述"]], total: 10000)
        XCTAssertEqual(widths.reduce(0, +), 10000); XCTAssertLessThan(widths[0], widths[1])
    }
    func testMissingImageStopsExportInsteadOfSilentlyDroppingContent() {
        let note = Note(chapterID: "c", title: "缺图", blocks: [.init(kind: .image, text: "实验结果", assetID: "missing")])
        XCTAssertThrowsError(try NoteExportContent.prepare(note: note, location: "", sourceNames: [:], assetURLs: [:], diagrams: [:]))
    }
    func testSafeFilenameAndXMLControlCharacters() {
        XCTAssertEqual(NoteExportContent.safeFilename("../目录/标题:一\n二"), "目录 标题 一 二")
        XCTAssertEqual(NoteExportContent.safeFilename(" / . "), "笔记")
        XCTAssertEqual(ExportMarkup.xml("a\u{01}&<b"), "a&amp;&lt;b")
    }
    func testPortableHTMLNeedsNoRemoteFilesOrScript() throws {
        let root = try XCTUnwrap(Bundle.main.resourceURL?.appendingPathComponent("KaTeX"))
        let portable = try NoteExportHTML.portable(renderedHTML: "<html><head><link href='notelibrary-math://bundle/katex.min.css'></head><body><script>alert(1)</script><p>正文</p></body></html>", resources: root)
        XCTAssertFalse(portable.contains("<script")); XCTAssertFalse(portable.contains("url(fonts/")); XCTAssertFalse(portable.contains("<link")); XCTAssertTrue(portable.contains("data:font/woff2;base64,"))
    }
    @MainActor func testActualPaginationAndExportArtifacts() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("NoteLibrary-Export-" + UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        guard FileManager.default.fileExists(atPath: root.deletingLastPathComponent().path) else { throw XCTSkip("Explicit isolated export workspace required") }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let formula = ContentBlock(kind: .formula, text: #"E=mc^2,\qquad x=\frac{-b\pm\sqrt{b^2-4ac}}{2a}"#, detail: "公式保持分式、上下标和根号结构，可在 Word 中继续编辑。")
        let rows = [["编号", "要点", "说明"]] + (1...44).map { ["\($0)", "概念与条件", "这是第 \($0) 行：长表格需要跨页，并在新页重复表头；中文和 English 可以自然换行。"] }
        let diagram = StudyDiagram(axes: true, xLabel: "Capital goods", yLabel: "Consumer goods", elements: [.init(kind: "curve", label: "PPC₁", style: "secondary", dashed: false, points: [[0,70],[40,70],[70,40],[70,0]]), .init(kind: "curve", label: "PPC₂", style: "primary", dashed: false, points: [[0,90],[55,90],[95,45],[95,0]])])
        var note = Note(chapterID: "c", title: "经济学学习笔记：概念、公式与图示", blocks: [
            .init(kind: .heading, text: "认识机会成本", detail: "学习笔记应保留清晰的层次，在导出后仍可阅读和编辑。"),
            .init(kind: .paragraph, text: "**机会成本**是为了得到某项选择而放弃的最佳替代方案的价值。\n\n面对有限资源，需要比较可行方案。这里保留中文、English、数字 123 和特殊字符 < > &。"),
            .init(kind: .bullet, text: "先明确约束和可选方案", detail: "不要把所有未选方案相加。"), formula,
            .init(kind: .heading, text: "跨页比较表"), .init(kind: .table, text: "要点与解释", detail: "表格结束后，这段说明应该完整出现。", rows: rows),
            .init(kind: .heading, text: "增长如何改变生产边界"), .init(kind: .diagram, text: "生产可能性曲线向外移动", detail: "生产能力提高，使两类产品可达到的组合扩大。", diagram: diagram),
            .init(kind: .example, text: "用一个例子检验理解", detail: "投资教育与技术可以提高未来的生产能力。\n\n这个例子说明原因与结果，不改变原有知识内容。")
        ])
        let block = note.blocks.first { $0.kind == .diagram }!
        let renderer = ImageRenderer(content: StudyDiagramView(diagram: diagram).environment(\.colorScheme, .light).frame(width: 700, height: 410)); renderer.scale = 3
        let cg = try XCTUnwrap(renderer.cgImage); let png = try XCTUnwrap(NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]))
        let image = ExportImage(data: png, width: cg.width, height: cg.height)
        note.blocks.append(.init(kind: .image, text: "嵌入图片", detail: "图片的说明保持在正文中。", assetID: "fixture")); note.sourceIDs = ["fixture"]
        let content = NoteExportContent(note: note, location: "经济学 / 导出验收", sourceNames: ["fixture": "图示原稿.png"], images: [block.id: image, "fixture": image])
        let options = NoteExportOptions(paper: .a4)
        let start = Date()
        let rendered = try await NoteExportRenderer().render(content, options: options)
        XCTAssertGreaterThan(rendered.pageCount, 2)
        try rendered.pdf.write(to: root.appendingPathComponent("mixed-content.pdf"))
        try rendered.html.write(to: root.appendingPathComponent("mixed-content.html"), atomically: true, encoding: .utf8)
        try NoteExportMarkdown.write(content, options: options, to: root.appendingPathComponent("mixed-content.md"))
        var word = WordNoteExport(content: content, options: options, mathML: rendered.mathML)
        try word.data().write(to: root.appendingPathComponent("mixed-content.docx"))
        let pdf = try XCTUnwrap(PDFDocument(data: rendered.pdf))
        let text = (0..<pdf.pageCount).compactMap { pdf.page(at: $0)?.string }.joined().precomposedStringWithCompatibilityMapping.replacingOccurrences(of: #"\s"#, with: "", options: .regularExpression)
        for expected in ["机会成本", "第 44 行", "表格结束后", "用一个例子", "图片的说明", "图示原稿.png"] { XCTAssertTrue(text.contains(expected.replacingOccurrences(of: " ", with: "")), expected) }
        let info: [String: Any] = ["pages": rendered.pageCount, "seconds": Date().timeIntervalSince(start), "pdfBytes": rendered.pdf.count, "formulaCount": rendered.mathML.count]
        try JSONSerialization.data(withJSONObject: info, options: .prettyPrinted).write(to: root.appendingPathComponent("render-report.json"))
    }

    @MainActor func testLongContentPaginationAndSymbolsRemainComplete() async throws {
        let long = (1...90).map { "段落\($0)中英文 mixed text 保留内容和 **强调**。" }.joined()
        let cell = (1...70).map { "条件\($0)：表格中的长内容也需要完整继续。" }.joined()
        let note = Note(chapterID: "c", title: "A → B：符号与长段落", blocks: [.init(kind: .heading, text: "实际增长 · A → B"), .init(kind: .paragraph, text: long), .init(kind: .table, text: "长单元格", rows: [["名称", "解释"], ["A", cell]]), .init(kind: .paragraph, text: "结束标记-END")])
        let result = try await NoteExportRenderer().render(.init(note: note, location: "验证", sourceNames: [:], images: [:]), options: .init(includeSources: false, pageNumbers: false))
        let doc = try XCTUnwrap(PDFDocument(data: result.pdf))
        let text = (0..<doc.pageCount).compactMap { doc.page(at: $0)?.string }.joined().precomposedStringWithCompatibilityMapping.replacingOccurrences(of: #"\s"#, with: "", options: .regularExpression)
        for i in 1...90 { XCTAssertTrue(text.contains("段落\(i)中英文")) }
        for i in 1...70 { XCTAssertTrue(text.contains("条件\(i):")) }
        XCTAssertTrue(text.contains("A→B")); XCTAssertTrue(text.contains("结束标记-END"))
    }

}
