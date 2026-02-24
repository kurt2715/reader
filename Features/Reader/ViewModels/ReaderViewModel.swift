import Foundation

final class ReaderViewModel: ObservableObject {
    let book: Book

    init(book: Book) {
        self.book = book
    }
}
