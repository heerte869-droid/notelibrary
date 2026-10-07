import SwiftUI
import AppKit

struct LibraryView: View {
    @EnvironmentObject var model: AppModel
    var book: Notebook? { model.destination.hasPrefix("book:") ? model.library.notebooks.first { $0.id == String(model.destination.dropFirst(5)) } : nil }
    var notes: [Note] { model.visibleNotes }
    var chapters: [Chapter] { model.library.chapters.filter { $0.notebookID == book?.id }.sorted { $0.order < $1.order } }
    var bookNotes: [Note] { book.map { model.notes(in: $0.id) } ?? model.activeNotes }
    var tags: [String] { Array(Set(bookNotes.flatMap(\.tags))).sorted() }
    var body: some View {
        VStack(spacing: 0) {
            if model.referenceReturn != nil {
                HStack(spacing: 8) {
                    Button { model.returnToReferenceConversation() } label: { Label("返回引用这篇笔记的对话", systemImage: "arrow.left").font(.system(size: 11, weight: .medium)).padding(.horizontal, 10).frame(height: 32) }.buttonStyle(FeedbackStyle(tinted: true, compact: true)).accessibilityIdentifier("return-to-reference-chat")
                    Spacer()
                    QuietIconButton(icon: "xmark", label: "收起返回对话入口", size: 28) { model.referenceReturn = nil }
                }.padding(.horizontal, 15).padding(.vertical, 7).background(Theme.accent.opacity(0.035))
            }
            ReaderChrome(expanded: !model.readingMode, axis: .vertical) {
            VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 17) {
                notebookHeader
                if book != nil {
                    HStack(spacing: 4) {
                        tab("全部内容", "notes", "doc.text", bookNotes.count)
                        tab("单词与术语", "term", "character.book.closed", count(.term))
                        tab("公式", "formula", "function", count(.formula))
                        tab("概念", "callout", "lightbulb", count(.callout))
                        tab("图示与表格", "visuals", "photo.on.rectangle", count(.image) + count(.diagram) + count(.table))
                        Spacer(minLength: 0)
                    }
                }
                HStack(spacing: 8) {
                    SearchBox(placeholder: book == nil ? "搜索笔记与内容" : "搜索这本笔记", text: $model.searchText)
                    if book != nil { ChoicePicker(title: "章节范围", selection: model.chapterFilter ?? "all", options: [ChoiceOption(id: "all", title: "所有章节")] + chapters.map { ChoiceOption(id: $0.id, title: $0.title) }) { model.chapterFilter = $0 == "all" ? nil : $0; reconcileSelection() } }
                    if !tags.isEmpty { ChoicePicker(title: "标签筛选", selection: model.tagFilter ?? "all", options: [ChoiceOption(id: "all", title: "所有标签")] + tags.map { ChoiceOption(id: $0, title: $0, icon: "tag") }) { model.tagFilter = $0 == "all" ? nil : $0; reconcileSelection() } }
                    ChoicePicker(title: "排序", selection: model.noteSort, options: [ChoiceOption(id: "updated", title: "最近编辑"), ChoiceOption(id: "created", title: "最近创建"), ChoiceOption(id: "title", title: "标题顺序")]) { model.noteSort = $0 }
                    QuietIconButton(icon: model.selectingNotes ? "checkmark.circle.fill" : "checkmark.circle", label: model.selectingNotes ? "结束多选" : "多选笔记") { model.selectingNotes.toggle(); model.selectedNotes = []; model.notebookSection = "notes" }
                }
            }.padding(.horizontal, 22).padding(.top, 20).padding(.bottom, 15)
            Rectangle().fill(Theme.border).frame(height: 1)
            if model.selectingNotes { selectionBar }
            }
            }
            if book != nil && model.notebookSection != "notes" { NotebookTopicsView() }
            else { readingLayout }
        }.onAppear { reconcileSelection() }.onChange(of: model.searchText) { _, _ in reconcileSelection() }
    }
    private var notebookHeader: some View {
        HStack(spacing: 0) {
            NotebookContextTitle(book: book, title: model.pageTitle,
                summary: book == nil ? "\(notes.count) 篇笔记" : "\(chapters.count) 个章节 · \(bookNotes.count) 篇笔记 · 已读 \(bookNotes.filter { model.isRead($0.id) }.count) 篇")
                .frame(minWidth: 150, maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 0) {
                if let book {
                    NotebookBarDivider()
                    NotebookHeaderAction(title: "书内复习", icon: "rectangle.on.rectangle", count: bookNotes.flatMap(\.blocks).filter(\.isReviewCard).count) { model.reviewBookID = book.id }
                        .help("复习这本笔记中的 \(bookNotes.flatMap(\.blocks).filter(\.isReviewCard).count) 张知识卡").accessibilityIdentifier("book-review")
                    NotebookBarDivider()
                    NotebookHeaderAction(title: "AI 补充", icon: "sparkles") { model.prepareConversationDraft("我想补充《\(book.title)》中的内容：", notebookID: book.id) }
                        .accessibilityIdentifier("book-ai-supplement")
                }
                NotebookBarDivider()
                NotebookHeaderAction(title: "写笔记", icon: "plus", emphasized: true) { model.newNote() }
                    .accessibilityIdentifier("book-new-note")
            }.fixedSize()
        }
        .background(Theme.secondary)
        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(Theme.border.opacity(0.7), lineWidth: 0.75).allowsHitTesting(false) }
        .accessibilityElement(children: .contain).accessibilityLabel("笔记本工具栏")
    }
    private func reconcileSelection() { if !notes.contains(where: { $0.id == model.selectedNoteID }) { model.selectedNoteID = notes.first?.id } }
    private func count(_ kind: BlockKind) -> Int { bookNotes.flatMap(\.blocks).filter { $0.kind == kind }.count }
    private func tab(_ title: String, _ id: String, _ icon: String, _ count: Int) -> some View { Button { model.notebookSection = id; model.selectingNotes = false; model.selectedNotes = [] } label: { HStack(spacing: 6) { Image(systemName: icon).font(.system(size: 11)); Text(title).font(.system(size: 11, weight: .medium)); Text("\(count)").font(.system(size: 9)).foregroundStyle(.secondary).monospacedDigit() }.padding(.horizontal, 10).padding(.vertical, 9) }.buttonStyle(FeedbackStyle(selected: model.notebookSection == id, compact: true)) }
    private var selectionBar: some View {
        HStack(spacing: 8) {
            ActionButton(title: model.selectedNotes.isSuperset(of: notes.map(\.id)) ? "取消全选" : "全选") { if model.selectedNotes.isSuperset(of: notes.map(\.id)) { model.selectedNotes = [] } else { model.selectedNotes = Set(notes.map(\.id)) } }
            Text("已选 \(model.selectedNotes.count) 篇").font(.system(size: 11)).foregroundStyle(.secondary)
            Spacer()
            ActionButton(title: "移动", icon: "folder") { model.noteAction = .init(kind: "move", ids: model.selectedNotes) }.disabled(model.selectedNotes.isEmpty)
            ActionButton(title: "标签", icon: "tag") { model.noteAction = .init(kind: "tags", ids: model.selectedNotes) }.disabled(model.selectedNotes.isEmpty)
            ActionButton(title: "标为已读", icon: "checkmark") { model.markRead(model.selectedNotes, completed: true) }.disabled(model.selectedNotes.isEmpty)
            ActionButton(title: "移到回收站", icon: "trash") { if model.bulkEdit(model.selectedNotes, title: "移除 \(model.selectedNotes.count) 篇笔记", change: { $0.deletedAt = Date() }) { model.selectedNotes = [] } }.disabled(model.selectedNotes.isEmpty)
        }.padding(.horizontal, 20).padding(.vertical, 9).background(Theme.accent.opacity(0.05))
    }
    private var readingLayout: some View {
        HStack(spacing: 0) {
            ReaderChrome(expanded: !model.readingMode && !(model.library.settings.showOriginal && !(model.currentNote?.sourceIDs.isEmpty ?? true)), axis: .horizontal, width: 261) {
            HStack(spacing: 0) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    if notes.isEmpty { VStack(alignment: .leading, spacing: 12) { Image(systemName: "doc.text.magnifyingglass").font(.system(size: 25, weight: .light)).foregroundStyle(Theme.accent); Text(model.searchText.isEmpty ? "还没有笔记" : "没有匹配内容").font(.system(size: 14, weight: .medium)); Text("可以写下第一篇，或调整上方的筛选。").font(.system(size: 11)).foregroundStyle(.secondary).lineSpacing(4) }.padding(22) }
                    if !LibrarySearch.query(model.searchText).isEmpty { Text("\(notes.count) 篇匹配笔记").font(.system(size: 10)).foregroundStyle(.secondary).padding(.horizontal, 12).padding(.vertical, 5) }
                    ForEach(notes) { note in NoteListRow(note: note) }
                }.padding(10)
            }.frame(width: 260).background(Theme.background.opacity(0.5))
            Rectangle().fill(Theme.border).frame(width: 1)
            }
            }
            if let note = model.currentNote, notes.contains(where: { $0.id == note.id }) { NoteReader(note: note).frame(maxWidth: .infinity) }
            else { VStack(spacing: 14) { Image(systemName: "book.pages").font(.system(size: 39, weight: .ultraLight)).foregroundStyle(Theme.accent); Text("选择一篇笔记，开始阅读").font(.system(size: 14)).foregroundStyle(.secondary) }.frame(maxWidth: .infinity, maxHeight: .infinity) }
        }
    }
}
// The notebook identity and its commands share one quiet contextual surface.
private struct NotebookContextTitle: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var center: ChoiceCenter
    let book: Notebook?
    let title: String
    let summary: String
    @State private var rect = CGRect.zero
    @FocusState private var focused: Bool
    private var sourceID: String { "notebook-title-" + (book?.id ?? "library") }
    private var expanded: Bool { center.presentation?.sourceID == sourceID }
    var body: some View {
        Group {
            if let book {
                Button { toggle() } label: { identity(disclosure: true) }
                    .buttonStyle(NotebookBarStyle(selected: expanded))
                    .focusable(interactions: .edit).focusEffectDisabled().focused($focused)
                    .onKeyPress(.space) { toggle(fromKeyboard: true); return .handled }
                    .onKeyPress(.return) { toggle(fromKeyboard: true); return .handled }
                    .overlay { if focused { RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.accent.opacity(0.6), lineWidth: 1.5).padding(3).allowsHitTesting(false) } }
                    .help("管理《\(book.title)》")
                    .accessibilityLabel("管理《\(book.title)》").accessibilityIdentifier("notebook-title-menu")
                    .accessibilityValue(expanded ? "已展开" : "已收起")
            } else { identity(disclosure: false) }
        }
        .background(GeometryReader { proxy in
            Color.clear.onAppear { rect = proxy.frame(in: .named(center.space)) }
                .onChange(of: proxy.frame(in: .named(center.space))) { _, next in
                    if expanded && rect != next { center.dismiss() }
                    rect = next
                }
        })
        .background {
            PointerObserver(onDown: { point, bounds, _ in
                // Mouse events must also cancel a delayed Escape focus return.
                if center.focusReturnSourceID == sourceID { center.focusReturnSourceID = nil }
                if !bounds.contains(point) { focused = false }
            }).allowsHitTesting(false)
        }
        .onChange(of: center.presentation?.sourceID) { old, next in
            if old == sourceID && next == nil {
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(140))
                    guard center.presentation == nil, center.popover == nil, center.focusReturnSourceID == sourceID else { return }
                    focused = true; center.focusReturnSourceID = nil
                }
            }
        }
        .onDisappear { if expanded { center.dismiss() } }
    }
    private func identity(disclosure: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: book == nil ? "rectangle.stack" : "book.closed")
                .font(.system(size: 20, weight: .regular))
                .foregroundStyle(book.map { Theme.colors[abs($0.color % 5)] } ?? Theme.accent)
                .frame(width: 25).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 7) {
                    Text(title).font(.system(size: 17, weight: .semibold)).lineLimit(1).truncationMode(.tail)
                    if disclosure { Image(systemName: "chevron.down").font(.system(size: 8, weight: .semibold)).foregroundStyle(.secondary).frame(width: 10).accessibilityHidden(true) }
                }
                Text(summary).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
            }
        }.padding(.horizontal, 14).frame(height: 54).contentShape(Rectangle())
    }
    private func toggle(fromKeyboard: Bool = false) {
        guard let book else { return }
        if !fromKeyboard { focused = false }
        if expanded { center.dismiss(restoreFocus: fromKeyboard) }
        else {
            focused = false
            center.presentation = .init(sourceID: sourceID, title: book.title, rect: rect, options: bookMenuOptions(book), selected: nil, choose: { model.performBookAction($0, book: book) })
        }
    }
}
private struct NotebookBarDivider: View {
    var body: some View {
        Rectangle().fill(LinearGradient(colors: [.clear, Theme.border, Theme.border, .clear], startPoint: .top, endPoint: .bottom))
            .frame(width: 1, height: 24).allowsHitTesting(false).accessibilityHidden(true)
    }
}
private struct NotebookHeaderAction: View {
    var title: String
    var icon: String
    var count: Int? = nil
    var emphasized = false
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 12, weight: .medium)).frame(width: 16)
                Text(title).font(.system(size: 12, weight: .medium))
            }.padding(.horizontal, 15).frame(height: 54).contentShape(Rectangle())
        }.buttonStyle(NotebookBarStyle(emphasized: emphasized))
            .accessibilityLabel(title).accessibilityValue(count.map { "\($0) 张知识卡" } ?? "")
    }
}
private struct NotebookBarStyle: ButtonStyle {
    var emphasized = false
    var selected = false
    func makeBody(configuration: Configuration) -> some View { Surface(configuration: configuration, emphasized: emphasized, selected: selected) }
    private struct Surface: View {
        @EnvironmentObject private var model: AppModel
        @Environment(\.accessibilityReduceMotion) private var reduced
        @Environment(\.isEnabled) private var enabled
        @State private var hovered = false
        let configuration: Configuration
        let emphasized: Bool
        let selected: Bool
        private var pressed: Bool { enabled && configuration.isPressed }
        private var activeHover: Bool { enabled && hovered }
        private var fill: Color {
            if emphasized { return Theme.accent.opacity(pressed ? 0.19 : activeHover ? 0.13 : 0.065) }
            if selected { return Theme.accent.opacity(0.08) }
            return Color.primary.opacity(pressed ? 0.08 : activeHover ? 0.045 : 0)
        }
        var body: some View {
            configuration.label.foregroundStyle(emphasized || selected ? Theme.accent : Color.primary)
                .background {
                    Rectangle().fill(fill)
                        .animation(reduced || model.library.settings.reduceMotion ? nil : .easeOut(duration: 0.10), value: activeHover)
                        .animation(nil, value: pressed).animation(nil, value: selected)
                }
                .opacity(enabled ? 1 : 0.4).contentShape(Rectangle())
                .onHover { hovered = $0 }.onDisappear { hovered = false }
        }
    }
}

struct NoteListRow: View {
    @EnvironmentObject var model: AppModel
    let note: Note
    @State private var hovered = false
    private var selected: Bool { model.selectedNoteID == note.id }
    var body: some View {
        HStack(spacing: 7) {
            if model.selectingNotes { Button { if model.selectedNotes.contains(note.id) { model.selectedNotes.remove(note.id) } else { model.selectedNotes.insert(note.id) } } label: { Image(systemName: model.selectedNotes.contains(note.id) ? "checkmark.circle.fill" : "circle").foregroundStyle(model.selectedNotes.contains(note.id) ? Theme.accent : .secondary).frame(width: 25, height: 30) }.buttonStyle(.plain).accessibilityLabel("选择 " + note.title) }
            Button { model.selectedNoteID = note.id; model.noteSearchRequest += 1 } label: {
                VStack(alignment: .leading, spacing: 7) {
                    HStack(spacing: 6) { HighlightedText(LibrarySearch.matches(note.title, query: model.searchText) ? LibrarySearch.snippet(note.title, query: model.searchText, limit: 62) : note.title, query: model.searchText).font(.system(size: 12, weight: .semibold)).lineLimit(2); Spacer(minLength: 0); if note.pinned == true { Image(systemName: "pin.fill").font(.system(size: 9)).foregroundStyle(Theme.accent).accessibilityLabel("已置顶") }; if note.favorite { Image(systemName: "star.fill").font(.system(size: 9)).foregroundStyle(.orange) }; if model.isRead(note.id) { Image(systemName: "checkmark.circle").font(.system(size: 9)).foregroundStyle(Theme.accent) } }
                    HighlightedText(LibrarySearch.noteHits(note, query: model.searchText).first.map { LibrarySearch.snippet($0.text, query: model.searchText, limit: 62) } ?? LibrarySearch.plain(note.blocks.first(where: { [.paragraph, .bullet, .callout].contains($0.kind) })?.text ?? note.blocks.first?.text ?? "空白笔记"), query: model.searchText).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(3).lineSpacing(3)
                    HStack { Text(model.library.chapters.first { $0.id == note.chapterID }?.title ?? "").lineLimit(1); Spacer(minLength: 3); Text(note.updatedAt.formatted(.dateTime.month().day())) }.font(.system(size: 9)).foregroundStyle(.tertiary)
                    if !note.tags.isEmpty { HighlightedText(note.tags.prefix(3).map { "#" + $0 }.joined(separator: "  "), query: model.searchText).font(.system(size: 9)).foregroundStyle(Theme.accent.opacity(0.85)).lineLimit(1) }
                }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 13).padding(.horizontal, 12).contentShape(Rectangle())
            }.buttonStyle(.plain)
        }.background(selected ? Theme.accent.opacity(0.10) : hovered ? Color.primary.opacity(0.045) : .clear, in: RoundedRectangle(cornerRadius: 10)).overlay(alignment: .leading) { if selected { Capsule().fill(Theme.accent).frame(width: 3).padding(.vertical, 15) } }.onHover { hovered = $0 }.noteContextActions(note)
    }
}

struct NoteReader: View {
    @EnvironmentObject var model: AppModel
    var note: Note
    @Environment(\.accessibilityReduceMotion) var reduced
    @State private var showInfo = false
    @State private var outline = false
    @State private var visibleBlockID: String?
    @State private var searchIndex = 0
    private var query: String { LibrarySearch.query(model.searchText) }
    private var searchHits: [LibrarySearch.Hit] { LibrarySearch.noteHits(note, query: query) }
    @FocusState private var readerFocused: Bool
    @EnvironmentObject private var choices: ChoiceCenter
    var body: some View {
        VStack(spacing: 0) {
            readerToolbar
            Divider().opacity(0.5)
            if !query.isEmpty {
                SearchMatchBar(query: query, index: searchIndex, count: searchHits.count,
                    previous: { moveSearch(-1) }, next: { moveSearch(1) }, close: { model.searchText = "" })
            }
            HSplitView {
                ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        VStack(alignment: .leading, spacing: 12) {
                            if note.deletedAt != nil { Label("已移到回收站", systemImage: "trash").font(.caption).foregroundStyle(.orange) }
                            HighlightedText(note.title).font(.system(size: min(34, model.library.settings.fontSize + 12), weight: .semibold)).lineSpacing(5).textSelection(.enabled)
                            HStack(spacing: 10) { Text(note.updatedAt, style: .date); if !note.tags.isEmpty { HighlightedText(note.tags.joined(separator: " · ")) }; if note.locked { Label("已锁定", systemImage: "lock") } }.font(.system(size: 11)).foregroundStyle(.tertiary).id("tags-" + note.id)
                        }.padding(.bottom, 8).id("title-" + note.id)
                        ForEach(note.blocks) { block in
                            ContentBlockView(block: block, fontSize: model.library.settings.fontSize, spacing: model.library.settings.lineSpacing).id(block.id)
                            if showInfo {
                                HStack(alignment: .top, spacing: 8) { Text(block.origin == "addition" ? "AI 补充" : block.origin == "correction" ? "已校正" : "来自原稿").foregroundStyle(Theme.accent); VStack(alignment: .leading) { ForEach(block.citations, id: \.self) { citation in if let url = URL(string: citation), ["https", "http"].contains(url.scheme ?? "") { Link(citation, destination: url) } else { Text(model.citationLabel(citation)) } } } }.font(.caption).padding(.bottom, 6)
                            }
                        }
                        if !note.sourceIDs.isEmpty {
                            Divider().padding(.top, 12)
                            Button { model.updateSettings { $0.showOriginal = true } } label: { Label("\(note.sourceIDs.count) 份原稿", systemImage: "photo.on.rectangle").font(.caption).padding(.horizontal, 12).frame(minHeight: 36).contentShape(Rectangle()) }.buttonStyle(FeedbackStyle()).foregroundStyle(.secondary)
                        }
                    }.scrollTargetLayout()
                        .frame(maxWidth: model.library.settings.readingWidth ?? 660, alignment: .leading).padding(.horizontal, 28).padding(.vertical, 38).frame(maxWidth: .infinity)
                }.scrollPosition(id: $visibleBlockID, anchor: .top).id(note.id)
                     .onAppear { if query.isEmpty, let id = model.focusedBlockID { proxy.scrollTo(id, anchor: .center) } }
                    .task(id: note.id + "|" + query + "|" + String(model.noteSearchRequest)) {
                        guard !query.isEmpty else { return }
                        do { try await Task.sleep(for: .milliseconds(140)) } catch { return }
                        searchIndex = 0
                        if let hit = searchHits.first { proxy.scrollTo(hit.id, anchor: .top) }
                    }
                    .onChange(of: model.focusedBlockID) { _, id in if let id {
                        withAnimation(reduced || model.library.settings.reduceMotion ? nil : .easeOut(duration: 0.18)) { proxy.scrollTo(id, anchor: .top) }
                    } }
                }
                if model.library.settings.showOriginal, !note.sourceIDs.isEmpty { OriginalPanel(ids: note.sourceIDs).frame(minWidth: 280, idealWidth: 380, maxWidth: 620) }
            }
            HStack(spacing: 10) {
                ActionButton(title: "上一篇", icon: "arrow.left") { adjacent(-1) }.disabled(noteIndex == 0)
                Spacer()
                Text("第 \(noteIndex + 1) / \(readingOrder.count) 篇").font(.system(size: 11)).foregroundStyle(.secondary).monospacedDigit()
                Spacer()
                ActionButton(title: noteIndex + 1 < readingOrder.count ? "下一篇" : "最后一篇", icon: "arrow.right") { adjacent(1) }.disabled(noteIndex + 1 >= readingOrder.count)
            }.padding(.horizontal, 18).padding(.vertical, 8).background(Theme.background.opacity(0.6))
        }.environment(\.searchHighlightQuery, query).focusable(model.readingMode).focusEffectDisabled().focused($readerFocused)
            .onKeyPress(.escape) {
                guard model.readingMode else { return .ignored }
                if choices.popover != nil || choices.presentation != nil { choices.dismiss() } else if outline { outline = false } else { setReadingMode(false) }
                return .handled
            }
            .onExitCommand { if choices.popover != nil || choices.presentation != nil { choices.dismiss() } else if outline { outline = false } else { setReadingMode(false) } }
            .onAppear { model.trackReading(note.id) }
            .onChange(of: note.id) { _, id in visibleBlockID = nil; choices.dismiss(); model.trackReading(id) }
            .onChange(of: model.library.settings.sidebarCollapsed) { _, _ in choices.dismiss() }
            .onChange(of: choices.popover?.sourceID) { _, id in if id != nil { readerFocused = false } else if model.readingMode { readerFocused = true } }
            .onChange(of: model.readingMode) { _, enabled in outline = false; choices.dismiss(); readerFocused = enabled }
            .overlay(alignment: .topLeading) {
                if outline { GeometryReader { geometry in ChapterNavigator(note: note, panelHeight: min(430, max(260, geometry.size.height - 68))) { outline = false }.padding(.leading, 12).padding(.top, 57) } }
            }
            .animation(reduced || model.library.settings.reduceMotion ? nil : .easeInOut(duration: 0.2), value: model.library.settings.showOriginal)
    }
    private func moveSearch(_ offset: Int) {
        guard !searchHits.isEmpty else { return }
        searchIndex = (searchIndex + offset + searchHits.count) % searchHits.count
        model.focusedBlockID = searchHits[searchIndex].id
    }
    private var readerToolbar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 5) {
                QuietIconButton(icon: "list.bullet.indent", label: "章节目录", selected: outline, size: 32) { outline.toggle() }
                Text(model.location(note)).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
            }.frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 8) {
                Button { setReadingMode(!model.readingMode) } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "book").font(.system(size: 13, weight: .medium))
                        Text(model.readingMode ? "退出阅读" : "阅读").font(.system(size: 12, weight: .medium))
                    }.frame(width: 92, height: 32).contentShape(Rectangle())
                }.buttonStyle(FeedbackStyle(tinted: true, selected: model.readingMode, compact: true))
                    .help(model.readingMode ? "退出阅读模式（⌘⇧R / Esc）" : "阅读模式（⌘⇧R）")
                    .accessibilityLabel(model.readingMode ? "退出阅读模式" : "阅读模式")
                    .accessibilityIdentifier("reader-focus")
                HStack(spacing: 2) {
                    FloatingControl(id: "reader-style", title: "阅读样式", size: CGSize(width: 296, height: 216), willOpen: { outline = false }) { _ in
                        Text(verbatim: "Aa").font(.system(size: 14, weight: .medium, design: .serif)).frame(width: 32, height: 32)
                    } panel: { ReaderStylePanel() }
                    if !note.sourceIDs.isEmpty {
                        QuietIconButton(icon: "rectangle.lefthalf.inset.filled", label: model.library.settings.showOriginal ? "收起原稿" : "对照原稿", selected: model.library.settings.showOriginal, size: 32) {
                            model.updateSettings { $0.showOriginal.toggle() }
                        }.accessibilityIdentifier("reader-original")
                    }
                }.padding(2).background(Theme.secondary, in: RoundedRectangle(cornerRadius: 9))
                readerActions
            }.fixedSize()
        }.padding(.horizontal, 18).padding(.vertical, 10)
    }
    private var readerActions: some View {
        FloatingControl(id: "reader-actions", title: "更多笔记操作", size: CGSize(width: 250, height: 354), willOpen: { outline = false }) { _ in
            Image(systemName: "ellipsis").font(.system(size: 14, weight: .medium)).frame(width: 32, height: 32)
        } panel: { ReaderActionsPanel(noteID: note.id, showInfo: $showInfo) }
    }
    private func setReadingMode(_ enabled: Bool) {
        outline = false; choices.dismiss()
        model.readingMode = enabled
    }
    private var orderedChapters: [Chapter] {
        let book = model.library.chapters.first { $0.id == note.chapterID }?.notebookID
        return model.library.chapters.filter { $0.notebookID == book }.sorted { $0.order < $1.order }
    }
    private var readingOrder: [Note] { orderedChapters.flatMap { chapter in model.activeNotes.filter { $0.chapterID == chapter.id }.sorted { $0.createdAt < $1.createdAt } } }
    private var noteIndex: Int { readingOrder.firstIndex { $0.id == note.id } ?? 0 }
    private func adjacent(_ offset: Int) {
        let index = noteIndex + offset
        guard readingOrder.indices.contains(index) else { return }
        model.searchText = ""; model.tagFilter = nil; model.openNote(readingOrder[index])
    }
    private func printNote() { model.exportNote = note }
}

struct ContentBlockView: View {
    @EnvironmentObject var model: AppModel
    let block: ContentBlock
    var fontSize: Double = 16
    var spacing: Double = 7
    var boxed = true
    var body: some View {
        Group {
            switch block.kind {
            case .heading:
                VStack(alignment: .leading, spacing: 10) {
                    HighlightedText(block.text).font(.system(size: fontSize + 5, weight: .semibold)).fixedSize(horizontal: false, vertical: true)
                    if !block.detail.isEmpty { text(block.detail).foregroundStyle(.secondary) }
                }.padding(.top, 16).padding(.bottom, 2)
            case .bullet: HStack(alignment: .top, spacing: 10) { Circle().fill(Theme.accent).frame(width: 5, height: 5).padding(.top, 8); VStack(alignment: .leading, spacing: 10) { text(block.text); if !block.detail.isEmpty { text(block.detail) } } }
            case .term, .callout:
                VStack(alignment: .leading, spacing: 10) { HStack(spacing: 8) { Image(systemName: block.kind.icon).foregroundStyle(Theme.accent); HighlightedText(block.text).font(.system(size: fontSize, weight: .semibold)) }; if !block.detail.isEmpty { text(block.detail) } }.padding(boxed ? 18 : 0).frame(maxWidth: .infinity, alignment: .leading).background(Theme.accent.opacity(boxed ? 0.055 : 0), in: RoundedRectangle(cornerRadius: 12))
            case .formula:
                VStack(alignment: .leading, spacing: 10) { FormulaView(formula: block.text, fontSize: fontSize + 1); if !block.detail.isEmpty { text(block.detail) } }
            case .table:
                VStack(alignment: .leading, spacing: 10) {
                    if !block.text.isEmpty { HighlightedText(block.text).font(.system(size: fontSize, weight: .semibold)) }
                    ReadingTableView(rows: block.rows, fontSize: fontSize)
                    if !block.detail.isEmpty { text(block.detail) }
                }
            case .diagram:
                VStack(alignment: .leading, spacing: 12) {
                    if !block.text.isEmpty { HighlightedText(block.text).font(.system(size: fontSize, weight: .semibold)) }
                    if let diagram = block.diagram { StudyDiagramView(diagram: diagram) }
                    if !block.detail.isEmpty { text(block.detail) }
                    if let source = block.citations.first(where: { model.asset($0) != nil }) {
                        Button { model.selectedSourceID = source } label: { Label("查看原稿", systemImage: "doc.text.magnifyingglass").font(.system(size: 11)) }.buttonStyle(FeedbackStyle(compact: true)).foregroundStyle(.secondary)
                    }
                }
            case .image:
                VStack(alignment: .leading, spacing: 8) { if let id = block.assetID, let url = model.assetURL(id) { SourceImageView(url: url, revision: model.asset(id)?.digest ?? "").clipShape(RoundedRectangle(cornerRadius: 12)).onTapGesture { model.selectedSourceID = id } }; if !block.text.isEmpty { HighlightedText(block.text).font(.caption).foregroundStyle(.secondary) }; if !block.detail.isEmpty { text(block.detail) } }
            case .example:
                VStack(alignment: .leading, spacing: 9) { Label("例题", systemImage: "pencil.and.list.clipboard").font(.caption).foregroundStyle(Theme.accent); text(block.text); if !block.detail.isEmpty { text(block.detail) } }.padding(18).frame(maxWidth: .infinity, alignment: .leading).background(Theme.secondary, in: RoundedRectangle(cornerRadius: 12))
            default:
                VStack(alignment: .leading, spacing: 10) { text(block.text); if !block.detail.isEmpty { text(block.detail) } }
            }
        }.textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
    }
    private func text(_ value: String) -> some View {
        VStack(alignment: .leading, spacing: max(10, spacing + 5)) {
            ForEach(Array(value.components(separatedBy: "\n\n").enumerated()), id: \.offset) { _, paragraph in
                HighlightedText(paragraph, markdown: true).font(.system(size: fontSize)).lineSpacing(spacing).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct OriginalPanel: View {
    @EnvironmentObject var model: AppModel
    let ids: [String]
    @State private var selected = 0
    @State private var mode = "original"
    private var asset: SourceAsset? { ids.indices.contains(selected) ? model.asset(ids[selected]) : nil }
    var body: some View {
        VStack(spacing: 0) {
            HStack { Text("原稿对照").font(.system(size: 12, weight: .medium)); Spacer(); if let asset { QuietIconButton(icon: "arrow.up.left.and.arrow.down.right", label: "展开原稿") { model.selectedSourceID = asset.id } }; QuietIconButton(icon: "xmark", label: "关闭原稿") { model.updateSettings { $0.showOriginal = false } } }.padding(12)
            if ids.count > 1 { ChoicePicker(title: "原稿", selection: String(selected), options: ids.enumerated().map { ChoiceOption(id: String($0.offset), title: model.asset($0.element)?.displayName ?? "原稿") }) { selected = Int($0) ?? 0; mode = "original" }.padding(.horizontal, 12).padding(.bottom, 10) }
            if let asset, let url = model.assetURL(asset.id) {
                if asset.isImage { ZoomableSourceImage(url: url, revision: asset.digest).id(asset.id) }
                else {
                    Picker("对照内容", selection: $mode) { Text("原件").tag("original"); Text("提取内容").tag("text") }.pickerStyle(.segmented).labelsHidden().padding(.horizontal, 12).padding(.bottom, 10)
                    if mode == "original" { SourceQuickLook(url: url) }
                    else { ScrollView { if let document = asset.document { SourceDocumentContent(document: document, fontSize: 13).padding(16) } else { Text("此文件没有提取文本").foregroundStyle(.secondary).padding(16) } } }
                }
            } else { ContentUnavailableView("原稿不可用", systemImage: "doc.questionmark") }
        }.background(Theme.background).onChange(of: ids) { _, _ in selected = 0; mode = "original" }
    }
}



struct HistoryView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) var dismiss
    @State private var expanded: Set<String> = []
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack { VStack(alignment: .leading, spacing: 7) { Text("整理与修改记录").font(.system(size: 21, weight: .semibold)); Text("比较修改前后，也可以撤销一次完整的整理。").font(.system(size: 11)).foregroundStyle(.secondary) }; Spacer(); QuietIconButton(icon: "xmark", label: "关闭修改记录") { dismiss() }.keyboardShortcut(.cancelAction) }.padding(24)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 13) {
                    if model.library.receipts.isEmpty { Text("还没有修改记录").font(.system(size: 13)).foregroundStyle(.secondary).padding(25) }
                    ForEach(model.library.receipts.reversed()) { receipt in
                        VStack(alignment: .leading, spacing: 13) {
                            HStack { VStack(alignment: .leading, spacing: 6) { Text(receipt.title).font(.system(size: 13, weight: .semibold)); Text(receipt.date.formatted(date: .abbreviated, time: .shortened)).font(.system(size: 10)).foregroundStyle(.secondary) }; Spacer(); if receipt.undone { TagPill(text: "已撤销") } else { ActionButton(title: "撤销", icon: "arrow.uturn.backward") { model.undo(receipt.id) } } }
                            ForEach(receipt.changes, id: \.after.id) { change in
                                let key = receipt.id + change.after.id
                                Button { if expanded.contains(key) { expanded.remove(key) } else { expanded.insert(key) } } label: { HStack { Image(systemName: expanded.contains(key) ? "chevron.down" : "chevron.right").font(.system(size: 9)); Text(change.after.title).font(.system(size: 12)); Spacer(); TagPill(text: change.before == nil ? "新建" : "更新") }.padding(8) }.buttonStyle(FeedbackStyle())
                                if expanded.contains(key) { HStack(alignment: .top, spacing: 18) { VStack(alignment: .leading, spacing: 9) { Text("修改前").font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary); Text(change.before.map(NoteEngine.markdown) ?? "新建笔记").font(.system(size: 11)).lineSpacing(5).textSelection(.enabled) }.frame(maxWidth: .infinity, alignment: .leading); Rectangle().fill(Theme.border).frame(width: 1); VStack(alignment: .leading, spacing: 9) { Text("修改后").font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.accent); Text(NoteEngine.markdown(change.after)).font(.system(size: 11)).lineSpacing(5).textSelection(.enabled) }.frame(maxWidth: .infinity, alignment: .leading) }.padding(13) }
                            }
                        }.padding(18).background(Theme.background, in: RoundedRectangle(cornerRadius: 14))
                    }
                }.padding(.horizontal, 24).padding(.bottom, 24)
            }
        }.frame(width: 840, height: 640).background(Theme.panel)
    }
}
struct BookStructureView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) var dismiss
    let bookID: String
    @State private var title = ""
    @State private var newChapter = ""
    @State private var summary = ""
    @State private var subject = ""
    private var chapters: [Chapter] { model.library.chapters.filter { $0.notebookID == bookID }.sorted { $0.order < $1.order } }
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack { Text("笔记本与章节").font(.system(size: 21, weight: .semibold)); Spacer(); ActionButton(title: "完成", primary: true) { model.renameNotebook(bookID, title: title); _ = model.mutate { state in if let i = state.notebooks.firstIndex(where: { $0.id == bookID }) { state.notebooks[i].summary = summary; state.notebooks[i].subject = subject } }; dismiss() } }
            VStack(alignment: .leading, spacing: 8) { Text("笔记本名称").font(.system(size: 11)).foregroundStyle(.secondary); TextField("笔记本名称", text: $title).textFieldStyle(FieldStyle()).onSubmit { model.renameNotebook(bookID, title: title) } }
            HStack { TextField("学科 / 主题", text: $subject).textFieldStyle(FieldStyle()); TextField("简介", text: $summary).textFieldStyle(FieldStyle()) }
            HStack { Text("封面颜色").font(.system(size: 11)).foregroundStyle(.secondary); Spacer(); ForEach(0..<Theme.colors.count, id: \.self) { index in Button { _ = model.mutate { state in if let i = state.notebooks.firstIndex(where: { $0.id == bookID }) { state.notebooks[i].color = index } } } label: { Circle().fill(Theme.colors[index]).frame(width: 23, height: 23).overlay { if model.library.notebooks.first(where: { $0.id == bookID })?.color == index { Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)).foregroundStyle(.white) } }.padding(4) }.buttonStyle(FeedbackStyle(compact: true)).accessibilityLabel("封面颜色 \(index + 1)") } }
            HStack { Text("封面样式").font(.system(size: 11)).foregroundStyle(.secondary); Spacer(); ChoicePicker(title: "封面样式", selection: model.library.notebooks.first { $0.id == bookID }?.coverStyle ?? "paper", options: [ChoiceOption(id: "paper", title: "纸页"), ChoiceOption(id: "index", title: "索引")]) { value in _ = model.mutate { state in if let i = state.notebooks.firstIndex(where: { $0.id == bookID }) { state.notebooks[i].coverStyle = value } } } }
            HStack { Text("章节顺序").font(.system(size: 14, weight: .semibold)); Spacer(); Text("锁定的章节会保留原有内容").font(.system(size: 10)).foregroundStyle(.secondary) }
            ScrollView { LazyVStack(spacing: 9) { ForEach(chapters) { chapter in ChapterManagementRow(chapter: chapter).padding(10).background(Theme.background, in: RoundedRectangle(cornerRadius: 10)) } } }
            HStack { TextField("新章节名称", text: $newChapter).textFieldStyle(FieldStyle()).onSubmit { addChapter() }; ActionButton(title: "添加", icon: "plus") { addChapter() }.disabled(newChapter.trimmingCharacters(in: .whitespaces).isEmpty) }
        }.padding(26).frame(width: 690, height: 600).background(Theme.panel).onAppear { title = model.library.notebooks.first { $0.id == bookID }?.title ?? ""; summary = model.library.notebooks.first { $0.id == bookID }?.summary ?? ""; subject = model.library.notebooks.first { $0.id == bookID }?.subject ?? "" }
    }
    private func addChapter() { model.addChapter(bookID: bookID, title: newChapter); newChapter = "" }
}
struct ChapterManagementRow: View {
    @EnvironmentObject var model: AppModel
    let chapter: Chapter
    @State private var title = ""
    var body: some View {
        HStack(spacing: 5) {
            Text(String(format: "%02d", chapter.order + 1)).font(.system(size: 10, design: .monospaced)).foregroundStyle(.tertiary).frame(width: 25)
            TextField("章节名", text: $title).textFieldStyle(.plain).font(.system(size: 12)).onSubmit { model.renameChapter(chapter.id, title: title) }
            if title != chapter.title { ActionButton(title: "保存") { model.renameChapter(chapter.id, title: title) } }
            QuietIconButton(icon: chapter.locked ? "lock.fill" : "lock.open", label: chapter.locked ? "解锁 AI 修改章节" : "锁定章节") { model.toggleChapterLock(chapter.id) }
            QuietIconButton(icon: "arrow.up", label: "章节上移") { model.moveChapter(chapter, offset: -1) }
            QuietIconButton(icon: "arrow.down", label: "章节下移") { model.moveChapter(chapter, offset: 1) }
        }.onAppear { title = chapter.title }
    }
}
