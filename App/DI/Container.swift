import Foundation

final class Container {
    static let shared = Container()

    let router = AppRouter()
    let libraryViewModel: LibraryViewModel

    private init() {
        let epubImportService = EPUBImportService()
        libraryViewModel = LibraryViewModel(
            txtImportService: TXTImportService(),
            pdfImportService: PDFImportService(),
            epubImportService: epubImportService,
            calibreEBookImportService: CalibreEBookImportService(epubImportService: epubImportService)
        )
    }
}
