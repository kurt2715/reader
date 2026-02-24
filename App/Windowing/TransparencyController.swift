import AppKit

final class TransparencyController {
    private let adapter = TransparentWindowAdapter()

    func apply(style: WindowStyle, to window: NSWindow) {
        switch style {
        case .normal:
            adapter.applyNormalStyle(to: window)
        case let .transparent(opacity):
            adapter.applyTransparentStyle(to: window, opacity: opacity)
        }
    }
}
