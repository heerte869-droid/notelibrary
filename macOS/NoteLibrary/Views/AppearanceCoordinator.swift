import AppKit
import QuartzCore
import SwiftUI

@MainActor final class AppearanceCoordinator {
    static let shared = AppearanceCoordinator()
    private struct Snapshot { let window: NSWindow; let bounds: CGRect; let image: CGImage }
    private var prepared: [Snapshot] = []
    private var preparedAppearance: NSAppearance.Name?
    private var overlays: [(layer: CALayer, origin: CGPoint)] = []
    private weak var controls: NSView?
    private var controlRect = CGRect.zero
    private var warmup: DispatchWorkItem?
    private var revision = 0
    private(set) var isTransitioning = false

    func register(_ view: NSView) {
        let rect = view.convert(view.bounds, to: nil)
        guard controls !== view || controlRect != rect else { return }
        controls = view; controlRect = rect
        prepareSoon()
    }
    func unregister(_ view: NSView) {
        guard controls === view else { return }
        controls = nil; warmup?.cancel(); prepared.removeAll()
    }
    private func prepareSoon() {
        warmup?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.prepare() }
        warmup = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: item)
    }
    private func prepare() {
        guard !isTransitioning, let controls, controls.window != nil,
              !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
        let start = CACurrentMediaTime()
        prepared.removeAll()
        preparedAppearance = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua])
        // Only the foreground settings surface animates. Recapturing the obscured
        // chat would traverse a potentially huge message tree and stall the next click.
        for window in NSApp.windows where window.isVisible && window.level == .normal && window === controls.window {
            guard let view = window.contentView, view.bounds.width > 0, view.bounds.height > 0 else { continue }
            // One pixel per point is enough for a short overlay and avoids Retina-sized captures.
            let size = view.bounds.size
            guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(ceil(size.width)), pixelsHigh: Int(ceil(size.height)), bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { continue }
            bitmap.size = size
            view.cacheDisplay(in: view.bounds, to: bitmap)
            if controls.window == window, let context = NSGraphicsContext(bitmapImageRep: bitmap)?.cgContext {
                var rect = view.convert(controls.bounds, from: controls).insetBy(dx: -4, dy: -4)
                if view.isFlipped { rect.origin.y = view.bounds.height - rect.maxY }
                context.clear(rect)
            }
            if let image = bitmap.cgImage { prepared.append(Snapshot(window: window, bounds: view.bounds, image: image)) }
        }
        metric("prepare", milliseconds: (CACurrentMediaTime() - start) * 1000, snapshots: prepared.count)
    }

    func apply(_ preference: String, animated: Bool) {
        guard let application = NSApp else { return }
        let start = CACurrentMediaTime()
        revision += 1
        let token = revision
        warmup?.cancel(); removeOverlays()
        let animate = animated && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let previous = application.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua])
        let point = application.currentEvent?.type == .keyDown
            ? application.keyWindow.map { CGPoint(x: $0.frame.midX, y: $0.frame.midY) } ?? NSEvent.mouseLocation
            : NSEvent.mouseLocation
        var radius: CGFloat = 1
        // Prepared snapshots provide a circular reveal. The layer transition below
        // keeps first clicks, resized windows and rapid reversals animated too.
        if animate && preparedAppearance == previous {
            for snapshot in prepared where snapshot.window.isVisible {
                guard let view = snapshot.window.contentView, view.bounds == snapshot.bounds else { continue }
                view.wantsLayer = true
                let layer = CALayer()
                layer.frame = view.bounds; layer.contents = snapshot.image; layer.contentsGravity = .resize
                layer.contentsScale = 1; layer.zPosition = 10000
                let origin = view.convert(snapshot.window.convertPoint(fromScreen: point), from: nil)
                radius = max(radius, Self.coveringRadius(bounds: view.bounds, origin: origin))
                view.layer?.addSublayer(layer)
                overlays.append((layer, origin))
            }
        }
        prepared.removeAll()
        let appearance = preference == "system" ? nil : NSAppearance(named: preference == "dark" ? .darkAqua : .aqua)
        let animatedWindows = application.windows.filter { $0.isVisible && $0.level == .normal }
        if animate {
            for window in animatedWindows where !overlays.contains(where: { $0.layer.superlayer === window.contentView?.layer }) {
                guard let view = window.contentView else { continue }
                view.wantsLayer = true
                let fade = CATransition()
                fade.type = .fade; fade.duration = 0.22
                fade.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                view.layer?.add(fade, forKey: "theme-fallback")
            }
        }
        application.appearance = appearance
        for window in application.windows { window.appearance = appearance; window.contentView?.needsDisplay = true }
        metric("apply", milliseconds: (CACurrentMediaTime() - start) * 1000, snapshots: overlays.count)
        guard animate, previous != application.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) else { removeOverlays(); prepareSoon(); return }
        guard !overlays.isEmpty else {
            isTransitioning = true
            metric("fallbackFade", milliseconds: (CACurrentMediaTime() - start) * 1000, snapshots: 0)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.23) { [weak self] in
                guard let self, self.revision == token else { return }
                self.isTransitioning = false; self.prepareSoon()
            }
            return
        }
        isTransitioning = true
        let endRadius = radius
        DispatchQueue.main.async { [weak self] in
            guard let self, self.revision == token else { return }
            self.metric("nextFrameScheduled", milliseconds: (CACurrentMediaTime() - start) * 1000, snapshots: self.overlays.count)
            CATransaction.begin(); CATransaction.setDisableActions(true)
            for item in self.overlays {
                let mask = CAShapeLayer(); mask.frame = item.layer.bounds; mask.fillRule = .evenOdd
                let begin = Self.revealMask(bounds: item.layer.bounds, origin: item.origin, radius: 0.1)
                let end = Self.revealMask(bounds: item.layer.bounds, origin: item.origin, radius: endRadius)
                mask.path = end; item.layer.mask = mask
                let reveal = CABasicAnimation(keyPath: "path")
                reveal.fromValue = begin; reveal.toValue = end; reveal.duration = 0.28
                reveal.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.65, 0.25, 1)
                mask.add(reveal, forKey: "theme-reveal")
            }
            CATransaction.commit()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.30) { [weak self] in
                guard let self, self.revision == token else { return }
                self.removeOverlays(); self.prepareSoon()
            }
        }
    }
    static func coveringRadius(bounds: CGRect, origin: CGPoint) -> CGFloat {
        hypot(max(abs(origin.x - bounds.minX), abs(origin.x - bounds.maxX)), max(abs(origin.y - bounds.minY), abs(origin.y - bounds.maxY))) + 2
    }
    private static func revealMask(bounds: CGRect, origin: CGPoint, radius: CGFloat) -> CGPath {
        let path = CGMutablePath(); path.addRect(bounds)
        path.addEllipse(in: CGRect(x: origin.x - radius, y: origin.y - radius, width: radius * 2, height: radius * 2))
        return path
    }
    private func removeOverlays() { overlays.forEach { $0.layer.removeFromSuperlayer() }; overlays.removeAll(); isTransitioning = false }
    private func metric(_ event: String, milliseconds: Double, snapshots: Int) {
        guard let path = Bundle.main.object(forInfoDictionaryKey: "NoteLibraryInteractionLog") as? String else { return }
        let line = "\(event) \(String(format: "%.2f", milliseconds)) ms snapshots=\(snapshots)\n"
        if !FileManager.default.fileExists(atPath: path) { FileManager.default.createFile(atPath: path, contents: nil) }
        if let handle = FileHandle(forWritingAtPath: path) { _ = try? handle.seekToEnd(); try? handle.write(contentsOf: Data(line.utf8)); try? handle.close() }
    }
}

struct ThemeTransitionAnchor: NSViewRepresentable {
    func makeNSView(context: Context) -> AnchorView { AnchorView() }
    func updateNSView(_ view: AnchorView, context: Context) { AppearanceCoordinator.shared.register(view) }
    static func dismantleNSView(_ view: AnchorView, coordinator: ()) { AppearanceCoordinator.shared.unregister(view) }
    final class AnchorView: NSView {
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); AppearanceCoordinator.shared.register(self) }
        override func setFrameSize(_ newSize: NSSize) { super.setFrameSize(newSize); AppearanceCoordinator.shared.register(self) }
    }
}
