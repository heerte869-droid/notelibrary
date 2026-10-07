import Foundation
import CryptoKit

/// Local, transparent scheduling heuristic; not a calibrated memory model.
enum StudyLearning {
    static func fingerprint(_ block: ContentBlock) -> String {
        SHA256.hash(data: Data([block.kind.rawValue, block.text, block.detail, block.reviewQuestion ?? ""].joined(separator: "\u{001f}").utf8)).map { String(format: "%02x", $0) }.joined()
    }
    static func isDue(_ block: ContentBlock, record: ReviewRecord?, now: Date = Date()) -> Bool {
        guard let record else { return true }
        guard let digest = record.fingerprint, digest == fingerprint(block) else { return true }
        return (record.dueAt ?? record.reviewedAt.addingTimeInterval(record.rating == "known" ? 86400 : 0)) <= now
    }
    static func record(_ block: ContentBlock, rating: String, previous: ReviewRecord?, now: Date = Date()) -> ReviewRecord {
        let same = previous?.fingerprint == fingerprint(block)
        let streak = rating == "known" ? (same ? previous?.streak ?? 0 : 0) + 1 : 0
        let days = [1, 3, 7, 14, 30, 60]
        let delay: TimeInterval = rating == "again" ? 600 : rating == "hard" ? 86400 : Double(days[min(streak - 1, days.count - 1)]) * 86400
        return ReviewRecord(blockID: block.id, rating: rating, reviewedAt: now, attempts: (previous?.attempts ?? 0) + 1, dueAt: now.addingTimeInterval(delay), streak: streak, fingerprint: fingerprint(block))
    }
    static func question(_ block: ContentBlock, in note: Note) -> String {
        if let question = block.reviewQuestion?.trimmingCharacters(in: .whitespacesAndNewlines), !question.isEmpty { return question }
        if block.kind == .formula {
            let index = note.blocks.firstIndex { $0.id == block.id } ?? 0
            let topic = note.blocks.prefix(index).last { $0.kind == .heading }?.text ?? note.title
            return "\(topic)中，这一公式如何表示？各符号代表什么？"
        }
        return block.kind == .term ? "什么是\(block.text)？请用自己的话解释。" : "如何解释“\(block.text)”？"
    }
    static func queue(notes: [Note], records: [ReviewRecord], filter: String, now: Date = Date()) -> [String] {
        notes.flatMap(\.blocks).filter { block in
            guard block.isReviewCard else { return false }
            let record = records.first { $0.blockID == block.id }
            switch filter {
            case "all": return true
            case "new": return record == nil
            case "again": return record?.rating == "again" || record?.rating == "hard"
            default: return isDue(block, record: record, now: now)
            }
        }.map(\.id)
    }
}

struct StudySession: Codable, Equatable {
    var bookID: String
    var filter = "due"
    var queue: [String]
    var index = 0
    var revealed = false
    var ratings: [String: String] = [:]
    var repeated: [String] = []
    var skipped = 0
    var updatedAt = Date()
    var currentID: String? { queue.indices.contains(index) ? queue[index] : nil }
    var completed: Bool { currentID == nil }
    mutating func advance(rating: String? = nil) {
        guard let id = currentID else { return }
        if let rating {
            ratings[id] = rating
            if rating == "again", !repeated.contains(id) {
                queue.insert(id, at: min(index + 3, queue.count)); repeated.append(id)
            }
        } else { skipped += 1 }
        index += 1; revealed = false; updatedAt = Date()
    }
    func isValid(for blocks: [ContentBlock]) -> Bool {
        let ids = Set(blocks.filter(\.isReviewCard).map(\.id))
        return index >= 0 && index <= queue.count && queue.allSatisfy { ids.contains($0) }
    }
}

enum SourceImageLayout {
    static func fit(image: CGSize, viewport: CGSize) -> CGSize {
        guard image.width > 0, image.height > 0 else { return .zero }
        let factor = min(max(1, viewport.width - 24) / image.width, max(1, viewport.height - 24) / image.height)
        return CGSize(width: image.width * factor, height: image.height * factor)
    }
}

/// Keeps editorial status out of finished learning content; raw evidence and chat stay intact.
enum LearningEditorial {
    private static let markers = ["待核对", "待确认", "待核实", "待校对", "待考证", "保留原稿拼写", "原稿编号有重复", "原稿有重复", "不悄悄替换", "不能悄悄替换", "未依据常识补全", "缺字未猜写", "未重新绘制或校正"]
    static func marker(in text: String) -> String? {
        let compact = text.filter { !$0.isWhitespace && $0 != "\u{200B}" && $0 != "\u{FEFF}" }
        return markers.first { compact.contains($0) }
    }
    static func tagMarker(in text: String) -> String? {
        if let marker = marker(in: text) { return marker }
        let value = text.filter { !$0.isWhitespace && $0 != "#" && $0 != "\u{200B}" && $0 != "\u{FEFF}" }
        return ["已核对", "已确认", "已核实", "已校对", "待补充", "待验证", "存疑"].first { value == $0 }
    }
    static func issue(_ plan: AIPlan) -> String? {
        for note in plan.notes {
            for (field, value) in [("笔记标题", note.title), ("笔记本名称", note.notebookTitle), ("章节名称", note.chapterTitle)] {
                if let marker = marker(in: value) { return field + "包含整理备注：" + marker }
            }
            for tag in note.tags {
                if let marker = tagMarker(in: tag) { return "笔记标签包含整理备注：" + marker }
            }
            for block in note.blocks {
                let content = ([block.text, block.detail, block.reviewQuestion ?? "", block.diagram?.accessibleDescription ?? ""] + block.rows.flatMap { $0 }).joined(separator: "\n")
                if let marker = marker(in: content) { return "学习内容包含整理备注：" + marker }
            }
        }
        return nil
    }
    static let repairInstructions = """
    这是保存前的成品检查。先用已提供的原稿、上下文和可靠知识核清疑点，再完成修订；删除“待核对”等词本身不等于事实已经核实，不能把不确定的结论改成肯定句来通过检查。未能确认的具体原文或事实只在 message 说明；若影响整篇成立，改为 action=ask 提出一次具体问题，或 action=reply 说明尚缺什么依据，notes 必须为空，不能伪造一个完成版本。
    返回 write 时，只允许修订块的 text/detail/rows/reviewQuestion 和顶层 message；仅当笔记标题、笔记本名称、章节名称或图中标签本身含整理备注时，才可清理对应文字。tags 仅删除含整理备注的标签，其余标签原样保留，不增加“已核对”“已确认”等替代标签。其他字段、块数、顺序、kind、ID、图形坐标、图元样式、来源和引用逐字不变。保留已确认的知识、条件和例子，不扩写新知识；所有仍未解决的信息在 message 具体说明，不得仅删提醒后隐藏问题。
    """
    static func adopting(_ candidate: AIPlan, for original: AIPlan) throws -> AIPlan {
        if ["ask", "reply"].contains(candidate.action) {
            guard candidate.notes.isEmpty, !(candidate.message.trimmingCharacters(in: .whitespacesAndNewlines)).isEmpty,
                  (candidate.action == "ask" ? !candidate.questions.isEmpty : candidate.questions.isEmpty),
                  (candidate.searchQueries ?? []).isEmpty else { throw AppFailure(message: "核对结果不完整，已保留对话草稿，未写入笔记。") }
            return candidate
        }
        // Repair prose and contaminated labels only; source identity and diagram geometry stay fixed.
        guard candidate.action == "write", candidate.questions.isEmpty, candidate.notes.count == original.notes.count else { throw AppFailure(message: "正文整理未完成，已保留草稿。") }
        var expected = original; expected.message = candidate.message
        for i in original.notes.indices {
            let before = original.notes[i], after = candidate.notes[i]
            if marker(in: before.title) != nil { expected.notes[i].title = after.title }
            if marker(in: before.notebookTitle) != nil { expected.notes[i].notebookTitle = after.notebookTitle }
            if marker(in: before.chapterTitle) != nil { expected.notes[i].chapterTitle = after.chapterTitle }
            expected.notes[i].tags = before.tags.filter { tagMarker(in: $0) == nil }
            guard after.blocks.count == before.blocks.count else { throw AppFailure(message: "正文整理改变了资料结构，已保留草稿。") }
            for j in before.blocks.indices {
                expected.notes[i].blocks[j].text = after.blocks[j].text
                expected.notes[i].blocks[j].detail = after.blocks[j].detail
                expected.notes[i].blocks[j].rows = after.blocks[j].rows
                expected.notes[i].blocks[j].reviewQuestion = after.blocks[j].reviewQuestion
                if var diagram = before.blocks[j].diagram, let repaired = after.blocks[j].diagram, diagram.elements.count == repaired.elements.count {
                    if marker(in: diagram.xLabel) != nil { diagram.xLabel = repaired.xLabel }
                    if marker(in: diagram.yLabel) != nil { diagram.yLabel = repaired.yLabel }
                    for k in diagram.elements.indices where marker(in: diagram.elements[k].label) != nil { diagram.elements[k].label = repaired.elements[k].label }
                    expected.notes[i].blocks[j].diagram = diagram
                }
            }
        }
        let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
        guard try encoder.encode(expected) == encoder.encode(candidate), issue(candidate) == nil else { throw AppFailure(message: "正文仍需完善，已保留对话草稿和原稿，未写入笔记。") }
        return candidate
    }
}
