import SwiftUI
import AppKit

func noteMenuOptions(_ note: Note, read: Bool) -> [ChoiceOption] {
    [ChoiceOption(id: "edit", title: "编辑笔记", icon: "square.and.pencil"),
     ChoiceOption(id: "rename", title: "重命名", icon: "pencil"),
     ChoiceOption(id: "move", title: "移动到章节…", icon: "folder"),
     ChoiceOption(id: "tags", title: "编辑标签…", icon: "tag"),
     ChoiceOption(id: "duplicate", title: "创建副本", icon: "plus.square.on.square"),
     ChoiceOption(id: "pin", title: note.pinned == true ? "取消置顶" : "置顶笔记", icon: note.pinned == true ? "pin.slash" : "pin"),
     ChoiceOption(id: "favorite", title: note.favorite ? "取消收藏" : "收藏笔记", icon: "star"),
     ChoiceOption(id: "read", title: read ? "标为未读" : "标为已读", icon: "checkmark.circle"),
     ChoiceOption(id: "copy", title: "复制 Markdown", icon: "doc.on.doc"),
     ChoiceOption(id: "export", title: "导出笔记…", icon: "square.and.arrow.up"),
     ChoiceOption(id: "trash", title: "移到回收站", icon: "trash", destructive: true)]
}

struct RightClickSurface: NSViewRepresentable {
    var onClick: (CGPoint) -> Void
    func makeNSView(context: Context) -> ClickView { let view = ClickView(); view.onClick = onClick; return view }
    func updateNSView(_ view: ClickView, context: Context) { view.onClick = onClick }
    final class ClickView: NSView {
        var onClick: (CGPoint) -> Void = { _ in }
        override var isFlipped: Bool { true }
        override func hitTest(_ point: NSPoint) -> NSView? {
            guard let event = NSApp.currentEvent, event.type == .rightMouseDown || event.type == .rightMouseUp || (event.type == .leftMouseDown && event.modifierFlags.contains(.control)) else { return nil }
            return super.hitTest(point)
        }
        override func rightMouseDown(with event: NSEvent) { onClick(convert(event.locationInWindow, from: nil)) }
        override func mouseDown(with event: NSEvent) { if event.modifierFlags.contains(.control) { onClick(convert(event.locationInWindow, from: nil)) } }
    }
}
struct NoteContextActions: ViewModifier {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var center: ChoiceCenter
    let note: Note
    func body(content: Content) -> some View {
        content.overlay { GeometryReader { proxy in RightClickSurface { point in
            let frame = proxy.frame(in: .named(center.space))
            center.presentation = .init(title: note.title, rect: CGRect(x: frame.minX + point.x, y: frame.minY + point.y, width: 1, height: 1), options: noteMenuOptions(note, read: model.isRead(note.id)), selected: nil, choose: { model.performNoteAction($0, note: note) })
        } } }
    }
}
extension View { func noteContextActions(_ note: Note) -> some View { modifier(NoteContextActions(note: note)) } }

struct NoteActionSheet: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) var dismiss
    let action: NoteActionRequest
    @State private var text = ""
    @State private var chapterID = ""
    @State private var mode = "append"
    private var notes: [Note] { model.library.notes.filter { action.ids.contains($0.id) } }
    private var title: String { ["rename": "重命名笔记", "move": "移动笔记", "tags": "编辑标签"][action.kind] ?? "笔记操作" }
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack { Text(title).font(.system(size: 22, weight: .semibold)); Spacer(); TagPill(text: "\(action.ids.count) 篇") }
            Text(notes.prefix(3).map(\.title).joined(separator: "、") + (notes.count > 3 ? " 等" : "")).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(2)
            if action.kind == "move" {
                ScrollView { VStack(alignment: .leading, spacing: 16) { ForEach(model.activeNotebooks) { book in
                    VStack(alignment: .leading, spacing: 7) {
                        Label(book.title, systemImage: "book.closed").font(.system(size: 12, weight: .semibold)).padding(.horizontal, 9)
                        ForEach(model.library.chapters.filter { $0.notebookID == book.id }.sorted { $0.order < $1.order }) { chapter in
                            Button { chapterID = chapter.id } label: { HStack { Text(chapter.title); Spacer(); if chapterID == chapter.id { Image(systemName: "checkmark").foregroundStyle(Theme.accent) } }.font(.system(size: 12)).padding(11).frame(maxWidth: .infinity, alignment: .leading) }.buttonStyle(FeedbackStyle(selected: chapterID == chapter.id))
                        }
                    }
                } } }.frame(height: 270)
            } else {
                if action.kind == "tags", action.ids.count > 1 { ChoicePicker(title: "标签操作", selection: mode, options: [ChoiceOption(id: "append", title: "追加标签"), ChoiceOption(id: "remove", title: "移除这些标签"), ChoiceOption(id: "replace", title: "替换全部标签")]) { mode = $0 } }
                TextField(action.kind == "tags" ? "标签，用逗号分隔" : "笔记名称", text: $text).textFieldStyle(FieldStyle())
                if action.kind == "tags" { Text(action.ids.count == 1 ? "删除文字可以清空标签。" : "这次操作会同时应用到所有选中的笔记。") .font(.system(size: 11)).foregroundStyle(.secondary) }
            }
            HStack { Spacer(); ActionButton(title: "取消") { dismiss() }; ActionButton(title: action.kind == "move" ? "移动到这里" : "保存", primary: true) { save() }.disabled(action.kind == "move" ? chapterID.isEmpty : action.kind == "rename" && text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
        }.padding(28).frame(width: 480).background(Theme.panel).onAppear { if action.kind == "rename" { text = notes.first?.title ?? "" }; if action.kind == "tags", notes.count == 1 { text = notes[0].tags.joined(separator: "，"); mode = "replace" } }
    }
    private func save() {
        var success = false
        if action.kind == "move" { success = model.moveNotes(action.ids, chapterID: chapterID) }
        if action.kind == "rename" { success = model.bulkEdit(action.ids, title: "重命名笔记") { $0.title = text.trimmingCharacters(in: .whitespacesAndNewlines) } }
        if action.kind == "tags" {
            let tags = LibraryEdits.tags(text)
            success = model.bulkEdit(action.ids, title: "更新 \(action.ids.count) 篇笔记的标签") { note in
                if mode == "replace" { note.tags = tags }
                else if mode == "remove" { note.tags.removeAll { tags.contains($0) } }
                else { note.tags = LibraryEdits.tags((note.tags + tags).joined(separator: ",")) }
            }
        }
        if success { dismiss() }
    }
}

struct ReviewView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) var dismiss
    @Environment(\.accessibilityReduceMotion) var reduced
    let bookID: String
    @State private var session: StudySession?
    @State private var previousSession: StudySession?
    @State private var previousRecord: ReviewRecord?
    @State private var resumed = false
    private var notes: [Note] { model.notes(in: bookID).sorted { $0.createdAt < $1.createdAt } }
    private var entries: [(note: Note, block: ContentBlock)] { notes.flatMap { note in note.blocks.filter(\.isReviewCard).map { (note, $0) } } }
    private var entry: (note: Note, block: ContentBlock)? { entries.first { $0.block.id == session?.currentID } }
    private var animation: Animation? { reduced || model.library.settings.reduceMotion ? nil : .easeInOut(duration: 0.18) }
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("书内复习").font(.system(size: 23, weight: .semibold))
                    Text(model.library.notebooks.first { $0.id == bookID }?.title ?? "").font(.system(size: 12)).foregroundStyle(.secondary)
                }
                Spacer()
                if previousSession != nil { QuietIconButton(icon: "arrow.uturn.backward", label: "撤回上次反馈") { undo() } }
                QuietIconButton(icon: "xmark", label: "关闭复习") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            HStack {
                ChoicePicker(title: "复习范围", selection: session?.filter ?? "due", options: [ChoiceOption(id: "due", title: "今日复习"), ChoiceOption(id: "all", title: "全部知识卡"), ChoiceOption(id: "new", title: "新知识卡"), ChoiceOption(id: "again", title: "需要巩固")]) { reset($0) }
                Spacer()
                if resumed { Text("已接续上次进度").font(.system(size: 10)).foregroundStyle(.secondary) }
                if let session, !session.queue.isEmpty { Text("\(min(session.index + 1, session.queue.count)) / \(session.queue.count)").font(.system(size: 12)).foregroundStyle(.secondary).monospacedDigit() }
            }
            if let session, !session.queue.isEmpty {
                ProgressView(value: Double(session.index), total: Double(session.queue.count)).tint(Theme.accent).accessibilityLabel("本轮复习进度")
            }
            if let entry, let session {
                VStack(alignment: .leading, spacing: 18) {
                    HStack { TagPill(text: entry.block.kind.label); Spacer(); Text(session.revealed ? "核对你的回答" : "先试着回忆").font(.system(size: 11)).foregroundStyle(.secondary) }
                    ScrollView {
                        VStack(alignment: .leading, spacing: 22) {
                            Text(StudyLearning.question(entry.block, in: entry.note)).font(.system(size: 22, weight: .medium)).lineSpacing(7).fixedSize(horizontal: false, vertical: true)
                            if session.revealed {
                                VStack(alignment: .leading, spacing: 14) {
                                    Rectangle().fill(Theme.accent.opacity(0.16)).frame(height: 1)
                                    if entry.block.kind == .formula { FormulaView(formula: entry.block.text, fontSize: 18) }
                                    else { Text(entry.block.text).font(.system(size: 16, weight: .semibold)).foregroundStyle(Theme.accent) }
                                    Text(.init(entry.block.detail)).font(.system(size: 16)).lineSpacing(7).fixedSize(horizontal: false, vertical: true)
                                }.transition(.opacity.combined(with: .offset(y: 6)))
                            }
                        }.textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding(.bottom, 5)
                    }
                    HStack { Text(entry.note.title).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1); Spacer(); Button { dismiss(); model.openNote(entry.note); model.focusedBlockID = entry.block.id; model.readingMode = true } label: { Label("看笔记", systemImage: "arrow.up.right").font(.system(size: 11)).padding(7) }.buttonStyle(FeedbackStyle(compact: true)) }
                }.padding(24).frame(maxWidth: .infinity, maxHeight: .infinity).background(Theme.background.opacity(0.65), in: RoundedRectangle(cornerRadius: 16)).id("\(session.index)-\(entry.block.id)").transition(.opacity.combined(with: .offset(y: 5)))
                HStack(spacing: 9) {
                    Button("稍后再看") { skip() }.font(.system(size: 12)).buttonStyle(FeedbackStyle(compact: true)).keyboardShortcut(.rightArrow, modifiers: []).help("右方向键")
                    Spacer()
                    if session.revealed {
                        ActionButton(title: "没想起", icon: "arrow.clockwise") { rate("again") }.keyboardShortcut("1", modifiers: []).help("1 · 本轮再练，10 分钟后复习")
                        ActionButton(title: "不太稳") { rate("hard") }.keyboardShortcut("2", modifiers: []).help("2 · 明天再练")
                        ActionButton(title: "记住了", icon: "checkmark", primary: true) { rate("known") }.keyboardShortcut("3", modifiers: []).help("3 · 延后复习")
                    } else {
                        ActionButton(title: "查看答案", icon: "eye", primary: true) { reveal() }.keyboardShortcut(.space, modifiers: []).help("空格键")
                    }
                }.frame(height: 38)
            } else {
                completion.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }.padding(28).frame(width: 700, height: min(650, (NSScreen.main?.visibleFrame.height ?? 850) - 110)).background(Theme.panel)
            .onAppear { load() }
    }
    private var completion: some View {
        VStack(spacing: 18) {
            Image(systemName: "checkmark.circle").font(.system(size: 36, weight: .light)).foregroundStyle(Theme.accent)
            Text(entries.isEmpty ? "还没有可复习的知识点" : session?.queue.isEmpty == true ? "今天暂时没有到期内容" : "本轮完成").font(.system(size: 22, weight: .semibold))
            if let session, !session.ratings.isEmpty {
                HStack(spacing: 28) {
                    metric("记住了", session.ratings.values.filter { $0 == "known" }.count)
                    metric("需巩固", session.ratings.values.filter { $0 != "known" }.count)
                    metric("稍后看", session.skipped)
                }
                Text("下次复习已按这次反馈安排。").font(.system(size: 12)).foregroundStyle(.secondary)
            } else { Text(entries.isEmpty ? "术语、概念和公式会自动加入复习。" : "也可以主动回顾其他知识卡。").font(.system(size: 12)).foregroundStyle(.secondary) }
            HStack(spacing: 10) {
                if !entries.isEmpty { ActionButton(title: "\(session?.ratings.values.contains(where: { $0 != "known" }) == true ? "再练薄弱项" : "回顾全部")", icon: "arrow.clockwise") { reset(session?.ratings.values.contains(where: { $0 != "known" }) == true ? "again" : "all") } }
                ActionButton(title: "完成", primary: true) { dismiss() }
            }
        }
    }
    private func metric(_ title: String, _ count: Int) -> some View { VStack(spacing: 6) { Text("\(count)").font(.system(size: 23, weight: .medium)).monospacedDigit(); Text(title).font(.system(size: 11)).foregroundStyle(.secondary) } }
    private func load() {
        guard session == nil else { return }
        if let saved = model.library.studySessions?.first(where: { $0.bookID == bookID }), !saved.completed, saved.isValid(for: entries.map(\.block)) {
            session = saved; resumed = true
        } else { reset("due") }
    }
    private func reset(_ filter: String) {
        let next = StudySession(bookID: bookID, filter: filter, queue: StudyLearning.queue(notes: notes, records: model.library.reviewRecords ?? [], filter: filter))
        guard model.saveStudySession(next) else { return }
        withAnimation(animation) { session = next; previousSession = nil; resumed = false }
    }
    private func reveal() {
        guard var next = session else { return }; next.revealed = true
        if model.saveStudySession(next) { withAnimation(animation) { session = next } }
    }
    private func skip() {
        guard var next = session else { return }; next.advance()
        if model.saveStudySession(next) { withAnimation(animation) { session = next; previousSession = nil; resumed = false } }
    }
    private func rate(_ rating: String) {
        guard let entry, let old = session, old.revealed else { return }
        var next = old; next.advance(rating: rating)
        let oldRecord = model.library.reviewRecords?.first { $0.blockID == entry.block.id }
        guard model.review(entry.block.id, rating: rating, session: next) else { return }
        withAnimation(animation) { previousSession = old; previousRecord = oldRecord; session = next; resumed = false }
    }
    private func undo() {
        guard let previousSession, let id = previousSession.currentID else { return }
        guard model.mutate({ state in
            state.reviewRecords?.removeAll { $0.blockID == id }
            if let previousRecord { state.reviewRecords = (state.reviewRecords ?? []) + [previousRecord] }
            state.studySessions?.removeAll { $0.bookID == bookID }
            state.studySessions = (state.studySessions ?? []) + [previousSession]
        }) else { return }
        withAnimation(animation) { session = previousSession; self.previousSession = nil }
    }
}
