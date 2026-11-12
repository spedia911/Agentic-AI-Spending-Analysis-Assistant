import Foundation

public enum CurrencyEvidence: Equatable, Sendable {
    case unspecified
    case explicit(String)
    case conflicting

    public var code: String? {
        if case let .explicit(code) = self { return code }
        return nil
    }

    /// Interpret currency markers beside amounts. Original purchase amounts are separate from billed amounts.
    public static func read(_ text: String) -> Self {
        let segments = text.components(separatedBy: CharacterSet(charactersIn: "\n|;"))
        let billed = segments.filter { billingAmountLabel(in: $0) != nil }
        let relevant = billed.isEmpty ? segments : billed
        let amount = #"\s*[+−-]?\s*[$€£₩¥₹]?\s*[+−-]?\s*\d[\d,.]*"#
        let codePattern = #"\b([A-Z]{3})\b"#
        var codes = Set<String>()
        for part in relevant {
            let snippet = billedAmountText(in: part)
            for pattern in [codePattern + amount, amount + #"\s*"# + codePattern] {
                guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
                for match in regex.matches(in: snippet, range: NSRange(snippet.startIndex..., in: snippet)) {
                    if let range = Range(match.range(at: 1), in: snippet) {
                        let code = String(snippet[range])
                        if Eligibility.validCurrency(code) { codes.insert(code) }
                    }
                }
            }
            for (marker, code) in [("US$", "USD"), ("CA$", "CAD"), ("AU$", "AUD"), ("HK$", "HKD"), ("₩", "KRW"), ("€", "EUR"), ("₹", "INR"), ("원", "KRW")] {
                let token = NSRegularExpression.escapedPattern(for: marker)
                if snippet.range(of: token + amount, options: .regularExpression) != nil
                    || (marker == "원" && snippet.range(of: amount + #"\s*원"#, options: .regularExpression) != nil) {
                    codes.insert(code)
                }
            }
        }
        if codes.count > 1 { return .conflicting }
        return codes.first.map(Self.explicit) ?? .unspecified
    }

    private static let billingLabel = #"(?i)\b(?:billed amount|charged amount|settled amount|billing currency)\b|\b(?:billed|charged|settled)\b(?=\s*:?\s*(?:[A-Z]{3}\s*)?[$€£₩¥₹+−-]?\s*\d)|청구금액|청구 금액"#
    private static let originalLabel = #"(?i)\b(?:original amount|original currency|foreign amount|foreign currency|purchase currency)\b|\b(?:original|foreign)\b(?=\s*:?\s*(?:[A-Z]{3}\s*)?[$€£₩¥₹+−-]?\s*\d)|현지통화|원거래"#

    static func originalAmountLabel(in text: String) -> Range<String.Index>? {
        text.range(of: originalLabel, options: .regularExpression)
    }

    static func billingAmountLabel(in text: String) -> Range<String.Index>? {
        text.range(of: billingLabel, options: .regularExpression)
    }

    /// Limits OCR amount matching to the billed amount when the layout labels it.
    static func billedAmountText(in text: String) -> String {
        if let billed = billingAmountLabel(in: text) {
            let tail = String(text[billed.upperBound...])
            if let original = originalAmountLabel(in: tail) { return String(tail[..<original.lowerBound]) }
            return tail
        }
        if let original = originalAmountLabel(in: text) { return String(text[..<original.lowerBound]) }
        return text
    }

    public func conflicts(with code: String?) -> Bool {
        switch self {
        case .unspecified: return false
        case let .explicit(evidence): return code.map { $0 != evidence } ?? false
        case .conflicting: return true
        }
    }
}
