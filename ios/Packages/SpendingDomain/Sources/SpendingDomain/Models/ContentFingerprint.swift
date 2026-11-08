import Foundation
import CryptoKit

public enum ContentFingerprint {
    public static func image(_ data: Data) -> String { "image:" + digest(data) }

    public static func json(_ extraction: ScreenshotExtractionResult) throws -> String {
        var canonical = extraction
        canonical.sourceDocumentId = ""
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return "json:" + digest(try encoder.encode(canonical))
    }

    public static func invalidJSON(_ text: String) -> String { "invalid-json:" + digest(Data(text.utf8)) }

    private static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
