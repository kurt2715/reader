import AppKit
import PDFKit
import SwiftUI
import WebKit

struct ReaderView: View {
    @EnvironmentObject private var windowManager: WindowManager

    let book: Book

    @State private var extractedPDFText: String = ""
    @State private var isExtractingPDFText = false
    @State private var pdfTextErrorMessage: String?

    var body: some View {
        Group {
            switch book.format {
            case .txt:
                textReaderView(text: book.textContent ?? "")
            case .epub, .mobi, .azw3:
                ebookReaderView
            case .pdf:
                pdfReaderView
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 8)
        .onAppear {
            ReadingNavigationManager.shared.clear()
            resetPDFTextStateForCurrentBook()
            startExtractingPDFTextIfNeeded()
        }
        .onChange(of: book.id) { _, _ in
            ReadingNavigationManager.shared.clear()
            resetPDFTextStateForCurrentBook()
            startExtractingPDFTextIfNeeded()
        }
        .onChange(of: windowManager.preferences.pdfReadingMode) { _, _ in
            startExtractingPDFTextIfNeeded()
        }
    }

    private var isHTMLBook: Bool {
        switch book.format {
        case .epub, .mobi, .azw3:
            return (book.richHTMLContent?.isEmpty == false)
        default:
            return false
        }
    }

    @ViewBuilder
    private func textReaderView(text: String) -> some View {
        ReaderTextView(
            text: text,
            fontSize: windowManager.preferences.fontSize,
            fontColor: windowManager.preferences.fontColor,
            progressKey: progressKey,
            tableOfContents: book.tableOfContents
        )
    }

    @ViewBuilder
    private var ebookReaderView: some View {
        if let richHTML = book.richHTMLContent, !richHTML.isEmpty {
            ReaderHTMLView(
                htmlBody: richHTML,
                fontSize: windowManager.preferences.fontSize,
                fontColor: windowManager.preferences.fontColor,
                progressKey: progressKey,
                tableOfContents: book.tableOfContents
            )
        } else {
            textReaderView(text: book.textContent ?? "")
        }
    }

    @ViewBuilder
    private var pdfReaderView: some View {
        switch windowManager.preferences.pdfReadingMode {
        case .original:
            ReaderPDFView(url: book.sourceURL, progressKey: progressKey, tableOfContents: book.tableOfContents)
        case .reflowedText:
            if isExtractingPDFText {
                ProgressView("Extracting text from PDF...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let pdfTextErrorMessage {
                Text(pdfTextErrorMessage)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if extractedPDFText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text("No selectable text found in this PDF. Try Original PDF mode.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                textReaderView(text: extractedPDFText)
            }
        }
    }

    private func resetPDFTextStateForCurrentBook() {
        guard book.format == .pdf else { return }
        extractedPDFText = ""
        pdfTextErrorMessage = nil
        isExtractingPDFText = false
    }

    private func startExtractingPDFTextIfNeeded() {
        guard book.format == .pdf else { return }
        guard windowManager.preferences.pdfReadingMode == .reflowedText else { return }
        guard !isExtractingPDFText else { return }
        guard extractedPDFText.isEmpty else { return }
        guard pdfTextErrorMessage == nil else { return }

        isExtractingPDFText = true
        let url = book.sourceURL

        DispatchQueue.global(qos: .userInitiated).async {
            let result = extractPDFText(from: url)

            DispatchQueue.main.async {
                self.isExtractingPDFText = false
                switch result {
                case let .success(text):
                    self.extractedPDFText = text
                case let .failure(error):
                    self.pdfTextErrorMessage = error.localizedDescription
                }
            }
        }
    }

    private func extractPDFText(from url: URL) -> Result<String, Error> {
        let hasAccess = url.startAccessingSecurityScopedResource()
        defer {
            if hasAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }

        guard let document = PDFDocument(url: url) else {
            return .failure(PDFImportError.unreadableFile(url))
        }

        return .success(document.string ?? "")
    }

    private var progressKey: String {
        book.sourceURL.path
    }
}

private struct ReaderTextView: NSViewRepresentable {
    let text: String
    let fontSize: Double
    let fontColor: ReaderFontColor
    let progressKey: String
    let tableOfContents: [BookTOCItem]

    final class Coordinator: NSObject {
        let navigationManager = ReadingNavigationManager.shared
        let searchManager = ReadingSearchManager.shared
        let progressStore = ReadingProgressStore.shared
        let tocManager = ReadingTOCManager.shared
        let progressKey: String
        let tableOfContents: [BookTOCItem]
        weak var scrollView: NSScrollView?
        weak var textView: NSTextView?
        var didRestore = false
        var positionStack: [Double] = []
        var searchOwnerID: String
        var tocOwnerID: String

        init(progressKey: String, tableOfContents: [BookTOCItem]) {
            self.progressKey = progressKey
            self.tableOfContents = tableOfContents
            self.searchOwnerID = "text:\(progressKey)"
            self.tocOwnerID = "toc:text:\(progressKey)"
        }

        @objc func onBoundsDidChange(_ notification: Notification) {
            guard let scrollView, let documentView = scrollView.documentView else { return }
            let maxY = max(0, documentView.bounds.height - scrollView.contentView.bounds.height)
            guard maxY > 0 else { return }
            let ratio = scrollView.contentView.bounds.origin.y / maxY
            progressStore.saveTextScrollRatio(ratio, for: progressKey)
        }

        func restorePositionIfNeeded() {
            guard !didRestore else { return }
            guard let ratio = progressStore.progress(for: progressKey)?.textScrollRatio else {
                didRestore = true
                return
            }
            guard let scrollView, let documentView = scrollView.documentView else { return }

            let maxY = max(0, documentView.bounds.height - scrollView.contentView.bounds.height)
            let targetY = ratio * maxY
            scrollView.contentView.scroll(to: NSPoint(x: 0, y: targetY))
            scrollView.reflectScrolledClipView(scrollView.contentView)
            didRestore = true
        }

        func registerNavigationAndSearch() {
            navigationManager.register(
                pushCurrentPositionAction: { [weak self] in
                    self?.pushCurrentPosition()
                },
                goBackAction: { [weak self] in
                    self?.goBackToPreviousPosition()
                },
                canGoBack: !positionStack.isEmpty
            )

            searchManager.register(
                owner: searchOwnerID,
                provider: ReaderSearchProvider(
                    search: { [weak self] query, completion in
                        completion(self?.search(query: query) ?? [])
                    },
                    activate: { [weak self] token in
                        self?.jumpToSearchToken(token)
                    }
                )
            )

            tocManager.register(
                owner: tocOwnerID,
                provider: ReaderTOCProvider(
                    items: { [self] in
                        self.mapTOC(self.tableOfContents)
                    },
                    activate: { [weak self] token in
                        self?.jumpToTOCToken(token)
                    }
                )
            )
        }

        func unregisterNavigationAndSearch() {
            navigationManager.clear()
            searchManager.unregister(owner: searchOwnerID)
            tocManager.unregister(owner: tocOwnerID)
        }

        func pushCurrentPosition() {
            guard let ratio = currentScrollRatio() else { return }
            positionStack.append(ratio)
            navigationManager.updateCanGoBack(!positionStack.isEmpty)
        }

        func goBackToPreviousPosition() {
            guard let ratio = positionStack.popLast(),
                  let scrollView,
                  let documentView = scrollView.documentView else {
                navigationManager.updateCanGoBack(false)
                return
            }
            let maxY = max(0, documentView.bounds.height - scrollView.contentView.bounds.height)
            scrollView.contentView.scroll(to: NSPoint(x: 0, y: ratio * maxY))
            scrollView.reflectScrolledClipView(scrollView.contentView)
            navigationManager.updateCanGoBack(!positionStack.isEmpty)
        }

        private func currentScrollRatio() -> Double? {
            guard let scrollView, let documentView = scrollView.documentView else { return nil }
            let maxY = max(0, documentView.bounds.height - scrollView.contentView.bounds.height)
            if maxY <= 0 { return 0 }
            return scrollView.contentView.bounds.origin.y / maxY
        }

        private func search(query: String) -> [ReaderSearchResult] {
            guard let textView else { return [] }
            let content = textView.string
            guard !content.isEmpty else { return [] }

            let nsContent = content as NSString
            let nsQuery = query as NSString
            let limit = 200
            var results: [ReaderSearchResult] = []
            var searchRange = NSRange(location: 0, length: nsContent.length)

            while searchRange.length > 0 && results.count < limit {
                let found = nsContent.range(of: query, options: [.caseInsensitive], range: searchRange)
                if found.location == NSNotFound { break }

                let excerptStart = max(0, found.location - 20)
                let excerptEnd = min(nsContent.length, found.location + found.length + 20)
                let excerptRange = NSRange(location: excerptStart, length: excerptEnd - excerptStart)
                let rawExcerpt = nsContent.substring(with: excerptRange)
                    .replacingOccurrences(of: "\n", with: " ")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let excerpt = rawExcerpt.isEmpty ? nsQuery as String : rawExcerpt
                let token = "\(found.location):\(found.length)"

                results.append(ReaderSearchResult(
                    id: token,
                    token: token,
                    excerpt: excerpt,
                    detail: "偏移 \(found.location)"
                ))

                let nextLocation = found.location + max(found.length, 1)
                if nextLocation >= nsContent.length { break }
                searchRange = NSRange(location: nextLocation, length: nsContent.length - nextLocation)
            }

            return results
        }

        private func jumpToSearchToken(_ token: String) {
            guard let textView else { return }
            let parts = token.split(separator: ":", maxSplits: 1)
            guard parts.count == 2,
                  let location = Int(parts[0]),
                  let length = Int(parts[1]) else {
                return
            }
            let nsContent = textView.string as NSString
            guard location >= 0, length > 0, location + length <= nsContent.length else { return }
            let range = NSRange(location: location, length: length)
            textView.scrollRangeToVisible(range)
            textView.setSelectedRange(range)
        }

        private func jumpToTOCToken(_ token: String) {
            guard token.hasPrefix("text:") else { return }
            let parts = token.split(separator: ":")
            guard parts.count >= 3,
                  let location = Int(parts[1]),
                  let length = Int(parts[2]),
                  let textView else { return }
            let nsContent = textView.string as NSString
            guard location >= 0, location < nsContent.length else { return }
            let safeLength = max(1, min(length, nsContent.length - location))
            let range = NSRange(location: location, length: safeLength)
            textView.scrollRangeToVisible(range)
            textView.setSelectedRange(range)
        }

        private func mapTOC(_ items: [BookTOCItem]) -> [ReaderTOCItem] {
            items.map { item in
                ReaderTOCItem(
                    id: item.id,
                    title: item.title,
                    token: item.token,
                    children: mapTOC(item.children)
                )
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(progressKey: progressKey, tableOfContents: tableOfContents)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = NSTextView(frame: .zero)
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.textColor = nsColor(for: fontColor)
        textView.isRichText = false
        textView.allowsUndo = false
        textView.textContainerInset = NSSize(width: 0, height: 8)
        textView.textContainer?.widthTracksTextView = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.font = NSFont.systemFont(ofSize: fontSize)
        textView.string = text

        let scrollView = NSScrollView(frame: .zero)
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.documentView = textView
        scrollView.contentView.postsBoundsChangedNotifications = true
        context.coordinator.scrollView = scrollView
        context.coordinator.textView = textView
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.onBoundsDidChange(_:)),
            name: NSView.boundsDidChangeNotification,
            object: scrollView.contentView
        )

        DispatchQueue.main.async {
            context.coordinator.restorePositionIfNeeded()
            context.coordinator.registerNavigationAndSearch()
        }
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else { return }
        if textView.string != text {
            textView.string = text
        }

        let currentSize = textView.font?.pointSize ?? 0
        if abs(currentSize - fontSize) > 0.1 {
            textView.font = NSFont.systemFont(ofSize: fontSize)
        }

        textView.textColor = nsColor(for: fontColor)

        DispatchQueue.main.async {
            context.coordinator.restorePositionIfNeeded()
        }
    }

    static func dismantleNSView(_ nsView: NSScrollView, coordinator: Coordinator) {
        NotificationCenter.default.removeObserver(
            coordinator,
            name: NSView.boundsDidChangeNotification,
            object: nsView.contentView
        )
        coordinator.unregisterNavigationAndSearch()
    }

    private func nsColor(for color: ReaderFontColor) -> NSColor {
        switch color {
        case .white:
            return .white
        case .black:
            return .black
        }
    }
}

private struct ReaderHTMLView: NSViewRepresentable {
    let htmlBody: String
    let fontSize: Double
    let fontColor: ReaderFontColor
    let progressKey: String
    let tableOfContents: [BookTOCItem]

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        let navigationManager = ReadingNavigationManager.shared
        let searchManager = ReadingSearchManager.shared
        let tocManager = ReadingTOCManager.shared
        let progressStore = ReadingProgressStore.shared
        var lastHTMLBody: String?
        var pendingStyleScript: String?
        var pendingInitialRestoreRatio: Double?
        var progressKey: String = ""
        var searchOwnerID: String = ""
        var tocOwnerID: String = ""
        var tocItems: [BookTOCItem] = []
        weak var webView: WKWebView?

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            guard let script = pendingStyleScript else { return }
            webView.evaluateJavaScript(script, completionHandler: nil)
            pendingStyleScript = nil

            if let ratio = pendingInitialRestoreRatio {
                let script = """
                (() => {
                  const body = document.body;
                  const max = Math.max(0, body.scrollHeight - window.innerHeight);
                  window.scrollTo(0, \(ratio) * max);
                })();
                """
                webView.evaluateJavaScript(script, completionHandler: nil)
                pendingInitialRestoreRatio = nil
            }
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            guard navigationAction.navigationType == .linkActivated else {
                decisionHandler(.allow)
                return
            }

            guard let url = navigationAction.request.url else {
                decisionHandler(.allow)
                return
            }

            let absolute = url.absoluteString
            let lower = absolute.lowercased()
            let isExternal = lower.hasPrefix("http://") || lower.hasPrefix("https://") || lower.hasPrefix("mailto:")
            guard !isExternal else {
                decisionHandler(.allow)
                return
            }

            let hasFragment = absolute.contains("#")
            let isSamePageLike = lower.hasPrefix("about:blank") || lower.hasPrefix("file://")
            let shouldHandleInternally = hasFragment || isSamePageLike
            guard shouldHandleInternally else {
                decisionHandler(.allow)
                return
            }

            webView.evaluateJavaScript("window.__readerPushPos && window.__readerPushPos();") { result, _ in
                let depth = result as? Int ?? 0
                Task { @MainActor in
                    self.navigationManager.updateCanGoBack(depth > 0)
                }
            }

            if let hrefLiteral = Self.jsStringLiteral(absolute) {
                webView.evaluateJavaScript("window.__readerJumpToHref && window.__readerJumpToHref(\(hrefLiteral));", completionHandler: nil)
            }
            decisionHandler(.cancel)
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == "readerNav" else { return }
            guard let payload = message.body as? [String: Any] else { return }

            if let messageType = payload["type"] as? String {
                switch messageType {
                case "stack":
                    let depth = payload["depth"] as? Int ?? 0
                    Task { @MainActor in
                        navigationManager.updateCanGoBack(depth > 0)
                    }
                case "scroll":
                    let ratio = payload["ratio"] as? Double ?? 0
                    progressStore.saveTextScrollRatio(ratio, for: progressKey)
                default:
                    break
                }
            }
        }

        func registerBackHandler() {
            navigationManager.register(
                pushCurrentPositionAction: { [weak self] in
                    self?.pushCurrentPosition()
                },
                goBackAction: { [weak self] in
                    self?.goBackToPreviousPosition()
                },
                canGoBack: false
            )
        }

        func goBackToPreviousPosition() {
            guard let webView else { return }
            webView.evaluateJavaScript("window.__readerGoBackPos && window.__readerGoBackPos();") { result, _ in
                let depth = result as? Int ?? 0
                Task { @MainActor in
                    self.navigationManager.updateCanGoBack(depth > 0)
                }
            }
        }

        func pushCurrentPosition() {
            guard let webView else { return }
            webView.evaluateJavaScript("window.__readerPushPos && window.__readerPushPos();") { result, _ in
                let depth = result as? Int ?? 0
                Task { @MainActor in
                    self.navigationManager.updateCanGoBack(depth > 0)
                }
            }
        }

        func registerSearchProvider() {
            guard let webView else { return }
            searchOwnerID = "html:\(progressKey)"
            searchManager.register(
                owner: searchOwnerID,
                provider: ReaderSearchProvider(
                    search: { query, completion in
                        guard let queryLiteral = Self.jsStringLiteral(query) else {
                            completion([])
                            return
                        }
                        let script = "window.__readerSearch && window.__readerSearch(\(queryLiteral));"
                        webView.evaluateJavaScript(script) { result, _ in
                            guard let rows = result as? [[String: Any]] else {
                                completion([])
                                return
                            }
                            let mapped = rows.compactMap { row -> ReaderSearchResult? in
                                guard let id = row["id"] as? String,
                                      let token = row["token"] as? String,
                                      let excerpt = row["excerpt"] as? String else {
                                    return nil
                                }
                                let detail = row["detail"] as? String ?? "网页匹配"
                                return ReaderSearchResult(id: id, token: token, excerpt: excerpt, detail: detail)
                            }
                            completion(mapped)
                        }
                    },
                    activate: { token in
                        guard let tokenLiteral = Self.jsStringLiteral(token) else { return }
                        webView.evaluateJavaScript("window.__readerJumpToSearchToken && window.__readerJumpToSearchToken(\(tokenLiteral));", completionHandler: nil)
                    }
                )
            )
        }

        func unregisterSearchProvider() {
            if !searchOwnerID.isEmpty {
                searchManager.unregister(owner: searchOwnerID)
            }
        }

        func registerTOCProvider() {
            tocOwnerID = "toc:html:\(progressKey)"
            tocManager.register(
                owner: tocOwnerID,
                provider: ReaderTOCProvider(
                    items: { [weak self] in
                        self?.mapTOC(self?.tocItems ?? []) ?? []
                    },
                    activate: { [weak self] token in
                        self?.jumpToTOCToken(token)
                    }
                )
            )
        }

        func unregisterTOCProvider() {
            if !tocOwnerID.isEmpty {
                tocManager.unregister(owner: tocOwnerID)
            }
        }

        func clearBackHandlerIfOwned() {
            Task { @MainActor in
                navigationManager.clear()
            }
        }

        private func jumpToTOCToken(_ token: String) {
            guard let webView else { return }
            if let tokenLiteral = Self.jsStringLiteral(token) {
                webView.evaluateJavaScript("window.__readerJumpToHref && window.__readerJumpToHref('#' + \(tokenLiteral));", completionHandler: nil)
            }
        }

        private func mapTOC(_ items: [BookTOCItem]) -> [ReaderTOCItem] {
            items.map { item in
                ReaderTOCItem(
                    id: item.id,
                    title: item.title,
                    token: item.token,
                    children: mapTOC(item.children)
                )
            }
        }

        private static func jsStringLiteral(_ text: String) -> String? {
            guard let data = try? JSONSerialization.data(withJSONObject: [text]),
                  let encoded = String(data: data, encoding: .utf8),
                  encoded.count >= 2 else {
                return nil
            }
            return String(encoded.dropFirst().dropLast())
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> WKWebView {
        let userContentController = WKUserContentController()
        userContentController.add(context.coordinator, name: "readerNav")
        userContentController.addUserScript(WKUserScript(
            source: positionTrackingScript,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        ))

        let config = WKWebViewConfiguration()
        config.userContentController = userContentController
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        context.coordinator.progressKey = progressKey
        context.coordinator.searchOwnerID = "html:\(progressKey)"
        context.coordinator.tocItems = tableOfContents
        context.coordinator.tocOwnerID = "toc:html:\(progressKey)"
        context.coordinator.pendingInitialRestoreRatio = context.coordinator.progressStore.progress(for: progressKey)?.textScrollRatio
        context.coordinator.webView = webView
        context.coordinator.registerBackHandler()
        context.coordinator.registerSearchProvider()
        context.coordinator.registerTOCProvider()
        webView.setValue(false, forKey: "drawsBackground")
        webView.loadHTMLString(htmlDocument(for: htmlBody), baseURL: nil)
        context.coordinator.lastHTMLBody = htmlBody
        context.coordinator.pendingStyleScript = styleUpdateScript(preservingPosition: false)
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        if context.coordinator.progressKey != progressKey {
            context.coordinator.unregisterSearchProvider()
            context.coordinator.unregisterTOCProvider()
            context.coordinator.progressKey = progressKey
            context.coordinator.searchOwnerID = "html:\(progressKey)"
            context.coordinator.tocOwnerID = "toc:html:\(progressKey)"
            context.coordinator.pendingInitialRestoreRatio = context.coordinator.progressStore.progress(for: progressKey)?.textScrollRatio
            context.coordinator.registerSearchProvider()
            context.coordinator.registerTOCProvider()
        }
        context.coordinator.tocItems = tableOfContents
        ReadingTOCManager.shared.refresh()

        if context.coordinator.lastHTMLBody != htmlBody {
            context.coordinator.lastHTMLBody = htmlBody
            context.coordinator.pendingStyleScript = styleUpdateScript(preservingPosition: false)
            nsView.loadHTMLString(htmlDocument(for: htmlBody), baseURL: nil)
            return
        }

        nsView.evaluateJavaScript(styleUpdateScript(preservingPosition: true), completionHandler: nil)
    }

    static func dismantleNSView(_ nsView: WKWebView, coordinator: Coordinator) {
        nsView.configuration.userContentController.removeScriptMessageHandler(forName: "readerNav")
        coordinator.clearBackHandlerIfOwned()
        coordinator.unregisterSearchProvider()
        coordinator.unregisterTOCProvider()
    }

    private func htmlDocument(for bodyHTML: String) -> String {
        let safeBody = sanitizeForTemplate(bodyHTML)
        return """
        <!doctype html>
        <html>
        <head>
          <meta charset=\"utf-8\" />
          <meta name=\"viewport\" content=\"width=device-width,initial-scale=1,maximum-scale=1\" />
          <style>
            :root { color-scheme: light dark; }
            html, body {
              margin: 0;
              padding: 0;
              background: transparent;
            }
            body {
              font-family: -apple-system, BlinkMacSystemFont, \"Helvetica Neue\", Helvetica, Arial, sans-serif;
              font-size: var(--reader-font-size, 22px);
              line-height: 1.65;
              color: var(--reader-font-color, #FFFFFF);
              -webkit-text-size-adjust: 100%;
              word-wrap: break-word;
            }
            p, div, section, article, blockquote, li {
              margin: 0.45em 0;
            }
            img {
              max-width: 100%;
              height: auto;
              display: block;
              margin: 0.8em auto;
            }
            .chapter-break {
              border: none;
              border-top: 1px solid rgba(127,127,127,0.25);
              margin: 1.2em 0;
            }
            mark.reader-search-hit {
              background: rgba(255, 214, 10, 0.55);
              color: inherit;
              border-radius: 4px;
              padding: 0 0.08em;
            }
            mark.reader-search-hit.reader-search-active {
              background: rgba(255, 95, 95, 0.65);
            }
          </style>
        </head>
        <body>
          \(safeBody)
        </body>
        </html>
        """
    }

    private func styleUpdateScript(preservingPosition: Bool) -> String {
        let colorHex = fontColor == .white ? "#FFFFFF" : "#000000"
        let size = Int(fontSize.rounded())

        if !preservingPosition {
            return """
            (() => {
              const root = document.documentElement;
              root.style.setProperty('--reader-font-size', '\(size)px');
              root.style.setProperty('--reader-font-color', '\(colorHex)');
            })();
            """
        }

        return """
        (() => {
          const root = document.documentElement;
          const body = document.body;
          const maxBefore = Math.max(0, body.scrollHeight - window.innerHeight);
          const ratio = maxBefore > 0 ? (window.scrollY / maxBefore) : 0;
          root.style.setProperty('--reader-font-size', '\(size)px');
          root.style.setProperty('--reader-font-color', '\(colorHex)');
          requestAnimationFrame(() => {
            const maxAfter = Math.max(0, body.scrollHeight - window.innerHeight);
            window.scrollTo(0, ratio * maxAfter);
          });
        })();
        """
    }

    private var positionTrackingScript: String {
        """
        (() => {
          if (!window.__readerPosStack) {
            window.__readerPosStack = [];
          }
          window.__readerPushPos = () => {
            const max = Math.max(0, document.body.scrollHeight - window.innerHeight);
            const ratio = max > 0 ? (window.scrollY / max) : 0;
            window.__readerPosStack.push(ratio);
            return window.__readerPosStack.length;
          };
          window.__readerGoBackPos = () => {
            if (!window.__readerPosStack.length) return 0;
            const ratio = window.__readerPosStack.pop();
            const max = Math.max(0, document.body.scrollHeight - window.innerHeight);
            window.scrollTo(0, ratio * max);
            return window.__readerPosStack.length;
          };
          const postReaderMessage = (payload) => {
            if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.readerNav) {
              window.webkit.messageHandlers.readerNav.postMessage(payload);
            }
          };
          const normalizeAnchor = (raw) => {
            if (!raw) return '';
            let value = raw;
            try { value = decodeURIComponent(value); } catch (_) {}
            return value
              .replace(/[^A-Za-z0-9\\-_:\\.]+/g, '-')
              .replace(/-{2,}/g, '-')
              .replace(/^-+|-+$/g, '');
          };
          const jumpToHref = (href) => {
            if (!href) return false;
            let fragment = '';
            if (href.startsWith('#')) {
              fragment = href.slice(1);
            } else {
              const hashIndex = href.indexOf('#');
              if (hashIndex >= 0) fragment = href.slice(hashIndex + 1);
            }
            if (!fragment) return false;
            const candidates = Array.from(new Set([fragment, normalizeAnchor(fragment)]))
              .filter(Boolean);
            for (const key of candidates) {
              const byId = document.getElementById(key);
              if (byId) {
                byId.scrollIntoView({ block: 'start', inline: 'nearest' });
                return true;
              }
              const byName = document.getElementsByName(key);
              if (byName && byName.length > 0) {
                byName[0].scrollIntoView({ block: 'start', inline: 'nearest' });
                return true;
              }
            }
            return false;
          };
          window.__readerJumpToHref = jumpToHref;
          const clearSearchMarks = () => {
            const marks = Array.from(document.querySelectorAll('mark.reader-search-hit'));
            for (const mark of marks) {
              const text = document.createTextNode(mark.textContent || '');
              mark.replaceWith(text);
            }
            document.body.normalize();
          };
          window.__readerSearch = (rawQuery) => {
            clearSearchMarks();
            const query = (rawQuery || '').trim();
            if (!query) return [];
            const lowerQuery = query.toLowerCase();
            const walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT, {
              acceptNode(node) {
                const parent = node.parentElement;
                if (!parent) return NodeFilter.FILTER_REJECT;
                if (parent.closest('script, style, noscript')) return NodeFilter.FILTER_REJECT;
                if (!node.nodeValue || !node.nodeValue.trim()) return NodeFilter.FILTER_REJECT;
                return NodeFilter.FILTER_ACCEPT;
              }
            });

            const textNodes = [];
            let current;
            while ((current = walker.nextNode())) {
              textNodes.push(current);
            }

            const maxResults = 200;
            let matchIndex = 0;
            const results = [];
            for (const node of textNodes) {
              if (matchIndex >= maxResults) break;
              const source = node.nodeValue || '';
              const lower = source.toLowerCase();
              const hits = [];
              let cursor = 0;
              while (cursor < lower.length && matchIndex + hits.length < maxResults) {
                const at = lower.indexOf(lowerQuery, cursor);
                if (at < 0) break;
                hits.push(at);
                cursor = at + Math.max(1, query.length);
              }
              if (!hits.length) continue;

              const fragment = document.createDocumentFragment();
              let start = 0;
              for (const at of hits) {
                if (at > start) {
                  fragment.appendChild(document.createTextNode(source.slice(start, at)));
                }
                const end = at + query.length;
                const mark = document.createElement('mark');
                mark.className = 'reader-search-hit';
                mark.id = `reader-search-hit-${matchIndex}`;
                mark.textContent = source.slice(at, end);
                fragment.appendChild(mark);

                const excerptStart = Math.max(0, at - 16);
                const excerptEnd = Math.min(source.length, end + 16);
                const excerpt = source.slice(excerptStart, excerptEnd).replace(/\\s+/g, ' ').trim();
                results.push({
                  id: `reader-search-${matchIndex}`,
                  token: `reader-search-hit-${matchIndex}`,
                  excerpt: excerpt || query,
                  detail: `匹配 ${matchIndex + 1}`
                });

                matchIndex += 1;
                start = end;
                if (matchIndex >= maxResults) break;
              }
              if (start < source.length) {
                fragment.appendChild(document.createTextNode(source.slice(start)));
              }
              node.parentNode.replaceChild(fragment, node);
            }
            return results;
          };
          window.__readerJumpToSearchToken = (token) => {
            if (!token) return false;
            const all = document.querySelectorAll('mark.reader-search-hit.reader-search-active');
            all.forEach(el => el.classList.remove('reader-search-active'));
            const target = document.getElementById(token);
            if (!target) return false;
            target.classList.add('reader-search-active');
            target.scrollIntoView({ block: 'center', inline: 'nearest' });
            return true;
          };
          document.addEventListener('click', (event) => {
            const anchor = event.target && event.target.closest ? event.target.closest('a[href]') : null;
            if (!anchor) return;
            const href = anchor.getAttribute('href') || '';
            const lower = href.toLowerCase();
            if (!href || lower.startsWith('javascript:') || lower.startsWith('mailto:')) return;
            const isExternal = lower.startsWith('http://') || lower.startsWith('https://') || lower.startsWith('mailto:');
            if (isExternal) return;
            const isInternal = href.startsWith('#') || (!lower.includes('://')) || lower.startsWith('file://') || href.includes('#');
            if (!isInternal) return;
            const depth = window.__readerPushPos();
            postReaderMessage({ type: 'stack', depth });
            if (jumpToHref(href)) {
              event.preventDefault();
            }
          }, true);
          let scrollTimer = null;
          window.addEventListener('scroll', () => {
            if (scrollTimer) clearTimeout(scrollTimer);
            scrollTimer = setTimeout(() => {
              const max = Math.max(0, document.body.scrollHeight - window.innerHeight);
              const ratio = max > 0 ? (window.scrollY / max) : 0;
              postReaderMessage({ type: 'scroll', ratio });
            }, 120);
          }, { passive: true });
        })();
        """
    }

    private func sanitizeForTemplate(_ html: String) -> String {
        html
            .replacingOccurrences(of: "</script>", with: "", options: [.caseInsensitive])
            .replacingOccurrences(of: "<script", with: "<disabled-script", options: [.caseInsensitive])
    }
}

private struct ReaderPDFView: NSViewRepresentable {
    let url: URL
    let progressKey: String
    let tableOfContents: [BookTOCItem]

    final class Coordinator: NSObject {
        let navigationManager = ReadingNavigationManager.shared
        let searchManager = ReadingSearchManager.shared
        let tocManager = ReadingTOCManager.shared
        var activeSecurityURL: URL?
        let progressStore = ReadingProgressStore.shared
        weak var pdfView: PDFView?
        var progressKey: String = ""
        var pendingRestorePageIndex: Int?
        var pageStack: [Int] = []
        var searchSelections: [PDFSelection] = []
        var searchOwnerID: String = ""
        var tocOwnerID: String = ""
        var tocItems: [BookTOCItem] = []

        @objc func onPDFPageChanged(_ notification: Notification) {
            guard let pdfView = notification.object as? PDFView else { return }
            guard let document = pdfView.document, let currentPage = pdfView.currentPage else { return }
            let index = document.index(for: currentPage)
            progressStore.savePDFPageIndex(index, for: progressKey)
        }

        func preparePendingRestore() {
            pendingRestorePageIndex = progressStore.progress(for: progressKey)?.pdfPageIndex
        }

        func restorePageIfAvailable() {
            guard let pageIndex = pendingRestorePageIndex else { return }
            guard let pdfView, let document = pdfView.document else { return }
            let safeIndex = min(max(pageIndex, 0), max(document.pageCount - 1, 0))
            guard let page = document.page(at: safeIndex) else { return }
            pdfView.go(to: page)
            pendingRestorePageIndex = nil
        }

        func saveCurrentPageIfAvailable() {
            guard let pdfView, let document = pdfView.document, let currentPage = pdfView.currentPage else { return }
            let index = document.index(for: currentPage)
            progressStore.savePDFPageIndex(index, for: progressKey)
        }

        func registerNavigationAndSearch() {
            searchOwnerID = "pdf:\(progressKey)"
            tocOwnerID = "toc:pdf:\(progressKey)"
            navigationManager.register(
                pushCurrentPositionAction: { [weak self] in
                    self?.pushCurrentPage()
                },
                goBackAction: { [weak self] in
                    self?.goBackPage()
                },
                canGoBack: !pageStack.isEmpty
            )

            searchManager.register(
                owner: searchOwnerID,
                provider: ReaderSearchProvider(
                    search: { [weak self] query, completion in
                        completion(self?.search(query: query) ?? [])
                    },
                    activate: { [weak self] token in
                        self?.jumpToSearchToken(token)
                    }
                )
            )

            tocManager.register(
                owner: tocOwnerID,
                provider: ReaderTOCProvider(
                    items: { [weak self] in
                        self?.mapTOC(self?.tocItems ?? []) ?? []
                    },
                    activate: { [weak self] token in
                        self?.jumpToTOCToken(token)
                    }
                )
            )
        }

        func unregisterNavigationAndSearch() {
            navigationManager.clear()
            if !searchOwnerID.isEmpty {
                searchManager.unregister(owner: searchOwnerID)
            }
            if !tocOwnerID.isEmpty {
                tocManager.unregister(owner: tocOwnerID)
            }
        }

        func pushCurrentPage() {
            guard let pdfView, let document = pdfView.document, let page = pdfView.currentPage else { return }
            pageStack.append(document.index(for: page))
            navigationManager.updateCanGoBack(!pageStack.isEmpty)
        }

        func goBackPage() {
            guard let target = pageStack.popLast(),
                  let pdfView,
                  let document = pdfView.document,
                  let page = document.page(at: min(max(target, 0), max(document.pageCount - 1, 0))) else {
                navigationManager.updateCanGoBack(false)
                return
            }
            pdfView.go(to: page)
            navigationManager.updateCanGoBack(!pageStack.isEmpty)
        }

        func search(query: String) -> [ReaderSearchResult] {
            guard let document = pdfView?.document else { return [] }
            let selections = document.findString(query, withOptions: [.caseInsensitive, .diacriticInsensitive])
            searchSelections = Array(selections.prefix(200))
            return searchSelections.enumerated().map { index, selection in
                let pageNumber = selection.pages.first.flatMap { document.index(for: $0) + 1 } ?? 0
                let excerpt = (selection.string ?? query)
                    .replacingOccurrences(of: "\n", with: " ")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let token = "\(index)"
                return ReaderSearchResult(
                    id: token,
                    token: token,
                    excerpt: excerpt.isEmpty ? query : excerpt,
                    detail: pageNumber > 0 ? "第 \(pageNumber) 页" : "PDF 匹配"
                )
            }
        }

        func jumpToSearchToken(_ token: String) {
            guard let index = Int(token),
                  index >= 0,
                  index < searchSelections.count,
                  let pdfView else {
                return
            }
            let selection = searchSelections[index]
            pdfView.go(to: selection)
            pdfView.setCurrentSelection(selection, animate: true)
        }

        func jumpToTOCToken(_ token: String) {
            guard token.hasPrefix("pdf-page:"),
                  let pageIndex = Int(token.replacingOccurrences(of: "pdf-page:", with: "")),
                  let pdfView,
                  let document = pdfView.document,
                  let page = document.page(at: min(max(pageIndex, 0), max(document.pageCount - 1, 0))) else {
                return
            }
            pdfView.go(to: page)
        }

        private func mapTOC(_ items: [BookTOCItem]) -> [ReaderTOCItem] {
            items.map { item in
                ReaderTOCItem(
                    id: item.id,
                    title: item.title,
                    token: item.token,
                    children: mapTOC(item.children)
                )
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> PDFView {
        let pdfView = PDFView(frame: .zero)
        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        pdfView.displayDirection = .vertical
        pdfView.backgroundColor = .clear
        context.coordinator.pdfView = pdfView
        context.coordinator.progressKey = progressKey
        context.coordinator.searchOwnerID = "pdf:\(progressKey)"
        context.coordinator.tocOwnerID = "toc:pdf:\(progressKey)"
        context.coordinator.tocItems = tableOfContents
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.onPDFPageChanged(_:)),
            name: Notification.Name.PDFViewPageChanged,
            object: pdfView
        )

        loadDocument(into: pdfView, context: context)
        context.coordinator.registerNavigationAndSearch()
        return pdfView
    }

    func updateNSView(_ nsView: PDFView, context: Context) {
        context.coordinator.progressKey = progressKey
        if context.coordinator.searchOwnerID != "pdf:\(progressKey)" {
            context.coordinator.unregisterNavigationAndSearch()
            context.coordinator.searchOwnerID = "pdf:\(progressKey)"
            context.coordinator.tocOwnerID = "toc:pdf:\(progressKey)"
            context.coordinator.registerNavigationAndSearch()
        }
        context.coordinator.tocItems = tableOfContents
        ReadingTOCManager.shared.refresh()
        if context.coordinator.pendingRestorePageIndex == nil {
            context.coordinator.preparePendingRestore()
        }
        guard context.coordinator.activeSecurityURL != url || nsView.document == nil else {
            return
        }

        loadDocument(into: nsView, context: context)
    }

    static func dismantleNSView(_ nsView: PDFView, coordinator: Coordinator) {
        coordinator.saveCurrentPageIfAvailable()
        NotificationCenter.default.removeObserver(
            coordinator,
            name: Notification.Name.PDFViewPageChanged,
            object: nsView
        )

        if let activeURL = coordinator.activeSecurityURL {
            activeURL.stopAccessingSecurityScopedResource()
            coordinator.activeSecurityURL = nil
        }
        nsView.document = nil
        coordinator.pdfView = nil
        coordinator.unregisterNavigationAndSearch()
    }

    private func loadDocument(into pdfView: PDFView, context: Context) {
        context.coordinator.saveCurrentPageIfAvailable()
        if let activeURL = context.coordinator.activeSecurityURL {
            activeURL.stopAccessingSecurityScopedResource()
            context.coordinator.activeSecurityURL = nil
        }

        if url.startAccessingSecurityScopedResource() {
            context.coordinator.activeSecurityURL = url
        }

        context.coordinator.preparePendingRestore()
        pdfView.document = PDFDocument(url: url)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) {
            context.coordinator.restorePageIfAvailable()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            context.coordinator.restorePageIfAvailable()
        }
    }
}
