import SwiftUI

extension AppModel {
    func notes(in bookID: String) -> [Note] {
        let ids = Set(library.chapters.filter { $0.notebookID == bookID }.map(\.id))
        return library.notes.filter { $0.deletedAt == nil && ids.contains($0.chapterID) }.sorted { $0.updatedAt > $1.updatedAt }
    }
    func openNote(_ note: Note) {
        guard LibraryScope.contains(note, in: library) else { toast = "这篇笔记已归档或移除，请先恢复笔记本"; recoverySection = LibraryScope.book(for: note, in: library)?.deletedAt == nil ? "archived" : "trash"; chooseDestination("trash"); return }
        if let chapter = library.chapters.first(where: { $0.id == note.chapterID }) { chooseDestination("book:" + chapter.notebookID) }
        else { chooseDestination("all") }
        notebookSection = "notes"; chapterFilter = nil; selectedNoteID = note.id
    }
}

struct ConversationListView: View {
    @EnvironmentObject var model: AppModel
    @State private var query = ""
    @State private var filter = "all"
    private var showingDrafts: Bool { filter == "drafts" }
    private var chats: [Conversation] {
        let source = showingDrafts ? model.draftConversations : model.recentConversations
        return source.filter {
            return (LibrarySearch.query(query).isEmpty || LibrarySearch.conversationMatches($0, query: query, draft: showingDrafts)) &&
                (filter == "all" || showingDrafts || (filter == "pinned" && $0.pinned == true) || (filter == "pending" && $0.state != "completed"))
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                VStack(alignment: .leading, spacing: 7) {
                    Text("对话记录").font(.system(size: 24, weight: .semibold))
                    Text(showingDrafts ? "草稿自动保留，发送后才会出现在最近对话。" : "继续讨论，或管理已经完成的整理。")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                }
                Spacer()
                ActionButton(title: "新对话", icon: "plus", primary: true) { model.newConversation() }
            }
            HStack {
                SearchBox(placeholder: showingDrafts ? "搜索未发送的草稿" : "搜索对话和消息", text: $query)
                ChoicePicker(title: "筛选对话", selection: filter, options: [
                    ChoiceOption(id: "all", title: "全部对话"),
                    ChoiceOption(id: "pinned", title: "已置顶"),
                    ChoiceOption(id: "pending", title: "待继续"),
                    ChoiceOption(id: "drafts", title: "未发送草稿", icon: "square.and.pencil", separatorBefore: true)
                ]) { filter = $0 }
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 9) {
                    if !LibrarySearch.query(query).isEmpty { Text("\(chats.count) 个匹配对话").font(.system(size: 11)).foregroundStyle(.secondary).padding(.bottom, 2) }
                    ForEach(chats) { chat in row(chat) }
                }
                if chats.isEmpty {
                    Text(showingDrafts ? "没有未发送的草稿" : "没有匹配的对话")
                        .font(.system(size: 13)).foregroundStyle(.secondary).padding(50)
                }
            }
        }.padding(30).onAppear { model.saveComposer() }
    }
    private func row(_ chat: Conversation) -> some View {
        let hit = LibrarySearch.conversationHits(chat, query: query).first
        return HStack(spacing: 0) {
            Button { model.selectConversation(chat.id, searchQuery: showingDrafts ? "" : query) } label: {
                HStack(spacing: 14) {
                    if showingDrafts {
                        Image(systemName: "square.and.pencil").font(.system(size: 16)).foregroundStyle(Theme.accent)
                            .frame(width: 34, height: 34).background(Theme.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 9))
                    } else { Avatar(size: 34) }
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            HighlightedText(showingDrafts ? chat.draftTitle : chat.title, query: query).font(.system(size: 14, weight: .medium)).lineLimit(1)
                            if showingDrafts { TagPill(text: "未发送", color: Theme.accent) }
                            else if chat.pinned == true { Image(systemName: "pin.fill").font(.caption2).foregroundStyle(Theme.accent) }
                            if model.runningConversationID == chat.id { TagPill(text: "正在回复", color: Theme.accent) }
                            else if model.queuePosition(chat.id) != nil { TagPill(text: "已排队", color: Theme.accent) }
                            else if model.unreadConversationIDs.contains(chat.id) { TagPill(text: "有新进展", color: Theme.accent) }
                            if chat.state == "awaitingAnswers" { TagPill(text: "等待补充", color: .orange) }
                        }
                        if !showingDrafts {
                            HighlightedText(LibrarySearch.query(query).isEmpty ? LibrarySearch.plain(chat.messages.last?.text ?? "") : LibrarySearch.snippet(hit?.text ?? chat.title, query: query, limit: 160), query: query)
                                .font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(3).lineSpacing(4)
                            if let hit { Text(hit.label).font(.system(size: 10)).foregroundStyle(Theme.accent) }
                        } else if !LibrarySearch.query(query).isEmpty {
                            HighlightedText(LibrarySearch.snippet(chat.draft, query: query, limit: 160), query: query).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(3)
                        } else if let book = model.library.notebooks.first(where: { $0.id == chat.notebookID }) {
                            Label(book.title, systemImage: "book.closed").font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                        }
                        if showingDrafts, let images = chat.draftAssetIDs, !images.isEmpty {
                            Label("\(images.count) 张图片", systemImage: "photo").font(.system(size: 11)).foregroundStyle(.secondary)
                        }
                        Text((showingDrafts ? "草稿保存于 " : "\(chat.messages.count) 条消息 · ") + chat.updatedAt.formatted(date: .abbreviated, time: .shortened))
                            .font(.system(size: 10)).foregroundStyle(.tertiary)
                    }
                    Spacer()
                }.padding(15).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
            }.buttonStyle(FeedbackStyle())
            if showingDrafts {
                QuietIconButton(icon: "trash", label: "草稿移到回收站") { model.deleteConversation(chat.id) }.padding(.trailing, 10)
            } else { ConversationMenu(chat: chat).padding(.trailing, 10) }
        }.background(Theme.background, in: RoundedRectangle(cornerRadius: 13))
    }
}
