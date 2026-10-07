import SwiftUI

struct InlineMessageEditor: View {
    @EnvironmentObject var model: AppModel
    var message: ChatMessage
    @State private var height: CGFloat = 36
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !message.assetIDs.isEmpty { Label("保留 \(message.assetIDs.count) 份原稿", systemImage: "photo.on.rectangle").font(.system(size: 10)).foregroundStyle(.secondary) }
            ComposerEditor(text: $model.editingText, height: $height, enterSends: false, onSend: { model.resendEditedMessage() }, onImagePaste: {}, placeholder: "修改这条消息…", accessibilityName: "重新编辑最新消息内容", minimumHeight: 36, maximumHeight: 180, focusOnAppear: true, onEscape: { model.cancelMessageEdit() }).frame(height: height)
            HStack(spacing: 7) {
                Text("⌘ ↵ 发送 · Esc 取消").font(.system(size: 9)).foregroundStyle(.tertiary)
                Spacer(minLength: 8)
                Button("取消") { model.cancelMessageEdit() }.font(.system(size: 11, weight: .medium)).padding(.horizontal, 12).frame(height: 30).background(Theme.panel.opacity(0.6), in: Capsule()).overlay(Capsule().stroke(Theme.border)).buttonStyle(FeedbackStyle(compact: true))
                Button { model.resendEditedMessage() } label: { Text("发送").font(.system(size: 11, weight: .semibold)).padding(.horizontal, 14).frame(height: 30) }.buttonStyle(FeedbackStyle(prominent: true, compact: true)).clipShape(Capsule()).disabled(model.editingText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty).accessibilityIdentifier("send-edited-message")
            }
            if model.currentConversation?.receiptID != nil { Text("替换本轮回复，已保存的笔记保留").font(.system(size: 9)).foregroundStyle(.secondary) }
        }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.composer, in: RoundedRectangle(cornerRadius: 15))
            .overlay(RoundedRectangle(cornerRadius: 15).stroke(Theme.accent.opacity(0.38)))
    }
}

struct ClearConversationDialog: View {
    @EnvironmentObject var model: AppModel
    @FocusState private var cancelFocused: Bool
    let title: String
    let confirm: () -> Void
    private func cancel() { model.clearConversationPresented = false }
    var body: some View {
        ZStack {
            Color.black.opacity(0.28).contentShape(Rectangle()).onTapGesture { cancel() }
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .top, spacing: 13) {
                    Image(systemName: "eraser").font(.system(size: 21, weight: .light)).foregroundStyle(Theme.accent).frame(width: 44, height: 44).background(Theme.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 13))
                    VStack(alignment: .leading, spacing: 6) { Text("清空当前对话？").font(.system(size: 19, weight: .semibold)); Text(title).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1) }
                    Spacer(minLength: 0)
                    QuietIconButton(icon: "xmark", label: "取消清空", size: 28) { cancel() }
                }
                VStack(alignment: .leading, spacing: 11) {
                    Label("聊天记录移入回收站，随时可以恢复", systemImage: "arrow.uturn.backward").font(.system(size: 12))
                    Label("笔记、固定记忆与当前附图继续保留", systemImage: "checkmark.shield").font(.system(size: 12)).foregroundStyle(.secondary)
                }.padding(15).frame(maxWidth: .infinity, alignment: .leading).background(Theme.secondary, in: RoundedRectangle(cornerRadius: 12))
                HStack(spacing: 9) {
                    Spacer()
                    Button("取消") { cancel() }.font(.system(size: 12, weight: .medium)).padding(.horizontal, 18).frame(height: 36).background(Theme.secondary, in: RoundedRectangle(cornerRadius: 10)).buttonStyle(FeedbackStyle(compact: true)).focused($cancelFocused).keyboardShortcut(.cancelAction)
                    ActionButton(title: "清空对话", primary: true) { confirm() }.accessibilityIdentifier("confirm-clear-conversation")
                }
            }.padding(24).frame(width: 430).background(Theme.panel, in: RoundedRectangle(cornerRadius: 20)).overlay(RoundedRectangle(cornerRadius: 20).stroke(Theme.border)).shadow(color: .black.opacity(0.22), radius: 32, y: 14).focusSection()
                .accessibilityElement(children: .contain).accessibilityLabel("清空对话确认")
                .onAppear { cancelFocused = true }
        }.onExitCommand { cancel() }
    }
}

struct CommandPalette: View {
    @EnvironmentObject var model: AppModel
    var commands: [ChatCommand]
    var selected: Int
    var visibleRows = 5
    var choose: (ChatCommand) -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack { Text("快捷命令").font(.system(size: 11, weight: .semibold)); Spacer(); Text("↑ ↓ 选择 · ↵ 执行").font(.system(size: 9)).foregroundStyle(.secondary) }.padding(.horizontal, 12).frame(height: 32)
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 3) {
                        ForEach(Array(commands.enumerated()), id: \.element.id) { index, command in
                            let unavailable = model.commandUnavailable(command)
                            Button { choose(command) } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: command.icon).font(.system(size: 16)).foregroundStyle(unavailable == nil ? Theme.accent : .secondary).frame(width: 26)
                                    VStack(alignment: .leading, spacing: 5) {
                                        HStack(spacing: 9) { Text("/" + command.rawValue).font(.system(size: 12, weight: .semibold, design: .monospaced)); Text(command.title).font(.system(size: 12, weight: .medium)); Spacer(minLength: 0) }
                                        Text(unavailable ?? command.detail).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                                    }
                                }.padding(.horizontal, 10).frame(maxWidth: .infinity, minHeight: 54, maxHeight: 54, alignment: .leading).background(index == selected ? Theme.accent.opacity(0.1) : .clear, in: RoundedRectangle(cornerRadius: 9)).contentShape(Rectangle())
                            }.buttonStyle(FeedbackStyle(compact: true)).opacity(unavailable == nil ? 1 : 0.6).id(index).accessibilityLabel("/\(command.rawValue) \(command.title)" + (unavailable.map { "，" + $0 } ?? ""))
                        }
                    }
                }.frame(height: CGFloat(min(commands.count, visibleRows)) * 57 - 3).scrollIndicators(.automatic)
                    .onChange(of: selected) { _, value in proxy.scrollTo(value, anchor: .center) }
            }
        }.padding(7).frame(width: 390).background(Theme.panel, in: RoundedRectangle(cornerRadius: 14)).overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.border)).shadow(color: .black.opacity(0.16), radius: 18, y: 6)
    }
}
struct CommandHelpView: View {
    @Environment(\.dismiss) var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 17) {
            HStack { Text("快捷命令").font(.system(size: 21, weight: .semibold)); Spacer(); QuietIconButton(icon: "xmark", label: "关闭命令帮助") { dismiss() } }
            Text("在消息框输入 /，用方向键选择，按 Enter 执行。命令由应用直接处理。").font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(4)
            ForEach(ChatCommand.allCases) { command in
                HStack(spacing: 12) { Image(systemName: command.icon).foregroundStyle(Theme.accent).frame(width: 22); VStack(alignment: .leading, spacing: 4) { Text("/" + command.rawValue + "  " + command.title).font(.system(size: 12, weight: .medium)); Text(command.detail).font(.system(size: 11)).foregroundStyle(.secondary) }; Spacer() }.padding(.vertical, 6)
            }
            Divider(); Text("消息编辑：⌘ Enter 重新发送 · Esc 取消\n命令面板：↑ ↓ 选择 · Enter / Tab 执行 · Esc 收起").font(.system(size: 11)).foregroundStyle(.secondary).lineSpacing(6)
        }.padding(26).frame(width: 500).background(Theme.panel)
    }
}

struct CompactStatusCard: View {
    var body: some View {
        HStack(spacing: 13) {
            ZStack { RoundedRectangle(cornerRadius: 11).fill(Theme.accent.opacity(0.1)).frame(width: 42, height: 42); Image(systemName: "text.badge.minus").font(.system(size: 19, weight: .light)).foregroundStyle(Theme.accent) }
            VStack(alignment: .leading, spacing: 6) { HStack(spacing: 7) { Text("正在整理对话记忆").font(.system(size: 12, weight: .semibold)); ActivityIndicator(size: 10) }; Text("提取目标与决定，保留近期消息和全部原文").font(.system(size: 11)).foregroundStyle(.secondary) }
            Spacer(minLength: 0)
        }.padding(15).frame(maxWidth: .infinity, alignment: .leading).background(Theme.secondary.opacity(0.65), in: RoundedRectangle(cornerRadius: 14)).overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.accent.opacity(0.17)))
    }
}
struct QuestionsCard: View {
    @EnvironmentObject var model: AppModel
    let chat: Conversation
    @State private var index = 0
    private var answered: Int { chat.questions.filter { !(chat.answers[$0.id] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.count }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: "text.bubble").font(.system(size: 18)).foregroundStyle(Theme.accent).frame(width: 35, height: 35).background(Theme.accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 4) { Text("补充一点信息").font(.system(size: 13, weight: .semibold)); Text("确认后继续整理，让笔记更准确").font(.system(size: 10)).foregroundStyle(.secondary) }
                Spacer(); Text("\(min(index + 1, chat.questions.count)) / \(chat.questions.count)").font(.system(size: 11, weight: .medium, design: .rounded)).monospacedDigit().foregroundStyle(.secondary)
            }
            if chat.questions.indices.contains(index) { questionBody(chat.questions[index]) }
            HStack(spacing: 8) {
                if index > 0 { Button("上一项") { index -= 1 }.buttonStyle(FeedbackStyle(compact: true)).font(.system(size: 11)).padding(5) }
                Text("已填写 \(answered) / \(chat.questions.count)").font(.system(size: 10)).foregroundStyle(.secondary); Spacer()
                Button {
                    if index + 1 < chat.questions.count { index += 1 } else { model.submitAnswers() }
                } label: { HStack(spacing: 8) { Text(index + 1 < chat.questions.count ? "下一项" : "继续整理"); Image(systemName: "arrow.right").font(.system(size: 10)) }.font(.system(size: 12, weight: .medium)).padding(.horizontal, 15).frame(height: 36) }.buttonStyle(FeedbackStyle(prominent: true)).disabled(model.isCurrentConversationBusy || !canContinue)
            }
        }.padding(18).background(Theme.panel, in: RoundedRectangle(cornerRadius: 16)).overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.accent.opacity(0.23))).shadow(color: .black.opacity(0.04), radius: 10, y: 4).onChange(of: chat.questions.map(\.id)) { _, _ in index = 0 }
    }
    private var canContinue: Bool {
        guard chat.questions.indices.contains(index) else { return false }
        return index + 1 == chat.questions.count ? answered == chat.questions.count : !(chat.answers[chat.questions[index].id] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    private func questionBody(_ question: AIQuestion) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(question.question).font(.system(size: 14, weight: .medium)).lineSpacing(4).fixedSize(horizontal: false, vertical: true)
            ForEach(Array(question.options.enumerated()), id: \.offset) { _, option in
                let chosen = chat.answers[question.id] == option
                Button { model.answer(question.id, value: option) } label: {
                    HStack(spacing: 10) { Image(systemName: chosen ? "checkmark.circle.fill" : "circle").font(.system(size: 16)).foregroundStyle(chosen ? Theme.accent : .secondary); Text(option).font(.system(size: 12)).lineSpacing(3).fixedSize(horizontal: false, vertical: true); Spacer(minLength: 0) }.padding(.horizontal, 12).padding(.vertical, 12).frame(maxWidth: .infinity, minHeight: 42, alignment: .leading).background(chosen ? Theme.accent.opacity(0.09) : Theme.secondary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10)).overlay(RoundedRectangle(cornerRadius: 10).stroke(chosen ? Theme.accent.opacity(0.45) : Theme.border)).contentShape(Rectangle())
                }.buttonStyle(FeedbackStyle(compact: true)).accessibilityAddTraits(chosen ? .isSelected : [])
            }
            TextField("也可以填写自己的说明", text: Binding(get: { chat.answers[question.id] ?? "" }, set: { model.answer(question.id, value: $0) }), axis: .vertical).lineLimit(2...4).textFieldStyle(FieldStyle()).font(.system(size: 12)).accessibilityLabel("补充说明")
        }
    }
}
