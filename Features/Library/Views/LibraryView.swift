import SwiftUI
import UniformTypeIdentifiers

struct LibraryView: View {
    @ObservedObject var viewModel: LibraryViewModel
    let onOpenBook: (Book) -> Void

    @State private var showingImporter = false
    @State private var bookPendingRemoval: Book?

    var body: some View {
        ZStack {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("Library")
                        .font(.largeTitle)
                        .bold()

                    Spacer()

                    Button("Import File") {
                        showingImporter = true
                    }
                    .disabled(viewModel.isImporting)
                }

                if viewModel.books.isEmpty {
                    ContentUnavailableView(
                        "No books yet",
                        systemImage: "books.vertical",
                        description: Text("Import .txt, .pdf, .epub, .mobi or .azw3 to start reading.")
                    )
                } else {
                    List(viewModel.books) { book in
                        Button {
                            onOpenBook(book)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(book.title)
                                    .font(.headline)
                                Text("\(book.format.rawValue.uppercased()) · \(book.sourceURL.lastPathComponent)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button("Remove from Home", role: .destructive) {
                                bookPendingRemoval = book
                            }
                        }
                    }
                }
            }
            .padding(24)

            if viewModel.isImporting {
                ProgressView("Importing...")
                    .padding(16)
                    .background(.regularMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
        .fileImporter(
            isPresented: $showingImporter,
            allowedContentTypes: supportedContentTypes,
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case let .success(urls):
                viewModel.importFiles(from: urls) { importedBooks in
                    if let firstBook = importedBooks.first {
                        onOpenBook(firstBook)
                    }
                }
            case let .failure(error):
                viewModel.importErrorMessage = error.localizedDescription
            }
        }
        .alert("Import Failed", isPresented: importErrorBinding) {
            Button("OK", role: .cancel) {
                viewModel.importErrorMessage = nil
            }
        } message: {
            Text(viewModel.importErrorMessage ?? "Unknown error")
        }
        .alert(
            "Remove from Home?",
            isPresented: removeAlertBinding,
            presenting: bookPendingRemoval
        ) { book in
            Button("Remove", role: .destructive) {
                viewModel.removeBookFromLibrary(book)
                bookPendingRemoval = nil
            }
            Button("Cancel", role: .cancel) {
                bookPendingRemoval = nil
            }
        } message: { _ in
            Text("This only removes the book from the app home list. The local file will not be deleted.")
        }
    }

    private var supportedContentTypes: [UTType] {
        var types: [UTType] = [.plainText, .utf8PlainText, .text, .pdf, .data]
        if let epub = UTType(filenameExtension: "epub") {
            types.append(epub)
        }
        if let mobi = UTType(filenameExtension: "mobi") {
            types.append(mobi)
        }
        if let azw3 = UTType(filenameExtension: "azw3") {
            types.append(azw3)
        }
        return types
    }

    private var importErrorBinding: Binding<Bool> {
        Binding(
            get: { viewModel.importErrorMessage != nil },
            set: { newValue in
                if !newValue {
                    viewModel.importErrorMessage = nil
                }
            }
        )
    }

    private var removeAlertBinding: Binding<Bool> {
        Binding(
            get: { bookPendingRemoval != nil },
            set: { newValue in
                if !newValue {
                    bookPendingRemoval = nil
                }
            }
        )
    }
}
