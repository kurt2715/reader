import Foundation

enum ReaderFontColor: String, Equatable {
    case white
    case black
}

enum PDFReadingMode: String, Equatable {
    case original
    case reflowedText
}

struct ReaderPreferences: Equatable {
    var transparencyEnabled: Bool = false
    var opacity: Double = 1.0
    var fontSize: Double = 16.0
    var fontName: String = "Songti SC"
    var fontColor: ReaderFontColor = .white
    var pdfReadingMode: PDFReadingMode = .original
}
