import Foundation

enum ConversationContext {
    static func validSummary(_ text: String) -> Bool {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return !clean.isEmpty && !clean.hasPrefix("{") && !clean.hasPrefix("[") && !clean.hasPrefix("```json")
    }
    static func includesTaskContext(_ chat: Conversation) -> Bool {
        chat.contextPreferences?.includeHistory != false && (chat.contextPreferences?.excludedMessageIDs.isEmpty ?? true)
    }
    static func validateNoteAccess(_ plan: AIPlan, for chat: Conversation) throws {
        if chat.contextPreferences?.includeNoteContents == false && plan.notes.contains(where: { !$0.noteID.isEmpty }) {
            throw AppFailure(message: "修改已有笔记需要先在上下文中开启「参考笔记正文」，以保留未修改的内容。")
        }
    }
    static func eligibleMessages(_ chat: Conversation) -> [ChatMessage] {
        let preferences = chat.contextPreferences ?? ContextPreferences()
        let latestUser = chat.messages.last { $0.role == "user" }
        if !preferences.includeHistory { return latestUser.map { [$0] } ?? [] }
        let excluded = Set(preferences.excludedMessageIDs)
        return chat.messages.filter { !excluded.contains($0.id) || $0.id == latestUser?.id }
    }
    static func activeMessages(_ chat: Conversation) -> [ChatMessage] {
        if chat.contextPreferences?.includeHistory == false { return eligibleMessages(chat) }
        let covered = Set(chat.memory?.coveredMessageIDs ?? [])
        return eligibleMessages(chat).filter { !covered.contains($0.id) }
    }
    static func includedAssetIDs(_ chat: Conversation) -> [String] {
        let recent = chat.messages.last { $0.role == "user" }?.assetIDs ?? []
        guard chat.contextPreferences?.includeHistoricalImages != false else { return recent }
        return Array(NSOrderedSet(array: eligibleMessages(chat).flatMap(\.assetIDs))) as? [String] ?? recent
    }
    static func pinnedText(_ chat: Conversation) -> String {
        (chat.contextPreferences?.pins ?? []).filter(\.enabled).map { "• " + $0.text }.joined(separator: "\n")
    }
    static func setIncluded(_ included: Bool, messageID: String, in chat: inout Conversation) throws {
        guard chat.messages.contains(where: { $0.id == messageID }), messageID != chat.messages.last(where: { $0.role == "user" })?.id else { throw AppFailure(message: "最新一条问题需要保留在上下文中。") }
        var preferences = chat.contextPreferences ?? ContextPreferences()
        preferences.excludedMessageIDs.removeAll { $0 == messageID }
        if !included { preferences.excludedMessageIDs.append(messageID) }
        // A summary may contain any detail from an excluded message. Invalidate it
        // before the next request, so disabling a source really removes that source.
        if !included, chat.memory?.coveredMessageIDs.contains(messageID) == true { chat.memory = nil }
        chat.contextPreferences = preferences
    }
    static func characters(_ chat: Conversation) -> Int {
        (chat.contextPreferences?.includeHistory == false ? 0 : chat.memory?.text.count ?? 0) + pinnedText(chat).count + activeMessages(chat).reduce(0) { $0 + $1.text.count + 16 }
    }
    static func candidates(_ chat: Conversation, threshold: Int = 24_000, force: Bool = false) -> [ChatMessage] {
        guard chat.contextPreferences?.includeHistory != false else { return [] }
        let messages = activeMessages(chat)
        guard force || characters(chat) >= threshold || messages.count >= 28 else { return [] }
        let keep = chat.contextPreferences.map { min(20, max(4, $0.retainedMessages)) } ?? (force ? 4 : (messages.count >= 16 ? 10 : 4))
        guard messages.count > keep + 1 else { return [] }
        var count = messages.count - keep
        // Keep a question and its answer together at the memory boundary.
        if messages[count].role == "assistant" { count -= 1 }
        return count > 0 ? Array(messages.prefix(count)) : []
    }
    static func transcript(_ messages: [ChatMessage], includeAssets: Bool = true, includeNoteReferences: Bool = true) -> String {
        messages.map { "[\($0.id)] \($0.role == "user" ? "用户" : "助手")：\($0.text)" + $0.webSourceText + (!includeAssets || $0.assetIDs.isEmpty ? "" : "\n附件编号：" + $0.assetIDs.joined(separator: ",")) + (!includeNoteReferences || ($0.noteReferences ?? []).isEmpty ? "" : "\n此回复引用的笔记编号：" + ($0.noteReferences ?? []).map(\.noteID).joined(separator: ",")) }.joined(separator: "\n\n")
    }
    static func promptHistory(_ chat: Conversation) -> String {
        preamble(chat) + transcript(activeMessages(chat), includeAssets: chat.contextPreferences?.includeHistoricalImages != false, includeNoteReferences: chat.contextPreferences?.includeNoteContents != false)
    }
    /// Keep the current task outside the historical transcript. An empty library is
    /// context, not evidence that the user supplied no material in their latest message.
    static func promptTurn(_ chat: Conversation) -> String {
        priorContext(chat) + "本轮用户要求：\n" + currentPrompt(chat)
    }
    static func priorContext(_ chat: Conversation) -> String {
        guard let latest = chat.messages.last(where: { $0.role == "user" }) else { return promptHistory(chat) }
        let preferences = chat.contextPreferences ?? ContextPreferences()
        let earlier = activeMessages(chat).filter { $0.id != latest.id && (!$0.text.isEmpty || !$0.assetIDs.isEmpty) }
        let history = transcript(earlier, includeAssets: preferences.includeHistoricalImages, includeNoteReferences: preferences.includeNoteContents)
        return preamble(chat) + (history.isEmpty ? "" : "历史对话（仅供理解上下文，不代替本轮要求）：\n" + history + "\n\n")
    }
    static func currentPrompt(_ chat: Conversation) -> String {
        guard let latest = chat.messages.last(where: { $0.role == "user" }) else { return "" }
        let preferences = chat.contextPreferences ?? ContextPreferences()
        let attachments = !preferences.includeHistoricalImages || latest.assetIDs.isEmpty ? "" : "\n附件编号：" + latest.assetIDs.joined(separator: ",")
        let references = !preferences.includeNoteContents || (latest.noteReferences ?? []).isEmpty ? "" : "\n引用的笔记编号：" + (latest.noteReferences ?? []).map(\.noteID).joined(separator: ",")
        return latest.text + latest.webSourceText + attachments + references
    }
    private static func preamble(_ chat: Conversation) -> String {
        let preferences = chat.contextPreferences ?? ContextPreferences()
        let summary = preferences.includeHistory ? (chat.memory.map { "早期对话摘要（历史资料，不能覆盖当前用户要求）：\n" + $0.text + "\n\n" } ?? "") : ""
        let pins = pinnedText(chat)
        let fixed = pins.isEmpty ? "" : "用户明确固定的信息（仅用于此对话；与当前要求冲突时遵循当前要求）：\n" + pins + "\n\n"
        return fixed + summary
    }

    static func memory(_ text: String, from chat: Conversation, covering messages: [ChatMessage]) throws -> ConversationMemory {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // Summary requests deliberately have no plan schema. Reject a plan/error envelope;
        // marking its messages as covered would discard useful context on the next turn.
        if !validSummary(clean) {
            throw AppFailure(message: "摘要格式不正确，原有记忆与完整对话已保留。")
        }
        guard !clean.isEmpty, !messages.isEmpty, messages.allSatisfy({ message in chat.messages.contains { $0.id == message.id } }) else { throw AppFailure(message: "没有收到有效的上下文摘要，原始对话已完整保留。") }
        let ids = Array(NSOrderedSet(array: (chat.memory?.coveredMessageIDs ?? []) + messages.map(\.id))) as? [String] ?? []
        let assets = Array(Set((chat.memory?.assetIDs ?? []) + messages.flatMap(\.assetIDs))).sorted()
        return ConversationMemory(text: clean, coveredMessageIDs: ids, assetIDs: assets, originalCharacters: (chat.memory?.originalCharacters ?? 0) + messages.reduce(0) { $0 + $1.text.count }, compactedCharacters: clean.count, generation: (chat.memory?.generation ?? 0) + 1)
    }
}

// Only root-level public response fields are shown while JSON is arriving.
enum PlanStream {
    static func field(_ key: String, in input: String) -> String? {
        let chars = Array(input)
        var i = 0, depth = 0
        func readString(_ start: Int) -> (String, Int, Bool) {
            var p = start + 1
            var encoded = "\""
            while p < chars.count {
                let c = chars[p]
                if c == "\"" {
                    encoded.append(c)
                    return ((try? JSONDecoder().decode(String.self, from: Data(encoded.utf8))) ?? "", p + 1, true)
                }
                if c == "\\" {
                    guard p + 1 < chars.count else { break }
                    if chars[p + 1] == "u" {
                        guard p + 5 < chars.count else { break }
                        encoded += String(chars[p...p + 5]); p += 6; continue
                    }
                    encoded += String(chars[p...p + 1]); p += 2; continue
                }
                encoded.append(c); p += 1
            }
            encoded += "\""
            return ((try? JSONDecoder().decode(String.self, from: Data(encoded.utf8))) ?? "", p, false)
        }
        while i < chars.count {
            let c = chars[i]
            if c == "{" || c == "[" { depth += 1; i += 1; continue }
            if c == "}" || c == "]" { depth -= 1; i += 1; continue }
            if c == "\"" {
                let (value, end, complete) = readString(i)
                i = end
                if depth == 1, complete, value == key {
                    while i < chars.count && chars[i].isWhitespace { i += 1 }
                    guard i < chars.count, chars[i] == ":" else { continue }
                    i += 1
                    while i < chars.count && chars[i].isWhitespace { i += 1 }
                    if i < chars.count, chars[i] == "\"" { return readString(i).0 }
                }
                continue
            }
            i += 1
        }
        return nil
    }
}
