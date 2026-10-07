import SwiftUI
import AppKit

struct FloatingPresentation {
    var sourceID: String
    var rect: CGRect
    var size: CGSize
    var content: AnyView
}

// Keep an opened surface on the same side of its trigger when a subpage gets shorter.
enum FloatingPlacement {
    static func opensBelow(anchor: CGRect, viewport: CGSize, height: CGFloat) -> Bool {
        let below = viewport.height - 10 - anchor.maxY - 7
        let above = anchor.minY - 17
        return below >= height || (above < height && below >= above)
    }
    static func frame(anchor: CGRect, viewport: CGSize, requested: CGSize, below: Bool) -> CGRect {
        let inset: CGFloat = 10, gap: CGFloat = 7
        let width = max(1, min(requested.width, viewport.width - inset * 2))
        let available = below ? viewport.height - inset - anchor.maxY - gap : anchor.minY - inset - gap
        let height = max(1, min(requested.height, available))
        let x = max(inset, min(anchor.maxX - width, viewport.width - width - inset))
        let y = below ? anchor.maxY + gap : anchor.minY - gap - height
        return CGRect(x: x, y: max(inset, y), width: width, height: height)
    }
}

struct FloatingControl<Label: View, Panel: View>: View {
    @EnvironmentObject private var center: ChoiceCenter
    var id: String
    var title: String
    var size: CGSize
    var willOpen: () -> Void = {}
    @ViewBuilder var label: (Bool) -> Label
    @ViewBuilder var panel: () -> Panel
    @State private var rect = CGRect.zero
    @FocusState private var triggerFocused: Bool
    private var expanded: Bool { center.popover?.sourceID == id }
    var body: some View {
        Button(action: toggle) { label(expanded).contentShape(Rectangle()) }
            .buttonStyle(FeedbackStyle(selected: expanded, compact: true))
            .focusable(interactions: .edit).focusEffectDisabled().focused($triggerFocused)
            .onKeyPress(.space) { toggle(); return .handled }
            .onKeyPress(.return) { toggle(); return .handled }
            .help(title).accessibilityLabel(title).accessibilityIdentifier(id)
            .accessibilityValue(expanded ? "已展开" : "已收起")
            .background(GeometryReader { proxy in
                Color.clear.onAppear { rect = proxy.frame(in: .named(center.space)) }
                    .onChange(of: proxy.frame(in: .named(center.space))) { _, next in
                        if expanded && rect != next { center.dismiss() }
                        rect = next
                    }
            })
            .onChange(of: center.popover?.sourceID) { old, next in
                if old == id && next == nil {
                    Task { @MainActor in
                        // The closing panel must leave the focus tree before restoring its trigger.
                        try? await Task.sleep(for: .milliseconds(180))
                        guard center.popover == nil, center.presentation == nil, center.focusReturnSourceID == id else { return }
                        triggerFocused = true
                        center.focusReturnSourceID = nil
                    }
                }
            }
            .onDisappear { if expanded { center.dismiss() } }
    }
    private func toggle() {
        if expanded { center.dismiss(restoreFocus: true) }
        else {
            triggerFocused = false
            willOpen()
            center.popover = FloatingPresentation(sourceID: id, rect: rect, size: size, content: AnyView(panel()))
        }
    }
}

struct FloatingPanelHost: View {
    @EnvironmentObject private var center: ChoiceCenter
    @EnvironmentObject private var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduced
    let item: FloatingPresentation
    let viewport: CGSize
    @State private var below: Bool?
    private var opensBelow: Bool { below ?? FloatingPlacement.opensBelow(anchor: item.rect, viewport: viewport, height: item.size.height) }
    private var panelRect: CGRect { FloatingPlacement.frame(anchor: item.rect, viewport: viewport, requested: item.size, below: opensBelow) }
    var body: some View {
        let rect = panelRect
        ZStack(alignment: .topLeading) {
            ScrollView {
                item.content.frame(maxWidth: .infinity).fixedSize(horizontal: false, vertical: true)
            }.scrollDisabled(item.size.height <= rect.height + 1).scrollIndicators(.hidden)
                .frame(width: rect.width, height: rect.height)
                .background(Theme.panel, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay { RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.border, lineWidth: 0.75).allowsHitTesting(false) }
                .shadow(color: .black.opacity(0.18), radius: 16, y: 6)
                .offset(x: rect.minX, y: rect.minY)
                .transition(.opacity.combined(with: .scale(scale: 0.985, anchor: opensBelow ? .topTrailing : .bottomTrailing)))
                .onKeyPress(.escape) { center.dismiss(restoreFocus: true); return .handled }
                .onExitCommand { center.dismiss(restoreFocus: true) }
                .animation(reduced || model.library.settings.reduceMotion ? nil : .easeInOut(duration: 0.16), value: item.size.height)
            PointerObserver(onDown: { point, _, _ in
                if !rect.contains(point) && !item.rect.contains(point) { center.dismiss() }
            }, onEscape: { center.dismiss(restoreFocus: true) }).allowsHitTesting(false)
        }.onAppear { below = opensBelow }
    }
}

struct ReaderStylePanel: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var center: ChoiceCenter
    @FocusState private var focused: Bool
    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Text("阅读样式").font(.system(size: 12, weight: .semibold))
                Spacer()
                QuietIconButton(icon: "xmark", label: "关闭阅读样式", size: 24) { center.dismiss(restoreFocus: true) }
            }
            HStack {
                Text("字号").foregroundStyle(.secondary)
                Spacer()
                HStack(spacing: 0) {
                    QuietIconButton(icon: "minus", label: "减小字号", size: 30) { model.updateSettings { $0.fontSize = max(14, $0.fontSize - 1) } }.disabled(model.library.settings.fontSize <= 14)
                    Text("\(Int(model.library.settings.fontSize))").font(.system(size: 13, weight: .medium)).monospacedDigit().frame(width: 42)
                    QuietIconButton(icon: "plus", label: "增大字号", size: 30) { model.updateSettings { $0.fontSize = min(24, $0.fontSize + 1) } }.disabled(model.library.settings.fontSize >= 24)
                }.padding(3).background(Theme.secondary, in: RoundedRectangle(cornerRadius: 9))
            }
            ReaderPresetRow(title: "行距", values: [("紧凑", 4), ("适中", 7), ("宽松", 11)], selected: model.library.settings.lineSpacing) { value in model.updateSettings { $0.lineSpacing = value } }
            ReaderPresetRow(title: "版心", values: [("窄", 560), ("适中", 660), ("宽", 780)], selected: model.library.settings.readingWidth ?? 660) { value in model.updateSettings { $0.readingWidth = value } }
        }.font(.system(size: 12)).padding(16).frame(height: 216)
            .focusable().focusEffectDisabled().focused($focused).onAppear { focused = true }
            .onKeyPress(.escape) { center.dismiss(restoreFocus: true); return .handled }
            .accessibilityElement(children: .contain).accessibilityLabel("阅读样式")
    }
}

private struct ReaderPresetRow: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduced
    var title: String
    var values: [(String, Double)]
    var selected: Double
    var choose: (Double) -> Void
    @Namespace private var indicator
    var body: some View {
        HStack {
            Text(title).foregroundStyle(.secondary)
            Spacer(minLength: 16)
            HStack(spacing: 2) {
                ForEach(values, id: \.1) { item in
                    Button { choose(item.1) } label: {
                        Text(item.0).font(.system(size: 11, weight: selected == item.1 ? .semibold : .medium))
                            .foregroundStyle(selected == item.1 ? Theme.accent : .secondary)
                            .frame(maxWidth: .infinity).frame(height: 30)
                            .background {
                                if selected == item.1 {
                                    RoundedRectangle(cornerRadius: 7).fill(Theme.accent.opacity(0.12))
                                        .overlay { RoundedRectangle(cornerRadius: 7).strokeBorder(Theme.accent.opacity(0.18), lineWidth: 0.75) }
                                        .matchedGeometryEffect(id: "selection", in: indicator)
                                }
                            }
                    }.buttonStyle(FeedbackStyle(compact: true))
                        .accessibilityLabel(title + "：" + item.0).accessibilityValue(selected == item.1 ? "已选择" : "未选择")
                        .accessibilityAddTraits(selected == item.1 ? .isSelected : [])
                }
            }.padding(3).frame(width: 196).background(Theme.secondary, in: RoundedRectangle(cornerRadius: 9))
                .animation(reduced || model.library.settings.reduceMotion ? nil : .smooth(duration: 0.18), value: selected)
        }
    }
}

struct ReaderActionsPanel: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var center: ChoiceCenter
    @Environment(\.accessibilityReduceMotion) private var reduced
    let noteID: String
    @Binding var showInfo: Bool
    @State private var page = "root"
    @State private var highlighted: String?
    @FocusState private var focused: Bool
    private var note: Note? { model.library.notes.first { $0.id == noteID && $0.deletedAt == nil } }
    private var title: String { page == "organize" ? "整理笔记" : page == "ai" ? "AI 助手" : "导出笔记" }
    private var rows: [ChoiceOption] {
        guard let note else { return [] }
        switch page {
        case "organize": return [.init(id: "pin", title: note.pinned == true ? "取消置顶" : "置顶笔记", icon: note.pinned == true ? "pin.slash" : "pin"), .init(id: "move", title: "移动到章节…", icon: "folder"), .init(id: "tags", title: "编辑标签…", icon: "tag"), .init(id: "duplicate", title: "创建副本", icon: "plus.square.on.square"), .init(id: "lock", title: note.locked ? "解锁 AI 修改" : "锁定当前内容", icon: note.locked ? "lock.open" : "lock")]
        case "ai": return [.init(id: "explain", title: "解释这篇笔记", icon: "text.bubble"), .init(id: "verify", title: "校对这篇笔记", icon: "checkmark.seal")]
        default: return [.init(id: "edit", title: "编辑笔记", icon: "square.and.pencil"), .init(id: "review", title: "复习本书", icon: "rectangle.on.rectangle"), .init(id: "organize", title: "整理笔记", icon: "folder", separatorBefore: true), .init(id: "ai", title: "AI 助手", icon: "sparkles"), .init(id: "export", title: "导出笔记…", icon: "square.and.arrow.up"), .init(id: "source", title: showInfo ? "收起来源信息" : "来源与补充", icon: "link", separatorBefore: true), .init(id: "history", title: "历史修改", icon: "clock.arrow.circlepath"), .init(id: "trash", title: "移到回收站", icon: "trash", destructive: true, separatorBefore: true)]
        }
    }
    private var targets: [String] { (page == "root" ? ["favorite", "read"] : ["back"]) + rows.map(\.id) }
    private var height: CGFloat { page == "root" ? 354 : CGFloat(52 + rows.count * 34) }
    var body: some View {
        VStack(spacing: 0) {
            if page == "root", let note {
                HStack(spacing: 6) {
                    quick("favorite", title: note.favorite ? "已收藏" : "收藏", icon: note.favorite ? "star.fill" : "star", selected: note.favorite)
                    quick("read", title: model.isRead(note.id) ? "已读" : "未读", icon: model.isRead(note.id) ? "checkmark.circle.fill" : "checkmark.circle", selected: model.isRead(note.id))
                }.padding(.bottom, 10)
            } else {
                Button { navigate("root") } label: {
                    HStack(spacing: 8) { Image(systemName: "chevron.left").font(.system(size: 10, weight: .semibold)); Text(title).font(.system(size: 12, weight: .semibold)); Spacer() }.padding(.horizontal, 10).frame(height: 32)
                }.buttonStyle(FeedbackStyle(selected: highlighted == "back", compact: true)).accessibilityLabel("返回笔记操作").padding(.bottom, 4)
            }
            VStack(spacing: 0) {
                ForEach(rows) { item in
                    if item.separatorBefore { Color.clear.frame(height: 8).accessibilityHidden(true) }
                    actionRow(item)
                }
            }.id(page).transition(.opacity)
        }.padding(8).frame(maxWidth: .infinity, alignment: .topLeading)
            .focusable().focusEffectDisabled().focused($focused)
            .onAppear { focused = true }
            .onChange(of: page) { _, _ in center.popover?.size.height = height }
            .animation(reduced || model.library.settings.reduceMotion ? nil : .easeOut(duration: 0.12), value: page)
            .onMoveCommand { direction in
                if direction == .left, page != "root" { navigate("root"); return }
                if direction == .right, let highlighted, ["organize", "ai"].contains(highlighted) { navigate(highlighted); return }
                guard direction == .down || direction == .up else { return }
                let index = highlighted.flatMap { targets.firstIndex(of: $0) }
                let next = direction == .down ? index.map { ($0 + 1) % targets.count } ?? 0 : index.map { ($0 + targets.count - 1) % targets.count } ?? targets.count - 1
                highlighted = targets[next]
            }
            .onKeyPress(.return) { guard let highlighted else { return .ignored }; perform(highlighted); return .handled }
            .onKeyPress(.space) { guard let highlighted else { return .ignored }; perform(highlighted); return .handled }
            .onKeyPress(.escape) { center.dismiss(restoreFocus: true); return .handled }
            .accessibilityElement(children: .contain).accessibilityLabel(page == "root" ? "笔记操作" : title)
    }
    private func quick(_ id: String, title: String, icon: String, selected: Bool) -> some View {
        Button { perform(id) } label: {
            HStack(spacing: 6) { Image(systemName: icon).font(.system(size: 12)); Text(title).font(.system(size: 11, weight: .medium)) }.frame(maxWidth: .infinity).frame(height: 32)
                .foregroundStyle(selected ? Theme.accent : .secondary)
        }.buttonStyle(FeedbackStyle(selected: selected || highlighted == id, compact: true))
            .background(Theme.secondary, in: RoundedRectangle(cornerRadius: 8))
            .accessibilityLabel(id == "favorite" ? (selected ? "取消收藏" : "收藏笔记") : (selected ? "标为未读" : "标为已读"))
            .onHover { hovering in if hovering { highlighted = id } else if highlighted == id { highlighted = nil } }
    }
    private func actionRow(_ item: ChoiceOption) -> some View {
        let submenu = page == "root" && ["organize", "ai"].contains(item.id)
        return Button { perform(item.id) } label: {
            HStack(spacing: 10) {
                Image(systemName: item.icon).font(.system(size: 13)).frame(width: 18)
                Text(item.title).font(.system(size: 12, weight: .medium)).lineLimit(1)
                Spacer(minLength: 6)
                if submenu { Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold)).foregroundStyle(.tertiary) }
            }.foregroundStyle(item.destructive ? Color.red.opacity(0.85) : Color.primary).padding(.horizontal, 10).frame(height: 34).contentShape(Rectangle())
        }.buttonStyle(FeedbackStyle(selected: highlighted == item.id, compact: true))
            .onHover { hovering in if hovering { highlighted = item.id } else if highlighted == item.id { highlighted = nil } }
            .accessibilityIdentifier("reader-action-" + item.id)
    }
    private func navigate(_ next: String) { page = next; highlighted = nil; focused = true }
    private func perform(_ id: String) {
        if id == "back" { navigate("root"); return }
        if page == "root", ["organize", "ai"].contains(id) { navigate(id); return }
        guard let note else { center.dismiss(); return }
        // State toggles remain open so their new state is immediately visible.
        if id == "favorite" { model.toggleFavorite(note); return }
        if id == "read" { model.markRead([note.id], completed: !model.isRead(note.id)); return }
        center.dismiss()
        switch id {
        case "edit": model.editorNote = note
        case "review": model.reviewBookID = model.library.chapters.first { $0.id == note.chapterID }?.notebookID
        case "pin", "move", "tags", "duplicate": model.performNoteAction(id, note: note)
        case "lock": model.toggleLock(note)
        case "explain": model.askAbout(note)
        case "verify": model.askAbout(note, verify: true)
        case "export": model.exportNote = note
        case "source": showInfo.toggle()
        case "history": model.historyPresented = true
        case "trash": model.trash(note)
        default: break
        }
    }
}
