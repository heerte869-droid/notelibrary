import Foundation

struct RecoveryDeletion: Identifiable {
    var id = makeID()
    var title: String
    var revision: Int
    var bookIDs: Set<String> = []
    var noteIDs: Set<String> = []
    var conversationIDs: Set<String> = []

    static func section(_ section: String, in state: LibraryState) -> Self {
        let archived = section == "archived"
        return Self(title: archived ? "清空归档" : "清空回收站", revision: state.contentRevision,
                    bookIDs: Set(state.notebooks.filter { archived ? $0.archivedAt != nil && $0.deletedAt == nil : $0.deletedAt != nil }.map(\.id)),
                    noteIDs: archived ? [] : Set(state.notes.filter { $0.deletedAt != nil }.map(\.id)),
                    conversationIDs: archived ? [] : Set(state.conversations.filter { $0.deletedAt != nil }.map(\.id)))
    }

    func summary(in state: LibraryState) -> String {
        let chapters = Set(state.chapters.filter { bookIDs.contains($0.notebookID) }.map(\.id))
        let noteCount = state.notes.filter { noteIDs.contains($0.id) || chapters.contains($0.chapterID) }.count
        var parts: [String] = []
        if !bookIDs.isEmpty { parts.append("\(bookIDs.count) 本笔记本") }
        if noteCount > 0 { parts.append("\(noteCount) 篇笔记") }
        if !conversationIDs.isEmpty { parts.append("\(conversationIDs.count) 个对话") }
        return parts.joined(separator: " · ")
    }

    var isEmpty: Bool { bookIDs.isEmpty && noteIDs.isEmpty && conversationIDs.isEmpty }
}

enum RecoveryEngine {
    static func apply(_ request: RecoveryDeletion, to state: inout LibraryState) throws {
        guard !request.isEmpty, request.revision == state.contentRevision else {
            throw AppFailure(message: "内容已经发生变化，请重新选择要清理的内容。")
        }
        guard request.bookIDs.allSatisfy({ id in state.notebooks.contains { $0.id == id && !LibraryScope.active($0) } }),
              request.noteIDs.allSatisfy({ id in state.notes.contains { $0.id == id && $0.deletedAt != nil } }),
              request.conversationIDs.allSatisfy({ id in state.conversations.contains { $0.id == id && $0.deletedAt != nil } }) else {
            throw AppFailure(message: "部分内容已恢复或移走，已取消这次删除。")
        }
        let chapterIDs = Set(state.chapters.filter { request.bookIDs.contains($0.notebookID) }.map(\.id))
        let noteIDs = request.noteIDs.union(state.notes.filter { chapterIDs.contains($0.chapterID) }.map(\.id))
        let blockIDs = Set(state.notes.filter { noteIDs.contains($0.id) }.flatMap(\.blocks).map(\.id))
        let removedReceipts = Set(state.receipts.filter { receipt in
            !Set(receipt.createdNotebookIDs).isDisjoint(with: request.bookIDs) ||
            !Set(receipt.createdChapterIDs).isDisjoint(with: chapterIDs) ||
            receipt.changes.contains { noteIDs.contains($0.after.id) || chapterIDs.contains($0.after.chapterID) || $0.before.map { chapterIDs.contains($0.chapterID) } == true }
        }.map(\.id))
        state.notebooks.removeAll { request.bookIDs.contains($0.id) }
        state.chapters.removeAll { chapterIDs.contains($0.id) }
        state.notes.removeAll { noteIDs.contains($0.id) }
        state.readingRecords?.removeAll { noteIDs.contains($0.noteID) }
        state.reviewRecords?.removeAll { blockIDs.contains($0.blockID) }
        state.receipts.removeAll { removedReceipts.contains($0.id) }
        state.conversations.removeAll { request.conversationIDs.contains($0.id) }
        for i in state.conversations.indices {
            if let bookID = state.conversations[i].notebookID, request.bookIDs.contains(bookID) { state.conversations[i].notebookID = nil }
            if let receiptID = state.conversations[i].receiptID, removedReceipts.contains(receiptID) { state.conversations[i].receiptID = nil }
            for j in state.conversations[i].messages.indices {
                if let receiptID = state.conversations[i].messages[j].receiptID, removedReceipts.contains(receiptID) { state.conversations[i].messages[j].receiptID = nil }
            }
        }
        state.contentRevision += 1
    }
}
