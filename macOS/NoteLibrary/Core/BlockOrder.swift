import Foundation

/// Reorder a draft without rebuilding blocks or losing their sources and table data.
enum BlockOrder {
    @discardableResult
    static func move(_ id: String, relativeTo targetID: String, after: Bool, in blocks: inout [ContentBlock]) -> Bool {
        guard id != targetID, let source = blocks.firstIndex(where: { $0.id == id }),
              blocks.contains(where: { $0.id == targetID }) else { return false }
        var updated = blocks
        let block = updated.remove(at: source)
        guard let target = updated.firstIndex(where: { $0.id == targetID }) else { return false }
        updated.insert(block, at: target + (after ? 1 : 0))
        guard updated != blocks else { return false }
        blocks = updated
        return true
    }
}
