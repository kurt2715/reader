import AppKit

final class TransparentWindowAdapter {
    func applyNormalStyle(to window: NSWindow) {
        applyChromeStyle(to: window)
        window.isOpaque = true
        window.backgroundColor = .windowBackgroundColor
        window.hasShadow = true
        window.alphaValue = 1.0
    }

    func applyTransparentStyle(to window: NSWindow, opacity: Double) {
        let clampedOpacity = min(max(opacity, 0.5), 1.0)

        applyChromeStyle(to: window)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.alphaValue = clampedOpacity
    }

    private func applyChromeStyle(to window: NSWindow) {
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.styleMask.insert(.fullSizeContentView)
        window.toolbar = nil
        window.titlebarSeparatorStyle = .none

        window.standardWindowButton(.closeButton)?.isHidden = true
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
    }
}
