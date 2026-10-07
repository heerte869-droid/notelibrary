import Foundation
import NaturalLanguage

struct AINoteReference: Codable, Equatable {
    var noteID: String
    var blockID: String
    var quote: String
}

// The snapshot keeps a citation intelligible after a rename, move or later edit.
// Navigation always resolves the ID against the current library.
struct NoteReference: Codable, Identifiable, Equatable {
    var noteID: String
    var blockID: String
    var title: String
    var location: String
    var quote: String
    var version: Int
    var id: String { noteID }
}

struct RetrievedBlock: Codable, Equatable {
    var id: String
    var text: String
}
struct RetrievedNote: Codable, Equatable {
    var noteID: String
    var title: String
    var location: String
    var version: Int
    var blocks: [RetrievedBlock]
    var excerpted: Bool
}
struct NoteQueryContext {
    var notes: [Note]
    var matches: [RetrievedNote]
    var sources: [RetrievedNote]
}

// Local matching scans the entire allowed library, rather than only recent notes.
// The model can reformulate a query when the first set does not answer the question.
enum NoteRetrieval {
    static let stopWords: Set<String> = Set("我 你 的 了 是 在 和 与 或 及 就 也 把 被 都 有 没有 什么 哪些 怎么 如何 为什么 帮 帮我 请 给 找 查找 找到 找出 检索 搜索 笔记 内容 相关 关于 总结 概括 一下 需要 之前 这些 那些 上面 这个 那个 一个 一些 可以 进行 解释 说明 告诉 根据 一起 分别 还有 the a an of to is are in and or for my me find search notes note please about summarize explain what how this these it".split(separator: " ").map(String.init))
    static func normalized(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: Locale(identifier: "zh_CN"))
    }
    static func terms(_ value: String) -> [String] {
        let text = normalized(String(value.prefix(1200)))
        let tokenizer = NLTokenizer(unit: .word); tokenizer.string = text
        var words: [String] = []
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            let word = String(text[range])
            if !stopWords.contains(word), word.count > 1 || word.unicodeScalars.allSatisfy({ CharacterSet.alphanumerics.contains($0) && $0.value < 128 }) {
                words.append(word)
            }
            return words.count < 80
        }
        return Array(Set(words)).sorted()
    }
    static func blockText(_ block: ContentBlock) -> String {
        ([block.text, block.detail] + block.rows.map { $0.joined(separator: " | ") }).filter { !$0.isEmpty }.joined(separator: "\n")
    }
    static func location(_ note: Note, state: LibraryState) -> String {
        guard let chapter = state.chapters.first(where: { $0.id == note.chapterID }), let book = state.notebooks.first(where: { $0.id == chapter.notebookID }) else { return "未归类" }
        return book.title + " / " + chapter.title
    }
    static func allowedNotes(_ state: LibraryState, chat: Conversation) -> [Note] {
        guard chat.contextPreferences?.includeNoteContents != false else { return [] }
        return LibraryScope.activeNotes(in: state).filter { note in
            chat.notebookID == nil || LibraryScope.book(for: note, in: state)?.id == chat.notebookID
        }
    }
    static func ranked(_ notes: [Note], queries: [String], state: LibraryState, preferredIDs: Set<String> = [], includeUnmatched: Bool = false) -> [Note] {
        let words = terms(queries.joined(separator: " "))
        return notes.compactMap { note -> (Note, Int)? in
            let title = normalized(note.title), body = normalized(note.searchableText), path = normalized(location(note, state: state)), tags = normalized(note.tags.joined(separator: " "))
            var score = preferredIDs.contains(note.id) ? 20 : 0
            for word in words {
                if title.contains(word) { score += 12 }
                if tags.contains(word) { score += 8 }
                if path.contains(word) { score += 3 }
                if body.contains(word) { score += 3 }
            }
            if queries.contains(where: { $0.contains(note.id) || (note.title.count > 1 && normalized($0).contains(title)) }) { score += 80 }
            return score > 0 || includeUnmatched ? (note, score) : nil
        }.sorted {
            if $0.1 != $1.1 { return $0.1 > $1.1 }
            if $0.0.updatedAt != $1.0.updatedAt { return $0.0.updatedAt > $1.0.updatedAt }
            return $0.0.id < $1.0.id
        }.map(\.0)
    }
    static func fullSource(_ note: Note, state: LibraryState) -> RetrievedNote {
        RetrievedNote(noteID: note.id, title: note.title, location: location(note, state: state), version: note.version, blocks: note.blocks.map { RetrievedBlock(id: $0.id, text: blockText($0)) }, excerpted: false)
    }
    static func excerpt(_ text: String, terms: [String], limit: Int = 1600) -> String {
        guard text.count > limit else { return text }
        let match = terms.compactMap { text.range(of: $0, options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive]) }.min { $0.lowerBound < $1.lowerBound }
        let start = match.map { text.index($0.lowerBound, offsetBy: -180, limitedBy: text.startIndex) ?? text.startIndex } ?? text.startIndex
        let end = text.index(start, offsetBy: limit, limitedBy: text.endIndex) ?? text.endIndex
        // No ellipses are injected into evidence, so every accepted quote is original text.
        return String(text[start..<end])
    }
    static func search(_ queries: [String], state: LibraryState, chat: Conversation) -> [RetrievedNote] {
        let clean = Array(queries.map { String($0.trimmingCharacters(in: .whitespacesAndNewlines).prefix(300)) }.filter { !$0.isEmpty }.prefix(4))
        guard !clean.isEmpty else { return [] }
        let words = terms(clean.joined(separator: " "))
        // Round-robin the queries before filling remaining slots, so a broad first
        // topic cannot crowd out the second topic in a comparison question.
        let allowed = allowedNotes(state, chat: chat)
        let groups = clean.map { ranked(allowed, queries: [$0], state: state) }
        var chosen: [Note] = []; var seen = Set<String>()
        for offset in 0..<12 {
            for group in groups where group.indices.contains(offset) {
                if chosen.count < 12, seen.insert(group[offset].id).inserted { chosen.append(group[offset]) }
            }
        }
        var budget = 32_000
        return chosen.compactMap { note in
            guard budget > 0 else { return nil }
            var scored: [(Int, ContentBlock, Int)] = []
            for (index, block) in note.blocks.enumerated() {
                let text = normalized(blockText(block))
                let score = words.filter { text.contains($0) }.count
                scored.append((index, block, score))
            }
            scored.sort { a, b in a.2 == b.2 ? a.0 < b.0 : a.2 > b.2 }
            var blocks: [RetrievedBlock] = []
            for entry in scored.prefix(6) where budget > 0 {
                let text = excerpt(blockText(entry.1), terms: words, limit: min(1600, budget))
                if !text.isEmpty { blocks.append(RetrievedBlock(id: entry.1.id, text: text)); budget -= text.count }
            }
            return RetrievedNote(noteID: note.id, title: note.title, location: location(note, state: state), version: note.version, blocks: blocks, excerpted: true)
        }
    }
    static func prepare(state: LibraryState, chat: Conversation, selectedNoteID: String?) -> NoteQueryContext {
        let query = chat.messages.last { $0.role == "user" }?.text ?? ""
        let recentReferences = ConversationContext.activeMessages(chat).suffix(4).flatMap { $0.noteReferences ?? [] }.map(\.noteID)
        let preferred = Set(recentReferences + [selectedNoteID].compactMap { $0 })
        let ordered = ranked(allowedNotes(state, chat: chat), queries: [query], state: state, preferredIDs: preferred, includeUnmatched: true)
        var budget = 60_000; var notes: [Note] = []
        for note in ordered.prefix(60) {
            let size = (try? JSONCoding.encoder.encode(note).count) ?? Int.max
            // Never truncate an editable note. Very long notes are supplied only
            // as read-only search excerpts and cannot be rewritten from a fragment.
            if size <= budget { notes.append(note); budget -= size }
        }
        let fullIDs = Set(notes.map(\.id))
        let matches = search([query], state: state, chat: chat).filter { !fullIDs.contains($0.noteID) }
        return NoteQueryContext(notes: notes, matches: matches, sources: notes.map { fullSource($0, state: state) } + matches)
    }
    static func validate(_ references: [AINoteReference], sources: [RetrievedNote]) throws -> [NoteReference] {
        guard references.count <= 12 else { throw AppFailure(message: "这次引用过多，请缩小查找范围后重试。") }
        var output: [NoteReference] = []; var seen = Set<String>()
        for reference in references {
            guard let source = sources.first(where: { $0.noteID == reference.noteID }) else { throw AppFailure(message: "回复中的笔记引用无法核对，已停止展示快捷入口。请重试。") }
            let quote = reference.quote.trimmingCharacters(in: .whitespacesAndNewlines)
            if reference.blockID.isEmpty {
                guard quote.isEmpty else { throw AppFailure(message: "引用原文缺少位置，请重试。") }
            } else {
                guard !quote.isEmpty, quote.count <= 400, sources.filter({ $0.noteID == reference.noteID }).contains(where: { $0.blocks.contains(where: { $0.id == reference.blockID && $0.text.contains(quote) }) }) else {
                    throw AppFailure(message: "回复中的摘录与原笔记不一致，请重试。")
                }
            }
            // Dropping a duplicate would shift every later [n] marker to the wrong card.
            guard seen.insert(source.noteID).inserted else { throw AppFailure(message: "回复中的引用编号重复，请重试以获得清楚的来源。") }
            output.append(NoteReference(noteID: source.noteID, blockID: reference.blockID, title: source.title, location: source.location, quote: quote, version: source.version))
        }
        return output
    }
    static func isReadOnlyLookup(_ text: String) -> Bool {
        let value = normalized(text)
        let writes = ["保存为", "保存到", "写入", "修改", "删除", "更新笔记", "补充到", "新增笔记", "整理成", "save", "update", "delete", "rewrite"]
        guard !writes.contains(where: value.contains) else { return false }
        return ["查找", "检索", "帮我找", "找一下", "找出", "找到", "哪些笔记", "哪篇笔记", "哪本笔记", "笔记里的", "笔记中的", "根据笔记", "总结笔记", "怎么记的", "find", "search"].contains(where: value.contains)
    }
    static func validateReadOnly(_ plan: AIPlan, searched: Bool, editableIDs: Set<String>) throws {
        if searched && (plan.action == "write" || !plan.notes.isEmpty) { throw AppFailure(message: "查找笔记只用于阅读和总结，本次没有修改笔记。") }
        if plan.notes.contains(where: { !$0.noteID.isEmpty && !editableIDs.contains($0.noteID) }) { throw AppFailure(message: "尚未取得这篇笔记的完整正文，无法安全修改。请从该笔记打开编辑。") }
    }
    static func unavailableReason(_ reference: NoteReference, state: LibraryState) -> String? {
        guard let note = state.notes.first(where: { $0.id == reference.noteID }) else { return "原笔记已移除" }
        if note.deletedAt != nil { return "笔记在回收站" }
        guard let book = LibraryScope.book(for: note, in: state) else { return "所属笔记本不可用" }
        if book.deletedAt != nil { return "笔记本在回收站" }
        if book.archivedAt != nil { return "笔记本已归档" }
        return nil
    }
}

struct ReferenceReaderSelection: Identifiable {
    var id = makeID()
    var references: [NoteReference]
    var selectedNoteID: String
    var conversationID: String
    var messageID: String
}
struct ReferenceReturn {
    var conversationID: String
    var messageID: String
}

extension ChatMessage {
    var copyText: String {
        let references = noteReferences ?? []
        let notes = references.isEmpty ? "" : "\n\n参考笔记\n" + references.enumerated().map { index, ref in
            "[\(index + 1)] \(ref.title) · \(ref.location)" + (ref.quote.isEmpty ? "" : "\n原文：" + ref.quote)
        }.joined(separator: "\n\n")
        return text + notes + webSourceText
    }
    var webSourceText: String {
        guard let sources = webSources, !sources.isEmpty else { return "" }
        return "\n\n网页来源\n" + sources.map { $0.title + "\n" + $0.url }.joined(separator: "\n\n")
    }
}
