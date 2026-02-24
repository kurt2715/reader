import Foundation

struct EPUBExtractedContent {
    let plainText: String
    let richHTML: String
    let tableOfContents: [BookTOCItem]
}

private struct NCXNode {
    var title: String
    var source: String?
    var children: [NCXNode]
}

private final class NCXParserDelegate: NSObject, XMLParserDelegate {
    var rootNodes: [NCXNode] = []

    private var stack: [NCXNode] = []
    private var textBuffer = ""

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        let element = elementName.lowercased()
        textBuffer = ""

        if element == "navpoint" {
            stack.append(NCXNode(title: "", source: nil, children: []))
            return
        }

        if element == "content", var last = stack.popLast() {
            last.source = attributeDict["src"]
            stack.append(last)
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        textBuffer += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        let element = elementName.lowercased()
        let text = textBuffer.trimmingCharacters(in: .whitespacesAndNewlines)

        if element == "text", !text.isEmpty, var last = stack.popLast() {
            last.title = text
            stack.append(last)
        } else if element == "navpoint", let node = stack.popLast() {
            if var parent = stack.popLast() {
                parent.children.append(node)
                stack.append(parent)
            } else {
                rootNodes.append(node)
            }
        }

        textBuffer = ""
    }
}

enum EPUBImportError: LocalizedError {
    case unzipFailed
    case emptyContent(URL)

    var errorDescription: String? {
        switch self {
        case .unzipFailed:
            return "Could not unzip EPUB file."
        case let .emptyContent(url):
            return "No readable text found in EPUB: \(url.lastPathComponent)"
        }
    }
}

final class EPUBImportService {
    func importBook(from url: URL) throws -> Book {
        let hasAccess = url.startAccessingSecurityScopedResource()
        defer {
            if hasAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let extracted = try extractContent(from: url)
        let title = url.deletingPathExtension().lastPathComponent
        return Book(
            title: title,
            sourceURL: url,
            format: .epub,
            textContent: extracted.plainText,
            richHTMLContent: extracted.richHTML,
            tableOfContents: extracted.tableOfContents
        )
    }

    func extractContent(from url: URL) throws -> EPUBExtractedContent {
        let fm = FileManager.default
        let tempDir = fm.temporaryDirectory.appendingPathComponent("reader-epub-\(UUID().uuidString)")
        try fm.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer {
            try? fm.removeItem(at: tempDir)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-qq", "-o", url.path, "-d", tempDir.path]

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            throw EPUBImportError.unzipFailed
        }

        guard process.terminationStatus == 0 else {
            throw EPUBImportError.unzipFailed
        }

        let htmlFiles = collectHTMLFiles(in: tempDir)
        let chapterAnchors = buildChapterAnchors(htmlFiles: htmlFiles, rootDir: tempDir)
        let tocItems = extractTOCItems(in: tempDir, chapterAnchors: chapterAnchors)
        var textParts: [String] = []
        var htmlParts: [String] = []
        textParts.reserveCapacity(htmlFiles.count)
        htmlParts.reserveCapacity(htmlFiles.count)

        for (index, fileURL) in htmlFiles.enumerated() {
            guard let html = try? decodeText(from: fileURL) else { continue }

            let inlinedHTML = inlineImageSources(in: html, htmlFileURL: fileURL, rootDir: tempDir)
            let bodyHTML = extractBodyHTML(from: inlinedHTML)
            let normalizedBody = normalizeIDsAndLinks(
                in: bodyHTML,
                chapterIndex: index,
                fileURL: fileURL,
                rootDir: tempDir,
                chapterAnchors: chapterAnchors
            )

            let plain = htmlToPlainText(normalizedBody)
            if !plain.isEmpty {
                textParts.append(plain)
            }
            if !normalizedBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let chapterAnchor = "reader-chapter-\(index)"
                let wrapped = "<section id=\"\(chapterAnchor)\">\(normalizedBody)</section>"
                htmlParts.append(wrapped)
            }
        }

        let joinedText = textParts.joined(separator: "\n\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let joinedHTML = htmlParts.joined(separator: "<hr class=\"chapter-break\" />")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if joinedText.isEmpty && joinedHTML.isEmpty {
            throw EPUBImportError.emptyContent(url)
        }

        return EPUBExtractedContent(
            plainText: joinedText,
            richHTML: joinedHTML,
            tableOfContents: tocItems
        )
    }

    private func extractTOCItems(in rootDir: URL, chapterAnchors: [String: String]) -> [BookTOCItem] {
        let ncxFiles = collectNCXFiles(in: rootDir)
        for ncx in ncxFiles {
            if let items = parseNCX(ncxURL: ncx, rootDir: rootDir, chapterAnchors: chapterAnchors), !items.isEmpty {
                return items
            }
        }
        return []
    }

    private func collectNCXFiles(in root: URL) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }
        var files: [URL] = []
        for case let fileURL as URL in enumerator where fileURL.pathExtension.lowercased() == "ncx" {
            files.append(fileURL)
        }
        return files.sorted { $0.path < $1.path }
    }

    private func parseNCX(ncxURL: URL, rootDir: URL, chapterAnchors: [String: String]) -> [BookTOCItem]? {
        guard let data = try? Data(contentsOf: ncxURL) else { return nil }
        let parser = XMLParser(data: data)
        let delegate = NCXParserDelegate()
        parser.delegate = delegate
        guard parser.parse() else { return nil }

        return buildTOCItems(from: delegate.rootNodes, ncxURL: ncxURL, rootDir: rootDir, chapterAnchors: chapterAnchors)
    }

    private func buildTOCItems(
        from nodes: [NCXNode],
        ncxURL: URL,
        rootDir: URL,
        chapterAnchors: [String: String]
    ) -> [BookTOCItem] {
        nodes.compactMap { node in
            guard let source = node.source?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !source.isEmpty,
                  let token = rewrittenAnchorHref(
                    from: source,
                    chapterPrefix: "reader-chapter-0",
                    fileURL: ncxURL,
                    rootDir: rootDir,
                    chapterAnchors: chapterAnchors
                  ) else {
                return nil
            }
            let cleanToken = token.hasPrefix("#") ? String(token.dropFirst()) : token
            let title = node.title.trimmingCharacters(in: .whitespacesAndNewlines)
            let children = buildTOCItems(from: node.children, ncxURL: ncxURL, rootDir: rootDir, chapterAnchors: chapterAnchors)
            return BookTOCItem(
                title: title.isEmpty ? "Untitled" : title,
                token: cleanToken,
                children: children
            )
        }
    }

    private func collectHTMLFiles(in root: URL) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var files: [URL] = []
        for case let fileURL as URL in enumerator {
            let ext = fileURL.pathExtension.lowercased()
            if ext == "xhtml" || ext == "html" || ext == "htm" {
                files.append(fileURL)
            }
        }

        return files.sorted { $0.path < $1.path }
    }

    private func buildChapterAnchors(htmlFiles: [URL], rootDir: URL) -> [String: String] {
        var map: [String: String] = [:]
        for (index, fileURL) in htmlFiles.enumerated() {
            let key = canonicalPathKey(relativePath(of: fileURL, rootDir: rootDir))
            map[key] = "reader-chapter-\(index)"
        }
        return map
    }

    private func decodeText(from url: URL) throws -> String {
        if let text = try? String(contentsOf: url, encoding: .utf8) {
            return text
        }
        if let text = try? String(contentsOf: url, encoding: .unicode) {
            return text
        }
        if let text = try? String(contentsOf: url, encoding: .isoLatin1) {
            return text
        }
        return try String(contentsOf: url)
    }

    private func extractBodyHTML(from html: String) -> String {
        guard let regex = try? NSRegularExpression(
            pattern: "(?is)<body([^>]*)>(.*?)</body>",
            options: []
        ) else {
            return html
        }

        let ns = html as NSString
        let range = NSRange(location: 0, length: ns.length)
        if let match = regex.firstMatch(in: html, options: [], range: range), match.numberOfRanges > 2 {
            let attrs = ns.substring(with: match.range(at: 1))
            let inner = ns.substring(with: match.range(at: 2))
            return bodyAnchorPrefix(from: attrs) + inner
        }
        return html
    }

    private func bodyAnchorPrefix(from bodyAttributes: String) -> String {
        let idValue = attributeValue(named: "id", from: bodyAttributes) ?? attributeValue(named: "name", from: bodyAttributes)
        guard let idValue, !idValue.isEmpty else { return "" }
        return "<a id=\"\(idValue)\" name=\"\(idValue)\"></a>"
    }

    private func attributeValue(named attribute: String, from attributes: String) -> String? {
        guard let regex = try? NSRegularExpression(
            pattern: "(?i)\\b\(NSRegularExpression.escapedPattern(for: attribute))\\s*=\\s*([\"'])(.*?)\\1",
            options: []
        ) else {
            return nil
        }
        let ns = attributes as NSString
        let range = NSRange(location: 0, length: ns.length)
        guard let match = regex.firstMatch(in: attributes, options: [], range: range), match.numberOfRanges > 2 else {
            return nil
        }
        return ns.substring(with: match.range(at: 2))
    }

    private func normalizeIDsAndLinks(
        in bodyHTML: String,
        chapterIndex: Int,
        fileURL: URL,
        rootDir: URL,
        chapterAnchors: [String: String]
    ) -> String {
        let chapterPrefix = "reader-chapter-\(chapterIndex)"
        var html = prefixElementIDs(in: bodyHTML, chapterPrefix: chapterPrefix)
        html = prefixAnchorNames(in: html, chapterPrefix: chapterPrefix)
        html = rewriteAnchorLinks(
            in: html,
            chapterPrefix: chapterPrefix,
            fileURL: fileURL,
            rootDir: rootDir,
            chapterAnchors: chapterAnchors
        )
        return html
    }

    private func prefixElementIDs(in html: String, chapterPrefix: String) -> String {
        guard let regex = try? NSRegularExpression(
            pattern: "(?i)\\bid\\s*=\\s*([\"'])(.*?)\\1",
            options: []
        ) else {
            return html
        }

        let ns = html as NSString
        let matches = regex.matches(in: html, options: [], range: NSRange(location: 0, length: ns.length))
        if matches.isEmpty { return html }

        var result = html
        for match in matches.reversed() {
            guard match.numberOfRanges >= 3 else { continue }
            let quote = ns.substring(with: match.range(at: 1))
            let value = ns.substring(with: match.range(at: 2))
            let prefixed = "\(chapterPrefix)-\(sanitizeAnchor(value))"
            let replacement = "id=\(quote)\(prefixed)\(quote)"
            if let range = Range(match.range, in: result) {
                result.replaceSubrange(range, with: replacement)
            }
        }
        return result
    }

    private func prefixAnchorNames(in html: String, chapterPrefix: String) -> String {
        guard let regex = try? NSRegularExpression(
            pattern: "(?i)<a\\b([^>]*?)\\bname\\s*=\\s*([\"'])(.*?)\\2([^>]*)>",
            options: []
        ) else {
            return html
        }

        let ns = html as NSString
        let matches = regex.matches(in: html, options: [], range: NSRange(location: 0, length: ns.length))
        if matches.isEmpty { return html }

        var result = html
        for match in matches.reversed() {
            guard match.numberOfRanges >= 5 else { continue }

            let beforeAttrs = ns.substring(with: match.range(at: 1))
            let quote = ns.substring(with: match.range(at: 2))
            let value = ns.substring(with: match.range(at: 3))
            let afterAttrs = ns.substring(with: match.range(at: 4))
            let prefixed = "\(chapterPrefix)-\(sanitizeAnchor(value))"
            let replacement = "<a\(beforeAttrs)name=\(quote)\(prefixed)\(quote)\(afterAttrs)>"

            if let range = Range(match.range, in: result) {
                result.replaceSubrange(range, with: replacement)
            }
        }

        return result
    }

    private func rewriteAnchorLinks(
        in html: String,
        chapterPrefix: String,
        fileURL: URL,
        rootDir: URL,
        chapterAnchors: [String: String]
    ) -> String {
        guard let regex = try? NSRegularExpression(
            pattern: "(?i)<a\\b([^>]*?)\\bhref\\s*=\\s*([\"'])(.*?)\\2([^>]*)>",
            options: []
        ) else {
            return html
        }

        let ns = html as NSString
        let matches = regex.matches(in: html, options: [], range: NSRange(location: 0, length: ns.length))
        if matches.isEmpty { return html }

        var result = html
        for match in matches.reversed() {
            guard match.numberOfRanges >= 5 else { continue }

            let href = ns.substring(with: match.range(at: 3))
            guard let rewrittenHref = rewrittenAnchorHref(
                from: href,
                chapterPrefix: chapterPrefix,
                fileURL: fileURL,
                rootDir: rootDir,
                chapterAnchors: chapterAnchors
            ) else {
                continue
            }

            let beforeAttrs = ns.substring(with: match.range(at: 1))
            let quote = ns.substring(with: match.range(at: 2))
            let afterAttrs = ns.substring(with: match.range(at: 4))
            let replacement = "<a\(beforeAttrs)href=\(quote)\(rewrittenHref)\(quote)\(afterAttrs)>"

            if let range = Range(match.range, in: result) {
                result.replaceSubrange(range, with: replacement)
            }
        }

        return result
    }

    private func rewrittenAnchorHref(
        from href: String,
        chapterPrefix: String,
        fileURL: URL,
        rootDir: URL,
        chapterAnchors: [String: String]
    ) -> String? {
        let normalizedHref = href.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = normalizedHref.lowercased()
        if lower.hasPrefix("http://") || lower.hasPrefix("https://") || lower.hasPrefix("mailto:") || lower.hasPrefix("data:") || lower.hasPrefix("javascript:") {
            return nil
        }

        if normalizedHref.hasPrefix("#") {
            let anchor = sanitizeAnchor(String(normalizedHref.dropFirst()))
            guard !anchor.isEmpty else { return nil }
            return "#\(chapterPrefix)-\(anchor)"
        }

        var pathPart = ""
        var fragment = ""

        if let parsedURL = URL(string: normalizedHref), parsedURL.scheme != nil {
            if parsedURL.isFileURL {
                pathPart = parsedURL.path
                fragment = parsedURL.fragment ?? ""
            } else {
                fragment = parsedURL.fragment ?? ""
                if fragment.isEmpty {
                    return nil
                }
                return "#\(chapterPrefix)-\(sanitizeAnchor(fragment))"
            }
        } else {
            let components = normalizedHref.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)
            pathPart = String(components.first ?? "")
            fragment = components.count > 1 ? String(components[1]) : ""
        }

        if let queryIndex = pathPart.firstIndex(of: "?") {
            pathPart = String(pathPart[..<queryIndex])
        }
        pathPart = pathPart.replacingOccurrences(of: "\\", with: "/")
        if let decodedPath = pathPart.removingPercentEncoding {
            pathPart = decodedPath
        }

        if pathPart.isEmpty {
            if fragment.isEmpty { return "#\(chapterPrefix)" }
            return "#\(chapterPrefix)-\(sanitizeAnchor(fragment))"
        }

        let targetURL: URL
        if pathPart.hasPrefix("/") {
            targetURL = rootDir.appendingPathComponent(String(pathPart.dropFirst()))
        } else {
            targetURL = fileURL.deletingLastPathComponent().appendingPathComponent(pathPart)
        }

        let relativeKey = canonicalPathKey(relativePath(of: targetURL.standardizedFileURL, rootDir: rootDir))
        guard let targetChapter = chapterAnchors[relativeKey] else { return nil }

        if fragment.isEmpty {
            return "#\(targetChapter)"
        }
        return "#\(targetChapter)-\(sanitizeAnchor(fragment))"
    }

    private func relativePath(of fileURL: URL, rootDir: URL) -> String {
        let rootPath = rootDir.standardizedFileURL.path
        let filePath = fileURL.standardizedFileURL.path
        if filePath.hasPrefix(rootPath) {
            return String(filePath.dropFirst(rootPath.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        }
        return fileURL.lastPathComponent
    }

    private func canonicalPathKey(_ rawPath: String) -> String {
        var value = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
        value = value.replacingOccurrences(of: "\\", with: "/")
        if let decoded = value.removingPercentEncoding {
            value = decoded
        }
        while value.hasPrefix("./") {
            value.removeFirst(2)
        }
        return value.lowercased()
    }

    private func sanitizeAnchor(_ value: String) -> String {
        let decoded = value.removingPercentEncoding ?? value
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_:."))
        let filtered = decoded.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" }
        return String(filtered).replacingOccurrences(of: "-{2,}", with: "-", options: .regularExpression)
    }

    private func inlineImageSources(in html: String, htmlFileURL: URL, rootDir: URL) -> String {
        guard let regex = try? NSRegularExpression(
            pattern: "(?i)<img\\b([^>]*?)\\bsrc\\s*=\\s*([\"'])(.*?)\\2([^>]*)>",
            options: []
        ) else {
            return html
        }

        let ns = html as NSString
        let range = NSRange(location: 0, length: ns.length)
        let matches = regex.matches(in: html, options: [], range: range)
        if matches.isEmpty {
            return html
        }

        var result = html
        for match in matches.reversed() {
            guard match.numberOfRanges >= 5 else { continue }

            let srcValue = ns.substring(with: match.range(at: 3))
            guard let newSource = inlineImageDataURI(
                for: srcValue,
                htmlFileURL: htmlFileURL,
                rootDir: rootDir
            ) else {
                continue
            }

            let beforeAttrs = ns.substring(with: match.range(at: 1))
            let quote = ns.substring(with: match.range(at: 2))
            let afterAttrs = ns.substring(with: match.range(at: 4))
            let replacement = "<img\(beforeAttrs)src=\(quote)\(newSource)\(quote)\(afterAttrs)>"

            if let swiftRange = Range(match.range, in: result) {
                result.replaceSubrange(swiftRange, with: replacement)
            }
        }

        return result
    }

    private func inlineImageDataURI(for src: String, htmlFileURL: URL, rootDir: URL) -> String? {
        let lower = src.lowercased()
        if lower.hasPrefix("data:") || lower.hasPrefix("http://") || lower.hasPrefix("https://") {
            return nil
        }

        let resolvedPath: URL
        if src.hasPrefix("/") {
            resolvedPath = rootDir.appendingPathComponent(String(src.dropFirst()))
        } else {
            resolvedPath = htmlFileURL.deletingLastPathComponent().appendingPathComponent(src)
        }

        let standardized = resolvedPath.standardizedFileURL
        guard let imageData = try? Data(contentsOf: standardized), !imageData.isEmpty else {
            return nil
        }

        let mimeType = mimeTypeForImageExtension(standardized.pathExtension.lowercased())
        let base64 = imageData.base64EncodedString()
        return "data:\(mimeType);base64,\(base64)"
    }

    private func mimeTypeForImageExtension(_ ext: String) -> String {
        switch ext {
        case "png":
            return "image/png"
        case "jpg", "jpeg":
            return "image/jpeg"
        case "gif":
            return "image/gif"
        case "webp":
            return "image/webp"
        case "svg":
            return "image/svg+xml"
        default:
            return "application/octet-stream"
        }
    }

    private func htmlToPlainText(_ html: String) -> String {
        var text = html

        text = text.replacingOccurrences(of: "(?is)<script[^>]*>.*?</script>", with: " ", options: .regularExpression)
        text = text.replacingOccurrences(of: "(?is)<style[^>]*>.*?</style>", with: " ", options: .regularExpression)
        text = text.replacingOccurrences(of: "(?i)<br\\s*/?>", with: "\n", options: .regularExpression)
        text = text.replacingOccurrences(of: "(?i)</(p|div|h1|h2|h3|h4|h5|h6|li|tr|section|article|blockquote)>", with: "\n", options: .regularExpression)
        text = text.replacingOccurrences(of: "(?is)<[^>]+>", with: " ", options: .regularExpression)

        text = decodeHTMLBasicEntities(text)
        text = text.replacingOccurrences(of: "[ \t\u{00A0}]+", with: " ", options: .regularExpression)
        text = text.replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)

        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func decodeHTMLBasicEntities(_ text: String) -> String {
        var value = text
        value = value.replacingOccurrences(of: "&nbsp;", with: " ")
        value = value.replacingOccurrences(of: "&amp;", with: "&")
        value = value.replacingOccurrences(of: "&lt;", with: "<")
        value = value.replacingOccurrences(of: "&gt;", with: ">")
        value = value.replacingOccurrences(of: "&quot;", with: "\"")
        value = value.replacingOccurrences(of: "&#39;", with: "'")
        value = value.replacingOccurrences(of: "&apos;", with: "'")
        return value
    }
}
