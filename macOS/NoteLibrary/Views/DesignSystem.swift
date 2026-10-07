import SwiftUI
import AppKit

enum Theme {
    static func adaptive(_ light: NSColor, _ dark: NSColor) -> Color { Color(nsColor: NSColor(name: nil) { $0.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light }) }
    static let accent = adaptive(NSColor(srgbRed: 0.03, green: 0.46, blue: 0.36, alpha: 1), NSColor(srgbRed: 0.38, green: 0.78, blue: 0.65, alpha: 1))
    static let onAccent = adaptive(.white, NSColor(srgbRed: 0.03, green: 0.17, blue: 0.13, alpha: 1))
    static let background = adaptive(NSColor(srgbRed: 0.953, green: 0.965, blue: 0.977, alpha: 1), NSColor(srgbRed: 0.070, green: 0.085, blue: 0.109, alpha: 1))
    static let panel = adaptive(NSColor(srgbRed: 0.998, green: 0.998, blue: 1, alpha: 1), NSColor(srgbRed: 0.108, green: 0.127, blue: 0.157, alpha: 1))
    static let composer = adaptive(.white, NSColor(srgbRed: 0.142, green: 0.164, blue: 0.200, alpha: 1))
    static let composerBorder = adaptive(NSColor.black.withAlphaComponent(0.11), NSColor.white.withAlphaComponent(0.13))
    static let secondary = Color.primary.opacity(0.045)
    static let border = Color.primary.opacity(0.085)
    static let colors: [Color] = [accent, .indigo, .orange, .pink, .blue]
    static func modelName(_ id: String) -> String { ["gpt-6-astra": "GPT-6 Astra", "gpt-6.1-sol": "GPT-6.1 Sol", "gpt-6-luna": "GPT-6 Luna"][id] ?? id }
}

// Frequent pointer actions acknowledge immediately. Only the background eases
// on hover; labels, selection, press feedback and layout never trail the input.
struct ControlSurface: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduced
    var prominent = false
    // A tinted action needs a visible hover change; selection stays quiet.
    var tinted = false
    var selected = false
    var hovered = false
    var pressed = false
    var radius: CGFloat = 9
    private var fill: Color {
        if prominent { return Theme.accent.opacity(pressed ? 0.84 : hovered ? 0.94 : 1) }
        if tinted { return Theme.accent.opacity(pressed ? 0.24 : hovered ? 0.17 : 0.10) }
        if selected { return Theme.accent.opacity(0.10 + (pressed ? 0.025 : hovered ? 0.01 : 0)) }
        return Color.primary.opacity(pressed ? 0.07 : hovered ? 0.04 : 0)
    }
    var body: some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous).fill(fill)
            .overlay {
                if tinted {
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .strokeBorder(Theme.accent.opacity(pressed ? 0.34 : hovered ? 0.24 : 0), lineWidth: 1)
                }
            }
            .animation(reduced || model.library.settings.reduceMotion ? nil : .easeOut(duration: hovered ? 0.06 : 0.09), value: hovered)
            .animation(nil, value: selected).animation(nil, value: pressed)
            .allowsHitTesting(false).accessibilityHidden(true)
    }
}
struct FeedbackStyle: ButtonStyle {
    var prominent = false
    var tinted = false
    var selected = false
    var compact = false
    func makeBody(configuration: Configuration) -> some View { FeedbackBody(configuration: configuration, prominent: prominent, tinted: tinted, selected: selected, compact: compact) }
    private struct FeedbackBody: View {
        @Environment(\.isEnabled) private var enabled
        @State private var hovered = false
        let configuration: Configuration
        let prominent: Bool
        let tinted: Bool
        let selected: Bool
        let compact: Bool
        var body: some View {
            configuration.label
                .frame(minWidth: compact ? 30 : 36, minHeight: compact ? 30 : 36)
                .foregroundStyle(prominent ? Theme.onAccent : (selected || tinted) ? Theme.accent : Color.primary)
                .background { ControlSurface(prominent: prominent, tinted: tinted, selected: selected, hovered: enabled && hovered, pressed: enabled && configuration.isPressed, radius: compact ? 7 : 11) }
                .opacity(enabled ? 1 : 0.35)
                .contentShape(Rectangle())
                .onHover { hovered = $0 }.onDisappear { hovered = false }
        }
    }
}

// Keep chrome mounted while its footprint closes. In particular, do not replace
// the reader or squeeze sidebar labels into a shrinking width during focus changes.
enum ReadingMotion {
    static func transition(reduced: Bool) -> Animation? {
        reduced ? nil : .smooth(duration: 0.32, extraBounce: 0)
    }
}
struct ReaderChrome<Content: View>: View {
    var expanded: Bool
    var axis: Axis
    var width: CGFloat? = nil
    @ViewBuilder var content: () -> Content
    var body: some View {
        ReaderChromeLayout(visibility: expanded ? 1 : 0, axis: axis, width: width) { content() }
            .clipped().opacity(expanded ? 1 : 0)
            .allowsHitTesting(expanded).disabled(!expanded)
            .accessibilityElement(children: expanded ? .contain : .ignore).accessibilityHidden(!expanded)
    }
}
private struct ReaderChromeLayout: Layout {
    var visibility: CGFloat
    var axis: Axis
    var width: CGFloat?
    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(visibility, width ?? 0) }
        set { visibility = newValue.first; if width != nil { width = newValue.second } }
    }
    private func expandedProposal(_ proposal: ProposedViewSize) -> ProposedViewSize {
        ProposedViewSize(width: axis == .horizontal ? width : proposal.width,
                         height: axis == .horizontal ? proposal.height : nil)
    }
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let content = subviews.first else { return .zero }
        let size = content.sizeThatFits(expandedProposal(proposal))
        let fraction = min(1, max(0, visibility))
        return CGSize(width: axis == .horizontal ? (width ?? size.width) * fraction : size.width,
                      height: axis == .vertical ? size.height * fraction : size.height)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews.first?.place(at: bounds.origin, anchor: .topLeading, proposal: expandedProposal(proposal))
    }
}

/// A single glyph in a fixed slot keeps disclosure labels aligned in both states.
struct DisclosureChevron: View {
    var expanded: Bool
    var body: some View {
        Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold))
            .rotationEffect(.degrees(expanded ? 90 : 0)).frame(width: 14, height: 14)
            .animation(nil, value: expanded).accessibilityHidden(true)
    }
}
struct QuietIconButton: View {
    var icon: String
    var label: String
    var selected = false
    var size: CGFloat = 36
    var action: () -> Void
    var body: some View { Button(action: action) { Image(systemName: icon).font(.system(size: 13, weight: .medium)).frame(width: size, height: size).contentShape(Rectangle()) }.buttonStyle(FeedbackStyle(selected: selected, compact: true)).help(label).accessibilityLabel(label) }
}
struct ActionButton: View {
    var title: String
    var icon: String = ""
    var primary = false
    var action: () -> Void
    var body: some View { Button(action: action) { HStack(spacing: 7) { if !icon.isEmpty { Image(systemName: icon) }; Text(title) }.font(.system(size: 12, weight: .medium)).padding(.horizontal, 14).frame(minHeight: 36).contentShape(Rectangle()) }.buttonStyle(FeedbackStyle(prominent: primary)).background(primary ? .clear : Theme.secondary, in: RoundedRectangle(cornerRadius: 11)) }
}
struct SearchBox: View {
    var placeholder = "搜索笔记"
    @Binding var text: String
    var autofocus = false
    @FocusState private var focused: Bool
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(focused ? Theme.accent : .secondary).allowsHitTesting(false)
            TextField(placeholder, text: $text).textFieldStyle(.plain).focused($focused).accessibilityLabel(placeholder)
                .onExitCommand { if text.isEmpty { focused = false } else { text = "" } }
            QuietIconButton(icon: "xmark", label: "清除搜索", size: 28) { text = ""; focused = true }
                .opacity(text.isEmpty ? 0 : 1).disabled(text.isEmpty).accessibilityHidden(text.isEmpty)
        }.font(.system(size: 12)).padding(.horizontal, 12).frame(minHeight: 38)
            .background(Theme.panel, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(focused ? Theme.accent.opacity(0.55) : Theme.border).allowsHitTesting(false))
            .contentShape(Rectangle()).onTapGesture { focused = true }
            .task {
                guard autofocus else { return }
                // Wait for the overlay to join the window before moving keyboard focus.
                await Task.yield()
                guard !Task.isCancelled else { return }
                focused = true
            }
            .background(PointerObserver(onDown: { point, bounds, window in
                if focused && !bounds.contains(point) { focused = false; window.makeFirstResponder(nil) }
            }))
    }
}
struct FieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View { configuration.textFieldStyle(.plain).padding(10).background(Theme.panel, in: RoundedRectangle(cornerRadius: 8)).overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.border)) }
}
struct SwitchRow: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.accessibilityReduceMotion) var reduced
    @Environment(\.isEnabled) private var enabled
    @State private var hovered = false
    var title: String
    var detail = ""
    @Binding var isOn: Bool
    var body: some View {
        Button { isOn.toggle() } label: {
            HStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(title).font(.system(size: 13, weight: .medium))
                    if !detail.isEmpty { Text(detail).font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
                }
                Spacer(minLength: 8)
                ZStack {
                    Capsule().fill(isOn ? Theme.accent : Color.secondary.opacity(0.24)).frame(width: 38, height: 22)
                    Circle().fill(.white).frame(width: 16, height: 16).shadow(color: .black.opacity(0.12), radius: 2, y: 1).offset(x: isOn ? 8 : -8)
                }.frame(width: 46, height: 36)
                    .animation(reduced || model.library.settings.reduceMotion ? nil : .easeOut(duration: 0.16), value: isOn)
                    .overlay(Capsule().stroke(hovered && enabled ? Theme.accent.opacity(0.28) : .clear, lineWidth: 1).frame(width: 44, height: 28))
            }.contentShape(Rectangle())
        }.buttonStyle(.plain).onHover { hovered = $0 }.onDisappear { hovered = false }
            .opacity(enabled ? 1 : 0.4)
            .accessibilityElement(children: .ignore).accessibilityLabel(title).accessibilityAddTraits(.isButton)
            .accessibilityValue(isOn ? "开启" : "关闭").accessibilityHint(detail)
            .accessibilityIdentifier("switch-" + title)
    }
}

struct TagPill: View {
    var text: String
    var color: Color = Theme.accent
    var body: some View { Text(text).font(.system(size: 10, weight: .medium)).foregroundStyle(color).padding(.horizontal, 8).padding(.vertical, 4).background(color.opacity(0.09), in: Capsule()) }
}
struct Avatar: View {
    var user = false
    var size: CGFloat = 29
    var body: some View { ZStack { RoundedRectangle(cornerRadius: size * 0.33).fill(user ? AnyShapeStyle(Color.primary.opacity(0.075)) : AnyShapeStyle(LinearGradient(colors: [Theme.accent, Theme.accent.opacity(0.75)], startPoint: .topLeading, endPoint: .bottomTrailing))); Image(systemName: user ? "person.fill" : "sparkles").font(.system(size: size * 0.44, weight: .medium)).foregroundStyle(user ? Color.secondary : Color.white) }.frame(width: size, height: size).accessibilityLabel(user ? "你" : "NoteLibrary AI") }
}
struct ActivityIndicator: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.accessibilityReduceMotion) var reduced
    var size: CGFloat = 15
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24, paused: reduced || model.library.settings.reduceMotion)) { timeline in
            Circle().trim(from: 0.1, to: 0.78).stroke(Theme.accent, style: StrokeStyle(lineWidth: 1.8, lineCap: .round)).rotationEffect(.degrees(reduced || model.library.settings.reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.2) * 300)).frame(width: size, height: size)
        }.accessibilityLabel("正在处理")
    }
}
struct ThinkingDots: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.accessibilityReduceMotion) var reduced
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24, paused: reduced || model.library.settings.reduceMotion)) { timeline in
            HStack(spacing: 5) { ForEach(0..<3) { index in
                let phase = reduced || model.library.settings.reduceMotion ? 0 : sin(timeline.date.timeIntervalSinceReferenceDate * 5 - Double(index))
                Circle().fill(Theme.accent.opacity(0.45 + 0.3 * (phase + 1) / 2)).frame(width: 5, height: 5).offset(y: phase * 2)
            } }
        }.frame(height: 18).accessibilityLabel("AI 正在回复")
    }
}

struct BrandMark: View {
    var id: String
    var size: CGFloat = 20
    var body: some View {
        Group {
            if id.isEmpty || id == "custom" { Image(systemName: "network").resizable().scaledToFit() }
            else { Image("Brand-" + id).resizable().scaledToFit() }
        }.frame(width: size, height: size).foregroundStyle(.primary).accessibilityHidden(true)
    }
}
struct ChoiceOption: Identifiable {
    var id: String
    var title: String
    var subtitle = ""
    var icon = ""
    var brand = ""
    var disabled = false
    var destructive = false
    var separatorBefore = false
}
enum ChoiceMenuMetrics {
    static func gap(before index: Int, option: ChoiceOption, selectionList: Bool) -> CGFloat {
        guard index > 0 else { return 0 }
        return selectionList ? (option.separatorBefore ? 10 : 4) : (option.separatorBefore ? 9 : 0)
    }
    static func contentHeight(options: [ChoiceOption], searchable: Bool, selectionList: Bool) -> CGFloat {
        let padding: CGFloat = selectionList ? 16 : 14
        let rows = options.isEmpty ? 100 : options.enumerated().reduce(CGFloat.zero) {
            $0 + ($1.element.subtitle.isEmpty ? 36 : 48) + gap(before: $1.offset, option: $1.element, selectionList: selectionList)
        }
        return padding + rows + (searchable ? 80 : 0)
    }
}
@MainActor final class ChoiceCenter: ObservableObject {
    let space = UUID().uuidString
    var focusReturnSourceID: String?
    @Published var presentation: Presentation? { didSet { if presentation != nil { focusReturnSourceID = nil; popover = nil } } }
    @Published var popover: FloatingPresentation? { didSet { if popover != nil { focusReturnSourceID = nil; presentation = nil } } }
    func dismiss(restoreFocus: Bool = false) {
        focusReturnSourceID = restoreFocus ? (popover?.sourceID ?? presentation?.sourceID) : nil
        presentation = nil; popover = nil
    }
    @Published var highlighted: String?
    @Published var keyboardNavigation = 0
    @Published var filteredOptions: [ChoiceOption]?
    struct Presentation {
        var sourceID = UUID().uuidString
        var trailing = false
        var title: String
        var rect: CGRect
        var options: [ChoiceOption]
        var selected: String?
        var choose: (String) -> Void
        var menuSize: CGSize? = nil
        var searchable = false
        var selectionList = false
    }
}
struct ChoicePicker: View {
    @EnvironmentObject var center: ChoiceCenter
    var title: String
    var selection: String
    var options: [ChoiceOption]
    var icon = ""
    var width: CGFloat? = nil
    var menuSize: CGSize? = nil
    var searchable = false
    var fillsWidth = false
    var onSelect: (String) -> Void
    @State private var rect = CGRect.zero
    @State private var sourceID = UUID().uuidString
    private var expanded: Bool { center.presentation?.sourceID == sourceID }
    var body: some View {
        Button {
            if expanded { center.presentation = nil }
            else { center.presentation = .init(sourceID: sourceID, title: title, rect: rect, options: options, selected: selection, choose: onSelect, menuSize: menuSize, searchable: searchable, selectionList: true) }
        } label: {
            HStack(spacing: 8) {
                if let brand = options.first(where: { $0.id == selection })?.brand, !brand.isEmpty { BrandMark(id: brand, size: 17) }
                else if !icon.isEmpty { Image(systemName: icon).foregroundStyle(Theme.accent) }
                Text(options.first { $0.id == selection }?.title ?? title).lineLimit(1).truncationMode(.tail)
                if width != nil || fillsWidth { Spacer(minLength: 0) }
                Image(systemName: "chevron.down").font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary)
            }.font(.system(size: 12, weight: .medium)).padding(.horizontal, 12).frame(width: width, height: 36).frame(maxWidth: fillsWidth ? .infinity : nil).contentShape(Rectangle())
        }.buttonStyle(FeedbackStyle(selected: expanded, compact: true)).background(Theme.secondary, in: RoundedRectangle(cornerRadius: 8)).accessibilityLabel(title).accessibilityValue(expanded ? "已展开" : "已收起")
            .background(GeometryReader { proxy in Color.clear.onAppear { rect = proxy.frame(in: .named(center.space)) }.onChange(of: proxy.frame(in: .named(center.space))) { _, value in if expanded && rect != value { center.presentation = nil }; rect = value } })
            .onDisappear { if expanded { center.presentation = nil } }
    }
}
struct ActionMenu: View {
    @EnvironmentObject var center: ChoiceCenter
    var title = "更多操作"
    var icon = "ellipsis"
    var sourceID = ""
    var trailing = false
    var size: CGFloat = 36
    var sidebar = false
    var selection: String? = nil
    var options: [ChoiceOption]
    var onSelect: (String) -> Void
    @State private var rect = CGRect.zero
    @State private var generatedID = UUID().uuidString
    private var id: String { sourceID.isEmpty ? generatedID : sourceID }
    private var expanded: Bool { center.presentation?.sourceID == id }
    var body: some View {
        Group {
            if sidebar { SidebarIconButton(icon: icon, label: title, selected: expanded, size: size, action: toggle).accessibilityIdentifier("menu-" + id) }
            else { QuietIconButton(icon: icon, label: title, selected: expanded, size: size, action: toggle) }
        }.accessibilityValue(expanded ? "已展开" : "已收起")
            .background(GeometryReader { proxy in Color.clear.onAppear { rect = proxy.frame(in: .named(center.space)) }.onChange(of: proxy.frame(in: .named(center.space))) { _, value in if expanded && rect != value { center.presentation = nil }; rect = value } })
            .onDisappear { if expanded { center.presentation = nil } }
    }
    private func toggle() {
        if expanded { center.presentation = nil }
        else { center.presentation = .init(sourceID: id, trailing: trailing, title: title, rect: rect, options: options, selected: selection, choose: onSelect) }
    }
}
// Fit the menu beside its trigger instead of clamping a full-height panel over it.
struct ChoiceMenuPlacement {
    static func frame(anchor: CGRect, viewport: CGSize, requested: CGSize, trailing: Bool = false) -> CGRect {
        let inset: CGFloat = 10, gap: CGFloat = 6
        let width = max(1, min(requested.width, viewport.width - inset * 2))
        let desiredHeight = max(1, min(requested.height, viewport.height - inset * 2))
        if trailing {
            let right = viewport.width - inset - anchor.maxX - gap
            let x = right >= width ? anchor.maxX + gap : anchor.minX - width - gap
            return CGRect(x: max(inset, min(x, viewport.width - width - inset)), y: max(inset, min(anchor.minY, viewport.height - desiredHeight - inset)), width: width, height: desiredHeight)
        }
        let below = max(0, viewport.height - inset - anchor.maxY - gap)
        let above = max(0, anchor.minY - inset - gap)
        let openBelow = below >= desiredHeight || (above < desiredHeight && below >= above)
        let height = max(1, min(desiredHeight, openBelow ? below : above))
        let x = max(inset, min(anchor.minX, viewport.width - width - inset))
        let y = openBelow ? anchor.maxY + gap : anchor.minY - gap - height
        return CGRect(x: x, y: y, width: width, height: height)
    }
}
private struct ChoiceHostDepth: EnvironmentKey { static let defaultValue = 0 }
private extension EnvironmentValues {
    var choiceHostDepth: Int { get { self[ChoiceHostDepth.self] } set { self[ChoiceHostDepth.self] = newValue } }
}
struct ChoiceHost: ViewModifier {
    @EnvironmentObject var model: AppModel
    @Environment(\.accessibilityReduceMotion) var reduced
    @StateObject private var center = ChoiceCenter()
    @Environment(\.choiceHostDepth) private var depth
    @State private var hostID = UUID()
    private var ownsError: Bool { model.activeErrorHost == hostID && model.error != nil }
    func body(content: Content) -> some View {
        content.environmentObject(center).coordinateSpace(name: center.space)
            .environment(\.choiceHostDepth, depth + 1)
            .disabled(ownsError).accessibilityHidden(ownsError)
            .onAppear { model.errorHosts[hostID] = depth }
            .onDisappear { model.errorHosts.removeValue(forKey: hostID) }
            .overlay {
                GeometryReader { geometry in
                    if let item = center.popover { FloatingPanelHost(item: item, viewport: geometry.size).id(item.sourceID).environmentObject(center) }
                    if let item = center.presentation {
                        let contentHeight = ChoiceMenuMetrics.contentHeight(options: item.options, searchable: item.searchable, selectionList: item.selectionList)
                        let requested = CGSize(width: item.menuSize?.width ?? (item.options.contains(where: { !$0.subtitle.isEmpty || $0.title.count > 13 }) ? 280 : 218), height: min(contentHeight, item.menuSize?.height ?? 430))
                        let menuRect = ChoiceMenuPlacement.frame(anchor: item.rect, viewport: geometry.size, requested: requested, trailing: item.trailing)
                        ChoicePanel(item: item, scrollable: contentHeight > menuRect.height + 1, availableHeight: menuRect.height).id(item.sourceID).environmentObject(center).frame(width: menuRect.width, height: menuRect.height).clipShape(RoundedRectangle(cornerRadius: 12))
                            .background(Theme.panel, in: RoundedRectangle(cornerRadius: 12))
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.border).allowsHitTesting(false))
                            .shadow(color: .black.opacity(0.13), radius: 12, y: 4)
                            .offset(x: menuRect.minX, y: menuRect.minY)
                            .transition(.opacity)
                        PointerObserver(onDown: { point, _, _ in
                            if !menuRect.contains(point) && !item.rect.contains(point) { center.dismiss() }
                        }, onEscape: { center.dismiss(restoreFocus: true) }, onKey: { event in
                            handleKey(event, item: item)
                        }).allowsHitTesting(false)
                    }
                }.animation(reduced || model.library.settings.reduceMotion ? nil : .easeOut(duration: 0.10), value: center.presentation?.sourceID)
                    .animation(reduced || model.library.settings.reduceMotion ? nil : .easeOut(duration: 0.15), value: center.popover?.sourceID)
            }
            .overlay {
                if ownsError, let error = model.error {
                    ZStack {
                        Color.black.opacity(0.17).onTapGesture { model.error = nil }
                        VStack(alignment: .leading, spacing: 18) {
                            Label("这一步需要处理", systemImage: "exclamationmark.circle").font(.headline)
                            Text(error).font(.system(size: 13)).lineSpacing(5).textSelection(.enabled)
                            HStack { Spacer(); ActionButton(title: "知道了", primary: true) { model.error = nil }.keyboardShortcut(.defaultAction).accessibilityIdentifier("dismiss-error") }
                        }.padding(26).frame(width: 440).background(Theme.panel, in: RoundedRectangle(cornerRadius: 18)).shadow(color: .black.opacity(0.15), radius: 25, y: 10)
                    }.environment(\.isEnabled, true).accessibilityHidden(false).onExitCommand { model.error = nil }
                }
            }
    }
    private func handleKey(_ event: NSEvent, item: ChoiceCenter.Presentation) -> Bool {
        guard !ownsError, event.modifierFlags.intersection([.command, .control, .option]).isEmpty else { return false }
        let enabled = (center.filteredOptions ?? item.options).filter { !$0.disabled }
        guard !enabled.isEmpty else { return false }
        if event.keyCode == 125 || event.keyCode == 126 {
            let index = enabled.firstIndex { $0.id == center.highlighted } ?? enabled.firstIndex { $0.id == item.selected }
            let next: Int
            if event.keyCode == 125 { next = index.map { ($0 + 1) % enabled.count } ?? 0 }
            else { next = index.map { ($0 + enabled.count - 1) % enabled.count } ?? (enabled.count - 1) }
            center.highlighted = enabled[next].id; center.keyboardNavigation += 1
            return true
        }
        if [36, 76].contains(event.keyCode), let id = center.highlighted, enabled.contains(where: { $0.id == id }) {
            center.presentation = nil; item.choose(id); return true
        }
        return false
    }
}
private struct MenuRowStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    @Environment(\.colorSchemeContrast) private var contrast
    var highlighted: Bool
    var selected: Bool
    var selectionList: Bool
    var groupedAction: Bool
    private func fill(pressed: Bool) -> Color {
        if !selectionList { return Theme.accent.opacity(pressed ? 0.15 : highlighted ? 0.09 : 0) }
        if selected { return Theme.accent.opacity(pressed ? 0.18 : highlighted ? 0.12 : 0.085) }
        return Color.primary.opacity(pressed ? 0.09 : highlighted ? 0.06 : groupedAction ? 0 : 0.028)
    }
    private var outline: Color {
        guard selectionList else { return .clear }
        if selected { return Theme.accent.opacity(contrast == .increased ? 0.6 : 0.25) }
        return Color.primary.opacity(contrast == .increased ? 0.22 : highlighted ? 0.07 : 0)
    }
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.background {
            RoundedRectangle(cornerRadius: 7, style: .continuous).fill(fill(pressed: configuration.isPressed))
                .overlay { RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(outline, lineWidth: 0.75) }
                .animation(nil, value: highlighted).animation(nil, value: selected).animation(nil, value: configuration.isPressed)
                .allowsHitTesting(false)
        }.opacity(enabled ? 1 : 0.4)
    }
}
private struct ChoicePanel: View {
    @EnvironmentObject var center: ChoiceCenter
    let item: ChoiceCenter.Presentation
    let scrollable: Bool
    let availableHeight: CGFloat
    @State private var query = ""
    @FocusState private var focused: Bool
    private var options: [ChoiceOption] { item.options.filter { query.isEmpty || $0.title.localizedCaseInsensitiveContains(query) || $0.subtitle.localizedCaseInsensitiveContains(query) } }
    private var needsScrollHint: Bool {
        let height = ChoiceMenuMetrics.contentHeight(options: options, searchable: item.searchable, selectionList: item.selectionList) + 18
        return !options.isEmpty && height > availableHeight + 1
    }
    var body: some View {
        ScrollViewReader { proxy in
            VStack(spacing: 0) {
                if item.searchable {
                    HStack { Text(item.title).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary); Spacer(); Text(query.isEmpty ? "\(item.options.count) 项" : "\(options.count) / \(item.options.count) 项").font(.system(size: 10)).foregroundStyle(.tertiary) }.padding(.horizontal, 13).padding(.top, 13).padding(.bottom, 9)
                    SearchBox(placeholder: "搜索", text: $query, autofocus: true).padding(.horizontal, 9).padding(.bottom, 8).fixedSize(horizontal: false, vertical: true)
                    Rectangle().fill(Theme.border).frame(height: 1)
                }
                if scrollable {
                    ScrollView { rows }.scrollIndicators(.hidden).clipped()
                    Label("上下滚动", systemImage: "arrow.up.and.down").font(.system(size: 9)).foregroundStyle(.tertiary).frame(maxWidth: .infinity).frame(height: 18).opacity(needsScrollHint ? 1 : 0).accessibilityHidden(!needsScrollHint)
                } else { rows.frame(maxHeight: .infinity, alignment: .top) }
            }.focusable(!item.searchable).focused($focused).focusEffectDisabled()
                .onAppear {
                    center.highlighted = nil; center.filteredOptions = options
                    if !item.searchable { focused = true }
                    if scrollable && !item.searchable, let selected = item.selected { proxy.scrollTo(selected, anchor: .center) }
                }
                .onChange(of: query) { _, _ in center.highlighted = nil; center.filteredOptions = options; proxy.scrollTo("choices-top", anchor: .top) }
                .onDisappear { center.filteredOptions = nil }
                .onMoveCommand { move($0) }
                .onChange(of: center.keyboardNavigation) { _, _ in if scrollable, let id = center.highlighted { proxy.scrollTo(id, anchor: .center) } }
                .onKeyPress(.return) { guard let id = center.highlighted, options.contains(where: { $0.id == id && !$0.disabled }) else { return .ignored }; select(id); return .handled }
        }
    }
    private func move(_ direction: MoveCommandDirection) {
        let enabled = options.filter { !$0.disabled }; guard !enabled.isEmpty else { return }
        let index = enabled.firstIndex { $0.id == center.highlighted }
        if direction == .down { center.highlighted = enabled[index.map { ($0 + 1) % enabled.count } ?? 0].id }
        if direction == .up { center.highlighted = enabled[index.map { ($0 + enabled.count - 1) % enabled.count } ?? (enabled.count - 1)].id }
    }
    private var rows: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: 0).id("choices-top")
            ForEach(Array(options.enumerated()), id: \.element.id) { index, option in
                if index > 0 {
                    if item.selectionList {
                        Color.clear.frame(height: ChoiceMenuMetrics.gap(before: index, option: option, selectionList: true)).accessibilityHidden(true)
                    } else if option.separatorBefore {
                        Rectangle().fill(Theme.border).frame(height: 1).padding(.vertical, 4).padding(.horizontal, 6).accessibilityHidden(true)
                    }
                }
                Button { select(option.id) } label: {
                    HStack(spacing: 10) {
                        if !option.brand.isEmpty { BrandMark(id: option.brand, size: 19) }
                        else if !option.icon.isEmpty { Image(systemName: option.icon).font(.system(size: 14)).frame(width: 20).foregroundStyle(option.destructive ? Color.red : Color.primary.opacity(0.85)) }
                        VStack(alignment: .leading, spacing: 4) {
                            HighlightedText(LibrarySearch.query(query).isEmpty ? option.title : LibrarySearch.snippet(option.title, query: query, limit: 62), query: query).font(.system(size: 12, weight: .medium)).foregroundStyle(option.destructive ? Color.red : Color.primary).lineLimit(1).truncationMode(.tail)
                            if !option.subtitle.isEmpty { HighlightedText(LibrarySearch.query(query).isEmpty ? option.subtitle : LibrarySearch.snippet(option.subtitle, query: query, limit: 80), query: query).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1) }
                        }
                        Spacer(minLength: 4)
                        Image(systemName: "checkmark").font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.accent).opacity(item.selected == option.id ? 1 : 0)
                    }.padding(.horizontal, 10).frame(maxWidth: .infinity, minHeight: option.subtitle.isEmpty ? 36 : 48, alignment: .leading).contentShape(Rectangle())
                }.buttonStyle(MenuRowStyle(highlighted: center.highlighted == option.id, selected: item.selected == option.id, selectionList: item.selectionList, groupedAction: option.separatorBefore)).disabled(option.disabled).help(option.title).id(option.id)
                    .onHover { active in if active && !option.disabled { center.highlighted = option.id } else if center.highlighted == option.id { center.highlighted = nil } }
                    .accessibilityAddTraits(item.selected == option.id ? .isSelected : [])
            }
            if options.isEmpty { Text("没有找到匹配的选项").font(.system(size: 12)).foregroundStyle(.secondary).frame(maxWidth: .infinity, minHeight: 100) }
        }.padding(item.selectionList ? 8 : 7).frame(maxWidth: .infinity, alignment: .topLeading)
    }
    private func select(_ id: String) { center.presentation = nil; item.choose(id) }
}

extension View { func choiceHost() -> some View { modifier(ChoiceHost()) } }

struct ComposerEditor: NSViewRepresentable {
    @Environment(\.isEnabled) private var isEnabled
    @Binding var text: String
    @Binding var height: CGFloat
    var enterSends: Bool
    var onSend: () -> Void
    var onImagePaste: () -> Void
    var onFocusChange: (Bool) -> Void = { _ in }
    var placeholder = "描述想法、提出问题，或输入 / 使用命令…"
    var accessibilityName = "消息输入框"
    var minimumHeight: CGFloat = 52
    var maximumHeight: CGFloat = 156
    var focusOnAppear = false
    var focusRequest = 0
    var onKey: (UInt16) -> Bool = { _ in false }
    var onEscape: () -> Void = {}
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.drawsBackground = false; scroll.borderType = .noBorder
        scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true
        let view = InputTextView(frame: .zero)
        view.delegate = context.coordinator
        view.isRichText = false; view.importsGraphics = false
        view.font = .systemFont(ofSize: 14); view.textColor = .labelColor
        view.insertionPointColor = NSColor(Theme.accent); view.drawsBackground = false
        view.textContainerInset = NSSize(width: 0, height: 8)
        view.textContainer?.lineFragmentPadding = 0
        view.isVerticallyResizable = true; view.isHorizontallyResizable = false
        view.autoresizingMask = [.width]
        view.textContainer?.widthTracksTextView = true
        view.minSize = NSSize(width: 0, height: minimumHeight); view.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        view.setAccessibilityLabel(accessibilityName); view.setAccessibilityIdentifier(focusOnAppear ? "message-inline-editor" : "chat-composer")
        scroll.documentView = view
        return scroll
    }
    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let view = scroll.documentView as? InputTextView else { return }
        view.isEditable = isEnabled; view.isSelectable = isEnabled
        if !isEnabled, view.window?.firstResponder === view {
            DispatchQueue.main.async { [weak view] in
                guard let view, !view.isEditable, let window = view.window, window.firstResponder === view else { return }
                window.makeFirstResponder(nil)
            }
        }
        if view.string != text, !view.hasMarkedText() { view.string = text }
        view.enterSends = enterSends; view.onSend = onSend; view.onImagePaste = onImagePaste; view.onFocusChange = onFocusChange
        view.placeholder = placeholder; view.onCommandKey = onKey; view.onEscape = onEscape
        if focusRequest != context.coordinator.focusRequest {
            context.coordinator.focusRequest = focusRequest
            DispatchQueue.main.async { [weak view] in
                guard let view, view.isEditable, let window = view.window else { return }
                window.makeFirstResponder(view)
                view.setSelectedRange(NSRange(location: view.string.utf16.count, length: 0))
            }
        }
        if focusOnAppear && !context.coordinator.didFocus {
            DispatchQueue.main.async { [weak view, weak coordinator = context.coordinator] in
                guard let view, let coordinator, !coordinator.didFocus, let window = view.window else { return }
                coordinator.didFocus = true; window.makeFirstResponder(view)
                view.setSelectedRange(NSRange(location: view.string.utf16.count, length: 0))
            }
        }
        view.textColor = .labelColor; view.insertionPointColor = NSColor(Theme.accent)
        view.needsDisplay = true
        context.coordinator.measure(view)
    }
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: ComposerEditor
        var didFocus = false
        var focusRequest = 0
        init(_ parent: ComposerEditor) { self.parent = parent }
        func textDidChange(_ notification: Notification) {
            guard let view = notification.object as? InputTextView else { return }
            parent.text = view.string; view.needsDisplay = true; measure(view)
        }
        func measure(_ view: NSTextView) {
            guard let container = view.textContainer, let layout = view.layoutManager else { return }
            layout.ensureLayout(for: container)
            let value = min(parent.maximumHeight, max(parent.minimumHeight, layout.usedRect(for: container).height + 19))
            if abs(parent.height - value) > 1 { DispatchQueue.main.async { self.parent.height = value } }
        }
    }
}
final class InputTextView: NSTextView {
    var enterSends = false
    var onSend: () -> Void = {}
    var onImagePaste: () -> Void = {}
    var onFocusChange: (Bool) -> Void = { _ in }
    var placeholder = ""
    var onCommandKey: (UInt16) -> Bool = { _ in false }
    var onEscape: () -> Void = {}
    private var outsideClickMonitor: Any?
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let outsideClickMonitor { NSEvent.removeMonitor(outsideClickMonitor); self.outsideClickMonitor = nil }
        guard window != nil else { return }
        outsideClickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self, let window = self.window, window.firstResponder === self else { return event }
            let surface = self.enclosingScrollView ?? self
            let inside = event.window == window && surface.bounds.contains(surface.convert(event.locationInWindow, from: nil))
            if !inside { window.makeFirstResponder(nil) }
            return event // The original click must reach the intended button on the first press.
        }
    }
    deinit { if let outsideClickMonitor { NSEvent.removeMonitor(outsideClickMonitor) } }
    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if accepted { onFocusChange(true) }
        return accepted
    }
    override func resignFirstResponder() -> Bool {
        let accepted = super.resignFirstResponder()
        if accepted { onFocusChange(false) }
        return accepted
    }
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        if string.isEmpty, !hasMarkedText() {
            (placeholder as NSString).draw(at: textContainerOrigin, withAttributes: [.font: font ?? NSFont.systemFont(ofSize: 14), .foregroundColor: NSColor.placeholderTextColor])
        }
    }
    override func keyDown(with event: NSEvent) {
        guard isEditable else { super.keyDown(with: event); return }
        if !hasMarkedText(), event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty, onCommandKey(event.keyCode) { return }
        if event.keyCode == 53, !hasMarkedText() { onEscape(); window?.makeFirstResponder(nil); return }
        if event.keyCode == 36, !hasMarkedText(), event.modifierFlags.contains(.command) || (enterSends && !event.modifierFlags.contains(.shift)) { onSend(); return }
        super.keyDown(with: event)
    }
    override func paste(_ sender: Any?) {
        if NSPasteboard.general.string(forType: .string) == nil, NSPasteboard.general.availableType(from: [.png, .tiff]) != nil { onImagePaste() }
        else { super.paste(sender) }
    }
}
