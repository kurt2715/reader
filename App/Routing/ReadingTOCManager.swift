import Foundation

struct ReaderTOCItem: Identifiable, Hashable {
    let id: String
    let title: String
    let token: String
    let children: [ReaderTOCItem]

    var optionalChildren: [ReaderTOCItem]? {
        children.isEmpty ? nil : children
    }
}

struct ReaderTOCProvider {
    let items: () -> [ReaderTOCItem]
    let activate: (_ token: String) -> Void
}

final class ReadingTOCManager: ObservableObject {
    static let shared = ReadingTOCManager()

    @Published var visibleItems: [ReaderTOCItem] = []

    private var activeOwner: String?
    private var provider: ReaderTOCProvider?

    private init() {}

    func register(owner: String, provider: ReaderTOCProvider) {
        activeOwner = owner
        self.provider = provider
        visibleItems = provider.items()
    }

    func unregister(owner: String) {
        guard activeOwner == owner else { return }
        activeOwner = nil
        provider = nil
        visibleItems = []
    }

    func refresh() {
        visibleItems = provider?.items() ?? []
    }

    func activate(token: String) {
        guard let provider else { return }
        ReadingNavigationManager.shared.pushCurrentPosition()
        provider.activate(token)
    }
}
