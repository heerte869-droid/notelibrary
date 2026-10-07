import SwiftUI
import AppKit

struct NoteActionRequest {
    var kind: String
    var ids: Set<String>
}

enum LibraryEdits {
    static func update(_ ids: Set<String>, title: String, state: inout LibraryState, transform: (inout Note) -> Void) throws {
        guard !ids.isEmpty, ids.allSatisfy({ id in state.notes.contains { $0.id == id && $0.deletedAt == nil } }) else { throw AppFailure(message: "所选笔记已发生变化，请重新选择。") }
        var changes: [NoteDelta] = []
        for i in state.notes.indices where ids.contains(state.notes[i].id) {
            let before = state.notes[i]
            transform(&state.notes[i])
            guard state.notes[i] != before else { continue }
            state.notes[i].version += 1; state.notes[i].updatedAt = Date()
            changes.append(NoteDelta(before: before, after: state.notes[i]))
        }
        if !changes.isEmpty {
            state.contentRevision += 1
            state.receipts.append(ChangeReceipt(id: makeID(), title: title, changes: changes, createdNotebookIDs: [], createdChapterIDs: []))
        }
    }
    static func duplicate(_ source: Note, state: inout LibraryState) -> Note {
        var copy = source
        copy.id = makeID(); copy.title += " · 副本"; copy.version = 1; copy.createdAt = Date(); copy.updatedAt = Date(); copy.deletedAt = nil; copy.locked = false; copy.pinned = nil
        copy.blocks = copy.blocks.map { var block = $0; block.id = makeID(); return block }
        state.notes.append(copy); state.contentRevision += 1
        state.receipts.append(ChangeReceipt(id: makeID(), title: "复制《" + source.title + "》", changes: [NoteDelta(before: nil, after: copy)], createdNotebookIDs: [], createdChapterIDs: []))
        return copy
    }
    static func tags(_ text: String) -> [String] {
        var seen = Set<String>()
        return text.components(separatedBy: CharacterSet(charactersIn: ",，\n")).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty && seen.insert($0).inserted }
    }
}

extension AppModel {
    var activeNotebooks: [Notebook] { SidebarContent.notebooks(library.notebooks, collapsed: false) }
    func createBook(title: String, subject: String, summary: String, color: Int, style: String, chapters: [String]) -> Bool {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return false }
        var book = Notebook(title: title, subject: subject, color: color)
        book.summary = summary; book.coverStyle = style
        let names = chapters.isEmpty ? ["第一章"] : chapters
        let saved = mutate(snapshot: true) { state in
            state.notebooks.append(book)
            for (index, title) in names.enumerated() { state.chapters.append(Chapter(notebookID: book.id, title: title, order: index)) }
            state.contentRevision += 1
        }
        if saved { chooseDestination("book:" + book.id) }
        return saved
    }
    var activeNotes: [Note] { LibraryScope.activeNotes(in: library) }
    func archiveBook(_ book: Notebook) { changeBookState(book.id, action: book.archivedAt == nil ? "archive" : "restore") }
    func deleteBook(_ book: Notebook) { changeBookState(book.id, action: "trash") }
    func restoreBook(_ book: Notebook) { changeBookState(book.id, action: "restore") }
    private func changeBookState(_ id: String, action: String) {
        guard mutate(snapshot: true, { try LibraryScope.setBook(id, action: action, in: &$0) }) else { return }
        if action != "restore" { recoverySection = action == "trash" ? "trash" : "archived" }
        selectedNotes = []; selectingNotes = false
        if let selectedNoteID, !activeNotes.contains(where: { $0.id == selectedNoteID }) { self.selectedNoteID = nil }
        if destination == "book:" + id { chooseDestination("home") }
        if action == "trash" { toast = "整本笔记已移到回收站，章节和内容可以一起恢复" }
        else if action == "archive" { toast = "已归档，可在「回收站 → 已归档」中找回" }
        else { toast = "笔记本已恢复到书架" }
    }
    func permanentlyDelete(_ request: RecoveryDeletion) -> Bool {
        guard !isRunning else { error = "请在当前 AI 操作结束后清理内容。"; return false }
        guard mutate({ try RecoveryEngine.apply(request, to: &$0) }) else { return false }
        if let conversationID, !library.conversations.contains(where: { $0.id == conversationID }) {
            self.conversationID = nil; composer = ""; attachments = []; previewPlan = nil
        }
        if let selectedNoteID, !library.notes.contains(where: { $0.id == selectedNoteID }) { self.selectedNoteID = nil }
        if let lastDeletedConversationID, request.conversationIDs.contains(lastDeletedConversationID) { self.lastDeletedConversationID = nil }
        toast = request.title.hasPrefix("清空") ? "已" + request.title : "已永久删除"
        return true
    }
    func pinBook(_ id: String) { _ = mutate { state in if let i = state.notebooks.firstIndex(where: { $0.id == id }) { state.notebooks[i].pinned = !(state.notebooks[i].pinned ?? false) } } }
    func isRead(_ noteID: String) -> Bool { library.readingRecords?.first { $0.noteID == noteID }?.completed == true }
    func trackReading(_ noteID: String) {
        guard activeNotes.contains(where: { $0.id == noteID }) else { return }
        _ = mutate { state in
            var records = state.readingRecords ?? []
            if let i = records.firstIndex(where: { $0.noteID == noteID }) { records[i].lastOpenedAt = Date() }
            else { records.append(ReadingRecord(noteID: noteID, completed: false, lastOpenedAt: Date())) }
            state.readingRecords = records
        }
    }
    func markRead(_ ids: Set<String>, completed: Bool) {
        _ = mutate { state in
            var records = state.readingRecords ?? []
            for id in ids where state.notes.contains(where: { $0.id == id && $0.deletedAt == nil }) {
                if let i = records.firstIndex(where: { $0.noteID == id }) { records[i].completed = completed }
                else { records.append(ReadingRecord(noteID: id, completed: completed, lastOpenedAt: Date())) }
            }
            state.readingRecords = records
        }
    }
    @discardableResult
    func saveStudySession(_ session: StudySession) -> Bool {
        mutate { state in
            var sessions = state.studySessions ?? []; sessions.removeAll { $0.bookID == session.bookID }
            sessions.append(session); state.studySessions = sessions
        }
    }
    @discardableResult
    func review(_ blockID: String, rating: String, session: StudySession? = nil) -> Bool {
        guard ["again", "hard", "known"].contains(rating), let block = activeNotes.flatMap(\.blocks).first(where: { $0.id == blockID }) else { return false }
        return mutate { state in
            var records = state.reviewRecords ?? []
            let record = StudyLearning.record(block, rating: rating, previous: records.first { $0.blockID == blockID })
            records.removeAll { $0.blockID == blockID }; records.append(record); state.reviewRecords = records
            if let session {
                var sessions = state.studySessions ?? []; sessions.removeAll { $0.bookID == session.bookID }
                sessions.append(session); state.studySessions = sessions
            }
        }
    }
    func bulkEdit(_ ids: Set<String>, title: String, change: (inout Note) -> Void) -> Bool {
        guard ids.allSatisfy({ id in activeNotes.contains { $0.id == id } }) else { error = "所选内容已归档或移除，请恢复后再编辑。"; return false }
        let saved = mutate(snapshot: true) { try LibraryEdits.update(ids, title: title, state: &$0, transform: change) }
        if saved { if library.notes.contains(where: { ids.contains($0.id) && $0.deletedAt != nil }) { recoverySection = "trash" }; toast = title + " · 可在修改记录撤销"; if !visibleNotes.contains(where: { $0.id == selectedNoteID }) { selectedNoteID = visibleNotes.first?.id } }
        return saved
    }
    func moveNotes(_ ids: Set<String>, chapterID: String) -> Bool {
        guard library.chapters.contains(where: { chapter in chapter.id == chapterID && activeNotebooks.contains { $0.id == chapter.notebookID } }) else { error = "请选择一个章节。"; return false }
        return bulkEdit(ids, title: "移动 \(ids.count) 篇笔记") { $0.chapterID = chapterID }
    }
    func duplicateNote(_ note: Note) {
        var copied: Note?
        if mutate(snapshot: true, { copied = LibraryEdits.duplicate(note, state: &$0) }), let copied { openNote(copied); toast = "已创建独立副本" }
    }
    func togglePin(_ note: Note) {
        guard LibraryScope.contains(note, in: library) else { return }
        _ = mutate { state in
            if let i = state.notes.firstIndex(where: { $0.id == note.id }) { state.notes[i].pinned = !(state.notes[i].pinned ?? false) }
        }
    }
    func performNoteAction(_ action: String, note: Note) {
        switch action {
        case "edit": editorNote = note
        case "rename", "move", "tags": noteAction = NoteActionRequest(kind: action, ids: [note.id])
        case "duplicate": duplicateNote(note)
        case "copy": NSPasteboard.general.clearContents(); NSPasteboard.general.setString(NoteEngine.markdown(note), forType: .string); toast = "已复制笔记内容"
        case "pin": togglePin(note)
        case "favorite": toggleFavorite(note)
        case "read": markRead([note.id], completed: !isRead(note.id))
        case "export": exportNote = note
        case "trash": _ = bulkEdit([note.id], title: "移除《\(note.title)》") { $0.deletedAt = Date() }
        default: break
        }
    }
    func transcript(_ chat: Conversation) -> String { "# " + chat.title + "\n\n" + chat.messages.map { "## " + ($0.role == "user" ? "你" : "NoteLibrary") + "\n\n" + $0.copyText + "\n" }.joined(separator: "\n") }
    func copyConversation(_ chat: Conversation) { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(transcript(chat), forType: .string); toast = "已复制对话" }
    func exportConversation(_ chat: Conversation) {
        let panel = NSSavePanel(); panel.nameFieldStringValue = chat.title + ".md"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try transcript(chat).write(to: url, atomically: true, encoding: .utf8); toast = "对话已导出" } catch { self.error = error.localizedDescription }
    }
    func forkConversation(_ chat: Conversation) {
        guard !isConversationBusy(chat.id) else { return }
        saveComposer()
        var copy = Conversation(title: chat.title + " · 分支", model: chat.model, effort: chat.effort)
        copy.messages = chat.messages.map { var message = $0; message.id = makeID(); message.events = nil; message.receiptID = nil; return message }
        copy.notebookID = chat.notebookID; copy.userNamed = true
        copy.pendingAssetIDs = Array(Set(chat.messages.flatMap(\.assetIDs)))
        if mutate({ $0.conversations.append(copy) }) { selectConversation(copy.id); toast = "已保留原对话，开始新的分支" }
    }
}
