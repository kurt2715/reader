import Foundation

enum AppRoute {
    case library
    case reader(Book)
}

final class AppRouter: ObservableObject {
    @Published var currentRoute: AppRoute = .library

    func open(book: Book) {
        currentRoute = .reader(book)
    }

    func showLibrary() {
        currentRoute = .library
    }
}
