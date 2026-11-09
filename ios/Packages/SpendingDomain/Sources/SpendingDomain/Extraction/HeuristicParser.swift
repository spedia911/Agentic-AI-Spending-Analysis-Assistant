import Foundation

public struct OCRLine: Codable, Sendable, Equatable {
    public var text: String
    public var boundingBox: EvidenceRegion?
    public var confidence: Double

    public init(text: String, boundingBox: EvidenceRegion? = nil, confidence: Double = 1) {
        self.text = text; self.boundingBox = boundingBox; self.confidence = confidence
    }
}

public enum ScreenshotLayout: String, Codable, Sendable, CaseIterable {
    case automatic, appleCard, capitalOne, bankActivity, generic
    public var title: String {
        switch self {
        case .automatic: return "Detect automatically"
        case .appleCard: return "Apple Card / dates below rows"
        case .capitalOne: return "Capital One / date headers"
        case .bankActivity: return "Bank activity / deposits and debits"
        case .generic: return "Generic statement"
        }
    }
}

public struct ScreenshotParseOptions: Sendable {
    public var cardName: String?
    public var layout: ScreenshotLayout
    public var observedMonthHint: String?
    public init(cardName: String? = nil, layout: ScreenshotLayout = .automatic, observedMonthHint: String? = nil) {
        self.cardName = cardName; self.layout = layout; self.observedMonthHint = observedMonthHint
    }
}

/// Uses OCR geometry for mobile transaction lists, with an inline-text fallback.
public enum HeuristicScreenshotParser {
    private static let money = #"[-+]?\s*[$€£]\s*[-+]?\s*(?:\d{1,3}(?:,\d{3})+|\d+)\.\d{2}(?:\s*CR)?"#
    private static let bareMoney = #"^\s*[-+]?\(?\d+(?:,\d{3})*\.\d{2}\)?(?:\s*CR)?\s*$"#
    private static let datePattern = #"\b(?:20\d{2}[-/]\d{1,2}[-/]\d{1,2}|\d{1,2}/\d{1,2}(?:/\d{2,4})?|(?:Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)[a-z]*\.?\s+\d{1,2}(?:,?\s+20\d{2})?)\b"#

    public static func detectLayout(_ lines: [OCRLine]) -> ScreenshotLayout {
        let text = lines.map(\.text).joined(separator: " ").lowercased()
        if text.contains("apple pay") || (text.contains("%") && lines.contains { match(#"^\d{1,2}/\d{1,2}/\d{2,4}$"#, $0.text) != nil }) { return .appleCard }
        if lines.contains(where: { subtitle in
            guard isBankSubtitle(subtitle.text), let left = subtitle.boundingBox, left.x < 0.45 else { return false }
            return lines.contains { balance in
                guard let right = balance.boundingBox, right.x > 0.54, abs(mid(right) - mid(left)) < 0.012 else { return false }
                return match(money, balance.text) != nil
            }
        }) { return .bankActivity }
        if text.contains("transactions") && (text.contains("miles") || text.contains("pay/move") || text.contains("clear all")) { return .capitalOne }
        if lines.contains(where: { match(#"(?i)^(January|February|March|April|May|June|July|August|September|October|November|December)\s+\d{1,2}$"#, $0.text) != nil }) { return .capitalOne }
        if text.contains("checking") || text.contains("direct deposit") || text.contains("bank activity") { return .bankActivity }
        return .generic
    }

    public static func statementMonth(_ text: String) -> String? {
        guard let value = match(#"(?i)\b(?:January|February|March|April|May|June|July|August|September|October|November|December)\s+20\d{2}\b"#, text) else { return nil }
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = TimeZone(secondsFromGMT: 0)
        f.dateFormat = "MMMM yyyy"
        guard let date = f.date(from: value) else { return nil }
        f.dateFormat = "yyyy-MM"; return f.string(from: date)
    }

    public static func parse(sourceDocumentId: String, fileName: String, lines: [OCRLine], options: ScreenshotParseOptions = ScreenshotParseOptions()) -> ScreenshotExtractionResult {
        let raw = lines.map(\.text).joined(separator: "\n")
        let layout = options.layout == .automatic ? detectLayout(lines) : options.layout
        let month = options.observedMonthHint ?? statementMonth(raw)
        let card = options.cardName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let account = card?.isEmpty == false ? card : (layout == .appleCard ? "Apple Card" : nil)
        let visible = lines.filter { $0.confidence >= 0.35 && !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let spatial = visible.filter { $0.boundingBox != nil }.sorted {
            let a = $0.boundingBox!, b = $1.boundingBox!
            return a.y == b.y ? a.x < b.x : a.y < b.y
        }
        if layout == .bankActivity, spatial.contains(where: { isBankSubtitle($0.text) }) {
            let rows = bankActivityRows(spatial, account: account, month: month)
            return ScreenshotExtractionResult(sourceDocumentId: sourceDocumentId, screenshotKind: .bankActivity,
                rawText: raw, extractionConfidence: rows.isEmpty ? 0.2 : 0.72, transactions: rows,
                warnings: rows.isEmpty ? ["No complete bank rows were found."]
                    : rows.contains(where: { !Validator.isValidDate($0.dateText ?? "") }) ? ["Add the statement month (YYYY-MM) for dates without a year."] : [])
        }
        var transactions: [ExtractedTransactionCandidate] = []
        var assets: [ExtractedAssetSnapshotCandidate] = []
        var warnings: [String] = []
        // Sticky header content can show blurred fragments of the previous scrolled row.
        let headerBottom = spatial.filter { statementMonth($0.text) != nil }.map { $0.boundingBox!.y + $0.boundingBox!.height }.max() ?? 0
        let totalBottom = spatial.filter { $0.text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "total" }.map { $0.boundingBox!.y + $0.boundingBox!.height }.max() ?? 0
        let floor = max(headerBottom, layout == .capitalOne ? totalBottom : 0)

        for (i, amountLine) in spatial.enumerated() {
            let box = amountLine.boundingBox!
            guard box.y > max(floor, 0.065),
                  let amount = match(money, amountLine.text) ?? (box.x > 0.55 ? match(bareMoney, amountLine.text) : nil),
                  !isSummary(amountLine.text) else { continue }
            let inlineMerchant = strip(amountLine.text, removing: [amount, match(datePattern, amountLine.text) ?? ""])
            let sameLineMerchant = isMerchant(inlineMerchant) ? inlineMerchant : nil
            let merchantIndex = spatial.indices.filter { j in
                let b = spatial[j].boundingBox!
                return j != i && b.x < box.x && b.x < 0.65 && isMerchant(spatial[j].text)
                    && abs(mid(b) - mid(box)) < max(0.011, max(b.height, box.height) * 0.6)
            }.max { spatial[$0].boundingBox!.x < spatial[$1].boundingBox!.x }
            guard let merchant = sameLineMerchant ?? merchantIndex.map({ spatial[$0].text }) else { continue }
            let merchantBox = merchantIndex.map { spatial[$0].boundingBox! } ?? box
            let nextAmountY = spatial.dropFirst(i + 1).first { line in
                guard let b = line.boundingBox else { return false }
                return b.y > box.y + 0.015 && (match(money, line.text) != nil || (b.x > 0.55 && match(bareMoney, line.text) != nil))
            }?.boundingBox?.y ?? 1
            var date = match(datePattern, amountLine.text)
            var evidence = [merchant, amountLine.text]
            if date == nil && layout != .capitalOne {
                // Apple Card places each row's numeric date below the merchant/location.
                if let dateLine = spatial.first(where: { line in
                    let b = line.boundingBox!
                    return b.y >= merchantBox.y && b.y < min(nextAmountY, merchantBox.y + 0.075)
                        && match(#"^\d{1,2}/\d{1,2}(?:/\d{2,4})?$"#, line.text) != nil
                }) { date = dateLine.text; evidence.append(dateLine.text) }
            }
            if date == nil && layout != .appleCard {
                // A date header applies to all following rows until the next header.
                if let header = spatial.last(where: { line in
                    let b = line.boundingBox!
                    return b.y < box.y && b.y >= floor && match("(?i)^" + datePattern + "$", line.text) != nil
                }) { date = header.text; evidence.append(header.text) }
            }
            let normalizedDate = Normalizer.normalizeDateText(date, observedMonthHint: month)
            let region = union(box, merchantBox)
            transactions.append(ExtractedTransactionCandidate(rowIndex: transactions.count,
                dateText: normalizedDate ?? date, merchantText: merchant, amountText: amount, accountSourceText: account,
                transactionTypeHint: typeHint(merchant, amount: amount, layout: layout), confidence: normalizedDate == nil ? 0.55 : 0.72,
                evidenceText: evidence.joined(separator: " | "), evidenceRegion: region))
        }

        // Inline OCR still supports statement rows without geometry.
        if transactions.isEmpty {
            for line in visible {
                let text = line.text.trimmingCharacters(in: .whitespacesAndNewlines)
                if let balance = detectBalance(text) {
                    assets.append(ExtractedAssetSnapshotCandidate(rowIndex: assets.count, accountLabelText: account ?? balance.account,
                        balanceText: balance.amount, balanceTypeHint: balance.type,
                        observedDateText: match(datePattern, text), confidence: 0.65, evidenceText: text, evidenceRegion: line.boundingBox))
                    continue
                }
                guard let date = match(datePattern, text), !isSummary(text) else { continue }
                let withoutDate = text.replacingOccurrences(of: date, with: "")
                guard let amount = match(money, withoutDate) ?? match(#"[-+]?\d+(?:,\d{3})*\.\d{2}(?:\s*CR)?\s*$"#, withoutDate) else { continue }
                let merchant = strip(withoutDate, removing: [amount])
                guard isMerchant(merchant) else { continue }
                transactions.append(ExtractedTransactionCandidate(rowIndex: transactions.count,
                    dateText: Normalizer.normalizeDateText(date, observedMonthHint: month) ?? date,
                    merchantText: merchant, amountText: amount, accountSourceText: account,
                    transactionTypeHint: typeHint(merchant, amount: amount, layout: layout), confidence: 0.72, evidenceText: text, evidenceRegion: line.boundingBox))
            }
        } else {
            for line in visible where match(#"(?i)balance|available credit"#, line.text) != nil {
                if let balance = detectBalance(line.text) {
                    assets.append(ExtractedAssetSnapshotCandidate(rowIndex: assets.count, accountLabelText: account ?? balance.account,
                        balanceText: balance.amount, balanceTypeHint: balance.type, observedDateText: match(datePattern, line.text),
                        confidence: 0.65, evidenceText: line.text, evidenceRegion: line.boundingBox))
                }
            }
        }
        if transactions.isEmpty && assets.isEmpty { warnings.append("No transaction rows could be structured. Choose the card/layout, add a statement month, or enter transactions manually.") }
        if transactions.contains(where: { Normalizer.normalizeDateText($0.dateText, observedMonthHint: month) == nil }) {
            warnings.append("Some dates need a statement year/month or manual correction.")
        }
        let kind: ScreenshotKind = !assets.isEmpty ? (transactions.isEmpty ? .bankActivity : .mixed)
            : transactions.isEmpty ? .unknown : (layout == .bankActivity || fileName.lowercased().contains("bank")) ? .bankActivity : .creditCard
        return ScreenshotExtractionResult(sourceDocumentId: sourceDocumentId,
            screenshotKind: kind,
            rawText: raw, extractionConfidence: transactions.isEmpty && assets.isEmpty ? 0.2 : 0.72,
            transactions: transactions, assetSnapshots: assets, warnings: warnings)
    }

    private static func isBankSubtitle(_ text: String) -> Bool {
        match(#"^(transfer|direct deposit|deposit|withdrawal|debit card|debit card purchase|check|interest|payment|fee|refund)$"#, text) != nil
    }

    private static func bankActivityRows(_ lines: [OCRLine], account: String?, month: String?) -> [ExtractedTransactionCandidate] {
        let footer = lines.filter {
            $0.boundingBox!.y > 0.85 && match(#"^(home|rewards|pay/move|offers|profile)$"#, $0.text) != nil
        }
        let bottom = footer.count >= 2 ? (footer.map { $0.boundingBox!.y }.min() ?? 1) - 0.045 : 1
        let headers = lines.filter { $0.boundingBox!.x < 0.35 && match("^" + datePattern + "$", $0.text) != nil }
        var rows: [ExtractedTransactionCandidate] = []
        var usedAmounts: Set<Int> = []
        for (i, merchant) in lines.enumerated() {
            let box = merchant.boundingBox!
            guard box.x < 0.55, box.y < bottom, !isBankSubtitle(merchant.text), isMerchant(merchant.text),
                  let header = headers.last(where: { $0.boundingBox!.y < box.y }),
                  let amountIndex = lines.indices.filter({ j in
                      let r = lines[j].boundingBox!
                      return r.x > 0.54 && abs(mid(r) - mid(box)) <= 0.009 && match(money, lines[j].text) != nil
                  }).min(by: { abs(mid(lines[$0].boundingBox!) - mid(box)) < abs(mid(lines[$1].boundingBox!) - mid(box)) }),
                  let amount = match(money, lines[amountIndex].text), usedAmounts.insert(amountIndex).inserted else { continue }
            let subtitle = lines.dropFirst(i + 1).first {
                let r = $0.boundingBox!
                return r.x < 0.35 && r.y > box.y + 0.007 && r.y < box.y + 0.036 && isBankSubtitle($0.text)
            }?.text ?? ""
            // The right-side number aligned to the subtitle is a running balance, not a transaction.
            let type = BankActivityClassification.type(merchant: merchant.text, descriptor: subtitle, amount: amount)
            let signed = amount.hasPrefix("+") || amount.hasPrefix("-") ? amount
                : type == .income || type == .refund ? "+" + amount : "-" + amount
            var date = Normalizer.normalizeDateText(header.text, observedMonthHint: month)
            if let context = month, context.hasSuffix("-01"), let parsed = date, parsed.dropFirst(4).hasPrefix("-12"),
               let year = Int(context.prefix(4)), parsed.hasPrefix(String(year)) {
                date = String(year - 1) + parsed.dropFirst(4)
            }
            rows.append(ExtractedTransactionCandidate(rowIndex: rows.count,
                dateText: date ?? header.text, merchantText: merchant.text, amountText: signed, accountSourceText: account,
                transactionTypeHint: type, confidence: date == nil ? 0.55 : 0.72,
                evidenceText: [header.text, merchant.text, subtitle, amount].filter { !$0.isEmpty }.joined(separator: " | "),
                evidenceRegion: union(box, lines[amountIndex].boundingBox!)))
        }
        return rows
    }

    private static func mid(_ b: EvidenceRegion) -> Double { b.y + b.height / 2 }
    private static func union(_ a: EvidenceRegion, _ b: EvidenceRegion) -> EvidenceRegion {
        let x = min(a.x, b.x), y = min(a.y, b.y)
        return EvidenceRegion(x: x, y: y, width: max(a.x+a.width,b.x+b.width)-x, height: max(a.y+a.height,b.y+b.height)-y)
    }
    private static func match(_ pattern: String, _ text: String) -> String? {
        guard let range = text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) else { return nil }
        return String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
    }
    private static func strip(_ text: String, removing parts: [String]) -> String {
        parts.filter { !$0.isEmpty }.reduce(text) { $0.replacingOccurrences(of: $1, with: "") }
            .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
    }
    private static func isSummary(_ text: String) -> Bool {
        match(#"(?i)\b(total|balance|available credit|statement balance|minimum payment|credit limit)\b"#, text) != nil
    }
    private static func isMerchant(_ text: String) -> Bool {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, t.rangeOfCharacter(from: .letters) != nil,
              match(money, t) == nil, !isSummary(t), statementMonth(t) == nil,
              match("(?i)^" + datePattern + "$", t) == nil else { return false }
        return match(#"(?i)^(apple pay|home|rewards|pay/move|offers|profile|search|transactions|clear all|phone/cable|other services|merchandise|internet|healthcare|grocery|gas/automotive|dining|.*\d[x×]\s*miles.*)$"#, t) == nil
    }
    private static func typeHint(_ text: String, amount: String, layout: ScreenshotLayout) -> TransactionType {
        if match(#"(?i)\b(transfer|zelle)\b"#, text) != nil { return .transfer }
        if match(#"(?i)\b(credit card payment|card autopay|payment to card)\b"#, text) != nil { return .payment }
        if match(#"(?i)\b(credit card|capital one|amex|american express|chase card|citi card|discover card)\b"#, text) != nil,
           match(#"(?i)\b(payment|epayment|autopay|pymt|pmt)\b"#, text) != nil { return .payment }
        if match(#"(?i)\b(refund|reversal)\b"#, text) != nil { return .refund }
        if match(#"(?i)\b(deposit|payroll|salary|direct dep|interest paid)\b"#, text) != nil { return .income }
        if match(#"(?i)\bpayment\b"#, text) != nil && layout != .bankActivity { return .payment }
        if layout != .bankActivity && match(#"(?i)\bcredit\b"#, text) != nil { return .refund }
        if layout == .bankActivity && match(#"^\s*[$€£]?\s*\+"#, amount) != nil { return .unknown }
        return .expense
    }
    private static func detectBalance(_ text: String) -> (account: String, amount: String, type: BalanceType)? {
        guard match(#"(?i)balance|available credit"#, text) != nil,
              let amount = match(money, text) ?? match(#"[-+]?\d+(?:,\d{3})*\.\d{2}"#, text) else { return nil }
        let lower = text.lowercased()
        let type: BalanceType = lower.contains("saving") ? .savings : lower.contains("available credit") ? .creditAvailable
            : lower.contains("credit") ? .creditBalance : lower.contains("checking") || lower.contains("current") ? .checking : .unknown
        return (text.components(separatedBy: ":")[0], amount, type)
    }
}
