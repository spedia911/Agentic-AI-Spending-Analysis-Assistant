import Foundation
import SwiftData
import SpendingDomain

@Model
final class SDSourceDocument {
    @Attribute(.unique) var sourceDocumentId: String
    var sourceTypeRaw: String
    var fileName: String
    var mimeType: String
    var localRelativePath: String?
    var createdTime: Date
    var modifiedTime: Date
    var processedAt: Date?
    var statusRaw: String
    var errorSummary: String?
    var rawText: String?
    var contentFingerprint: String?
    var importedJSON: String?
    var cardName: String?
    var screenshotLayout: String?
    var observedMonthHint: String?
    var ocrLinesJSON: String?
    var imageDeletedAt: Date?
    var originalFileStatus: String?
    var importAccountId: String?

    init(from record: SourceDocumentRecord) {
        self.sourceDocumentId = record.sourceDocumentId
        self.sourceTypeRaw = record.sourceType.rawValue
        self.fileName = record.fileName
        self.mimeType = record.mimeType
        self.localRelativePath = record.localRelativePath
        self.createdTime = record.createdTime
        self.modifiedTime = record.modifiedTime
        self.processedAt = record.processedAt
        self.statusRaw = record.status.rawValue
        self.errorSummary = record.errorSummary
        self.rawText = record.rawText
        self.contentFingerprint = record.contentFingerprint
        self.importedJSON = record.importedJSON
        self.imageDeletedAt = record.imageDeletedAt
        self.originalFileStatus = record.originalFileStatus
        self.importAccountId = record.importAccountId
        self.ocrLinesJSON = record.ocrLinesJSON
        self.observedMonthHint = record.observedMonthHint
        self.screenshotLayout = record.screenshotLayout
        self.cardName = record.cardName
    }

    func apply(_ record: SourceDocumentRecord) {
        sourceTypeRaw = record.sourceType.rawValue
        fileName = record.fileName
        mimeType = record.mimeType
        localRelativePath = record.localRelativePath
        createdTime = record.createdTime
        modifiedTime = record.modifiedTime
        processedAt = record.processedAt
        statusRaw = record.status.rawValue
        errorSummary = record.errorSummary
        rawText = record.rawText
        contentFingerprint = record.contentFingerprint
        importedJSON = record.importedJSON
        imageDeletedAt = record.imageDeletedAt
        originalFileStatus = record.originalFileStatus
        importAccountId = record.importAccountId
        ocrLinesJSON = record.ocrLinesJSON
        observedMonthHint = record.observedMonthHint
        screenshotLayout = record.screenshotLayout
        cardName = record.cardName
    }

    func toRecord() -> SourceDocumentRecord {
        var record = SourceDocumentRecord(
            sourceDocumentId: sourceDocumentId,
            sourceType: SourceType(rawValue: sourceTypeRaw) ?? .files,
            fileName: fileName,
            mimeType: mimeType,
            localRelativePath: localRelativePath,
            createdTime: createdTime,
            modifiedTime: modifiedTime,
            processedAt: processedAt,
            status: ProcessingStatus(rawValue: statusRaw) ?? .pending,
            errorSummary: errorSummary,
            rawText: rawText,
            contentFingerprint: contentFingerprint,
            importedJSON: importedJSON,
            cardName: cardName,
            screenshotLayout: screenshotLayout,
            observedMonthHint: observedMonthHint,
            ocrLinesJSON: ocrLinesJSON,
            imageDeletedAt: imageDeletedAt,
            originalFileStatus: originalFileStatus
        )
        record.importAccountId = importAccountId
        return record
    }
}

@Model
final class SDTransaction {
    @Attribute(.unique) var transactionId: String
    var sourceDocumentId: String
    var observedMonth: String
    var transactionDate: String
    var merchantRaw: String
    var merchantNormalized: String
    var amount: Double
    var transactionTypeRaw: String
    var accountId: String?
    var currencyCode: String?
    var confirmedBilledCurrency: String?
    var assumedCurrencyCode: String?
    var billedCurrencyCode: String? { confirmedBilledCurrency ?? assumedCurrencyCode ?? currencyCode }
    var accountLabel: String
    var originRaw: String?
    var categoryRaw: String
    var categoryConfidence: Double
    var extractionConfidence: Double
    var validationStatusRaw: String
    var reviewStatusRaw: String
    var evidenceText: String
    var evidenceRegion: String?
    var createdAt: Date
    var updatedAt: Date

    init(from record: TransactionRecord) {
        self.transactionId = record.transactionId
        self.sourceDocumentId = record.sourceDocumentId
        self.observedMonth = record.observedMonth
        self.transactionDate = record.transactionDate
        self.merchantRaw = record.merchantRaw
        self.merchantNormalized = record.merchantNormalized
        self.amount = record.amount
        self.transactionTypeRaw = record.transactionType.rawValue
        self.accountId = record.accountId
        self.currencyCode = record.currencyCode
        self.confirmedBilledCurrency = record.confirmedBilledCurrency
        self.assumedCurrencyCode = record.assumedCurrencyCode
        self.accountLabel = record.accountLabel
        self.originRaw = record.origin?.rawValue
        self.categoryRaw = record.category.rawValue
        self.categoryConfidence = record.categoryConfidence
        self.extractionConfidence = record.extractionConfidence
        self.validationStatusRaw = record.validationStatus.rawValue
        self.reviewStatusRaw = record.reviewStatus.rawValue
        self.evidenceText = record.evidenceText
        self.evidenceRegion = record.evidenceRegion
        self.createdAt = record.createdAt
        self.updatedAt = record.updatedAt
    }

    func apply(_ record: TransactionRecord) {
        sourceDocumentId = record.sourceDocumentId
        observedMonth = record.observedMonth
        transactionDate = record.transactionDate
        merchantRaw = record.merchantRaw
        merchantNormalized = record.merchantNormalized
        amount = record.amount
        transactionTypeRaw = record.transactionType.rawValue
        accountId = record.accountId
        currencyCode = record.currencyCode
        confirmedBilledCurrency = record.confirmedBilledCurrency
        assumedCurrencyCode = record.assumedCurrencyCode
        accountLabel = record.accountLabel
        originRaw = record.origin?.rawValue
        categoryRaw = record.category.rawValue
        categoryConfidence = record.categoryConfidence
        extractionConfidence = record.extractionConfidence
        validationStatusRaw = record.validationStatus.rawValue
        reviewStatusRaw = record.reviewStatus.rawValue
        evidenceText = record.evidenceText
        evidenceRegion = record.evidenceRegion
        createdAt = record.createdAt
        updatedAt = record.updatedAt
    }

    func toRecord() -> TransactionRecord {
        var record = TransactionRecord(
            transactionId: transactionId,
            sourceDocumentId: sourceDocumentId,
            observedMonth: observedMonth,
            transactionDate: transactionDate,
            merchantRaw: merchantRaw,
            merchantNormalized: merchantNormalized,
            amount: amount,
            transactionType: TransactionType(rawValue: transactionTypeRaw) ?? .unknown,
            accountLabel: accountLabel,
            accountId: accountId,
            currencyCode: currencyCode,
            origin: originRaw.flatMap(TransactionOrigin.init(rawValue:)),
            category: SpendingCategory(rawValue: categoryRaw) ?? .uncategorized,
            categoryConfidence: categoryConfidence,
            extractionConfidence: extractionConfidence,
            validationStatus: ValidationStatus(rawValue: validationStatusRaw) ?? .needsReview,
            reviewStatus: ReviewStatus(rawValue: reviewStatusRaw) ?? .none,
            evidenceText: evidenceText,
            evidenceRegion: evidenceRegion,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
        record.confirmedBilledCurrency = confirmedBilledCurrency
        record.assumedCurrencyCode = assumedCurrencyCode
        return record
    }
}

@Model
final class SDAssetSnapshot {
    @Attribute(.unique) var assetSnapshotId: String
    var sourceDocumentId: String
    var observedMonth: String
    var observedDate: String
    var accountId: String?
    var currencyCode: String?
    var confirmedCurrencyCode: String?
    var accountLabel: String
    var balance: Double
    var balanceTypeRaw: String
    var confidence: Double
    var evidenceText: String
    var evidenceRegion: String?
    var createdAt: Date

    init(from record: AssetSnapshotRecord) {
        self.assetSnapshotId = record.assetSnapshotId
        self.sourceDocumentId = record.sourceDocumentId
        self.observedMonth = record.observedMonth
        self.observedDate = record.observedDate
        self.accountId = record.accountId
        self.currencyCode = record.currencyCode
        self.confirmedCurrencyCode = record.confirmedCurrencyCode
        self.accountLabel = record.accountLabel
        self.balance = record.balance
        self.balanceTypeRaw = record.balanceType.rawValue
        self.confidence = record.confidence
        self.evidenceText = record.evidenceText
        self.evidenceRegion = record.evidenceRegion
        self.createdAt = record.createdAt
    }

    func apply(_ record: AssetSnapshotRecord) {
        sourceDocumentId = record.sourceDocumentId
        observedMonth = record.observedMonth
        observedDate = record.observedDate
        accountId = record.accountId
        currencyCode = record.currencyCode
        confirmedCurrencyCode = record.confirmedCurrencyCode
        accountLabel = record.accountLabel
        balance = record.balance
        balanceTypeRaw = record.balanceType.rawValue
        confidence = record.confidence
        evidenceText = record.evidenceText
        evidenceRegion = record.evidenceRegion
        createdAt = record.createdAt
    }

    func toRecord() -> AssetSnapshotRecord {
        var record = AssetSnapshotRecord(
            assetSnapshotId: assetSnapshotId,
            sourceDocumentId: sourceDocumentId,
            observedMonth: observedMonth,
            observedDate: observedDate,
            accountLabel: accountLabel,
            accountId: accountId,
            currencyCode: currencyCode,
            balance: balance,
            balanceType: BalanceType(rawValue: balanceTypeRaw) ?? .unknown,
            confidence: confidence,
            evidenceText: evidenceText,
            evidenceRegion: evidenceRegion,
            createdAt: createdAt
        )
        record.confirmedCurrencyCode = confirmedCurrencyCode
        return record
    }
}

@Model
final class SDReviewItem {
    @Attribute(.unique) var reviewItemId: String
    var targetTypeRaw: String
    var targetId: String
    var issueTypeRaw: String
    var fieldName: String?
    var severityRaw: String
    var question: String
    var suggestedOptionsJSON: String
    var statusRaw: String
    var userAnswer: String?
    var createdAt: Date
    var resolvedAt: Date?

    init(from record: ReviewItemRecord) {
        self.reviewItemId = record.reviewItemId
        self.targetTypeRaw = record.targetType.rawValue
        self.targetId = record.targetId
        self.issueTypeRaw = record.issueType.rawValue
        self.fieldName = record.fieldName
        self.severityRaw = record.severity.rawValue
        self.question = record.question
        self.suggestedOptionsJSON = (try? String(data: JSONEncoder().encode(record.suggestedOptions), encoding: .utf8)) ?? "[]"
        self.statusRaw = record.status.rawValue
        self.userAnswer = record.userAnswer
        self.createdAt = record.createdAt
        self.resolvedAt = record.resolvedAt
    }

    func apply(_ record: ReviewItemRecord) {
        targetTypeRaw = record.targetType.rawValue
        targetId = record.targetId
        issueTypeRaw = record.issueType.rawValue
        fieldName = record.fieldName
        severityRaw = record.severity.rawValue
        question = record.question
        suggestedOptionsJSON = (try? String(data: JSONEncoder().encode(record.suggestedOptions), encoding: .utf8)) ?? "[]"
        statusRaw = record.status.rawValue
        userAnswer = record.userAnswer
        createdAt = record.createdAt
        resolvedAt = record.resolvedAt
    }

    func toRecord() -> ReviewItemRecord {
        let options = (try? JSONDecoder().decode([String].self, from: Data(suggestedOptionsJSON.utf8))) ?? []
        return ReviewItemRecord(
            reviewItemId: reviewItemId,
            targetType: ReviewTargetType(rawValue: targetTypeRaw) ?? .transaction,
            targetId: targetId,
            issueType: ReviewIssueType(rawValue: issueTypeRaw) ?? .lowConfidence,
            severity: Severity(rawValue: severityRaw) ?? .medium,
            question: question,
            fieldName: fieldName,
            suggestedOptions: options,
            status: ReviewItemStatus(rawValue: statusRaw) ?? .pending,
            userAnswer: userAnswer,
            createdAt: createdAt,
            resolvedAt: resolvedAt
        )
    }
}

@Model
final class SDCorrection {
    @Attribute(.unique) var correctionId: String
    var targetTypeRaw: String
    var targetId: String
    var fieldName: String
    var oldValue: String
    var newValue: String
    var applyFuture: Bool
    var createdAt: Date

    init(from record: CorrectionRecord) {
        self.correctionId = record.correctionId
        self.targetTypeRaw = record.targetType.rawValue
        self.targetId = record.targetId
        self.fieldName = record.fieldName
        self.oldValue = record.oldValue
        self.newValue = record.newValue
        self.applyFuture = record.applyFuture
        self.createdAt = record.createdAt
    }

    func toRecord() -> CorrectionRecord {
        CorrectionRecord(
            correctionId: correctionId,
            targetType: CorrectionTargetType(rawValue: targetTypeRaw) ?? .transaction,
            targetId: targetId,
            fieldName: fieldName,
            oldValue: oldValue,
            newValue: newValue,
            applyFuture: applyFuture,
            createdAt: createdAt
        )
    }
}

@Model
final class SDMonthlySummary {
    var currencyCode: String?
    var month: String
    var category: String
    var totalAmount: Double
    var transactionCount: Int
    var reviewedCount: Int
    var unresolvedCount: Int
    var monthOverMonthDelta: Double?
    var completenessStatusRaw: String

    init(from record: MonthlySummaryRecord) {
        self.currencyCode = record.currencyCode
        self.month = record.month
        self.category = record.category
        self.totalAmount = record.totalAmount
        self.transactionCount = record.transactionCount
        self.reviewedCount = record.reviewedCount
        self.unresolvedCount = record.unresolvedCount
        self.monthOverMonthDelta = record.monthOverMonthDelta
        self.completenessStatusRaw = record.completenessStatus.rawValue
    }

    func toRecord() -> MonthlySummaryRecord {
        MonthlySummaryRecord(
            month: month,
            category: category,
            totalAmount: totalAmount,
            transactionCount: transactionCount,
            reviewedCount: reviewedCount,
            unresolvedCount: unresolvedCount,
            monthOverMonthDelta: monthOverMonthDelta,
            completenessStatus: CompletenessStatus(rawValue: completenessStatusRaw) ?? .unknown,
            currencyCode: currencyCode
        )
    }
}

@Model
final class SDCashFlowSummary {
    var currencyCode: String?
    var month: String
    var spendingTotal: Double
    var incomeTotal: Double
    var refundTotal: Double
    var transferTotal: Double
    var paymentTotal: Double
    var feeTotal: Double
    var netCashFlow: Double
    var transactionCount: Int
    var unresolvedCount: Int
    var completenessStatusRaw: String

    init(from record: CashFlowSummaryRecord) {
        self.currencyCode = record.currencyCode
        self.month = record.month
        self.spendingTotal = record.spendingTotal
        self.incomeTotal = record.incomeTotal
        self.refundTotal = record.refundTotal
        self.transferTotal = record.transferTotal
        self.paymentTotal = record.paymentTotal
        self.feeTotal = record.feeTotal
        self.netCashFlow = record.netCashFlow
        self.transactionCount = record.transactionCount
        self.unresolvedCount = record.unresolvedCount
        self.completenessStatusRaw = record.completenessStatus.rawValue
    }

    func toRecord() -> CashFlowSummaryRecord {
        CashFlowSummaryRecord(
            month: month,
            spendingTotal: spendingTotal,
            incomeTotal: incomeTotal,
            refundTotal: refundTotal,
            transferTotal: transferTotal,
            paymentTotal: paymentTotal,
            feeTotal: feeTotal,
            netCashFlow: netCashFlow,
            transactionCount: transactionCount,
            unresolvedCount: unresolvedCount,
            completenessStatus: CompletenessStatus(rawValue: completenessStatusRaw) ?? .unknown,
            currencyCode: currencyCode
        )
    }
}

@Model
final class SDAnomaly {
    @Attribute(.unique) var anomalyId: String
    var anomalyTypeRaw: String
    var severityRaw: String
    var month: String
    var relatedRecordIdsJSON: String
    var summary: String
    var suggestedAction: String
    var statusRaw: String
    var createdAt: Date

    init(from record: AnomalyRecord) {
        self.anomalyId = record.anomalyId
        self.anomalyTypeRaw = record.anomalyType.rawValue
        self.severityRaw = record.severity.rawValue
        self.month = record.month
        self.relatedRecordIdsJSON = (try? String(data: JSONEncoder().encode(record.relatedRecordIds), encoding: .utf8)) ?? "[]"
        self.summary = record.summary
        self.suggestedAction = record.suggestedAction
        self.statusRaw = record.status.rawValue
        self.createdAt = record.createdAt
    }

    func apply(_ record: AnomalyRecord) {
        anomalyTypeRaw = record.anomalyType.rawValue
        severityRaw = record.severity.rawValue
        month = record.month
        relatedRecordIdsJSON = (try? String(data: JSONEncoder().encode(record.relatedRecordIds), encoding: .utf8)) ?? "[]"
        summary = record.summary
        suggestedAction = record.suggestedAction
        statusRaw = record.status.rawValue
        createdAt = record.createdAt
    }

    func toRecord() -> AnomalyRecord {
        let related = (try? JSONDecoder().decode([String].self, from: Data(relatedRecordIdsJSON.utf8))) ?? []
        return AnomalyRecord(
            anomalyId: anomalyId,
            anomalyType: AnomalyType(rawValue: anomalyTypeRaw) ?? .missingData,
            severity: Severity(rawValue: severityRaw) ?? .low,
            month: month,
            relatedRecordIds: related,
            summary: summary,
            suggestedAction: suggestedAction,
            status: AnomalyStatus(rawValue: statusRaw) ?? .open,
            createdAt: createdAt
        )
    }
}

@Model
final class SDAccount {
    @Attribute(.unique) var accountId: String
    var label: String
    var currencyCode: String
    var preferredSpendingCurrency: String?
    var spendingCurrency: String { preferredSpendingCurrency ?? currencyCode }
    init(id: String = UUID().uuidString, label: String, currencyCode: String, preferredSpendingCurrency: String? = nil) {
        self.accountId = id; self.label = label; self.currencyCode = currencyCode
        self.preferredSpendingCurrency = preferredSpendingCurrency
    }
    func toRecord() -> AccountRecord { AccountRecord(accountId: accountId, label: label, currencyCode: currencyCode, preferredSpendingCurrency: preferredSpendingCurrency) }
}

@Model
final class SDDataset {
    @Attribute(.unique) var key: String
    var datasetId: String
    var restoredSnapshotId: String?
    init(datasetId: String = UUID().uuidString) { key = "primary"; self.datasetId = datasetId }
}
