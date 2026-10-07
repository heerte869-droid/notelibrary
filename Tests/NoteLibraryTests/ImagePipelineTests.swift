import XCTest
import ImageIO
import UniformTypeIdentifiers
@testable import NoteLibrary

final class ImagePipelineTests: XCTestCase {
    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("NoteLibrary-ImageTest-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }
    private func fixture(in directory: URL, name: String = "source", width: Int = 2400, height: Int = 1600, orientation: Int = 1, alpha: Bool = false, type: UTType = .heic, shade: CGFloat = 0.4) throws -> URL {
        try autoreleasepool {
            let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: (alpha ? CGImageAlphaInfo.premultipliedLast : .noneSkipLast).rawValue))
            context.setFillColor(CGColor(red: shade, green: 0.6, blue: 0.3, alpha: alpha ? 0.5 : 1))
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            let image = try XCTUnwrap(context.makeImage())
            let url = directory.appendingPathComponent(name + "." + (type.preferredFilenameExtension ?? "heic"))
            let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil))
            CGImageDestinationAddImage(destination, image, [kCGImagePropertyOrientation: orientation, kCGImageDestinationLossyCompressionQuality: 0.9] as CFDictionary)
            XCTAssertTrue(CGImageDestinationFinalize(destination))
            return url
        }
    }
    func testRotatedHEICThumbnailIsSmallAndUpright() throws {
        let root = try directory(), url = try fixture(in: root, orientation: 6)
        XCTAssertTrue(ImagePipeline.isReadable(try Data(contentsOf: url)))
        let image = try XCTUnwrap(ImagePipeline.thumbnail(url, maxPixelSize: 96))
        XCTAssertEqual(image.width, 64); XCTAssertEqual(image.height, 96)
        XCTAssertLessThan(image.bytesPerRow * image.height, 64 * 1024)
    }
    func testCorruptImagesFailWithoutCachingTheFailure() async throws {
        let root = try directory(), url = root.appendingPathComponent("source.heic")
        try Data("broken image".utf8).write(to: url)
        XCTAssertFalse(ImagePipeline.isReadable(try Data(contentsOf: url)))
        let cache = ImagePreviewCache()
        let missing = await cache.image(url, maxPixelSize: 96)
        XCTAssertNil(missing)
        _ = try fixture(in: root)
        let repaired = await cache.image(url, maxPixelSize: 96)
        XCTAssertNotNil(repaired)
    }
    func testConcurrentPreviewRequestsReuseOneImageAndRespectResolution() async throws {
        let root = try directory(), url = try fixture(in: root), cache = ImagePreviewCache()
        let results = await withTaskGroup(of: CGImage?.self, returning: [CGImage].self) { group in
            for _ in 0..<12 { group.addTask { await cache.image(url, maxPixelSize: 96, revision: "same-source") } }
            var images: [CGImage] = []
            for await image in group { if let image { images.append(image) } }
            return images
        }
        XCTAssertEqual(results.count, 12)
        let first = try XCTUnwrap(results.first)
        XCTAssertTrue(results.allSatisfy { $0 === first })
        let larger = await cache.image(url, maxPixelSize: 360, revision: "same-source")
        XCTAssertEqual(larger?.width, 360)
        try FileManager.default.removeItem(at: url)
        let cached = await cache.image(url, maxPixelSize: 96, revision: "same-source")
        XCTAssertTrue(cached === first)
        let differentRevision = await cache.image(url, maxPixelSize: 96, revision: "changed-source")
        XCTAssertNil(differentRevision)
    }
    func testAIConversionPreservesResolutionOrientationAndOriginalBytes() async throws {
        let root = try directory(), url = try fixture(in: root, orientation: 6)
        let original = try Data(contentsOf: url), folder = root.appendingPathComponent("Prepared")
        let converted = try await ImagePipeline.offMain { try ImagePipeline.prepareForAI(url, folder: folder) }
        XCTAssertEqual(converted.pathExtension, "jpg")
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(converted as CFURL, nil))
        let properties = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        XCTAssertEqual(properties[kCGImagePropertyPixelWidth] as? Int, 1600)
        XCTAssertEqual(properties[kCGImagePropertyPixelHeight] as? Int, 2400)
        XCTAssertEqual(try Data(contentsOf: url), original)
        let firstDate = try converted.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        let again = try await ImagePipeline.offMain { try ImagePipeline.prepareForAI(url, folder: folder) }
        XCTAssertEqual(converted, again)
        XCTAssertEqual(try again.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate, firstDate)
    }
    func testTransparentConversionKeepsAlphaAndNativePNGPassesThrough() async throws {
        let root = try directory(), url = try fixture(in: root, width: 128, height: 64, alpha: true, type: .tiff)
        let folder = root.appendingPathComponent("Prepared")
        let converted = try await ImagePipeline.offMain { try ImagePipeline.prepareForAI(url, folder: folder) }
        XCTAssertEqual(converted.pathExtension, "png")
        let image = try XCTUnwrap(ImagePipeline.thumbnail(converted, maxPixelSize: 128))
        XCTAssertTrue([CGImageAlphaInfo.premultipliedFirst, .premultipliedLast, .first, .last].contains(image.alphaInfo))
        let passed = try await ImagePipeline.offMain { try ImagePipeline.prepareForAI(converted, folder: folder) }
        XCTAssertEqual(passed, converted)
    }
    @MainActor func testPreparationYieldsMainActorAndCancellationPropagates() async throws {
        let started = expectation(description: "Worker started"), release = DispatchSemaphore(value: 0)
        let task = Task {
            try await ImagePipeline.offMain {
                XCTAssertFalse(Thread.isMainThread)
                started.fulfill()
                guard release.wait(timeout: .now() + 3) == .success else { throw AppFailure(message: "Main actor did not stay responsive") }
                return true
            }
        }
        await fulfillment(of: [started], timeout: 2)
        task.cancel(); release.signal()
        do { _ = try await task.value; XCTFail("Cancellation must reach caller") } catch is CancellationError {} catch { throw error }
    }
    @MainActor func testHEICBatchImportAndPreviewsKeepConversationOwnership() async throws {
        let root = try directory()
        let urls = try await ImagePipeline.offMain { [self] in
            try (0..<11).map { try fixture(in: root, name: "photo-\($0)", width: 1024, height: 768, shade: CGFloat($0) / 12) }
        }
        let model = AppModel(dataDirectory: root.appendingPathComponent("Library"))
        let owner = Conversation(id: "owner", draft: "保留原图"), other = Conversation(id: "other", draft: "其他草稿")
        model.library.conversations = [owner, other]; model.conversationID = owner.id; model.composer = owner.draft
        model.importSources(urls); model.selectConversation(other.id)
        for _ in 0..<200 { if model.importStatus == nil { break }; try await Task.sleep(for: .milliseconds(25)) }
        XCTAssertNil(model.importStatus); XCTAssertNil(model.error)
        XCTAssertEqual(model.library.assets.count, 11); XCTAssertEqual(model.composer, "其他草稿")
        XCTAssertTrue(model.attachments.isEmpty)
        XCTAssertEqual(model.library.conversations.first { $0.id == owner.id }?.draftAssetIDs?.count, 11)
        for asset in model.library.assets {
            let image = await ImagePreviewCache.shared.image(model.database!.assetURL(asset), maxPixelSize: 96, revision: asset.digest)
            XCTAssertEqual(image?.width, 96)
            let source = try XCTUnwrap(urls.first { $0.lastPathComponent == asset.displayName })
            XCTAssertEqual(try Data(contentsOf: model.database!.assetURL(asset)), try Data(contentsOf: source))
        }
        let saved = try model.database!.load()
        XCTAssertEqual(saved.conversations.first { $0.id == owner.id }?.draftAssetIDs?.count, 11)
    }
}

extension ImagePipelineTests {
    func testLosslessCodexConversionRetainsDecodedPixelsAndDoesNotReuseJPEG() async throws {
        let root = try directory(), width = 384, height = 256
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        for x in stride(from: 3, to: width, by: 7) {
            context.setFillColor(CGColor(red: CGFloat(x % 3) / 3, green: 0, blue: CGFloat(x % 5) / 5, alpha: 1))
            context.fill(CGRect(x: x, y: 12, width: 1, height: height - 24))
        }
        let originalURL = root.appendingPathComponent("small-writing.heic")
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(originalURL as CFURL, UTType.heic.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, try XCTUnwrap(context.makeImage()), nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        let originalBytes = try Data(contentsOf: originalURL), folder = root.appendingPathComponent("Prepared")
        let jpeg = try await ImagePipeline.offMain { try ImagePipeline.prepareForAI(originalURL, folder: folder) }
        let png = try await ImagePipeline.offMain { try ImagePipeline.prepareForAI(originalURL, folder: folder, lossless: true) }
        XCTAssertEqual(jpeg.pathExtension, "jpg"); XCTAssertEqual(png.pathExtension, "png"); XCTAssertNotEqual(jpeg, png)
        func decodedPixels(_ url: URL) throws -> Data {
            let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
            let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
            XCTAssertEqual(image.width, width); XCTAssertEqual(image.height, height)
            let bitmap = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            bitmap.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return Data(bytes: try XCTUnwrap(bitmap.data), count: width * height * 4)
        }
        XCTAssertEqual(try decodedPixels(originalURL), try decodedPixels(png), "Lossless preparation must not change decoded handwriting pixels")
        XCTAssertNotEqual(try decodedPixels(originalURL), try decodedPixels(jpeg), "This edge fixture must catch an accidental JPEG conversion")
        XCTAssertEqual(try Data(contentsOf: originalURL), originalBytes)
        let again = try await ImagePipeline.offMain { try ImagePipeline.prepareForAI(originalURL, folder: folder, lossless: true) }
        XCTAssertEqual(again, png)
    }
    func testCodexImagesKeepSourceIdentityAfterConversionAndRequestOriginalDetail() throws {
        var first = AIImageInput(url: URL(fileURLWithPath: "/original/one.heic"), sourceID: "source-b", displayName: "同名\"扫描.heic")
        first.url = URL(fileURLWithPath: "/prepared/hash-b.png")
        let second = AIImageInput(url: URL(fileURLWithPath: "/prepared/hash-a.png"), sourceID: "source-a", displayName: "同名\"扫描.heic")
        let inputs = CodexClient.imageInputs([first, second])
        XCTAssertEqual(inputs.count, 4)
        for (index, image) in [first, second].enumerated() {
            XCTAssertEqual(inputs[index * 2]["type"] as? String, "text")
            let text = try XCTUnwrap(inputs[index * 2]["text"] as? String)
            let data = try XCTUnwrap(text.components(separatedBy: "\n").dropFirst().joined(separator: "\n").data(using: .utf8))
            let label = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: String])
            XCTAssertEqual(label["sourceID"], image.sourceID); XCTAssertEqual(label["filename"], image.displayName)
            XCTAssertEqual(label["localPath"], image.url.path)
            XCTAssertEqual(inputs[index * 2 + 1]["path"] as? String, image.url.path)
            XCTAssertEqual(inputs[index * 2 + 1]["detail"] as? String, "original")
        }
    }
}
