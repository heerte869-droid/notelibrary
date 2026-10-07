import SwiftUI

struct ChapterNavigator: View {
    @EnvironmentObject var model: AppModel
    let note: Note
    var panelHeight: CGFloat = 430
    var close: () -> Void
    @State private var query = ""
    @State private var collapsed: Set<String> = []
    private var book: Notebook? { LibraryScope.book(for: note, in: model.library) }
    private var chapters: [Chapter] { model.library.chapters.filter { $0.notebookID == book?.id }.sorted { $0.order < $1.order } }
    private func notes(_ chapter: Chapter) -> [Note] {
        model.activeNotes.filter { $0.chapterID == chapter.id && (query.isEmpty || chapter.title.localizedCaseInsensitiveContains(query) || $0.title.localizedCaseInsensitiveContains(query)) }.sorted { $0.createdAt < $1.createdAt }
    }
    private var matchingChapters: [Chapter] { chapters.filter { query.isEmpty || !notes($0).isEmpty || $0.title.localizedCaseInsensitiveContains(query) } }
    private var fittedHeight: CGFloat { min(panelHeight, max(290, CGFloat(175 + chapters.count * 41 + chapters.reduce(0) { $0 + notes($1).count } * 40))) }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) { Text("章节导航").font(.system(size: 14, weight: .semibold)); Text(book?.title ?? "当前笔记本").font(.system(size: 11)).foregroundStyle(.secondary) }
                Spacer(); QuietIconButton(icon: "xmark", label: "关闭章节导航", action: close)
            }
            SearchBox(placeholder: "查找章节或笔记", text: $query)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 5) {
                        if matchingChapters.isEmpty { Text("没有匹配的章节或笔记").font(.system(size: 12)).foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(.vertical, 28) }
                        ForEach(matchingChapters) { chapter in
                            VStack(alignment: .leading, spacing: 2) {
                                Button { if collapsed.contains(chapter.id) { collapsed.remove(chapter.id) } else { collapsed.insert(chapter.id) } } label: {
                                    HStack(spacing: 8) {
                                        Image(systemName: collapsed.contains(chapter.id) ? "chevron.right" : "chevron.down").font(.system(size: 9, weight: .semibold)).frame(width: 10)
                                        HighlightedText(chapter.title, query: query).font(.system(size: 12, weight: .semibold)).lineLimit(2)
                                        Spacer(); if chapter.locked { Image(systemName: "lock").font(.system(size: 10)) }
                                        Text("\(notes(chapter).count)").font(.system(size: 10)).monospacedDigit().foregroundStyle(.secondary)
                                    }.padding(.horizontal, 9).frame(maxWidth: .infinity, minHeight: 36, alignment: .leading).contentShape(Rectangle())
                                }.buttonStyle(FeedbackStyle(compact: true))
                                if !collapsed.contains(chapter.id) || !query.isEmpty {
                                    ForEach(notes(chapter)) { sibling in
                                        Button {
                                            model.searchText = ""; model.tagFilter = nil; model.openNote(sibling); close()
                                        } label: {
                                            HStack(spacing: 9) {
                                                Image(systemName: model.isRead(sibling.id) ? "checkmark.circle" : "doc.text").font(.system(size: 11)).foregroundStyle(sibling.id == note.id ? Theme.accent : Color.secondary).frame(width: 16)
                                                HighlightedText(sibling.title, query: query).font(.system(size: 12)).lineLimit(2)
                                                Spacer(minLength: 0)
                                                if sibling.id == note.id { Circle().fill(Theme.accent).frame(width: 5, height: 5) }
                                            }.padding(.leading, 25).padding(.trailing, 11).padding(.vertical, 7).frame(maxWidth: .infinity, minHeight: 38, alignment: .leading).contentShape(Rectangle())
                                        }.buttonStyle(FeedbackStyle(selected: sibling.id == note.id, compact: true)).id(sibling.id)
                                    }
                                    if notes(chapter).isEmpty { Text("暂无笔记").font(.system(size: 11)).foregroundStyle(.tertiary).padding(.leading, 28).padding(.vertical, 7) }
                                }
                            }
                        }
                    }
                }.onAppear { proxy.scrollTo(note.id, anchor: .center) }
            }
            Rectangle().fill(Theme.border).frame(height: 1)
            HStack {
                Text("\(chapters.count) 章").font(.system(size: 11)).foregroundStyle(.secondary)
                Spacer()
                ActionButton(title: "管理章节", icon: "slider.horizontal.3") { close(); model.organizingBookID = book?.id }
            }
        }.padding(15).frame(width: 330, height: fittedHeight)
            .background(Theme.panel, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.border).allowsHitTesting(false))
            .shadow(color: .black.opacity(0.20), radius: 18, y: 8)
            .background(PointerObserver(onDown: { point, bounds, _ in
                if !bounds.contains(point) { DispatchQueue.main.async { close() } }
            }, onEscape: close))
    }
}
