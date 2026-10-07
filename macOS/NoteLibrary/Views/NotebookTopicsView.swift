import SwiftUI

/// Chapter collections stay separate from the long-form reader: one idea per
/// card, a predictable grid, and local disclosure for unusually long material.
struct NotebookTopicsView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduced
    @State private var preview: TopicEntry?
    private var kinds: [BlockKind] {
        model.notebookSection == "visuals" ? [.image, .diagram, .table]
            : BlockKind(rawValue: model.notebookSection).map { [$0] } ?? []
    }
    private struct TopicGroup: Identifiable {
        let chapter: Chapter
        let entries: [TopicEntry]
        var id: String { chapter.id }
    }
    private var groups: [TopicGroup] {
        guard model.destination.hasPrefix("book:") else { return [] }
        let bookID = String(model.destination.dropFirst(5))
        let notes = model.visibleNotes
        let query = model.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return model.library.chapters
            .filter { $0.notebookID == bookID && (model.chapterFilter == nil || $0.id == model.chapterFilter) }
            .sorted { $0.order < $1.order }
            .compactMap { chapter in
                let entries = notes.filter { $0.chapterID == chapter.id }.flatMap { note in
                    note.blocks.filter { block in
                        kinds.contains(block.kind) && (query.isEmpty ||
                            LibrarySearch.blockMatches(block, query: query) || LibrarySearch.matches(note.title, query: query) || note.tags.contains { LibrarySearch.matches($0, query: query) })
                    }.map { TopicEntry(note: note, block: $0) }
                }
                return entries.isEmpty ? nil : TopicGroup(chapter: chapter, entries: entries)
            }
    }
    var body: some View {
        GeometryReader { geometry in
            let available = max(1, geometry.size.width - 48)
            let visual = model.notebookSection == "visuals" || model.notebookSection == "formula"
            let columns = TopicCardLayout.columnCount(width: available, visual: visual)
            let sections = groups
            ScrollViewReader { proxy in
                ScrollView {
                    if sections.isEmpty {
                        VStack(spacing: 14) {
                            Image(systemName: kinds.first?.icon ?? "square.grid.2x2")
                                .font(.system(size: 32, weight: .light)).foregroundStyle(Theme.accent)
                            Text(model.searchText.isEmpty ? "这本笔记还没有此类条目" : "没有找到相关条目")
                                .font(.system(size: 16, weight: .medium))
                            Text("条目来自本书笔记，按章节排列。")
                                .font(.system(size: 12)).foregroundStyle(.secondary)
                            ActionButton(title: "回到全部内容", icon: "doc.text") { model.notebookSection = "notes" }
                        }.frame(maxWidth: .infinity).padding(.top, 80)
                    } else {
                        LazyVStack(alignment: .leading, spacing: 30) {
                            ForEach(sections) { section in
                                VStack(alignment: .leading, spacing: 14) {
                                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                                        Text(section.chapter.title).font(.system(size: 15, weight: .semibold))
                                            .fixedSize(horizontal: false, vertical: true).accessibilityAddTraits(.isHeader)
                                        Text("\(section.entries.count) 个条目")
                                            .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize()
                                        Spacer(minLength: 0)
                                    }
                                    LazyVStack(spacing: 16) {
                                        ForEach(Array(stride(from: 0, to: section.entries.count, by: columns)), id: \.self) { start in
                                            TopicCardLayout(columns: columns) {
                                                ForEach(section.entries[start..<min(start + columns, section.entries.count)]) { entry in
                                                    TopicCard(entry: entry, returnToCard: {
                                                        withAnimation(reduced || model.library.settings.reduceMotion ? nil : .easeInOut(duration: 0.2)) {
                                                            proxy.scrollTo(entry.id, anchor: .top)
                                                        }
                                                    }) { preview = entry }.id(entry.id)
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }.padding(24)
                    }
                }.id(model.destination + ":" + model.notebookSection)
                    .environment(\.searchHighlightQuery, model.searchText)
                    .accessibilityIdentifier("notebook-topics")
                    .sheet(item: $preview) { entry in
                        TopicVisualPreview(entry: entry, maximumHeight: min(740, geometry.size.height + 100))
                            .frame(width: min(900, geometry.size.width - 32))
                            .environmentObject(model)
                    }
            }
        }
    }
}

private struct TopicEntry: Identifiable {
    let note: Note
    let block: ContentBlock
    var id: String { note.id + ":" + block.id }
}

/// Equalise each row's outside edges and footer, without squeezing its text.
struct TopicCardLayout: Layout {
    let columns: Int
    var spacing: CGFloat = 16
    static func columnCount(width: CGFloat, visual: Bool) -> Int {
        max(1, min(visual ? 2 : 3, Int((max(0, width) + 16) / ((visual ? 420 : 300) + 16))))
    }
    private func cellWidth(_ width: CGFloat) -> CGFloat {
        max(1, (width - spacing * CGFloat(max(0, columns - 1))) / CGFloat(max(1, columns)))
    }
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width.flatMap { $0.isFinite ? max(1, $0) : nil } ?? 600
        let height = subviews.map { $0.sizeThatFits(.init(width: cellWidth(width), height: nil)).height }.max() ?? 0
        return CGSize(width: width, height: height)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let width = cellWidth(bounds.width)
        for index in subviews.indices {
            subviews[index].place(at: CGPoint(x: bounds.minX + CGFloat(index) * (width + spacing), y: bounds.minY),
                                 anchor: .topLeading, proposal: .init(width: width, height: bounds.height))
        }
    }
}

private struct TopicCard: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduced
    let entry: TopicEntry
    let returnToCard: () -> Void
    let preview: () -> Void
    @State private var tableExpanded = false
    private var block: ContentBlock { entry.block }
    private var visual: Bool { [.table, .image, .diagram].contains(block.kind) }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: block.kind.icon).font(.system(size: 13))
                        .foregroundStyle(Theme.accent).frame(width: 16, height: 20).accessibilityHidden(true)
                    HighlightedText(block.text.isEmpty ? block.kind.label : block.text)
                        .font(.system(size: 14, weight: .semibold)).lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, minHeight: 36, alignment: .topLeading)
                        .accessibilityAddTraits(.isHeader)
                    if visual {
                        QuietIconButton(icon: "arrow.up.left.and.arrow.down.right", label: "放大查看：" + block.text, size: 26, action: preview)
                            .accessibilityIdentifier("topic-preview-" + block.id)
                    }
                }
                cardContent
            }.padding(18)
            Spacer(minLength: 0)
            sourceActions.padding(.horizontal, 12).padding(.vertical, 8)
                .background(Theme.secondary.opacity(0.6))
        }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Theme.background)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.border.opacity(0.8), lineWidth: 0.75).allowsHitTesting(false) }
            .textSelection(.enabled).noteContextActions(entry.note)
            .accessibilityElement(children: .contain).accessibilityIdentifier("topic-entry-" + block.id)
    }
    @ViewBuilder private var cardContent: some View {
        switch block.kind {
        case .term, .callout:
            TopicCardText(text: block.detail, onCollapse: returnToCard)
        case .table:
            ReadingTableView(rows: tableExpanded || !model.searchText.isEmpty ? block.rows : Array(block.rows.prefix(6)), fontSize: 13)
            if block.rows.count > 6 && model.searchText.isEmpty {
                Button {
                    let wasExpanded = tableExpanded
                    withAnimation(reduced || model.library.settings.reduceMotion ? nil : .easeInOut(duration: 0.2)) { tableExpanded.toggle() }
                    if wasExpanded { returnToCard() }
                } label: {
                    HStack(spacing: 5) {
                        Text(tableExpanded ? "收起表格" : "展开全部 \(block.rows.count - 1) 行")
                        Image(systemName: "chevron.down").font(.system(size: 9, weight: .semibold))
                            .rotationEffect(.degrees(tableExpanded ? 180 : 0)).frame(width: 12, height: 12)
                    }.font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.accent).padding(.horizontal, 6)
                }.buttonStyle(FeedbackStyle(compact: true)).accessibilityValue(tableExpanded ? "已展开" : "已收起")
            }
            if !block.detail.isEmpty { TopicCardText(text: block.detail, lineLimit: 4, onCollapse: returnToCard) }
        case .diagram:
            if let diagram = block.diagram { StudyDiagramView(diagram: diagram) }
            if !block.detail.isEmpty { TopicCardText(text: block.detail, lineLimit: 4, onCollapse: returnToCard) }
        case .image:
            if let id = block.assetID, let url = model.assetURL(id) {
                SourceImageView(url: url, revision: model.asset(id)?.digest ?? "")
                    .frame(height: 220).frame(maxWidth: .infinity).clipped()
            }
            if !block.detail.isEmpty { TopicCardText(text: block.detail, lineLimit: 4, onCollapse: returnToCard) }
        case .formula:
            FormulaView(formula: block.text, fontSize: 15)
            if !block.detail.isEmpty { TopicCardText(text: block.detail, onCollapse: returnToCard) }
        default:
            TopicCardText(text: block.detail, onCollapse: returnToCard)
        }
    }
    private var sourceActions: some View {
        HStack(spacing: 8) {
            Button {
                model.openNote(entry.note); model.focusedBlockID = block.id
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "arrow.up.right").font(.system(size: 10))
                    HighlightedText(entry.note.title).font(.system(size: 10)).lineLimit(1).truncationMode(.tail)
                }.padding(.horizontal, 5).frame(height: 28)
            }.buttonStyle(FeedbackStyle(compact: true))
                .help("在笔记中查看：" + entry.note.title)
                .accessibilityLabel("查看原笔记：" + entry.note.title)
                .accessibilityIdentifier("topic-source-" + block.id)
            Spacer(minLength: 0)
            QuietIconButton(icon: "square.and.pencil", label: "编辑条目：" + block.text, size: 28) { model.editorNote = entry.note }
        }.textSelection(.disabled)
    }
}

/// Measure the actual rendered text, so disclosure is only offered when needed.
/// No summary is generated and no note content is removed.
private struct TopicCardText: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduced
    let text: String
    var lineLimit = 7
    var onCollapse: () -> Void = {}
    @State private var expanded = false
    @State private var fullHeight: CGFloat = 0
    @State private var previewHeight: CGFloat = 0
    private var hasMore: Bool { fullHeight > previewHeight + 1 }
    private var attributed: AttributedString {
        (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(text)
    }
    private var prose: some View {
        Text(SearchHighlight.apply(attributed, query: model.searchText)).font(.system(size: 14)).lineSpacing(5)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            prose.lineLimit(expanded || !model.searchText.isEmpty ? nil : lineLimit).fixedSize(horizontal: false, vertical: true)
                .background(alignment: .topLeading) {
                    prose.fixedSize(horizontal: false, vertical: true)
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { fullHeight = $0 }
                        .hidden().accessibilityHidden(true)
                }
                .background(alignment: .topLeading) {
                    prose.lineLimit(lineLimit).fixedSize(horizontal: false, vertical: true)
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { previewHeight = $0 }
                        .hidden().accessibilityHidden(true)
                }
            if hasMore && model.searchText.isEmpty {
                Button {
                    let wasExpanded = expanded
                    withAnimation(reduced || model.library.settings.reduceMotion ? nil : .easeInOut(duration: 0.2)) { expanded.toggle() }
                    if wasExpanded { onCollapse() }
                } label: {
                    HStack(spacing: 5) {
                        Text(expanded ? "收起" : "展开全文")
                        Image(systemName: "chevron.down").font(.system(size: 9, weight: .semibold))
                            .rotationEffect(.degrees(expanded ? 180 : 0)).frame(width: 12, height: 12)
                    }.font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.accent).padding(.horizontal, 6)
                }.buttonStyle(FeedbackStyle(compact: true)).accessibilityValue(expanded ? "已展开" : "已收起")
            }
        }
    }
}

private struct TopicVisualPreview: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let entry: TopicEntry
    let maximumHeight: CGFloat
    @State private var contentHeight: CGFloat = 0
    @State private var headerHeight: CGFloat = 72
    private var bodyHeight: CGFloat {
        let estimate = entry.block.kind == .table ? CGFloat(entry.block.rows.count) * 48 + 24 : 540
        return min(max(100, maximumHeight - headerHeight), contentHeight > 0 ? contentHeight : estimate)
    }
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text(entry.block.text.isEmpty ? entry.block.kind.label : entry.block.text)
                    .font(.system(size: 16, weight: .semibold)).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 12)
                QuietIconButton(icon: "xmark", label: "关闭放大查看") { dismiss() }
            }.padding(20)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { headerHeight = $0 }
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if entry.block.kind == .table { ReadingTableView(rows: entry.block.rows, fontSize: 15) }
                    else if let diagram = entry.block.diagram { StudyDiagramView(diagram: diagram) }
                    else if let id = entry.block.assetID, let url = model.assetURL(id) {
                        SourceImageView(url: url, revision: model.asset(id)?.digest ?? "", maxPixelSize: 3200)
                    }
                    if !entry.block.detail.isEmpty { Text(entry.block.detail).font(.system(size: 15)).lineSpacing(6).fixedSize(horizontal: false, vertical: true) }
                }.textSelection(.enabled).padding(.horizontal, 24).padding(.bottom, 24)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
            }.frame(height: bodyHeight)
        }.background(Theme.panel).onExitCommand { dismiss() }
            .accessibilityIdentifier("topic-visual-preview")
    }
}

/// Keep complete cells, including ragged imported rows. Width follows content;
/// height follows the tallest *measured* cell in that row, never a grid's surplus.
struct ReadingTableView: View {
    let rows: [[String]]
    var fontSize: Double = 14
    private var columns: Int { rows.map(\.count).max() ?? 0 }
    var body: some View {
        if columns > 0 {
            ViewThatFits(in: .horizontal) {
                ReadingTableLayout(weights: ReadingTableLayout.columnWeights(rows), minimumColumnWidth: max(110, fontSize * 7.5)) {
                    ForEach(rows.indices, id: \.self) { row in
                        ForEach(0..<columns, id: \.self) { column in
                            HighlightedText(rows[row].indices.contains(column) ? rows[row][column] : "")
                                .font(.system(size: fontSize, weight: row == 0 ? .semibold : .regular))
                                .lineSpacing(4).fixedSize(horizontal: false, vertical: true)
                                .padding(.horizontal, 14).padding(.vertical, 12)
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                                .background(row == 0 ? Theme.secondary : row.isMultiple(of: 2) ? Theme.secondary.opacity(0.5) : .clear)
                                .accessibilityAddTraits(row == 0 ? .isHeader : [])
                        }
                    }
                }.clipShape(RoundedRectangle(cornerRadius: 8))
                // Many-column tables reflow into labelled records in a narrow reader.
                // This preserves every cell without introducing a scroll trap.
                VStack(alignment: .leading, spacing: 12) {
                    if rows.count == 1 {
                        ForEach(rows[0].indices, id: \.self) { HighlightedText(rows[0][$0]).font(.system(size: fontSize, weight: .semibold)) }
                    } else {
                        ForEach(1..<rows.count, id: \.self) { row in
                            VStack(alignment: .leading, spacing: 12) {
                                ForEach(0..<columns, id: \.self) { column in
                                    VStack(alignment: .leading, spacing: 4) {
                                        if rows[0].indices.contains(column), !rows[0][column].isEmpty {
                                            HighlightedText(rows[0][column]).font(.system(size: max(11, fontSize - 2), weight: .semibold)).foregroundStyle(.secondary)
                                        }
                                        HighlightedText(rows[row].indices.contains(column) ? rows[row][column] : "")
                                            .font(.system(size: fontSize)).lineSpacing(4)
                                    }.fixedSize(horizontal: false, vertical: true)
                                }
                            }.padding(14).frame(maxWidth: .infinity, alignment: .leading)
                                .background(Theme.secondary.opacity(row.isMultiple(of: 2) ? 0.5 : 1), in: RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }.textSelection(.enabled).accessibilityElement(children: .contain).accessibilityLabel("表格")
        }
    }
}

struct ReadingTableLayout: Layout {
    let weights: [CGFloat]
    var minimumColumnWidth: CGFloat = 110
    static func columnWeights(_ rows: [[String]]) -> [CGFloat] {
        let count = rows.map(\.count).max() ?? 0
        return (0..<count).map { column in
            let longest = rows.filter { $0.indices.contains(column) }.map { row in
                row[column].reduce(CGFloat.zero) { $0 + ($1.isASCII ? 0.55 : 1) }
            }.max() ?? 0
            return max(12, min(32, longest))
        }
    }
    private func measurements(width: CGFloat, subviews: Subviews) -> (widths: [CGFloat], heights: [CGFloat]) {
        guard !weights.isEmpty else { return ([], []) }
        let minimum = min(minimumColumnWidth, width / CGFloat(weights.count))
        var widths = Array(repeating: CGFloat.zero, count: weights.count)
        var remaining = Array(weights.indices)
        var available = width
        while !remaining.isEmpty {
            let sum = remaining.reduce(CGFloat.zero) { $0 + weights[$1] }
            let constrained = remaining.filter { available * weights[$0] / max(1, sum) < minimum }
            if constrained.isEmpty {
                for column in remaining { widths[column] = available * weights[column] / max(1, sum) }
                break
            }
            for column in constrained { widths[column] = minimum; available -= minimum }
            remaining.removeAll { constrained.contains($0) }
        }
        var heights = Array(repeating: CGFloat.zero, count: (subviews.count + weights.count - 1) / weights.count)
        for index in subviews.indices {
            let height = subviews[index].sizeThatFits(.init(width: widths[index % weights.count], height: nil)).height
            heights[index / weights.count] = max(heights[index / weights.count], height)
        }
        return (widths, heights)
    }
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let minimum = CGFloat(weights.count) * minimumColumnWidth
        let proposed = proposal.width.flatMap { $0.isFinite ? $0 : nil } ?? minimum
        let width = max(minimum, proposed)
        let measured = measurements(width: width, subviews: subviews)
        return CGSize(width: width, height: measured.heights.reduce(0, +))
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard !weights.isEmpty else { return }
        let measured = measurements(width: bounds.width, subviews: subviews)
        var y = bounds.minY
        for row in measured.heights.indices {
            var x = bounds.minX
            for column in weights.indices {
                let index = row * weights.count + column
                guard subviews.indices.contains(index) else { continue }
                subviews[index].place(at: CGPoint(x: x, y: y), anchor: .topLeading,
                                     proposal: .init(width: measured.widths[column], height: measured.heights[row]))
                x += measured.widths[column]
            }
            y += measured.heights[row]
        }
    }
}
