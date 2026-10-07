import SwiftUI

enum BookshelfLayoutStyle: String, CaseIterable, Identifiable {
    case wide, centered
    var id: String { rawValue }
    var title: String { self == .centered ? "居中陈列" : "宽幅书架" }
    var detail: String { self == .centered ? "保持适中的书本尺寸，两侧留出空间。" : "减少两侧留白，窗口变宽时增加每行数量。" }
    static func resolved(_ value: String?) -> Self { Self(rawValue: value ?? "") ?? .wide }
}

struct BookshelfLayout {
    let style: BookshelfLayoutStyle
    let inset: CGFloat
    let spacing: CGFloat
    let columns: Int
    let cardWidth: CGFloat
    let contentWidth: CGFloat
    let coverHeight: CGFloat
    var cardHeight: CGFloat { coverHeight + 176 }

    init(availableWidth: CGFloat, style: BookshelfLayoutStyle, previous: BookshelfLayout? = nil) {
        self.style = style
        inset = style == .wide ? 24 : 32
        spacing = style == .wide ? 16 : 20
        let available = max(260, availableWidth - inset * 2)
        // Choose columns from space, never from the number of books. A sparse shelf
        // must not enlarge its remaining books when another book is removed.
        let stride: CGFloat = style == .wide ? 301 : 328
        let limit = style == .wide ? Int.max : 4
        let fitting = min(limit, max(1, Int((available + spacing) / stride)))
        if let previous, previous.style == style, fitting > previous.columns {
            // A 12-point entry buffer keeps a small reversal of the resize handle
            // from repeatedly swapping the last column between two rows.
            let buffered = min(limit, max(1, Int((available + spacing - 12) / stride)))
            columns = max(previous.columns, buffered)
        } else {
            // Shrink immediately when a column no longer fits; never overflow.
            columns = fitting
        }
        cardWidth = min(style == .wide ? 312 : 324, (available - CGFloat(columns - 1) * spacing) / CGFloat(columns))
        contentWidth = cardWidth * CGFloat(columns) + CGFloat(columns - 1) * spacing
        // Extra room adds columns before it can inflate covers. Both layouts keep
        // a portrait card, while labels and controls retain their normal size.
        coverHeight = max((cardWidth - 24) * 0.74, style == .wide ? cardWidth * 1.27 - 176 : 0)
    }
}

struct HomeView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduced
    @State private var query = ""
    @State private var scope = "all"
    @State private var order = "updated"
    @State private var previousLayout: BookshelfLayout?
    private var books: [Notebook] {
        model.activeNotebooks.filter { book in
            let notes = model.notes(in: book.id)
            let matches = query.isEmpty || (book.title + book.subject + (book.summary ?? "")).localizedCaseInsensitiveContains(query)
            let pending = Set((model.library.reviewRecords ?? []).filter { $0.rating == "again" }.map(\.blockID))
            return matches && (scope == "all" || scope == "unread" && notes.contains { !model.isRead($0.id) } || scope == "review" && notes.flatMap(\.blocks).contains { pending.contains($0.id) } || scope == "pinned" && book.pinned == true)
        }.sorted {
            if ($0.pinned == true) != ($1.pinned == true) { return $0.pinned == true }
            if order == "title" { return $0.title.localizedStandardCompare($1.title) == .orderedAscending }
            if order == "created" { return $0.createdAt > $1.createdAt }
            return (model.notes(in: $0.id).first?.updatedAt ?? $0.createdAt) > (model.notes(in: $1.id).first?.updatedAt ?? $1.createdAt)
        }
    }
    private var shelfMotion: Animation? { reduced || model.library.settings.reduceMotion ? nil : .easeOut(duration: 0.18) }
    private var layoutStyle: BookshelfLayoutStyle { .resolved(model.library.settings.bookshelfLayout) }
    var body: some View {
        GeometryReader { geometry in
            let layout = BookshelfLayout(availableWidth: geometry.size.width, style: layoutStyle, previous: previousLayout)
            let pageWidth = layoutStyle == .wide ? max(260, geometry.size.width - layout.inset * 2) : layout.contentWidth
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 7) { Text("我的书架").font(.system(size: 27, weight: .semibold)); Text("按学科收好笔记，沿着章节继续阅读。").font(.system(size: 12)).foregroundStyle(.secondary) }
                    Spacer(); ActionButton(title: "新建笔记本", icon: "plus") { model.newBookPresented = true }; ActionButton(title: "导入原稿", icon: "photo.badge.plus", primary: true) { model.chooseSources() }
                }
                HStack(spacing: 10) {
                    SearchBox(placeholder: "搜索笔记本、学科", text: $query).frame(maxWidth: 350)
                    Spacer(minLength: 0)
                    ChoicePicker(title: "书架范围", selection: scope, options: [ChoiceOption(id: "all", title: "全部笔记本"), ChoiceOption(id: "unread", title: "有未读笔记", icon: "book"), ChoiceOption(id: "review", title: "有待巩固内容", icon: "rectangle.on.rectangle"), ChoiceOption(id: "pinned", title: "已置顶", icon: "pin")]) { scope = $0 }
                    ChoicePicker(title: "书架排序", selection: order, options: [ChoiceOption(id: "updated", title: "最近更新"), ChoiceOption(id: "created", title: "最近创建"), ChoiceOption(id: "title", title: "名称顺序")]) { order = $0 }
                }
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(layout.cardWidth), spacing: layout.spacing, alignment: .top), count: layout.columns), alignment: .leading, spacing: 22) {
                    ForEach(books) { book in
                        BookCard(book: book, coverHeight: layout.coverHeight).environment(\.searchHighlightQuery, query)
                            .transition(.opacity)
                    }
                    if query.isEmpty && scope == "all" { creationCard(height: layout.cardHeight) }
                }.frame(width: layout.contentWidth, alignment: .leading)
                    .animation(shelfMotion, value: books.map(\.id))
                    .animation(nil, value: layout.columns)
                if books.isEmpty && (!query.isEmpty || scope != "all") {
                    VStack(spacing: 13) {
                        Image(systemName: "line.3.horizontal.decrease.circle").font(.system(size: 27, weight: .light))
                        Text("这个范围没有笔记本").font(.system(size: 14, weight: .medium))
                        Text("调整筛选，或清空搜索查看书架。").font(.system(size: 11)).foregroundStyle(.secondary)
                        ActionButton(title: "重置筛选", icon: "arrow.counterclockwise") { scope = "all"; query = "" }
                    }.padding(40).frame(maxWidth: .infinity)
                }
                if !model.activeNotebooks.isEmpty {
                    HStack(spacing: 12) {
                        Text("\(model.activeNotebooks.count) 本笔记 · \(model.activeNotes.count) 篇内容").font(.system(size: 11)).foregroundStyle(.secondary)
                        Spacer()
                    }
                }

            }.frame(width: pageWidth, alignment: .leading)
                .padding(.horizontal, layout.inset).padding(.vertical, 32)
                .frame(maxWidth: .infinity, alignment: layoutStyle == .wide ? .leading : .center)
                // Live resizing is direct manipulation, not a content transition.
                // Do not let parent animations make the shelf trail the window.
                .animation(nil, value: geometry.size)
                .animation(nil, value: layoutStyle)
        }.background(Theme.background.opacity(0.40))
            .onChange(of: layout.columns, initial: true) { _, _ in rememberLayout(layout) }
            .onChange(of: layoutStyle) { _, _ in rememberLayout(layout) }
        }
    }
    private func rememberLayout(_ layout: BookshelfLayout) {
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) { previousLayout = layout }
    }
    private func creationCard(height: CGFloat) -> some View {
        Button { model.newBookPresented = true } label: {
            VStack(spacing: 12) {
                Image(systemName: "plus").font(.system(size: 19, weight: .light)).foregroundStyle(Theme.accent).frame(width: 40, height: 40).background(Theme.accent.opacity(0.07), in: Circle())
                Text("创建一本笔记").font(.system(size: 15, weight: .medium))
                Text(model.activeNotebooks.isEmpty && model.library.notebooks.contains { $0.archivedAt != nil || $0.deletedAt != nil } ? "已收起的笔记可在「回收站 → 已归档」找回\n也可以开始一本新笔记" : "设置封面与章节\n开始收集新内容").font(.system(size: 11)).foregroundStyle(.secondary).multilineTextAlignment(.center).lineSpacing(6)
            }.padding(18).frame(maxWidth: .infinity).frame(height: height)
        }.buttonStyle(FeedbackStyle()).overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.accent.opacity(0.28), style: StrokeStyle(lineWidth: 1, dash: [5, 4]))).accessibilityIdentifier("shelf-create-notebook")
    }
}

struct BookCover: View {
    let title: String
    let subject: String
    let color: Int
    var style = "paper"
    var compact = false
    private var palette: [Color] { [
        [Color(red: 0.16, green: 0.56, blue: 0.50), Color(red: 0.17, green: 0.44, blue: 0.59)],
        [Color(red: 0.39, green: 0.43, blue: 0.74), Color(red: 0.51, green: 0.35, blue: 0.73)],
        [Color(red: 0.78, green: 0.47, blue: 0.27), Color(red: 0.74, green: 0.35, blue: 0.39)],
        [Color(red: 0.72, green: 0.37, blue: 0.53), Color(red: 0.53, green: 0.36, blue: 0.70)],
        [Color(red: 0.24, green: 0.49, blue: 0.73), Color(red: 0.20, green: 0.57, blue: 0.63)]
    ][abs(color % 5)] }
    var body: some View {
        ZStack(alignment: .leading) {
            LinearGradient(colors: palette, startPoint: .topLeading, endPoint: .bottomTrailing)
            GeometryReader { geometry in
                ZStack {
                    RoundedRectangle(cornerRadius: 10).fill(.white.opacity(0.09)).frame(width: 100, height: 128).rotationEffect(.degrees(-14)).offset(x: 16, y: 9)
                    RoundedRectangle(cornerRadius: 10).fill(.white.opacity(0.11)).frame(width: 100, height: 128).rotationEffect(.degrees(5))
                    VStack(alignment: .leading, spacing: 10) {
                        if style == "index" || style == "lines" {
                            ForEach(0..<3) { i in HStack(spacing: 9) { RoundedRectangle(cornerRadius: 2).fill(.white.opacity(0.72)).frame(width: 9, height: 9); Capsule().fill(.white.opacity(0.40)).frame(width: CGFloat(47 - i * 7), height: 4) } }
                        } else {
                            Image(systemName: "sparkle").font(.system(size: 27, weight: .light)).foregroundStyle(.white.opacity(0.66)).padding(.bottom, 8)
                            Capsule().fill(.white.opacity(0.60)).frame(width: 55, height: 4)
                            Capsule().fill(.white.opacity(0.35)).frame(width: 38, height: 4)
                        }
                    }.rotationEffect(.degrees(5))
                }.scaleEffect(compact ? 0.85 : 1).position(x: geometry.size.width - 50, y: geometry.size.height - 32)
            }.allowsHitTesting(false)
            VStack(alignment: .leading, spacing: 15) {
                HStack(spacing: 6) { Image(systemName: "book.closed.fill").font(.system(size: 9)); HighlightedText(subject.isEmpty ? "我的笔记" : subject).font(.system(size: 9, weight: .medium)).lineLimit(1) }.padding(.horizontal, 9).padding(.vertical, 6).background(.white.opacity(0.15), in: Capsule())
                Spacer(minLength: 0)
                HighlightedText(title.isEmpty ? "一本新的笔记" : title).font(.system(size: compact ? 24 : 25, weight: .bold)).lineSpacing(4).lineLimit(3).minimumScaleFactor(compact ? 0.85 : 0.72).padding(.trailing, compact ? 32 : 60)
            }.foregroundStyle(.white).padding(compact ? 20 : 22)
        }.clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

struct BookCard: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.searchHighlightQuery) private var searchQuery
    let book: Notebook
    var coverHeight: CGFloat = 222
    @State private var hovered = false
    private var notes: [Note] { model.notes(in: book.id) }
    private var readCount: Int { notes.filter { model.isRead($0.id) }.count }
    private var chapterCount: Int { model.library.chapters.filter { $0.notebookID == book.id }.count }
    private var resume: Note? { let records = model.library.readingRecords ?? []; return records.sorted { $0.lastOpenedAt > $1.lastOpenedAt }.compactMap { record in notes.first { $0.id == record.noteID } }.first ?? notes.first }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button { model.chooseDestination("book:" + book.id) } label: { BookCover(title: book.title, subject: book.subject, color: book.color, style: book.coverStyle ?? "paper", compact: true).frame(height: coverHeight).contentShape(Rectangle()) }.buttonStyle(FeedbackStyle()).help(book.title).padding(12)
            VStack(alignment: .leading, spacing: 9) {
                HStack { Text("\(chapterCount) 章 · \(notes.count) 篇笔记").font(.system(size: 12, weight: .medium)); Spacer(); if book.pinned == true { Image(systemName: "pin.fill").font(.system(size: 10)).foregroundStyle(Theme.accent) } }
                HighlightedText(LibrarySearch.query(searchQuery).isEmpty ? ((book.summary ?? "").isEmpty ? (notes.first?.title ?? "章节已准备好，写下第一篇笔记。") : book.summary!) : LibrarySearch.snippet(book.summary ?? "", query: searchQuery, limit: 90)).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(2).lineSpacing(3).frame(height: 30, alignment: .topLeading).help((book.summary ?? "").isEmpty ? (notes.first?.title ?? "章节已准备好，写下第一篇笔记。") : book.summary!)
                VStack(spacing: 5) {
                    HStack { Text(notes.isEmpty ? "阅读进度" : "已读 \(readCount) / \(notes.count)"); Spacer(); Text(notes.isEmpty ? "尚未开始" : "\(Int(Double(readCount) / Double(notes.count) * 100))%") }.font(.system(size: 9)).foregroundStyle(.secondary)
                    GeometryReader { geometry in Capsule().fill(Theme.border).overlay(alignment: .leading) { Capsule().fill(Theme.accent.opacity(0.7)).frame(width: notes.isEmpty ? 0 : geometry.size.width * Double(readCount) / Double(notes.count)) } }.frame(height: 3)
                }
                Rectangle().fill(Theme.border).frame(height: 1)
                HStack {
                    BookMenu(book: book, compact: true)
                    Spacer()
                    Button { if let resume { model.openNote(resume) } else { model.chooseDestination("book:" + book.id); model.newNote() } } label: { HStack(spacing: 7) { Text(notes.isEmpty ? "写第一篇" : "继续阅读"); Image(systemName: "arrow.right") }.font(.system(size: 12, weight: .medium)).padding(.horizontal, 12).frame(height: 34).contentShape(Rectangle()) }.buttonStyle(FeedbackStyle(tinted: true, compact: true)).accessibilityIdentifier("shelf-open-" + book.id)
                }
            }.padding(.horizontal, 16).padding(.bottom, 14).frame(height: 152, alignment: .top)
        }.background(Theme.panel, in: RoundedRectangle(cornerRadius: 16)).overlay(RoundedRectangle(cornerRadius: 16).stroke(hovered ? Theme.accent.opacity(0.30) : Theme.border)).shadow(color: .black.opacity(hovered ? 0.05 : 0.02), radius: 12, y: 4).onHover { hovered = $0 }
    }
}
func bookMenuOptions(_ book: Notebook) -> [ChoiceOption] {
    [ChoiceOption(id: "edit", title: "封面与章节", icon: "pencil"),
     ChoiceOption(id: "pin", title: book.pinned == true ? "取消置顶" : "置顶笔记本", icon: "pin"),
     ChoiceOption(id: "review", title: "复习这本笔记", icon: "rectangle.on.rectangle"),
     ChoiceOption(id: "archive", title: "归档笔记本", icon: "archivebox", separatorBefore: true),
     ChoiceOption(id: "delete", title: "移到回收站", icon: "trash", destructive: true)]
}
extension AppModel {
    func performBookAction(_ action: String, book: Notebook) {
        switch action {
        case "edit": organizingBookID = book.id
        case "pin": pinBook(book.id)
        case "review": reviewBookID = book.id
        case "archive": archiveBook(book)
        case "delete": deleteBook(book)
        default: break
        }
    }
}
struct BookMenu: View {
    @EnvironmentObject var model: AppModel
    let book: Notebook
    var sourceID = ""
    var sidebar = false
    var compact = false
    var body: some View {
        ActionMenu(title: "管理《\(book.title)》", sourceID: sourceID, trailing: sidebar, size: sidebar ? 30 : compact ? 34 : 36, sidebar: sidebar, options: bookMenuOptions(book)) { model.performBookAction($0, book: book) }
    }
}
struct BookContextActions: ViewModifier {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var center: ChoiceCenter
    let book: Notebook
    var sourceID: String
    func body(content: Content) -> some View {
        content.overlay { GeometryReader { proxy in RightClickSurface { point in
            let frame = proxy.frame(in: .named(center.space))
            center.presentation = .init(sourceID: sourceID, title: book.title, rect: CGRect(x: frame.minX + point.x, y: frame.minY + point.y, width: 1, height: 1), options: bookMenuOptions(book), selected: nil, choose: { model.performBookAction($0, book: book) })
        } } }
    }
}

struct BookCreationView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) var dismiss
    @State private var title = ""
    @State private var subject = ""
    @State private var summary = ""
    @State private var color = 0
    @State private var style = "paper"
    @State private var template = "blank"
    @State private var chapters = "第一章"
    var body: some View {
        VStack(alignment: .leading, spacing: 23) {
            HStack { VStack(alignment: .leading, spacing: 6) { Text("创建笔记本").font(.system(size: 23, weight: .semibold)); Text("封面和目录都可以随时调整。") .font(.system(size: 11)).foregroundStyle(.secondary) }; Spacer(); QuietIconButton(icon: "xmark", label: "取消创建") { dismiss() } }
            HStack(alignment: .top, spacing: 28) {
                VStack(spacing: 18) {
                    BookCover(title: title, subject: subject, color: color, style: style).frame(height: 175)
                    HStack(spacing: 12) { ForEach(0..<5) { i in Button { color = i } label: { Circle().fill(Theme.colors[i]).frame(width: 24, height: 24).overlay { if color == i { Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)).foregroundStyle(.white) } } }.buttonStyle(.plain).accessibilityLabel("封面颜色 \(i + 1)") } }
                    ChoicePicker(title: "封面纹样", selection: style, options: [ChoiceOption(id: "paper", title: "纸页"), ChoiceOption(id: "index", title: "索引")]) { style = $0 }
                }.frame(width: 245)
                VStack(alignment: .leading, spacing: 16) {
                    field("笔记本名称", placeholder: "例如：生物学", text: $title)
                    field("学科 / 主题", placeholder: "例如：自然科学", text: $subject)
                    field("简介", placeholder: "这本笔记准备记录什么", text: $summary)
                    HStack { Text("初始章节").font(.system(size: 11)).foregroundStyle(.secondary); Spacer(); ChoicePicker(title: "章节模板", selection: template, options: [ChoiceOption(id: "blank", title: "空白目录"), ChoiceOption(id: "course", title: "课程学习"), ChoiceOption(id: "reading", title: "阅读摘记"), ChoiceOption(id: "language", title: "语言学习")]) { value in template = value; chapters = ["blank": "第一章", "course": "基础概念\n课堂笔记\n例题与练习\n复习总结", "reading": "阅读摘录\n观点与思考\n延伸资料", "language": "词汇与表达\n语法与用法\n阅读与写作"][value] ?? "第一章" } }
                    TextField("每行一个章节", text: $chapters, axis: .vertical).lineLimit(4...6).textFieldStyle(FieldStyle()).font(.system(size: 12))
                }.frame(maxWidth: .infinity)
            }
            HStack { Text("AI 会在此基础上匹配或新增章节。").font(.system(size: 10)).foregroundStyle(.secondary); Spacer(); ActionButton(title: "取消") { dismiss() }; ActionButton(title: "创建笔记本", primary: true) { if model.createBook(title: title, subject: subject, summary: summary, color: color, style: style, chapters: LibraryEdits.tags(chapters)) { dismiss() } }.disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
        }.padding(28).frame(width: 735).background(Theme.panel)
    }
    private func field(_ label: String, placeholder: String, text: Binding<String>) -> some View { VStack(alignment: .leading, spacing: 7) { Text(label).font(.system(size: 11)).foregroundStyle(.secondary); TextField(placeholder, text: text).textFieldStyle(FieldStyle()).font(.system(size: 12)) } }
}
