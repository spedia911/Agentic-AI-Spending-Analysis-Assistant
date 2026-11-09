import Foundation
import PDFKit
import SpendingDomain

enum StatementPDFReader {
    enum Failure: LocalizedError {
        case invalid, locked, tooLarge, noText

        var errorDescription: String? {
            switch self {
            case .invalid: "This file could not be opened as a PDF."
            case .locked: "Export an unlocked copy of the statement and import it again."
            case .tooLarge: "Choose a bank statement of up to 30 pages and 20 MB."
            case .noText: "This PDF has no selectable text. Import screenshots of its transaction pages instead."
            }
        }
    }

    static func read(_ data: Data) async throws -> [OCRLine] {
        try await Task.detached(priority: .userInitiated) {
            guard data.count <= 20_000_000 else { throw Failure.tooLarge }
            guard let pdf = PDFDocument(data: data), pdf.pageCount > 0 else { throw Failure.invalid }
            guard !pdf.isLocked else { throw Failure.locked }
            guard pdf.pageCount <= 30 else { throw Failure.tooLarge }
            var output: [OCRLine] = []
            for index in 0..<pdf.pageCount {
                guard let page = pdf.page(at: index), page.numberOfCharacters > 0 else { continue }
                let bounds = page.bounds(for: .mediaBox)
                // The PDF's text stream can put amounts before descriptions, or wrap two rows
                // together. Select each physical row independently using its glyph positions.
                var bands: Set<Int> = []
                for i in 0..<page.numberOfCharacters {
                    let rect = page.characterBounds(at: i)
                    if !rect.isEmpty, rect.midY.isFinite, rect.midY > bounds.minY, rect.midY < bounds.maxY {
                        bands.insert(Int((rect.midY * 2).rounded()))
                    }
                }
                var seen: Set<String> = []
                for band in bands.sorted(by: >) {
                    let region = CGRect(x: bounds.minX, y: Double(band) / 2 - 1, width: bounds.width, height: 2)
                    guard let selected = page.selection(for: region)?.string else { continue }
                    let line = selected.components(separatedBy: .newlines).joined(separator: " | ").trimmingCharacters(in: .whitespaces)
                    guard !line.isEmpty, seen.insert(line).inserted else { continue }
                    let masked = line.replacingOccurrences(of: #"(?i)(\b(?:checking|savings)[^$|]*?\s+-\s+)\d+(\d{4})\s*$"#,
                        with: "$1*$2", options: .regularExpression)
                    output.append(OCRLine(text: masked))
                }
            }
            guard !output.isEmpty else { throw Failure.noText }
            return output
        }.value
    }
}
