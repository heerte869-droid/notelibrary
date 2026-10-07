import SwiftUI

struct BlockInsertion: Equatable {
    let targetID: String
    let after: Bool
}
private struct BlockFrameKey: PreferenceKey {
    static let defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) { value.merge(nextValue(), uniquingKeysWith: { _, new in new }) }
}

struct NoteEditor: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduced
    @State var note: Note
    @State private var draggingID: String?
    @State private var insertion: BlockInsertion?
    @State private var blockFrames: [String: CGRect] = [:]
    @State private var dragPoint: CGPoint?
    private var motion: Animation? { reduced || model.library.settings.reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.86) }
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text("编辑笔记").font(.system(size: 17, weight: .semibold))
                    Text("拖动内容块手柄调整顺序，保存后生效").font(.system(size: 10)).foregroundStyle(.secondary)
                }
                Spacer(); ActionButton(title: "取消") { dismiss() }
                Button { model.saveNote(note) } label: { Text("保存").font(.system(size: 12, weight: .medium)).padding(.horizontal, 18).frame(height: 36) }.buttonStyle(FeedbackStyle(prominent: true)).keyboardShortcut("s")
            }.padding(.horizontal, 24).padding(.vertical, 18)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    TextField("标题", text: $note.title).font(.title2.weight(.semibold)).textFieldStyle(.plain)
                    ChoicePicker(title: "所属章节", selection: note.chapterID, options: model.library.chapters.filter { chapter in model.activeNotebooks.contains { $0.id == chapter.notebookID } }.map { chapter in ChoiceOption(id: chapter.id, title: (model.library.notebooks.first { $0.id == chapter.notebookID }?.title ?? "") + " / " + chapter.title, icon: "book.closed") }) { note.chapterID = $0 }
                    TextField("标签，用逗号分隔", text: Binding(get: { note.tags.joined(separator: "，") }, set: { note.tags = LibraryEdits.tags($0) })).textFieldStyle(FieldStyle())
                    VStack(spacing: 16) {
                        ForEach($note.blocks) { $block in
                            EditableBlockRow(block: $block, first: note.blocks.first?.id == block.id, last: note.blocks.last?.id == block.id, move: { delta in move(block.id, by: delta) }, remove: { withAnimation(motion) { note.blocks.removeAll { $0.id == block.id } } }, dragBegan: { draggingID = block.id }, dragMoved: updateDrag, dragEnded: endDrag)
                                .opacity(draggingID == block.id ? 0.40 : 1)
                                .overlay(alignment: insertion?.after == true ? .bottom : .top) {
                                    if insertion?.targetID == block.id {
                                        HStack(spacing: 0) { Circle().fill(Theme.accent).frame(width: 6, height: 6); Capsule().fill(Theme.accent).frame(height: 2); Circle().fill(Theme.accent).frame(width: 6, height: 6) }.padding(.horizontal, 1).offset(y: insertion?.after == true ? 8 : -8).allowsHitTesting(false)
                                    }
                                }
                                .background(GeometryReader { geometry in Color.clear.preference(key: BlockFrameKey.self, value: [block.id: geometry.frame(in: .named("note-editor"))]) })
                                .id(block.id)
                        }
                    }.onPreferenceChange(BlockFrameKey.self) { blockFrames = $0; if let point = dragPoint { updateDrag(point) } }
                    HStack {
                        ActionButton(title: "添加内容块", icon: "plus") { withAnimation(motion) { note.blocks.append(ContentBlock()) } }
                        Spacer()
                        if draggingID != nil { Label("松开放到标记位置", systemImage: "arrow.down.to.line").font(.system(size: 10)).foregroundStyle(Theme.accent) }
                    }.frame(maxWidth: .infinity, minHeight: 42).contentShape(Rectangle())
                }.padding(24)
            }
        }.frame(width: 780, height: 710).coordinateSpace(name: "note-editor").background(Theme.panel).buttonStyle(FeedbackStyle()).textFieldStyle(FieldStyle())
            .overlay(alignment: .topLeading) {
                if let point = dragPoint, let block = note.blocks.first(where: { $0.id == draggingID }) {
                    HStack(spacing: 10) {
                        Image(systemName: block.kind.icon).foregroundStyle(Theme.accent)
                        VStack(alignment: .leading, spacing: 5) { Text(block.kind.label).font(.system(size: 9)).foregroundStyle(.secondary); Text(block.text.isEmpty ? "空白内容块" : block.text).font(.system(size: 12, weight: .medium)).lineLimit(1) }
                        Spacer(minLength: 0)
                    }.padding(12).frame(width: 285, height: 58).background(Theme.panel, in: RoundedRectangle(cornerRadius: 12)).overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.accent.opacity(0.4))).shadow(color: .black.opacity(0.18), radius: 14, y: 6)
                        .position(x: min(624, max(154, point.x + 130)), y: min(675, max(108, point.y - 12))).allowsHitTesting(false)
                }
            }
            .onDisappear { finishDrag() }
    }
    private func finishDrag() { withAnimation(motion) { draggingID = nil; insertion = nil; dragPoint = nil } }
    private func updateDrag(_ point: CGPoint) {
        guard let draggingID else { return }
        dragPoint = point
        guard point.x >= 16, point.x <= 764, point.y >= 84, point.y <= 710 else { insertion = nil; return }
        let targets = note.blocks.filter { $0.id != draggingID }.compactMap { block in blockFrames[block.id].map { (block.id, $0) } }
        if let target = targets.first(where: { point.y < $0.1.midY }) { insertion = BlockInsertion(targetID: target.0, after: false) }
        else if let target = targets.last { insertion = BlockInsertion(targetID: target.0, after: true) }
        else { insertion = nil }
    }
    private func endDrag(_ point: CGPoint, _ cancelled: Bool) {
        guard !cancelled else { finishDrag(); return }
        updateDrag(point)
        if let id = draggingID, let insertion { commitDrop(id, insertion.targetID, insertion.after) }
        else { finishDrag() }
    }
    private func commitDrop(_ id: String, _ targetID: String, _ after: Bool) {
        withAnimation(motion) { BlockOrder.move(id, relativeTo: targetID, after: after, in: &note.blocks); draggingID = nil; insertion = nil; dragPoint = nil }
    }
    private func move(_ id: String, by delta: Int) {
        guard let index = note.blocks.firstIndex(where: { $0.id == id }), note.blocks.indices.contains(index + delta) else { return }
        commitDrop(id, note.blocks[index + delta].id, delta > 0)
    }
}

private struct EditableBlockRow: View {
    @Binding var block: ContentBlock
    let first: Bool
    let last: Bool
    let move: (Int) -> Void
    let remove: () -> Void
    let dragBegan: () -> Void
    let dragMoved: (CGPoint) -> Void
    let dragEnded: (CGPoint, Bool) -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                BlockDragHandle(block: block, onBegin: dragBegan, onMove: dragMoved, onEnd: dragEnded).frame(width: 26, height: 32).help("拖动调整顺序；也可以使用右侧的上移、下移按钮")
                ChoicePicker(title: "内容类型", selection: block.kind.rawValue, options: BlockKind.allCases.filter { $0 != .diagram || block.diagram != nil }.map { ChoiceOption(id: $0.rawValue, title: $0.label, icon: $0.icon) }) { block.kind = BlockKind(rawValue: $0) ?? .paragraph }
                if block.isReviewCard { Label("知识卡", systemImage: "rectangle.on.rectangle").font(.system(size: 9)).foregroundStyle(Theme.accent).padding(.leading, 4) }
                Spacer()
                QuietIconButton(icon: "arrow.up", label: "上移内容", size: 30) { move(-1) }.disabled(first)
                QuietIconButton(icon: "arrow.down", label: "下移内容", size: 30) { move(1) }.disabled(last)
                QuietIconButton(icon: "trash", label: "删除内容块", size: 30) { remove() }
            }
            TextField(block.kind == .term ? "单词或术语" : "内容", text: $block.text, axis: .vertical).textFieldStyle(FieldStyle()).lineLimit(2...12)
            if [.paragraph, .heading, .term, .callout, .formula, .example, .image, .diagram].contains(block.kind) {
                if [.term, .callout, .formula].contains(block.kind) {
                    TextField("复习问题（可选）", text: Binding(get: { block.reviewQuestion ?? "" }, set: { block.reviewQuestion = $0 }), axis: .vertical).textFieldStyle(FieldStyle()).lineLimit(1...3)
                }
                TextField([.term, .callout, .formula].contains(block.kind) ? "解释或含义 · 填写后自动成为知识卡" : "说明或例句", text: $block.detail, axis: .vertical).textFieldStyle(FieldStyle()).lineLimit(2...8)
            }
            if block.kind == .diagram, let diagram = block.diagram {
                StudyDiagramView(diagram: diagram)
                HStack {
                    TextField("横轴", text: Binding(get: { block.diagram?.xLabel ?? "" }, set: { block.diagram?.xLabel = $0 }))
                    TextField("纵轴", text: Binding(get: { block.diagram?.yLabel ?? "" }, set: { block.diagram?.yLabel = $0 }))
                }
                ForEach(diagram.elements.indices.filter { !diagram.elements[$0].label.isEmpty }, id: \.self) { i in
                    TextField("图中标签", text: Binding(get: { block.diagram?.elements[i].label ?? "" }, set: { block.diagram?.elements[i].label = $0 }))
                }
            }
            if block.kind == .table { tableEditor }
        }.padding(12).background(Theme.secondary.opacity(0.75), in: RoundedRectangle(cornerRadius: 12)).overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.border.opacity(0.7)))
    }
    private var tableEditor: some View {
        VStack(spacing: 9) {
            if block.rows.isEmpty { ActionButton(title: "创建表格") { block.rows = [["列一", "列二"], ["", ""]] } }
            ForEach(block.rows.indices, id: \.self) { r in
                HStack { ForEach(block.rows[r].indices, id: \.self) { c in TextField("", text: Binding(get: { block.rows.indices.contains(r) && block.rows[r].indices.contains(c) ? block.rows[r][c] : "" }, set: { if block.rows.indices.contains(r), block.rows[r].indices.contains(c) { block.rows[r][c] = $0 } })).textFieldStyle(FieldStyle()) }; Button { block.rows.remove(at: r) } label: { Image(systemName: "minus.circle") }.buttonStyle(FeedbackStyle(compact: true)) }
            }
            HStack { ActionButton(title: "添加行", icon: "plus") { block.rows.append(Array(repeating: "", count: max(2, block.rows.first?.count ?? 2))) }; ActionButton(title: "添加列") { for i in block.rows.indices { block.rows[i].append("") } }; if (block.rows.first?.count ?? 0) > 1 { ActionButton(title: "删除末列") { for i in block.rows.indices { block.rows[i].removeLast() } } } }.font(.caption)
        }
    }
}
