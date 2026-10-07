import SwiftUI
import AppKit

struct PointerObserver: NSViewRepresentable {
    var onDown: (CGPoint, CGRect, NSWindow) -> Void
    var onEscape: (() -> Void)? = nil
    var onKey: ((NSEvent) -> Bool)? = nil
    func makeNSView(context: Context) -> ObserverView {
        let view = ObserverView()
        view.onDown = onDown; view.onEscape = onEscape; view.onKey = onKey
        return view
    }
    func updateNSView(_ view: ObserverView, context: Context) { view.onDown = onDown; view.onEscape = onEscape; view.onKey = onKey }
    static func dismantleNSView(_ view: ObserverView, coordinator: ()) { view.stop() }
    final class ObserverView: NSView {
        var onDown: ((CGPoint, CGRect, NSWindow) -> Void)?
        var onEscape: (() -> Void)?
        var onKey: ((NSEvent) -> Bool)?
        private var monitor: Any?
        override var isFlipped: Bool { true }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow(); stop()
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown]) { [weak self] event in
                guard let self, let window = self.window, event.window == window else { return event }
                if event.type == .keyDown {
                    if event.keyCode == 53, let onEscape = self.onEscape { onEscape(); return nil }
                    if self.onKey?(event) == true { return nil }
                } else { self.onDown?(self.convert(event.locationInWindow, from: nil), self.bounds, window) }
                return event
            }
        }
        func stop() { if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil } }
        deinit { if let monitor { NSEvent.removeMonitor(monitor) } }
    }
}
