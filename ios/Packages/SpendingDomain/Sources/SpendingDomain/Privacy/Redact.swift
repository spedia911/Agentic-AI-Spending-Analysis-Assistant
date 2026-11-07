import Foundation

public enum PrivacyRedactor {
    public static func maskSensitiveText(_ value: String, maxLength: Int = 240) -> String {
        var result = value
        result = result.replacingOccurrences(
            of: #"[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}"#,
            with: "[email]",
            options: [.regularExpression, .caseInsensitive]
        )
        result = result.replacingOccurrences(
            of: #"\b(?:AIza[0-9A-Za-z_-]{20,}|sk-[A-Za-z0-9_-]{16,}|gh[pousr]_[A-Za-z0-9_]{20,})\b"#,
            with: "[secret]",
            options: .regularExpression
        )
        result = result.replacingOccurrences(
            of: #"\b(api[_-]?key|authorization|bearer|client[_-]?secret|password|private[_-]?key|secret|token)\s*[:=]\s*["']?[^\s"',]+"#,
            with: "$1=[secret]",
            options: [.regularExpression, .caseInsensitive]
        )
        result = result.replacingOccurrences(of: #"\b\d{5,}\b"#, with: "[number]", options: .regularExpression)
        if result.count > maxLength {
            return String(result.prefix(maxLength))
        }
        return result
    }

    public static func safeErrorDetail(_ error: Error, fallback: String = "Unknown error") -> String {
        let message = error.localizedDescription.isEmpty ? fallback : error.localizedDescription
        return maskSensitiveText(message)
    }

    public static func maskAccountLabel(_ value: String?) -> String {
        guard let value else { return "Unknown account" }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "Unknown account" }

        let pattern = try! NSRegularExpression(pattern: #"\b\d{5,}\b"#)
        let ns = trimmed as NSString
        let matches = pattern.matches(in: trimmed, range: NSRange(location: 0, length: ns.length))
        var result = trimmed
        for match in matches.reversed() {
            guard let range = Range(match.range, in: result) else { continue }
            let digits = String(result[range])
            let keep = min(4, digits.count)
            let masked = String(repeating: "*", count: max(0, digits.count - keep)) + digits.suffix(keep)
            result.replaceSubrange(range, with: masked)
        }
        return result.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
