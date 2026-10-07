import Foundation

struct AppliedPlan {
    var state: LibraryState
    var receipt: ChangeReceipt
}

enum NoteEngine {
    static func validate(_ plan: AIPlan, pendingQuestions: Bool) throws {
        guard plan.action == "write", plan.questions.isEmpty, !pendingQuestions else { throw AppFailure(message: "还有问题需要回答，暂时不会写入笔记。") }
        guard !plan.notes.isEmpty, plan.notes.count <= 40 else { throw AppFailure(message: "整理结果没有有效笔记，或一次改动过多。") }
        guard LearningEditorial.issue(plan) == nil else { throw AppFailure(message: "整理结果还有未处理的核对说明，已保留对话草稿，未写入笔记。") }
        for note in plan.notes {
            guard !note.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !note.blocks.isEmpty else { throw AppFailure(message: "整理结果缺少标题或正文。") }
            for block in note.blocks {
                guard BlockKind(rawValue: block.kind) != nil, ["source", "addition", "correction"].contains(block.origin) else { throw AppFailure(message: "整理结果包含无法识别的内容类型。") }
                if block.kind == "diagram" {
                    guard let diagram = block.diagram else { throw AppFailure(message: "示意图缺少可绘制内容，草稿已保留。") }; try diagram.validate()
                }
                if block.kind != "image", !(block.sourceAssetID ?? "").isEmpty { throw AppFailure(message: "原图引用类型不一致，草稿已保留。") }
                if block.kind == "table" {
                    guard !block.rows.isEmpty, let count = block.rows.first?.count, count > 0, count <= 20, block.rows.allSatisfy({ $0.count == count }) else { throw AppFailure(message: "表格结构不完整，已保留草稿。") }
                }
                if block.origin == "correction", block.citations.isEmpty, note.sourceIDs.isEmpty { throw AppFailure(message: "这项校正没有可追溯依据，暂不写入。") }
            }
        }
    }

    static func diagramProblem(_ plan: AIPlan) -> String? {
        for block in plan.notes.flatMap(\.blocks) where block.kind == "diagram" {
            do { guard let diagram = block.diagram else { return "缺少图示结构" }; try diagram.validate() }
            catch { return error.localizedDescription }
        }
        return nil
    }
    static func adoptingDiagramRepair(_ candidate: AIPlan, for original: AIPlan) throws -> AIPlan {
        guard original.notes.count == candidate.notes.count else { throw AppFailure(message: "图示校验改变了正文，已保留原草稿。") }
        var expected = original
        for i in original.notes.indices {
            guard original.notes[i].blocks.count == candidate.notes[i].blocks.count else { throw AppFailure(message: "图示校验改变了正文，已保留原草稿。") }
            for j in original.notes[i].blocks.indices where original.notes[i].blocks[j].kind == "diagram" { expected.notes[i].blocks[j].diagram = candidate.notes[i].blocks[j].diagram }
        }
        let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
        guard try encoder.encode(expected) == encoder.encode(candidate), diagramProblem(candidate) == nil else { throw AppFailure(message: "图示未通过校验，已保留草稿和原稿。") }
        return candidate
    }

    static func apply(_ plan: AIPlan, to original: LibraryState, baseRevision: Int, taskID: String, generatedAssets: [String: String] = [:], pendingQuestions: Bool = false) throws -> AppliedPlan {
        try validate(plan, pendingQuestions: pendingQuestions)
        guard !original.committedTaskIDs.contains(taskID) else { throw AppFailure(message: "这次整理已经保存，不会重复添加。") }
        guard original.contentRevision == baseRevision else { throw AppFailure(message: "笔记刚刚被修改。草稿已保留，请重新整理以合并最新内容。") }
        var state = original
        var changes: [NoteDelta] = []
        var books: [String] = []
        var chapters: [String] = []
        var changedIDs = Set<String>()
        for (entryIndex, entry) in plan.notes.enumerated() {
            let existing = entry.noteID.isEmpty ? nil : state.notes.first { $0.id == entry.noteID && LibraryScope.contains($0, in: state) }
            if !entry.noteID.isEmpty && existing == nil { throw AppFailure(message: "找不到要更新的笔记，已停止保存。") }
            if existing?.locked == true || original.chapters.first(where: { $0.id == existing?.chapterID })?.locked == true { throw AppFailure(message: "目标笔记已锁定，请先解锁或让 AI 新建笔记。") }
            let book: Notebook
            if !entry.notebookID.isEmpty {
                guard let found = state.notebooks.first(where: { $0.id == entry.notebookID && LibraryScope.active($0) }) else { throw AppFailure(message: "目标笔记本不存在。") }
                book = found
            } else if let found = state.notebooks.first(where: { $0.title == entry.notebookTitle.trimmingCharacters(in: .whitespacesAndNewlines) && LibraryScope.active($0) }) { book = found }
            else {
                let title = entry.notebookTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !title.isEmpty else { throw AppFailure(message: "需要先确定新笔记本的名称。") }
                guard !state.notebooks.contains(where: { $0.title == title && !LibraryScope.active($0) }) else { throw AppFailure(message: "同名笔记本已归档或删除，请先恢复，或明确使用新的名称。") }
                book = Notebook(title: title, subject: title, color: state.notebooks.count % 5)
                state.notebooks.append(book); books.append(book.id)
            }
            let chapter: Chapter
            if !entry.chapterID.isEmpty {
                guard let found = state.chapters.first(where: { $0.id == entry.chapterID && $0.notebookID == book.id }) else { throw AppFailure(message: "章节与笔记本不匹配。") }
                chapter = found
            } else if let found = state.chapters.first(where: { $0.notebookID == book.id && $0.title == entry.chapterTitle }) { chapter = found }
            else {
                guard !entry.chapterTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw AppFailure(message: "需要先确定章节名称。") }
                chapter = Chapter(notebookID: book.id, title: entry.chapterTitle, order: state.chapters.filter { $0.notebookID == book.id }.count)
                state.chapters.append(chapter); chapters.append(chapter.id)
            }
            guard !chapter.locked else { throw AppFailure(message: "目标章节已锁定。") }
            let assetIDs = Set(state.assets.map(\.id))
            guard entry.sourceIDs.allSatisfy({ assetIDs.contains($0) }) else { throw AppFailure(message: "整理结果引用了不存在的原图。") }
            var note = existing ?? Note(chapterID: chapter.id, title: entry.title)
            guard changedIDs.insert(note.id).inserted else { throw AppFailure(message: "同一笔记出现了相互重复的修改。") }
            let originalBlocks = Set(note.blocks.map(\.id))
            var blockIDs = Set<String>()
            var blocks: [ContentBlock] = []
            for (blockIndex, draft) in entry.blocks.enumerated() {
                let id = draft.id.isEmpty ? makeID() : draft.id
                guard blockIDs.insert(id).inserted, draft.id.isEmpty || originalBlocks.contains(id) else { throw AppFailure(message: "内容引用不一致，已停止写入。") }
                var block = ContentBlock(id: id, kind: BlockKind(rawValue: draft.kind)!, text: draft.text, detail: draft.detail, rows: draft.rows, diagram: draft.diagram, origin: draft.origin, citations: draft.citations, reviewQuestion: draft.reviewQuestion)
                if block.kind == .image {
                    if let sourceID = draft.sourceAssetID, !sourceID.isEmpty {
                        guard draft.diagramPrompt.isEmpty, Set(entry.sourceIDs + (existing?.sourceIDs ?? [])).contains(sourceID), state.assets.contains(where: { $0.id == sourceID && $0.isImage }) else { throw AppFailure(message: "图示引用的原图与本篇笔记来源不匹配。") }
                        block.assetID = sourceID
                    } else if let generated = generatedAssets["\(entryIndex):\(blockIndex)"], assetIDs.contains(generated) { block.assetID = generated }
                    else if let prior = existing?.blocks.first(where: { $0.id == id }), let assetID = prior.assetID { block.assetID = assetID }
                    else { throw AppFailure(message: "图示尚未生成，草稿已保留。") }
                }
                blocks.append(block)
            }
            note.chapterID = chapter.id
            note.title = entry.title
            note.blocks = blocks
            note.sourceIDs = Array(Set(note.sourceIDs + entry.sourceIDs)).sorted()
            note.tags = entry.tags
            note.updatedAt = Date()
            note.version = (existing?.version ?? 0) + 1
            state.notes.removeAll { $0.id == note.id }
            state.notes.append(note)
            changes.append(NoteDelta(before: existing, after: note))
        }
        state.contentRevision += 1
        state.committedTaskIDs.append(taskID)
        let receipt = ChangeReceipt(id: taskID, title: plan.message, changes: changes, createdNotebookIDs: books, createdChapterIDs: chapters)
        state.receipts.append(receipt)
        return AppliedPlan(state: state, receipt: receipt)
    }

    static func undo(receiptID: String, in original: LibraryState) throws -> LibraryState {
        guard let receipt = original.receipts.first(where: { $0.id == receiptID }), !receipt.undone else { throw AppFailure(message: "这次整理已经撤销或记录不存在。") }
        for change in receipt.changes {
            guard var current = original.notes.first(where: { $0.id == change.after.id }) else { throw AppFailure(message: "笔记已被移除，无法直接撤销。") }
            current.pinned = change.after.pinned
            guard current.version == change.after.version, current == change.after else { throw AppFailure(message: "部分笔记在整理后又被修改。为保留这些修改，不能直接撤销；请在历史记录中对照恢复。") }
        }
        var state = original
        for change in receipt.changes {
            state.notes.removeAll { $0.id == change.after.id }
            if var before = change.before { before.pinned = original.notes.first { $0.id == change.after.id }?.pinned; state.notes.append(before) }
        }
        for id in receipt.createdChapterIDs where !state.notes.contains(where: { $0.chapterID == id }) { state.chapters.removeAll { $0.id == id } }
        for id in receipt.createdNotebookIDs where !state.chapters.contains(where: { $0.notebookID == id }) { state.notebooks.removeAll { $0.id == id } }
        if let i = state.receipts.firstIndex(where: { $0.id == receiptID }) { state.receipts[i].undone = true }
        state.contentRevision += 1
        return state
    }

    static func markdown(_ note: Note) -> String {
        var lines = ["# \(note.title)", ""]
        for block in note.blocks {
            switch block.kind {
            case .heading: lines.append("## \(block.text)" + (block.detail.isEmpty ? "" : "\n\n" + block.detail))
            case .bullet: lines.append("- \(block.text)" + (block.detail.isEmpty ? "" : "\n\n" + block.detail))
            case .term, .callout: lines.append("### \(block.text)\n\n\(block.detail)")
            case .formula: lines.append("$$\n\(block.text)\n$$\n\n\(block.detail)")
            case .diagram:
                if let diagram = block.diagram { lines.append("### \(block.text)\n\n" + diagram.svg(title: block.text) + "\n\n" + block.detail) }
            case .table:
                if !block.text.isEmpty { lines.append("### \(block.text)\n") }
                if let first = block.rows.first {
                    let escape: (String) -> String = { $0.replacingOccurrences(of: "|", with: "\\|").replacingOccurrences(of: "\n", with: "<br>") }
                    lines.append("| " + first.map(escape).joined(separator: " | ") + " |")
                    lines.append("| " + first.map { _ in "---" }.joined(separator: " | ") + " |")
                    for row in block.rows.dropFirst() { lines.append("| " + row.map(escape).joined(separator: " | ") + " |") }
                }
                if !block.detail.isEmpty { lines.append("\n" + block.detail) }
            case .image: lines.append("![\(block.text)](Assets/\(block.assetID ?? ""))\n\n\(block.detail)")
            default: lines.append(block.text + (block.detail.isEmpty ? "" : "\n\n" + block.detail))
            }
            if !block.citations.isEmpty { lines.append(block.citations.map { "来源：\($0)" }.joined(separator: "\n")) }
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }
}
