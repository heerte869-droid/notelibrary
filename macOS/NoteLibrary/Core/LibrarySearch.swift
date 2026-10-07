import Foundation

/// Local search uses the same text for filtering, excerpts and destination anchors.
/// It never rewrites the saved note or sends search terms to a provider.
enum LibrarySearch {
    struct Hit: Identifiable, Equatable {
        var id: String
        var text: String
        var label: String
        var messageID: String? = nil
    }
    private static let plainCache: NSCache<NSString, NSString> = {
        let cache = NSCache<NSString, NSString>(); cache.countLimit = 600
        cache.totalCostLimit = 4 * 1024 * 1024
        return cache
    }()
    static func query(_ value: String) -> String { value.trimmingCharacters(in: .whitespacesAndNewlines) }
    static func plain(_ value: String) -> String {
        guard value.contains(where: { "*_`[".contains($0) }) else { return value }
        if let cached = plainCache.object(forKey: value as NSString) { return cached as String }
        let parsed = (try? AttributedString(markdown: value, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(value)
        let result = String(parsed.characters)
        plainCache.setObject(result as NSString, forKey: value as NSString, cost: value.utf8.count + result.utf8.count)
        return result
    }
    static func ranges(in text: String, query value: String) -> [Range<String.Index>] {
        let term = query(value)
        guard !term.isEmpty, !text.isEmpty else { return [] }
        var cursor = text.startIndex
        var result: [Range<String.Index>] = []
        while cursor < text.endIndex, let range = text.range(of: term, options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], range: cursor..<text.endIndex) {
            guard range.upperBound > cursor else { break }
            result.append(range); cursor = range.upperBound
        }
        return result
    }
    static func matches(_ text: String, query value: String) -> Bool {
        let term = query(value)
        return !term.isEmpty && plain(text).range(of: term, options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive]) != nil
    }
    static func snippet(_ source: String, query value: String, limit: Int = 100) -> String {
        let text = plain(source).split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard !text.isEmpty else { return "" }
        let term = query(value)
        let match = term.isEmpty ? nil : text.range(of: term, options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive])
        let budget = max(24, limit, match.map { text.distance(from: $0.lowerBound, to: $0.upperBound) + 16 } ?? 0)
        let before = min(18, budget / 5)
        var start = match.map { text.index($0.lowerBound, offsetBy: -before, limitedBy: text.startIndex) ?? text.startIndex } ?? text.startIndex
        // Avoid opening an excerpt halfway through an English word. Do not
        // extend a URL or an unbroken identifier into an unbounded preview.
        if start > text.startIndex {
            var candidate = start
            for _ in 0..<16 {
                let previous = text.index(before: candidate)
                guard text[candidate].isASCIIWord, text[previous].isASCIIWord else { break }
                candidate = previous
                if candidate == text.startIndex { break }
            }
            if candidate == text.startIndex || !text[text.index(before: candidate)].isASCIIWord { start = candidate }
            else if let hit = match {
                while start < hit.lowerBound && text[start].isASCIIWord { start = text.index(after: start) }
            }
        }
        let end = text.index(start, offsetBy: budget, limitedBy: text.endIndex) ?? text.endIndex
        return (start > text.startIndex ? "…" : "") + text[start..<end] + (end < text.endIndex ? "…" : "")
    }
    static func blockFields(_ block: ContentBlock) -> [String] {
        [block.text, block.detail] + block.rows.map { $0.joined(separator: " · ") } + [block.diagram?.accessibleDescription ?? ""]
    }
    static func blockMatches(_ block: ContentBlock, query: String) -> Bool { blockFields(block).contains { matches($0, query: query) } }
    static func noteHits(_ note: Note, query: String) -> [Hit] {
        guard !Self.query(query).isEmpty else { return [] }
        // A matching passage is the most useful preview, even when the title also matches.
        var hits = note.blocks.compactMap { block -> Hit? in
            guard let field = blockFields(block).first(where: { matches($0, query: query) }) else { return nil }
            return Hit(id: block.id, text: field, label: block.kind.label)
        }
        if matches(note.title, query: query) { hits.append(Hit(id: "title-" + note.id, text: note.title, label: "标题")) }
        let tags = note.tags.filter { matches($0, query: query) }
        if !tags.isEmpty { hits.append(Hit(id: "tags-" + note.id, text: tags.map { "#" + $0 }.joined(separator: "  "), label: "标签")) }
        return hits
    }
    static func noteMatches(_ note: Note, query: String) -> Bool {
        matches(note.title, query: query) || note.tags.contains { matches($0, query: query) } || note.blocks.contains { blockMatches($0, query: query) }
    }
    static func paragraphs(_ text: String) -> [String] { text.components(separatedBy: "\n\n") }
    static func messageAnchor(_ id: String, paragraph: Int) -> String { "search-message-" + id + "-" + String(paragraph) }
    static func conversationHits(_ chat: Conversation, query: String) -> [Hit] {
        guard !Self.query(query).isEmpty else { return [] }
        return chat.messages.flatMap { message in
            paragraphs(message.text).enumerated().compactMap { index, paragraph -> Hit? in
                guard matches(paragraph, query: query) else { return nil }
                return Hit(id: messageAnchor(message.id, paragraph: index), text: paragraph,
                           label: message.role == "user" ? "你的消息" : "AI 回复", messageID: message.id)
            }
        }
    }
    static func conversationMatches(_ chat: Conversation, query: String, draft: Bool = false) -> Bool {
        if draft { return matches(chat.draftTitle, query: query) || matches(chat.draft, query: query) }
        return matches(chat.title, query: query) || chat.messages.contains { matches($0.text, query: query) }
    }
}

private extension Character {
    var isASCIIWord: Bool { unicodeScalars.allSatisfy { $0.isASCII && (CharacterSet.alphanumerics.contains($0) || $0 == "_") } }
}
