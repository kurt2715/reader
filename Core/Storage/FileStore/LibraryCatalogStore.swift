import Foundation

struct PersistedBookEntry: Codable {
    let title: String
    let sourcePath: String
    let formatRawValue: String
}

final class LibraryCatalogStore {
    static let shared = LibraryCatalogStore()

    private let fileURL: URL

    init(fileManager: FileManager = .default) {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("Reader", isDirectory: true)
        if !fileManager.fileExists(atPath: dir.path) {
            try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        fileURL = dir.appendingPathComponent("library_catalog.json")
    }

    func load() -> [PersistedBookEntry] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        guard let entries = try? JSONDecoder().decode([PersistedBookEntry].self, from: data) else { return [] }
        return entries
    }

    func save(_ entries: [PersistedBookEntry]) {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
