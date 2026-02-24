import Foundation

struct ToggleTransparencyCommand {
    func execute() {
        WindowManager.shared.preferences.transparencyEnabled.toggle()
        WindowManager.shared.applyCurrentStyleToMainWindowIfNeeded()
    }
}
