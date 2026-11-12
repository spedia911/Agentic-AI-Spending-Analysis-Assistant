import Foundation
import SwiftData
import SpendingDomain

struct ImportOutcome: Identifiable {
    enum Status { case imported, alreadyImported, needsDetails, failed }
    let id = UUID()
    var fileName: String
    var status: Status
    var source: SourceDocumentRecord?
    var error: String?
    var details: ScreenshotImportDetails? = nil

    static func failure(_ name: String, _ error: Error, source: SourceDocumentRecord? = nil) -> Self {
        Self(fileName: name, status: .failed, source: source, error: PrivacyRedactor.safeErrorDetail(error))
    }
}

struct ScreenshotImportDetails: Identifiable {
    var id: String { source.sourceDocumentId }
    let source: SourceDocumentRecord
    let needsYear: Bool
    let needsDate: Bool
    let needsAccount: Bool
    var batchID: UUID? = nil
}

enum ImportFailure: Error, LocalizedError {
    case missingImage, replacementHasRows, unavailableSource, emptyImage, invalidMonth, missingAccount
    var errorDescription: String? {
        switch self {
        case .missingImage: return "The source image is unavailable or was removed by retention. Reimport the screenshot or attach AI JSON."
        case .replacementHasRows: return "This source already has extracted rows. Correct its transactions in Review."
        case .unavailableSource: return "The source is unavailable."
        case .emptyImage: return "No image data was received."
        case .missingAccount: return "Choose an account or enter a name."
        case .invalidMonth: return "Enter a year or statement month, for example 2026 or 2026-10."
        }
    }
}

/// One shared service serializes imports across await points, including concurrent entry points.
@MainActor
final class ImportPipelineService {
    var processingAllowed = true
    private func requireUnlocked() throws { guard processingAllowed else { throw BackupError.invalid("Unlock the app to continue processing.") } }
    let store: LocalStore
    let files: SourceFileStore
    private let recognize: (Data) async throws -> [OCRLine]
    private let enableFoundationModels: () -> Bool
    private var locked = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(store: LocalStore, files: SourceFileStore = SourceFileStore(),
         enableFoundationModels: @escaping () -> Bool = { UserDefaults.standard.object(forKey: "enableFoundationModels") as? Bool ?? true },
         recognize: @escaping (Data) async throws -> [OCRLine] = VisionOCRService.recognizeLines) {
        self.store = store; self.files = files
        self.enableFoundationModels = enableFoundationModels; self.recognize = recognize
    }

    private func acquire() async {
        if !locked { locked = true; return }
        await withCheckedContinuation { waiters.append($0) }
    }
    private func release() {
        if waiters.isEmpty { locked = false } else { waiters.removeFirst().resume() }
    }

    func importImage(data: Data, fileName: String, mimeType: String, sourceType: SourceType, options: ScreenshotParseOptions = ScreenshotParseOptions(), requestDetails: Bool = false, accountId: String? = nil) async -> ImportOutcome {
        await acquire(); defer { release() }
        return await importImageUnlocked(data: data, fileName: fileName, mimeType: mimeType, sourceType: sourceType, options: options, requestDetails: requestDetails, accountId: accountId)
    }

    private func importImageUnlocked(data: Data, fileName: String, mimeType: String, sourceType: SourceType,
                                     retrySource: SourceDocumentRecord? = nil, options: ScreenshotParseOptions = ScreenshotParseOptions(), requestDetails: Bool = false, accountId: String? = nil) async -> ImportOutcome {
        var source: SourceDocumentRecord?
        var newPath: String?
        do {
            try requireUnlocked()
            guard !data.isEmpty else { throw ImportFailure.emptyImage }
            let isPDF = mimeType == "application/pdf"
            if !isPDF, let month = options.observedMonthHint, !month.isEmpty, !Normalizer.isValidStatementDateHint(month) { throw ImportFailure.invalidMonth }
            try backfillFingerprints()
            let fingerprint = ContentFingerprint.image(data)
            let existing = try retrySource ?? store.source(fingerprint: fingerprint)
            if let existing, existing.status == .processed {
                return ImportOutcome(fileName: fileName, status: .alreadyImported, source: existing)
            }
            var record = existing ?? SourceDocumentRecord(sourceDocumentId: "src_" + UUID().uuidString,
                sourceType: sourceType, fileName: fileName, mimeType: mimeType, contentFingerprint: fingerprint)
            if existing == nil, let account = try store.account(id: accountId) {
                record.importAccountId = account.id
                record.cardName = account.label
            }
            if existing == nil && !isPDF {
                record.cardName = record.cardName ?? options.cardName.flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : PrivacyRedactor.maskAccountLabel($0) }
                record.screenshotLayout = options.layout.rawValue
                record.observedMonthHint = options.observedMonthHint
            }
            source = record
            // Keep the source durable before invoking OCR; restore an expired image on reimport.
            if record.localRelativePath == nil || (try? files.read(record.localRelativePath!)) == nil {
                record.localRelativePath = try files.save(data: data, sourceId: record.sourceDocumentId, fileName: fileName)
                record.imageDeletedAt = nil
                record.originalFileStatus = nil
                newPath = record.localRelativePath
            }
            record.contentFingerprint = fingerprint
            record.status = .pending; record.errorSummary = nil
            try store.commit { try store.upsert(source: record) }
            newPath = nil
            source = record
            try requireUnlocked()
            let lines = try await isPDF ? StatementPDFReader.read(data) : recognize(data)
            record.ocrLinesJSON = String(decoding: try JSONEncoder().encode(lines), as: UTF8.self)
            record.rawText = lines.map(\.text).joined(separator: "\n")
            if !isPDF && (record.screenshotLayout == nil || record.screenshotLayout == ScreenshotLayout.automatic.rawValue) {
                record.screenshotLayout = HeuristicScreenshotParser.detectLayout(lines).rawValue
            }
            if record.cardName == nil || record.cardName?.isEmpty == true {
                if record.screenshotLayout == ScreenshotLayout.appleCard.rawValue { record.cardName = "Apple Card" }
            }
            source = record
            var extraction = try parseDocument(record, lines: lines)
            if isPDF, record.importAccountId == nil { record.cardName = extraction.transactions.first?.accountSourceText }
            if !isPDF && extraction.transactions.isEmpty && extraction.assetSnapshots.isEmpty {
                // Optional enhancement failures must not discard the OCR evidence or fallback path.
                if let structured = try? await OnDeviceAIFactory.makeStructurer(enabled: enableFoundationModels()).structure(
                    ocrText: extraction.rawText, sourceDocumentId: record.sourceDocumentId, fileName: record.fileName) {
                    extraction = structured
                }
            }
            return try await finishDocument(extraction, source: &record, requestDetails: requestDetails)
        } catch {
            if let newPath { try? files.remove(newPath) }
            return recordFailure(error, name: fileName, source: source)
        }
    }

    func importAIJSON(text: String, fileName: String = "ai-import.json", attachingTo sourceId: String? = nil,
                      sourceType: SourceType = .aiImport) async -> ImportOutcome {
        await acquire(); defer { release() }
        return await importJSONUnlocked(text: text, fileName: fileName, sourceId: sourceId, sourceType: sourceType)
    }

    private func importJSONUnlocked(text: String, fileName: String, sourceId: String?, sourceType: SourceType) async -> ImportOutcome {
        var source: SourceDocumentRecord?
        do {
            try requireUnlocked()
            try backfillFingerprints()
            if let sourceId {
                guard let existing = try store.source(id: sourceId) else { throw ImportFailure.unavailableSource }
                guard try !store.hasRows(sourceId: sourceId), existing.status != .processed else { throw ImportFailure.replacementHasRows }
                source = existing
            }
            let parsed: ScreenshotExtractionResult
            do { parsed = try ExtractionJSONParser.parse(text) }
            catch {
                if source == nil {
                    source = try store.source(fingerprint: ContentFingerprint.invalidJSON(text))
                        ?? SourceDocumentRecord(sourceDocumentId: "src_" + UUID().uuidString, sourceType: sourceType,
                            fileName: fileName, mimeType: "application/json", contentFingerprint: ContentFingerprint.invalidJSON(text))
                }
                source?.importedJSON = text
                throw error
            }
            let fingerprint = try ContentFingerprint.json(parsed)
            if let existing = try store.source(fingerprint: fingerprint), existing.status == .processed {
                // Do not silently attach an already imported document to a different failed source.
                if sourceId != nil && sourceId != existing.sourceDocumentId { throw ImportFailure.replacementHasRows }
                return ImportOutcome(fileName: fileName, status: .alreadyImported, source: existing)
            }
            if source == nil {
                source = try store.source(fingerprint: fingerprint) ?? SourceDocumentRecord(
                    sourceDocumentId: "src_" + UUID().uuidString, sourceType: sourceType,
                    fileName: fileName, mimeType: "application/json", contentFingerprint: fingerprint)
            }
            var record = source!
            record.importedJSON = text
            if record.rawText == nil { record.rawText = parsed.rawText }
            // For an attached repair, preserve the screenshot fingerprint and OCR evidence.
            if record.localRelativePath == nil { record.contentFingerprint = fingerprint }
            source = record
            try await persist(extraction: parsed, source: &record)
            return ImportOutcome(fileName: fileName, status: .imported, source: record)
        } catch {
            // A disallowed replacement must never mutate a completed source.
            if case ImportFailure.replacementHasRows = error { return .failure(fileName, error) }
            return recordFailure(error, name: fileName, source: source)
        }
    }

    func retry(sourceId: String, requestDetails: Bool = false, fallbackDate: String? = nil) async -> ImportOutcome {
        await acquire(); defer { release() }
        do {
            try requireUnlocked()
            guard let source = try store.source(id: sourceId) else { throw ImportFailure.unavailableSource }
            if source.status == .processed { return ImportOutcome(fileName: source.fileName, status: .alreadyImported, source: source) }
            if let json = source.importedJSON ?? (source.mimeType == "application/json" ? source.rawText : nil) {
                return await importJSONUnlocked(text: json, fileName: source.fileName, sourceId: sourceId, sourceType: source.sourceType)
            }
            guard try !store.hasRows(sourceId: sourceId) else { throw ImportFailure.replacementHasRows }
            if let json = source.ocrLinesJSON, let data = json.data(using: .utf8), let lines = try? JSONDecoder().decode([OCRLine].self, from: data) {
                var record = source
                var extraction: ScreenshotExtractionResult
                do { extraction = try parseDocument(record, lines: lines) }
                catch { return recordFailure(error, name: source.fileName, source: source) }
                if source.mimeType == "application/pdf" { record.cardName = extraction.transactions.first?.accountSourceText }
                if source.mimeType != "application/pdf", extraction.transactions.isEmpty && extraction.assetSnapshots.isEmpty,
                   let structured = try? await OnDeviceAIFactory.makeStructurer(enabled: enableFoundationModels()).structure(
                    ocrText: extraction.rawText, sourceDocumentId: sourceId, fileName: source.fileName) { extraction = structured }
                do { return try await finishDocument(extraction, source: &record, requestDetails: requestDetails, fallbackDate: fallbackDate)
                } catch { return recordFailure(error, name: source.fileName, source: source) }
            }
            guard let relative = source.localRelativePath, let data = try? files.read(relative) else { throw ImportFailure.missingImage }
            return await importImageUnlocked(data: data, fileName: source.fileName, mimeType: source.mimeType, sourceType: source.sourceType, retrySource: source, requestDetails: requestDetails)
        } catch { return .failure("Retry", error) }
    }

    private func finishDocument(_ result: ScreenshotExtractionResult, source: inout SourceDocumentRecord,
                                requestDetails: Bool, fallbackDate: String? = nil) async throws -> ImportOutcome {
        var extraction = result
        if requestDetails, let details = missingDetails(extraction, source: source) {
            source.status = .needsDetails
            source.errorSummary = nil
            let record = source
            try store.commit { try store.upsert(source: record) }
            return ImportOutcome(fileName: record.fileName, status: .needsDetails, source: record, details: details)
        }
        if let fallbackDate, Validator.isValidDate(fallbackDate) {
            for i in extraction.transactions.indices where !Validator.isValidDate(extraction.transactions[i].dateText ?? "")
                && !isYearlessDate(extraction.transactions[i].dateText) {
                extraction.transactions[i].dateText = fallbackDate
            }
        }
        if !extraction.transactions.isEmpty && extraction.transactions.allSatisfy({ Validator.isValidDate($0.dateText ?? "") }) {
            extraction.warnings.removeAll(where: isScreenshotDateWarning)
        }
        try await persist(extraction: extraction, source: &source)
        return ImportOutcome(fileName: source.fileName, status: .imported, source: source)
    }

    private func isScreenshotDateWarning(_ warning: String) -> Bool {
        warning == "Some dates need a statement year/month or manual correction."
            || warning == "Add the statement month (YYYY-MM) for dates without a year."
    }

    private func isYearlessDate(_ date: String?) -> Bool {
        guard let date, !Validator.isValidDate(date),
              Normalizer.normalizeDateText(date, observedMonthHint: nil) == nil else { return false }
        // A leap year recognizes February 29 as a legible month and day.
        return Normalizer.normalizeDateText(date, observedMonthHint: "2024-06").map(Validator.isValidDate) ?? false
    }

    private func missingDetails(_ extraction: ScreenshotExtractionResult, source: SourceDocumentRecord) -> ScreenshotImportDetails? {
        guard source.mimeType.hasPrefix("image/"), !extraction.transactions.isEmpty else { return nil }
        let dates = extraction.transactions.map(\.dateText)
        let needsYear = dates.contains(where: isYearlessDate)
        let needsDate = dates.contains { !Validator.isValidDate($0 ?? "") && !isYearlessDate($0) }
        let needsAccount = store.defaultCurrency == nil && PrivacyRedactor.maskAccountLabel(source.cardName) == "Unknown account" && extraction.transactions.contains {
            PrivacyRedactor.maskAccountLabel($0.accountSourceText) == "Unknown account"
        }
        guard needsYear || needsDate || needsAccount else { return nil }
        return ScreenshotImportDetails(source: source, needsYear: needsYear, needsDate: needsDate, needsAccount: needsAccount)
    }

    func applySharedScreenshotDetails(period: String?, account: String?, accountId: String? = nil, to request: ScreenshotImportDetails) async -> ImportOutcome {
        do {
            guard let current = try detailsForSource(id: request.id) else { return await retry(sourceId: request.id, requestDetails: true) }
            let usePeriod = current.needsYear ? period : nil
            let useAccount = current.needsAccount ? account : nil
            let useAccountId = current.needsAccount ? accountId : nil
            guard usePeriod != nil || useAccount != nil || useAccountId != nil else {
                return ImportOutcome(fileName: current.source.fileName, status: .needsDetails, source: current.source, details: current)
            }
            try updateSourceOptions(id: current.id, cardName: useAccount ?? current.source.cardName ?? "",
                layout: ScreenshotLayout(rawValue: current.source.screenshotLayout ?? "") ?? .automatic,
                month: usePeriod ?? current.source.observedMonthHint ?? "", accountId: useAccountId)
            return await retry(sourceId: request.id, requestDetails: true)
        } catch { return .failure(request.source.fileName, error, source: request.source) }
    }

    func detailsForSource(id: String) throws -> ScreenshotImportDetails? {
        guard let source = try store.source(id: id), source.status == .needsDetails,
              let text = source.ocrLinesJSON, let lines = try? JSONDecoder().decode([OCRLine].self, from: Data(text.utf8)) else { return nil }
        return missingDetails(try parseDocument(source, lines: lines), source: source)
            ?? ScreenshotImportDetails(source: source, needsYear: false, needsDate: false, needsAccount: false)
    }

    private func parseDocument(_ source: SourceDocumentRecord, lines: [OCRLine]) throws -> ScreenshotExtractionResult {
        if source.mimeType == "application/pdf" {
            return try BankStatementParser.parse(sourceId: source.sourceDocumentId, rows: lines.map(\.text), fileName: source.fileName)
        }
        let configured = ScreenshotLayout(rawValue: source.screenshotLayout ?? "") ?? .automatic
        let detected = HeuristicScreenshotParser.detectLayout(lines)
        return HeuristicScreenshotParser.parse(sourceDocumentId: source.sourceDocumentId, fileName: source.fileName, lines: lines,
            options: ScreenshotParseOptions(cardName: source.cardName,
                layout: configured == .capitalOne && detected == .bankActivity ? detected : configured,
                observedMonthHint: source.observedMonthHint))
    }

    func backfillFingerprints() throws {
        let sources = try store.allSources()
        try store.commit {
            for var source in sources where source.contentFingerprint == nil {
                if let relative = source.localRelativePath, let data = try? files.read(relative) {
                    source.contentFingerprint = ContentFingerprint.image(data)
                } else if let text = source.importedJSON ?? source.rawText,
                          let parsed = try? ExtractionJSONParser.parse(text) {
                    source.contentFingerprint = try ContentFingerprint.json(parsed)
                    source.importedJSON = text
                }
                if source.contentFingerprint != nil { try store.upsert(source: source) }
            }
        }
    }

    private func recordFailure(_ error: Error, name: String, source: SourceDocumentRecord?) -> ImportOutcome {
        guard processingAllowed, var record = source else { return .failure(name, error) }
        record.status = .error; record.errorSummary = PrivacyRedactor.safeErrorDetail(error)
        do {
            try store.commit {
                try store.upsert(source: record)
                try store.upsert(review: ReviewItemRecord(reviewItemId: "review_" + StableHash.make([record.sourceDocumentId, "source_error"]),
                    targetType: .sourceDocument, targetId: record.sourceDocumentId, issueType: .missingField, severity: .high,
                    question: "Import needs attention: \(record.errorSummary ?? "Unknown error")", fieldName: "extraction"))
            }
            return .failure(name, error, source: record)
        } catch {
            return .failure(name, error)
        }
    }

    private func persist(extraction: ScreenshotExtractionResult, source: inout SourceDocumentRecord) async throws {
        try requireUnlocked()
        var extraction = extraction
        if let card = source.cardName, !card.isEmpty {
            for i in extraction.transactions.indices { extraction.transactions[i].accountSourceText = card }
        }
        guard !extraction.transactions.isEmpty || !extraction.assetSnapshots.isEmpty else {
            if source.rawText == nil { source.rawText = extraction.rawText }
            throw ExtractionError.emptyResult
        }
        let selectedAccount = try store.account(id: source.importAccountId)
        let output = await ProcessingPipeline.process(PipelineInput(sourceDocumentId: source.sourceDocumentId,
            fileName: source.fileName, extraction: extraction, existingTransactions: try store.allTransactions(),
            corrections: try store.allCorrections(), existingAssets: try store.allAssets(),
            observedMonthHint: source.observedMonthHint ?? HeuristicScreenshotParser.statementMonth(source.rawText ?? ""),
            origin: origin(for: source, kind: extraction.screenshotKind), account: selectedAccount, defaultCurrency: store.defaultCurrency),
            classifier: OnDeviceAIFactory.makeClassifier(enabled: enableFoundationModels()))
        source.status = .processed; source.processedAt = Date(); source.modifiedTime = Date()
        if source.rawText == nil || source.rawText?.isEmpty == true { source.rawText = extraction.rawText }
        source.errorSummary = output.warnings.isEmpty ? nil : PrivacyRedactor.maskSensitiveText(output.warnings.joined(separator: "; "))
        let record = source
        try requireUnlocked()
        try store.commit(rebuild: true) {
            for tx in output.transactions {
                try store.upsert(transaction: tx)
            }
            for var asset in output.assetSnapshots {
                if let account = selectedAccount { asset.accountId = account.id; asset.currencyCode = account.currencyCode; asset.accountLabel = account.label }
                try store.upsert(asset: asset)
            }
            for review in output.reviewItems { try store.upsert(review: review) }
            for var review in try store.allReviews() where review.targetType == .sourceDocument && review.targetId == record.sourceDocumentId && review.status == .pending {
                review.status = .resolved; review.resolvedAt = Date(); review.userAnswer = "Import completed"
                try store.upsert(review: review)
            }
            try store.upsert(source: record)
        }
    }

    private func origin(for source: SourceDocumentRecord, kind: ScreenshotKind? = nil) -> TransactionOrigin? {
        if source.mimeType == "application/pdf" || kind == .bankActivity { return .bank }
        if source.mimeType.hasPrefix("image/") {
            if let raw = source.ocrLinesJSON, let lines = try? JSONDecoder().decode([OCRLine].self, from: Data(raw.utf8)),
               HeuristicScreenshotParser.detectLayout(lines) == .bankActivity { return .bank }
            switch ScreenshotLayout(rawValue: source.screenshotLayout ?? "") {
            case .bankActivity: return .bank
            case .appleCard, .capitalOne: return .card
            default: return nil
            }
        }
        if source.mimeType == "application/json" {
            let resolved = kind ?? source.importedJSON.flatMap { try? ExtractionJSONParser.parse($0).screenshotKind }
            if resolved == .bankActivity { return .bank }
            if resolved == .creditCard { return .card }
        }
        return nil
    }

    func backfillTransactionOrigins() throws {
        let unresolved = try store.allTransactions().filter { $0.origin == nil }
        guard !unresolved.isEmpty else { return }
        let origins = Dictionary(uniqueKeysWithValues: try store.allSources().compactMap { source in
            origin(for: source).map { (source.sourceDocumentId, $0) }
        })
        let updates = unresolved.compactMap { transaction -> TransactionRecord? in
            guard let origin = origins[transaction.sourceDocumentId] else { return nil }
            var row = transaction; row.origin = origin; return row
        }
        guard !updates.isEmpty else { return }
        try store.commit { for row in updates { try store.upsert(transaction: row) } }
    }

    func seedDemo() throws {
        let seed = DemoSeed.make()
        try store.commit(rebuild: true) {
            if try store.account(id: "00000000-0000-0000-0000-000000000001") == nil {
                store.modelContext.insert(SDAccount(id: "00000000-0000-0000-0000-000000000001", label: "Demo account", currencyCode: "USD"))
            }
            for source in seed.sources where try store.source(id: source.sourceDocumentId) == nil { try store.upsert(source: source) }
            let ids = Set(try store.allTransactions().map(\.transactionId))
            let assetIds = Set(try store.allAssets().map(\.assetSnapshotId))
            for tx in seed.transactions where !ids.contains(tx.transactionId) { try store.upsert(transaction: tx) }
            for asset in seed.assets where !assetIds.contains(asset.assetSnapshotId) { try store.upsert(asset: asset) }
            let reviewIds = Set(try store.allReviews().map(\.reviewItemId))
            for review in seed.reviews where !reviewIds.contains(review.reviewItemId) { try store.upsert(review: review) }
        }
    }

    func apply(review: ReviewItemRecord, action: ReviewAction) throws {
        let applied = try CorrectionApplier.apply(review: review, action: action, transactions: store.allTransactions(), reviewItems: store.allReviews())
        try store.commit(rebuild: true) {
            for tx in applied.transactions { try store.upsert(transaction: tx) }
            for review in applied.reviewItems { try store.upsert(review: review) }
            for correction in applied.corrections { try store.insert(correction: correction) }
        }
    }
}

extension ImportPipelineService {
    func completeScreenshotDetails(id: String, account: String, month: String, fallbackDate: String?, accountId: String? = nil) async -> ImportOutcome {
        do {
            guard let request = try detailsForSource(id: id) else {
                return await retry(sourceId: id, requestDetails: true)
            }
            let month = month.trimmingCharacters(in: .whitespacesAndNewlines)
            let account = try store.account(id: accountId)?.label ?? account.trimmingCharacters(in: .whitespacesAndNewlines)
            if request.needsYear && month.isEmpty { throw ImportFailure.invalidMonth }
            if request.needsAccount && PrivacyRedactor.maskAccountLabel(account) == "Unknown account" {
                throw ImportFailure.missingAccount
            }
            if let fallbackDate, !Validator.isValidDate(fallbackDate) { throw ReviewError.invalidFields }
            try updateSourceOptions(id: id, cardName: account, layout: ScreenshotLayout(rawValue: request.source.screenshotLayout ?? "") ?? .automatic, month: month, accountId: accountId)
            return await retry(sourceId: id, fallbackDate: fallbackDate)
        } catch { return .failure("Screenshot details", error) }
    }

    func applySourceBatch(ids: Set<String>, period: String?, account: String?, accountId: String? = nil) async throws -> [ImportOutcome] {
        let sources = try ids.sorted().map { id in
            guard let source = try store.source(id: id),
                  source.mimeType.hasPrefix("image/") || (source.mimeType == "application/pdf" && period == nil) else {
                throw ImportFailure.unavailableSource
            }
            return source
        }
        try store.commit(rebuild: true) {
            for source in sources {
                try updateSourceOptions(id: source.sourceDocumentId, cardName: account ?? source.cardName ?? "",
                    layout: ScreenshotLayout(rawValue: source.screenshotLayout ?? "") ?? .automatic,
                    month: period ?? source.observedMonthHint ?? "", staged: true, accountId: accountId)
            }
        }
        var outcomes: [ImportOutcome] = []
        for source in sources where source.status == .needsDetails {
            outcomes.append(await retry(sourceId: source.sourceDocumentId, requestDetails: true))
        }
        return outcomes
    }

    func updateSourceOptions(id: String, cardName: String, layout: ScreenshotLayout, month: String, staged: Bool = false, accountId: String? = nil, applyAccountToRows: Bool = true) throws {
        guard var source = try store.source(id: id) else { throw ImportFailure.unavailableSource }
        let cleanMonth = month.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleanMonth.isEmpty || Normalizer.isValidStatementDateHint(cleanMonth) else { throw ImportFailure.invalidMonth }
        let oldMonth = source.observedMonthHint
        let oldAccount = source.cardName
        let selectedAccount = try store.account(id: accountId ?? source.importAccountId)
        if let accountId, !accountId.isEmpty, selectedAccount == nil { throw ReviewError.invalidFields }
        if accountId != nil { source.importAccountId = selectedAccount?.id }
        let masked = selectedAccount?.label ?? PrivacyRedactor.maskAccountLabel(cardName)
        source.cardName = masked == "Unknown account" ? nil : masked
        source.screenshotLayout = layout.rawValue
        source.observedMonthHint = cleanMonth.isEmpty ? nil : cleanMonth
        source.modifiedTime = Date()
        let now = source.modifiedTime
        let transactions = try store.allTransactions()
        let reviews = try store.allReviews()
        let priorCorrections = try store.allCorrections()
        let manuallyDated = Set(priorCorrections.filter { $0.targetType == .transaction && $0.fieldName == "transaction_date" }.map(\.targetId))
        let sourceRows = transactions.filter { $0.sourceDocumentId == id }
        var edited: [TransactionRecord] = []
        var correctedDates: Set<String> = []
        var corrections: [CorrectionRecord] = []
        var yearlessEvidence: [String: String] = [:]
        if !cleanMonth.isEmpty, let json = source.ocrLinesJSON,
           let lines = try? JSONDecoder().decode([OCRLine].self, from: Data(json.utf8)), source.mimeType.hasPrefix("image/") {
            var unanchored = source
            unanchored.observedMonthHint = nil
            for candidate in try parseDocument(unanchored, lines: lines).transactions where isYearlessDate(candidate.dateText) {
                if let date = candidate.dateText { yearlessEvidence[candidate.evidenceText] = date }
            }
        }
        for var tx in sourceRows {
            if applyAccountToRows, accountId != nil, tx.accountId != selectedAccount?.id {
                corrections.append(CorrectionRecord(correctionId: UUID().uuidString, targetType: .transaction,
                    targetId: tx.id, fieldName: "account_id", oldValue: tx.accountId ?? "",
                    newValue: selectedAccount?.id ?? "", applyFuture: false))
                tx.assignAccount(selectedAccount, defaultCurrency: store.defaultCurrency)
                tx.accountLabel = masked
            } else if applyAccountToRows, oldAccount != source.cardName, tx.accountLabel != masked {
                corrections.append(CorrectionRecord(correctionId: "corr_" + UUID().uuidString, targetType: .transaction,
                    targetId: tx.transactionId, fieldName: "account_label", oldValue: tx.accountLabel, newValue: masked, applyFuture: false))
                tx.accountLabel = masked
            }
            if source.mimeType.hasPrefix("image/"), !cleanMonth.isEmpty, !manuallyDated.contains(tx.transactionId),
               oldMonth != cleanMonth || !Validator.isValidDate(tx.transactionDate),
               let visibleDate = yearlessEvidence[tx.evidenceText] ?? yearlessEvidenceToken(tx.evidenceText),
               var date = Normalizer.normalizeDateText(visibleDate, observedMonthHint: cleanMonth) {
                if source.screenshotLayout == ScreenshotLayout.bankActivity.rawValue, cleanMonth.hasSuffix("-01"),
                   date.dropFirst(4).hasPrefix("-12"), let year = Int(cleanMonth.prefix(4)) {
                    date = String(year - 1) + date.dropFirst(4)
                }
                if Validator.isValidDate(date), date != tx.transactionDate {
                    corrections.append(CorrectionRecord(correctionId: "corr_" + UUID().uuidString, targetType: .transaction,
                        targetId: tx.transactionId, fieldName: "source_date", oldValue: tx.transactionDate, newValue: date, applyFuture: false))
                    tx.transactionDate = date; tx.observedMonth = String(date.prefix(7))
                    correctedDates.insert(tx.transactionId)
                }
            }
            tx.updatedAt = now
            edited.append(tx)
        }
        let dated = edited.filter { correctedDates.contains($0.transactionId) && $0.validationStatus != .rejected }
        let datedIds = Set(dated.map(\.transactionId))
        let validation = Validator.validate(dated, existingTransactions: transactions.filter { !datedIds.contains($0.transactionId) })
        var issueMap = Dictionary(uniqueKeysWithValues: reviews.map { ($0.reviewItemId, $0) })
        let refreshed = validation.reviewItems.filter { $0.issueType == .duplicateRisk || $0.fieldName == "transaction_date" }
        let refreshedIds = Set(refreshed.map(\.reviewItemId))
        for var issue in reviews where datedIds.contains(issue.targetId) && issue.targetType == .transaction && issue.status == .pending
            && (issue.fieldName == "transaction_date" || issue.issueType == .duplicateRisk) && !refreshedIds.contains(issue.reviewItemId) {
            issue.status = .resolved; issue.resolvedAt = now; issue.userAnswer = "Source date corrected"
            issueMap[issue.reviewItemId] = issue
        }
        for issue in refreshed { issueMap[issue.reviewItemId] = issue }
        let pending = Set(issueMap.values.filter { $0.targetType == .transaction && $0.status == .pending && !$0.isAdvisory }.map(\.targetId))
        for i in edited.indices where datedIds.contains(edited[i].transactionId) {
            let needsReview = pending.contains(edited[i].transactionId)
            edited[i].validationStatus = needsReview ? .needsReview : .valid
            edited[i].reviewStatus = needsReview ? .pending : .resolved
        }
        var result = CorrectionApplication(transactions: transactions.filter { $0.sourceDocumentId != id } + edited,
            reviewItems: Array(issueMap.values), corrections: corrections)
        // Keep unchanged rows stable.
        let before = Dictionary(uniqueKeysWithValues: sourceRows.map { ($0.transactionId, $0) })
        for i in result.transactions.indices {
            if var original = before[result.transactions[i].transactionId] {
                original.updatedAt = now
                if original == result.transactions[i], let unchanged = before[original.transactionId] { result.transactions[i] = unchanged }
            }
        }
        if !edited.isEmpty, edited.allSatisfy({ Validator.isValidDate($0.transactionDate) }), let warning = source.errorSummary {
            let remaining = warning.components(separatedBy: "; ").filter { !isScreenshotDateWarning($0) }
            source.errorSummary = remaining.isEmpty ? nil : remaining.joined(separator: "; ")
        }
        let assets: [AssetSnapshotRecord] = applyAccountToRows && (accountId != nil || oldAccount != source.cardName)
            ? try store.allAssets().filter { $0.sourceDocumentId == id }.map { before in
                var asset = before
                asset.accountLabel = masked
                if accountId != nil {
                    asset.accountId = selectedAccount?.id
                    asset.currencyCode = selectedAccount?.currencyCode
                }
                return asset
            } : []
        _ = try commitCorrection(result, before: transactions, reviews: reviews, source: source, assets: assets, staged: staged)
    }

    private func yearlessEvidenceToken(_ evidence: String) -> String? {
        let fullDate = #"(?i)\b(?:20\d{2}[-/]\d{1,2}[-/]\d{1,2}|\d{1,2}/\d{1,2}/\d{2,4}|(?:Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)[a-z]*\.?\s+\d{1,2},?\s+20\d{2})\b"#
        guard evidence.range(of: fullDate, options: .regularExpression) == nil else { return nil }
        let parts = evidence.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        let date = #"^(?:\d{1,2}/\d{1,2}|(?:Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)[a-z]*\.?\s+\d{1,2})$"#
        let candidates = Set(parts.filter { $0.range(of: date, options: [.regularExpression, .caseInsensitive]) != nil })
        return candidates.count == 1 ? candidates.first : nil
    }

    func deleteStoredImage(sourceId: String) throws {
        guard var source = try store.source(id: sourceId) else { throw ImportFailure.unavailableSource }
        guard let path = source.localRelativePath else { return }
        if FileManager.default.fileExists(atPath: try files.url(path).path) { try files.remove(path) }
        source.localRelativePath = nil
        source.imageDeletedAt = Date()
        // Source IDs, fingerprints, evidence text, and transactions remain available.
        try store.commit { try store.upsert(source: source) }
    }

    func addManualAsset(accountLabel: String, observedDate: String, balance: Double, balanceType: BalanceType, accountId: String? = nil) throws {
        let account = try store.account(id: accountId)
        let label = account?.label ?? PrivacyRedactor.maskAccountLabel(accountLabel)
        guard Validator.isValidDate(observedDate), balance.isFinite, balanceType.tracksAsAsset,
              !label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              label.lowercased() != "unknown account" else {
            throw ReviewError.invalidFields
        }
        let sourceId = "manual_asset_" + UUID().uuidString
        var asset = AssetSnapshotRecord(
            assetSnapshotId: "asset_manual_" + UUID().uuidString,
            sourceDocumentId: sourceId,
            observedMonth: String(observedDate.prefix(7)),
            observedDate: observedDate,
            accountLabel: label,
            balance: balance,
            balanceType: balanceType,
            confidence: 1,
            evidenceText: "Manually entered balance."
        )
        if let account { asset.accountId = account.id; asset.currencyCode = account.currencyCode; asset.accountLabel = account.label }
        try store.commit(rebuild: true) {
            try store.upsert(source: SourceDocumentRecord(
                sourceDocumentId: sourceId,
                sourceType: .manual,
                fileName: "Manual balance",
                mimeType: "application/vnd.spendingassistant.manual-asset",
                status: .processed,
                rawText: "Manually entered balance for \(label).",
                cardName: label
            ))
            try store.upsert(asset: asset)
        }
    }

    func addManualTransaction(_ edit: TransactionEdit, category: SpendingCategory, sourceId: String? = nil, accountId: String? = nil) throws {
        guard Validator.isValidDate(edit.date), edit.amount.isFinite, edit.amount != 0,
              !edit.merchant.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw ReviewError.invalidFields }
        let id = sourceId ?? "manual_" + UUID().uuidString
        if sourceId != nil { guard try store.source(id: id) != nil else { throw ImportFailure.unavailableSource } }
        let normalized = TransactionClassification.normalize(
            type: edit.type,
            category: category == .uncategorized && edit.type != .unknown
                ? (TransactionClassification.canonicalCategory(for: edit.type) ?? .uncategorized)
                : category,
            prefer: category == .uncategorized ? .type : .category
        )
        var tx = TransactionRecord(transactionId: "txn_manual_" + UUID().uuidString, sourceDocumentId: id,
            observedMonth: String(edit.date.prefix(7)), transactionDate: edit.date,
            merchantRaw: edit.merchant, merchantNormalized: Normalizer.normalizeMerchant(edit.merchant), amount: edit.amount,
            transactionType: normalized.type, accountLabel: PrivacyRedactor.maskAccountLabel(edit.account),
            category: normalized.category, categoryConfidence: normalized.category == .uncategorized ? 0 : 1, extractionConfidence: 1,
            validationStatus: .valid, reviewStatus: .resolved, evidenceText: "Manually entered by the user.")
        tx.assignAccount(try store.account(id: accountId), defaultCurrency: store.defaultCurrency)
        let validated = Validator.validate([tx], existingTransactions: try store.allTransactions())
        var reviews = validated.reviewItems
        tx = validated.transactions[0]
        _ = TransactionClassification.normalize(&tx, prefer: .type)
        if tx.category == .uncategorized {
            let categorized = Categorizer.categorize([tx], corrections: try store.allCorrections())
            tx = categorized.transactions[0]; reviews += categorized.reviewItems
        }
        if reviews.isEmpty { tx.reviewStatus = .resolved }
        let record = tx
        try store.commit(rebuild: true) {
            if sourceId == nil {
                try store.upsert(source: SourceDocumentRecord(sourceDocumentId: id, sourceType: .manual,
                    fileName: "Manual transaction", mimeType: "application/vnd.spendingassistant.manual",
                    status: .processed, rawText: "Manually entered by the user.", cardName: record.accountLabel))
            }
            try store.upsert(transaction: record)
            for review in reviews { try store.upsert(review: review) }
        }
    }
}

extension ImportPipelineService {
    @discardableResult
    func editTransaction(id: String, fields: TransactionEdit, category: SpendingCategory?, rememberCategory: Bool = false, confirm: Bool = false, matchSourceAccount: Bool = false, accountId: String? = nil, billedCurrency: String? = nil) throws -> Bool {
        let target = ReviewItemRecord(reviewItemId: "manual_edit", targetType: .transaction, targetId: id,
            issueType: .unclearCategory, severity: .low, question: "Manual correction")
        let transactions = try store.allTransactions()
        let reviews = try store.allReviews()
        guard let current = transactions.first(where: { $0.transactionId == id }) else { throw ReviewError.missingTarget }
        let selectedAccount = try store.account(id: accountId.flatMap { $0.isEmpty ? nil : $0 })
        let accountLabel = selectedAccount?.label ?? PrivacyRedactor.maskAccountLabel(fields.account)
        var fields = fields; fields.account = accountLabel
        if let billedCurrency, !billedCurrency.isEmpty, !Eligibility.validCurrency(billedCurrency) { throw ReviewError.invalidFields }
        let mappingChanged = accountId != nil && (current.accountId ?? "") != (accountId ?? "")
        let fieldsChanged = fields.date != current.transactionDate || fields.merchant != current.merchantNormalized
            || fields.amount != current.amount || fields.type != current.transactionType || fields.account != current.accountLabel
            || mappingChanged
        var applied = fieldsChanged ? try CorrectionApplier.apply(review: target, action: .edit(fields),
            transactions: transactions, reviewItems: reviews)
            : CorrectionApplication(transactions: transactions, reviewItems: reviews, corrections: [])
        if let category, category != .uncategorized {
            if rememberCategory, let edited = applied.transactions.first(where: { $0.transactionId == id }) {
                applyMerchantCategory(edited.merchantNormalized, origin: edited.origin, category: category, to: &applied)
            } else {
                let result = try CorrectionApplier.apply(review: target, action: .category(category, remember: false),
                    transactions: applied.transactions, reviewItems: applied.reviewItems)
                applied.transactions = result.transactions
                applied.reviewItems = result.reviewItems
                applied.corrections += result.corrections
            }
        }
        func applyAccountMapping(to indices: [Int]) {
            guard accountId != nil else { return }
            for i in indices {
                let before = applied.transactions[i]
                let newId = selectedAccount?.id
                let newCurrency = selectedAccount?.currencyCode
                let newLabel = selectedAccount?.label ?? before.accountLabel
                guard before.accountId != newId || before.currencyCode != newCurrency || before.accountLabel != newLabel else { continue }
                applied.corrections.append(CorrectionRecord(correctionId: "corr_" + UUID().uuidString, targetType: .transaction,
                    targetId: before.transactionId, fieldName: "account_id", oldValue: before.accountId ?? "",
                    newValue: newId ?? "", applyFuture: false, createdAt: Date()))
                applied.transactions[i].assignAccount(selectedAccount, defaultCurrency: store.defaultCurrency)
                applied.transactions[i].accountLabel = newLabel
                applied.transactions[i].updatedAt = Date()
            }
        }
        if let index = applied.transactions.firstIndex(where: { $0.transactionId == id }) {
            applyAccountMapping(to: [index])
            if let billedCurrency {
                let value = billedCurrency.isEmpty ? nil : billedCurrency
                let previous = applied.transactions[index].confirmedBilledCurrency
                if value != previous {
                    applied.transactions[index].confirmedBilledCurrency = value
                    applied.corrections.append(CorrectionRecord(correctionId: UUID().uuidString, targetType: .transaction,
                        targetId: id, fieldName: "confirmed_billed_currency", oldValue: previous ?? "",
                        newValue: value ?? "", applyFuture: false))
                }
            }
        }
        var updatedSource: SourceDocumentRecord?
        if matchSourceAccount, !accountLabel.isEmpty, accountLabel != "Unknown account",
           var source = try store.source(id: current.sourceDocumentId), source.mimeType.hasPrefix("image/") {
            if source.cardName != accountLabel || (accountId != nil && source.importAccountId != selectedAccount?.id) {
                applied.corrections.append(CorrectionRecord(correctionId: "corr_" + UUID().uuidString, targetType: .sourceDocument,
                    targetId: source.sourceDocumentId, fieldName: "card_name", oldValue: source.cardName ?? "",
                    newValue: accountLabel, applyFuture: false, createdAt: Date()))
                source.cardName = accountLabel
                if accountId != nil { source.importAccountId = selectedAccount?.id }
                source.modifiedTime = Date(); updatedSource = source
            }
            let siblingIndexes = applied.transactions.indices.filter {
                applied.transactions[$0].sourceDocumentId == source.sourceDocumentId && applied.transactions[$0].transactionId != id
            }
            applyAccountMapping(to: Array(siblingIndexes))
            for i in siblingIndexes where accountId == nil && applied.transactions[i].accountLabel != accountLabel {
                let before = applied.transactions[i]
                applied.transactions[i].accountLabel = accountLabel; applied.transactions[i].updatedAt = Date()
                applied.corrections.append(CorrectionRecord(correctionId: "corr_" + UUID().uuidString, targetType: .transaction,
                    targetId: before.transactionId, fieldName: "account_label", oldValue: before.accountLabel,
                    newValue: accountLabel, applyFuture: false, createdAt: Date()))
            }
        }
        if confirm, let index = applied.transactions.firstIndex(where: { $0.transactionId == id }),
           applied.transactions[index].validationStatus == .valid,
           !applied.reviewItems.contains(where: { $0.targetType == .transaction && $0.targetId == id && $0.status == .pending && !$0.isAdvisory }),
           current.reviewStatus != .resolved {
            applied.transactions[index].reviewStatus = .resolved
            applied.transactions[index].updatedAt = Date()
            applied.corrections.append(CorrectionRecord(correctionId: "corr_" + UUID().uuidString, targetType: .transaction,
                targetId: id, fieldName: "transaction_confirmation", oldValue: current.reviewStatus.rawValue,
                newValue: "confirmed", applyFuture: false, createdAt: Date()))
        }
        return try commitCorrection(applied, before: transactions, reviews: reviews, source: updatedSource)
    }
}

extension ImportPipelineService {
    @discardableResult
    func setMerchantCategory(_ merchant: String, origin: TransactionOrigin? = nil, category: SpendingCategory) throws -> Bool {
        try setMerchantCategories([(merchant, origin)], category: category)
    }

    /// Apply one category to many merchant groups and remember each group.
    func setMerchantCategories(_ merchants: [(name: String, origin: TransactionOrigin?)], category: SpendingCategory) throws -> Bool {
        let before = try store.allTransactions()
        let reviews = try store.allReviews()
        var applied = CorrectionApplication(transactions: before, reviewItems: reviews, corrections: [])
        var seen: Set<String> = []
        for merchant in merchants {
            let key = Categorizer.scopedMerchantKey(merchant.name, origin: merchant.origin)
            guard seen.insert(key).inserted else { continue }
            applyMerchantCategory(merchant.name, origin: merchant.origin, category: category, to: &applied)
        }
        return try commitCorrection(applied, before: before, reviews: reviews)
    }

    private func applyMerchantCategory(_ merchant: String, origin: TransactionOrigin?, category: SpendingCategory, to result: inout CorrectionApplication) {
        let key = Categorizer.merchantKey(merchant)
        guard !key.isEmpty, category != .uncategorized, merchant != "Unknown merchant" else { return }
        let now = Date()
        let indices = result.transactions.indices.filter {
            result.transactions[$0].validationStatus != .rejected && result.transactions[$0].origin == origin && Categorizer.merchantKey(result.transactions[$0].merchantNormalized) == key
        }
        guard !indices.isEmpty else { return }
        let ids = Set(indices.map { result.transactions[$0].transactionId })
        for i in result.reviewItems.indices where result.reviewItems[i].targetType == .transaction
            && ids.contains(result.reviewItems[i].targetId) && result.reviewItems[i].issueType == .unclearCategory
            && result.reviewItems[i].status == .pending {
            result.reviewItems[i].status = .resolved
            result.reviewItems[i].userAnswer = category.rawValue
            result.reviewItems[i].resolvedAt = now
        }
        let required = Set(result.reviewItems.filter { $0.targetType == .transaction && $0.status == .pending && !$0.isAdvisory }.map(\.targetId))
        for i in indices {
            let old = result.transactions[i]
            let pending = required.contains(old.transactionId)
            let normalized = TransactionClassification.normalize(
                type: old.transactionType,
                category: category,
                prefer: .category
            )
            guard old.category != normalized.category || old.categoryConfidence != 1
                    || old.transactionType != normalized.type
                    || old.reviewStatus != (pending ? .pending : .resolved) else { continue }
            result.transactions[i].category = normalized.category
            result.transactions[i].categoryConfidence = 1
            if normalized.type != old.transactionType {
                result.transactions[i].transactionType = normalized.type
                result.corrections.append(CorrectionRecord(correctionId: "corr_" + UUID().uuidString, targetType: .transaction,
                    targetId: old.transactionId, fieldName: "transaction_type", oldValue: old.transactionType.rawValue,
                    newValue: normalized.type.rawValue, applyFuture: false, createdAt: now))
            }
            result.transactions[i].reviewStatus = pending ? .pending : .resolved
            result.transactions[i].validationStatus = pending ? .needsReview : .valid
            result.transactions[i].updatedAt = now
            result.corrections.append(CorrectionRecord(correctionId: "corr_" + UUID().uuidString, targetType: .transaction,
                targetId: old.transactionId, fieldName: "category", oldValue: old.category.rawValue,
                newValue: normalized.category.rawValue, applyFuture: false, createdAt: now))
        }
        result.corrections.append(CorrectionRecord(correctionId: "corr_" + UUID().uuidString, targetType: .merchantRule,
            targetId: Categorizer.ruleTarget(merchant, origin: origin), fieldName: "category", oldValue: "", newValue: category.rawValue,
            applyFuture: true, createdAt: now))
    }

    private func commitCorrection(_ applied: CorrectionApplication, before: [TransactionRecord], reviews: [ReviewItemRecord],
                                  source: SourceDocumentRecord? = nil, assets: [AssetSnapshotRecord] = [], staged: Bool = false) throws -> Bool {
        let originalRows = Dictionary(uniqueKeysWithValues: before.map { ($0.transactionId, $0) })
        let originalReviews = Dictionary(uniqueKeysWithValues: reviews.map { ($0.reviewItemId, $0) })
        let rows = applied.transactions.filter { originalRows[$0.transactionId] != $0 }
        let issues = applied.reviewItems.filter { originalReviews[$0.reviewItemId] != $0 }
        guard !rows.isEmpty || !issues.isEmpty || !applied.corrections.isEmpty || source != nil || !assets.isEmpty else { return false }
        func write() throws {
            for tx in rows { try store.upsert(transaction: tx) }
            for issue in issues { try store.upsert(review: issue) }
            for correction in applied.corrections { try store.insert(correction: correction) }
            if let source { try store.upsert(source: source) }
            for asset in assets { try store.upsert(asset: asset) }
        }
        if staged { try write() } else { try store.commit(rebuild: true, write) }
        return true
    }
}

extension ImportPipelineService {
    func completeManualSource(id: String) throws {
        guard var source = try store.source(id: id) else { throw ImportFailure.unavailableSource }
        if source.status == .processed { return }
        let rows = try store.allTransactions().filter { $0.sourceDocumentId == id }
        let assets = try store.allAssets().filter { $0.sourceDocumentId == id }
        guard !rows.isEmpty, rows.allSatisfy({ $0.transactionId.hasPrefix("txn_manual_") }), assets.isEmpty else {
            throw ImportFailure.replacementHasRows
        }
        source.status = .processed
        source.processedAt = Date()
        source.modifiedTime = Date()
        source.errorSummary = "Manually transcribed. Individual transaction review items may still need attention."
        try store.commit {
            try store.upsert(source: source)
            for var review in try store.allReviews() where review.targetType == .sourceDocument && review.targetId == id && review.status == .pending {
                review.status = .resolved
                review.resolvedAt = Date()
                review.userAnswer = "User confirmed all visible rows were entered manually."
                try store.upsert(review: review)
            }
        }
    }
}

struct ReviewUndoSnapshot {
    let transaction: TransactionRecord
    let reviews: [ReviewItemRecord]
    let correctionIds: Set<String>
    let relatedTransactions: [TransactionRecord]
    let source: SourceDocumentRecord?
    let merchantKey: String?
}

extension ImportPipelineService {
    func reviewSnapshot(_ transaction: TransactionRecord, accountSource: Bool = false, merchant: String? = nil) throws -> ReviewUndoSnapshot {
        let key = merchant.map { Categorizer.scopedMerchantKey($0, origin: transaction.origin) }
        let related = try store.allTransactions().filter {
            $0.transactionId != transaction.transactionId &&
                ((accountSource && $0.sourceDocumentId == transaction.sourceDocumentId)
                || (key != nil && Categorizer.scopedMerchantKey($0.merchantNormalized, origin: $0.origin) == key))
        }
        let ids = Set(related.map(\.transactionId) + [transaction.transactionId])
        return ReviewUndoSnapshot(transaction: transaction,
            reviews: try store.allReviews().filter { $0.targetType == .transaction && ids.contains($0.targetId) },
            correctionIds: Set(try store.allCorrections().map(\.correctionId)), relatedTransactions: related,
            source: accountSource ? try store.source(id: transaction.sourceDocumentId) : nil, merchantKey: key)
    }

    func undoReview(_ snapshot: ReviewUndoSnapshot) throws {
        let transactions = snapshot.relatedTransactions + [snapshot.transaction]
        let ids = Set(transactions.map(\.transactionId))
        try store.commit(rebuild: true) {
            for transaction in transactions { try store.upsert(transaction: transaction) }
            if let source = snapshot.source { try store.upsert(source: source) }
            for row in try store.modelContext.fetch(FetchDescriptor<SDReviewItem>()) where row.targetTypeRaw == ReviewTargetType.transaction.rawValue && ids.contains(row.targetId) {
                store.modelContext.delete(row)
            }
            for review in snapshot.reviews { try store.upsert(review: review) }
            for row in try store.modelContext.fetch(FetchDescriptor<SDCorrection>()) where !snapshot.correctionIds.contains(row.correctionId) {
                let relatedRow = row.targetTypeRaw == CorrectionTargetType.transaction.rawValue && ids.contains(row.targetId)
                let sourceEdit = row.targetTypeRaw == CorrectionTargetType.sourceDocument.rawValue && row.targetId == snapshot.source?.sourceDocumentId
                let rule = row.targetTypeRaw == CorrectionTargetType.merchantRule.rawValue
                    && Categorizer.ruleKey(target: row.targetId) == (snapshot.merchantKey ?? Categorizer.scopedMerchantKey(snapshot.transaction.merchantNormalized, origin: snapshot.transaction.origin))
                if relatedRow || sourceEdit || rule { store.modelContext.delete(row) }
            }
        }
    }

    func deleteSource(id: String) throws {
        guard let source = try store.source(id: id) else { throw ImportFailure.unavailableSource }
        let manager = FileManager.default
        if let path = source.localRelativePath {
            let original = try files.url(path)
            if manager.fileExists(atPath: original.path) {
                let staged = try files.url(".deleting-" + UUID().uuidString)
                try manager.moveItem(at: original, to: staged)
                do { try store.deleteSource(id: id) }
                catch {
                    try manager.moveItem(at: staged, to: original)
                    throw error
                }
                try manager.removeItem(at: staged)
                return
            }
        }
        try store.deleteSource(id: id)
    }
}


extension ImportPipelineService {
    @discardableResult
    func cleanupSources(retentionDays: Int) throws -> Int {
        guard processingAllowed, retentionDays > 0 else { return 0 }
        var removed = 0
        let cutoff = Date().addingTimeInterval(-Double(retentionDays) * 86_400)
        for var source in try store.allSources() {
            guard let path = source.localRelativePath else { continue }
            let url = try files.url(path)
            guard FileManager.default.fileExists(atPath: url.path),
                  let modified = try url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
                  modified < cutoff else { continue }
            // Record the retention decision first; a failed file removal can be retried.
            source.originalFileStatus = "expired"
            try store.commit { try store.upsert(source: source) }
            try files.remove(path)
            removed += 1
        }
        return removed
    }
}
