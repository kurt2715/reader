import Foundation

struct ToggleTransparencyCommand {
    func execute() {
        WindowManager.shared.toggleTransparency()
    }
}
