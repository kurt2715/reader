import Foundation

enum BookFormat: String, Hashable {
    case txt
    case pdf
    case epub
    case mobi
    case azw3
}

struct BookTOCItem: Identifiable, Hashable {
    let id: String
    let title: String
    let token: String
    let children: [BookTOCItem]

    init(id: String = UUID().uuidString, title: String, token: String, children: [BookTOCItem] = []) {
        self.id = id
        self.title = title
        self.token = token
        self.children = children
    }
}

struct Book: Identifiable, Hashable {
    let id: UUID
    let title: String
    let author: String?
    let sourceURL: URL
    let format: BookFormat
    let textContent: String?
    let richHTMLContent: String?
    let tableOfContents: [BookTOCItem]
    let usesCustomMetadata: Bool

    var displayTitleAndAuthor: String {
        guard let author, !author.isEmpty else { return title }
        return "\(title) - \(author)"
    }

    init(
        id: UUID = UUID(),
        title: String,
        author: String? = nil,
        sourceURL: URL,
        format: BookFormat,
        textContent: String? = nil,
        richHTMLContent: String? = nil,
        tableOfContents: [BookTOCItem] = [],
        usesCustomMetadata: Bool = false
    ) {
        self.id = id
        self.title = title
        self.author = author
        self.sourceURL = sourceURL
        self.format = format
        self.textContent = textContent
        self.richHTMLContent = richHTMLContent
        self.tableOfContents = tableOfContents
        self.usesCustomMetadata = usesCustomMetadata
    }

    func replacingMetadata(title: String, author: String?, usesCustomMetadata: Bool = true) -> Book {
        Book(
            id: id,
            title: title,
            author: author,
            sourceURL: sourceURL,
            format: format,
            textContent: textContent,
            richHTMLContent: richHTMLContent,
            tableOfContents: tableOfContents,
            usesCustomMetadata: usesCustomMetadata
        )
    }

    func preservingCustomMetadata(from existing: Book) -> Book {
        guard existing.usesCustomMetadata else { return self }
        return Book(
            id: existing.id,
            title: existing.title,
            author: existing.author,
            sourceURL: sourceURL,
            format: format,
            textContent: textContent,
            richHTMLContent: richHTMLContent,
            tableOfContents: tableOfContents,
            usesCustomMetadata: true
        )
    }
}
