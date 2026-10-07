import XCTest
import AppKit
import PDFKit
@testable import NoteLibrary

final class SourceImportTests: XCTestCase {
    func fixture(_ name: String) throws -> URL { try XCTUnwrap(Bundle(for: Self.self).url(forResource: name, withExtension: nil, subdirectory: "Fixtures")) }
    func parse(_ name: String) throws -> SourceDocument { let document = try SourceImport.read(fixture(name)).1; return try XCTUnwrap(document) }
    func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("NoteLibrary-ImportTest-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true); addTeardownBlock { try? FileManager.default.removeItem(at: url) }; return url
    }
    func testMarkdownKeepsTablesAndCodeWithoutInterpretation() throws {
        let document = try parse("lesson.md")
        XCTAssertEqual(document.format, "Markdown"); XCTAssertTrue(document.text.contains("|蒸发|液体变成气体|")); XCTAssertTrue(document.text.contains("print(\"保留代码\")"))
        XCTAssertEqual(document.text, SourceImport.clean(try String(contentsOf: fixture("lesson.md"), encoding: .utf8)))
    }
    func testChineseUTF16CSVAndGB18030Decode() throws {
        XCTAssertTrue(try parse("table.csv").text.contains("物理,动量守恒"))
        XCTAssertTrue(try parse("gb18030.txt").text.contains("细胞与光合作用"))
        XCTAssertThrowsError(try SourceImport.decodeText(Data([0, 1, 2, 3])))
    }
    func testWordReadsParagraphAndTableInOrder() throws {
        let text = try parse("lesson.docx").text
        XCTAssertTrue(text.contains("水循环学习资料")); XCTAssertTrue(text.contains("水蒸气形成水滴")); XCTAssertLessThan(text.range(of: "第一部分")!.lowerBound, text.range(of: "水蒸气")!.lowerBound)
    }
    func testPowerPointFollowsPresentationOrderAndIncludesNotes() throws {
        let document = try parse("lesson.pptx")
        XCTAssertEqual(document.pageCount, 3)
        XCTAssertTrue(document.sections[0].text.contains("第三部分")); XCTAssertTrue(document.sections[0].text.contains("NOTE_GAMMA"))
        XCTAssertTrue(document.sections[1].text.contains("第一部分")); XCTAssertTrue(document.sections[2].text.contains("NOTE_BETA"))
    }
    func testBlankPresentationIsNotReportedAsReadable() throws {
        XCTAssertThrowsError(try parse("blank.pptx")) { XCTAssertTrue($0.localizedDescription.contains("未识别到")) }
    }
    func testLegacyPowerPointParsesIndependentOfficeFixture() throws {
        let document = try parse("legacy-basic.ppt")
        XCTAssertEqual(document.format, "PPT"); XCTAssertGreaterThan(document.pageCount ?? 0, 0)
        XCTAssertTrue(document.sections[0].text.contains("This is on page 1")); XCTAssertTrue(document.sections[1].text.contains("This is page two"))
    }
    func testLegacyPPTReorderedFileAndEncryptedFile() throws {
        let document = try parse("legacy-reordered.ppt")
        XCTAssertEqual(document.pageCount, 3); XCTAssertTrue(document.sections[1].text.contains("Third slide I added")); XCTAssertTrue(document.sections[2].text.contains("Second slide I added"))
        XCTAssertThrowsError(try parse("legacy-encrypted.ppt")) { XCTAssertTrue($0.localizedDescription.contains("密码") || $0.localizedDescription.contains("加密")) }
        XCTAssertThrowsError(try SourceImport.parse(Data(repeating: 0, count: 1024), extension: "ppt"))
    }
    func testSpreadsheetPreservesSparseCellsFormulaAndSheets() throws {
        let document = try parse("lesson.xlsx")
        XCTAssertEqual(document.sections.map(\.title), ["物理", "化学"])
        XCTAssertTrue(document.text.contains("C2: 公式：=A2*2")); XCTAssertTrue(document.text.contains("B4: 原子")); XCTAssertTrue(document.text.contains("D3: TRUE"))
    }
    func testPDFTextPagesAndPasswordFailure() throws {
        let document = try parse("lesson.pdf")
        XCTAssertEqual(document.pageCount, 3); XCTAssertFalse(document.usedOCR)
        XCTAssertTrue(document.sections[0].text.contains("Evaporation")); XCTAssertTrue(document.sections[2].text.contains("Precipitation"))
        XCTAssertThrowsError(try parse("locked.pdf")) { XCTAssertTrue($0.localizedDescription.contains("密码")) }
    }
    func testScannedPDFIsRecognizedLocally() throws {
        let document = try parse("scanned.pdf")
        XCTAssertTrue(document.usedOCR); XCTAssertTrue(document.text.uppercased().contains("WATER CYCLE")); XCTAssertNotNil(document.notice)
    }
    func testRTFAndLegacyWordNativeReaders() throws {
        let text = NSAttributedString(string: "Physics lesson: momentum is conserved.\n第二行：动量守恒。")
        for (ext, type) in [("rtf", NSAttributedString.DocumentType.rtf), ("doc", .docFormat)] {
            let data = try text.data(from: NSRange(location: 0, length: text.length), documentAttributes: [.documentType: type])
            let document = try SourceImport.parse(data, extension: ext)
            XCTAssertTrue(document.text.contains("momentum")); XCTAssertTrue(document.text.contains("动量守恒"))
        }
    }
    func testHTMLDoesNotIncludeScriptsOrRemoteResources() throws {
        let document = try parse("page.html")
        XCTAssertTrue(document.text.contains("太阳能")); XCTAssertTrue(document.text.contains("光合作用 & 叶绿体"))
        XCTAssertFalse(document.text.contains("DO_NOT_EXECUTE")); XCTAssertFalse(document.text.contains("tracker"))
    }
    func testMalformedZIPTraversalAndXMLAreRejected() throws {
        XCTAssertThrowsError(try parse("unsafe.docx")); XCTAssertThrowsError(try parse("entity.docx"))
        XCTAssertThrowsError(try SourceImport.parse(Data("not a zip".utf8), extension: "docx"))
        let entity = "<?xml version=\"1.0\" encoding=\"UTF-16\"?><!DOCTYPE document [<!ENTITY x \"expanded\">]><document>&x;</document>"
        XCTAssertThrowsError(try DocumentXML.parse(entity.data(using: .utf16)!))
    }
    func testLargeOrEmptyTextDoesNotSilentlyTruncate() throws {
        XCTAssertThrowsError(try SourceImport.parse(Data(String(repeating: "中", count: SourceImport.maxCharacters + 1).utf8), extension: "md"))
        XCTAssertThrowsError(try SourceImport.parse(Data(), extension: "txt"))
        let root = try directory(), unsupported = root.appendingPathComponent("unsupported.exe")
        try Data([1, 2, 3]).write(to: unsupported); XCTAssertThrowsError(try SourceImport.read(unsupported))
    }
    func testOriginalDocumentAndExtractedTextSurviveBackupAndDedupe() throws {
        let root = try directory(), db = try LibraryDatabase(root: root.appendingPathComponent("library"))
        let asset = try db.importSource(fixture("lesson.docx"), existing: [])
        XCTAssertFalse(asset.isImage); XCTAssertEqual(try Data(contentsOf: db.assetURL(asset)), try Data(contentsOf: fixture("lesson.docx")))
        XCTAssertEqual(try db.importSource(fixture("lesson.docx"), existing: [asset]).id, asset.id)
        var state = LibraryState(); state.assets = [asset]; try db.save(state)
        let backup = root.appendingPathComponent("backup"); try db.exportBackup(state, to: backup)
        let restored = try LibraryDatabase(root: root.appendingPathComponent("restored")); let result = try restored.readBackup(from: backup)
        XCTAssertEqual(result.assets.first?.document, asset.document); XCTAssertEqual(result.assets.first?.digest, asset.digest); XCTAssertEqual(result.assets.first?.id, asset.id); XCTAssertEqual(try Data(contentsOf: restored.assetURL(asset)), try Data(contentsOf: fixture("lesson.docx")))
    }
    func testOldImageMetadataStillDecodes() throws {
        let old = "{\"id\":\"old\",\"filename\":\"old.png\",\"displayName\":\"old.png\",\"digest\":\"hash\",\"generated\":false,\"createdAt\":0}"
        let asset = try JSONDecoder().decode(SourceAsset.self, from: Data(old.utf8))
        XCTAssertTrue(asset.isImage); XCTAssertNil(asset.document); XCTAssertNil(asset.byteCount)
    }
    func testMultipleDocumentContextBudgetAndExclusion() throws {
        let document = SourceDocument(format: "TXT", sections: [SourceSection(title: "", text: String(repeating: "字", count: 100_000))])
        var first = SourceAsset(filename: "one.txt", displayName: "one", digest: "one"); first.document = document
        var second = first; second.id = "two"
        XCTAssertThrowsError(try SourceImport.validateContext([first, second])); XCTAssertNoThrow(try SourceImport.validateContext([first]))
        var chat = Conversation(); chat.messages = [ChatMessage(role: "user", text: "first", assetIDs: [first.id]), ChatMessage(role: "user", text: "second", assetIDs: [second.id])]
        chat.contextPreferences = ContextPreferences(); chat.contextPreferences?.includeHistoricalImages = false
        XCTAssertEqual(ConversationContext.includedAssetIDs(chat), [second.id])
    }
    @MainActor func waitForImport(_ model: AppModel, timeout: Double = 15) async throws {
        for _ in 0..<Int(timeout * 20) { if model.importStatus == nil { return }; try await Task.sleep(for: .milliseconds(50)) }
        XCTFail("Import did not finish"); model.cancelImport()
    }
    @MainActor func testSwitchConversationDuringImportPreservesOwnerAndDraft() async throws {
        let model = AppModel(dataDirectory: try directory())
        let a = Conversation(id: "import-owner"), b = Conversation(id: "other", draft: "保留这里的草稿")
        model.library.conversations = [a, b]; model.conversationID = a.id; model.composer = "整理这些资料"
        model.importSources([try fixture("lesson.md"), try fixture("lesson.docx")]); model.selectConversation(b.id)
        try await waitForImport(model)
        XCTAssertEqual(model.conversationID, b.id); XCTAssertEqual(model.composer, "保留这里的草稿"); XCTAssertTrue(model.attachments.isEmpty)
        let owner = try XCTUnwrap(model.library.conversations.first { $0.id == a.id })
        XCTAssertEqual(owner.draftAssetIDs?.count, 2); XCTAssertEqual(owner.draft, "整理这些资料")
        XCTAssertTrue(model.context(for: Conversation(messages: [ChatMessage(role: "user", text: "Read", assetIDs: owner.draftAssetIDs ?? [])])).contains("水蒸气形成水滴"))
    }
    @MainActor func testMixedBatchRetainsValidFilesAndReportsFailures() async throws {
        let model = AppModel(dataDirectory: try directory())
        model.importSources([try fixture("lesson.md"), try fixture("unsafe.docx")]); try await waitForImport(model)
        XCTAssertEqual(model.attachments.count, 1); XCTAssertEqual(model.library.assets.count, 1)
        XCTAssertTrue(model.error?.contains("unsafe.docx") == true)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: model.database!.assetsURL.path).count, 1)
    }
    @MainActor func testCancelledImportDoesNotLeaveFilesOrAttachments() async throws {
        let model = AppModel(dataDirectory: try directory())
        model.importSources([try fixture("scanned.pdf")]); model.cancelImport(); try await waitForImport(model)
        XCTAssertTrue(model.attachments.isEmpty); XCTAssertTrue(model.library.assets.isEmpty)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: model.database!.assetsURL.path).isEmpty)
    }
}

extension SourceImportTests {
    func testLongReadingSlicesPreserveEveryCharacterAndHeading() throws {
        let document = SourceDocument(format: "Markdown", sections: [
            SourceSection(title: "第一节", text: String(repeating: "中文 👩🏽‍💻 e\u{301} 原文。\n\n", count: 4000)),
            SourceSection(title: "第二节", text: String(repeating: "没有换行的一段长文", count: 1300)),
            SourceSection(title: "空白节", text: "")])
        let slices = try SourceReadingSlice.make(document)
        XCTAssertGreaterThan(slices.count, 10)
        XCTAssertTrue(slices.allSatisfy { $0.text.count <= 3000 })
        for (index, section) in document.sections.enumerated() {
            let group = slices.filter { $0.section == index }
            XCTAssertEqual(group.map(\.text).joined(), section.text)
            XCTAssertEqual(group.filter(\.startsSection).map(\.title), [section.title])
            XCTAssertTrue(group.dropFirst().allSatisfy { $0.title.isEmpty })
        }
    }
    func testCancelledControlStopsDocumentBeforeParsing() throws {
        let control = SourceImportControl(); control.cancel()
        XCTAssertThrowsError(try SourceImport.read(fixture("scanned.pdf"), control: control)) { XCTAssertTrue($0 is CancellationError) }
    }
    func testPDFProgressAndBoundedRendering() throws {
        let control = SourceImportControl()
        let document = try SourceImport.read(fixture("lesson.pdf"), control: control).1
        XCTAssertEqual(document?.pageCount, 3); XCTAssertEqual(control.progress, "第 3/3 页")
        let pdf = try XCTUnwrap(PDFDocument(url: fixture("scanned.pdf")))
        defer { withExtendedLifetime(pdf) {} }
        let page = try XCTUnwrap(pdf.page(at: 0))
        let ref = try XCTUnwrap(page.pageRef)
        let image = try SourceImport.renderPage(ref, maxPixelSize: 800)
        XCTAssertEqual(max(image.width, image.height), 800)
        XCTAssertLessThan(image.bytesPerRow * image.height, 800 * 800 * 5)
    }
    func testPDFRenderingUpscalesArtworkWithPageRotationAndOrigin() throws {
        let data = NSMutableData()
        var bounds = CGRect(x: 50, y: 80, width: 100, height: 160)
        let consumer = try XCTUnwrap(CGDataConsumer(data: data))
        let pdfContext = try XCTUnwrap(CGContext(consumer: consumer, mediaBox: &bounds, nil))
        pdfContext.beginPDFPage(nil)
        pdfContext.setFillColor(CGColor(gray: 0, alpha: 1))
        pdfContext.fill(bounds.insetBy(dx: 10, dy: 16))
        pdfContext.endPDFPage(); pdfContext.closePDF()
        for angle in [0, 90, 180, 270] {
            let document = try XCTUnwrap(PDFDocument(data: data as Data))
            document.page(at: 0)?.rotation = angle
            let provider = try XCTUnwrap(CGDataProvider(data: try XCTUnwrap(document.dataRepresentation()) as CFData))
            let native = try XCTUnwrap(CGPDFDocument(provider))
            let page = try XCTUnwrap(native.page(at: 1))
            let image = try SourceImport.renderPage(page, maxPixelSize: 800)
            let rotated = angle % 180 == 90
            XCTAssertEqual(image.width, rotated ? 800 : 500)
            XCTAssertEqual(image.height, rotated ? 500 : 800)
            let gray = try XCTUnwrap(CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue))
            gray.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            let pixels = try XCTUnwrap(gray.data).assumingMemoryBound(to: UInt8.self)
            for x in [0.2, 0.8] { for y in [0.2, 0.8] {
                XCTAssertLessThan(pixels[Int(y * Double(image.height)) * image.width + Int(x * Double(image.width))], 20, "Artwork must fill the rendered page at rotation \(angle)")
            } }
            XCTAssertGreaterThan(pixels[image.width / 20 + image.width * (image.height / 20)], 240)
        }
    }
    func testReimportUsesSavedExtractionAndRestoresMissingOriginal() throws {
        let database = try LibraryDatabase(root: directory()), url = try fixture("scanned.pdf")
        let first = try database.importSource(url, existing: [])
        XCTAssertTrue(first.document?.usedOCR == true)
        let control = SourceImportControl()
        let second = try database.importSource(url, existing: [first], control: control)
        XCTAssertEqual(second, first); XCTAssertNil(control.progress, "A known original must not rerun per-page extraction or OCR")
        try FileManager.default.removeItem(at: database.assetURL(first))
        let restored = try database.importSource(url, existing: [first])
        XCTAssertEqual(restored, first)
        XCTAssertEqual(try Data(contentsOf: database.assetURL(restored)), try Data(contentsOf: url))
    }
    func testCancelledXMLParserReturnsCancellationInsteadOfMalformedError() async throws {
        let task = Task.detached { () throws -> DocumentXML in
            while !Task.isCancelled { await Task.yield() }
            return try DocumentXML.parse(Data(("<document>" + String(repeating: "<p>内容</p>", count: 20_000) + "</document>").utf8))
        }
        task.cancel()
        do { _ = try await task.value; XCTFail("Expected cancellation") } catch is CancellationError {} catch { XCTFail("Unexpected error: \(error)") }
    }
    @MainActor func testTwentyLargeTextsDoNotBlockMainActorOrLoseDraft() async throws {
        let root = try directory(), model = AppModel(dataDirectory: root.appendingPathComponent("Library"))
        let body = String(repeating: "原文与公式保留。Water cycle lesson.\n", count: 3500)
        XCTAssertLessThan(body.count, SourceImport.maxCharacters)
        let files = try await ImagePipeline.offMain {
            try (0..<20).map { index in
                let url = root.appendingPathComponent("large-\(index)." + (index.isMultiple(of: 2) ? "md" : "txt"))
                try ("File \(index)\n" + body).write(to: url, atomically: true, encoding: .utf8)
                return url
            }
        }
        var largestGap = 0.0, last = Date(), ticks = 0
        let heartbeat = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(5))
                let now = Date(); largestGap = max(largestGap, now.timeIntervalSince(last)); last = now; ticks += 1
            }
        }
        defer { heartbeat.cancel() }
        let start = Date(); model.composer = "保留这份草稿"; model.importSources(files)
        for _ in 0..<800 { if model.importStatus == nil { break }; try await Task.sleep(for: .milliseconds(25)) }
        heartbeat.cancel(); await heartbeat.value
        XCTAssertNil(model.importStatus); XCTAssertNil(model.error)
        XCTAssertEqual(model.attachments.count, 20); XCTAssertEqual(model.composer, "保留这份草稿")
        XCTAssertEqual(try model.database!.load().assets.count, 20)
        XCTAssertGreaterThan(ticks, 1); XCTAssertLessThan(largestGap, 0.75)
        print("DOCUMENT_BATCH_METRICS seconds=\(Date().timeIntervalSince(start)) maxMainActorGapSeconds=\(largestGap) ticks=\(ticks)")
    }
}


extension SourceImportTests {
    func testMixedPDFReadsNativeTextAndDirectNestedAndInlineImages() throws {
        let document = try parse("mixed-content.pdf")
        XCTAssertEqual(document.pageCount, 3); XCTAssertTrue(document.usedOCR)
        for (index, mode) in ["direct", "form", "inline"].enumerated() {
            let text = document.sections[index].text
            XCTAssertTrue(text.contains("19.625 and 7319; mode " + mode))
            XCTAssertTrue(text.contains("RASTER SOURCE ALPHA"), "Missing raster text on \(mode) page")
            XCTAssertTrue(text.contains("END OF IMAGE 7319"))
            XCTAssertEqual(text.components(separatedBy: "Native text must stay exact:").count, 2)
        }
    }
    func testPDFSupplementPreservesNativeNumbersAndDistinctMathSigns() {
        let native = "Balance 19.625\na+b\nx=10"
        let merged = SourceImport.mergeRecognizedText("Balance 19.625\na-b\nx=1\nX=10\nExtra line", into: native)
        XCTAssertTrue(merged.hasPrefix(native)); XCTAssertTrue(merged.contains("a-b"))
        XCTAssertTrue(merged.contains("X=10")); XCTAssertTrue(merged.contains("Extra line")); XCTAssertTrue(merged.components(separatedBy: "\n").contains("x=1"))
    }
    func testWordKeepsFractionExponentAndFirstFootnote() throws {
        let document = try parse("structured-math.docx")
        XCTAssertTrue(document.text.contains("\\frac{1}{2}")); XCTAssertTrue(document.text.contains("{x}^{2}"))
        XCTAssertTrue(document.text.contains("FIRST_FOOTNOTE 9327")); XCTAssertFalse(document.text.contains("NOT_A_NOTE"))
        XCTAssertTrue(document.text.contains("WORD SOURCE BETA END")); XCTAssertTrue(document.text.contains("H_{2}O; power ^{3}"))
    }
    func testUnsupportedMathIsIdentifiedInsteadOfFlattenedAsReliable() throws {
        let xml = try DocumentXML.parse(Data("<oMath><m><mr><e><r><t>matrix entry</t></r></e></mr></m></oMath>".utf8))
        let math = try XCTUnwrap(xml.all("oMath").first)
        XCTAssertTrue(SourceImport.mathText(math).contains("复杂公式结构请对照原件"))
    }
    @MainActor func testReimportRefreshesOldExtractionWithoutChangingSourceIdentity() async throws {
        let model = AppModel(dataDirectory: try directory())
        let original = try model.database!.importSource(fixture("mixed-content.pdf"), existing: [])
        var old = original; old.document?.extractionVersion = nil; old.document?.sections = [SourceSection(title: "旧提取", text: "缺少插图")]
        model.library.assets = [old]
        model.importSources([try fixture("mixed-content.pdf")]); try await waitForImport(model, timeout: 60)
        XCTAssertNil(model.error)
        let updated = try XCTUnwrap(model.library.assets.first)
        XCTAssertEqual(updated.id, original.id); XCTAssertEqual(updated.filename, original.filename); XCTAssertEqual(updated.digest, original.digest)
        XCTAssertEqual(updated.document, original.document); XCTAssertEqual(model.library.assets.count, 1)
        XCTAssertEqual(try model.database!.load().assets.first?.document, original.document)
        XCTAssertEqual(try Data(contentsOf: model.database!.assetURL(updated)), try Data(contentsOf: fixture("mixed-content.pdf")))
    }
    @MainActor func testMixedDocumentsWithSameDisplayNameRemainBoundToTheirSourceAfterRestart() async throws {
        let root = try directory(), model = AppModel(dataDirectory: root.appendingPathComponent("Library"))
        let a = root.appendingPathComponent("A"), b = root.appendingPathComponent("B")
        try FileManager.default.createDirectory(at: a, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: b, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: fixture("mixed-content.pdf"), to: a.appendingPathComponent("lesson.pdf"))
        try FileManager.default.copyItem(at: fixture("lesson.pdf"), to: b.appendingPathComponent("lesson.pdf"))
        model.importSources([a.appendingPathComponent("lesson.pdf"), try fixture("structured-math.docx"), b.appendingPathComponent("lesson.pdf"), try fixture("lesson.pptx"), try fixture("lesson.md")])
        // The first Vision OCR call may load system recognition models after a cold boot.
        try await waitForImport(model, timeout: 60); XCTAssertNil(model.error); XCTAssertEqual(model.attachments.count, 5)
        guard model.attachments.count == 5 else { return }
        let state = try model.database!.load()
        let chat = Conversation(messages: [ChatMessage(role: "user", text: "继续整理", assetIDs: model.attachments)])
        let prompt = model.context(for: chat)
        let start = try XCTUnwrap(prompt.firstIndex(of: "{")), end = try XCTUnwrap(prompt.lastIndex(of: "}"))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(prompt[start...end].utf8)) as? [String: Any])
        let sources = try XCTUnwrap(json["sourceAssets"] as? [[String: Any]])
        XCTAssertEqual(sources.count, 5)
        for original in state.assets {
            let source = try XCTUnwrap(sources.first { $0["id"] as? String == original.id })
            XCTAssertEqual(source["displayName"] as? String, original.displayName)
            let document = try XCTUnwrap(source["document"] as? [String: Any])
            let sections = try XCTUnwrap(document["sections"] as? [[String: String]])
            XCTAssertEqual(sections.map { $0["text"] ?? "" }, original.document?.sections.map(\.text))
        }
        let duplicates = state.assets.filter { $0.displayName == "lesson.pdf" }
        XCTAssertEqual(duplicates.count, 2); guard duplicates.count == 2 else { return }; XCTAssertNotEqual(duplicates[0].id, duplicates[1].id)
        XCTAssertNotEqual(duplicates[0].document?.text, duplicates[1].document?.text)
    }
}


extension SourceImportTests {
    func testHTMLPreservesCellBoundariesAndEscapedUnicodeAndMath() throws {
        let html = "<table><tr><td>Mass</td><td>12</td></tr><tr><td>Force</td><td>2 &times; 3</td></tr></table><p>&#20013;&#x6587; &le; 9 &amp;lt; &unknown;</p>"
        let document = try SourceImport.parse(Data(html.utf8), extension: "html")
        XCTAssertTrue(document.text.contains("Mass\t12")); XCTAssertTrue(document.text.contains("Force\t2 × 3"))
        XCTAssertTrue(document.text.contains("中文 ≤ 9 &lt; &unknown;"))
        XCTAssertFalse(document.text.contains("Mass12"))
    }
}


extension SourceImportTests {
    func testLegacyPDFStoredAsPNGIsRecoveredWithAllPagesAndSameIdentity() throws {
        let database = try LibraryDatabase(root: directory())
        let bytes = try Data(contentsOf: fixture("lesson.pdf"))
        let original = try database.importSource(fixture("lesson.pdf"), existing: [])
        var legacy = original; legacy.document = nil; legacy.filename = legacy.id + ".png"
        try FileManager.default.moveItem(at: database.assetURL(original), to: database.assetURL(legacy))
        let repaired = try database.refreshedSource(legacy)
        XCTAssertEqual(repaired.id, original.id); XCTAssertEqual(repaired.digest, original.digest)
        XCTAssertFalse(repaired.isImage); XCTAssertEqual(repaired.document?.pageCount, 3)
        XCTAssertTrue(repaired.document?.sections[2].text.contains("Precipitation") == true)
        XCTAssertEqual(try Data(contentsOf: database.assetURL(repaired)), bytes)
        XCTAssertTrue(FileManager.default.fileExists(atPath: database.assetURL(legacy).path), "Keep old copy until state commits")
        var state = LibraryState(); state.assets = [repaired]; try database.save(state)
        database.removeSupersededOriginal(legacy, replacedBy: repaired)
        XCTAssertFalse(FileManager.default.fileExists(atPath: database.assetURL(legacy).path))
        XCTAssertEqual(try Data(contentsOf: database.assetURL(try XCTUnwrap(database.load().assets.first))), bytes)
    }
}
