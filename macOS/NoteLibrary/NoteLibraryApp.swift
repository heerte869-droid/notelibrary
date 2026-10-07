import SwiftUI
import AppKit

@main
struct NoteLibraryApp: App {
    @StateObject private var model = AppModel()
    var body: some Scene {
        WindowGroup(Bundle.main.object(forInfoDictionaryKey: "NoteLibraryWindowTitle") as? String ?? "NoteLibrary") {
            RootView().environmentObject(model)
                .onAppear { AppearanceCoordinator.shared.apply(model.library.settings.appearance, animated: false) }
                .tint(Theme.accent)
        }
        .defaultSize(width: 1280, height: 850)
        .windowToolbarStyle(.unifiedCompact)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("新的 AI 对话") { model.newConversation() }.keyboardShortcut("n")
                Button("新建笔记") { model.newNote() }.keyboardShortcut("n", modifiers: [.command, .shift])
                Button("导入学习资料…") { model.chooseSources() }.keyboardShortcut("o")
            }
            CommandGroup(replacing: .appSettings) { Button("设置…") { model.settingsPresented = true }.keyboardShortcut(",") }
            CommandGroup(after: .pasteboard) { Button("粘贴笔记图片") { model.pasteImage() }.keyboardShortcut("v", modifiers: [.command, .shift]) }
            CommandMenu("笔记") {
                Button("显示全部笔记") { model.chooseDestination("all") }.keyboardShortcut("1")
                Button("打开 AI 对话") { model.chooseDestination("chat") }.keyboardShortcut("2")
                Button(model.isSidebarCollapsed ? "展开侧栏" : "收起侧栏") { model.toggleSidebar() }
                    .keyboardShortcut("s", modifiers: [.command, .option]).disabled(model.readingMode)
                Button("切换阅读模式") { model.readingMode.toggle() }
                    .keyboardShortcut("r", modifiers: [.command, .shift])
                    .disabled(model.currentNote == nil || (!model.destination.hasPrefix("book:") && !["all", "favorites", "recent"].contains(model.destination)) || model.notebookSection != "notes")
                Button("版本记录") { model.historyPresented = true }
                Button("导出完整备份…") { model.exportBackup() }
            }
        }
    }
}
