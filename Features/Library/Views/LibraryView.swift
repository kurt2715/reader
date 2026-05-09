import SwiftUI
import UniformTypeIdentifiers

struct LibraryView: View {
    @EnvironmentObject private var windowManager: WindowManager
    @ObservedObject var viewModel: LibraryViewModel
    let onOpenBook: (Book) -> Void

    @State private var showingImporter = false
    @State private var bookPendingRemoval: Book?
    @State private var bookPendingMetadataEdit: Book?
    @State private var metadataTitleDraft = ""
    @State private var metadataAuthorDraft = ""
    @State private var searchText = ""
    @State private var isSearchVisible = false
    @FocusState private var isSearchFieldFocused: Bool

    var body: some View {
        ZStack {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("Library")
                        .font(.largeTitle)
                        .bold()
                        .foregroundStyle(libraryForegroundColor)

                    Spacer()

                    if !viewModel.books.isEmpty, isSearchVisible {
                        TextField("Search", text: $searchText)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 220)
                            .focused($isSearchFieldFocused)
                            .onSubmit {
                                hideSearch()
                            }
                    }

                    if !viewModel.books.isEmpty {
                        Button {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                isSearchVisible.toggle()
                                if !isSearchVisible {
                                    searchText = ""
                                    isSearchFieldFocused = false
                                } else {
                                    isSearchFieldFocused = true
                                }
                            }
                        } label: {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 18, weight: .semibold))
                                .frame(width: 28, height: 28)
                        }
                        .foregroundStyle(libraryForegroundColor)
                        .help("Search")
                        .buttonStyle(.borderless)
                    }

                    Button {
                        showingImporter = true
                    } label: {
                        Image(systemName: "tray.and.arrow.down")
                            .font(.system(size: 18, weight: .semibold))
                            .frame(width: 28, height: 28)
                    }
                    .foregroundStyle(libraryForegroundColor)
                    .help("Import File")
                    .buttonStyle(.borderless)
                    .disabled(viewModel.isImporting)
                }

                if viewModel.books.isEmpty {
                    ContentUnavailableView(
                        "No books yet",
                        systemImage: "books.vertical",
                        description: Text("Import .txt, .pdf, .epub, .mobi or .azw3 to start reading.")
                    )
                    .foregroundStyle(libraryForegroundColor)
                } else if filteredBooks.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                        .foregroundStyle(libraryForegroundColor)
                } else {
                    List(filteredBooks) { book in
                        Button {
                            onOpenBook(book)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(book.displayTitleAndAuthor)
                                    .font(.headline)
                            }
                            .padding(.vertical, 8)
                            .foregroundStyle(libraryForegroundColor)
                            .help(book.sourceURL.path)
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(Color.clear)
                        .contextMenu {
                            Button("Edit Metadata") {
                                beginMetadataEdit(for: book)
                            }
                            Button("Remove from Home", role: .destructive) {
                                bookPendingRemoval = book
                            }
                        }
                    }
                    .scrollContentBackground(.hidden)
                    .background(Color.clear)
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
        .sheet(item: $bookPendingMetadataEdit) { book in
            MetadataEditorSheet(
                book: book,
                title: $metadataTitleDraft,
                author: $metadataAuthorDraft,
                onCancel: {
                    bookPendingMetadataEdit = nil
                },
                onSave: {
                    viewModel.updateMetadata(
                        for: book,
                        title: metadataTitleDraft,
                        author: metadataAuthorDraft
                    )
                    bookPendingMetadataEdit = nil
                }
            )
        }
        .onChange(of: isSearchFieldFocused) { _, focused in
            if !focused, isSearchVisible {
                hideSearch()
            }
        }
    }

    private func hideSearch() {
        withAnimation(.easeInOut(duration: 0.15)) {
            isSearchVisible = false
            searchText = ""
            isSearchFieldFocused = false
        }
    }

    private var libraryForegroundColor: Color {
        windowManager.preferences.fontColor == .white ? .white : .black
    }

    private var filteredBooks: [Book] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return viewModel.books }

        return viewModel.books.filter { book in
            let searchableValues = [
                book.title,
                book.author ?? "",
                book.displayTitleAndAuthor,
                book.sourceURL.lastPathComponent,
                book.sourceURL.deletingPathExtension().lastPathComponent,
                book.sourceURL.path
            ]
            return searchableValues.contains { value in
                value.localizedCaseInsensitiveContains(query)
            }
        }
    }

    private func beginMetadataEdit(for book: Book) {
        metadataTitleDraft = book.title
        metadataAuthorDraft = book.author ?? ""
        bookPendingMetadataEdit = book
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

private struct MetadataEditorSheet: View {
    let book: Book
    @Binding var title: String
    @Binding var author: String
    let onCancel: () -> Void
    let onSave: () -> Void

    private var canSave: Bool {
        title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Edit Metadata")
                .font(.headline)

            VStack(alignment: .leading, spacing: 10) {
                TextField("Title", text: $title)
                    .textFieldStyle(.roundedBorder)
                TextField("Author", text: $author)
                    .textFieldStyle(.roundedBorder)
            }

            Text(book.sourceURL.path)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .truncationMode(.middle)

            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Save", action: onSave)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSave)
            }
        }
        .padding(20)
        .frame(width: 420)
    }
}
