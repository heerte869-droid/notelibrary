import SwiftUI
import AppKit

enum AIModelChoices {
    static func providers(_ function: AIFunction, settings: AppSettings, searchOnly: Bool = false) -> [ChoiceOption] {
        [ChoiceOption(id: "codex", title: "本机 Codex", subtitle: "使用已登录的本机账号", brand: "codex")] + settings.profiles.map { profile in
            let count = settings.models(in: profile.id, for: function, searchOnly: searchOnly).count
            return ChoiceOption(id: profile.id, title: profile.name, subtitle: count == 0 ? "待添加适用模型" : "\(count) 个适用模型", brand: profile.brandID)
        }
    }
    static func models(_ function: AIFunction, provider: String, settings: AppSettings, available: [AvailableModel], searchOnly: Bool = false) -> [ChoiceOption] {
        let brand = provider == "codex" ? "openai" : settings.profiles.first { $0.id == provider }?.brandID ?? "custom"
        return settings.models(in: provider, for: function, searchOnly: searchOnly).map { item in
            ChoiceOption(id: item.id, title: provider == "codex" ? (function == .image ? "Codex 生图" : Theme.modelName(item.id)) : item.id,
                         subtitle: provider == "codex" ? "" : item.label, brand: brand, disabled: provider == "codex" && !available.isEmpty && !available.contains { $0.id == item.id })
        }
    }

    static func conversationModels(provider: String, settings: AppSettings, available: [AvailableModel]) -> [ChoiceOption] {
        models(.conversation, provider: provider, settings: settings, available: available).filter { !$0.disabled }.map { option in
            ChoiceOption(id: AISelection(providerID: provider, modelID: option.id).id, title: option.title, brand: option.brand)
        }
    }

}

/// Two explicit controls: changing the service never mixes its model list with another service.
struct AISelectionFields: View {
    @EnvironmentObject private var model: AppModel
    var function: AIFunction
    var selection: AISelection
    var searchOnly = false
    var onSelect: (AISelection) -> Void
    var onAdd: () -> Void
    var onManage: (String) -> Void
    private var settings: AppSettings { model.library.settings }
    private var providers: [ChoiceOption] {
        var items = AIModelChoices.providers(function, settings: settings, searchOnly: searchOnly)
        if !items.contains(where: { $0.id == selection.providerID }) { items.insert(ChoiceOption(id: selection.providerID, title: "请选择服务", disabled: true), at: 0) }
        items.append(ChoiceOption(id: "add", title: "添加服务商…", icon: "plus", separatorBefore: true))
        return items
    }
    private var models: [ChoiceOption] {
        var items = AIModelChoices.models(function, provider: selection.providerID, settings: settings, available: model.availableModels, searchOnly: searchOnly)
        if !items.contains(where: { $0.id == selection.modelID }) {
            items.insert(ChoiceOption(id: selection.modelID, title: selection.modelID.isEmpty ? "待添加模型" : "模型已移除 · " + selection.modelID, disabled: true), at: 0)
        }
        return items
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("服务商").font(.system(size: 10)).foregroundStyle(.secondary)
                    ChoicePicker(title: function.label + "服务商", selection: selection.providerID, options: providers, menuSize: CGSize(width: 290, height: 360), searchable: providers.count > 8, fillsWidth: true) { provider in
                        if provider == "add" { onAdd() }
                        else { onSelect(settings.selection(in: provider, for: function, current: selection, searchOnly: searchOnly)) }
                    }
                }.frame(maxWidth: .infinity)
                VStack(alignment: .leading, spacing: 6) {
                    Text("模型").font(.system(size: 10)).foregroundStyle(.secondary)
                    ChoicePicker(title: function.label + "模型", selection: selection.modelID, options: models, menuSize: CGSize(width: 330, height: 340), searchable: models.count > 7, fillsWidth: true) { onSelect(AISelection(providerID: selection.providerID, modelID: $0)) }
                        .disabled(models.allSatisfy(\.disabled))
                }.frame(maxWidth: .infinity)
            }
            if selection.providerID != "codex", settings.profiles.contains(where: { $0.id == selection.providerID }), settings.models(in: selection.providerID, for: function, searchOnly: searchOnly).isEmpty {
                HStack(spacing: 6) {
                    Text("此服务还没有适用于\(function.label)的模型。").font(.system(size: 10)).foregroundStyle(.secondary)
                    Spacer(minLength: 2)
                    Button("管理模型") { onManage(selection.providerID) }.font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.accent).buttonStyle(FeedbackStyle(compact: true))
                }
            }
        }
    }
}

struct AIConnectionSettings: View {
    @EnvironmentObject var model: AppModel
    var capabilities = false
    @State private var editingProfile: APIProfile?
    @State private var editorSection = "connection"
    @State private var assignment: String?
    @State private var expandedProvider: String? = nil
    @State private var status = ""
    @State private var testing = false
    @State private var testTask: Task<Void, Never>?
    @State private var testID = UUID()
    @State private var showPath = false
    @State private var editingSearch = false
    private var settings: AppSettings { model.library.settings }
    private var primary: AISelection { settings.selection(.conversation) }
    private var defaultSettings: AppSettings { settings }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if capabilities {
                Text("跟随对话使用聊天中选择的模型；单独指定可混用其他服务。下方显示新对话的默认配置。").font(.system(size: 11)).foregroundStyle(.secondary).lineSpacing(4)
                conversationSummary
                ForEach(AIFunction.allCases.filter { $0 != .conversation }) { capability($0) }
                searchSection
            } else {
                SettingSection(title: "默认对话", subtitle: "先选择服务商，再选择模型。聊天顶部只切换此服务的模型。") {
                    AISelectionFields(function: .conversation, selection: primary, onSelect: { value in
                        model.setDefaultAISelection(value); status = ""
                    }, onAdd: { add(assignment: "default") }, onManage: manage)
                    if primary.providerID == "codex" {
                        HStack { Text("思考强度").font(.system(size: 11)).foregroundStyle(.secondary); Spacer(); effortPicker }
                    }
                    HStack(spacing: 8) {
                        if testing { ActivityIndicator() }
                        Text(status.isEmpty ? (primary.providerID == "codex" ? model.connectionStatus : primary.modelID.isEmpty ? "添加模型后即可测试连接。" : "可发送简短请求检查连接。") : status).font(.system(size: 10)).foregroundStyle(.secondary).lineSpacing(3)
                        Spacer(minLength: 8)
                        ActionButton(title: testing ? "停止测试" : "测试连接", icon: testing ? "stop" : "bolt") { if testing { testTask?.cancel() } else { test() } }.disabled(model.connecting || model.isRunning || primary.modelID.isEmpty)
                    }
                }
                serviceLibrary
                HStack { Text("读图、编排、校对、生图与搜索可以混用不同服务。").font(.system(size: 10)).foregroundStyle(.secondary); Spacer(); Button("分配 AI 功能 →") { model.settingsSection = "capabilities" }.font(.system(size: 11)).foregroundStyle(Theme.accent).buttonStyle(FeedbackStyle(compact: true)) }
            }
        }.padding(2)
            .sheet(item: $editingProfile) { profile in APIProfileEditor(profile: profile, assignment: assignment, initialSection: editorSection, onSaved: { expandedProvider = $0.id; resetTest() }).environmentObject(model).choiceHost() }
            .sheet(isPresented: $editingSearch) { SearchConfigurationEditor(configuration: settings.webSearch ?? WebSearchConfiguration()).environmentObject(model).choiceHost() }
            .onChange(of: primary) { _, _ in resetTest() }
            .onChange(of: settings.profiles) { _, _ in resetTest() }
            .onDisappear { resetTest() }
    }
    private func add(assignment: String? = nil) { editorSection = "connection"; self.assignment = assignment; editingProfile = ServicePreset.named("custom").newProfile }
    private func manage(_ id: String) { editorSection = "models"; assignment = nil; editingProfile = settings.profiles.first { $0.id == id } }
    private var effortPicker: some View {
        ChoicePicker(title: "思考强度", selection: settings.defaultEffort, options: (model.availableModels.first { $0.id == primary.modelID }?.efforts ?? ["low", "medium", "high"]).map { ChoiceOption(id: $0, title: ["low": "轻量", "medium": "标准", "high": "深入", "xhigh": "更深入", "max": "最高", "ultra": "Ultra"][$0] ?? $0) }) { value in model.updateSettings { $0.defaultEffort = value } }
    }
    private var serviceLibrary: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack { Text("已连接的服务").font(.system(size: 14, weight: .semibold)); Spacer(); ActionButton(title: "添加服务商", icon: "plus") { add() } }
            VStack(spacing: 0) {
                serviceRow(id: "codex", name: "本机 Codex", brand: "codex", models: settings.models(in: "codex", for: .conversation))
                ForEach(settings.profiles) { profile in
                    separator
                    serviceRow(id: profile.id, name: profile.name, brand: profile.brandID, models: profile.catalog)
                }
            }.background(Theme.panel, in: RoundedRectangle(cornerRadius: 12)).overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.border))
        }
    }
    private func serviceRow(id: String, name: String, brand: String, models: [APIModel]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Button { expandedProvider = expandedProvider == id ? nil : id } label: {
                    HStack(spacing: 11) {
                        BrandMark(id: brand, size: 22)
                        VStack(alignment: .leading, spacing: 4) { Text(name).font(.system(size: 12, weight: .semibold)); Text(models.isEmpty ? "尚未添加模型" : "\(models.count) 个模型").font(.system(size: 10)).foregroundStyle(.secondary) }
                        Spacer(minLength: 4)
                        if primary.providerID == id { Text("默认").font(.system(size: 9, weight: .medium)).foregroundStyle(Theme.accent).padding(.horizontal, 6).padding(.vertical, 3).background(Theme.accent.opacity(0.07), in: Capsule()) }
                        DisclosureChevron(expanded: expandedProvider == id).foregroundStyle(.secondary)
                    }.padding(.vertical, 12).padding(.leading, 14).contentShape(Rectangle())
                }.buttonStyle(FeedbackStyle(compact: true)).accessibilityLabel(name + "模型列表").accessibilityValue(expandedProvider == id ? "已展开" : "已收起")
                if id != "codex" { ActionButton(title: "编辑连接", icon: "slider.horizontal.3") { editorSection = "connection"; assignment = nil; editingProfile = settings.profiles.first { $0.id == id } }.accessibilityLabel("编辑连接 " + name).padding(.trailing, 12) }
                else { Spacer().frame(width: 10) }
            }
            if expandedProvider == id {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(models) { item in
                        HStack(spacing: 8) {
                            BrandMark(id: id == "codex" ? "openai" : brand, size: 15)
                            Text(id == "codex" ? Theme.modelName(item.id) : item.id).font(.system(size: 11)).lineLimit(1).help(item.id)
                            Spacer(minLength: 4)
                            Text(item.label).font(.system(size: 9)).foregroundStyle(.secondary)
                            if primary.providerID == id && primary.modelID == item.id { Image(systemName: "checkmark").font(.system(size: 10, weight: .semibold)).foregroundStyle(Theme.accent) }
                        }.padding(.vertical, 9)
                    }
                    if models.isEmpty { Text("连接已保存。添加模型后，即可用于对话或分配给其他功能。").font(.system(size: 11)).foregroundStyle(.secondary).lineSpacing(4).padding(.vertical, 10) }
                    if id == "codex" {
                        Button { showPath.toggle() } label: { HStack(spacing: 8) { DisclosureChevron(expanded: showPath); Text("本机连接选项").font(.system(size: 10)) } }.buttonStyle(FeedbackStyle(compact: true)).padding(.vertical, 8)
                        if showPath { codexFields }
                    } else {
                        Button("管理模型 →") { manage(id) }.font(.system(size: 11)).foregroundStyle(Theme.accent).buttonStyle(FeedbackStyle(compact: true)).padding(.vertical, 9)
                    }
                }.padding(.leading, 47).padding(.trailing, 18).padding(.bottom, 9)
            }
        }
    }
    private var conversationSummary: some View {
        SettingSection(title: "日常对话", subtitle: "聊天、查找笔记与总结；聊天顶部可临时切换。") {
            HStack(spacing: 10) { selectionSummary(primary); Spacer(); ActionButton(title: "对话设置", icon: "arrow.up.right") { model.settingsSection = "ai" }.fixedSize() }
        }
    }
    private func selectionSummary(_ selected: AISelection) -> some View {
        HStack(spacing: 8) {
            BrandMark(id: selected.providerID == "codex" ? "codex" : settings.profiles.first { $0.id == selected.providerID }?.brandID ?? "custom", size: 17)
            Text(selected.providerID == "codex" ? "本机 Codex" : settings.profiles.first { $0.id == selected.providerID }?.name ?? "待选择服务").font(.system(size: 11)).foregroundStyle(.secondary)
            Image(systemName: "chevron.right").font(.system(size: 8)).foregroundStyle(.tertiary)
            Text(selected.modelID.isEmpty ? "待选择模型" : Theme.modelName(selected.modelID)).font(.system(size: 11, weight: .medium)).lineLimit(1)
        }
    }
    private func capability(_ function: AIFunction) -> some View {
        let selection = settings.selection(function)
        let mode = function == .image ? (selection.providerID == "none" ? "off" : "custom") : (settings.routes[function.rawValue] == nil ? "inherit" : "custom")
        let descriptions: [AIFunction: String] = [.recognition: "识别上传图片中的内容", .organize: "编排笔记与章节", .verify: "核对知识并补充解释", .image: "按需生成学习插图"]
        let problem: String? = { do { try settings.validate(selection, for: function); return nil } catch { return error.localizedDescription } }()
        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 4) { Text(function.label).font(.system(size: 13, weight: .semibold)); Text(descriptions[function] ?? "").font(.system(size: 10)).foregroundStyle(.secondary) }
                Spacer()
                ChoicePicker(title: function.label + "分配方式", selection: mode, options: function == .image ? [ChoiceOption(id: "off", title: "不启用"), ChoiceOption(id: "custom", title: "单独指定")] : [ChoiceOption(id: "inherit", title: "跟随对话"), ChoiceOption(id: "custom", title: "单独指定")], width: 136) { value in
                    model.updateSettings { s in
                        if value == "inherit" { s.assign(function, to: nil) }
                        else if value == "off" { s.assign(function, to: AISelection(providerID: "none", modelID: "")) }
                        else { s.assign(function, to: s.selection(in: primary.providerID, for: function, current: selection)) }
                    }
                }
            }
            if mode == "custom" {
                AISelectionFields(function: function, selection: selection, onSelect: { value in model.updateSettings { $0.assign(function, to: value) } }, onAdd: { add(assignment: function.rawValue) }, onManage: manage)
            } else if mode == "inherit" { selectionSummary(primary) }
            if function != .image, mode != "off", let problem { Label(problem, systemImage: "exclamationmark.circle").font(.system(size: 10)).foregroundStyle(.orange).lineSpacing(3) }
            if mode == "off" { Text("文字笔记正常使用；需要插图时再选择服务。 ").font(.system(size: 10)).foregroundStyle(.secondary) }
            if function == .image && mode != "off" { CapabilityTestPanel(kind: .image, settings: settings) }
        }.padding(16).frame(maxWidth: .infinity, alignment: .leading).background(Theme.panel, in: RoundedRectangle(cornerRadius: 12)).overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.border))
    }
    private var searchSection: some View {
        let search = settings.webSearch ?? WebSearchConfiguration()
        return SettingSection(title: "联网查阅", subtitle: "为对话与知识校对提供网页来源。") {
            HStack(spacing: 10) { Label(search.title, systemImage: "globe").font(.system(size: 11, weight: .medium)); Spacer(); ActionButton(title: "配置搜索", icon: "slider.horizontal.3") { editingSearch = true }.fixedSize() }
            if search.mode == "builtin" {
                selectionSummary(settings.selection(.verify))
            } else if search.mode == "model", let selected = search.selection { selectionSummary(selected) }
            else if let host = URL(string: search.baseURL)?.host { Text(host).font(.system(size: 10)).foregroundStyle(.secondary) }
            CapabilityTestPanel(kind: .search, settings: settings, hint: settings.onlineVerification ? "验证当前配置与网页来源。" : "校对联网已关闭，仍可单独测试。")
        }
    }
    private var codexFields: some View {
        VStack(alignment: .leading, spacing: 0) {
            separator
            Text("连接电脑上已登录的 Codex，无需额外填写 API 密钥。").font(.system(size: 11)).foregroundStyle(.secondary).lineSpacing(5).padding(.vertical, 16)
            HStack { VStack(alignment: .leading, spacing: 5) { Text("Codex 可执行文件").font(.system(size: 13)); Text(model.library.settings.codexPath.isEmpty ? "自动查找本机安装" : URL(fileURLWithPath: model.library.settings.codexPath).lastPathComponent).font(.system(size: 10)).foregroundStyle(.secondary) }; Spacer(); EmptyView() }.padding(.vertical, 14)
            Group {
                HStack { TextField("留空自动查找", text: Binding(get: { model.library.settings.codexPath }, set: { value in model.updateSettings { $0.codexPath = value } })).textFieldStyle(FieldStyle()).font(.system(size: 10, design: .monospaced)); QuietIconButton(icon: "folder", label: "选择可执行文件") { let panel = NSOpenPanel(); panel.canChooseDirectories = false; if panel.runModal() == .OK, let url = panel.url { model.updateSettings { $0.codexPath = url.path } } } }.padding(.bottom, 12)
                ActionButton(title: "恢复自动查找", icon: "arrow.uturn.backward") { model.updateSettings { $0.codexPath = "" }; model.connect() }.disabled(model.connecting || model.isRunning).padding(.bottom, 10)
                ActionButton(title: "重新连接", icon: "arrow.clockwise") { model.connect() }.disabled(model.connecting || model.isRunning).padding(.bottom, 14)
            }
            separator
        }
    }
    private var separator: some View { Rectangle().fill(Theme.border).frame(height: 1) }
    private func resetTest() { testID = UUID(); testTask?.cancel(); testing = false; status = "" }
    private func test() {
        let selection = primary; let snapshot = defaultSettings; let identifier = UUID(); testID = identifier
        testing = true; status = "正在验证…"
        testTask = Task {
            defer { if testID == identifier { testing = false } }
            do {
                try snapshot.validate(selection, for: .conversation)
                try await model.ai.probeConversation(selection: selection, settings: snapshot) { title, _, phase in
                    guard testID == identifier else { return }
                    if title == "验证笔记整理", phase == "running" { status = "正在验证笔记整理…" }
                }
                guard testID == identifier else { return }; try Task.checkCancellation()
                status = "对话与笔记整理测试通过"
                if selection.providerID == "codex" { model.availableModels = model.ai.codex.models; model.connectionStatus = "Codex 已连接"; model.imageSkillAvailable = model.ai.codex.imageSkillPath != nil && model.ai.codex.supportsImageGeneration }
            } catch { if testID == identifier { status = Task.isCancelled ? "测试已停止" : error.localizedDescription } }
        }
    }
}

struct SearchConfigurationEditor: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State var configuration: WebSearchConfiguration
    @State private var key = ""
    @State private var readingKey = true
    @State private var keyReadTask: Task<Void, Never>?
    @State private var keyUnavailable = false
    @State private var needsReplacementKey = false
    @State private var status = ""
    @State private var problem = ""
    @State private var busy = false
    @State private var searchDrafts: [String: (WebSearchConfiguration, String)] = [:]
    @State private var editingProfile: APIProfile?
    var body: some View {
        VStack(spacing: 0) {
            HStack { VStack(alignment: .leading, spacing: 4) { Text("联网查阅").font(.system(size: 19, weight: .semibold)); Text("独立配置搜索，也可沿用校对模型。").font(.system(size: 11)).foregroundStyle(.secondary) }; Spacer(); QuietIconButton(icon: "xmark", label: "关闭搜索配置") { dismiss() }.keyboardShortcut(.cancelAction) }.padding(22)
            Rectangle().fill(Theme.border).frame(height: 1)
            ScrollViewReader { scroll in
                ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack { Text("搜索方式").font(.system(size: 12)); Spacer(); ChoicePicker(title: "搜索方式", selection: configuration.mode, options: [ChoiceOption(id: "builtin", title: "沿用校对模型", subtitle: "由校对模型调用联网工具，无需单独密钥"), ChoiceOption(id: "model", title: "指定搜索模型", subtitle: "选择另一个具备联网能力的模型"), ChoiceOption(id: "tavily", title: "Tavily 兼容 API", subtitle: "官方服务或兼容的自定义地址"), ChoiceOption(id: "brave", title: "Brave 兼容 API", subtitle: "官方服务或兼容的自定义地址")], width: 270, menuSize: CGSize(width: 360, height: 290)) { value in
                        chooseMode(value)
                    }.disabled(busy || readingKey).help("模型搜索需要支持联网工具；也可选择独立搜索 API。") }

                    if configuration.mode == "model" {
                        AISelectionFields(function: .verify, selection: configuration.selection ?? model.library.settings.selection(in: "codex", for: .verify), searchOnly: true, onSelect: { configuration.selection = $0 }, onAdd: { editingProfile = ServicePreset.named("custom").newProfile }, onManage: { id in editingProfile = model.library.settings.profiles.first { $0.id == id } }).disabled(busy)
                    } else if ["tavily", "brave"].contains(configuration.mode) {
                        VStack(alignment: .leading, spacing: 7) { Text("搜索接口地址").font(.system(size: 11)).foregroundStyle(.secondary); TextField("HTTPS 根地址或完整搜索地址", text: $configuration.baseURL).textFieldStyle(FieldStyle()).accessibilityLabel("搜索接口根地址").help("可填写官方或兼容服务的根地址，也可粘贴完整搜索地址。") }.disabled(busy)
                        VStack(alignment: .leading, spacing: 7) { Text("搜索 API 密钥").font(.system(size: 11)).foregroundStyle(.secondary); SecureField("保存在本机；本机免密服务可留空", text: $key).textFieldStyle(FieldStyle()).accessibilityLabel("搜索 API 密钥") }.disabled(busy || readingKey || keyUnavailable)
                        if readingKey { Text("正在读取已保存的密钥…").font(.system(size: 10)).foregroundStyle(.secondary) }
                        if keyUnavailable { ActionButton(title: "重试读取", icon: "arrow.clockwise") { keyReadTask?.cancel(); keyReadTask = Task { await loadKey() } }.disabled(readingKey) }
                    }
                    CapabilityTestPanel(kind: .search, settings: model.library.settings, searchConfiguration: configuration, credential: configuration.usesAPI ? key.trimmingCharacters(in: .whitespacesAndNewlines) : nil, disabled: readingKey || keyUnavailable || (configuration.usesAPI && needsReplacementKey && key.isEmpty), onBusyChange: { busy = $0 }).id("search-test-result")
                    if !problem.isEmpty { Label(problem, systemImage: "exclamationmark.circle").font(.system(size: 11)).foregroundStyle(.red).lineSpacing(4).textSelection(.enabled) }
                }.padding(22)
                }.onChange(of: busy) { wasBusy, isBusy in
                    if wasBusy && !isBusy { scroll.scrollTo("search-test-result", anchor: .bottom) }
                }
            }
            Rectangle().fill(Theme.border).frame(height: 1)
            HStack { Spacer(); ActionButton(title: "取消") { dismiss() }; ActionButton(title: "保存配置", primary: true) { do { try model.saveSearchConfiguration(configuration, credential: key); model.toast = "搜索配置已保存"; dismiss() } catch { problem = error.localizedDescription } }.disabled(busy || readingKey || keyUnavailable || (configuration.usesAPI && needsReplacementKey && key.isEmpty)) }.padding(18)
        }.frame(width: 640, height: configuration.usesAPI ? 480 : 360).background(Theme.panel)
            .sheet(item: $editingProfile) { profile in APIProfileEditor(profile: profile).environmentObject(model).choiceHost() }
            .task { await loadKey() }
            .onDisappear { keyReadTask?.cancel() }
    }
    private func chooseMode(_ mode: String) {
        guard mode != configuration.mode else { return }
        searchDrafts[configuration.mode] = (configuration, key)
        if let draft = searchDrafts[mode] { configuration = draft.0; key = draft.1 }
        else {
            configuration.mode = mode; key = ""
            if mode == "model" { configuration.selection = model.library.settings.selection(in: "codex", for: .verify) }
            if mode == "tavily" { configuration.baseURL = "https://api.tavily.com" }
            if mode == "brave" { configuration.baseURL = "https://api.search.brave.com" }
        }
        problem = ""; keyUnavailable = false; needsReplacementKey = false
    }
    private func loadKey() async {
        guard configuration.usesAPI else { readingKey = false; return }
        readingKey = true
        do { let loaded = try await model.ai.credentials.readAsync(configuration.keyID); try Task.checkCancellation(); key = loaded; keyUnavailable = false; needsReplacementKey = false; problem = "" }
        catch { if !Task.isCancelled { needsReplacementKey = (error as? CredentialStore.Failure) == .legacyUnavailable; keyUnavailable = !needsReplacementKey; problem = needsReplacementKey ? "" : error.localizedDescription } }
        readingKey = false
    }
}

enum CapabilityTestKind { case image, search }

struct CapabilityTestPanel: View {
    @EnvironmentObject private var model: AppModel
    var kind: CapabilityTestKind
    var settings: AppSettings
    var searchConfiguration: WebSearchConfiguration? = nil
    var credential: String? = nil
    var hint: String? = nil
    var disabled = false
    var onBusyChange: (Bool) -> Void = { _ in }
    @State private var busy = false
    @State private var status = ""
    @State private var failed = false
    @State private var preview: NSImage?
    @State private var sources: [WebSearchSource] = []
    @State private var task: Task<Void, Never>?
    @State private var service: AIService?
    @State private var identifier = UUID()
    private var configuration: WebSearchConfiguration { searchConfiguration ?? settings.webSearch ?? WebSearchConfiguration() }
    private var configurationProblem: String? {
        do {
            if kind == .image { try settings.validate(settings.selection(.image), for: .image) }
            else { _ = try configuration.validated(settings: settings) }
            return nil
        } catch { return error.localizedDescription }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 12) {
                Text(hint ?? (kind == .image ? "生成一张测试图，可能产生服务商费用。" : "测试不保存配置，也不会加入对话。"))
                    .font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                    .help(kind == .image ? "使用当前生图配置生成测试图，测试结束清理临时文件。" : "测试只发送固定公开问题并检查网页来源，不发送笔记或历史对话。")
                Spacer(minLength: 0)
                ActionButton(title: busy ? "停止测试" : kind == .image ? "测试生图" : "测试搜索", icon: busy ? "stop" : "play") {
                    if busy { reset(); status = "测试已停止" } else { start() }
                }.fixedSize().disabled(!busy && (disabled || configurationProblem != nil)).accessibilityIdentifier(kind == .image ? "test-assigned-image" : "test-assigned-search")
            }
            if let problem = configurationProblem, status.isEmpty {
                Label(problem, systemImage: "info.circle").font(.system(size: 10)).foregroundStyle(.secondary).lineSpacing(3)
            }
            if !status.isEmpty {
                HStack(alignment: .top, spacing: 8) {
                    if busy { ActivityIndicator(size: 13) }
                    else { Image(systemName: failed ? "exclamationmark.circle" : preview != nil || !sources.isEmpty ? "checkmark.circle" : "info.circle").frame(width: 14) }
                    Text(status).font(.system(size: 11)).lineSpacing(3).textSelection(.enabled).id(status)
                }.foregroundStyle(failed ? Color.red : Theme.accent)
            }
            if let preview {
                HStack(spacing: 12) {
                    Image(nsImage: preview).resizable().scaledToFit().frame(width: 86, height: 86).background(Theme.panel, in: RoundedRectangle(cornerRadius: 8)).clipShape(RoundedRectangle(cornerRadius: 8)).accessibilityLabel("生图测试结果")
                    Text("已收到可用图片\n测试图片不会加入笔记或对话。").font(.system(size: 10)).foregroundStyle(.secondary).lineSpacing(4)
                    Spacer(minLength: 0)
                }.padding(10).background(Theme.secondary, in: RoundedRectangle(cornerRadius: 9))
            }
            if !sources.isEmpty {
                VStack(alignment: .leading, spacing: 7) {
                    ForEach(Array(sources.prefix(3))) { source in
                        if let url = URL(string: source.url) {
                            Link(destination: url) {
                                HStack(spacing: 8) { Image(systemName: "globe").frame(width: 14); Text(source.title).lineLimit(1); Spacer(minLength: 4); Text(url.host ?? "").font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(1); Image(systemName: "arrow.up.right").font(.system(size: 9)) }
                                    .font(.system(size: 11)).padding(.horizontal, 10).frame(height: 32).contentShape(Rectangle())
                            }.buttonStyle(FeedbackStyle(compact: true)).help(source.url)
                        }
                    }
                }.padding(5).background(Theme.secondary, in: RoundedRectangle(cornerRadius: 9))
            }
        }.onChange(of: settings) { _, _ in reset() }
            .onChange(of: searchConfiguration) { _, _ in reset() }
            .onChange(of: credential) { _, _ in reset() }
            .onDisappear { reset() }
    }
    private func reset() {
        identifier = UUID(); task?.cancel(); service?.codex.disconnect(); service = nil
        busy = false; status = ""; failed = false; preview = nil; sources = []; onBusyChange(false)
    }
    private func start() {
        reset()
        let id = UUID(); identifier = id
        let snapshot = settings; let search = configuration; let key = credential
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("NoteLibrary-CapabilityTest-" + id.uuidString, isDirectory: true)
        let tester = model.ai.isolatedProbe(workspace: folder); service = tester
        busy = true; onBusyChange(true); status = kind == .image ? "正在生成测试图…" : "正在检索并核对网页来源…"
        task = Task {
            defer {
                tester.codex.disconnect(); try? FileManager.default.removeItem(at: folder)
                if identifier == id { busy = false; service = nil; onBusyChange(false) }
            }
            do {
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                if kind == .image {
                    let url = try await tester.generateImage(prompt: "白色背景上的一片绿色叶子，简洁清楚，无文字。", model: snapshot.selection(.image).modelID, effort: "low", settings: snapshot) { _, _, _ in }
                    let image = NSImage(data: try Data(contentsOf: url))
                    try Task.checkCancellation(); guard identifier == id else { return }
                    guard let image else { throw AppFailure(message: "收到的文件无法显示为图片。") }
                    preview = image; status = "生图测试通过"
                } else {
                    let result = try await tester.probeSearch(settings: snapshot, configuration: search, credential: key)
                    try Task.checkCancellation(); guard identifier == id else { return }
                    sources = result; status = "搜索测试通过 · 返回 \(result.count) 条网页来源"
                }
            } catch {
                guard identifier == id else { return }
                failed = !Task.isCancelled; status = Task.isCancelled ? "测试已停止" : error.localizedDescription
            }
        }
    }
}
