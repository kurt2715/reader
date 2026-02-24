import AppKit
import Combine

final class WindowManager: ObservableObject {
    static let shared = WindowManager()

    @Published var preferences = ReaderPreferences()

    private let transparencyController = TransparencyController()

    private init() {}

    func applyCurrentStyleToMainWindowIfNeeded() {
        guard let window = NSApplication.shared.windows.first else { return }

        if preferences.transparencyEnabled {
            transparencyController.apply(
                style: .transparent(opacity: preferences.opacity),
                to: window
            )
        } else {
            transparencyController.apply(style: .normal, to: window)
        }
    }

    func toggleTransparency() {
        preferences.transparencyEnabled.toggle()
        applyCurrentStyleToMainWindowIfNeeded()
    }

    func setOpacity(_ value: Double) {
        preferences.opacity = clampedOpacity(value)
        applyCurrentStyleToMainWindowIfNeeded()
    }

    func adjustOpacity(by delta: Double) {
        setOpacity(preferences.opacity + delta)
    }

    func setFontSize(_ value: Double) {
        preferences.fontSize = clampedFontSize(value)
    }

    func adjustFontSize(by delta: Double) {
        setFontSize(preferences.fontSize + delta)
    }

    func setFontColor(_ color: ReaderFontColor) {
        preferences.fontColor = color
    }

    func setPDFReadingMode(_ mode: PDFReadingMode) {
        preferences.pdfReadingMode = mode
    }

    private func clampedOpacity(_ value: Double) -> Double {
        min(max(value, 0.5), 1.0)
    }

    private func clampedFontSize(_ value: Double) -> Double {
        min(max(value, 12.0), 42.0)
    }
}
