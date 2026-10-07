import SwiftUI

struct TrashView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject private var choices: ChoiceCenter
    @Environment(\.accessibilityReduceMotion) private var reduced
    @State private var queries: [String: String] = [:]
    private var query: String { queries[model.recoverySection] ?? "" }
    private var queryBinding: Binding<String> { Binding(get: { query }, set: { queries[model.recoverySection] = $0 }) }
    private var motion: Animation? { reduced || model.library.settings.reduceMotion ? nil : .easeOut(duration: 0.16) }
    @State private var expanded: Set<String> = []
    private var archived: [Notebook] { model.library.notebooks.filter { $0.archivedAt != nil && $0.deletedAt == nil } }
    private var deleted: [Notebook] { model.library.notebooks.filter { $0.deletedAt != nil } }
    private var looseNotes: [Note] { model.library.notes.filter { $0.deletedAt != nil && LibraryScope.book(for: $0, in: model.library)?.deletedAt == nil } }
    private var chats: [Conversation] { model.library.conversations.filter { $0.deletedAt != nil } }
    private var isArchive: Bool { model.recoverySection == "archived" }
    private var clearRequest: RecoveryDeletion { .section(model.recoverySection, in: model.library) }
    private func matches(_ value: String) -> Bool { query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || value.localizedCaseInsensitiveContains(query.trimmingCharacters(in: .whitespacesAndNewlines)) }
    private var books: [Notebook] { (isArchive ? archived : deleted).filter { matches($0.title + $0.subject) }.sorted { ($0.deletedAt ?? $0.archivedAt ?? $0.createdAt) > ($1.deletedAt ?? $1.archivedAt ?? $1.createdAt) } }
    private var filteredNotes: [Note] { looseNotes.filter { matches($0.title) } }
    private var filteredChats: [Conversation] { chats.filter { matches($0.title) } }
    private var empty: Bool { books.isEmpty && (isArchive || (filteredNotes.isEmpty && filteredChats.isEmpty)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack {
                Text("回收站").font(.system(size: 25, weight: .semibold))
                Spacer()
                RecoveryDeleteButton(title: isArchive ? "清空归档…" : "清空回收站…") { model.recoveryDeletion = clearRequest }
                    .disabled(clearRequest.isEmpty || model.isRunning)
                    .help(clearRequest.isEmpty ? "这里暂时没有可清理的内容" : "永久删除当前分类的全部内容，包含搜索中未显示的内容")
            }
            HStack(spacing: 5) {
                segment("已归档", "archived", archived.count, "archivebox")
                segment("已删除", "trash", deleted.count + looseNotes.count + chats.count, "trash")
                Spacer(minLength: 20)
                SearchBox(placeholder: isArchive ? "搜索归档笔记" : "搜索已删除内容", text: queryBinding).frame(maxWidth: 310)
            }
            Group {
                Label(isArchive ? "归档内容可以放回书架；永久删除后无法撤销。" : "恢复笔记本时，章节、附件与复习记录会一起恢复。", systemImage: "info.circle")
                    .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            if empty { emptyState }
            else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(books) { book in bookRow(book).transition(.opacity) }
                        if !isArchive {
                            if !filteredNotes.isEmpty { Text("单独删除的笔记").font(.system(size: 13, weight: .semibold)).padding(.top, 12) }
                            ForEach(filteredNotes) { note in
                                HStack(spacing: 14) {
                                    Image(systemName: "doc.text").foregroundStyle(Theme.accent).frame(width: 30)
                                    VStack(alignment: .leading, spacing: 5) { HighlightedText(note.title, query: query).font(.system(size: 13, weight: .medium)); Text(model.location(note)).font(.system(size: 11)).foregroundStyle(.secondary) }
                                    Spacer()
                                    if let book = LibraryScope.book(for: note, in: model.library), !LibraryScope.active(book) {
                                        ActionButton(title: "先恢复笔记本", icon: "archivebox") { model.restoreBook(book) }
                                    } else { ActionButton(title: "恢复笔记", icon: "arrow.uturn.backward") { model.restore(note) } }
                                    ActionMenu(title: "已删除笔记操作", options: [ChoiceOption(id: "delete", title: "永久删除", icon: "trash", destructive: true)]) { _ in
                                        model.recoveryDeletion = .init(title: "永久删除《\(note.title)》", revision: model.library.contentRevision, noteIDs: [note.id])
                                    }
                                }.padding(15).background(Theme.background, in: RoundedRectangle(cornerRadius: 12))
                            }
                            if !filteredChats.isEmpty { Text("已删除的对话").font(.system(size: 13, weight: .semibold)).padding(.top, 12) }
                            ForEach(filteredChats) { chat in
                                HStack(spacing: 14) {
                                    Image(systemName: "bubble.left").foregroundStyle(Theme.accent).frame(width: 30)
                                    VStack(alignment: .leading, spacing: 5) { HighlightedText(chat.title, query: query).font(.system(size: 13, weight: .medium)); Text("\(chat.messages.count) 条消息").font(.system(size: 11)).foregroundStyle(.secondary) }
                                    Spacer()
                                    ActionButton(title: "恢复对话", icon: "arrow.uturn.backward") { model.restoreConversation(chat.id) }
                                    ActionMenu(title: "已删除对话操作", options: [ChoiceOption(id: "delete", title: "永久删除", icon: "trash", destructive: true)]) { _ in
                                        model.recoveryDeletion = .init(title: "永久删除「\(chat.title)」", revision: model.library.contentRevision, conversationIDs: [chat.id])
                                    }
                                }.padding(15).background(Theme.background, in: RoundedRectangle(cornerRadius: 12))
                            }
                        }
                    }.padding(.bottom, 20)
                        .animation(motion, value: expanded)
                        .animation(motion, value: model.library.contentRevision)
                }.id(model.recoverySection)
            
            }
        }.padding(28).frame(maxWidth: .infinity, maxHeight: .infinity)
            .onChange(of: model.recoverySection) { _, _ in choices.presentation = nil }
    }

    private var emptyState: some View {
        VStack(spacing: 15) {
            Image(systemName: query.isEmpty ? (isArchive ? "archivebox" : "trash") : "magnifyingglass")
                .font(.system(size: 29, weight: .light)).foregroundStyle(Theme.accent)
                .frame(width: 70, height: 70).background(Theme.accent.opacity(0.07), in: RoundedRectangle(cornerRadius: 22))
            Text(query.isEmpty ? (isArchive ? "归档区是空的" : "回收站是空的") : "没有匹配的内容").font(.system(size: 16, weight: .medium))
            Text(query.isEmpty ? (isArchive ? "暂时不用的笔记，可以从书架归档到这里。" : "暂时没有已删除的笔记或对话。") : "换个关键词，或清除搜索后查看全部。")
                .font(.system(size: 12)).foregroundStyle(.secondary)
            if !query.isEmpty { ActionButton(title: "清除搜索", icon: "xmark") { queryBinding.wrappedValue = "" } }
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func segment(_ title: String, _ id: String, _ count: Int, _ icon: String) -> some View {
        Button { guard model.recoverySection != id else { return }; choices.presentation = nil; model.recoverySection = id } label: {
            HStack(spacing: 8) { Image(systemName: icon).frame(width: 16, height: 16); Text(title); Text("\(count)").font(.system(size: 10)).monospacedDigit().foregroundStyle(.secondary) }
                .font(.system(size: 12, weight: .medium)).padding(.horizontal, 13).frame(height: 38).contentShape(Rectangle())
        }.buttonStyle(FeedbackStyle(selected: model.recoverySection == id))
            .accessibilityAddTraits(model.recoverySection == id ? .isSelected : []).accessibilityIdentifier("recovery-tab-" + id)
    }

    private func bookRow(_ book: Notebook) -> some View {
        let chapters = model.library.chapters.filter { $0.notebookID == book.id }.sorted { $0.order < $1.order }
        let notes = model.notes(in: book.id)
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 0) {
                Button { if expanded.contains(book.id) { expanded.remove(book.id) } else { expanded.insert(book.id) } } label: {
                    HStack(spacing: 14) {
                        Image(systemName: "book.closed").font(.system(size: 22)).foregroundStyle(Theme.colors[abs(book.color % 5)]).frame(width: 44, height: 48).background(Theme.panel, in: RoundedRectangle(cornerRadius: 9))
                        VStack(alignment: .leading, spacing: 6) { HighlightedText(book.title, query: query).font(.system(size: 14, weight: .semibold)); Text("\(chapters.count) 章 · \(notes.count) 篇笔记").font(.system(size: 11)).foregroundStyle(.secondary) }
                        Spacer(); Image(systemName: "chevron.down").font(.system(size: 10)).foregroundStyle(.secondary).rotationEffect(.degrees(expanded.contains(book.id) ? 180 : 0))
                    }.padding(15).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                }.buttonStyle(FeedbackStyle()).accessibilityLabel("查看《" + book.title + "》的内容")
                    .accessibilityValue(expanded.contains(book.id) ? "已展开" : "已收起")
                ActionButton(title: book.deletedAt == nil ? "放回书架" : "恢复笔记本", icon: "arrow.uturn.backward") { model.restoreBook(book) }.padding(.horizontal, 10)
                ActionMenu(title: book.deletedAt == nil ? "归档笔记本操作" : "已删除笔记本操作", options: [ChoiceOption(id: "delete", title: "永久删除", icon: "trash", destructive: true)]) { _ in
                    model.recoveryDeletion = .init(title: "永久删除《\(book.title)》", revision: model.library.contentRevision, bookIDs: [book.id])
                }.padding(.trailing, 10)
            }
            if expanded.contains(book.id) {
                VStack(alignment: .leading, spacing: 13) {
                    ForEach(chapters) { chapter in
                        VStack(alignment: .leading, spacing: 5) {
                            Text(chapter.title).font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.accent)
                            Text(notes.filter { $0.chapterID == chapter.id }.map(\.title).joined(separator: " · ").isEmpty ? "暂无笔记" : notes.filter { $0.chapterID == chapter.id }.map(\.title).joined(separator: " · ")).font(.system(size: 11)).foregroundStyle(.secondary)
                        }
                    }
                    if chapters.isEmpty { Text("这本笔记还没有章节").font(.system(size: 11)).foregroundStyle(.secondary) }
                }.padding(.horizontal, 24).padding(.bottom, 20).transition(.opacity)
            }
        }.background(Theme.background, in: RoundedRectangle(cornerRadius: 13)).overlay(RoundedRectangle(cornerRadius: 13).stroke(Theme.border).allowsHitTesting(false))
    }
}

private struct RecoveryDeleteButton: View {
    var title: String
    var prominent = false
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) { Image(systemName: "trash"); Text(title) }
                .font(.system(size: 12, weight: .medium)).foregroundStyle(prominent ? Color.white : Color.red.opacity(0.88))
                .padding(.horizontal, 14).frame(minHeight: 36).contentShape(Rectangle())
        }.buttonStyle(FeedbackStyle())
            .background(prominent ? Color.red.opacity(0.82) : Theme.secondary, in: RoundedRectangle(cornerRadius: 11))
    }
}

struct RecoveryConfirmationDialog: View {
    @EnvironmentObject private var model: AppModel
    @FocusState private var cancelFocused: Bool
    let request: RecoveryDeletion
    var body: some View {
        ZStack {
            Color.black.opacity(0.22).contentShape(Rectangle()).onTapGesture { model.recoveryDeletion = nil }
            VStack(alignment: .leading, spacing: 16) {
                Label(request.title, systemImage: "trash").font(.system(size: 17, weight: .semibold)).lineLimit(2)
                Text(request.summary(in: model.library)).font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.accent)
                Text("相关章节、正文、学习记录与修改记录会一起移除，无法撤销。已有备份和其他内容不受影响。")
                    .font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(4).fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 10) {
                    Spacer()
                    ActionButton(title: "取消") { model.recoveryDeletion = nil }.keyboardShortcut(.cancelAction).focused($cancelFocused)
                    RecoveryDeleteButton(title: request.title.hasPrefix("清空") ? "确认清空" : "永久删除", prominent: true) {
                        let deleted = model.permanentlyDelete(request)
                        if deleted || model.error != nil { model.recoveryDeletion = nil }
                    }.disabled(model.isRunning)
                }.padding(.top, 4)
            }.padding(24).frame(width: 430).background(Theme.panel, in: RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.border).allowsHitTesting(false))
                .shadow(color: .black.opacity(0.18), radius: 22, y: 8)
                .focusSection().accessibilityElement(children: .contain).accessibilityLabel("永久删除确认")
        }.onAppear { cancelFocused = true }
    }
}
