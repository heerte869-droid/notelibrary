import Foundation

enum LibraryScope {
    static func active(_ book: Notebook) -> Bool { book.archivedAt == nil && book.deletedAt == nil }
    static func book(for note: Note, in state: LibraryState) -> Notebook? {
        guard let chapter = state.chapters.first(where: { $0.id == note.chapterID }) else { return nil }
        return state.notebooks.first { $0.id == chapter.notebookID }
    }
    static func contains(_ note: Note, in state: LibraryState) -> Bool {
        note.deletedAt == nil && book(for: note, in: state).map(active) == true
    }
    static func activeNotes(in state: LibraryState) -> [Note] {
        let books = Set(state.notebooks.filter(active).map(\.id))
        let chapters = Set(state.chapters.filter { books.contains($0.notebookID) }.map(\.id))
        return state.notes.filter { $0.deletedAt == nil && chapters.contains($0.chapterID) }
    }
    static func setBook(_ id: String, action: String, in state: inout LibraryState) throws {
        guard let index = state.notebooks.firstIndex(where: { $0.id == id }) else { throw AppFailure(message: "这本笔记已不存在。") }
        switch action {
        case "archive":
            guard state.notebooks[index].deletedAt == nil else { throw AppFailure(message: "请先从回收站恢复这本笔记。") }
            state.notebooks[index].archivedAt = Date()
        case "trash": state.notebooks[index].deletedAt = Date()
        case "restore": state.notebooks[index].archivedAt = nil; state.notebooks[index].deletedAt = nil
        default: throw AppFailure(message: "无法识别这项笔记本操作。")
        }
        state.contentRevision += 1
    }
}
