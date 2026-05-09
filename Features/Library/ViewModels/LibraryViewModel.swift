import Foundation

enum BookImportError: LocalizedError {
    case unsupportedFileType(URL)

    var errorDescription: String? {
        switch self {
        case let .unsupportedFileType(url):
            return "Unsupported file type: \(url.lastPathComponent)"
        }
    }
}

final class LibraryViewModel: ObservableObject {
    @Published private(set) var books: [Book] = []
    @Published var importErrorMessage: String?
    @Published var isImporting = false

    private let txtImportService: TXTImportService
    private let pdfImportService: PDFImportService
    private let epubImportService: EPUBImportService
    private let calibreEBookImportService: CalibreEBookImportService
    private let catalogStore: LibraryCatalogStore

    init(
        txtImportService: TXTImportService,
        pdfImportService: PDFImportService,
        epubImportService: EPUBImportService,
        calibreEBookImportService: CalibreEBookImportService,
        catalogStore: LibraryCatalogStore = .shared
    ) {
        self.txtImportService = txtImportService
        self.pdfImportService = pdfImportService
        self.epubImportService = epubImportService
        self.calibreEBookImportService = calibreEBookImportService
        self.catalogStore = catalogStore

        loadCatalog()
        refreshCatalogMetadataIfNeeded()
    }

    func importFiles(from urls: [URL], completion: @escaping ([Book]) -> Void) {
        guard !urls.isEmpty else {
            completion([])
            return
        }

        isImporting = true
        importErrorMessage = nil

        let txtService = txtImportService
        let pdfService = pdfImportService
        let epubService = epubImportService
        let calibreService = calibreEBookImportService

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            var importedBooks: [Book] = []
            var firstErrorMessage: String?

            for url in urls {
                do {
                    let importedBook = try Self.importBook(
                        from: url,
                        txtService: txtService,
                        pdfService: pdfService,
                        epubService: epubService,
                        calibreService: calibreService
                    )
                    importedBooks.append(importedBook)
                } catch {
                    if firstErrorMessage == nil {
                        firstErrorMessage = error.localizedDescription
                    }
                }
            }

            DispatchQueue.main.async {
                guard let self else { return }

                self.mergeImportedBooks(importedBooks)
                self.persistCatalog()
                self.importErrorMessage = firstErrorMessage
                self.isImporting = false
                completion(importedBooks)
            }
        }
    }

    func openBook(_ book: Book, completion: @escaping (Book?) -> Void) {
        // Already hydrated in current session.
        if bookRequiresHydration(book) == false {
            completion(book)
            return
        }

        isImporting = true
        importErrorMessage = nil

        let txtService = txtImportService
        let pdfService = pdfImportService
        let epubService = epubImportService
        let calibreService = calibreEBookImportService
        let sourceURL = book.sourceURL

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result: Result<Book, Error>
            do {
                let hydrated = try Self.importBook(
                    from: sourceURL,
                    txtService: txtService,
                    pdfService: pdfService,
                    epubService: epubService,
                    calibreService: calibreService
                )
                result = .success(hydrated)
            } catch {
                result = .failure(error)
            }

            DispatchQueue.main.async {
                guard let self else { return }
                self.isImporting = false

                switch result {
                case let .success(hydratedBook):
                    let bookToOpen = hydratedBook.preservingCustomMetadata(from: book)
                    self.mergeImportedBooks([bookToOpen])
                    self.persistCatalog()
                    completion(bookToOpen)
                case let .failure(error):
                    self.importErrorMessage = error.localizedDescription
                    completion(nil)
                }
            }
        }
    }

    func removeBookFromLibrary(_ book: Book) {
        books.removeAll { $0.id == book.id }
        persistCatalog()
    }

    func updateMetadata(for book: Book, title: String, author: String?) {
        let cleanedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedTitle.isEmpty else { return }

        let cleanedAuthor = author?.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedAuthor = cleanedAuthor?.isEmpty == false ? cleanedAuthor : nil

        guard let index = books.firstIndex(where: { $0.id == book.id }) else { return }
        books[index] = books[index].replacingMetadata(title: cleanedTitle, author: normalizedAuthor)
        books.sort { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        persistCatalog()
    }

    private func bookRequiresHydration(_ book: Book) -> Bool {
        switch book.format {
        case .txt:
            return book.textContent == nil
        case .epub, .mobi, .azw3:
            return book.textContent == nil && book.richHTMLContent == nil
        case .pdf:
            return false
        }
    }

    private static func importBook(
        from url: URL,
        txtService: TXTImportService,
        pdfService: PDFImportService,
        epubService: EPUBImportService,
        calibreService: CalibreEBookImportService
    ) throws -> Book {
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "txt":
            return try txtService.importBook(from: url)
        case "pdf":
            return try pdfService.importBook(from: url)
        case "epub":
            return try epubService.importBook(from: url)
        case "mobi":
            return try calibreService.importBook(from: url, format: .mobi)
        case "azw3":
            return try calibreService.importBook(from: url, format: .azw3)
        default:
            throw BookImportError.unsupportedFileType(url)
        }
    }

    private func mergeImportedBooks(_ importedBooks: [Book]) {
        guard !importedBooks.isEmpty else { return }

        var mergedBooks = books
        for book in importedBooks {
            if let existingIndex = mergedBooks.firstIndex(where: { $0.sourceURL == book.sourceURL }) {
                mergedBooks[existingIndex] = book.preservingCustomMetadata(from: mergedBooks[existingIndex])
            } else {
                mergedBooks.append(book)
            }
        }

        mergedBooks.sort { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        books = mergedBooks
    }

    private func loadCatalog() {
        let entries = catalogStore.load()
        let loadedBooks: [Book] = entries.compactMap { entry in
            guard let format = BookFormat(rawValue: entry.formatRawValue) else { return nil }
            let url = URL(fileURLWithPath: entry.sourcePath)
            guard FileManager.default.fileExists(atPath: url.path) else { return nil }

            return Book(
                title: entry.title,
                author: entry.author,
                sourceURL: url,
                format: format,
                usesCustomMetadata: entry.usesCustomMetadata ?? false
            )
        }

        books = loadedBooks.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        persistCatalog()
    }

    private func refreshCatalogMetadataIfNeeded() {
        let candidates = books.filter { book in
            switch book.format {
            case .txt:
                return false
            case .pdf, .epub, .mobi, .azw3:
                if book.usesCustomMetadata { return false }
                return book.author == nil || book.title == book.sourceURL.deletingPathExtension().lastPathComponent
            }
        }
        guard !candidates.isEmpty else { return }

        let txtService = txtImportService
        let pdfService = pdfImportService
        let epubService = epubImportService
        let calibreService = calibreEBookImportService

        DispatchQueue.global(qos: .utility).async { [weak self] in
            var refreshedBooks: [Book] = []
            for book in candidates {
                guard let refreshed = try? Self.importBook(
                    from: book.sourceURL,
                    txtService: txtService,
                    pdfService: pdfService,
                    epubService: epubService,
                    calibreService: calibreService
                ) else {
                    continue
                }
                refreshedBooks.append(refreshed)
            }

            guard !refreshedBooks.isEmpty else { return }
            DispatchQueue.main.async {
                guard let self else { return }
                self.mergeImportedBooks(refreshedBooks)
                self.persistCatalog()
            }
        }
    }

    private func persistCatalog() {
        let entries = books.map {
            PersistedBookEntry(
                title: $0.title,
                author: $0.author,
                usesCustomMetadata: $0.usesCustomMetadata,
                sourcePath: $0.sourceURL.path,
                formatRawValue: $0.format.rawValue
            )
        }
        catalogStore.save(entries)
    }
}
