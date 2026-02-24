import Foundation

struct ReaderSearchResult: Identifiable, Hashable {
    let id: String
    let token: String
    let excerpt: String
    let detail: String
}

struct ReaderSearchProvider {
    let search: (_ query: String, _ completion: @escaping ([ReaderSearchResult]) -> Void) -> Void
    let activate: (_ token: String) -> Void
}

final class ReadingSearchManager: ObservableObject {
    static let shared = ReadingSearchManager()

    @Published var isPresented = false
    @Published var query: String = ""
    @Published private(set) var results: [ReaderSearchResult] = []
    @Published private(set) var isSearching = false

    private var activeOwner: String?
    private var provider: ReaderSearchProvider?

    private init() {}

    func register(owner: String, provider: ReaderSearchProvider) {
        activeOwner = owner
        self.provider = provider
    }

    func unregister(owner: String) {
        guard activeOwner == owner else { return }
        activeOwner = nil
        provider = nil
        results = []
        query = ""
        isSearching = false
    }

    func openPanel() {
        isPresented = true
    }

    func closePanel() {
        isPresented = false
    }

    func performSearch() {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else {
            results = []
            return
        }

        guard let provider else {
            results = []
            return
        }

        isSearching = true
        provider.search(term) { [weak self] output in
            DispatchQueue.main.async {
                self?.results = output
                self?.isSearching = false
            }
        }
    }

    func activate(_ result: ReaderSearchResult) {
        guard let provider else { return }
        provider.activate(result.token)
    }
}
