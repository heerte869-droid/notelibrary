import SwiftUI
import AppKit

struct ChatView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.accessibilityReduceMotion) var reduced
    @State private var scrollState = ChatScrollState()
    @State private var scrollPosition = ScrollPosition(idType: String.self)
    @State private var userScrolling = false
    @State private var composerFocused = false
    @State private var editorHeight: CGFloat = 40
    @State private var commandIndex = 0
    @State private var contentWidth: CGFloat = 780
    @State private var composerFocusRequest = 0
    @State private var commandsHovered = false
    @State private var commandsDismissed = false
    @State private var searchIndex = 0
    @State private var searchedConversationID: String?
    private var searchQuery: String { LibrarySearch.query(model.conversationSearchQuery) }
    private var searchHits: [LibrarySearch.Hit] { chat.map { LibrarySearch.conversationHits($0, query: searchQuery) } ?? [] }
    private var commands: [ChatCommand] { ChatCommand.matches(model.composer) }
    private var showCommands: Bool { (composerFocused || commandsHovered) && !commandsDismissed && !commands.isEmpty && model.editingMessageID == nil }
    var chat: Conversation? { model.currentConversation }
    private var empty: Bool { chat?.messages.isEmpty != false }
    private var displayedMessages: [ChatMessage] {
        var messages = chat?.messages ?? []
        if model.isCurrentConversationRunning, model.currentAssistantVisible, !model.isCurrentCompacting, model.currentWorkingAction != "write", var pending = model.pendingResponse, !messages.contains(where: { $0.id == pending.id }) {
            pending.text = model.currentStreamText
            messages.append(pending)
        }
        return messages
    }
    private func isStreaming(_ message: ChatMessage) -> Bool { model.isCurrentConversationRunning && model.pendingResponse?.id == message.id && chat?.messages.contains(where: { $0.id == message.id }) != true }
    var motion: Animation? { reduced || model.library.settings.reduceMotion ? nil : .easeInOut(duration: 0.22) }
    private var selectedAI: AISelection { model.library.settings.selection(.conversation, conversation: chat) }
    private var modelChoices: [ChoiceOption] { AIModelChoices.conversationModels(provider: selectedAI.providerID, settings: model.library.settings, available: model.availableModels) }
    var codexSelected: Bool { selectedAI.providerID == "codex" }
    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(Theme.border).frame(height: 1)
            if !searchQuery.isEmpty {
                SearchMatchBar(query: searchQuery, index: searchIndex, count: searchHits.count, titleOnly: searchHits.isEmpty,
                    previous: { moveSearch(-1) }, next: { moveSearch(1) }, close: { model.conversationSearchQuery = "" })
            }
            backgroundReplyNotice
            HStack(spacing: 0) {
                GeometryReader { geometry in
                VStack(spacing: 0) {
                    if chat?.messages.isEmpty != false { welcome(height: geometry.size.height) }
                    else {
                        conversation
                        composer(width: contentWidth).padding(.horizontal, 24).padding(.top, 8).padding(.bottom, 14)
                    }
                }.onGeometryChange(for: Double.self) { _ in geometry.size.width } action: { width in
                    contentWidth = ChatLayout.contentWidth(available: width, mode: model.library.settings.chatLayout)
                }.onChange(of: model.library.settings.chatLayout) { _, mode in
                    contentWidth = ChatLayout.contentWidth(available: geometry.size.width, mode: mode)
                }
                }.frame(minWidth: 470, maxWidth: .infinity)

                if model.showPreview, let plan = model.previewPlan, !plan.notes.isEmpty { Rectangle().fill(Theme.border).frame(width: 1); PlanPreview(plan: plan).frame(width: 335).transition(.move(edge: .trailing).combined(with: .opacity)) }
            }
        }.environment(\.searchHighlightQuery, searchQuery).animation(motion, value: model.showPreview)
        .sheet(isPresented: $model.commandHelpPresented) { CommandHelpView() }
        .onChange(of: model.composer) { _, _ in commandIndex = 0; commandsDismissed = false }
        .onChange(of: chat?.id) { _, _ in commandsDismissed = false }
    }
    @ViewBuilder private var backgroundReplyNotice: some View {
        if let running = model.runningConversation, running.id != chat?.id {
            HStack(spacing: 8) {
                ActivityIndicator(size: 10)
                Text(model.compacting ? "后台整理上下文" : "后台回复中").font(.system(size: 11, weight: .medium))
                Text(running.title).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                Spacer(minLength: 8)
                Button("查看对话") { model.selectConversation(running.id) }
                    .font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.accent)
                    .buttonStyle(FeedbackStyle(compact: true)).accessibilityIdentifier("view-background-conversation")
            }.padding(.horizontal, 24).frame(height: 34)
                .background(Theme.accent.opacity(0.045))
                .accessibilityIdentifier("background-reply-notice")
        }
    }
    @ViewBuilder private var queuedReplyNotice: some View {
        if let id = chat?.id, let position = model.queuePosition(id) {
            HStack(spacing: 10) {
                Image(systemName: "hourglass").font(.system(size: 13)).foregroundStyle(Theme.accent)
                VStack(alignment: .leading, spacing: 4) {
                    Text("已排队 · 前面还有 \(position) 个回复").font(.system(size: 12, weight: .medium))
                    Text("轮到后自动回复，可以先查看其他对话。").font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Button("取消排队") { model.stop() }.font(.system(size: 11)).buttonStyle(FeedbackStyle(compact: true))
            }.padding(12).background(Theme.secondary.opacity(0.6), in: RoundedRectangle(cornerRadius: 11))
                .accessibilityIdentifier("queued-reply-notice")
        }
    }
    private var sendLabel: String {
        if model.isCurrentConversationRunning { return "停止回复" }
        if model.isCurrentConversationBusy { return "取消排队" }
        return model.isRunning ? "排队发送" : "发送消息"
    }
    private var sendHelp: String {
        if model.isCurrentConversationBusy { return sendLabel }
        if model.isRunning { return "加入队列，当前回复完成后自动处理" }
        return model.library.settings.enterSends ? "Enter 发送 · Shift Enter 换行" : "⌘ Enter 发送 · Enter 换行"
    }
    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                HighlightedText(chat?.hasStarted == true ? chat?.title ?? "AI 对话" : "AI 对话").font(.system(size: 14, weight: .semibold)).lineLimit(1)
                HStack(spacing: 8) { Circle().fill(model.connectionStatus == "Codex 已连接" ? Theme.accent : .secondary).frame(width: 5, height: 5); Text(model.isCurrentCompacting ? "正在压缩上下文" : model.isCurrentConversationRunning ? (model.currentWorkingAction == "write" ? "正在编排笔记" : model.currentWorkingAction == "search" ? "正在查找笔记" : "正在回复") : model.isCurrentConversationBusy ? "已排队，轮到后自动回复" : "查找笔记、理解知识，也能一起整理").font(.system(size: 10)).foregroundStyle(.secondary) }
            }
            Spacer(minLength: 10)
            ChoicePicker(title: modelChoices.isEmpty ? "待添加模型" : "选择对话模型", selection: selectedAI.id,
                         options: modelChoices,
                         width: 180, menuSize: CGSize(width: 280, height: 380),
                         searchable: modelChoices.count > 9) { value in
                if let selection = AISelection(id: value) { model.setAISelection(selection) }
            }.disabled(model.isCurrentConversationBusy || modelChoices.isEmpty)
            ActionMenu(title: "聊天布局", icon: "rectangle.split.2x1", selection: model.library.settings.chatLayout ?? "comfortable", options: [ChoiceOption(id: "comfortable", title: "舒适阅读", subtitle: "收拢正文，适合长文", icon: "text.alignleft"), ChoiceOption(id: "wide", title: "宽屏布局", subtitle: "随窗口加宽，消息与输入框对齐", icon: "arrow.left.and.right")]) { value in model.updateSettings { $0.chatLayout = value } }
            Button { model.contextPresented = true } label: { HStack(spacing: 5) { if model.isCurrentCompacting { ActivityIndicator(size: 11) } else { Image(systemName: "circle.dotted.circle").font(.system(size: 13)) }; Text(chat?.memory == nil ? "上下文" : "已压缩").font(.system(size: 10)) }.foregroundStyle(Theme.accent).padding(8) }.buttonStyle(FeedbackStyle(compact: true)).accessibilityLabel("上下文与记忆")
            if model.previewPlan?.notes.isEmpty == false { QuietIconButton(icon: "rectangle.righthalf.inset.filled", label: "切换笔记预览") { model.showPreview.toggle() } }
            if let chat, chat.hasStarted { ConversationMenu(chat: chat) }
            QuietIconButton(icon: "square.and.pencil", label: "新对话") { model.newConversation() }
        }.padding(.horizontal, 24).padding(.vertical, 16)
    }
    private func welcome(height: CGFloat) -> some View {
        ScrollView {
            VStack(spacing: 22) {
                VStack(spacing: 11) {
                    HStack(spacing: 11) { Avatar(size: 34); Text("今天想一起探索什么？").font(.system(size: 25, weight: .semibold)) }
                    Text("查找已有知识，讨论一个问题，或整理新的笔记。").font(.system(size: 12)).foregroundStyle(.secondary)
                }
                composer(width: min(contentWidth, 760)).zIndex(2)
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    starter("整理课堂笔记", "从文档或图片开始，按章节收好", "doc.on.doc") { model.chooseSources() }
                    starter("补充已有内容", "接着上次的笔记继续", "text.badge.plus") { model.composer = "我想补充已有笔记本中的内容："; composerFocusRequest += 1 }
                    starter("查找与总结", "找到相关笔记，带着原文一起理解", "doc.text.magnifyingglass") { model.composer = "帮我查找相关笔记并总结："; composerFocusRequest += 1 }
                    starter("校对与完善", "核对原稿，找出疑点", "checkmark.shield") { model.composer = "请帮我检查笔记中可能的错误："; composerFocusRequest += 1 }
                }.frame(maxWidth: min(contentWidth, 760))
                if let previous = model.resumableConversation {
                    Button { model.resumeConversation(previous.id); composerFocusRequest += 1 } label: {
                        HStack(spacing: 7) { Image(systemName: "clock.arrow.circlepath"); Text("继续上次对话 · " + previous.title).lineLimit(1); Image(systemName: "arrow.right").font(.system(size: 9)) }.font(.system(size: 11)).foregroundStyle(.secondary).padding(.horizontal, 10).frame(height: 30)
                    }.buttonStyle(FeedbackStyle(compact: true)).frame(maxWidth: min(contentWidth, 760))
                        .help("打开原来的对话和消息，当前草稿会保留")
                        .accessibilityIdentifier("resume-previous-conversation")
                }
            }.padding(.horizontal, 24).padding(.vertical, 30).frame(maxWidth: .infinity, minHeight: height, alignment: .center)
        }.scrollIndicators(.hidden)
    }
    private func starter(_ title: String, _ detail: String, _ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 11) {
                Image(systemName: icon).font(.system(size: 16, weight: .regular)).foregroundStyle(Theme.accent).frame(width: 32, height: 32).background(Theme.accent.opacity(0.07), in: RoundedRectangle(cornerRadius: 9))
                VStack(alignment: .leading, spacing: 4) { Text(title).font(.system(size: 12, weight: .medium)); Text(detail).font(.system(size: 10)).foregroundStyle(.secondary) }
                Spacer(minLength: 0)
                Image(systemName: "arrow.up.left").font(.system(size: 9)).foregroundStyle(.tertiary)
            }.padding(.horizontal, 13).frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
        }.buttonStyle(FeedbackStyle()).background(Theme.secondary.opacity(0.7), in: RoundedRectangle(cornerRadius: 12)).overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.border.opacity(0.7)))
    }
    private var conversation: some View {
        ScrollViewReader { searchProxy in
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ForEach(displayedMessages) { message in
                    MessageRow(message: message, streaming: isStreaming(message), latest: message.id == displayedMessages.last?.id, editable: message.id == model.latestUserMessageID).id(message.id).transition(.opacity)
                    if let events = message.events, let _ = message.receiptID, !events.isEmpty { ExecutionCard(events: events, state: "completed", writing: true, initiallyExpanded: false) }
                    if let receiptID = message.receiptID, let receipt = model.library.receipts.first(where: { $0.id == receiptID }) { SavedCard(receipt: receipt) }
                }
                queuedReplyNotice
                if model.isCurrentCompacting { CompactStatusCard() }
                if let notice = model.contextNotice, !model.isCurrentCompacting {
                    HStack(spacing: 8) { Image(systemName: "circle.dotted.circle").foregroundStyle(Theme.accent); Text(notice).font(.system(size: 11)).foregroundStyle(.secondary); Spacer(); Button("查看") { model.contextPresented = true }.buttonStyle(FeedbackStyle(compact: true)) }.padding(12).background(Theme.secondary.opacity(0.55), in: RoundedRectangle(cornerRadius: 11))
                }

                if let chat, (!model.isCurrentConversationRunning || model.currentAssistantVisible), !chat.events.isEmpty, chat.operationKind == "write" || model.currentWorkingAction == "write" || chat.events.contains(where: { ["识别原稿", "查阅参考资料", "生成图示"].contains($0.title) }) { ExecutionCard(events: chat.events, state: chat.state, writing: chat.operationKind == "write" || model.currentWorkingAction == "write") }
                if let chat, chat.state == "awaitingAnswers" { QuestionsCard(chat: chat).transition(.opacity) }
                if let receiptID = chat?.receiptID, let receipt = model.library.receipts.first(where: { $0.id == receiptID }) { SavedCard(receipt: receipt) }
                if let chat, ["failed", "cancelled", "interrupted"].contains(chat.state) {
                    VStack(alignment: .leading, spacing: 10) { Label(chat.state == "cancelled" ? "已停止" : "这次回复尚未完成", systemImage: "pause.circle").font(.system(size: 12, weight: .medium)); Text(chat.lastError ?? "材料与对话已保留，可以继续。").font(.system(size: 11)).foregroundStyle(.secondary).textSelection(.enabled); HStack { ActionButton(title: "重新生成", icon: "arrow.clockwise") { model.retry() }.disabled(model.isCurrentConversationBusy); if chat.editBackup != nil { ActionButton(title: "恢复上一版对话", icon: "arrow.uturn.backward") { model.restoreEditedTurn() }.disabled(model.isCurrentConversationBusy) } } }.padding(17).frame(maxWidth: .infinity, alignment: .leading).background(Theme.background, in: RoundedRectangle(cornerRadius: 12))
                }
                Color.clear.frame(height: 4).accessibilityHidden(true)
            }.frame(maxWidth: contentWidth).padding(.horizontal, 24).padding(.top, 24).padding(.bottom, 10).frame(maxWidth: .infinity)
        }
        .scrollPosition($scrollPosition)
        .defaultScrollAnchor(searchQuery.isEmpty ? .bottom : .top, for: .initialOffset)
        .defaultScrollAnchor(scrollState.followsLatest ? .bottom : nil, for: .sizeChanges)
        .onScrollPhaseChange { _, phase, context in
            userScrolling = phase == .tracking || phase == .interacting || phase == .decelerating
            if userScrolling {
                scrollState.observe(distanceToBottom: context.geometry.contentSize.height - context.geometry.visibleRect.maxY, userDriven: true)
            }
        }
        .onScrollGeometryChange(for: ChatScrollGeometry.self) { geometry in
            ChatScrollGeometry(height: geometry.contentSize.height, viewport: geometry.containerSize.height, distanceToBottom: geometry.contentSize.height - geometry.visibleRect.maxY)
        } action: { previous, current in
            let stableLayout = current.height == previous.height && current.viewport == previous.viewport
            // Content growth must not be mistaken for the reader scrolling away.
            let userMoved = stableLayout && scrollPosition.isPositionedByUser && current.distanceToBottom != previous.distanceToBottom
            scrollState.observe(distanceToBottom: current.distanceToBottom, userDriven: userScrolling || userMoved)
            if searchQuery.isEmpty && scrollState.followsLatest && !userScrolling && (current.height != previous.height || current.viewport != previous.viewport) {
                followAfterLayout()
            }
        }
        .task(id: (chat?.id ?? "") + "|" + searchQuery) {
            let selectedID = chat?.id
            // Ending the highlight keeps the passage on screen. A new chat
            // still opens at the latest message unless entered from search.
            if searchQuery.isEmpty && searchedConversationID == selectedID { searchedConversationID = nil; return }
            scrollState = ChatScrollState(); userScrolling = false; searchIndex = 0
            if !searchHits.isEmpty {
                searchedConversationID = selectedID
                scrollState.observe(distanceToBottom: 100, userDriven: true)
                do { try await Task.sleep(for: .milliseconds(140)) } catch { return }
            } else { await Task.yield() }
            guard !Task.isCancelled, selectedID == chat?.id else { return }
            if let hit = searchHits.first {
                searchProxy.scrollTo(hit.id, anchor: .top)
            } else if let back = model.referenceReturn, back.conversationID == chat?.id, chat?.messages.contains(where: { $0.id == back.messageID }) == true {
                scrollState.observe(distanceToBottom: 100, userDriven: true)
                scrollPosition.scrollTo(id: back.messageID, anchor: .top)
                model.referenceReturn = nil
            } else { scrollPosition.scrollTo(edge: .bottom) }
        }
        .onChange(of: model.scrollToLatestRequest) { _, _ in goToLatest() }
        .onChange(of: model.currentAssistantVisible) { _, _ in followAfterLayout() }
        .onChange(of: chat?.messages.last?.id) { _, _ in followAfterLayout() }
        .onChange(of: model.currentStreamText) { _, _ in followAfterLayout() }
        .onChange(of: chat?.state) { _, _ in followAfterLayout() }
        .overlay(alignment: .bottom) {
            if !scrollState.atBottom {
                QuietIconButton(icon: "arrow.down", label: "回到最新消息", size: 36) { goToLatest() }
                    .background(Theme.panel, in: Circle())
                    .overlay(Circle().stroke(Theme.border).allowsHitTesting(false))
                    .shadow(color: .black.opacity(0.12), radius: 9, y: 3).padding(.bottom, 12)
            }
        }
        .onChange(of: searchIndex) { _, index in
            guard searchHits.indices.contains(index) else { return }
            withAnimation(motion) { searchProxy.scrollTo(searchHits[index].id, anchor: .top) }
        }
        .accessibilityIdentifier("conversation-timeline")
        }
    }
    private func moveSearch(_ offset: Int) {
        guard !searchHits.isEmpty else { return }
        searchIndex = (searchIndex + offset + searchHits.count) % searchHits.count
        scrollState.observe(distanceToBottom: 100, userDriven: true); userScrolling = false

    }
    private func goToLatest() {
        model.conversationSearchQuery = ""
        scrollState.resume(); userScrolling = false
        var transaction = Transaction(); transaction.disablesAnimations = true
        withTransaction(transaction) { scrollPosition = ScrollPosition(edge: .bottom) }
        followAfterLayout()
    }
    private func followAfterLayout(animated: Bool = false) {
        let id = chat?.id
        Task { @MainActor in
            await Task.yield()
            guard searchQuery.isEmpty, chat?.id == id, scrollState.followsLatest, !userScrolling else { return }
            withAnimation(animated ? motion : nil) { scrollPosition.scrollTo(edge: .bottom) }
        }
    }
    private func composer(width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            if !model.attachments.isEmpty {
                ScrollView(.horizontal) { HStack(spacing: 8) { ForEach(model.attachments, id: \.self) { SourceAttachmentCard(id: $0, removable: true) } } }.scrollIndicators(.hidden).frame(height: 54)
            }
            if model.isImportingCurrentConversation, let status = model.importStatus {
                HStack(spacing: 8) {
                    ActivityIndicator(size: 11)
                    Text(status).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                    Spacer(minLength: 8)
                    Button("取消") { model.cancelImport() }.font(.system(size: 10)).buttonStyle(FeedbackStyle(compact: true))
                }.padding(.horizontal, 5).frame(height: 25).accessibilityIdentifier("source-import-progress")
            }
            ComposerEditor(text: $model.composer, height: $editorHeight, enterSends: model.library.settings.enterSends, onSend: { sendFromComposer() }, onImagePaste: { model.pasteImage() }, onFocusChange: { composerFocused = $0 }, minimumHeight: 40, focusRequest: composerFocusRequest, onKey: handleCommandKey).frame(height: editorHeight).disabled(model.editingMessageID != nil)
            HStack(spacing: 5) {
                QuietIconButton(icon: "plus", label: "添加学习资料") { model.chooseSources() }
                QuietIconButton(icon: "doc.on.clipboard", label: "粘贴图片") { model.pasteImage() }
                if !model.activeNotebooks.isEmpty { ChoicePicker(title: "笔记本范围", selection: chat?.notebookID ?? "auto", options: [ChoiceOption(id: "auto", title: "全部笔记", subtitle: "查找所有未归档笔记；保存时按内容归类", icon: "tray")] + model.activeNotebooks.map { ChoiceOption(id: $0.id, title: $0.title, icon: "book.closed") }, width: 158, menuSize: CGSize(width: 292, height: 320), searchable: true) { model.scopeConversation($0 == "auto" ? nil : $0) }.disabled(model.isCurrentConversationBusy) }
                Spacer()
                Button { if model.composer.isEmpty { model.composer = "/"; commandsDismissed = false; composerFocusRequest += 1 } else { model.commandHelpPresented = true } } label: { Text("/ 命令").font(.system(size: 10)).padding(.horizontal, 8).frame(height: 32) }.buttonStyle(FeedbackStyle(compact: true)).foregroundStyle(.secondary).help("输入 / 使用快捷命令")
                if !model.composer.isEmpty { Text("\(model.composer.count)").font(.system(size: 9)).monospacedDigit().foregroundStyle(.tertiary).padding(.trailing, 5) }
                Button { if model.isCurrentConversationBusy { model.stop() } else { sendFromComposer() } } label: {
                    Image(systemName: model.isCurrentConversationRunning ? "stop.fill" : model.isCurrentConversationBusy ? "xmark" : "arrow.up")
                        .font(.system(size: model.isCurrentConversationBusy ? 11 : 16, weight: .semibold))
                        .frame(width: 34, height: 34)
                }.buttonStyle(FeedbackStyle(prominent: true, compact: true)).clipShape(Circle())
                    .disabled(model.editingMessageID != nil || (!model.isCurrentConversationBusy && !canSend))
                    .accessibilityLabel(sendLabel).accessibilityIdentifier("send-message").help(sendHelp)
            }
        }.padding(14)
            .background {
                RoundedRectangle(cornerRadius: 18).fill(Theme.composer)
                    .overlay(RoundedRectangle(cornerRadius: 18).stroke(composerFocused ? Theme.accent.opacity(0.52) : Theme.composerBorder, lineWidth: 1))
                    .shadow(color: .black.opacity(composerFocused ? 0.10 : 0.065), radius: 13, y: 4)
                    .animation(reduced || model.library.settings.reduceMotion ? nil : .easeOut(duration: 0.10), value: composerFocused)
                    .allowsHitTesting(false)
            }
            .frame(maxWidth: width)
            .overlay(alignment: empty ? .bottomLeading : .topLeading) {
                if showCommands {
                    CommandPalette(commands: commands, selected: commandIndex, visibleRows: empty ? 3 : 5) { command in
                        if model.executeCommand(command) { commandsDismissed = true }
                    }.fixedSize(horizontal: false, vertical: true).onHover { commandsHovered = $0 }.offset(y: (empty ? 1 : -1) * (46 + CGFloat(min(commands.count, empty ? 3 : 5)) * 57 + 8))
                }
            }
            .frame(maxWidth: .infinity)
    }
    private func sendFromComposer() {
        if !commandsDismissed, model.editingMessageID == nil, commands.indices.contains(commandIndex) {
            if model.executeCommand(commands[commandIndex]) { commandsDismissed = true }
        } else { model.send(); composerFocusRequest += 1 }
    }
    private func handleCommandKey(_ key: UInt16) -> Bool {
        guard showCommands else { return false }
        switch key {
        case 125: commandIndex = min(commands.count - 1, commandIndex + 1)
        case 126: commandIndex = max(0, commandIndex - 1)
        case 36, 48: sendFromComposer()
        case 53: commandsDismissed = true
        default: return false
        }
        return true
    }
    private var canSend: Bool { !model.isImportingCurrentConversation && (!model.composer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !model.attachments.isEmpty) }
}
private struct ChatScrollGeometry: Equatable { var height: CGFloat; var viewport: CGFloat; var distanceToBottom: CGFloat }
struct MessageRow: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.searchHighlightQuery) private var searchQuery
    let message: ChatMessage
    var streaming = false
    var latest = false
    var editable = false
    @State private var hover = false
    @State private var expandedSources = false
    var user: Bool { message.role == "user" }
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if user { Spacer(minLength: 32) } else { Avatar(size: 28) }
            VStack(alignment: user ? .trailing : .leading, spacing: 7) {
                if !user {
                    HStack(spacing: 8) {
                        Text("NoteLibrary").font(.system(size: 12, weight: .semibold))
                        if model.library.settings.showMessageTime != false { Text(message.date, style: .time).font(.system(size: 9)).foregroundStyle(.tertiary) }
                    }.foregroundStyle(.secondary)
                }
                if model.editingMessageID == message.id { InlineMessageEditor(message: message) }
                else {
                VStack(alignment: .leading, spacing: 10) {
                    if !user, !message.assetIDs.isEmpty {
                        ForEach(message.assetIDs, id: \.self) { id in
                            if let asset = model.asset(id), asset.isImage, let url = model.assetURL(id) {
                                Button { model.selectedSourceID = id } label: {
                                    SourceImageView(url: url, revision: asset.digest, maxPixelSize: 1000)
                                        .frame(maxWidth: 420).frame(height: 320)
                                        .background(Theme.secondary, in: RoundedRectangle(cornerRadius: 12))
                                        .clipShape(RoundedRectangle(cornerRadius: 12))
                                        .contentShape(RoundedRectangle(cornerRadius: 12))
                                }.buttonStyle(FeedbackStyle()).accessibilityLabel("查看生成图片").help("查看图片")
                            } else { SourceAttachmentCard(id: id) }
                        }
                    } else if !message.assetIDs.isEmpty {
                        ScrollView(.horizontal) { HStack(spacing: 8) { ForEach(message.assetIDs, id: \.self) { id in
                            if model.asset(id)?.isImage == true, let url = model.assetURL(id) { Button { model.selectedSourceID = id } label: { SourceImageView(url: url, revision: model.asset(id)?.digest ?? "", maxPixelSize: 360).frame(width: 170, height: 135).clipShape(RoundedRectangle(cornerRadius: 8)) }.buttonStyle(FeedbackStyle()) } else { SourceAttachmentCard(id: id) }
                        } } }.scrollIndicators(.hidden)
                    }
                    if !message.text.isEmpty {
                        if !streaming, !searchQuery.isEmpty { SearchMessageText(message: message) }
                        else if !user, !streaming, !(message.noteReferences ?? []).isEmpty { CitationAnswerText(message: message) }
                        else { Text(.init(message.text)).font(.system(size: 15)).lineSpacing(5).textSelection(.enabled).fixedSize(horizontal: false, vertical: true) }
                    }
                    if !user, !streaming, let references = message.noteReferences, !references.isEmpty { NoteReferencesView(references: references, messageID: message.id) }
                    if !user, !streaming, let sources = message.webSources, !sources.isEmpty {
                        VStack(alignment: .leading, spacing: 7) {
                            HStack(spacing: 12) {
                                Text("网页来源").font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                                if sources.count > 3 {
                                    Button(expandedSources ? "收起" : "全部 \(sources.count) 个") { expandedSources.toggle() }
                                        .font(.system(size: 11)).buttonStyle(FeedbackStyle(compact: true)).foregroundStyle(Theme.accent)
                                }
                            }
                            ForEach(expandedSources ? sources : Array(sources.prefix(3))) { source in
                                if let url = URL(string: source.url) {
                                    Link(destination: url) {
                                        HStack(alignment: .firstTextBaseline, spacing: 7) {
                                            Image(systemName: "arrow.up.right").font(.system(size: 10))
                                            Text(source.title).lineLimit(2).multilineTextAlignment(.leading)
                                        }.font(.system(size: 12)).foregroundStyle(Theme.accent)
                                    }.buttonStyle(FeedbackStyle(compact: true)).help(source.url)
                                }
                            }
                        }.padding(.top, 5)
                    }
                    if streaming {
                        if message.text.isEmpty {
                            TimelineView(.periodic(from: message.date, by: 1)) { timeline in
                                HStack(spacing: 9) {
                                    ActivityIndicator(size: 12)
                                    Text(ReplyActivity.title(events: model.currentConversation?.events ?? [], action: model.currentWorkingAction)).lineLimit(1)
                                    Text(ReplyActivity.elapsed(from: message.date, now: timeline.date)).monospacedDigit().foregroundStyle(.tertiary)
                                }.font(.system(size: 12)).foregroundStyle(.secondary).frame(height: 24)
                                    .accessibilityIdentifier("reply-waiting-status")
                                    .help("显示实际处理阶段和已用时间；可随时用输入框右侧的停止按钮中止。")
                            }
                        } else { ResponseCursor() }
                    }
                }.padding(.horizontal, user ? 15 : 0).padding(.vertical, user ? 11 : 0)
                    .background(user ? Theme.secondary : .clear, in: RoundedRectangle(cornerRadius: 15))
                }
                if !streaming && model.editingMessageID != message.id {
                    HStack(spacing: 2) {
                        if user && model.library.settings.showMessageTime != false { Text(message.date, style: .time).font(.system(size: 9)).foregroundStyle(.tertiary).padding(.trailing, 5) }
                        QuietIconButton(icon: "doc.on.doc", label: "复制消息", size: 30) { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(message.copyText, forType: .string); model.toast = "已复制消息" }
                        if user && editable { QuietIconButton(icon: "pencil", label: "重新编辑最新消息", size: 34) { model.beginMessageEdit(message.id) }.disabled(model.isCurrentConversationBusy) }
                    }.foregroundStyle(.secondary).opacity(hover || latest ? 1 : 0.55)
                }
            }.frame(maxWidth: user ? (model.editingMessageID == message.id ? min(620, max(360, CGFloat(message.text.count) * 7 + 70)) : 760) : .infinity, alignment: user ? .trailing : .leading)
            if !user { Spacer(minLength: 4) }
        }.frame(maxWidth: .infinity, alignment: user ? .trailing : .leading)
            .onHover { hover = $0 }
            .onDisappear { hover = false }
    }
}
struct ResponseCursor: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.accessibilityReduceMotion) var reduced
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 15, paused: reduced || model.library.settings.reduceMotion)) { timeline in
            let opacity = reduced || model.library.settings.reduceMotion ? 0.65 : 0.35 + 0.45 * (sin(timeline.date.timeIntervalSinceReferenceDate * 4) + 1) / 2
            RoundedRectangle(cornerRadius: 1).fill(Color.secondary.opacity(opacity)).frame(width: 3, height: 14)
        }.frame(height: 20).accessibilityLabel("正在回复")
    }
}

struct ExecutionCard: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.accessibilityReduceMotion) var reduced
    var events: [OperationEvent]
    var state: String?
    var writing: Bool
    @State private var expanded: Bool
    init(events: [OperationEvent], state: String? = nil, writing: Bool = false, initiallyExpanded: Bool = true) {
        self.events = events; self.state = state; self.writing = writing
        _expanded = State(initialValue: initiallyExpanded)
    }
    var body: some View {
        let progress = OperationProgress(events: events, state: state, writing: writing)
        VStack(alignment: .leading, spacing: 18) {
            Button {
                withAnimation(reduced || model.library.settings.reduceMotion ? nil : .easeInOut(duration: 0.18)) { expanded.toggle() }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "list.bullet.clipboard").foregroundStyle(Theme.accent).frame(width: 18, height: 18)
                    Text(progress.title).font(.system(size: 12, weight: .semibold))
                    Spacer()
                    Image(systemName: "chevron.down").font(.system(size: 9, weight: .medium))
                        .frame(width: 12, height: 12).rotationEffect(.degrees(expanded ? 180 : 0))
                }.padding(3).contentShape(Rectangle())
            }.buttonStyle(FeedbackStyle(compact: true))
                .accessibilityLabel(progress.title).accessibilityValue(expanded ? "已展开" : "已收起")
                .accessibilityIdentifier("execution-progress-toggle")
            if expanded {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(progress.steps.enumerated()), id: \.element.id) { index, step in
                        progressRow(step, number: index + 1, last: index == progress.steps.count - 1)
                    }
                }.padding(.horizontal, 3).transition(.opacity)
            }
        }.padding(15).background(Theme.background, in: RoundedRectangle(cornerRadius: 13))
            .overlay(RoundedRectangle(cornerRadius: 13).stroke(Theme.border))
    }
    private func progressRow(_ step: OperationProgress.Step, number: Int, last: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 5) {
                Group {
                    switch step.status {
                    case .running: ActivityIndicator(size: 16)
                    case .completed: Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.accent)
                    case .failed: Image(systemName: "exclamationmark.circle").foregroundStyle(Color.red)
                    case .interrupted: Image(systemName: "pause.circle").foregroundStyle(.secondary)
                    case .pending:
                        Text(String(number)).font(.system(size: 9, weight: .medium)).foregroundStyle(.secondary)
                            .frame(width: 16, height: 16).overlay(Circle().stroke(Theme.border))
                    }
                }.font(.system(size: 15)).frame(width: 18, height: 18)
                if !last { Capsule().fill(step.status == .completed ? Theme.accent.opacity(0.24) : Theme.border).frame(width: 1, height: 29) }
            }.frame(width: 18).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                Text(step.title).font(.system(size: 12, weight: step.status == .running ? .semibold : .medium))
                    .foregroundStyle(step.status == .pending ? Color.secondary : Color.primary)
                if !step.detail.isEmpty {
                    Text(step.detail).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1).help(step.detail)
                }
            }.padding(.top, 1)
            Spacer(minLength: 0)
        }.frame(minHeight: last ? 34 : 56, alignment: .top)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("第 \(number) 步，\(step.title)，\(step.accessibilityStatus)" + (step.detail.isEmpty ? "" : "，" + step.detail))
            .accessibilityIdentifier("execution-step-" + step.stage.rawValue)
    }
}
struct SavedCard: View {
    @EnvironmentObject var model: AppModel
    let receipt: ChangeReceipt
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(receipt.undone ? "本次整理已撤销" : "已自动保存", systemImage: receipt.undone ? "arrow.uturn.backward.circle" : "checkmark.circle.fill").font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.accent)
            ForEach(receipt.changes, id: \.after.id) { change in
                Button { if let note = model.library.notes.first(where: { $0.id == change.after.id }) { model.openNote(note) } } label: { HStack { Image(systemName: "doc.text"); VStack(alignment: .leading, spacing: 3) { Text(change.after.title); Text(model.location(change.after)).font(.caption).foregroundStyle(.secondary) }; Spacer(); Image(systemName: "arrow.up.right").font(.caption) } }.buttonStyle(FeedbackStyle()).disabled(receipt.undone)
            }
            if !receipt.undone { Button("撤销本次整理") { model.undo(receipt.id) }.font(.caption).buttonStyle(FeedbackStyle(compact: true)) }
        }.padding(17).background(Theme.accent.opacity(0.06), in: RoundedRectangle(cornerRadius: 13))
    }
}

struct PlanPreview: View {
    @EnvironmentObject var model: AppModel
    var plan: AIPlan
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack { Text("笔记预览").font(.system(size: 13, weight: .medium)); Spacer(); QuietIconButton(icon: "xmark", label: "收起预览") { model.showPreview = false } }.padding(16)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 23) {
                    ForEach(Array(plan.notes.enumerated()), id: \.offset) { _, note in
                        VStack(alignment: .leading, spacing: 14) {
                            Text(note.notebookTitle + " / " + note.chapterTitle).font(.caption).foregroundStyle(.secondary)
                            Text(note.title).font(.title2.weight(.semibold))
                            ForEach(Array(note.blocks.enumerated()), id: \.offset) { _, block in
                                let saved = model.library.notes.first { $0.id == note.noteID || ($0.title == note.title && $0.blocks.contains { $0.text == block.text }) }
                                let assetID = block.sourceAssetID ?? saved?.blocks.first { $0.id == block.id || ($0.kind.rawValue == block.kind && $0.text == block.text) }?.assetID
                                if block.kind == "image", assetID == nil { Label("图示正在准备", systemImage: "photo").font(.caption).foregroundStyle(.secondary) }
                                else { ContentBlockView(block: ContentBlock(kind: BlockKind(rawValue: block.kind) ?? .paragraph, text: block.text, detail: block.detail, rows: block.rows, assetID: assetID, diagram: block.diagram, origin: block.origin, citations: block.citations, reviewQuestion: block.reviewQuestion), fontSize: 14, spacing: 5) }
                            }
                        }
                    }
                }.padding(24)
            }
        }.background(Theme.background)
    }
}
