import SwiftUI

@main
struct ReaderApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var windowManager = WindowManager.shared
    @StateObject private var router = Container.shared.router
    @StateObject private var libraryViewModel = Container.shared.libraryViewModel

    var body: some Scene {
        WindowGroup("Reader") {
            RootView()
                .environmentObject(windowManager)
                .environmentObject(router)
                .environmentObject(libraryViewModel)
        }
        .windowStyle(.hiddenTitleBar)

        Window("全文检索", id: "reader-search") {
            ReaderSearchPanel()
                .frame(minWidth: 520, minHeight: 420)
        }

        Window("目录", id: "reader-toc") {
            ReaderTOCPanel()
                .frame(minWidth: 360, minHeight: 460)
        }

        .commands {
            ReaderCommands()
        }
    }
}

private struct RootView: View {
    @EnvironmentObject private var windowManager: WindowManager
    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var libraryViewModel: LibraryViewModel

    var body: some View {
        Group {
            switch router.currentRoute {
            case .library:
                LibraryView(viewModel: libraryViewModel) { selectedBook in
                    libraryViewModel.openBook(selectedBook) { hydratedBook in
                        guard let hydratedBook else { return }
                        router.open(book: hydratedBook)
                    }
                }
            case let .reader(book):
                ReaderView(book: book)
            }
        }
        .frame(minWidth: 420, minHeight: 80)
        .background(Color.clear)
        .ignoresSafeArea(.container, edges: .top)
        .onAppear {
            windowManager.applyCurrentStyleToMainWindowIfNeeded()
        }
    }
}

private struct ReaderCommands: Commands {
    @Environment(\.openWindow) private var openWindow
    @ObservedObject private var windowManager = WindowManager.shared
    @ObservedObject private var router = Container.shared.router
    @ObservedObject private var navigationManager = ReadingNavigationManager.shared

    var body: some Commands {
        CommandMenu("Reader") {
            Button("返回主页") {
                router.showLibrary()
            }
            .keyboardShortcut("h", modifiers: [.command, .shift])
            .disabled(!isReadingRoute)

            Button("返回上一个位置") {
                navigationManager.goBackToPreviousPosition()
            }
            .keyboardShortcut("[", modifiers: [.command])
            .disabled(!navigationManager.canGoBackPosition)

            Button("全文检索...") {
                openWindow(id: "reader-search")
            }
            .keyboardShortcut("f", modifiers: [.command])
            .disabled(!isReadingRoute)

            Button("目录...") {
                openWindow(id: "reader-toc")
            }
            .keyboardShortcut("t", modifiers: [.command])
            .disabled(!isReadingRoute)

            Divider()

            Button(windowManager.preferences.transparencyEnabled ? "Disable Transparency" : "Enable Transparency") {
                windowManager.toggleTransparency()
            }
            .keyboardShortcut("t", modifiers: [.command, .shift])

            Divider()

            Button("Opacity +10%") {
                windowManager.adjustOpacity(by: 0.1)
            }
            .keyboardShortcut("]", modifiers: [.command, .option])

            Button("Opacity -10%") {
                windowManager.adjustOpacity(by: -0.1)
            }
            .keyboardShortcut("[", modifiers: [.command, .option])

            Divider()

            Button(opacityLabel("100%", value: 1.0)) {
                windowManager.setOpacity(1.0)
            }
            Button(opacityLabel("90%", value: 0.9)) {
                windowManager.setOpacity(0.9)
            }
            Button(opacityLabel("80%", value: 0.8)) {
                windowManager.setOpacity(0.8)
            }
            Button(opacityLabel("70%", value: 0.7)) {
                windowManager.setOpacity(0.7)
            }
            Button(opacityLabel("60%", value: 0.6)) {
                windowManager.setOpacity(0.6)
            }
            Button(opacityLabel("50%", value: 0.5)) {
                windowManager.setOpacity(0.5)
            }

            Divider()

            Button(pdfModeLabel("PDF Original Layout", mode: .original)) {
                windowManager.setPDFReadingMode(.original)
            }
            .disabled(!isReadingPDFRoute)

            Button(pdfModeLabel("PDF Text Mode", mode: .reflowedText)) {
                windowManager.setPDFReadingMode(.reflowedText)
            }
            .disabled(!isReadingPDFRoute)

            Divider()

            Button(fontColorLabel("Font Color White", color: .white)) {
                windowManager.setFontColor(.white)
            }
            Button(fontColorLabel("Font Color Black", color: .black)) {
                windowManager.setFontColor(.black)
            }

            Divider()

            Button("Font +2") {
                windowManager.adjustFontSize(by: 2)
            }
            .keyboardShortcut("=", modifiers: [.command])

            Button("Font -2") {
                windowManager.adjustFontSize(by: -2)
            }
            .keyboardShortcut("-", modifiers: [.command])

            Divider()

            Button(fontLabel("14", value: 14)) {
                windowManager.setFontSize(14)
            }
            Button(fontLabel("18", value: 18)) {
                windowManager.setFontSize(18)
            }
            Button(fontLabel("22", value: 22)) {
                windowManager.setFontSize(22)
            }
            Button(fontLabel("26", value: 26)) {
                windowManager.setFontSize(26)
            }
            Button(fontLabel("30", value: 30)) {
                windowManager.setFontSize(30)
            }
        }
    }

    private func opacityLabel(_ title: String, value: Double) -> String {
        abs(windowManager.preferences.opacity - value) < 0.01 ? "\(title) ✓" : title
    }

    private func fontLabel(_ title: String, value: Double) -> String {
        abs(windowManager.preferences.fontSize - value) < 0.1 ? "Font \(title) ✓" : "Font \(title)"
    }

    private func fontColorLabel(_ title: String, color: ReaderFontColor) -> String {
        windowManager.preferences.fontColor == color ? "\(title) ✓" : title
    }

    private func pdfModeLabel(_ title: String, mode: PDFReadingMode) -> String {
        windowManager.preferences.pdfReadingMode == mode ? "\(title) ✓" : title
    }

    private var isReadingRoute: Bool {
        if case .reader = router.currentRoute {
            return true
        }
        return false
    }

    private var isReadingPDFRoute: Bool {
        if case let .reader(book) = router.currentRoute {
            return book.format == .pdf
        }
        return false
    }
}

private struct ReaderTOCPanel: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var tocManager = ReadingTOCManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if tocManager.visibleItems.isEmpty {
                Text("当前书籍没有可用目录")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(tocManager.visibleItems, children: \.optionalChildren) { item in
                    Button {
                        tocManager.activate(token: item.token)
                    } label: {
                        Text(item.title)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }

            HStack {
                Text("目录项：\(flattenedCount(tocManager.visibleItems))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("关闭") {
                    dismiss()
                }
            }
        }
        .padding(16)
        .onAppear {
            tocManager.refresh()
        }
    }

    private func flattenedCount(_ items: [ReaderTOCItem]) -> Int {
        items.reduce(0) { partial, item in
            partial + 1 + flattenedCount(item.children)
        }
    }
}

private struct ReaderSearchPanel: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var searchManager = ReadingSearchManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                TextField("输入关键字", text: $searchManager.query)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        searchManager.performSearch()
                    }

                Button("搜索") {
                    searchManager.performSearch()
                }
                .keyboardShortcut(.return, modifiers: [])
            }

            if searchManager.isSearching {
                ProgressView("搜索中...")
            }

            List(searchManager.results) { result in
                Button {
                    searchManager.activate(result)
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(highlighted(result.excerpt, query: searchManager.query))
                            .lineLimit(2)
                        Text(result.detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            HStack {
                Text("结果数：\(searchManager.results.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("关闭") {
                    dismiss()
                }
            }
        }
        .padding(16)
    }

    private func highlighted(_ text: String, query: String) -> AttributedString {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { return AttributedString(text) }

        let nsText = text as NSString
        var attributed = AttributedString(text)
        var searchRange = NSRange(location: 0, length: nsText.length)

        while searchRange.length > 0 {
            let found = nsText.range(of: trimmedQuery, options: [.caseInsensitive], range: searchRange)
            if found.location == NSNotFound { break }
            if let range = Range(found, in: attributed) {
                attributed[range].backgroundColor = .yellow.opacity(0.7)
                attributed[range].foregroundColor = .black
            }

            let nextLocation = found.location + max(found.length, 1)
            if nextLocation >= nsText.length { break }
            searchRange = NSRange(location: nextLocation, length: nsText.length - nextLocation)
        }

        return attributed
    }
}
