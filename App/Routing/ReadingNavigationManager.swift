import Foundation

final class ReadingNavigationManager: ObservableObject {
    static let shared = ReadingNavigationManager()

    @Published private(set) var canGoBackPosition = false

    private var pushCurrentPositionAction: (() -> Void)?
    private var goBackAction: (() -> Void)?

    private init() {}

    func register(
        pushCurrentPositionAction: (() -> Void)? = nil,
        goBackAction: @escaping () -> Void,
        canGoBack: Bool
    ) {
        self.pushCurrentPositionAction = pushCurrentPositionAction
        self.goBackAction = goBackAction
        self.canGoBackPosition = canGoBack
    }

    func updateCanGoBack(_ canGoBack: Bool) {
        canGoBackPosition = canGoBack
    }

    func clear() {
        pushCurrentPositionAction = nil
        goBackAction = nil
        canGoBackPosition = false
    }

    func pushCurrentPosition() {
        pushCurrentPositionAction?()
    }

    func goBackToPreviousPosition() {
        goBackAction?()
    }
}
