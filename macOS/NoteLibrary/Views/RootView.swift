import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct RootView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.accessibilityReduceMotion) var reduced
    @State private var dropTarget = false
    var body: some View {
        HStack(spacing: 0) {
            ReaderChrome(expanded: !model.readingMode, axis: .horizontal, width: model.isSidebarCollapsed ? 61 : 217) {
                HStack(spacing: 0) {
                    NavigationSidebar()
                    Rectangle().fill(Theme.border).frame(width: 1)
                }
            }
            Group {
                if let failure = model.startupFailure { VStack(spacing: 15) { Image(systemName: "externaldrive.badge.exclamationmark").font(.largeTitle); Text("资料库暂时无法打开").font(.headline); Text(failure).font(.callout).foregroundStyle(.secondary) }.padding(40) }
                else if model.destination == "home" { HomeView() }
                else if model.destination == "chat" { ChatView() }
                else if model.destination == "conversations" { ConversationListView() }
                else if model.destination == "trash" { TrashView() }
                else { LibraryView() }
            }.frame(maxWidth: .infinity, maxHeight: .infinity).background(Theme.panel)
                .overlay(alignment: .topTrailing) {
                    ToastLayer().padding(.top, 76).padding(.trailing, 22)
                }
        }.frame(minWidth: 1010, minHeight: 670).background(Theme.background)
            .animation(ReadingMotion.transition(reduced: reduced || model.library.settings.reduceMotion), value: model.readingMode)
            .animation(ReadingMotion.transition(reduced: reduced || model.library.settings.reduceMotion), value: model.isSidebarCollapsed)
            .disabled(model.clearConversationPresented || model.referenceReader != nil || model.recoveryDeletion != nil).accessibilityHidden(model.clearConversationPresented || model.referenceReader != nil || model.recoveryDeletion != nil)
            .overlay { if dropTarget { ZStack { Theme.accent.opacity(0.07); RoundedRectangle(cornerRadius: 16).stroke(Theme.accent, style: StrokeStyle(lineWidth: 2, dash: [8])).padding(12); Label("松开，添加到对话", systemImage: "doc.badge.plus").font(.title3.weight(.medium)).padding(24).background(Theme.panel, in: RoundedRectangle(cornerRadius: 16)) }.allowsHitTesting(false) } }
            .onDrop(of: [UTType.fileURL], isTargeted: $dropTarget) { providers in
                Task { @MainActor in
                    var urls: [URL] = []
                    for provider in providers {
                        let url: URL? = await withCheckedContinuation { continuation in _ = provider.loadObject(ofClass: URL.self) { url, _ in continuation.resume(returning: url) } }
                        if let url { urls.append(url) }
                    }
                    model.importSources(urls)
                }; return true
            }
            .task(id: model.toast) { guard model.toast != nil else { return }; do { try await Task.sleep(for: .seconds(4)); model.toast = nil } catch {} }
            .sheet(isPresented: $model.settingsPresented, onDismiss: model.settingsDidDismiss) { SettingsView().environmentObject(model).choiceHost() }
            .sheet(item: $model.exportNote) { note in NoteExportView(note: note).environmentObject(model).choiceHost() }
            .sheet(item: $model.editorNote) { note in NoteEditor(note: note).environmentObject(model).choiceHost() }
            .sheet(isPresented: Binding(get: { model.organizingBookID != nil }, set: { if !$0 { model.organizingBookID = nil } })) { if let id = model.organizingBookID { BookStructureView(bookID: id).environmentObject(model).choiceHost() } }
            .sheet(isPresented: $model.historyPresented) { HistoryView().environmentObject(model).choiceHost() }
            .sheet(isPresented: $model.newBookPresented) { BookCreationView().environmentObject(model).choiceHost() }
            .sheet(isPresented: Binding(get: { model.renameConversationID != nil }, set: { if !$0 { model.renameConversationID = nil } })) { if let id = model.renameConversationID { NameSheet(title: "重命名对话", subtitle: "给这次讨论一个容易找到的名称。", initial: model.library.conversations.first { $0.id == id }?.title ?? "", placeholder: "对话名称", save: { model.renameConversation(id, title: $0) }).environmentObject(model) } }
            .sheet(isPresented: Binding(get: { model.noteAction != nil }, set: { if !$0 { model.noteAction = nil } })) { if let action = model.noteAction { NoteActionSheet(action: action).environmentObject(model).choiceHost() } }
            .sheet(isPresented: Binding(get: { model.reviewBookID != nil }, set: { if !$0 { model.reviewBookID = nil } })) { if let id = model.reviewBookID { ReviewView(bookID: id).environmentObject(model).choiceHost() } }
            .sheet(isPresented: $model.contextPresented) { ContextDetailView().environmentObject(model).choiceHost() }
            .sheet(isPresented: Binding(get: { model.selectedSourceID != nil }, set: { if !$0 { model.selectedSourceID = nil } })) {
                if let id = model.selectedSourceID { SourcePreview(id: id).environmentObject(model).id(id) }
            }

            .choiceHost()
            .overlay {
                ZStack {
                    if model.clearConversationPresented, let chat = model.currentConversation {
                        ClearConversationDialog(title: chat.title) {
                            guard model.conversationID == chat.id else { model.clearConversationPresented = false; return }
                            model.clearCurrentConversation()
                            if model.error != nil { model.clearConversationPresented = false }
                        }.transition(.opacity)
                    }
                }.animation(reduced || model.library.settings.reduceMotion ? nil : .easeOut(duration: 0.12), value: model.clearConversationPresented)
            }
            .overlay {
                ZStack { if let request = model.recoveryDeletion { RecoveryConfirmationDialog(request: request).transition(.opacity) } }
                    .animation(reduced || model.library.settings.reduceMotion ? nil : .easeOut(duration: 0.12), value: model.recoveryDeletion != nil)
            }
            .overlay {
                ZStack {
                    if let selection = model.referenceReader {
                        GeometryReader { geometry in
                            ZStack {
                                Color.black.opacity(0.20).contentShape(Rectangle()).onTapGesture { model.referenceReader = nil }
                                NoteReferenceReader(selection: selection, maximumHeight: min(580, geometry.size.height - 64))
                                    .frame(width: min(660, geometry.size.width - 48))
                            }.frame(maxWidth: .infinity, maxHeight: .infinity)
                        }.transition(.opacity).zIndex(4)
                    }
                }.animation(reduced || model.library.settings.reduceMotion ? nil : .easeOut(duration: 0.12), value: model.referenceReader?.id)
            }
            .onChange(of: model.conversationID) { _, _ in model.clearConversationPresented = false; model.referenceReader = nil; model.recoveryDeletion = nil; if !model.destination.hasPrefix("book:") && model.destination != "all" && model.destination != "favorites" && model.destination != "recent" { model.readingMode = false } }
            .onChange(of: model.destination) { _, destination in
                model.clearConversationPresented = false; model.referenceReader = nil; model.recoveryDeletion = nil
                if !destination.hasPrefix("book:"), !["all", "favorites", "recent"].contains(destination) { model.readingMode = false }
            }
            .task { if model.database != nil && model.startupFailure == nil && !model.ai.codex.connected { model.connect() } }
    }
}

// Animate the sidebar surface, never its label or geometry.
struct SidebarSurface: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduced
    var selected = false
    var hovered = false
    var pressed = false
    var secondary = false
    private var motion: Animation? { reduced || model.library.settings.reduceMotion ? nil : .easeOut(duration: hovered ? 0.06 : 0.09) }
    private var fill: Color {
        if selected { return Theme.accent.opacity((secondary ? 0.075 : 0.105) + (pressed ? 0.020 : hovered ? 0.008 : 0)) }
        return Color.primary.opacity(pressed ? 0.055 : hovered ? 0.035 : 0)
    }
    var body: some View {
        RoundedRectangle(cornerRadius: 9, style: .continuous).fill(fill)
            .animation(motion, value: hovered)
            .animation(nil, value: selected)
            .animation(nil, value: pressed)
            .allowsHitTesting(false).accessibilityHidden(true)
    }
}
struct SidebarButtonStyle: ButtonStyle {
    var selected = false
    func makeBody(configuration: Configuration) -> some View { FeedbackBody(configuration: configuration, selected: selected) }
    private struct FeedbackBody: View {
        @Environment(\.isEnabled) private var enabled
        @State private var hovered = false
        let configuration: Configuration
        let selected: Bool
        var body: some View {
            configuration.label
                .foregroundStyle(selected ? Theme.accent : Color.primary)
                .background { SidebarSurface(selected: selected, hovered: enabled && hovered, pressed: enabled && configuration.isPressed) }
                .contentShape(RoundedRectangle(cornerRadius: 9))
                .onHover { hovered = $0 }.onDisappear { hovered = false }
        }
    }
}
struct SidebarIconButton: View {
    var icon: String
    var label: String
    var selected = false
    var size: CGFloat = 30
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 12, weight: .medium)).foregroundStyle(selected ? Theme.accent : .secondary)
                .frame(width: size, height: size).contentShape(Rectangle())
        }.buttonStyle(SidebarButtonStyle(selected: selected)).help(label).accessibilityLabel(label)
    }
}
// Retain both views so collapsing never resets the full sidebar's scroll position.
struct NavigationSidebar: View {
    @EnvironmentObject private var model: AppModel
    private var collapsed: Bool { model.isSidebarCollapsed }
    var body: some View {
        ZStack(alignment: .topLeading) {
            SidebarView().frame(width: 216)
                .opacity(collapsed ? 0 : 1).allowsHitTesting(!collapsed).disabled(collapsed)
                .accessibilityHidden(collapsed)
            SidebarRail().frame(width: 60)
                .opacity(collapsed ? 1 : 0).allowsHitTesting(collapsed).disabled(!collapsed)
                .accessibilityHidden(!collapsed)
        }.frame(width: collapsed ? 60 : 216, alignment: .leading).clipped().background(Theme.background)
    }
}
struct SidebarToggle: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var center: ChoiceCenter
    var body: some View {
        SidebarIconButton(icon: "sidebar.left", label: model.isSidebarCollapsed ? "展开侧栏（⌘⌥S）" : "收起侧栏（⌘⌥S）", size: 32) {
            center.dismiss(); model.toggleSidebar()
        }.accessibilityIdentifier("sidebar-toggle")
            .accessibilityValue(model.isSidebarCollapsed ? "已收起" : "已展开")
    }
}
struct SidebarRail: View {
    @EnvironmentObject private var model: AppModel
    private var books: [Notebook] { SidebarContent.notebooks(model.library.notebooks, collapsed: false) }
    var body: some View {
        VStack(spacing: 0) {
            SidebarToggle().padding(.top, 24).padding(.bottom, 22)
            VStack(spacing: 3) {
                nav("我的书架", "square.grid.2x2", "home")
                nav("AI 对话", "sparkles", "chat")
                nav("全部笔记", "rectangle.stack", "all")
                nav("我的收藏", "star", "favorites")
            }
            VStack(spacing: 4) {
                ActionMenu(title: "笔记本", icon: "books.vertical", sourceID: "rail-books", trailing: true, size: 38, sidebar: true, selection: model.destination.hasPrefix("book:") ? String(model.destination.dropFirst(5)) : nil,
                    options: books.map { ChoiceOption(id: $0.id, title: $0.title, icon: "book.closed") } + [.init(id: "new", title: "新建笔记本", icon: "plus", separatorBefore: true)]) { id in
                        if id == "new" { model.newBookPresented = true } else { model.chooseDestination("book:" + id) }
                    }.background { SidebarSurface(selected: model.destination.hasPrefix("book:")) }
                ActionMenu(title: "最近对话", icon: "bubble.left.and.bubble.right", sourceID: "rail-chats", trailing: true, size: 38, sidebar: true, selection: model.destination == "chat" ? model.conversationID : nil,
                    options: model.recentConversations.prefix(8).map { ChoiceOption(id: $0.id, title: $0.title, icon: "bubble.left") } + [.init(id: "all", title: "全部对话", icon: "text.bubble", separatorBefore: true), .init(id: "new", title: "新建对话", icon: "square.and.pencil")]) { id in
                        if id == "all" { model.chooseDestination("conversations") } else if id == "new" { model.newConversation() } else { model.selectConversation(id) }
                    }
            }.padding(.top, 22)
            Spacer(minLength: 16)
            SidebarUtilities(compact: true).padding(.bottom, 18)
        }.frame(maxHeight: .infinity).background(Theme.background)
    }
    private func nav(_ title: String, _ icon: String, _ destination: String) -> some View {
        Button { model.chooseDestination(destination) } label: {
            Image(systemName: icon).font(.system(size: 15)).frame(width: 38, height: 40)
        }.buttonStyle(SidebarButtonStyle(selected: model.destination == destination))
            .help(title).accessibilityLabel(title).accessibilityIdentifier("rail-" + destination)
            .accessibilityAddTraits(model.destination == destination ? .isSelected : [])
    }
}

// Utilities follow the rail rhythm, without a separate capsule competing with navigation.
struct SidebarUtilities: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var center: ChoiceCenter
    var compact = false
    var body: some View {
        Group {
            if compact { VStack(spacing: 6) { actions } }
            else { HStack(spacing: 4) { actions } }
        }
    }
    @ViewBuilder private var actions: some View {
        utility("回收站", icon: "trash", selected: model.destination == "trash", id: compact ? "rail-trash" : "nav-trash") {
            model.chooseDestination("trash")
        }
        utility("设置", icon: "gearshape", selected: model.settingsPresented, id: compact ? "rail-settings" : "nav-settings") {
            model.settingsPresented = true
        }
    }
    private func utility(_ title: String, icon: String, selected: Bool, id: String, action: @escaping () -> Void) -> some View {
        Button { center.dismiss(); action() } label: {
            HStack(spacing: 7) {
                Image(systemName: icon).font(.system(size: 13, weight: .regular)).frame(width: 20, height: 20)
                    .overlay(alignment: .bottomTrailing) {
                        if compact && title == "设置" {
                            Circle().fill(model.connectionStatus == "Codex 已连接" ? Theme.accent : .secondary)
                                .frame(width: 4, height: 4).overlay { Circle().stroke(Theme.background, lineWidth: 1.5) }
                                .offset(x: 2, y: 1).accessibilityHidden(true)
                        }
                    }
                if !compact { Text(title).font(.system(size: 11, weight: .medium)) }
            }.foregroundStyle(selected ? Theme.accent : .secondary)
                .frame(width: compact ? 38 : nil, height: 38).frame(maxWidth: compact ? nil : .infinity)
                .contentShape(Rectangle())
        }.buttonStyle(SidebarButtonStyle(selected: selected))
            .help(title == "设置" ? "设置 · " + model.connectionStatus : title).accessibilityLabel(title).accessibilityIdentifier(id)
            .accessibilityValue(title == "设置" ? model.connectionStatus : "")
            .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

struct SidebarView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduced
    private var disclosureMotion: Animation? { reduced || model.library.settings.reduceMotion ? nil : .easeOut(duration: 0.12) }
    private var booksCollapsed: Bool { model.library.settings.sidebarNotebooksCollapsed ?? (model.activeNotebooks.count > 6) }
    private var chatsCollapsed: Bool { model.library.settings.sidebarConversationsCollapsed ?? false }
    private var sidebarBooks: [Notebook] { SidebarContent.notebooks(model.library.notebooks, collapsed: booksCollapsed) }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 7) {
                Image(systemName: "books.vertical.fill").font(.system(size: 20)).foregroundStyle(Theme.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text("NoteLibrary").font(.system(size: 14, weight: .semibold))
                    Text("你的知识，逐渐成书").font(.system(size: 9)).foregroundStyle(.secondary)
                }.fixedSize()
                Spacer(minLength: 0)
                SidebarToggle()
            }.frame(height: 32).padding(.horizontal, 14).padding(.top, 24).padding(.bottom, 22)
            VStack(spacing: 3) {
                nav("我的书架", "square.grid.2x2", "home")
                nav("AI 对话", "sparkles", "chat")
                nav("全部笔记", "rectangle.stack", "all", count: model.activeNotes.count)
                nav("我的收藏", "star", "favorites", count: model.activeNotes.filter(\.favorite).count)
            }.padding(.horizontal, 10)
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 0) {
                            Button { model.updateSettings { $0.sidebarNotebooksCollapsed = !booksCollapsed } } label: {
                                HStack(spacing: 6) {
                                    Text("笔记本")
                                    if model.activeNotebooks.count > 3 { disclosure(collapsed: booksCollapsed) }
                                    Spacer(minLength: 0)
                                    if booksCollapsed && model.activeNotebooks.count > 3 { Text("3 / \(model.activeNotebooks.count)").font(.system(size: 9)).monospacedDigit() }
                                }.font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary).padding(.horizontal, 11).frame(maxWidth: .infinity, minHeight: 32).contentShape(Rectangle())
                            }.buttonStyle(SidebarButtonStyle()).disabled(model.activeNotebooks.count <= 3)
                                .accessibilityLabel(booksCollapsed ? "展开全部笔记本" : "折叠笔记本，保留前三本")
                                .accessibilityIdentifier("toggle-sidebar-notebooks")
                            SidebarIconButton(icon: "plus", label: "新建笔记本") { model.newBookPresented = true }
                        }.padding(.trailing, 4).padding(.bottom, 4)
                        ForEach(sidebarBooks) { book in NotebookSidebarRow(book: book) }
                        if model.activeNotebooks.isEmpty {
                            Button { model.newBookPresented = true } label: { HStack(spacing: 8) { Image(systemName: "plus.circle"); Text("创建第一本笔记") }.font(.system(size: 11)).foregroundStyle(.secondary).padding(11).frame(maxWidth: .infinity, alignment: .leading) }.buttonStyle(SidebarButtonStyle())
                        }
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 0) {
                            Button { model.updateSettings { $0.sidebarConversationsCollapsed = !chatsCollapsed } } label: {
                                HStack(spacing: 6) { Text("最近对话"); disclosure(collapsed: chatsCollapsed); Spacer(minLength: 0) }
                                    .font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary).padding(.leading, 11).frame(maxWidth: .infinity, minHeight: 32).contentShape(Rectangle())
                            }.buttonStyle(SidebarButtonStyle()).accessibilityLabel(chatsCollapsed ? "展开最近对话" : "折叠最近对话").accessibilityIdentifier("toggle-sidebar-conversations")
                            Button { model.chooseDestination("conversations") } label: { Text("全部").font(.system(size: 10)).frame(width: 30, height: 30) }.buttonStyle(SidebarButtonStyle(selected: model.destination == "conversations")).accessibilityLabel("查看全部对话")
                            SidebarIconButton(icon: "square.and.pencil", label: "新建对话") { model.newConversation() }.help("新建对话")
                        }.padding(.trailing, 4).padding(.bottom, 4)
                        ForEach(SidebarContent.conversations(model.recentConversations, collapsed: chatsCollapsed)) { chat in ConversationSidebarRow(chat: chat) }
                        if !chatsCollapsed && model.recentConversations.isEmpty { Text("开始的讨论会保留在这里").font(.system(size: 10)).foregroundStyle(.tertiary).padding(11) }
                    }
                }.padding(.horizontal, 10).padding(.top, 18)
            }.scrollIndicators(.hidden)
            VStack(spacing: 4) {
                SidebarUtilities()
                HStack(spacing: 6) { Circle().fill(model.connectionStatus == "Codex 已连接" ? Theme.accent : .secondary).frame(width: 5, height: 5); Text(model.connectionStatus).font(.system(size: 9)); Spacer(); Text("本地资料库").font(.system(size: 9)) }.foregroundStyle(.tertiary).padding(.horizontal, 9).padding(.vertical, 7)
            }.padding(12)
        }.background(Theme.background)
            // Content and toast transitions must not animate the sidebar layout.
            .transaction { $0.animation = nil }
    }
    private func disclosure(collapsed: Bool) -> some View {
        Image(systemName: "chevron.down").font(.system(size: 8, weight: .semibold)).frame(width: 9, height: 9)
            .rotationEffect(.degrees(collapsed ? -90 : 0)).animation(disclosureMotion, value: collapsed)
    }
    private func nav(_ title: String, _ icon: String, _ value: String, count: Int? = nil) -> some View {
        let selected = model.destination == value
        return Button { model.chooseDestination(value) } label: {
            HStack(spacing: 10) {
                Image(systemName: icon).font(.system(size: 14)).foregroundStyle(selected ? Theme.accent : .secondary).frame(width: 20, height: 20)
                Text(title).lineLimit(1)
                Spacer(minLength: 0)
                if let count { Text("\(count)").font(.system(size: 10)).foregroundStyle(.secondary).monospacedDigit() }
            }.font(.system(size: 12, weight: .medium)).padding(.horizontal, 11)
                .frame(maxWidth: .infinity, minHeight: 40, maxHeight: 40, alignment: .leading).contentShape(Rectangle())
        }.buttonStyle(SidebarButtonStyle(selected: selected))
            .accessibilityAddTraits(selected ? [.isSelected] : [])
            .accessibilityIdentifier("nav-" + value)
    }
}
struct ConversationSidebarRow: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var center: ChoiceCenter
    let chat: Conversation
    @State private var hover = false
    private var menuID: String { "sidebar-chat-" + chat.id }
    private var active: Bool { model.destination == "chat" && model.conversationID == chat.id }
    private var expanded: Bool { center.presentation?.sourceID == menuID }
    var body: some View {
        HStack(spacing: 0) {
            Button { model.selectConversation(chat.id) } label: {
                HStack(spacing: 10) {
                    if model.runningConversationID == chat.id { ActivityIndicator(size: 12).frame(width: 20) }
                    else {
                        Image(systemName: model.queuePosition(chat.id) != nil ? "hourglass" : chat.pinned == true ? "pin.fill" : chat.state == "awaitingAnswers" ? "questionmark.bubble" : "bubble.left")
                            .font(.system(size: 12)).foregroundStyle(chat.state == "awaitingAnswers" ? Color.orange : active ? Theme.accent : .secondary).frame(width: 20)
                    }
                    Text(chat.title).font(.system(size: 11)).lineLimit(1)
                    Spacer(minLength: 0)
                    if model.unreadConversationIDs.contains(chat.id) { Circle().fill(Theme.accent).frame(width: 5, height: 5).accessibilityHidden(true) }
                }.padding(.leading, 11).padding(.trailing, 4)
                    .frame(maxWidth: .infinity, minHeight: 38, maxHeight: 38, alignment: .leading).contentShape(Rectangle())
            }.buttonStyle(SidebarRowButtonStyle()).accessibilityIdentifier("conversation-row-" + chat.id)
                .accessibilityValue(model.runningConversationID == chat.id ? "正在回复" : model.queuePosition(chat.id) != nil ? "已排队" : model.unreadConversationIDs.contains(chat.id) ? "有新进展" : active ? "当前对话" : "")
                .accessibilityAddTraits(active ? [.isSelected] : [])
            ConversationMenu(chat: chat, sourceID: menuID, sidebar: true).padding(.trailing, 4)
        }.frame(height: 38).contentShape(Rectangle())
            .background { SidebarSurface(selected: active, hovered: hover || expanded, secondary: true) }
            .onHover { hover = $0 }.onDisappear { hover = false }
    }
}
struct SidebarRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        // Keep the selected row's surface intact, even during a click.
        configuration.label.foregroundStyle(.primary)
            .background { SidebarPressSurface(pressed: configuration.isPressed) }
            .contentShape(Rectangle())
    }
}
private struct SidebarPressSurface: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduced
    let pressed: Bool
    var body: some View {
        RoundedRectangle(cornerRadius: 9).fill(Color.primary.opacity(pressed ? 0.018 : 0))
            .animation(nil, value: pressed)
            .allowsHitTesting(false).accessibilityHidden(true)
    }
}
struct NotebookSidebarRow: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var center: ChoiceCenter
    let book: Notebook
    @State private var hover = false
    private var menuID: String { "sidebar-book-" + book.id }
    private var active: Bool { model.destination == "book:" + book.id }
    private var expanded: Bool { center.presentation?.sourceID == menuID }
    var body: some View {
        HStack(spacing: 0) {
            Button { model.chooseDestination("book:" + book.id) } label: {
                HStack(spacing: 10) {
                    Image(systemName: "book.closed").font(.system(size: 14)).foregroundStyle(Theme.colors[abs(book.color % 5)]).frame(width: 20)
                    Text(book.title).font(.system(size: 12)).lineLimit(1)
                    Spacer(minLength: 0)
                    if book.pinned == true { Image(systemName: "pin.fill").font(.system(size: 8)).foregroundStyle(.secondary) }
                    Text("\(model.notes(in: book.id).count)").font(.system(size: 10)).foregroundStyle(.secondary).monospacedDigit()
                        .frame(minWidth: 14, alignment: .trailing).accessibilityHidden(true)
                }.padding(.leading, 11).padding(.trailing, 4).frame(maxWidth: .infinity, minHeight: 38, maxHeight: 38).contentShape(Rectangle())
            }.buttonStyle(SidebarRowButtonStyle()).accessibilityIdentifier("notebook-row-" + book.id)
                .accessibilityValue("\(model.notes(in: book.id).count) 篇笔记" + (active ? "，当前笔记本" : ""))
                .accessibilityAddTraits(active ? [.isSelected] : [])
            BookMenu(book: book, sourceID: menuID, sidebar: true).padding(.trailing, 4)
        }.frame(height: 38).contentShape(Rectangle())
            .background { SidebarSurface(selected: active, hovered: hover || expanded, secondary: true) }
            .onHover { hover = $0 }.onDisappear { hover = false }
            .modifier(BookContextActions(book: book, sourceID: menuID))
    }
}
struct ConversationMenu: View {
    @EnvironmentObject var model: AppModel
    let chat: Conversation
    var sourceID = ""
    var sidebar = false
    var body: some View {
        ActionMenu(title: sidebar ? "管理对话：\(chat.title)" : "管理对话", sourceID: sourceID, trailing: sidebar, size: sidebar ? 30 : 36, sidebar: sidebar, options: [
            ChoiceOption(id: "rename", title: "重命名", icon: "pencil"),
            ChoiceOption(id: "pin", title: chat.pinned == true ? "取消置顶" : "置顶对话", icon: "pin"),
            ChoiceOption(id: "fork", title: "从这里开始新对话", icon: "arrow.triangle.branch", disabled: model.isConversationBusy(chat.id), separatorBefore: true),
            ChoiceOption(id: "copy", title: "复制对话内容", icon: "doc.on.doc"),
            ChoiceOption(id: "export", title: "导出对话", icon: "square.and.arrow.up"),
            ChoiceOption(id: "delete", title: "移到回收站", icon: "trash", disabled: model.isConversationBusy(chat.id), destructive: true, separatorBefore: true)
        ]) { action in
            if action == "copy" { model.copyConversation(chat) }; if action == "export" { model.exportConversation(chat) }; if action == "fork" { model.forkConversation(chat) }
            if action == "rename" { model.renameConversationID = chat.id }
            if action == "pin" { model.pinConversation(chat.id) }
            if action == "delete" { model.deleteConversation(chat.id) }
        }
    }
}
struct NameSheet: View {
    @Environment(\.dismiss) var dismiss
    var title: String
    var subtitle: String
    var initial: String
    var placeholder: String
    var save: (String) -> Void
    @State private var text = ""
    @FocusState private var focused: Bool
    var body: some View { VStack(alignment: .leading, spacing: 19) { Text(title).font(.system(size: 21, weight: .semibold)); Text(subtitle).font(.system(size: 12)).foregroundStyle(.secondary); TextField(placeholder, text: $text).textFieldStyle(FieldStyle()).focused($focused).onSubmit { submit() }; HStack { Spacer(); ActionButton(title: "取消") { dismiss() }; ActionButton(title: "保存", primary: true) { submit() }.disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) } }.padding(30).frame(width: 430).background(Theme.panel).onAppear { text = initial; focused = true } }
    private func submit() { guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }; save(text); dismiss() }
}

struct StatusNotice: View {
    @EnvironmentObject var model: AppModel
    let text: String
    private var success: Bool { !text.contains("请") && !text.hasPrefix("当前") && (text.contains("已") || text.contains("成功") || text.contains("可在修改记录撤销")) }
    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: success ? "checkmark.circle.fill" : "info.circle").font(.system(size: 15)).foregroundStyle(Theme.accent)
            Text(text).font(.system(size: 12)).lineSpacing(3).fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, alignment: .leading)
            if text == "对话已移到回收站", let id = model.lastDeletedConversationID { Button("撤销") { model.restoreConversation(id) }.font(.system(size: 12, weight: .medium)).buttonStyle(FeedbackStyle(compact: true)) }
            QuietIconButton(icon: "xmark", label: "关闭提示", size: 28) { model.toast = nil }
        }.padding(.leading, 14).padding(.trailing, 5).padding(.vertical, 8).frame(maxWidth: 350, alignment: .leading)
            .background(Theme.panel, in: RoundedRectangle(cornerRadius: 12)).overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.border)).shadow(color: .black.opacity(0.12), radius: 15, y: 5)
            .accessibilityElement(children: .contain)
    }
}

private struct ToastLayer: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduced
    var body: some View {
        ZStack(alignment: .topTrailing) {
            if let text = model.toast { StatusNotice(text: text).transition(.opacity) }
        }.animation(reduced || model.library.settings.reduceMotion ? nil : .easeOut(duration: 0.14), value: model.toast)
    }
}
