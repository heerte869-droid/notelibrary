import SwiftUI
import AppKit

/// This local drag keeps the native text fields selectable and commits only on
/// mouse-up. Escape and releases outside the editor leave the draft unchanged.
struct BlockDragHandle: NSViewRepresentable {
    let block: ContentBlock
    let onBegin: () -> Void
    let onMove: (CGPoint) -> Void
    let onEnd: (CGPoint, Bool) -> Void
    func makeNSView(context: Context) -> HandleView { HandleView() }
    func updateNSView(_ view: HandleView, context: Context) {
        view.onBegin = onBegin; view.onMove = onMove; view.onEnd = onEnd
        view.setAccessibilityLabel("拖动内容块：" + block.kind.label + "，" + String(block.text.prefix(24)))
    }
    final class HandleView: NSView {
        var onBegin: () -> Void = {}
        var onMove: (CGPoint) -> Void = { _ in }
        var onEnd: (CGPoint, Bool) -> Void = { _, _ in }
        private var downPoint: NSPoint?
        private var lastWindowPoint: NSPoint = .zero
        private var dragging = false
        private var scrollTimer: Timer?
        override var acceptsFirstResponder: Bool { true }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            setAccessibilityElement(true); setAccessibilityRole(.group)
            setAccessibilityHelp("拖动调整内容顺序；也可使用上移、下移按钮")
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
        override func draw(_ dirtyRect: NSRect) {
            NSColor.secondaryLabelColor.withAlphaComponent(0.65).setFill()
            for column in 0..<2 { for row in 0..<3 {
                NSBezierPath(ovalIn: NSRect(x: bounds.midX - 4.5 + CGFloat(column) * 6, y: bounds.midY - 7.5 + CGFloat(row) * 6, width: 3, height: 3)).fill()
            } }
        }
        override func resetCursorRects() { addCursorRect(bounds, cursor: .openHand) }
        override func mouseDown(with event: NSEvent) {
            window?.makeFirstResponder(self); downPoint = event.locationInWindow; lastWindowPoint = event.locationInWindow
        }
        override func mouseDragged(with event: NSEvent) {
            guard let downPoint else { return }
            lastWindowPoint = event.locationInWindow
            guard dragging || hypot(lastWindowPoint.x - downPoint.x, lastWindowPoint.y - downPoint.y) > 3 else { return }
            if !dragging {
                dragging = true; onBegin(); NSCursor.closedHand.set()
                let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in self?.scrollAtEdge() }
                scrollTimer = timer; RunLoop.main.add(timer, forMode: .common)
            }
            onMove(editorPoint())
        }
        override func mouseUp(with event: NSEvent) { lastWindowPoint = event.locationInWindow; finish(cancelled: false) }
        override func keyDown(with event: NSEvent) { if event.keyCode == 53, dragging { finish(cancelled: true) } else { super.keyDown(with: event) } }
        override func viewWillMove(toWindow newWindow: NSWindow?) { if newWindow == nil { finish(cancelled: true) }; super.viewWillMove(toWindow: newWindow) }
        private func editorPoint() -> CGPoint {
            guard let content = window?.contentView else { return .zero }
            let point = content.convert(lastWindowPoint, from: nil)
            return CGPoint(x: point.x, y: content.isFlipped ? point.y : content.bounds.height - point.y)
        }
        private func finish(cancelled: Bool) {
            scrollTimer?.invalidate(); scrollTimer = nil; downPoint = nil
            guard dragging else { return }
            let point = editorPoint(); dragging = false; NSCursor.arrow.set(); onEnd(point, cancelled)
        }
        private func scrollAtEdge() {
            guard dragging, let scroll = enclosingScrollView else { return }
            let clip = scroll.contentView
            let point = clip.convert(lastWindowPoint, from: nil)
            guard point.x >= clip.bounds.minX, point.x <= clip.bounds.maxX else { return }
            let edge: CGFloat = 40
            var delta: CGFloat = 0
            if point.y < clip.bounds.minY + edge { delta = -min(10, (clip.bounds.minY + edge - point.y) / 5) }
            else if point.y > clip.bounds.maxY - edge { delta = min(10, (point.y - clip.bounds.maxY + edge) / 5) }
            guard delta != 0 else { return }
            let rect = clip.documentRect
            let y = min(max(rect.minY, clip.bounds.minY + delta), max(rect.minY, rect.maxY - clip.bounds.height))
            clip.scroll(to: NSPoint(x: clip.bounds.minX, y: y)); scroll.reflectScrolledClipView(clip)
            onMove(editorPoint())
        }
        deinit { scrollTimer?.invalidate() }
    }
}
