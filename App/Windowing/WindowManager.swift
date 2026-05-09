import AppKit
import Combine

final class WindowManager: ObservableObject {
    static let shared = WindowManager()

    @Published var preferences = ReaderPreferences()

    private let transparencyController = TransparencyController()
    private let frameDefaultsKey = "reader.mainWindowFrame"
    private weak var observedMainWindow: NSWindow?
    private var didRestoreMainWindowFrame = false

    private init() {}

    func applyCurrentStyleToMainWindowIfNeeded() {
        guard let window = mainReaderWindow() else { return }
        restoreMainWindowFrameIfNeeded(window)
        observeMainWindowIfNeeded(window)

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
        updatePreferences { preferences in
            preferences.transparencyEnabled.toggle()
            preferences.fontColor = preferences.transparencyEnabled ? .black : .white
        }
        applyCurrentStyleToMainWindowIfNeeded()
    }

    func setOpacity(_ value: Double) {
        updatePreferences { preferences in
            preferences.opacity = clampedOpacity(value)
        }
        applyCurrentStyleToMainWindowIfNeeded()
    }

    func adjustOpacity(by delta: Double) {
        setOpacity(preferences.opacity + delta)
    }

    func setFontSize(_ value: Double) {
        updatePreferences { preferences in
            preferences.fontSize = clampedFontSize(value)
        }
    }

    func adjustFontSize(by delta: Double) {
        setFontSize(preferences.fontSize + delta)
    }

    func setFontColor(_ color: ReaderFontColor) {
        updatePreferences { preferences in
            preferences.fontColor = color
        }
    }

    func setPDFReadingMode(_ mode: PDFReadingMode) {
        updatePreferences { preferences in
            preferences.pdfReadingMode = mode
        }
    }

    private func clampedOpacity(_ value: Double) -> Double {
        min(max(value, 0.5), 1.0)
    }

    private func clampedFontSize(_ value: Double) -> Double {
        min(max(value, 12.0), 42.0)
    }

    private func updatePreferences(_ update: (inout ReaderPreferences) -> Void) {
        var nextPreferences = preferences
        update(&nextPreferences)
        preferences = nextPreferences
    }

    private func mainReaderWindow() -> NSWindow? {
        NSApplication.shared.windows.first { window in
            window.title == "Reader"
        } ?? NSApplication.shared.mainWindow ?? NSApplication.shared.keyWindow
    }

    private func observeMainWindowIfNeeded(_ window: NSWindow) {
        guard observedMainWindow !== window else { return }
        if let observedMainWindow {
            NotificationCenter.default.removeObserver(self, name: NSWindow.didResizeNotification, object: observedMainWindow)
            NotificationCenter.default.removeObserver(self, name: NSWindow.didMoveNotification, object: observedMainWindow)
            NotificationCenter.default.removeObserver(self, name: NSWindow.willCloseNotification, object: observedMainWindow)
        }

        observedMainWindow = window
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(saveMainWindowFrame(_:)),
            name: NSWindow.didResizeNotification,
            object: window
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(saveMainWindowFrame(_:)),
            name: NSWindow.didMoveNotification,
            object: window
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(saveMainWindowFrame(_:)),
            name: NSWindow.willCloseNotification,
            object: window
        )
    }

    private func restoreMainWindowFrameIfNeeded(_ window: NSWindow) {
        guard !didRestoreMainWindowFrame else { return }
        didRestoreMainWindowFrame = true

        guard let storedFrame = UserDefaults.standard.string(forKey: frameDefaultsKey) else { return }
        let frame = NSRectFromString(storedFrame)
        guard frame.width >= 420, frame.height >= 80, frame.isEmpty == false else { return }

        let visibleFrames = NSScreen.screens.map(\.visibleFrame)
        let intersectsVisibleScreen = visibleFrames.contains { $0.intersects(frame) }
        guard intersectsVisibleScreen else { return }

        window.setFrame(frame, display: true)
    }

    @objc private func saveMainWindowFrame(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        UserDefaults.standard.set(NSStringFromRect(window.frame), forKey: frameDefaultsKey)
    }
}
