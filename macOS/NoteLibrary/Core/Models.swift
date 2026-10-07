import Foundation

func makeID() -> String { UUID().uuidString.lowercased() }

enum BlockKind: String, Codable, CaseIterable {
    case paragraph, heading, bullet, term, formula, example, table, image, diagram, callout
    var label: String {
        switch self {
        case .paragraph: return "正文"
        case .heading: return "小标题"
        case .bullet: return "要点"
        case .term: return "单词与术语"
        case .formula: return "公式"
        case .example: return "例题"
        case .table: return "表格"
        case .image: return "图片"
        case .diagram: return "示意图"
        case .callout: return "概念"
        }
    }
    var icon: String {
        switch self {
        case .term: return "character.book.closed"
        case .formula: return "function"
        case .table: return "tablecells"
        case .image: return "photo"
        case .diagram: return "chart.xyaxis.line"
        case .callout: return "lightbulb"
        default: return "text.alignleft"
        }
    }
}

struct ContentBlock: Codable, Identifiable, Equatable {
    var id = makeID()
    var kind: BlockKind = .paragraph
    var text = ""
    var detail = ""
    var rows: [[String]] = []
    var assetID: String? = nil
    var diagram: StudyDiagram? = nil
    var origin = "source"
    var citations: [String] = []
    var reviewQuestion: String? = nil
    var isReviewCard: Bool {
        [.term, .formula, .callout].contains(kind)
            && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !detail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

struct Notebook: Codable, Identifiable, Equatable {
    var id = makeID()
    var title: String
    var subject = ""
    var color = 0
    var createdAt = Date()
    var summary: String? = nil
    var coverStyle: String? = nil
    var pinned: Bool? = nil
    var archivedAt: Date? = nil
    var deletedAt: Date? = nil
}

struct ReadingRecord: Codable, Equatable {
    var noteID: String
    var completed: Bool
    var lastOpenedAt: Date
}

struct ReviewRecord: Codable, Equatable {
    var blockID: String
    var rating: String
    var reviewedAt: Date
    var attempts: Int
    var dueAt: Date? = nil
    var streak: Int? = nil
    var fingerprint: String? = nil
}

struct Chapter: Codable, Identifiable, Equatable {
    var id = makeID()
    var notebookID: String
    var title: String
    var order: Int = 0
    var locked = false
}

struct Note: Codable, Identifiable, Equatable {
    var id = makeID()
    var chapterID: String
    var title: String
    var blocks: [ContentBlock] = []
    var sourceIDs: [String] = []
    var tags: [String] = []
    var favorite = false
    var pinned: Bool? = nil
    var locked = false
    var version = 1
    var createdAt = Date()
    var updatedAt = Date()
    var deletedAt: Date? = nil
    var searchableText: String { ([title] + tags + blocks.flatMap { [$0.text, $0.detail, $0.diagram?.accessibleDescription ?? ""] + $0.rows.flatMap { $0 } }).joined(separator: " ") }
}

struct SourceAsset: Codable, Identifiable, Equatable {
    var id = makeID()
    var filename: String
    var displayName: String
    var digest: String
    var generated = false
    var createdAt = Date()
    var byteCount: Int? = nil
    var document: SourceDocument? = nil
}

struct AIQuestion: Codable, Identifiable, Equatable {
    var id: String
    var question: String
    var options: [String]
}

struct ChatMessage: Codable, Identifiable, Equatable {
    var id = makeID()
    var role: String
    var text: String
    var assetIDs: [String] = []
    var date = Date()
    var events: [OperationEvent]? = nil
    var receiptID: String? = nil
    var noteReferences: [NoteReference]? = nil
    var webSources: [WebSearchSource]? = nil
}

struct OperationEvent: Codable, Identifiable, Equatable {
    var id = makeID()
    var title: String
    var detail = ""
    var status = "running"
    var date = Date()
    var stage: OperationStage? = nil
}

struct Conversation: Codable, Identifiable, Equatable {
    var id = makeID()
    var title = "新对话"
    var model = "gpt-6-astra"
    var effort = "medium"
    var messages: [ChatMessage] = []
    var events: [OperationEvent] = []
    var questions: [AIQuestion] = []
    var answers: [String: String] = [:]
    var pendingAssetIDs: [String] = []
    var draft = ""
    var draftAssetIDs: [String]? = nil
    var planJSON: String? = nil
    var taskID: String? = nil
    var receiptID: String? = nil
    var state = "idle"
    var updatedAt = Date()
    var pinned: Bool? = nil
    var userNamed: Bool? = nil
    var deletedAt: Date? = nil
    var notebookID: String? = nil
    var memory: ConversationMemory? = nil
    var operationKind: String? = nil
    var lastError: String? = nil
    var editBackup: ConversationTurnBackup? = nil
    var contextPreferences: ContextPreferences? = nil
    var aiSelection: AISelection? = nil
    var hasStarted: Bool { !messages.isEmpty }
    var hasDraft: Bool { !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !(draftAssetIDs ?? []).isEmpty }
    var hasContent: Bool { hasStarted || hasDraft }
    var draftTitle: String {
        if userNamed == true { return title }
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? "附件草稿" : String(text.prefix(32))
    }
}

struct PinnedMemory: Codable, Identifiable, Equatable {
    var id = makeID()
    var text: String
    var enabled = true
}

struct ContextPreferences: Codable, Equatable {
    var autoCompact: Bool? = nil
    var includeHistory = true
    var includeHistoricalImages = true
    var includeNoteContents = true
    var retainedMessages = 10
    var excludedMessageIDs: [String] = []
    var pins: [PinnedMemory] = []
}

struct ConversationMemory: Codable, Equatable {
    var text: String
    var coveredMessageIDs: [String]
    var assetIDs: [String]
    var createdAt = Date()
    var originalCharacters: Int
    var compactedCharacters: Int
    var generation: Int
}

struct NoteDelta: Codable, Equatable {
    var before: Note?
    var after: Note
}

struct ChangeReceipt: Codable, Identifiable, Equatable {
    var id: String
    var title: String
    var date = Date()
    var changes: [NoteDelta]
    var createdNotebookIDs: [String]
    var createdChapterIDs: [String]
    var undone = false
}

/// A connection can serve several models. Capability labels are user-selected,
/// never inferred from an arbitrary vendor's model identifier.
struct APIModel: Codable, Identifiable, Equatable {
    var id: String
    var kind = "text"
    var protocolKind: String? = nil
    var outputFormat = "prompt"
    var supportsSearch = false
    var maxOutputTokens: Int? = nil
    var imageFormat: String? = nil // nil resolves by endpoint; explicit formats also work with custom gateways
    var label: String { kind == "image" ? "生图" : kind == "vision" ? "文本与读图" : "文本" }
    func supports(_ function: AIFunction) -> Bool {
        if function == .image { return kind == "image" }
        if function == .recognition { return kind == "vision" }
        return kind == "text" || kind == "vision"
    }
}
struct AISelection: Codable, Equatable, Hashable {
    var providerID: String
    var modelID: String
    var id: String { providerID + "\n" + modelID }
    init(providerID: String, modelID: String) { self.providerID = providerID; self.modelID = modelID }
    init?(id: String) {
        guard let split = id.firstIndex(of: "\n") else { return nil }
        providerID = String(id[..<split]); modelID = String(id[id.index(after: split)...])
    }
}
struct APIProfile: Codable, Identifiable, Equatable {
    var id = makeID()
    var name = "自定义 API"
    var baseURL = "https://api.openai.com/v1"
    var protocolKind = "responses"
    // Retained for lossless migration from the original single-model format.
    var model = ""
    var imageModel = ""
    var models: [APIModel]? = nil
    var presetID: String? = nil
    var catalog: [APIModel] {
        if let models { return models }
        var result: [APIModel] = []
        if !model.isEmpty { result.append(APIModel(id: model, kind: "vision", outputFormat: "schema", supportsSearch: protocolKind == "responses")) }
        if !imageModel.isEmpty { result.append(APIModel(id: imageModel, kind: "image")) }
        return result
    }
    var brandID: String {
        if let presetID, presetID != "custom", ServicePreset.all.contains(where: { $0.id == presetID }) { return presetID }
        guard let host = URL(string: baseURL)?.host else { return "custom" }
        return ServicePreset.all.first { $0.id != "custom" && URL(string: $0.address)?.host == host }?.id ?? "custom"
    }
    func firstModel(for function: AIFunction) -> String { catalog.first { $0.supports(function) }?.id ?? "" }
    mutating func replaceModels(_ items: [APIModel]) {
        models = items
        model = items.first { $0.supports(.conversation) }?.id ?? ""
        imageModel = items.first { $0.supports(.image) }?.id ?? ""
    }
    func validated() throws -> APIProfile {
        var copy = self
        copy.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if copy.name.isEmpty, let preset = ServicePreset.all.first(where: { $0.id == presetID && $0.id != "custom" }) { copy.name = preset.name }
        guard !copy.name.isEmpty else { throw AppFailure(message: "请填写连接名称，方便识别不同服务。") }
        copy.baseURL = try APIEndpoint.normalized(baseURL)
        guard ["responses", "chat", "anthropic"].contains(protocolKind) else { throw AppFailure(message: "请选择此服务支持的接口。") }
        var items = catalog
        for i in items.indices {
            items[i].id = items[i].id.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !items[i].id.isEmpty, !items[i].id.contains(where: { $0.isWhitespace }), ["text", "vision", "image"].contains(items[i].kind), ["prompt", "json", "schema"].contains(items[i].outputFormat), items[i].protocolKind == nil || ["responses", "chat", "anthropic"].contains(items[i].protocolKind!) else { throw AppFailure(message: "请填写服务商提供的模型 ID，并选择有效的模型用途。") }
        }
        guard items.allSatisfy({ !$0.supportsSearch || ($0.protocolKind ?? protocolKind) == "responses" }) else { throw AppFailure(message: "联网搜索需要 Responses 接口。请修改此模型的接口，或关闭其联网搜索选项。") }
        guard items.allSatisfy({ $0.kind == "image" || ($0.protocolKind ?? protocolKind) != "anthropic" || $0.outputFormat != "json" }) else { throw AppFailure(message: "Claude Messages 请使用通用兼容或严格结构输出。") }
        guard items.allSatisfy({ $0.maxOutputTokens == nil || (1024...131072).contains($0.maxOutputTokens!) }) else { throw AppFailure(message: "输出预算应在 1024 到 131072 之间，请按模型支持的范围设置。") }
        guard items.allSatisfy({ $0.imageFormat == nil || ImageGenerationProtocol(rawValue: $0.imageFormat!) != nil }) else { throw AppFailure(message: "请选择有效的生图接口格式。") }
        guard Set(items.map(\.id)).count == items.count else { throw AppFailure(message: "这个模型已经添加过了，请修改已有模型。") }
        copy.replaceModels(items)
        return copy
    }
}
enum APIEndpoint {
    static func normalized(_ address: String) throws -> String {
        let clean = address.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let parts = URLComponents(string: clean), let host = parts.host, !host.isEmpty,
              parts.user == nil, parts.password == nil, parts.query == nil, parts.fragment == nil,
              parts.scheme == "https" || (parts.scheme == "http" && ["localhost", "127.0.0.1", "::1", "[::1]"].contains(host)) else { throw AppFailure(message: "请输入 HTTPS 服务地址；本机服务可用 HTTP。地址中不要包含密钥、参数或用户名。") }
        guard !["/responses", "/chat/completions", "/images/generations", "/images", "/image_generation", "/models", "/messages", "/multimodal-generation/generation"].contains(where: { parts.path.hasSuffix($0) }) else { throw AppFailure(message: "请填写接口根地址，例如 https://api.openai.com/v1，不要填具体请求地址。") }
        return clean
    }
    static func url(_ address: String, path: String) throws -> URL {
        guard let result = URL(string: try normalized(address) + path) else { throw AppFailure(message: "服务地址无法使用。") }
        return result
    }
}

struct ServicePreset: Identifiable {
    var id: String
    var name: String
    var address: String
    var protocolKind = "chat"
    var help: String
    var documentation: String
    static let all: [ServicePreset] = [
        .init(id: "openai", name: "OpenAI", address: "https://api.openai.com/v1", protocolKind: "responses", help: "使用 OpenAI API 密钥；ChatGPT 订阅与 API 额度分别计算。", documentation: "https://developers.openai.com/api/docs/quickstart"),
        .init(id: "deepseek", name: "DeepSeek", address: "https://api.deepseek.com", help: "使用 DeepSeek 开放平台密钥，模型 ID 可从列表获取。", documentation: "https://api-docs.deepseek.com/"),
        .init(id: "claude", name: "Claude", address: "https://api.anthropic.com/v1", protocolKind: "anthropic", help: "直接使用 Claude API 的 Messages 接口。生图请另外配置服务。", documentation: "https://platform.claude.com/docs/en/api/overview"),
        .init(id: "gemini", name: "Gemini", address: "https://generativelanguage.googleapis.com/v1beta/openai", help: "使用 Google AI Studio 密钥及官方 OpenAI 兼容接口。", documentation: "https://ai.google.dev/gemini-api/docs/openai"),
        .init(id: "kimi", name: "Kimi", address: "https://api.moonshot.ai/v1", help: "默认国际端点；国内账户可改成 https://api.moonshot.cn/v1。", documentation: "https://platform.moonshot.ai/docs/api/chat"),
        .init(id: "glm", name: "GLM · 智谱", address: "https://open.bigmodel.cn/api/paas/v4", help: "默认通用 API 地址；Coding Plan 的地址与额度不同，请按订阅说明修改。", documentation: "https://docs.bigmodel.cn/"),
        .init(id: "qwen", name: "Qwen · 通义千问", address: "https://dashscope.aliyuncs.com/compatible-mode/v1", help: "默认北京按量付费端点。其他地域、工作空间或 Coding Plan 需使用对应地址和密钥。", documentation: "https://help.aliyun.com/en/model-studio/base-url"),
        .init(id: "doubao", name: "Doubao · 豆包", address: "https://ark.cn-beijing.volces.com/api/v3", help: "使用火山方舟密钥；按控制台填写模型 ID 或推理接入点 ID。", documentation: "https://docs.volcengine.com/docs/ark/compatible-with-openai-sdk?lang=zh"),
        .init(id: "minimax", name: "MiniMax", address: "https://api.minimax.io/v1", help: "默认国际通用 API；国内服务或订阅计划请改用账户对应的接口地址。", documentation: "https://platform.minimax.io/docs/api-reference/text-openai-api"),
        .init(id: "openrouter", name: "OpenRouter", address: "https://openrouter.ai/api/v1", help: "可混用不同厂商模型，填写完整模型 ID；用途按该模型说明选择。", documentation: "https://openrouter.ai/docs/quickstart"),
        .init(id: "siliconflow", name: "SiliconFlow · 硅基流动", address: "https://api.siliconflow.cn/v1", help: "使用硅基流动密钥，模型 ID 需包含完整厂商和模型路径。", documentation: "https://docs.siliconflow.cn/en/userguide/quickstart"),
        .init(id: "custom", name: "自定义 API", address: "https://api.openai.com/v1", help: "支持 Responses、Chat Completions、Claude Messages；本机免密服务可以不填密钥。", documentation: "")
    ]
    static func named(_ id: String?) -> ServicePreset { all.first { $0.id == id } ?? all.last! }
    var newProfile: APIProfile { APIProfile(name: name, baseURL: address, protocolKind: protocolKind, models: [], presetID: id) }
    func suggestedName(existingNames: [String]) -> String {
        let names = Set(existingNames)
        if !names.contains(name) { return name }
        var number = 2
        while names.contains(name + " " + String(number)) { number += 1 }
        return name + " " + String(number)
    }
}

struct WebSearchConfiguration: Codable, Equatable {
    var mode = "builtin" // builtin, model, tavily, brave
    var selection: AISelection? = nil
    var baseURL = "https://api.tavily.com"
    var keyID = makeID()
    var usesAPI: Bool { ["tavily", "brave"].contains(mode) }
    var title: String { ["builtin": "沿用校对模型", "model": "指定搜索模型", "tavily": "Tavily 搜索 API", "brave": "Brave 搜索 API"][mode] ?? "待配置" }
    func searchSelection(settings: AppSettings) throws -> AISelection {
        guard let selected = mode == "builtin" ? settings.selection(.verify) : selection else { throw AppFailure(message: "请选择支持联网搜索的服务与模型。") }
        try settings.validate(selected, for: .verify)
        if selected.providerID != "codex" {
            guard let profile = settings.profiles.first(where: { $0.id == selected.providerID }), let item = profile.catalog.first(where: { $0.id == selected.modelID }), item.supportsSearch, (item.protocolKind ?? profile.protocolKind) == "responses" else {
                throw AppFailure(message: "所选模型未配置联网工具。请选择支持联网的搜索模型，或单独连接 Tavily / Brave 搜索 API。")
            }
        }
        return selected
    }
    func validated(settings: AppSettings) throws -> WebSearchConfiguration {
        var copy = self
        guard ["builtin", "model", "tavily", "brave"].contains(mode) else { throw AppFailure(message: "请选择有效的搜索方式。") }
        if !usesAPI { _ = try searchSelection(settings: settings) }
        else { copy.baseURL = try SearchEndpoint.base(baseURL, mode: mode) }
        return copy
    }
}

enum SearchEndpoint {
    static func base(_ address: String, mode: String) throws -> String {
        var result = try APIEndpoint.normalized(address)
        let suffixes = mode == "brave" ? ["/res/v1/web/search", "/res/v1"] : ["/search"]
        if let suffix = suffixes.first(where: { result.hasSuffix($0) }) { result.removeLast(suffix.count) }
        return try APIEndpoint.normalized(result)
    }
    static func url(_ address: String, mode: String) throws -> URL {
        guard ["tavily", "brave"].contains(mode) else { throw AppFailure(message: "请选择搜索 API 的兼容格式。") }
        return URL(string: try base(address, mode: mode) + (mode == "brave" ? "/res/v1/web/search" : "/search"))!
    }
    static func query(_ value: String, mode: String) throws -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw AppFailure(message: "请输入搜索关键词。") }
        if mode == "brave" { return String(trimmed.split(whereSeparator: \.isWhitespace).prefix(75).joined(separator: " ").prefix(600)) }
        return String(trimmed.prefix(700))
    }
}

enum AIFunction: String, CaseIterable, Identifiable {
    case conversation, recognition, organize, verify, image
    var id: String { rawValue }
    var label: String {
        switch self {
        case .conversation: return "日常对话"
        case .recognition: return "图片识别"
        case .organize: return "内容编排"
        case .verify: return "知识校对"
        case .image: return "图示生成"
        }
    }
}

struct AppSettings: Codable, Equatable {
    var codexPath = ""
    var defaultModel = "gpt-6-astra"
    var defaultEffort = "medium"
    var defaultProvider = "codex"
    var profiles: [APIProfile] = []
    var routes: [String: String] = [:]
    var routeModels: [String: String]? = nil
    var defaultAPIModel: String? = nil
    var preferredModels: [String: String]? = nil
    var language = "简体中文"
    var detail = "适度补充解释和例子"
    var onlineVerification = false
    var webSearch: WebSearchConfiguration? = nil
    var appearance = "system"
    var fontSize: Double = 16
    var lineSpacing: Double = 7
    var readingWidth: Double? = nil
    var showOriginal = false
    var reduceMotion = false
    var enterSends = false
    var automaticSnapshots = true
    var notifications = false
    var autoCompact: Bool? = nil
    var compactAfterCharacters: Int? = nil
    var showMessageTime: Bool? = nil
    var chatLayout: String? = nil
    var bookshelfLayout: String? = nil
    var sidebarCollapsed: Bool? = nil
    var sidebarNotebooksCollapsed: Bool? = nil
    var sidebarConversationsCollapsed: Bool? = nil
    func route(_ function: AIFunction) -> String {
        if let explicit = routes[function.rawValue] { return explicit }
        // Keep a previously configured image service, but never require or
        // silently inherit image generation from a new text-only connection.
        if function == .image { return profiles.first { $0.id == defaultProvider && $0.models == nil && !$0.imageModel.isEmpty }?.id ?? "none" }
        return defaultProvider
    }
    func selection(_ function: AIFunction, conversation: Conversation? = nil) -> AISelection {
        let inherited = function != .image && routes[function.rawValue] == nil
        if (function == .conversation || inherited), let chosen = conversation?.aiSelection { return chosen }
        let provider = route(function)
        if provider == "codex" {
            return AISelection(providerID: provider, modelID: routeModels?[function.rawValue] ?? (inherited || function == .conversation ? conversation?.model : nil) ?? defaultModel)
        }
        let profile = profiles.first { $0.id == provider }
        let model = routeModels?[function.rawValue] ?? (provider == defaultProvider && (inherited || function == .conversation) ? defaultAPIModel : nil) ?? profile?.firstModel(for: function) ?? ""
        return AISelection(providerID: provider, modelID: model)
    }
    func models(in provider: String, for function: AIFunction, searchOnly: Bool = false) -> [APIModel] {
        if provider == "codex" {
            return (function == .image ? [defaultModel] : ["gpt-6-astra", "gpt-6.1-sol", "gpt-6-luna"]).map { APIModel(id: $0, kind: function == .image ? "image" : "vision", supportsSearch: true) }
        }
        return profiles.first { $0.id == provider }?.catalog.filter { $0.supports(function) && (!searchOnly || $0.supportsSearch) } ?? []
    }
    func selection(in provider: String, for function: AIFunction, current: AISelection? = nil, searchOnly: Bool = false) -> AISelection {
        let ids = models(in: provider, for: function, searchOnly: searchOnly).map(\.id)
        let candidates = [current?.providerID == provider ? current?.modelID : nil, preferredModels?[provider + "\n" + function.rawValue], provider == "codex" ? defaultModel : provider == defaultProvider ? defaultAPIModel : nil]
        let chosen = candidates.compactMap { $0 }.first { ids.contains($0) } ?? ids.first ?? ""
        return AISelection(providerID: provider, modelID: chosen)
    }
    mutating func remember(_ selection: AISelection, for function: AIFunction) {
        guard !selection.modelID.isEmpty, selection.providerID != "none" else { return }
        if preferredModels == nil { preferredModels = [:] }
        preferredModels?[selection.providerID + "\n" + function.rawValue] = selection.modelID
    }
    mutating func setDefaultSelection(_ selected: AISelection) {
        defaultProvider = selected.providerID
        if selected.providerID == "codex" { defaultModel = selected.modelID } else { defaultAPIModel = selected.modelID }
        remember(selected, for: .conversation)
        assign(.conversation, to: nil)
    }
    mutating func assign(_ function: AIFunction, to selection: AISelection?) {
        if routeModels == nil { routeModels = [:] }
        if let selection { remember(selection, for: function); routes[function.rawValue] = selection.providerID; routeModels?[function.rawValue] = selection.modelID }
        else { routes.removeValue(forKey: function.rawValue); routeModels?.removeValue(forKey: function.rawValue) }
    }
    func validate(_ selection: AISelection, for function: AIFunction) throws {
        if selection.providerID == "none" { throw AppFailure(message: function == .image ? "图示生成尚未启用。请在设置 → AI 功能分配选择生图服务与模型；文字笔记无需生图模型。" : "请在设置中为\(function.label)选择服务与模型。") }
        if selection.providerID == "codex" { return }
        guard let profile = profiles.first(where: { $0.id == selection.providerID }) else { throw AppFailure(message: "所选连接已不存在，请在设置中重新选择。") }
        guard let model = profile.catalog.first(where: { $0.id == selection.modelID }) else { throw AppFailure(message: "请先为「\(profile.name)」添加模型，再为\(function.label)选择模型。") }
        guard model.supports(function) else { throw AppFailure(message: function == .recognition ? "当前模型未标记为支持读图。请在 AI 功能分配选择支持图片输入的模型，或在连接中修改模型用途。" : "所选模型不适用于\(function.label)，请在设置中重新选择。") }
    }
}

struct LibraryState: Codable {
    var schemaVersion = 1
    var contentRevision = 0
    var notebooks: [Notebook] = []
    var chapters: [Chapter] = []
    var notes: [Note] = []
    var assets: [SourceAsset] = []
    var conversations: [Conversation] = []
    var receipts: [ChangeReceipt] = []
    var committedTaskIDs: [String] = []
    var settings = AppSettings()
    var readingRecords: [ReadingRecord]? = nil
    var reviewRecords: [ReviewRecord]? = nil
    var studySessions: [StudySession]? = nil

    @discardableResult
    mutating func upgradeLegacySolModel() -> Bool {
        var changed = false
        // These fields select the built-in Codex model for future requests.
        // Custom API profiles and the original message contents remain intact.
        if settings.defaultModel == "gpt-6-sol" {
            settings.defaultModel = "gpt-6.1-sol"
            if ["none", "minimal"].contains(settings.defaultEffort) { settings.defaultEffort = "low" }
            changed = true
        }
        for i in conversations.indices where conversations[i].model == "gpt-6-sol" {
            conversations[i].model = "gpt-6.1-sol"
            if ["none", "minimal"].contains(conversations[i].effort) { conversations[i].effort = "low" }
            changed = true
        }
        return changed
    }
}

struct AIBlock: Codable {
    var id: String
    var kind: String
    var text: String
    var detail: String
    var rows: [[String]]
    var origin: String
    var citations: [String]
    var diagramPrompt: String
    var sourceAssetID: String? = nil
    var diagram: StudyDiagram? = nil
    var reviewQuestion: String? = nil
}

struct AINoteChange: Codable {
    var noteID: String
    var notebookID: String
    var notebookTitle: String
    var chapterID: String
    var chapterTitle: String
    var title: String
    var blocks: [AIBlock]
    var sourceIDs: [String]
    var tags: [String]
}

struct AIPlan: Codable {
    var action: String
    var message: String
    var questions: [AIQuestion]
    var notes: [AINoteChange]
    var references: [AINoteReference]? = nil
    var searchQueries: [String]? = nil
    var imagePrompt: String? = nil
}

struct AvailableModel: Identifiable {
    var id: String
    var name: String
    var efforts: [String]
    var isDefault: Bool
}

struct AppFailure: LocalizedError {
    var message: String
    var errorDescription: String? { message }
}

enum JSONCoding {
    static var encoder: JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.sortedKeys]
        return e
    }
    static var decoder: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }
}
