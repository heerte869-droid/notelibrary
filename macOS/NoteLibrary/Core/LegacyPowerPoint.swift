import Foundation

// PowerPoint 97–2003: follow the live persist directory, never resurrect deleted slide records.
enum LegacyPowerPoint {
    struct Record { var type: Int; var instance: Int; var container: Bool; var start: Int; var end: Int }
    static func read(_ bytes: Data) throws -> SourceDocument {
        let file = try CompoundDocument(bytes)
        let data = try file.stream("PowerPoint Document"), user = try file.stream("Current User")
        guard user.count >= 20, user.le32(12) == 0xe391c05f else { throw SourceImport.failure("旧版 PPT 已加密或无法读取，请解除密码后导入。") }
        func record(_ offset: Int, limit: Int? = nil) throws -> Record {
            try Task.checkCancellation()
            let bound = limit ?? data.count
            guard offset >= 0, offset + 8 <= bound else { throw SourceImport.failure("PPT 记录不完整。") }
            let end = offset + 8 + Int(data.le32(offset + 4))
            guard end <= bound else { throw SourceImport.failure("PPT 内容被截断。") }
            return Record(type: data.le16(offset + 2), instance: data.le16(offset) >> 4, container: data.le16(offset) & 15 == 15, start: offset + 8, end: end)
        }
        func children(_ parent: Record) throws -> [Record] {
            var offset = parent.start, result: [Record] = []
            while offset < parent.end { let item = try record(offset, limit: parent.end); result.append(item); offset = item.end }
            return result
        }
        var edit = Int(user.le32(16)), seen = Set<Int>(), persist: [UInt32: Int] = [:], documentID: UInt32?
        while true {
            try Task.checkCancellation()
            guard seen.insert(edit).inserted, seen.count <= 2000 else { throw SourceImport.failure("PPT 编辑记录损坏。") }
            let atom = try record(edit)
            guard atom.type == 4085, atom.end - atom.start >= 28 else { throw SourceImport.failure("PPT 版本记录无法读取。") }
            if documentID == nil { documentID = data.le32(atom.start + 16) }
            if atom.end - atom.start >= 32, data.le32(atom.start + 28) != 0 { throw SourceImport.failure("PPT 已加密，请解除密码保护后导入。") }
            let directory = try record(Int(data.le32(atom.start + 12)))
            guard directory.type == 6002 else { throw SourceImport.failure("PPT 幻灯片目录无法读取。") }
            var cursor = directory.start
            while cursor < directory.end {
                guard cursor + 4 <= directory.end else { throw SourceImport.failure("PPT 幻灯片目录不完整。") }
                let packed = data.le32(cursor), first = packed & 0x000fffff, count = Int(packed >> 20); cursor += 4
                guard count > 0, cursor + count * 4 <= directory.end else { throw SourceImport.failure("PPT 幻灯片目录无效。") }
                for index in 0..<count { let key = first + UInt32(index); if persist[key] == nil { persist[key] = Int(data.le32(cursor + index * 4)) } }
                cursor += count * 4
            }
            let previous = Int(data.le32(atom.start + 8))
            if previous == 0 { break }; edit = previous
        }
        guard let documentID, let offset = persist[documentID] else { throw SourceImport.failure("PPT 缺少当前文档记录。") }
        let document = try record(offset)
        guard document.type == 1000, let list = try children(document).first(where: { $0.type == 4080 && $0.instance == 0 }) else { throw SourceImport.failure("PPT 缺少幻灯片列表。") }
        func text(_ item: Record, depth: Int = 0) throws -> [String] {
            guard depth < 40 else { throw SourceImport.failure("PPT 结构过于复杂，请另存为 PPTX 或 PDF。") }
            if item.type == 4000 {
                let text = String(data: data.subdata(in: item.start..<item.end), encoding: .utf16LittleEndian) ?? ""
                return [SourceImport.clean(text.replacingOccurrences(of: "\u{b}", with: "\n"))]
            }
            if item.type == 4008 {
                // TextBytesAtom stores the low byte of each Unicode character, not UTF-8.
                return [SourceImport.clean(String(data: data.subdata(in: item.start..<item.end), encoding: .isoLatin1) ?? "")]
            }
            return item.container ? try children(item).flatMap { try text($0, depth: depth + 1) } : []
        }
        var sections: [SourceSection] = [], currentID: UInt32?, fragments: [String] = []
        func finish() throws {
            guard let currentID else { return }
            guard let offset = persist[currentID] else { throw SourceImport.failure("PPT 某页幻灯片记录缺失。") }
            let slide = try record(offset)
            guard slide.type == 1006 else { throw SourceImport.failure("PPT 幻灯片记录无效。") }
            let extra = try text(slide).filter { !fragments.contains($0) }
            let content = (fragments + extra).filter { !$0.isEmpty }.joined(separator: "\n")
            sections.append(SourceSection(title: "第 \(sections.count + 1) 页", text: content))
        }
        for item in try children(list) {
            if item.type == 1011 {
                try finish(); guard item.start + 4 <= item.end else { throw SourceImport.failure("PPT 幻灯片编号缺失。") }
                currentID = data.le32(item.start); fragments = []
            } else if currentID != nil { fragments += try text(item) }
        }
        try finish()
        guard !sections.isEmpty, sections.count <= 200 else { throw SourceImport.failure("旧版 PPT 每次最多读取 200 页。") }
        return SourceDocument(format: "PPT", sections: sections, pageCount: sections.count, notice: "已读取当前幻灯片文字；旧版图表与插图请对照原件。")
    }
}

struct CompoundDocument {
    let data: Data
    let sectorSize: Int
    var fat: [UInt32] = []
    var miniFAT: [UInt32] = []
    var directory = Data()
    var miniStream = Data()
    init(_ data: Data) throws {
        self.data = data
        guard data.count >= 512, data.starts(with: [0xd0, 0xcf, 0x11, 0xe0, 0xa1, 0xb1, 0x1a, 0xe1]), data.le16(28) == 0xfffe, [9, 12].contains(data.le16(30)), data.le16(32) == 6 else { throw SourceImport.failure("不是有效的旧版 Office 文件，请检查扩展名。") }
        sectorSize = 1 << data.le16(30)
        let expected = Int(data.le32(44)); guard expected > 0, expected < 20_000 else { throw SourceImport.failure("Office 分配表无效。") }
        var ids = (0..<109).map { data.le32(76 + $0 * 4) }.filter { $0 < 0xfffffffa }
        var next = data.le32(68), seen = Set<UInt32>()
        while next < 0xfffffffa {
            guard seen.insert(next).inserted, seen.count < 2000 else { throw SourceImport.failure("Office 分配表包含循环。") }
            let bytes = try sector(next)
            ids += stride(from: 0, to: sectorSize - 4, by: 4).map { bytes.le32($0) }.filter { $0 < 0xfffffffa }
            next = bytes.le32(sectorSize - 4)
        }
        guard ids.count >= expected, Set(ids.prefix(expected)).count == expected else { throw SourceImport.failure("Office 分配表不完整。") }
        for id in ids.prefix(expected) { let bytes = try sector(id); fat += stride(from: 0, to: sectorSize, by: 4).map { bytes.le32($0) } }
        directory = try chain(data.le32(48), table: fat, size: sectorSize, storage: data, base: sectorSize, limit: 4_000_000)
        guard directory.count >= 128 else { throw SourceImport.failure("Office 文档目录为空。") }
        let miniCount = Int(data.le32(64))
        if miniCount > 0 {
            let mini = try chain(data.le32(60), table: fat, size: sectorSize, storage: data, base: sectorSize, limit: 4_000_000)
            miniFAT = stride(from: 0, to: mini.count - 3, by: 4).map { mini.le32($0) }
            let rootSize = Int(directory.le32(120))
            guard directory.le32(124) == 0, rootSize <= 100_000_000 else { throw SourceImport.failure("Office 小文件区过大。") }
            miniStream = try chain(directory.le32(116), table: fat, size: sectorSize, storage: data, base: sectorSize, limit: rootSize + sectorSize)
            if miniStream.count > rootSize { miniStream.count = rootSize }
        }
    }
    private func sector(_ id: UInt32) throws -> Data {
        let start = (Int(id) + 1) * sectorSize
        guard start >= sectorSize, start <= data.count, sectorSize <= data.count - start else { throw SourceImport.failure("Office 文件扇区缺失。") }
        return data.subdata(in: start..<start + sectorSize)
    }
    private func chain(_ first: UInt32, table: [UInt32], size: Int, storage: Data, base: Int, limit: Int) throws -> Data {
        var next = first, result = Data(), seen = Set<UInt32>()
        while next != 0xfffffffe {
            try Task.checkCancellation()
            guard Int(next) < table.count, seen.insert(next).inserted, result.count + size <= limit else { throw SourceImport.failure("Office 文件链无效或内容过大。") }
            let start = base + Int(next) * size
            guard start <= storage.count, size <= storage.count - start else { throw SourceImport.failure("Office 文件被截断。") }
            result.append(storage.subdata(in: start..<start + size)); next = table[Int(next)]
        }
        return result
    }
    func stream(_ name: String) throws -> Data {
        for offset in stride(from: 0, through: directory.count - 128, by: 128) {
            let length = directory.le16(offset + 64)
            guard length >= 2, length <= 64, directory[offset + 66] == 2 else { continue }
            let title = String(data: directory.subdata(in: offset..<offset + length - 2), encoding: .utf16LittleEndian)
            if title == name {
                let size = Int(directory.le32(offset + 120)), start = directory.le32(offset + 116)
                guard directory.le32(offset + 124) == 0, size <= 100_000_000 else { throw SourceImport.failure("Office 文档流过大。") }
                if size == 0 { return Data() }
                var result = size < 4096 ? try chain(start, table: miniFAT, size: 64, storage: miniStream, base: 0, limit: size + 64) : try chain(start, table: fat, size: sectorSize, storage: data, base: sectorSize, limit: size + sectorSize)
                guard result.count >= size else { throw SourceImport.failure("Office 文档流不完整。") }; result.count = size; return result
            }
        }
        throw SourceImport.failure("Office 文档缺少 \(name) 内容。")
    }
}
