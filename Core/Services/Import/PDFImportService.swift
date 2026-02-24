import Foundation
import PDFKit

enum PDFImportError: LocalizedError {
    case unreadableFile(URL)

    var errorDescription: String? {
        switch self {
        case let .unreadableFile(url):
            return "Could not open PDF: \(url.lastPathComponent)"
        }
    }
}

final class PDFImportService {
    func importBook(from url: URL) throws -> Book {
        let hasAccess = url.startAccessingSecurityScopedResource()
        defer {
            if hasAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }

        guard PDFDocument(url: url) != nil else {
            throw PDFImportError.unreadableFile(url)
        }

        let title = url.deletingPathExtension().lastPathComponent
        let document = PDFDocument(url: url)
        let toc = document.map(extractTOC(from:)) ?? []
        return Book(title: title, sourceURL: url, format: .pdf, tableOfContents: toc)
    }

    private func extractTOC(from document: PDFDocument) -> [BookTOCItem] {
        guard let root = document.outlineRoot else { return [] }
        return outlineChildren(from: root, document: document)
    }

    private func outlineChildren(from parent: PDFOutline, document: PDFDocument) -> [BookTOCItem] {
        guard parent.numberOfChildren > 0 else { return [] }
        var result: [BookTOCItem] = []
        for index in 0 ..< parent.numberOfChildren {
            guard let child = parent.child(at: index) else { continue }
            let title = (child.label ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else {
                let nested = outlineChildren(from: child, document: document)
                result.append(contentsOf: nested)
                continue
            }

            let token: String
            let actionDestinationPage: PDFPage?
            if let action = child.action as? PDFActionGoTo {
                actionDestinationPage = action.destination.page
            } else {
                actionDestinationPage = nil
            }
            if let page = child.destination?.page ?? actionDestinationPage {
                let pageIndex = max(0, document.index(for: page))
                token = "pdf-page:\(pageIndex)"
            } else {
                let nested = outlineChildren(from: child, document: document)
                if !nested.isEmpty {
                    result.append(contentsOf: nested)
                }
                continue
            }

            result.append(BookTOCItem(
                title: title,
                token: token,
                children: outlineChildren(from: child, document: document)
            ))
        }
        return result
    }
}
