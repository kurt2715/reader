import Foundation

struct BookReadingProgress: Codable {
    var textScrollRatio: Double?
    var pdfPageIndex: Int?
}

final class ReadingProgressStore {
    static let shared = ReadingProgressStore()

    private let fileURL: URL
    private var cache: [String: BookReadingProgress] = [:]

    init(fileManager: FileManager = .default) {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("Reader", isDirectory: true)
        if !fileManager.fileExists(atPath: dir.path) {
            try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        fileURL = dir.appendingPathComponent("reading_progress.json")

        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode([String: BookReadingProgress].self, from: data) {
            cache = decoded
        }
    }

    func progress(for sourcePath: String) -> BookReadingProgress? {
        cache[sourcePath]
    }

    func saveTextScrollRatio(_ ratio: Double, for sourcePath: String) {
        var progress = cache[sourcePath] ?? BookReadingProgress()
        progress.textScrollRatio = min(max(ratio, 0), 1)
        cache[sourcePath] = progress
        flush()
    }

    func savePDFPageIndex(_ pageIndex: Int, for sourcePath: String) {
        var progress = cache[sourcePath] ?? BookReadingProgress()
        progress.pdfPageIndex = max(pageIndex, 0)
        cache[sourcePath] = progress
        flush()
    }

    private func flush() {
        guard let data = try? JSONEncoder().encode(cache) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
