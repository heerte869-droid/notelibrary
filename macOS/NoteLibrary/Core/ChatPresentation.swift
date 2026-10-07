import Foundation

struct QueuedReply {
    let conversationID: String
    let function: AIFunction
    let settings: AppSettings
    let selectedNoteID: String?
}

struct ChatScrollState {
    private(set) var followsLatest = true
    private(set) var atBottom = true

    mutating func observe(distanceToBottom: Double, userDriven: Bool) {
        atBottom = distanceToBottom <= 60
        if userDriven { followsLatest = atBottom }
    }

    mutating func resume() { followsLatest = true }
}

@MainActor final class AssistantPresentation {
    private var task: Task<Void, Error>?
    private var generation = 0

    func begin(reveal: @escaping () -> Void) {
        cancel()
        let token = generation
        task = Task {
            await Task.yield()
            try Task.checkCancellation()
            guard token == generation else { return }
            reveal()
        }
    }

    func waitUntilVisible() async throws { try await task?.value }
    func cancel() { generation += 1; task?.cancel(); task = nil }
}

// Collapse limits are independent: notebooks keep the first three, chats keep no rows.
enum SidebarContent {
    static func notebooks(_ books: [Notebook], collapsed: Bool) -> [Notebook] {
        let visible = books.filter(LibraryScope.active).sorted {
            if ($0.pinned == true) != ($1.pinned == true) { return $0.pinned == true }
            return $0.createdAt == $1.createdAt ? $0.id < $1.id : $0.createdAt < $1.createdAt
        }
        return collapsed ? Array(visible.prefix(3)) : visible
    }
    static func conversations(_ chats: [Conversation], collapsed: Bool) -> [Conversation] {
        collapsed ? [] : Array(chats.filter { $0.deletedAt == nil && $0.hasStarted }.prefix(8))
    }
}

// Drafts are recoverable without becoming history. Compare the complete payload,
// excluding only identity, autosave time and the old automatically generated title.
enum ConversationDrafts {
    static func equivalent(_ lhs: Conversation, _ rhs: Conversation) -> Bool {
        guard !lhs.hasStarted, !rhs.hasStarted, lhs.deletedAt == nil, rhs.deletedAt == nil else { return false }
        var a = lhs, b = rhs
        a.id = ""; b.id = ""; a.updatedAt = .distantPast; b.updatedAt = .distantPast
        if a.userNamed != true { a.title = "新对话" }
        if b.userNamed != true { b.title = "新对话" }
        a.draftAssetIDs = a.draftAssetIDs ?? []; b.draftAssetIDs = b.draftAssetIDs ?? []
        return a == b
    }
    static func mergingDuplicates(_ conversations: [Conversation]) -> [Conversation] {
        var kept: [Conversation] = []
        var redundant = Set<String>()
        for chat in conversations.sorted(by: { $0.updatedAt > $1.updatedAt }) where chat.deletedAt == nil && !chat.hasStarted {
            if kept.contains(where: { equivalent($0, chat) }) { redundant.insert(chat.id) }
            else { kept.append(chat) }
        }
        return conversations.filter { !redundant.contains($0.id) }
    }
}

// A replaced turn stays recoverable until its new response has been saved.
struct ConversationTurnBackup: Codable, Equatable {
    var messages: [ChatMessage]
    var events: [OperationEvent]
    var questions: [AIQuestion]
    var answers: [String: String]
    var pendingAssetIDs: [String]
    var planJSON: String?
    var taskID: String?
    var receiptID: String?
    var state: String
    var memory: ConversationMemory?
    var operationKind: String?
    var lastError: String?
    var title: String
    init(_ chat: Conversation) {
        messages = chat.messages; events = chat.events; questions = chat.questions; answers = chat.answers
        pendingAssetIDs = chat.pendingAssetIDs; planJSON = chat.planJSON; taskID = chat.taskID
        receiptID = chat.receiptID; state = chat.state; memory = chat.memory
        operationKind = chat.operationKind; lastError = chat.lastError; title = chat.title
    }
    func restore(into chat: inout Conversation) {
        chat.messages = messages; chat.events = events; chat.questions = questions; chat.answers = answers
        chat.pendingAssetIDs = pendingAssetIDs; chat.planJSON = planJSON; chat.taskID = taskID
        chat.receiptID = receiptID; chat.state = state; chat.memory = memory
        chat.operationKind = operationKind; chat.lastError = lastError; chat.title = title; chat.editBackup = nil
    }
}

enum ConversationEditing {
    static func replaceLatest(in chat: inout Conversation, messageID: String, text: String) throws {
        guard let index = chat.messages.lastIndex(where: { $0.role == "user" }), chat.messages[index].id == messageID else {
            throw AppFailure(message: "只能重新编辑最新一条用户消息。")
        }
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { throw AppFailure(message: "请填写消息内容。") }
        let removedIDs = Set(chat.messages[index...].map(\.id))
        chat.editBackup = chat.editBackup ?? ConversationTurnBackup(chat)
        chat.messages[index].text = clean
        chat.messages[index].date = Date()
        chat.messages.removeSubrange((index + 1)..<chat.messages.count)
        if !(Set(chat.memory?.coveredMessageIDs ?? []).intersection(removedIDs)).isEmpty { chat.memory = nil }
        chat.events = []; chat.questions = []; chat.answers = [:]
        chat.planJSON = nil; chat.taskID = makeID(); chat.receiptID = nil
        chat.operationKind = nil; chat.lastError = nil; chat.state = "idle"
        if index == 0 && chat.userNamed != true { chat.title = String(clean.prefix(22)) }
    }
}

enum ChatCommand: String, CaseIterable, Identifiable {
    case compact, clear, new, retry, stop, export, context, help
    var id: String { rawValue }
    var title: String { switch self { case .compact: "压缩上下文"; case .clear: "清空当前对话"; case .retry: "重新生成回复"; case .export: "导出对话"; case .context: "查看上下文与记忆"; case .new: "新建对话"; case .stop: "停止当前回复"; case .help: "查看命令与快捷键" } }
    var detail: String { switch self { case .compact: "提取早期摘要，保留完整记录"; case .clear: "记录移入回收站，保留笔记与固定记忆"; case .retry: "重新尝试未完成的最后一轮"; case .export: "将完整对话保存为 Markdown"; case .context: "管理固定信息与参与回复的历史"; case .new: "保存当前草稿，开始新的对话"; case .stop: "立即中止生成，保留已有内容"; case .help: "输入 / 选择命令，无需发送给 AI" } }
    var icon: String { switch self { case .compact: "text.badge.minus"; case .clear: "eraser"; case .retry: "arrow.clockwise"; case .export: "square.and.arrow.up"; case .context: "circle.dotted.circle"; case .new: "square.and.pencil"; case .stop: "stop.circle"; case .help: "questionmark.circle" } }
    static func exact(_ text: String) -> ChatCommand? {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard clean.hasPrefix("/") else { return nil }
        return ChatCommand(rawValue: String(clean.dropFirst()))
    }
    static func matches(_ text: String) -> [ChatCommand] {
        guard text.hasPrefix("/"), !text.contains(where: { $0.isWhitespace }) else { return [] }
        let query = String(text.dropFirst()).lowercased()
        return allCases.filter { query.isEmpty || $0.rawValue.hasPrefix(query) || $0.title.contains(query) }
    }
}

enum ChatLayout {
    static func contentWidth(available: Double, mode: String?) -> Double {
        let inset = available < 900 ? 24.0 : 32.0
        return max(280, min(available - inset * 2, mode == "wide" ? 1180 : 780))
    }
}

enum ConnectionPresentation {
    static func inheritedTitle(_ settings: AppSettings) -> String {
        if settings.defaultProvider == "codex" { return "沿用主服务 · Codex" }
        return "沿用主服务 · " + (settings.profiles.first { $0.id == settings.defaultProvider }?.name ?? "未配置")
    }
    static func detail(_ function: AIFunction, settings: AppSettings, codexConnected: Bool, imageAvailable: Bool) -> String {
        let selection = settings.selection(function)
        if selection.providerID == "none" { return function == .image ? "未启用 · 不影响聊天、读图和文字笔记" : "未配置服务，请选择连接" }
        if selection.providerID == "codex" {
            if !codexConnected { return "本机 Codex 尚未连接" }
            if function == .image { return imageAvailable ? "本机图像生成可用" : "当前 Codex 连接未提供图像生成能力" }
            return "本机 Codex · " + Theme.modelName(selection.modelID)
        }
        guard let profile = settings.profiles.first(where: { $0.id == selection.providerID }) else { return "未配置服务，请选择连接" }
        do { try settings.validate(selection, for: function) }
        catch { return error.localizedDescription }
        return profile.name + " · " + selection.modelID + "（可用性以测试为准）"
    }
}

// UI stages describe work the user recognizes, not nested model/tool lifetimes.
// The optional stage on stored events keeps older conversations readable.
enum OperationStage: String, Codable, CaseIterable {
    case preparation, reading, reference, organization, illustration, saving

    var title: String {
        switch self {
        case .preparation: return "准备原稿"
        case .reading: return "读取原稿"
        case .reference: return "查阅资料"
        case .organization: return "整理内容"
        case .illustration: return "生成图示"
        case .saving: return "校验并保存"
        }
    }
    static func resolve(_ title: String, previous: OperationStage?, scope: OperationStage? = nil) -> OperationStage {
        // Preparing/rechecking images inside refinement or illustration belongs to
        // that operation; it must not reopen the first step of the entire job.
        if scope == .organization || scope == .illustration { return scope! }
        if title == "准备图片" { return .preparation }
        if let scope { return scope }
        switch title {
        case "识别原稿": return .reading
        case "编排笔记", "细化章节编排", "模型处理": return .organization
        case "制作图示": return .illustration
        case "生成图示", "准备图示文件": return previous ?? .illustration
        case "校验并保存": return .saving
        case "查阅参考资料":
            return [.reading, .organization, .illustration].contains(previous) ? previous! : .reference
        default: return previous ?? .organization
        }
    }
}

enum OperationEvents {
    static func record(_ events: inout [OperationEvent], title: String, detail: String, status: String, scope: OperationStage? = nil) {
        let stage = OperationStage.resolve(title, previous: events.last?.stage, scope: scope)
        if let index = events.lastIndex(where: { $0.title == title && $0.stage == stage && $0.status == "running" }) {
            events[index].status = status
            if !detail.isEmpty { events[index].detail = concise(detail) }
        } else {
            events.append(OperationEvent(title: title, detail: concise(detail), status: status, stage: stage))
        }
    }
    static func concise(_ detail: String) -> String {
        detail.replacingOccurrences(of: " · 保留高清细节", with: "")
            .replacingOccurrences(of: "，正在汇总", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct OperationProgress {
    enum Status: String { case pending, running, completed, failed, interrupted }
    struct Step: Identifiable {
        var stage: OperationStage
        var title: String
        var detail: String
        var status: Status
        var id: OperationStage { stage }
        var accessibilityStatus: String {
            switch status {
            case .pending: return "未开始"
            case .running: return "进行中"
            case .completed: return "已完成"
            case .failed: return "未完成"
            case .interrupted: return "已停止"
            }
        }
    }
    let steps: [Step]
    let title: String
    var running: Bool { steps.contains { $0.status == .running } }
    var current: Step? { steps.first { $0.status == .running } }

    init(events: [OperationEvent], state: String? = nil, writing: Bool = false) {
        var order: [OperationStage] = []
        var grouped: [OperationStage: [OperationEvent]] = [:]
        var previous: OperationStage?
        for event in events {
            let stage = event.stage ?? OperationStage.resolve(event.title, previous: previous)
            if grouped[stage] == nil { order.append(stage) }
            grouped[stage, default: []].append(event)
            previous = stage
        }
        // Older versions announced separate recognition before preparing its images.
        if let prepare = order.firstIndex(of: .preparation), let read = order.firstIndex(of: .reading), prepare > read {
            order.remove(at: prepare); order.insert(.preparation, at: read)
        }
        let active = order.last
        let isWriting = writing || events.contains { ["编排笔记", "细化章节编排", "校验并保存"].contains($0.title) }
        let outcome = state ?? (events.contains { $0.status == "running" } ? "processing" : events.contains { $0.status == "failed" } ? "failed" : events.contains { $0.status == "interrupted" } ? "interrupted" : "completed")
        let processing = ["processing", "saving"].contains(outcome)
        if processing || ["failed", "cancelled", "interrupted"].contains(outcome) {
            if !order.contains(.organization) { order.append(.organization) }
            if isWriting && !order.contains(.saving) { order.append(.saving) }
        }
        steps = order.map { stage in
            let values = grouped[stage] ?? []
            let status: Status
            if values.isEmpty { status = .pending }
            else if stage != active { status = .completed }
            else if outcome == "failed" { status = .failed }
            else if ["cancelled", "interrupted"].contains(outcome) { status = .interrupted }
            else { status = processing ? .running : .completed }
            let label = stage == .organization && isWriting ? "整理笔记" : stage.title
            return Step(stage: stage, title: label, detail: Self.detail(stage: stage, events: values, status: status), status: status)
        }
        switch outcome {
        case "failed": title = "整理未完成"
        case "cancelled", "interrupted": title = "整理已停止"
        case "awaitingAnswers": title = "等待补充"
        default: title = processing ? (isWriting ? "正在整理笔记" : "正在处理资料") : (isWriting ? "整理完成" : "处理记录")
        }
    }
    private static func detail(stage: OperationStage, events: [OperationEvent], status: Status) -> String {
        if status == .pending { return "" }
        if status == .failed { return "未完成，可以重新生成" }
        if status == .interrupted { return "已停止，原稿已保留" }
        if status == .running {
            if events.last(where: { $0.title == "恢复模型连接" })?.status == "running" { return "连接中断，正在重试" }
            if events.last(where: { $0.title == "核对原稿" })?.status == "running" { return "正在核对原稿" }
            if events.last(where: { $0.title == "查阅参考资料" })?.status == "running" { return "正在查阅参考资料" }
        }
        let titles: [String]
        switch stage {
        case .preparation: titles = ["准备图片"]
        case .reading: titles = ["识别原稿", "模型处理"]
        case .reference: titles = ["查阅参考资料"]
        case .organization: titles = ["编排笔记", "细化章节编排", "模型处理"]
        case .illustration: titles = ["制作图示", "生成图示"]
        case .saving: titles = ["校验并保存"]
        }
        let detail = OperationEvents.concise(events.last(where: { titles.contains($0.title) })?.detail ?? "")
        if status == .completed {
            if stage == .saving { return detail }
            if stage == .reading { return detail.contains("张") ? detail : "已完成读取" }
            return ""
        }
        if !detail.isEmpty { return detail }
        return stage == .organization ? "正在整理内容" : "正在处理"
    }
}

// Keep waiting feedback in the existing reply row, with no invented percentage.
enum ReplyActivity {
    static func title(events: [OperationEvent], action: String) -> String {
        if action == "search" { return "正在查找相关笔记" }
        guard let step = OperationProgress(events: events, state: "processing", writing: action == "write").current else { return "正在准备请求" }
        if step.stage == .preparation { return step.title + (step.detail.isEmpty ? "" : " · " + step.detail) }
        return step.detail.isEmpty ? step.title : step.detail
    }
    static func elapsed(from start: Date, now: Date) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(start)))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}
