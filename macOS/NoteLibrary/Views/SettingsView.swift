import SwiftUI
import AppKit

struct SettingSection<Content: View>: View {
    var title: String
    var subtitle = ""
    @ViewBuilder var content: Content
    var body: some View { VStack(alignment: .leading, spacing: 16) { VStack(alignment: .leading, spacing: 5) { Text(title).font(.system(size: 14, weight: .semibold)); if !subtitle.isEmpty { Text(subtitle).font(.system(size: 11)).foregroundStyle(.secondary) } }; content }.padding(20).frame(maxWidth: .infinity, alignment: .leading).background(Theme.panel, in: RoundedRectangle(cornerRadius: 14)).overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.border)) }
}
struct SettingsView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) var dismiss
    @Environment(\.accessibilityReduceMotion) var reduced
    @EnvironmentObject private var choices: ChoiceCenter
    @State private var scrollPosition = ScrollPosition(edge: .top)
    private var section: String { model.settingsSection }
    @State private var editingProfile: APIProfile?
    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Text("偏好设置").font(.system(size: 21, weight: .semibold)).padding(.horizontal, 12).padding(.top, 20).padding(.bottom, 18)
                settingTab("服务与模型", "sparkles", "ai")
                settingTab("AI 功能分配", "slider.horizontal.3", "capabilities")
                settingTab("整理与对话", "text.badge.checkmark", "organize")
                settingTab("阅读与外观", "textformat.size", "appearance")
                settingTab("数据与备份", "externaldrive", "data")
                Spacer()
                Text("NoteLibrary \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "开发版")\n本地笔记与阅读").font(.system(size: 10)).foregroundStyle(.tertiary).lineSpacing(6).padding(12)
            }.padding(14).frame(width: 192).background(Theme.background)
            Rectangle().fill(Theme.border).frame(width: 1)
            VStack(spacing: 0) {
                HStack { Text(["ai": "服务与模型", "capabilities": "AI 功能分配", "organize": "整理与对话", "appearance": "阅读与外观", "data": "数据与备份"][section] ?? "设置").font(.system(size: 17, weight: .semibold)); Spacer(); QuietIconButton(icon: "xmark", label: "关闭设置") { dismiss() }.keyboardShortcut(.cancelAction) }.padding(.horizontal, 26).padding(.vertical, 18)
                ScrollView { VStack(alignment: .leading, spacing: 16) { if section == "ai" { AIConnectionSettings() } else if section == "capabilities" { AIConnectionSettings(capabilities: true) } else if section == "organize" { organizeSettings } else if section == "appearance" { appearanceSettings } else { dataSettings } }.padding(.horizontal, 24).padding(.bottom, 24).frame(maxWidth: .infinity, alignment: .leading) }.scrollIndicators(.automatic).scrollPosition($scrollPosition)
                    .onChange(of: section) { _, _ in scrollPosition.scrollTo(edge: .top) }
            }.background(Theme.background.opacity(0.45))
        }.frame(width: 880, height: 640).background(Theme.panel).textFieldStyle(FieldStyle()).buttonStyle(FeedbackStyle())
            .sheet(item: $editingProfile) { profile in APIProfileEditor(profile: profile).environmentObject(model).choiceHost() }
            .sheet(isPresented: Binding(get: { model.restoreCandidateURL != nil }, set: { if !$0 { model.restoreCandidateURL = nil } })) {
                VStack(alignment: .leading, spacing: 18) {
                    Label("恢复这份备份", systemImage: "arrow.counterclockwise").font(.system(size: 20, weight: .semibold))
                    Text(model.restoreCandidateURL?.lastPathComponent ?? "").font(.system(size: 13, weight: .medium))
                    Text("当前资料库会先保留一份完整备份，再切换到所选资料。").font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(5)
                    HStack { Spacer(); ActionButton(title: "取消") { model.restoreCandidateURL = nil }.keyboardShortcut(.cancelAction); ActionButton(title: "恢复资料", primary: true) { model.confirmRestoreBackup() } }
                }.padding(28).frame(width: 480).background(Theme.panel).environmentObject(model).choiceHost()
            }
    }
    private func binding<T>(_ keyPath: WritableKeyPath<AppSettings, T>) -> Binding<T> { Binding(get: { model.library.settings[keyPath: keyPath] }, set: { value in model.updateSettings { $0[keyPath: keyPath] = value } }) }
    private var providers: [ChoiceOption] { [ChoiceOption(id: "codex", title: "本机 Codex", icon: "desktopcomputer")] + model.library.settings.profiles.map { ChoiceOption(id: $0.id, title: $0.name, subtitle: $0.model, icon: "network") } }
    private func settingTab(_ title: String, _ icon: String, _ id: String) -> some View { Button { guard section != id else { return }; choices.presentation = nil; model.settingsSection = id } label: { HStack(spacing: 10) { Image(systemName: icon).frame(width: 18); Text(title); Spacer() }.font(.system(size: 12, weight: .medium)).padding(12) }.buttonStyle(SidebarButtonStyle(selected: section == id)).accessibilityAddTraits(section == id ? .isSelected : []).accessibilityIdentifier("settings-tab-" + id) }
    @ViewBuilder private var organizeSettings: some View {
        SettingSection(title: "内容整理", subtitle: "关键疑问解决后自动保存，每次修改留下可撤销记录。") {
            HStack { Text("正文语言").font(.system(size: 12)); Spacer(); TextField("语言", text: binding(\.language)).frame(width: 185) }
            HStack { Text("补充程度").font(.system(size: 12)); Spacer(); ChoicePicker(title: "补充程度", selection: model.library.settings.detail, options: [ChoiceOption(id: "适度补充解释和例子", title: "适度补充解释和例子"), ChoiceOption(id: "尽量忠于原稿，只补充必要上下文", title: "尽量忠于原稿")]) { value in model.updateSettings { $0.detail = value } } }
            SwitchRow(title: "校对时查阅联网资料", detail: "搜索服务在 AI 功能分配中选择，可以与文字模型分开。", isOn: binding(\.onlineVerification))
        }
        SettingSection(title: "对话与上下文") {
            SwitchRow(title: "自动压缩长对话", detail: "生成早期记忆并保留近期全文。不会删除任何原始消息。", isOn: Binding(get: { model.library.settings.autoCompact != false }, set: { value in model.updateSettings { $0.autoCompact = value } }))
            HStack { Text("压缩触发长度").font(.system(size: 12)); Spacer(); ChoicePicker(title: "压缩触发长度", selection: String(model.library.settings.compactAfterCharacters ?? 24000), options: [ChoiceOption(id: "12000", title: "约 1.2 万字符"), ChoiceOption(id: "24000", title: "约 2.4 万字符"), ChoiceOption(id: "48000", title: "约 4.8 万字符")]) { value in model.updateSettings { $0.compactAfterCharacters = Int(value) } } }
            Text("活跃消息达到 28 条时也会压缩。这是应用的整理阈值，不代表模型的最大容量。").font(.system(size: 10)).foregroundStyle(.secondary).lineSpacing(4)
            SwitchRow(title: "Enter 发送", detail: "开启后用 Shift Enter 换行；始终支持 ⌘ Enter 发送。", isOn: binding(\.enterSends))
            SwitchRow(title: "显示消息时间", isOn: Binding(get: { model.library.settings.showMessageTime != false }, set: { value in model.updateSettings { $0.showMessageTime = value } }))
        }
    }
    @ViewBuilder private var appearanceSettings: some View {
        SettingSection(title: "界面外观") {
            HStack(spacing: 10) {
                appearanceOption("跟随系统", icon: "desktopcomputer", value: "system")
                appearanceOption("浅色", icon: "sun.max", value: "light")
                appearanceOption("深色", icon: "moon", value: "dark")
            }.background(ThemeTransitionAnchor())
            SwitchRow(title: "减少动态效果", detail: "关闭位移、缩放和循环动画，保留清楚的状态反馈。", isOn: binding(\.reduceMotion))
        }
        SettingSection(title: "书架布局", subtitle: "选择后立即生效，自动记住你的偏好。") {
            HStack(alignment: .top, spacing: 12) {
                ForEach(BookshelfLayoutStyle.allCases) { style in
                    bookshelfLayoutOption(style)
                }
            }
            Label("仅调整书架，对话的阅读布局单独设置。", systemImage: "info.circle")
                .font(.system(size: 10)).foregroundStyle(.secondary)
        }
        SettingSection(title: "阅读排版") {
            adjust("正文字号", value: binding(\.fontSize), range: 13...23)
            adjust("段内行距", value: binding(\.lineSpacing), range: 2...14)
            Text("知识在积累中逐渐清晰。\n每一篇笔记，都能与原稿相互对照。").font(.system(size: model.library.settings.fontSize)).lineSpacing(model.library.settings.lineSpacing).padding(18).frame(maxWidth: .infinity, alignment: .leading).background(Theme.background, in: RoundedRectangle(cornerRadius: 11))
            SwitchRow(title: "阅读时显示原稿对照", detail: "也可以在每篇笔记的工具栏随时切换。", isOn: binding(\.showOriginal))
        }
    }
    private func bookshelfLayoutOption(_ style: BookshelfLayoutStyle) -> some View {
        let selected = BookshelfLayoutStyle.resolved(model.library.settings.bookshelfLayout) == style
        return Button {
            guard !selected else { return }
            model.updateSettings { $0.bookshelfLayout = style.rawValue }
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                BookshelfLayoutPreview(style: style)
                HStack(spacing: 8) {
                    Text(style.title).font(.system(size: 12, weight: .semibold))
                    Spacer(minLength: 0)
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 15)).foregroundStyle(selected ? Theme.accent : Color.secondary)
                }
                Text(style.detail).font(.system(size: 11)).foregroundStyle(.secondary)
                    .lineSpacing(3).frame(maxWidth: .infinity, alignment: .leading)
            }.padding(13).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
        }.buttonStyle(FeedbackStyle())
            .background(selected ? Theme.accent.opacity(0.055) : Theme.background, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(selected ? Theme.accent.opacity(0.65) : Theme.border, lineWidth: 1).allowsHitTesting(false))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("书架布局：" + style.title)
            .accessibilityValue(selected ? "已选择" : "未选择")
            .accessibilityHint(style.detail)
            .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
            .accessibilityIdentifier("bookshelf-layout-" + style.rawValue)
    }
    private func appearanceOption(_ title: String, icon: String, value: String) -> some View {
        let selected = model.library.settings.appearance == value
        return Button {
            guard !selected else { return }
            model.updateSettings { $0.appearance = value }
        } label: {
            HStack(spacing: 9) {
                Image(systemName: icon).font(.system(size: 17, weight: .regular)).frame(width: 23)
                Text(title).font(.system(size: 12, weight: .medium))
                Spacer(minLength: 3)
                Image(systemName: "checkmark.circle.fill").font(.system(size: 13)).opacity(selected ? 1 : 0)
            }.padding(.horizontal, 13).frame(maxWidth: .infinity, minHeight: 54).contentShape(Rectangle())
        }.buttonStyle(FeedbackStyle(selected: selected))
            .background(Theme.secondary, in: RoundedRectangle(cornerRadius: 11))
            .overlay(RoundedRectangle(cornerRadius: 11).stroke(selected ? Theme.accent.opacity(0.35) : Theme.border).allowsHitTesting(false))
            .accessibilityLabel("主题：" + title).accessibilityValue(selected ? "已选择" : "未选择")
            .accessibilityIdentifier("appearance-" + value)
    }
    @ViewBuilder private var dataSettings: some View {
        SettingSection(title: "这台 Mac 上的资料") {
            HStack(spacing: 16) { TagPill(text: "\(model.library.notebooks.count) 本笔记本"); TagPill(text: "\(model.library.notes.filter { $0.deletedAt == nil }.count) 篇笔记"); TagPill(text: "\(model.library.assets.count) 张图片") }
            ActionButton(title: "在 Finder 中查看", icon: "folder") { if let root = model.database?.root { NSWorkspace.shared.open(root) } }
        }
        SettingSection(title: "备份与恢复", subtitle: "完整备份包含笔记、对话、原稿和生成的图示。") {
            SwitchRow(title: "修改前自动保留快照", detail: "保留最近 40 份结构快照。", isOn: binding(\.automaticSnapshots))
            HStack { ActionButton(title: "导出完整备份", icon: "square.and.arrow.up") { model.exportBackup() }; ActionButton(title: "从备份恢复", icon: "arrow.counterclockwise") { model.restoreBackup() }.disabled(model.isRunning) }
            ActionButton(title: "查看修改记录", icon: "clock.arrow.circlepath") { model.openHistoryFromSettings() }
        }
        SettingSection(title: "资料与 AI 请求") { Text("笔记保存在本机。使用云端 AI 时，本次任务所需的图片、相关笔记和对话摘要会发给所选服务。API 密钥不会写进备份。").font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(5) }
    }
    private func adjust(_ title: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View { HStack { Text(title).font(.system(size: 12)); Spacer(); QuietIconButton(icon: "minus", label: "减小" + title) { value.wrappedValue = max(range.lowerBound, value.wrappedValue - 1) }.disabled(value.wrappedValue <= range.lowerBound); Text("\(Int(value.wrappedValue))").font(.system(size: 12)).monospacedDigit().frame(width: 30); QuietIconButton(icon: "plus", label: "增大" + title) { value.wrappedValue = min(range.upperBound, value.wrappedValue + 1) }.disabled(value.wrappedValue >= range.upperBound) } }
    private func effortLabel(_ value: String) -> String { ["low": "轻量", "medium": "标准", "high": "深入", "xhigh": "更深入", "max": "最高", "ultra": "Ultra"][value] ?? value }
    private func chooseCodex() { let panel = NSOpenPanel(); panel.canChooseDirectories = false; if panel.runModal() == .OK, let url = panel.url { model.updateSettings { $0.codexPath = url.path } } }

}


private struct BookshelfLayoutPreview: View {
    let style: BookshelfLayoutStyle
    var body: some View {
        GeometryReader { geometry in
            let layout = BookshelfLayout(availableWidth: 1800, style: style)
            let scale = geometry.size.width / 1800
            HStack(alignment: .top, spacing: layout.spacing * scale) {
                ForEach(0..<layout.columns, id: \.self) { _ in
                    VStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 3).fill(Theme.accent.opacity(0.34))
                            .frame(height: layout.coverHeight * scale)
                        Capsule().fill(Color.secondary.opacity(0.28)).frame(height: 2)
                        Capsule().fill(Color.secondary.opacity(0.15)).frame(height: 2).padding(.trailing, 7)
                    }.padding(3).frame(width: layout.cardWidth * scale, height: layout.cardHeight * scale, alignment: .top)
                        .background(Theme.panel, in: RoundedRectangle(cornerRadius: 4))
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Theme.border))
                }
            }.frame(width: geometry.size.width, height: geometry.size.height, alignment: .center)
        }.frame(height: 74).padding(.horizontal, 4)
            .background(Theme.secondary.opacity(0.65), in: RoundedRectangle(cornerRadius: 7))
            .accessibilityHidden(true)
    }
}

struct APIProfileEditor: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduced
    @State var profile: APIProfile
    var assignment: String? = nil
    var initialSection = "connection"
    var onSaved: (APIProfile) -> Void = { _ in }
    @State private var key = ""
    @State private var storedKey = ""
    @State private var readingKey = true
    @State private var keyUnavailable = false
    @State private var needsReplacementKey = false
    @State private var replacingKey = false
    @State private var removingKey = false
    @FocusState private var keyFocused: Bool
    @State private var items: [APIModel] = []
    @State private var discovered: [String] = []
    @State private var modelDraft: APIModel?
    @State private var editingID: String?
    @State private var showDiscovered = false
    @State private var connectionOptions = false
    @State private var status = ""
    @State private var problem = ""
    @State private var busy = false
    @State private var operation: Task<Void, Never>?
    @State private var testingID = ""
    @State private var testImage: NSImage?
    @State private var confirmRemoval = false
    @State private var gallery = false
    @FocusState private var focusedPreset: String?
    @State private var keyboardNavigation = false
    @State private var returningToGallery = false
    @State private var presetDrafts: [String: PresetDraft] = [:]
    private struct PresetDraft {
        var profile: APIProfile
        var key: String
        var items: [APIModel]
        var section: String
        var options: Bool
        var testingID: String
    }
    private var reducePageMotion: Bool { reduced || model.library.settings.reduceMotion }
    private var pageMotion: Animation? { reducePageMotion ? nil : .easeOut(duration: 0.22) }
    private var pageTransition: AnyTransition {
        guard !reducePageMotion else { return .identity }
        // Clear the outgoing text before the next page becomes legible. The
        // sheet, close button, and Cancel remain stationary throughout.
        return .asymmetric(
            insertion: .opacity.animation(.timingCurve(0.2, 0, 0, 1, duration: 0.16).delay(0.06)),
            removal: .opacity.animation(.easeIn(duration: 0.08)))
    }
    @State private var presetQuery = ""
    @State private var section = "connection"
    @State private var initialized = false
    @State private var contentPosition = ScrollPosition(edge: .top)
    @State private var temporaryFolder = FileManager.default.temporaryDirectory.appendingPathComponent("NoteLibrary-ConnectionTest-" + UUID().uuidString, isDirectory: true)
    private var existing: Bool { model.library.settings.profiles.contains { $0.id == profile.id } }
    private var preset: ServicePreset { ServicePreset.named(profile.presetID) }
    private var usesPreset: Bool { preset.id != "custom" }
    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .topLeading) {
                if initialized {
                    if gallery {
                        VStack(spacing: 0) { pageHeader(gallery: true); presetGallery }
                            .transition(pageTransition).zIndex(1)
                            .allowsHitTesting(gallery).accessibilityHidden(!gallery)
                    } else {
                        VStack(spacing: 0) { pageHeader(gallery: false); editorPage }
                            .transition(pageTransition).zIndex(2)
                            .allowsHitTesting(!gallery).accessibilityHidden(gallery)
                    }
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .clipped().animation(pageMotion, value: gallery)
                .overlay(alignment: .topTrailing) {
                    QuietIconButton(icon: "xmark", label: "关闭服务编辑") { dismiss() }
                        .keyboardShortcut(.cancelAction).padding(.trailing, 24).padding(.top, 23)
                }
            Rectangle().fill(Theme.border).frame(height: 1)
            HStack(spacing: 12) {
                ActionButton(title: "取消") { dismiss() }
                if existing { Button("删除服务") { confirmRemoval.toggle() }.font(.system(size: 11)).foregroundStyle(.red).buttonStyle(FeedbackStyle(compact: true)).disabled(busy) }
                Spacer()
                if !gallery && initialized {
                    HStack(spacing: 12) {
                        if !existing { Text(items.isEmpty ? "可先保存服务，稍后添加模型" : "已添加 \(items.count) 个模型").font(.system(size: 10)).foregroundStyle(.secondary) }
                        ActionButton(title: "保存服务", primary: true) { save() }.disabled(busy || readingKey || keyUnavailable).accessibilityIdentifier("save-api-profile")
                    }.transition(pageTransition)
                }
            }.frame(height: 36).padding(.horizontal, 24).padding(.vertical, 14)
                .animation(pageMotion, value: gallery)
        }.frame(width: 660, height: 580).background(Theme.panel)
            .background(PointerObserver(onDown: { _, _, _ in
                // Pointer input cancels keyboard emphasis, including a queued
                // return request. Hover alone never changes focus or selection.
                keyboardNavigation = false; focusedPreset = nil
            }, onKey: { event in
                keyboardNavigation = true
                return false
            }))
            .onAppear {
                guard !initialized else { return }; initialized = true
                var transaction = Transaction(); transaction.disablesAnimations = true
                withTransaction(transaction) {
                    if !existing { readingKey = false }; items = profile.catalog; testingID = items.first?.id ?? ""
                    gallery = !existing && profile.presetID == "custom"; section = existing ? initialSection : "connection"
                }
            }
            .task { if readingKey { await loadCredential() } }
            .task(id: gallery) {
                guard initialized, !existing else { return }
                await Task.yield()
                guard !Task.isCancelled else { return }
                if gallery {
                    focusedPreset = returningToGallery && keyboardNavigation ? profile.presetID : nil
                } else if usesPreset && section == "connection" && keyboardNavigation { keyFocused = true }
            }
            .sheet(item: $modelDraft) { item in
                APIModelEditor(profile: profile, draft: item, editingID: editingID, existingModels: items) { changed in
                    var updated = items
                    if let editingID, let index = updated.firstIndex(where: { $0.id == editingID }) { updated[index] = changed } else { updated.append(changed) }
                    items = updated; testingID = changed.id; problem = ""; status = "模型已加入列表；保存服务后生效。"
                }.environmentObject(model).choiceHost()
            }
            .sheet(isPresented: $showDiscovered) {
                DiscoveredModelsView(profile: profile, discovered: discovered, existingModels: items) { added in
                    items.append(contentsOf: added); testingID = added.first?.id ?? testingID; status = "已加入 \(added.count) 个模型；保存服务后生效。"
                }.environmentObject(model).choiceHost()
            }
            .onDisappear { operation?.cancel(); try? FileManager.default.removeItem(at: temporaryFolder) }
    }
    private func pageHeader(gallery: Bool) -> some View {
        HStack(spacing: 12) {
            if !gallery { BrandMark(id: existing ? profile.brandID : preset.id, size: 27) }
            VStack(alignment: .leading, spacing: 4) {
                Text(gallery ? "添加服务商" : profile.name).font(.system(size: 19, weight: .semibold))
                Text(gallery ? "选择预设，或连接自己的 API 服务。" : "连接信息填写一次，模型按需添加。")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 44)
        }.frame(height: 42, alignment: .leading).padding(.horizontal, 24).padding(.vertical, 20)
    }
    private var editorPage: some View {
        VStack(spacing: 0) {
                HStack(spacing: 4) {
                    tab("连接信息", "connection")
                    tab("模型列表" + (items.isEmpty ? "" : " · \(items.count)"), "models")
                    Spacer()
                    if !existing { Button { returnToGallery() } label: { Label("选择服务", systemImage: "chevron.left").font(.system(size: 11)).padding(.horizontal, 7).frame(height: 30) }.foregroundStyle(.secondary).buttonStyle(FeedbackStyle(compact: true)).disabled(busy).keyboardShortcut("[", modifiers: .command).help("返回选择服务（⌘[）").accessibilityLabel("返回选择服务") }
                }.padding(.horizontal, 24).padding(.bottom, 12)
                Rectangle().fill(Theme.border).frame(height: 1)
                ScrollViewReader { reader in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 18) {
                            ZStack(alignment: .topLeading) {
                                if section == "connection" { connectionContent.transition(pageTransition) }
                                else { modelsContent.transition(pageTransition) }
                            }.animation(pageMotion, value: section)
                            if busy { HStack(spacing: 8) { ActivityIndicator(); Text(status).font(.system(size: 11)).foregroundStyle(.secondary); Spacer(); Button("停止") { operation?.cancel() }.buttonStyle(FeedbackStyle(compact: true)) } }
                            else if !status.isEmpty { Label(status, systemImage: "info.circle").font(.system(size: 11)).foregroundStyle(.secondary).lineSpacing(4) }
                            if let testImage { Image(nsImage: testImage).resizable().scaledToFit().frame(maxWidth: .infinity).frame(height: 130).clipShape(RoundedRectangle(cornerRadius: 8)) }
                            if !problem.isEmpty {
                                HStack(alignment: .top, spacing: 8) { Image(systemName: "exclamationmark.circle").foregroundStyle(.red); Text(problem).font(.system(size: 11)).lineSpacing(4).textSelection(.enabled); Spacer(minLength: 4); QuietIconButton(icon: "xmark", label: "收起填写提示", size: 24) { problem = "" } }.padding(12).background(Color.red.opacity(0.06), in: RoundedRectangle(cornerRadius: 8)).accessibilityIdentifier("api-inline-error").id("api-error")
                            }
                            if confirmRemoval {
                                VStack(alignment: .leading, spacing: 10) {
                                    Text("删除「" + profile.name + "」？").font(.system(size: 12, weight: .semibold))
                                    Text("删除连接与密钥，保留笔记和对话。使用此服务的功能会提示重新选择。").font(.system(size: 11)).foregroundStyle(.secondary)
                                    HStack { Spacer(); ActionButton(title: "取消删除") { confirmRemoval = false }; ActionButton(title: "删除服务", icon: "trash") { remove() } }
                                }.padding(14).background(Theme.secondary, in: RoundedRectangle(cornerRadius: 10)).id("remove-service")
                            }
                        }.padding(24).frame(maxWidth: .infinity, alignment: .leading)
                    }.scrollIndicators(.automatic).scrollPosition($contentPosition)
                        .onChange(of: section) { _, _ in contentPosition.scrollTo(edge: .top) }
                        .onChange(of: problem) { _, value in if !value.isEmpty { reader.scrollTo("api-error", anchor: .bottom) } }
                        .onChange(of: confirmRemoval) { _, value in if value { reader.scrollTo("remove-service", anchor: .bottom) } }
                }
        }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
    private func tab(_ title: String, _ value: String) -> some View {
        Button { keyFocused = false; section = value; problem = "" } label: { Text(title).font(.system(size: 12, weight: .medium)).padding(.horizontal, 14).padding(.vertical, 9) }.buttonStyle(SidebarButtonStyle(selected: section == value)).accessibilityAddTraits(section == value ? .isSelected : [])
    }
    private var presetGallery: some View {
        VStack(alignment: .leading, spacing: 14) {
            SearchBox(placeholder: "搜索服务商", text: $presetQuery, autofocus: !returningToGallery || !keyboardNavigation).fixedSize(horizontal: false, vertical: true)
            ScrollView {
                let presets = ServicePreset.all.filter { presetQuery.isEmpty || $0.name.localizedCaseInsensitiveContains(presetQuery) }
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                    ForEach(presets) { option in
                        Button { applyPreset(option.id) } label: {
                            HStack(spacing: 10) { BrandMark(id: option.id, size: 24); HighlightedText(option.name, query: presetQuery).font(.system(size: 12, weight: .medium)).lineLimit(2); Spacer(minLength: 0) }.padding(14).frame(maxWidth: .infinity, minHeight: 66, alignment: .leading).contentShape(Rectangle())
                        }.buttonStyle(FeedbackStyle(compact: true)).background(Theme.secondary.opacity(0.6), in: RoundedRectangle(cornerRadius: 10)).overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.border))
                            .focusable(interactions: .activate).focusEffectDisabled().focused($focusedPreset, equals: option.id)
                            .overlay {
                                if gallery && keyboardNavigation && focusedPreset == option.id {
                                    RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.accent, lineWidth: 2)
                                        .allowsHitTesting(false).accessibilityHidden(true)
                                }
                            }
                            .onKeyPress(.space) { applyPreset(option.id); return .handled }
                            .onKeyPress(.return) { applyPreset(option.id); return .handled }
                            .accessibilityLabel("添加 " + option.name)
                    }
                }
                if presets.isEmpty { Text("没有匹配的预设，可以使用自定义 API。").font(.system(size: 11)).foregroundStyle(.secondary).padding(.vertical, 28); ActionButton(title: "自定义 API", icon: "plus") { applyPreset("custom") } }
            }.clipped()
            Text("预设会填好官方地址和接口；不同账号、地域和自定义地址均可调整。").font(.system(size: 10)).foregroundStyle(.secondary).lineSpacing(4)
        }.padding(.horizontal, 24).padding(.bottom, 24)
    }
    private var connectionContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            if !usesPreset { connectionFields }
            VStack(alignment: .leading, spacing: 8) {
                HStack { Text("API 密钥").font(.system(size: 12, weight: .medium)); Spacer(); if replacingKey || removingKey { Button("取消更改") { key = storedKey; replacingKey = false; removingKey = false; keyFocused = false; problem = "" }.font(.system(size: 10)).buttonStyle(FeedbackStyle(compact: true)) } }
                if readingKey {
                    HStack(spacing: 8) { ActivityIndicator(); Text("正在读取已保存的密钥…").font(.system(size: 11)).foregroundStyle(.secondary) }
                } else if keyUnavailable {
                    ActionButton(title: "重试读取", icon: "arrow.clockwise") {
                        readingKey = true
                        operation = Task { await loadCredential() }
                    }.accessibilityIdentifier("retry-api-key-read")
                } else if !storedKey.isEmpty && !replacingKey && !removingKey {
                    HStack(spacing: 9) { Image(systemName: "lock").foregroundStyle(.secondary); Text("密钥已保存在本机").font(.system(size: 11)).foregroundStyle(.secondary); Spacer(); ActionButton(title: "更换密钥") { replacingKey = true; key = ""; keyFocused = true; problem = "" } }.padding(12).background(Theme.secondary.opacity(0.55), in: RoundedRectangle(cornerRadius: 9))
                } else if removingKey {
                    Text("保存服务后移除本地密钥；服务商平台上的密钥不变。").font(.system(size: 11)).foregroundStyle(.secondary)
                } else {
                    SecureField(replacingKey ? "输入新的 API 密钥" : "输入此服务的密钥", text: $key).textFieldStyle(FieldStyle()).focused($keyFocused).accessibilityIdentifier("api-key").onChange(of: key) { _, _ in problem = "" }
                    Text(replacingKey ? "保存服务后替换密钥；取消更改会保留原密钥。" : "保存在本机。本机免密服务可留空。").font(.system(size: 10)).foregroundStyle(.secondary)
                }
            }
            if usesPreset {
                HStack(alignment: .top, spacing: 8) {
                    Text(preset.help).font(.system(size: 11)).foregroundStyle(.secondary).lineSpacing(4)
                    Spacer(minLength: 8)
                    if let url = URL(string: preset.documentation), !preset.documentation.isEmpty { Link("配置说明 ↗", destination: url).font(.system(size: 10)) }
                }
                Rectangle().fill(Theme.border).frame(height: 1)
                Button { connectionOptions.toggle() } label: { HStack { HStack(spacing: 8) { DisclosureChevron(expanded: connectionOptions); Text("连接选项").font(.system(size: 11)) }; Text("名称、地址与接口").font(.system(size: 10)).foregroundStyle(.secondary); Spacer() }.padding(.vertical, 4).contentShape(Rectangle()) }.buttonStyle(FeedbackStyle(compact: true)).accessibilityIdentifier("connection-options")
                if connectionOptions {
                    connectionFields
                    if !storedKey.isEmpty && !removingKey { Button("移除本地密钥…") { key = ""; removingKey = true; replacingKey = false; problem = "" }.font(.system(size: 10)).foregroundStyle(.red).buttonStyle(FeedbackStyle(compact: true)) }
                }
            }
            if !usesPreset && !storedKey.isEmpty && !removingKey { Button("移除本地密钥…") { key = ""; removingKey = true; replacingKey = false; problem = "" }.font(.system(size: 10)).foregroundStyle(.red).buttonStyle(FeedbackStyle(compact: true)) }
            Rectangle().fill(Theme.border).frame(height: 1)
            HStack {
                VStack(alignment: .leading, spacing: 5) { Text(items.isEmpty ? "接下来，添加需要的模型" : "已添加 \(items.count) 个模型").font(.system(size: 12, weight: .medium)); Text("模型集中保存在此服务下，再分配给对话或其他功能。").font(.system(size: 10)).foregroundStyle(.secondary) }
                Spacer(minLength: 8)
                ActionButton(title: "管理模型", icon: "arrow.right") { section = "models" }
            }
        }.disabled(busy)
    }
    private var modelsContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("此服务的模型").font(.system(size: 13, weight: .semibold)); Spacer()
                ActionButton(title: "获取列表", icon: "arrow.down.circle") { discover() }.disabled(busy)
                ActionButton(title: "手动添加", icon: "plus") { editingID = nil; modelDraft = APIModel(id: "") }.disabled(busy)
            }
            if items.isEmpty {
                VStack(spacing: 10) { Image(systemName: "square.stack.3d.up").font(.system(size: 25)).foregroundStyle(.tertiary); Text("还没有模型").font(.system(size: 13, weight: .medium)); Text("获取服务端列表，或填写模型 ID。\n只需要聊天时，添加文本模型即可。").font(.system(size: 11)).foregroundStyle(.secondary).multilineTextAlignment(.center).lineSpacing(4) }.frame(maxWidth: .infinity).padding(.vertical, 34)
            } else {
                VStack(spacing: 0) {
                    ForEach(items) { item in
                        HStack(spacing: 10) {
                            BrandMark(id: profile.brandID, size: 20)
                            VStack(alignment: .leading, spacing: 4) { Text(item.id).font(.system(size: 12, weight: .medium)).lineLimit(1).help(item.id); Text(item.label).font(.system(size: 10)).foregroundStyle(.secondary) }
                            Spacer(minLength: 6)
                            QuietIconButton(icon: "pencil", label: "编辑模型 " + item.id, size: 30) { editingID = item.id; modelDraft = item }.disabled(busy)
                            QuietIconButton(icon: "minus.circle", label: "移除模型 " + item.id, size: 30) { items.removeAll { $0.id == item.id }; if testingID == item.id { testingID = items.first?.id ?? "" }; status = "保存后移除模型，原来的功能分配会提示重新选择。" }.disabled(busy)
                        }.padding(.horizontal, 12).padding(.vertical, 10)
                        if item.id != items.last?.id { Rectangle().fill(Theme.border).frame(height: 1).padding(.leading, 42) }
                    }
                }.background(Theme.secondary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10)).overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.border))
                HStack { Text("验证模型").font(.system(size: 11)).foregroundStyle(.secondary); Spacer(); ChoicePicker(title: "测试模型", selection: testingID, options: items.map { ChoiceOption(id: $0.id, title: $0.id, subtitle: $0.label, brand: profile.brandID) }, width: 245, menuSize: CGSize(width: 320, height: 300), searchable: items.count > 7) { testingID = $0 }.disabled(busy); ActionButton(title: busy ? "停止" : "测试", icon: busy ? "stop" : "bolt") { if busy { operation?.cancel() } else { test() } } }
                Text(items.first { $0.id == testingID }?.kind == "image" ? "生图测试会实际生成一张测试图，可能产生服务商费用。" : "测试使用简短内容，不改动笔记；配置在保存服务后生效。").font(.system(size: 10)).foregroundStyle(.secondary).lineSpacing(3)
            }
        }
    }
    private var connectionFields: some View {
        VStack(alignment: .leading, spacing: 12) {
            field(usesPreset ? "显示名称" : "连接名称", placeholder: usesPreset ? preset.name + "（可选）" : "例如：我的模型服务", text: $profile.name)
            field("接口根地址", placeholder: "服务商提供的根地址", text: $profile.baseURL)
            Text("填写接口根地址，不要附加 /chat/completions、/responses 或 /images/generations。").font(.system(size: 10)).foregroundStyle(.secondary).lineSpacing(3)
            HStack { Text("默认接口").font(.system(size: 11)).foregroundStyle(.secondary).frame(width: 88, alignment: .leading); ChoicePicker(title: "默认接口", selection: profile.protocolKind, options: [ChoiceOption(id: "chat", title: "Chat Completions 兼容"), ChoiceOption(id: "responses", title: "Responses"), ChoiceOption(id: "anthropic", title: "Claude Messages")], width: 245) { profile.protocolKind = $0 }; Spacer() }
            if usesPreset { Text("名称自动填写；同一服务的不同账号或地域可在这里区分。").font(.system(size: 10)).foregroundStyle(.secondary) }
        }
    }
    private func field(_ title: String, placeholder: String, text: Binding<String>) -> some View {
        HStack { Text(title).font(.system(size: 11)).foregroundStyle(.secondary).frame(width: 88, alignment: .leading); TextField(placeholder, text: text).textFieldStyle(FieldStyle()).accessibilityLabel(title) }
    }
    private func returnToGallery() {
        presetDrafts[preset.id] = PresetDraft(profile: profile, key: key, items: items,
            section: section, options: connectionOptions, testingID: testingID)
        keyFocused = false; focusedPreset = nil; returningToGallery = true
        withAnimation(pageMotion) { gallery = true }
    }
    private func applyPreset(_ id: String) {
        guard gallery else { return } // A disappearing card must never activate twice.
        focusedPreset = nil; keyFocused = false
        if let draft = presetDrafts[id] {
            profile = draft.profile; key = draft.key; items = draft.items
            section = draft.section; connectionOptions = draft.options; testingID = draft.testingID
        } else {
            let selected = ServicePreset.named(id)
            profile.presetID = id; profile.name = selected.suggestedName(existingNames: model.library.settings.profiles.map(\.name)); profile.baseURL = selected.address; profile.protocolKind = selected.protocolKind
            connectionOptions = false; key = ""; items = []; testingID = ""; section = "connection"
        }
        discovered = []; status = ""; problem = ""; testImage = nil
        contentPosition.scrollTo(edge: .top)
        withAnimation(pageMotion) { gallery = false }
    }
    private func loadCredential() async {
        do { let loaded = try await model.ai.credentials.readAsync(profile.id); try Task.checkCancellation(); key = loaded; storedKey = loaded; keyUnavailable = false; needsReplacementKey = false; problem = "" }
        catch { if !Task.isCancelled { needsReplacementKey = (error as? CredentialStore.Failure) == .legacyUnavailable; keyUnavailable = !needsReplacementKey; problem = needsReplacementKey ? "" : error.localizedDescription } }
        readingKey = false
    }
    private func candidate() throws -> APIProfile { if readingKey || keyUnavailable { throw AppFailure(message: "请先完成密钥读取，再保存或测试。原密钥未被修改。") }; if needsReplacementKey && key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { throw AppFailure(message: "请填写 API 密钥。") }; if replacingKey && key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { throw AppFailure(message: "请输入新密钥，或取消更改以保留原密钥。") }; var copy = profile; if usesPreset && copy.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { copy.name = preset.suggestedName(existingNames: model.library.settings.profiles.filter { $0.id != profile.id }.map(\.name)) }; copy.replaceModels(items); return try copy.validated() }
    private func save() {
        do { let saved = try candidate(); try model.saveAPIProfile(saved, credential: key, assignment: assignment); onSaved(saved); model.toast = saved.catalog.isEmpty ? "服务已保存，可继续添加模型" : "服务与模型已保存"; dismiss() }
        catch { problem = error.localizedDescription }
    }
    private func remove() {
        do { try model.removeAPIProfile(profile.id); model.toast = "服务已删除，笔记和对话已保留"; dismiss() }
        catch { problem = error.localizedDescription }
    }
    private func discover() {
        do {
            let current = try candidate(); let credential = key
            busy = true; problem = ""; status = "正在获取模型列表…"
            operation = Task {
                defer { busy = false }
                do { discovered = try await model.ai.fetchModels(profile: current, credential: credential); try Task.checkCancellation(); status = ""; showDiscovered = true }
                catch { if Task.isCancelled { status = "已停止获取列表" } else { problem = error.localizedDescription + "\n也可以手动填写模型 ID。"; status = "" } }
            }
        } catch { problem = error.localizedDescription }
    }
    private func test() {
        do {
            let current = try candidate()
            guard let selected = current.catalog.first(where: { $0.id == testingID }) else { throw AppFailure(message: "请选择要测试的模型。") }
            var settings = model.library.settings
            settings.profiles.removeAll { $0.id == current.id }; settings.profiles.append(current)
            settings.assign(.image, to: AISelection(providerID: current.id, modelID: selected.id))
            let credential = key
            let tester = model.ai.isolatedProbe(workspace: temporaryFolder)
            busy = true; problem = ""; testImage = nil; status = selected.kind == "image" ? "正在生成测试图…" : "正在验证模型与笔记格式…"
            operation = Task {
                defer { busy = false }
                do {
                    if selected.kind == "image" {
                        let url = try await tester.generateImage(prompt: "白色背景上的一片绿色叶子，简洁的学习插图。", model: selected.id, effort: "low", settings: settings, credential: credential) { _, _, _ in }
                        try Task.checkCancellation(); testImage = NSImage(contentsOf: url); status = "生图测试通过，已收到实际图像；保存后可分配给图示生成。"
                    } else {
                        var images: [AIImageInput] = []
                        if selected.kind == "vision" {
                            try FileManager.default.createDirectory(at: temporaryFolder, withIntermediateDirectories: true)
                            let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 32, pixelsHigh: 32, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
                            for x in 0..<32 { for y in 0..<32 { bitmap.setColor(.systemGreen, atX: x, y: y) } }
                            let url = temporaryFolder.appendingPathComponent("vision-test.png"); try bitmap.representation(using: .png, properties: [:])!.write(to: url); images = [AIImageInput(url: url)]
                        }
                        try await tester.probeConversation(selection: AISelection(providerID: current.id, modelID: selected.id), settings: settings, images: images, credential: credential) { title, _, phase in
                            if title == "验证笔记整理", phase == "running" { status = "正在验证笔记整理…" }
                        }
                        try Task.checkCancellation()
                        status = selected.kind == "vision" ? "读图、对话与笔记整理测试通过。" : "对话与笔记整理测试通过。"
                    }
                } catch { if Task.isCancelled || (error as? URLError)?.code == .cancelled { status = "测试已停止" } else { problem = error.localizedDescription; status = "" } }
            }
        } catch { problem = error.localizedDescription }
    }
}


struct APIModelEditor: View {
    @Environment(\.dismiss) private var dismiss
    let profile: APIProfile
    @State var draft: APIModel
    var editingID: String?
    var existingModels: [APIModel]
    var onSave: (APIModel) -> Void
    @State private var advanced = false
    @State private var problem = ""
    @FocusState private var focused: Bool
    private var protocolKind: String { draft.protocolKind ?? profile.protocolKind }
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) { BrandMark(id: profile.brandID, size: 23); VStack(alignment: .leading, spacing: 3) { Text(editingID == nil ? "添加模型" : "编辑模型").font(.system(size: 17, weight: .semibold)); Text(profile.name).font(.system(size: 10)).foregroundStyle(.secondary) }; Spacer(); QuietIconButton(icon: "xmark", label: "关闭模型编辑") { dismiss() }.keyboardShortcut(.cancelAction) }.padding(22)
            Rectangle().fill(Theme.border).frame(height: 1)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 7) { Text("模型 ID").font(.system(size: 11, weight: .medium)); TextField("服务商提供的完整模型 ID", text: $draft.id).textFieldStyle(FieldStyle()).focused($focused).accessibilityLabel("模型 ID") }
                    VStack(alignment: .leading, spacing: 8) {
                        Text("模型用途").font(.system(size: 11, weight: .medium))
                        HStack(spacing: 8) { kind("text", "文本", "text.bubble"); kind("vision", "文本与读图", "photo"); kind("image", "生图", "paintbrush.pointed") }
                        Text("按服务商说明选择。生图只在需要插图时使用。").font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                    if draft.kind == "image" {
                        VStack(alignment: .leading, spacing: 7) {
                            Text("生图接口").font(.system(size: 11, weight: .medium))
                            ChoicePicker(title: "生图接口格式", selection: draft.imageFormat ?? "preset", options: [ChoiceOption(id: "preset", title: "沿用服务预设")] + ImageGenerationProtocol.allCases.map { ChoiceOption(id: $0.rawValue, title: $0.title) }, fillsWidth: true) { draft.imageFormat = $0 == "preset" ? nil : $0 }
                            Text("第三方中转按其文档选择兼容格式；尺寸沿用模型默认值。保存后可在功能分配中单独测试。").font(.system(size: 10)).foregroundStyle(.secondary).lineSpacing(3)
                        }
                    } else {
                        Button { advanced.toggle() } label: { HStack(spacing: 8) { DisclosureChevron(expanded: advanced); Text("接口与兼容选项").font(.system(size: 11)) } }.buttonStyle(FeedbackStyle(compact: true))
                        if advanced { advancedFields }
                    }
                    if !problem.isEmpty { Label(problem, systemImage: "exclamationmark.circle").font(.system(size: 11)).foregroundStyle(.red).lineSpacing(4) }
                }.padding(22)
            }.clipped()
            Rectangle().fill(Theme.border).frame(height: 1)
            HStack { Spacer(); ActionButton(title: "取消") { dismiss() }; ActionButton(title: editingID == nil ? "加入列表" : "完成修改", primary: true) { save() }.keyboardShortcut(.defaultAction).disabled(draft.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }.padding(.horizontal, 22).padding(.vertical, 14)
        }.frame(width: 520, height: advanced || draft.kind == "image" ? 520 : 398).background(Theme.panel).onAppear { focused = true }
    }
    private func kind(_ id: String, _ name: String, _ icon: String) -> some View {
        Button { draft.kind = id; if id == "image" { draft.supportsSearch = false; draft.protocolKind = nil; draft.outputFormat = "prompt" } } label: {
            HStack(spacing: 7) { Image(systemName: icon).font(.system(size: 13)); Text(name).font(.system(size: 11, weight: .medium)) }.frame(maxWidth: .infinity).padding(.vertical, 12).contentShape(Rectangle())
        }.buttonStyle(SidebarButtonStyle(selected: draft.kind == id)).background(Theme.secondary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8)).overlay(RoundedRectangle(cornerRadius: 8).stroke(draft.kind == id ? Theme.accent.opacity(0.4) : Theme.border)).accessibilityAddTraits(draft.kind == id ? .isSelected : [])
    }
    private var advancedFields: some View {
        VStack(alignment: .leading, spacing: 12) {
            row("接口") {
                ChoicePicker(title: "模型接口", selection: draft.protocolKind ?? "inherit", options: [ChoiceOption(id: "inherit", title: "沿用服务默认"), ChoiceOption(id: "responses", title: "Responses"), ChoiceOption(id: "chat", title: "Chat Completions"), ChoiceOption(id: "anthropic", title: "Claude Messages")], width: 270) { value in
                    draft.protocolKind = value == "inherit" ? nil : value
                    if protocolKind == "anthropic" && draft.outputFormat == "json" { draft.outputFormat = "prompt" }
                    if protocolKind != "responses" { draft.supportsSearch = false }
                }
            }
            row("笔记输出") {
                ChoicePicker(title: "笔记输出格式", selection: draft.outputFormat, options: [ChoiceOption(id: "prompt", title: "通用兼容")] + (protocolKind == "anthropic" ? [] : [ChoiceOption(id: "json", title: "JSON 模式")]) + [ChoiceOption(id: "schema", title: "严格结构")], width: 270) { draft.outputFormat = $0 }
            }
            row("输出预算") {
                ChoicePicker(title: "单次输出预算", selection: String(draft.maxOutputTokens ?? 0), options: [ChoiceOption(id: "0", title: "沿用服务默认")]+[4096,8192,16384,32768,65536].map { ChoiceOption(id: String($0), title: "\($0) tokens") }, width: 270) { draft.maxOutputTokens = $0 == "0" ? nil : Int($0) }
            }
            SwitchRow(title: "模型自带联网搜索", detail: "服务须支持 Responses 的 web_search 工具。", isOn: $draft.supportsSearch).disabled(protocolKind != "responses")
        }
    }
    private func row<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View { HStack { Text(title).font(.system(size: 11)).foregroundStyle(.secondary); Spacer(); content() } }
    private func save() {
        do {
            draft.id = draft.id.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !existingModels.contains(where: { $0.id == draft.id && $0.id != editingID }) else { throw AppFailure(message: "这个模型已在列表中，可以直接编辑它。") }
            var candidate = profile; candidate.replaceModels(existingModels.filter { $0.id != editingID } + [draft]); _ = try candidate.validated()
            onSave(draft); dismiss()
        } catch { problem = error.localizedDescription }
    }
}

struct DiscoveredModelsView: View {
    @Environment(\.dismiss) private var dismiss
    let profile: APIProfile
    var discovered: [String]
    var existingModels: [APIModel]
    var onSave: ([APIModel]) -> Void
    @State private var query = ""
    @State private var selected = Set<String>()
    @State private var kind = "text"
    @State private var listPosition = ScrollPosition(edge: .top)
    @State private var problem = ""
    private var available: [String] { Array(Set(discovered)).sorted() }
    private var filtered: [String] { available.filter { query.isEmpty || $0.localizedCaseInsensitiveContains(query) } }
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) { BrandMark(id: profile.brandID, size: 24); VStack(alignment: .leading, spacing: 4) { Text("从服务添加模型").font(.system(size: 17, weight: .semibold)); Text(profile.name + " · \(available.count) 个模型").font(.system(size: 10)).foregroundStyle(.secondary) }; Spacer(); QuietIconButton(icon: "xmark", label: "关闭服务模型列表") { dismiss() }.keyboardShortcut(.cancelAction) }.padding(22)
            SearchBox(placeholder: "搜索模型 ID", text: $query, autofocus: true).padding(.horizontal, 20).padding(.bottom, 14).fixedSize(horizontal: false, vertical: true)
            Rectangle().fill(Theme.border).frame(height: 1)
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(filtered, id: \.self) { id in
                        let exists = existingModels.contains { $0.id == id }
                        Button { if selected.contains(id) { selected.remove(id) } else { selected.insert(id) } } label: {
                            HStack(spacing: 10) { Image(systemName: exists || selected.contains(id) ? "checkmark.square.fill" : "square").foregroundStyle(exists ? Color.secondary : Theme.accent); HighlightedText(LibrarySearch.snippet(id, query: query, limit: 90), query: query).font(.system(size: 12)).lineLimit(1); Spacer(minLength: 4); if exists { Text("已添加").font(.system(size: 10)).foregroundStyle(.secondary) } }.padding(.horizontal, 12).frame(maxWidth: .infinity, minHeight: 38, alignment: .leading).contentShape(Rectangle())
                        }.buttonStyle(FeedbackStyle(compact: true)).disabled(exists).accessibilityLabel(id + (exists ? " 已添加" : "")).accessibilityAddTraits(selected.contains(id) ? .isSelected : [])
                    }
                    if filtered.isEmpty { Text("没有匹配的模型").font(.system(size: 12)).foregroundStyle(.secondary).padding(30) }
                }.padding(8)
            }.clipped().scrollPosition($listPosition).onChange(of: query) { _, _ in listPosition.scrollTo(edge: .top) }
            Rectangle().fill(Theme.border).frame(height: 1)
            VStack(alignment: .leading, spacing: 10) {
                HStack { Text("所选模型用途").font(.system(size: 11)); Spacer(); ChoicePicker(title: "所选模型用途", selection: kind, options: [ChoiceOption(id: "text", title: "文本"), ChoiceOption(id: "vision", title: "文本与读图"), ChoiceOption(id: "image", title: "生图")], width: 180) { kind = $0 } }
                Text("列表只提供模型 ID。用途需按服务商说明选择，之后可逐个修改。").font(.system(size: 10)).foregroundStyle(.secondary)
                if !problem.isEmpty { Text(problem).font(.system(size: 11)).foregroundStyle(.red) }
                HStack { Text("已选 \(selected.count) 个").font(.system(size: 11)).foregroundStyle(.secondary); Spacer(); ActionButton(title: "取消") { dismiss() }; ActionButton(title: "加入模型列表", primary: true) { save() }.disabled(selected.isEmpty) }
            }.padding(20)
        }.frame(width: 540, height: 520).background(Theme.panel)
    }
    private func save() {
        do {
            let added = available.filter { id in selected.contains(id) && !existingModels.contains(where: { $0.id == id }) }.map { APIModel(id: $0, kind: kind) }
            var candidate = profile; candidate.replaceModels(existingModels + added); _ = try candidate.validated(); onSave(added); dismiss()
        } catch { problem = error.localizedDescription }
    }
}
