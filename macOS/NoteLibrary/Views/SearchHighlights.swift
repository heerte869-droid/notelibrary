import SwiftUI

private struct SearchHighlightKey: EnvironmentKey { static let defaultValue = "" }
extension EnvironmentValues {
    var searchHighlightQuery: String {
        get { self[SearchHighlightKey.self] }
        set { self[SearchHighlightKey.self] = newValue }
    }
}

enum SearchHighlight {
    static func apply(_ source: AttributedString, query: String) -> AttributedString {
        var result = source
        let plain = String(source.characters)
        for range in LibrarySearch.ranges(in: plain, query: query) {
            guard let lower = AttributedString.Index(range.lowerBound, within: result),
                  let upper = AttributedString.Index(range.upperBound, within: result) else { continue }
            result[lower..<upper].backgroundColor = Theme.accent.opacity(0.20)
            result[lower..<upper].foregroundColor = .primary
            var intent = result[lower..<upper].inlinePresentationIntent ?? []
            intent.insert(.stronglyEmphasized)
            result[lower..<upper].inlinePresentationIntent = intent
        }
        return result
    }
}

struct HighlightedText: View {
    @Environment(\.searchHighlightQuery) private var inheritedQuery
    let value: String
    var query: String? = nil
    var markdown = false
    init(_ value: String, query: String? = nil, markdown: Bool = false) {
        self.value = value; self.query = query; self.markdown = markdown
    }
    var body: some View {
        let parsed = markdown ? ((try? AttributedString(markdown: value, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(value)) : AttributedString(value)
        Text(SearchHighlight.apply(parsed, query: query ?? inheritedQuery))
    }
}

struct SearchMatchBar: View {
    let query: String
    let index: Int
    let count: Int
    var titleOnly = false
    let previous: () -> Void
    let next: () -> Void
    let close: () -> Void
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(Theme.accent)
            Text(query).fontWeight(.medium).lineLimit(1).truncationMode(.middle)
            Spacer(minLength: 8)
            Text(titleOnly ? "标题匹配" : "\(count == 0 ? 0 : index + 1) / \(count) 处")
                .foregroundStyle(.secondary).monospacedDigit().fixedSize()
            if count > 1 {
                QuietIconButton(icon: "chevron.up", label: "上一个匹配位置", size: 26, action: previous)
                QuietIconButton(icon: "chevron.down", label: "下一个匹配位置", size: 26, action: next)
            }
            QuietIconButton(icon: "xmark", label: "结束搜索定位", size: 26, action: close)
        }.font(.system(size: 11)).padding(.horizontal, 18).frame(height: 38)
            .background(Theme.accent.opacity(0.045))
            .accessibilityElement(children: .contain).accessibilityIdentifier("search-match-navigation")
    }
}

struct SearchMessageText: View {
    let message: ChatMessage
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(LibrarySearch.paragraphs(message.text).enumerated()), id: \.offset) { index, paragraph in
                Group {
                    if !(message.noteReferences ?? []).isEmpty, message.role != "user" {
                        CitationAnswerText(message: paragraphMessage(paragraph))
                    } else {
                        HighlightedText(paragraph, markdown: true).font(.system(size: 15)).lineSpacing(5)
                            .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                    }
                }.id(LibrarySearch.messageAnchor(message.id, paragraph: index))
            }
        }
    }
    private func paragraphMessage(_ text: String) -> ChatMessage { var copy = message; copy.text = text; return copy }
}
