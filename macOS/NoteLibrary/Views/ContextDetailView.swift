import SwiftUI

struct ContextDetailView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) var dismiss
    @State private var tab = "overview"
    @State private var query = ""
    @State private var newPin = ""
    private var chat: Conversation? { model.currentConversation }
    private var preferences: ContextPreferences { chat?.contextPreferences ?? ContextPreferences() }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 7) { Text("上下文与记忆").font(.system(size: 21, weight: .semibold)); Text("决定 AI 在这段对话里记住什么、参考什么。").font(.system(size: 11)).foregroundStyle(.secondary) }
                Spacer(); QuietIconButton(icon: "xmark", label: "关闭上下文") { dismiss() }
            }
            HStack(spacing: 5) {
                section("概览", id: "overview", icon: "circle.dotted.circle")
                section("固定记忆", id: "pins", icon: "pin")
                section("历史范围", id: "history", icon: "text.bubble")
                Spacer()
                if model.isCurrentConversationBusy { Label("生成结束后可调整", systemImage: "hourglass").font(.system(size: 10)).foregroundStyle(.secondary) }
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 17) {
                    if tab == "overview" { overview }
                    else if tab == "pins" { pins }
                    else { history }
                }.frame(maxWidth: .infinity, alignment: .leading).padding(2)
            }.scrollIndicators(.automatic)
        }.padding(25).frame(width: 680, height: 585).background(Theme.panel)
    }
    private func section(_ title: String, id: String, icon: String) -> some View {
        Button { tab = id } label: { Label(title, systemImage: icon).font(.system(size: 12, weight: .medium)).padding(.horizontal, 13).frame(height: 36) }.buttonStyle(FeedbackStyle(selected: tab == id)).accessibilityAddTraits(tab == id ? .isSelected : [])
    }
    private var overview: some View {
        VStack(alignment: .leading, spacing: 17) {
            HStack(spacing: 0) {
                metric("完整消息", "\(chat?.messages.count ?? 0)")
                Divider().frame(height: 30)
                metric("对话字符", "\(chat.map(ConversationContext.characters) ?? 0)")
                Divider().frame(height: 30)
                metric("固定信息", "\(preferences.pins.filter(\.enabled).count) 条")
            }.padding(.vertical, 10)
            VStack(spacing: 15) {
                SwitchRow(title: "自动整理长对话", detail: "为这段对话提取早期摘要，完整记录始终保留。", isOn: Binding(get: { (preferences.autoCompact ?? model.library.settings.autoCompact) != false }, set: { value in model.updateContextPreferences { $0.autoCompact = value } }))
                Divider()
                HStack {
                    VStack(alignment: .leading, spacing: 5) { Text("近期原文保留").font(.system(size: 13, weight: .medium)); Text("整理时保留最近的消息，问题与回答一起保留。 ").font(.system(size: 11)).foregroundStyle(.secondary) }
                    Spacer()
                    ChoicePicker(title: "近期原文保留数量", selection: String(preferences.retainedMessages), options: [4, 10, 20].map { ChoiceOption(id: String($0), title: "\($0) 条消息") }, width: 108) { value in model.updateContextPreferences { $0.retainedMessages = Int(value) ?? 10 } }
                }
                Divider()
                SwitchRow(title: "参考笔记正文", detail: "关闭后不附带资料库中的笔记正文，适合单纯聊天。", isOn: Binding(get: { preferences.includeNoteContents }, set: { value in model.updateContextPreferences { $0.includeNoteContents = value } }))
                SwitchRow(title: "携带历史附件", detail: "关闭后只携带最新问题的附件；历史消息仍可参考。", isOn: Binding(get: { preferences.includeHistoricalImages }, set: { value in model.updateContextPreferences { $0.includeHistoricalImages = value } }))
            }.padding(17).background(Theme.secondary.opacity(0.6), in: RoundedRectangle(cornerRadius: 14)).disabled(model.isCurrentConversationBusy)
            if model.isCurrentCompacting { CompactStatusCard() }
            VStack(alignment: .leading, spacing: 12) {
                HStack { Label("记忆摘要", systemImage: "text.alignleft").font(.system(size: 12, weight: .semibold)); Spacer(); if let memory = chat?.memory { Text("第 \(memory.generation) 次整理").font(.system(size: 10)).foregroundStyle(.secondary) } }
                if let memory = chat?.memory {
                    Text(.init(memory.text)).font(.system(size: 13)).lineSpacing(5).textSelection(.enabled)
                    Text("涵盖 \(memory.coveredMessageIDs.count) 条消息 · \(memory.createdAt.formatted(date: .abbreviated, time: .shortened))").font(.system(size: 10)).foregroundStyle(.secondary)
                } else { Text("尚未生成摘要，目前保留完整原文。固定记忆会独立保留，不会在自动整理中被覆盖。").font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(5) }
            }.padding(17).frame(maxWidth: .infinity, alignment: .leading).background(Theme.background, in: RoundedRectangle(cornerRadius: 13))
        }
    }
    private var pins: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("把不能遗漏的目标、术语约定或输出偏好固定下来。每条可以单独停用；只有开启的内容会随请求发送，且仅影响当前对话。").font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(5)
            ForEach(preferences.pins) { pin in MemoryPinRow(pin: pin).id(pin.id) }
            VStack(alignment: .leading, spacing: 11) {
                TextField("例如：保留英文术语，例子优先使用生态系统", text: $newPin, axis: .vertical).lineLimit(2...4).font(.system(size: 12)).textFieldStyle(FieldStyle()).accessibilityLabel("新的固定记忆")
                HStack { Text("\(preferences.pins.count) / 8 条 · 每条最多 500 字").font(.system(size: 10)).foregroundStyle(.secondary); Spacer(); ActionButton(title: "固定这条信息", icon: "pin", primary: true) { model.saveMemoryPin(text: newPin); if model.error == nil { newPin = "" } }.disabled(newPin.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || newPin.count > 500 || preferences.pins.count >= 8) }
            }.padding(15).background(Theme.secondary.opacity(0.5), in: RoundedRectangle(cornerRadius: 13))
        }.disabled(model.isCurrentConversationBusy)
    }
    private var history: some View {
        VStack(alignment: .leading, spacing: 14) {
            SwitchRow(title: "参考历史对话", detail: "关闭后不再携带历史消息与追问记录，原文仍然保留。", isOn: Binding(get: { preferences.includeHistory }, set: { value in model.updateContextPreferences { $0.includeHistory = value } })).disabled(model.isCurrentConversationBusy)
            Text("排除消息后，这条原文不再随请求发送。若摘要包含这条消息，旧摘要会失效并重新使用其余原文。").font(.system(size: 11)).foregroundStyle(.secondary).lineSpacing(4)
            SearchBox(placeholder: "查找历史消息", text: $query)
            LazyVStack(spacing: 8) {
                ForEach((chat?.messages ?? []).filter { LibrarySearch.query(query).isEmpty || LibrarySearch.matches($0.text, query: query) }.reversed()) { message in
                    let latest = message.id == chat?.messages.last(where: { $0.role == "user" })?.id
                    VStack(alignment: .leading, spacing: 8) {
                        HStack { Text(message.role == "user" ? "你" : "NoteLibrary").font(.system(size: 11, weight: .semibold)); Text(message.date, style: .time).font(.system(size: 10)).foregroundStyle(.secondary); Spacer(); if latest { Text("最新问题 · 始终保留").font(.system(size: 10)).foregroundStyle(Theme.accent) } else { Button { model.setContextMessageIncluded(preferences.excludedMessageIDs.contains(message.id), id: message.id) } label: { Label(preferences.excludedMessageIDs.contains(message.id) ? "已排除" : "参与回复", systemImage: preferences.excludedMessageIDs.contains(message.id) ? "minus.circle" : "checkmark.circle.fill").font(.system(size: 11)).padding(.horizontal, 8).frame(height: 30) }.buttonStyle(FeedbackStyle(compact: true)).foregroundStyle(preferences.excludedMessageIDs.contains(message.id) ? Color.secondary : Theme.accent).disabled(model.isCurrentConversationBusy || !preferences.includeHistory).accessibilityLabel("切换历史消息：" + String(message.text.prefix(24))) } }
                        HighlightedText(message.text.isEmpty ? "附件消息" : LibrarySearch.query(query).isEmpty ? message.text : LibrarySearch.snippet(message.text, query: query, limit: 160), query: query).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(3).textSelection(.enabled)
                    }.padding(12).background(Theme.secondary.opacity(0.55), in: RoundedRectangle(cornerRadius: 11))
                }
                if chat?.messages.isEmpty != false { Text("开始对话后，可以在这里逐条选择历史内容。").font(.system(size: 12)).foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(.vertical, 45) }
            }
        }
    }
    private func metric(_ label: String, _ value: String) -> some View { VStack(alignment: .leading, spacing: 6) { Text(value).font(.system(size: 21, weight: .medium)).monospacedDigit(); Text(label).font(.system(size: 10)).foregroundStyle(.secondary) }.frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 14) }
}
private struct MemoryPinRow: View {
    @EnvironmentObject var model: AppModel
    let pin: PinnedMemory
    @State private var text = ""
    @State private var editing = false
    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            SwitchRow(title: "固定信息", detail: pin.enabled ? "每次回复都会携带" : "已停用，暂不发送", isOn: Binding(get: { pin.enabled }, set: { value in model.updateContextPreferences { preferences in if let i = preferences.pins.firstIndex(where: { $0.id == pin.id }) { preferences.pins[i].enabled = value } } }))
            if editing {
                TextField("固定信息", text: $text, axis: .vertical).lineLimit(2...5).textFieldStyle(FieldStyle()).font(.system(size: 12))
                HStack { Spacer(); ActionButton(title: "取消") { editing = false }; ActionButton(title: "保存", primary: true) { model.saveMemoryPin(id: pin.id, text: text); editing = false }.disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || text.count > 500) }
            } else {
                Text(pin.text).font(.system(size: 13)).lineSpacing(4).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                HStack { Spacer(); QuietIconButton(icon: "pencil", label: "编辑固定信息") { text = pin.text; editing = true }; QuietIconButton(icon: "trash", label: "移除固定信息") { model.updateContextPreferences { $0.pins.removeAll { $0.id == pin.id } } } }
            }
        }.padding(15).background(Theme.secondary.opacity(0.55), in: RoundedRectangle(cornerRadius: 13))
    }
}
