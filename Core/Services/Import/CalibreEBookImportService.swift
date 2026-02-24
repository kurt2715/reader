import Foundation

enum CalibreEBookImportError: LocalizedError {
    case unsupportedFormat(BookFormat)
    case calibreNotInstalled
    case conversionFailed(String)
    case emptyOutput(URL)

    var errorDescription: String? {
        switch self {
        case let .unsupportedFormat(format):
            return "Unsupported Calibre conversion format: \(format.rawValue)"
        case .calibreNotInstalled:
            return "MOBI/AZW3 import requires Calibre CLI (ebook-convert). Install Calibre first."
        case let .conversionFailed(message):
            return "ebook-convert failed: \(message)"
        case let .emptyOutput(url):
            return "Converted output is empty: \(url.lastPathComponent)"
        }
    }
}

final class CalibreEBookImportService {
    private let epubImportService: EPUBImportService

    init(epubImportService: EPUBImportService) {
        self.epubImportService = epubImportService
    }

    func importBook(from url: URL, format: BookFormat) throws -> Book {
        guard format == .mobi || format == .azw3 else {
            throw CalibreEBookImportError.unsupportedFormat(format)
        }

        let hasAccess = url.startAccessingSecurityScopedResource()
        defer {
            if hasAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let conversionResult = try convertToEPUB(from: url)
        defer {
            try? FileManager.default.removeItem(at: conversionResult.temporaryDirectory)
        }

        let extracted = try epubImportService.extractContent(from: conversionResult.outputURL)
        let title = url.deletingPathExtension().lastPathComponent

        return Book(
            title: title,
            sourceURL: url,
            format: format,
            textContent: extracted.plainText,
            richHTMLContent: extracted.richHTML,
            tableOfContents: extracted.tableOfContents
        )
    }

    private func convertToEPUB(from url: URL) throws -> (outputURL: URL, temporaryDirectory: URL) {
        guard let executablePath = findExecutablePath() else {
            throw CalibreEBookImportError.calibreNotInstalled
        }

        let fm = FileManager.default
        let tempDir = fm.temporaryDirectory.appendingPathComponent("reader-calibre-\(UUID().uuidString)")
        try fm.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let outputURL = tempDir.appendingPathComponent("out.epub")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = [url.path, outputURL.path]

        let stderrPipe = Pipe()
        process.standardError = stderrPipe

        do {
            try process.run()
        } catch {
            throw CalibreEBookImportError.conversionFailed(error.localizedDescription)
        }

        process.waitUntilExit()

        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrText = String(data: stderrData, encoding: .utf8) ?? ""

        guard process.terminationStatus == 0 else {
            let message = stderrText.trimmingCharacters(in: .whitespacesAndNewlines)
            throw CalibreEBookImportError.conversionFailed(message.isEmpty ? "unknown error" : message)
        }

        guard (try? outputURL.checkResourceIsReachable()) == true else {
            throw CalibreEBookImportError.emptyOutput(url)
        }

        return (outputURL: outputURL, temporaryDirectory: tempDir)
    }

    private func findExecutablePath() -> String? {
        let candidates = [
            "/usr/local/bin/ebook-convert",
            "/opt/homebrew/bin/ebook-convert",
            "/Applications/calibre.app/Contents/MacOS/ebook-convert"
        ]

        for path in candidates where FileManager.default.isExecutableFile(atPath: path) {
            return path
        }
        return nil
    }
}
