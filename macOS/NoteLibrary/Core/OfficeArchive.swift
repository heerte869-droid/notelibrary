import Foundation
import zlib

// Read bounded entries in memory. Never extract an archive or follow external relationships.
struct OfficeArchive {
    struct Entry { var offset: Int; var compressed: Int; var size: Int; var method: Int; var crc: UInt32 }
    let data: Data
    var entries: [String: Entry] = [:]
    init(_ data: Data) throws {
        self.data = data
        guard data.count >= 22 else { throw SourceImport.failure("Office 文件不完整。") }
        let lower = max(0, data.count - 65_557)
        guard let end = stride(from: data.count - 22, through: lower, by: -1).first(where: { data.le32($0) == 0x06054b50 && $0 + 22 + data.le16($0 + 20) == data.count }) else { throw SourceImport.failure("Office 文件损坏，或文件格式与扩展名不符。") }
        let count = data.le16(end + 10)
        var offset = Int(data.le32(end + 16))
        let directoryEnd = offset + Int(data.le32(end + 12))
        guard data.le16(end + 4) == 0, data.le16(end + 6) == 0, data.le16(end + 8) == count, count > 0, count <= 10_000, directoryEnd <= end else { throw SourceImport.failure("这个 Office 文件过大，或使用了不支持的分卷格式。") }
        var total = 0
        for _ in 0..<count {
            try Task.checkCancellation()
            guard offset + 46 <= directoryEnd, data.le32(offset) == 0x02014b50 else { throw SourceImport.failure("Office 文件目录损坏。") }
            let flags = data.le16(offset + 8), method = data.le16(offset + 10)
            let nameLength = data.le16(offset + 28), extra = data.le16(offset + 30), comment = data.le16(offset + 32)
            let next = offset + 46 + nameLength + extra + comment
            guard next <= directoryEnd, flags & 1 == 0, [0, 8].contains(method) else { throw SourceImport.failure("请先解除文档密码保护，再重新导入。") }
            guard let name = String(data: data.subdata(in: offset + 46..<offset + 46 + nameLength), encoding: .utf8), !name.hasPrefix("/"), !name.contains("\\"), !name.split(separator: "/").contains(".."), entries[name] == nil else { throw SourceImport.failure("Office 文件包含不合法的内部路径。") }
            let size = Int(data.le32(offset + 24)), compressed = Int(data.le32(offset + 20)), local = Int(data.le32(offset + 42))
            total += size
            guard size <= 40_000_000, total <= 200_000_000, local + 30 <= offset, compressed <= data.count else { throw SourceImport.failure("文档解压后的内容过大，请拆分后导入。") }
            entries[name] = Entry(offset: local, compressed: compressed, size: size, method: method, crc: data.le32(offset + 16))
            offset = next
        }
    }
    func read(_ name: String) throws -> Data {
        try Task.checkCancellation()
        guard let entry = entries[name], data.le32(entry.offset) == 0x04034b50 else { throw SourceImport.failure("文档缺少必要内容：\(name)") }
        let start = entry.offset + 30 + data.le16(entry.offset + 26) + data.le16(entry.offset + 28)
        guard start <= data.count, entry.compressed <= data.count - start else { throw SourceImport.failure("Office 文件内容被截断。") }
        let compressed = data.subdata(in: start..<start + entry.compressed)
        var result: Data
        if entry.method == 0 {
            guard compressed.count == entry.size else { throw SourceImport.failure("Office 文件长度校验失败。") }; result = compressed
        } else {
            result = Data(count: max(1, entry.size))
            var stream = z_stream()
            guard inflateInit2_(&stream, -MAX_WBITS, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)) == Z_OK else { throw SourceImport.failure("无法解压文档。") }
            defer { inflateEnd(&stream) }
            let outputSize = result.count
            let status = compressed.withUnsafeBytes { input in result.withUnsafeMutableBytes { output -> Int32 in
                stream.next_in = UnsafeMutablePointer(mutating: input.bindMemory(to: Bytef.self).baseAddress)
                stream.avail_in = uInt(compressed.count)
                stream.next_out = output.bindMemory(to: Bytef.self).baseAddress
                stream.avail_out = uInt(outputSize)
                return inflate(&stream, Z_FINISH)
            } }
            guard status == Z_STREAM_END, stream.total_out == entry.size else { throw SourceImport.failure("Office 文件解压失败或内容超过声明大小。") }
            result.count = entry.size
        }
        try Task.checkCancellation()
        let checksum = result.withUnsafeBytes { crc32(0, $0.bindMemory(to: Bytef.self).baseAddress, uInt(result.count)) }
        guard UInt32(checksum) == entry.crc else { throw SourceImport.failure("Office 文件校验失败，请重新下载原件。") }
        return result
    }
    func xml(_ name: String) throws -> DocumentXML { try DocumentXML.parse(read(name)) }
    func related(to path: String) throws -> [String: String] {
        let components = path.split(separator: "/").map(String.init)
        let parent = components.dropLast().joined(separator: "/")
        let relPath = parent + "/_rels/" + (components.last ?? "") + ".rels"
        guard entries[relPath] != nil else { return [:] }
        var result: [String: String] = [:]
        for node in try xml(relPath).all("Relationship") where node.attributes["TargetMode"] != "External" {
            guard let id = node.attributes["Id"], let target = node.attributes["Target"], !target.contains(":"), !target.contains("\\") else { continue }
            var parts = target.hasPrefix("/") ? [] : Array(components.dropLast())
            for part in target.split(separator: "/").map(String.init) {
                if part == ".." { guard !parts.isEmpty else { throw SourceImport.failure("文档引用路径无效。") }; parts.removeLast() }
                else if part != "." { parts.append(part) }
            }
            let resolved = parts.joined(separator: "/")
            if entries[resolved] != nil { result[id] = resolved }
        }
        return result
    }
}

final class DocumentXML: NSObject, XMLParserDelegate {
    let name: String
    var attributes: [String: String] = [:]
    var text = ""
    var children: [DocumentXML] = []
    init(_ name: String) { self.name = name }
    func all(_ name: String) -> [DocumentXML] { (self.name == name ? [self] : []) + children.flatMap { $0.all(name) } }
    var content: String { text + children.map(\.content).joined() }
    static func parse(_ data: Data) throws -> DocumentXML {
        guard data.count <= 20_000_000 else { throw SourceImport.failure("文档正文过大，请拆分后导入。") }
        // OOXML never requires a DTD. Refuse entities, including internal expansion bombs.
        guard data.range(of: Data("<!DOCTYPE".utf8)) == nil, data.range(of: Data("<!ENTITY".utf8)) == nil else { throw SourceImport.failure("文档 XML 包含不支持的实体声明。") }
        let root = DocumentXML("root"); root.stack = [root]; defer { root.stack = [] }
        let parser = XMLParser(data: data); parser.delegate = root; parser.shouldResolveExternalEntities = false; parser.externalEntityResolvingPolicy = .never
        let parsed = parser.parse(); try Task.checkCancellation()
        guard parsed, !root.exceeded else { throw SourceImport.failure("文档内容无法解析，请确认文件完整。") }
        root.stack = []; return root
    }
    private var stack: [DocumentXML] = []
    private var nodes = 0
    private var exceeded = false
    private var characters = 0
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String]) {
        if Task.isCancelled { parser.abortParsing(); return }
        nodes += 1
        guard nodes <= 200_000, stack.count < 100 else { exceeded = true; parser.abortParsing(); return }
        let node = DocumentXML(elementName.split(separator: ":").last.map(String.init) ?? elementName); node.attributes = attributeDict
        stack.last?.children.append(node); stack.append(node)
    }
    func parser(_ parser: XMLParser, foundCharacters string: String) { if Task.isCancelled { parser.abortParsing(); return }; characters += string.count; if characters > 10_000_000 { exceeded = true; parser.abortParsing() } else { stack.last?.text += string } }
    func parser(_ parser: XMLParser, foundInternalEntityDeclarationWithName name: String, value: String?) { exceeded = true; parser.abortParsing() }
    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) { if stack.count > 1 { stack.removeLast() } }
}

extension Data {
    func le16(_ index: Int) -> Int { guard index >= 0, index + 2 <= count else { return 0 }; return Int(self[index]) | Int(self[index + 1]) << 8 }
    func le32(_ index: Int) -> UInt32 { guard index >= 0, index + 4 <= count else { return 0 }; return UInt32(self[index]) | UInt32(self[index + 1]) << 8 | UInt32(self[index + 2]) << 16 | UInt32(self[index + 3]) << 24 }
}
