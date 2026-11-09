import Foundation

enum BankActivityClassification {
    static func type(merchant: String, descriptor: String, amount: String) -> TransactionType {
        let text = (merchant + " " + descriptor).lowercased()
        func matches(_ expression: String) -> Bool { text.range(of: expression, options: .regularExpression) != nil }
        let positive = (Normalizer.normalizeAmountText(amount) ?? 0) > 0 && amount.contains("+")
        if matches(#"\b(payroll|salary|direct deposit|interest paid|interest credit)\b"#) { return .income }
        if matches(#"\b(refund|reversal)\b"#) { return .refund }
        if !positive && matches(#"\b(applecard|apple card|credit card|capital one|citi card|amex|american express|discover card|bilt payment)\b"#)
            && matches(#"\b(transfer|payment|pmt|autopay|pymt)\b"#) { return .payment }
        if matches(#"\b(robinhood|brokerage|zelle|internal transfer)\b"#) { return .transfer }
        if !positive && matches(#"\b(comcast|xfinity|pgande|electric|utility|utilities)\b"#) { return .expense }
        if matches(#"\btransfer\b"#) { return .transfer }
        if matches(#"\bfee\b"#) { return .fee }
        if positive || matches(#"\bdeposit\b"#) { return .unknown }
        return .expense
    }
}

public enum BankStatementError: LocalizedError {
    case unsupported, incomplete
    public var errorDescription: String? {
        switch self {
        case .unsupported: "This PDF does not contain a supported single-account bank statement table."
        case .incomplete: "The statement transactions do not reconcile to the opening and closing balances. No rows were imported."
        }
    }
}

/// Parses the signed amount and running balance columns of a text-based bank statement.
public enum BankStatementParser {
    private static let day = #"\b(?:Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)[a-z]*\s+\d{1,2}\b"#
    private static let money = #"[-+]?\s*\$\s*\d+(?:,\d{3})*\.\d{2}"#

    public static func parse(sourceId: String, rows: [String], fileName: String = "") throws -> ScreenshotExtractionResult {
        let raw = rows.joined(separator: "\n")
        let hints = filenameHints(fileName)
        let period = matches(day + #"\s*[-–]\s*"# + day + #"(?:,\s*20\d{2})?"#, in: raw).first
        let printedYear = period.flatMap { matches(#",\s*20\d{2}$"#, in: $0).first }.flatMap { Int($0.suffix(4)) }
        guard let year = printedYear ?? hints.year else { throw BankStatementError.unsupported }
        let start: String
        let end: String
        let startDay = period.flatMap { matches(day, in: $0).first }
            ?? rows.first { $0.localizedCaseInsensitiveContains("Opening Balance") }.flatMap { matches(day, in: $0).first }
        let endDay = period.flatMap { matches(day, in: $0).last }
            ?? rows.first { $0.localizedCaseInsensitiveContains("Closing Balance") }.flatMap { matches(day, in: $0).first }
        if let startDay, let endDay, let last = date(endDay, year: year), let first = date(startDay, year: year),
           let firstCorrected = date(startDay, year: first > last ? year - 1 : year) {
            start = firstCorrected
            end = last
        } else if let month = hints.month {
            start = String(format: "%04d-%02d-01", year, month)
            end = String(format: "%04d-%02d-31", year, month)
        } else {
            throw BankStatementError.unsupported
        }

        let accounts = Set(rows.compactMap { matches(#"(?i)^\s*[^|$\n]*(?:checking|savings)[^|$\n]*?\s+-\s+\*?\d{4,}\s*$"#, in: $0).first })
        guard accounts.count <= 1 else { throw BankStatementError.unsupported }
        let account: String?
        if let accountLine = accounts.first, let digits = matches(#"\d{4,}\s*$"#, in: accountLine).first {
            let name = accountLine.components(separatedBy: " - ").dropLast().joined(separator: " - ").trimmingCharacters(in: .whitespaces)
            account = name + " *" + digits.trimmingCharacters(in: .whitespaces).suffix(4)
        } else { account = hints.account }
        let balanceType: BalanceType = account?.localizedCaseInsensitiveContains("savings") == true ? .savings
            : account?.localizedCaseInsensitiveContains("checking") == true ? .checking : .unknown
        var opening: Int?
        var ending: Int?
        var running: Int?
        var closingDate: String?
        var transactions: [ExtractedTransactionCandidate] = []
        var inTable = false
        for row in rows {
            if row.range(of: #"(?i)\bDATE\b.*\bDESCRIPTION\b.*\bAMOUNT\b.*\bBALANCE\b"#, options: .regularExpression) != nil {
                inTable = true; continue
            }
            guard inTable, period.map({ !row.contains($0) }) ?? true, let header = matches(day, in: row).first, let range = row.range(of: header) else { continue }
            let rowDate = date(header, year: year).flatMap { $0 > end ? date(header, year: year - 1) : $0 }
            guard let rowDate, rowDate >= start, rowDate <= end else { continue }
            let values = matches(money, in: row)
            let description = String(row[range.upperBound...]).components(separatedBy: "|").first ?? ""
            let clean = description.replacingOccurrences(of: money, with: "", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
            if clean.caseInsensitiveCompare("Opening Balance") == .orderedSame {
                guard opening == nil, values.count == 1, let value = cents(values[0]) else { throw BankStatementError.incomplete }
                opening = value; running = value; continue
            }
            if clean.caseInsensitiveCompare("Closing Balance") == .orderedSame {
                guard ending == nil, values.count == 1, let value = cents(values[0]), value == running else { throw BankStatementError.incomplete }
                ending = value; closingDate = rowDate; inTable = false; continue
            }
            guard running != nil, values.count == 2,
                  let signed = values.first(where: { $0.hasPrefix("+") || $0.hasPrefix("-") }),
                  let amount = cents(signed), let balance = cents(values[1]), let prior = running,
                  prior + amount == balance, !clean.isEmpty else { throw BankStatementError.incomplete }
            running = balance
            let type = BankActivityClassification.type(merchant: clean, descriptor: "", amount: signed)
            let merchant = clean.replacingOccurrences(of: #"(?i)^(Withdrawal|Deposit)\s+(from|to)\s+"#, with: "", options: .regularExpression)
                .replacingOccurrences(of: #"(?i)\s+(PAYROLL|DEBITS|WEB ONLINE|CABLE SVCS|MOBILE PMT|PAYMENT)$"#, with: "", options: .regularExpression)
            transactions.append(ExtractedTransactionCandidate(rowIndex: transactions.count, dateText: rowDate,
                merchantText: merchant, amountText: signed, accountSourceText: account, transactionTypeHint: type,
                confidence: 0.92, evidenceText: PrivacyRedactor.maskSensitiveText(row)))
        }
        guard opening != nil, let ending, let closingDate, !transactions.isEmpty else { throw BankStatementError.incomplete }
        let asset = ExtractedAssetSnapshotCandidate(rowIndex: 0, accountLabelText: account,
            balanceText: String(format: "%.2f", Double(ending) / 100),
            balanceTypeHint: balanceType,
            observedDateText: closingDate, confidence: 0.95, evidenceText: "Statement closing balance")
        return ScreenshotExtractionResult(sourceDocumentId: sourceId, screenshotKind: .bankActivity,
            rawText: PrivacyRedactor.maskSensitiveText(raw), extractionConfidence: 0.92, transactions: transactions, assetSnapshots: [asset])
    }

    private static func filenameHints(_ fileName: String) -> (year: Int?, month: Int?, account: String?) {
        let base = URL(fileURLWithPath: fileName).deletingPathExtension().lastPathComponent
        let numeric = matches(#"(?<!\d)20\d{2}(?:[-_. ]?(?:0[1-9]|1[0-2])(?:[-_. ]?(?:0[1-9]|[12]\d|3[01]))?)?(?!\d)"#, in: base).first
        let written = matches(#"(?i)\b(?:January|February|March|April|May|June|July|August|September|October|November|December)[ _.-]+20\d{2}\b"#, in: base).first
        let digits = numeric?.filter(\.isNumber) ?? ""
        let writtenMonth = written.flatMap { HeuristicScreenshotParser.statementMonth(
            $0.replacingOccurrences(of: #"[_.-]+"#, with: " ", options: .regularExpression)) }
        let year = digits.count >= 4 ? Int(digits.prefix(4)) : writtenMonth.flatMap { Int($0.prefix(4)) }
        let month = digits.count >= 6 ? Int(digits.dropFirst(4).prefix(2)) : writtenMonth.flatMap { Int($0.suffix(2)) }
        var label = base
        if let token = written ?? numeric, let range = label.range(of: token) { label.removeSubrange(range) }
        label = label.replacingOccurrences(of: #"(?i)\b(?:bank statement|statement|activity)\b"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"[_-]+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let account = label.range(of: #"(?i)\b(?:checking|savings)\b"#, options: .regularExpression) != nil
            ? PrivacyRedactor.maskAccountLabel(label) : nil
        return (year, month, account)
    }

    private static func date(_ day: String, year: Int) -> String? {
        Normalizer.normalizeDateText(day, observedMonthHint: "\(year)-01").flatMap { Validator.isValidDate($0) ? $0 : nil }
    }

    private static func matches(_ regex: String, in text: String) -> [String] {
        guard let re = try? NSRegularExpression(pattern: regex, options: [.caseInsensitive]) else { return [] }
        return re.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap {
            Range($0.range, in: text).map { String(text[$0]).trimmingCharacters(in: .whitespacesAndNewlines) }
        }
    }

    private static func cents(_ amount: String) -> Int? {
        guard let number = Normalizer.normalizeAmountText(amount), number.isFinite, abs(number) < 1_000_000_000_000 else { return nil }
        return Int((number * 100).rounded())
    }
}
