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
    let sourceURL: URL
    let format: BookFormat
    let textContent: String?
    let richHTMLContent: String?
    let tableOfContents: [BookTOCItem]

    init(
        id: UUID = UUID(),
        title: String,
        sourceURL: URL,
        format: BookFormat,
        textContent: String? = nil,
        richHTMLContent: String? = nil,
        tableOfContents: [BookTOCItem] = []
    ) {
        self.id = id
        self.title = title
        self.sourceURL = sourceURL
        self.format = format
        self.textContent = textContent
        self.richHTMLContent = richHTMLContent
        self.tableOfContents = tableOfContents
    }
}
