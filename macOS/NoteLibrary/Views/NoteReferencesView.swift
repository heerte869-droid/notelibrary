import SwiftUI
import AppKit

// Keep citations in the text flow; only validated note references become links.
// Markdown is parsed once so emphasis and existing links remain intact.
struct NoteCitationText {
    struct Part {
        var text: AttributedString
        var indices: [Int] = []
    }
    static func parts(_ source: String, count: Int) -> [Part] {
        guard count > 0 else { return [Part(text: markdown(source))] }
        // Protect explicitly escaped brackets before Markdown removes the escape.
        let sentinel = (0xE000...0xF8FF).lazy.compactMap(UnicodeScalar.init).map(String.init).first { !source.contains($0) } ?? "⌜escaped-bracket⌝"
        let chars = Array(source); var escaped = ""; var i = 0
        while i < chars.count {
            if chars[i] == "\\", i + 1 < chars.count {
                if chars[i + 1] == "[" { escaped += sentinel }
                else { escaped.append(chars[i]); escaped.append(chars[i + 1]) }
                i += 2
            } else { escaped.append(chars[i]); i += 1 }
        }
        let parsed = markdown(escaped)
        let pattern = try! NSRegularExpression(pattern: #"(?:\[[1-9][0-9]?\](?:[ \t]*(?=\[[1-9][0-9]?\]))?)+"#)
        let number = try! NSRegularExpression(pattern: #"\[([1-9][0-9]?)\]"#)
        var parts: [Part] = []
        for run in parsed.runs {
            let value = AttributedString(parsed[run.range])
            let raw = String(value.characters)
            let matches = run.link == nil && !(run.inlinePresentationIntent?.contains(.code) ?? false)
                ? pattern.matches(in: raw, range: NSRange(raw.startIndex..., in: raw)) : []
            var start = raw.startIndex
            func appendText(_ range: Range<String.Index>) {
                guard !range.isEmpty else { return }
                var slice = AttributedString(String(raw[range]).replacingOccurrences(of: sentinel, with: (run.inlinePresentationIntent?.contains(.code) ?? false) ? "\\[" : "["))
                slice.setAttributes(run.attributes)
                parts.append(Part(text: slice))
            }
            for match in matches {
                guard let range = Range(match.range, in: raw) else { continue }
                let group = String(raw[range])
                let indices = number.matches(in: group, range: NSRange(group.startIndex..., in: group)).compactMap { result -> Int? in
                    guard let range = Range(result.range(at: 1), in: group), let n = Int(group[range]) else { return nil }; return n - 1
                }
                guard !indices.isEmpty, indices.allSatisfy({ $0 < count }) else { continue }
                appendText(start..<range.lowerBound)
                var unique: [Int] = []; for index in indices where !unique.contains(index) { unique.append(index) }
                parts.append(Part(text: AttributedString(unique.count == 1 ? "笔记" : "笔记 · \(unique.count)"), indices: unique))
                start = range.upperBound
            }
            appendText(start..<raw.endIndex)
        }
        return parts
    }
    private static func markdown(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(text)
    }
}

private struct CitationAttribute: TextAttribute { var id: Int }
private struct CitationHit: Identifiable, Equatable { var id: Int; var rect: CGRect }
private struct CitationRenderer: TextRenderer {
    var didLayout: ([CitationHit]) -> Void
    func draw(layout: Text.Layout, in context: inout GraphicsContext) {
        var hits: [CitationHit] = []
        for line in layout {
            var marks: [Int: CGRect] = [:]
            for run in line {
                if let mark = run[CitationAttribute.self] {
                    let rect = run.typographicBounds.rect
                    marks[mark.id] = marks[mark.id].map { $0.union(rect) } ?? rect
                }
            }
            for (id, rect) in marks {
                hits.append(CitationHit(id: id, rect: rect))
                context.fill(Path(roundedRect: rect.insetBy(dx: 0, dy: -2), cornerRadius: 4), with: .color(Theme.accent.opacity(0.085)))
            }
            for run in line { context.draw(run) }
        }
        didLayout(hits.sorted { $0.id < $1.id })
    }
}

struct CitationAnswerText: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.searchHighlightQuery) private var searchQuery
    let message: ChatMessage
    @State private var hits: [CitationHit] = []
    private var references: [NoteReference] { message.noteReferences ?? [] }
    var body: some View {
        let parts = NoteCitationText.parts(message.text, count: references.count)
        let text = parts.enumerated().reduce(Text("")) { result, item in
            let (index, part) = item
            guard !part.indices.isEmpty else { return result + Text(SearchHighlight.apply(part.text, query: searchQuery)) }
            // Word joiners keep the small label together at a line break.
            let label = AttributedString(" " + String(part.text.characters).map(String.init).joined(separator: "\u{2060}") + " ")
            return result + Text(" ") + Text(label).font(.system(size: 10, weight: .medium)).foregroundColor(Theme.accent).baselineOffset(1).customAttribute(CitationAttribute(id: index)) + Text(" ")
        }
        text.font(.system(size: 15)).lineSpacing(5).textSelection(.enabled)
            .textRenderer(CitationRenderer { layout in
                // Drawing stays synchronous; update hit targets only after the layout pass.
                DispatchQueue.main.async { if hits != layout { hits = layout } }
            })
            .fixedSize(horizontal: false, vertical: true)
            .overlay(alignment: .topLeading) {
                GeometryReader { _ in
                    ForEach(hits) { hit in
                        if parts.indices.contains(hit.id) {
                            let indices = parts[hit.id].indices
                            let group = indices.compactMap { references.indices.contains($0) ? references[$0] : nil }
                            CitationHitButton(titles: group.map(\.title), identifier: "citation-" + message.id + "-" + String(hit.id)) {
                                guard let first = group.first else { return }
                                model.presentReferences(group, selected: first.noteID, messageID: message.id)
                            }
                            .frame(width: max(24, hit.rect.width), height: max(22, hit.rect.height + 4))
                            .position(x: hit.rect.midX, y: hit.rect.midY)
                        }
                    }
                }
            }
    }
}

// Real buttons sit on the rendered labels so selection never consumes a citation click.
// They also expose each source to keyboard focus, VoiceOver and hover help.
private struct CitationHitButton: View {
    let titles: [String]
    let identifier: String
    let action: () -> Void
    @State private var hover = false
    @FocusState private var focused: Bool
    var body: some View {
        Button(action: action) {
            RoundedRectangle(cornerRadius: 4).fill(Theme.accent.opacity(hover ? 0.09 : 0.001))
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(Theme.accent.opacity(focused ? 0.55 : 0), lineWidth: 1))
                .contentShape(Rectangle())
        }.buttonStyle(.plain).focused($focused).onHover { hover = $0 }
            .help(titles.joined(separator: "\n"))
            .accessibilityLabel("查看原文：" + titles.joined(separator: "、"))
            .accessibilityIdentifier(identifier)
    }
}

struct NoteReferencesView: View {
    @EnvironmentObject var model: AppModel
    let references: [NoteReference]
    let messageID: String
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Image(systemName: "books.vertical").foregroundStyle(Theme.accent)
                Text("参考笔记").fontWeight(.medium)
                Text("\(references.count)").foregroundStyle(.secondary).monospacedDigit()
                Spacer()
                Text("查看原文").foregroundStyle(.tertiary)
            }.font(.system(size: 10))
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 250), spacing: 8)], alignment: .leading, spacing: 8) {
                ForEach(Array(references.enumerated()), id: \.element.noteID) { index, reference in
                    ReferenceCard(reference: reference, number: index + 1) {
                        model.presentReferences(references, selected: reference.noteID, messageID: messageID)
                    }
                }
            }
        }.padding(.top, 3).frame(maxWidth: 720, alignment: .leading).accessibilityIdentifier("note-references-" + messageID)
    }
}

private struct ReferenceCard: View {
    @EnvironmentObject var model: AppModel
    let reference: NoteReference
    let number: Int
    var action: () -> Void
    @State private var hover = false
    private var current: Note? { model.library.notes.first { $0.id == reference.noteID } }
    private var unavailable: String? { NoteRetrieval.unavailableReason(reference, state: model.library) }
    private var title: String { current?.title ?? reference.title }
    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "doc.text").font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.accent).frame(width: 26, height: 28).background(Theme.accent.opacity(0.07), in: RoundedRectangle(cornerRadius: 6))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(title).font(.system(size: 12, weight: .semibold)).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                        Text(current.map(model.location) ?? reference.location).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Image(systemName: "arrow.up.right").font(.system(size: 10)).foregroundStyle(hover ? Theme.accent : .secondary).padding(.top, 4)
                }
                if !reference.quote.isEmpty { Text(reference.quote).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading) }
                if let unavailable { Label(unavailable + " · 可查看当时摘录", systemImage: "archivebox").font(.system(size: 9)).foregroundStyle(.secondary) }
                else if current?.version != reference.version { Text("原笔记已更新").font(.system(size: 9)).foregroundStyle(Theme.accent) }
            }.padding(.horizontal, 11).padding(.vertical, 9).frame(maxWidth: .infinity, minHeight: 62, alignment: .topLeading).contentShape(RoundedRectangle(cornerRadius: 11))
        }.buttonStyle(FeedbackStyle(compact: true))
            .background(Theme.secondary.opacity(0.6), in: RoundedRectangle(cornerRadius: 11))
            .overlay(RoundedRectangle(cornerRadius: 11).stroke(hover ? Theme.accent.opacity(0.35) : Theme.border).allowsHitTesting(false))
            .onHover { hover = $0 }
            .help(title + "\n" + (current.map(model.location) ?? reference.location))
            .accessibilityLabel("参考笔记 \(number)：\(title)")
            .accessibilityHint(unavailable ?? "查看原文并定位到引用段落，关闭后继续本次对话")
            .accessibilityIdentifier("note-reference-" + reference.noteID)
    }
}

struct NoteReferenceReader: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.accessibilityReduceMotion) var reduced
    let selection: ReferenceReaderSelection
    var maximumHeight: CGFloat
    @State private var measuredHeight: CGFloat?
    @State private var selectedID: String
    @FocusState private var closeFocused: Bool
    init(selection: ReferenceReaderSelection, maximumHeight: CGFloat) {
        self.selection = selection
        self.maximumHeight = maximumHeight
        _selectedID = State(initialValue: selection.selectedNoteID)
    }
    private var reference: NoteReference { selection.references.first { $0.noteID == selectedID } ?? selection.references[0] }
    private var note: Note? { model.library.notes.first { $0.id == selectedID } }
    private var unavailable: String? { NoteRetrieval.unavailableReason(reference, state: model.library) }
    private var index: Int { selection.references.firstIndex { $0.noteID == selectedID } ?? 0 }
    private var highlightedBlock: String? {
        guard let note, !reference.blockID.isEmpty, let block = note.blocks.first(where: { $0.id == reference.blockID }), NoteRetrieval.blockText(block).contains(reference.quote) else { return nil }
        return block.id
    }
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "doc.text.magnifyingglass").foregroundStyle(Theme.accent)
                Text("笔记原文").font(.system(size: 13, weight: .semibold))
                Text("\(index + 1) / \(selection.references.count)").font(.system(size: 10)).foregroundStyle(.secondary).monospacedDigit()
                Spacer()
                if selection.references.count > 1 {
                    QuietIconButton(icon: "chevron.left", label: "上一篇引用", size: 30) { adjacent(-1) }.disabled(index == 0)
                    QuietIconButton(icon: "chevron.right", label: "下一篇引用", size: 30) { adjacent(1) }.disabled(index + 1 == selection.references.count)
                }
                Button { model.referenceReader = nil } label: { Label("返回对话", systemImage: "xmark").font(.system(size: 11)).padding(.horizontal, 10).frame(height: 32) }
                    .buttonStyle(FeedbackStyle(compact: true)).keyboardShortcut(.cancelAction).focused($closeFocused).accessibilityIdentifier("close-note-reference")
            }.padding(.horizontal, 20).padding(.vertical, 13)
            Divider().opacity(0.65)
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(note.map(model.location) ?? reference.location).font(.system(size: 11)).foregroundStyle(.secondary).textSelection(.enabled)
                            Text(note?.title ?? reference.title).font(.system(size: 20, weight: .semibold)).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                            if let note, unavailable == nil {
                                Text("更新于 " + note.updatedAt.formatted(date: .abbreviated, time: .omitted)).font(.system(size: 10)).foregroundStyle(.tertiary)
                            }
                        }
                        if let unavailable {
                            Label(unavailable, systemImage: "archivebox").font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
                            Text("下面保留的是回答时的摘录。恢复原笔记后，这个入口会重新可用。").font(.system(size: 12)).foregroundStyle(.secondary)
                            quoteSnapshot
                        } else if let note {
                            if note.version != reference.version {
                                VStack(alignment: .leading, spacing: 8) {
                                    Label("原笔记在这次回答后有更新", systemImage: "clock.arrow.circlepath").font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.accent)
                                    Text(highlightedBlock == nil ? "当前显示最新正文；回答时的摘录保留在下方，原段落可能已修改。" : "当前显示最新正文，引用段落仍可定位。").font(.system(size: 11)).foregroundStyle(.secondary)
                                    if highlightedBlock == nil { quoteSnapshot }
                                }.padding(13).background(Theme.secondary, in: RoundedRectangle(cornerRadius: 10))
                            }
                            ForEach(note.blocks) { block in
                                VStack(alignment: .leading, spacing: 8) {
                                    if block.id == highlightedBlock { Label("本次引用", systemImage: "text.quote").font(.system(size: 10, weight: .medium)).foregroundStyle(Theme.accent) }
                                    ContentBlockView(block: block, fontSize: min(model.library.settings.fontSize, 16), spacing: min(model.library.settings.lineSpacing, 6))
                                }.padding(.horizontal, 10).padding(.vertical, block.id == highlightedBlock ? 10 : 3).frame(maxWidth: .infinity, alignment: .leading)
                                    .background(block.id == highlightedBlock ? Theme.accent.opacity(0.065) : .clear, in: RoundedRectangle(cornerRadius: 11))
                                    .overlay(RoundedRectangle(cornerRadius: 11).stroke(block.id == highlightedBlock ? Theme.accent.opacity(0.22) : .clear))
                                    .id(block.id)
                            }
                            if note.blocks.isEmpty { Text("这篇笔记还没有正文。").font(.system(size: 13)).foregroundStyle(.secondary) }
                        }
                    }.padding(.horizontal, 20).padding(.vertical, 18).frame(maxWidth: .infinity, alignment: .leading)
                        .id("reference-top")
                        .background(GeometryReader { geometry in Color.clear.preference(key: ReferenceBodyHeight.self, value: geometry.size.height) })
                }.id(selectedID)
                    .frame(height: min(max(180, measuredHeight ?? 320), max(180, maximumHeight - 122)))
                    .onPreferenceChange(ReferenceBodyHeight.self) { height in
                        guard height > 0, measuredHeight == nil else { return }
                        var transaction = Transaction(); transaction.disablesAnimations = true
                        // Keep the first document's viewport while moving between sources.
                        withTransaction(transaction) { measuredHeight = height }
                    }
                    .task(id: selectedID) {
                        await Task.yield()
                        var transaction = Transaction(); transaction.disablesAnimations = true
                        // A citation near the beginning should retain its title and location.
                        let firstBlock = note?.blocks.first?.id
                        let anchor = unavailable == nil && highlightedBlock != firstBlock ? highlightedBlock ?? "reference-top" : "reference-top"
                        withTransaction(transaction) { proxy.scrollTo(anchor, anchor: .top) }
                    }
            }
            Divider().opacity(0.65)
            HStack(spacing: 10) {
                Text("关闭后继续原来的对话").font(.system(size: 10)).foregroundStyle(.secondary)
                Spacer()
                Button { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(reference.quote, forType: .string); model.toast = "已复制原文摘录" } label: { Label("复制摘录", systemImage: "doc.on.doc").font(.system(size: 11)).padding(.horizontal, 10).frame(height: 34) }.buttonStyle(FeedbackStyle(compact: true)).disabled(reference.quote.isEmpty)
                ActionButton(title: "在笔记本中打开", icon: "arrow.up.right", primary: true) { model.openReferenceInNotebook(reference, from: selection) }.disabled(unavailable != nil).accessibilityIdentifier("open-reference-in-notebook")
            }.padding(.horizontal, 20).padding(.vertical, 12)
        }.background(Theme.panel, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.border).allowsHitTesting(false))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .shadow(color: .black.opacity(0.18), radius: 28, y: 10)
            .onAppear { closeFocused = true }
            .accessibilityIdentifier("note-reference-reader")
    }
    @ViewBuilder private var quoteSnapshot: some View {
        if !reference.quote.isEmpty { VStack(alignment: .leading, spacing: 6) { Text("回答时的原文").font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary); Text(reference.quote).font(.system(size: 13)).lineSpacing(5).textSelection(.enabled) } }
    }
    private func adjacent(_ offset: Int) {
        let next = index + offset
        guard selection.references.indices.contains(next) else { return }
        // Replace locally; avoid sliding the entire document across the screen.
        selectedID = selection.references[next].noteID
    }
}

private struct ReferenceBodyHeight: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}
