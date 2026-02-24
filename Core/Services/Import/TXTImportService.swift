import CoreFoundation
import Foundation

enum TXTImportError: LocalizedError {
    case unreadableFile(URL)

    var errorDescription: String? {
        switch self {
        case let .unreadableFile(url):
            return "Could not read file: \(url.lastPathComponent)"
        }
    }
}

final class TXTImportService {
    func importBook(from url: URL) throws -> Book {
        let hasAccess = url.startAccessingSecurityScopedResource()
        defer {
            if hasAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let content = try Self.readText(from: url)
        let title = url.deletingPathExtension().lastPathComponent
        let toc = Self.extractTOC(from: content)
        return Book(title: title, sourceURL: url, format: .txt, textContent: content, tableOfContents: toc)
    }

    private static func readText(from url: URL) throws -> String {
        if let utf8Text = try? String(contentsOf: url, encoding: .utf8) {
            return utf8Text
        }

        if let unicodeText = try? String(contentsOf: url, encoding: .unicode) {
            return unicodeText
        }

        let gb18030 = String.Encoding(
            rawValue: CFStringConvertEncodingToNSStringEncoding(
                CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)
            )
        )
        if let gbText = try? String(contentsOf: url, encoding: gb18030) {
            return gbText
        }

        throw TXTImportError.unreadableFile(url)
    }

    private static func extractTOC(from text: String) -> [BookTOCItem] {
        let nsText = text as NSString
        var items: [BookTOCItem] = []
        var searchLocation = 0
        let patterns = [
            #"^\s*第[0-9一二三四五六七八九十百千零〇两]+[章节回卷部幕]\s*.*$"#,
            #"^\s*(序章|序幕|前言|后记|尾声|引子)\s*$"#,
            #"^\s*(chapter|prologue|epilogue)\b.*$"#
        ]
        let regex = try? NSRegularExpression(
            pattern: patterns.joined(separator: "|"),
            options: [.caseInsensitive]
        )

        guard let regex else { return [] }

        while searchLocation < nsText.length {
            let lineRange = nsText.lineRange(for: NSRange(location: searchLocation, length: 0))
            let line = nsText.substring(with: lineRange)
            let trimmed = line.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            if !trimmed.isEmpty {
                let match = regex.firstMatch(in: trimmed, options: [], range: NSRange(location: 0, length: (trimmed as NSString).length))
                if match != nil {
                    let token = "text:\(lineRange.location):\(max(lineRange.length, 1))"
                    items.append(BookTOCItem(title: trimmed, token: token))
                    if items.count >= 400 { break }
                }
            }

            let next = lineRange.location + max(lineRange.length, 1)
            if next <= searchLocation { break }
            searchLocation = next
        }

        return items
    }
}
