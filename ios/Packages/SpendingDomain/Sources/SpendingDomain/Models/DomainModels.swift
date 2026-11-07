import Foundation

public enum SourceType: String, Codable, Sendable, CaseIterable {
    case photos, files, share, aiImport = "ai_import"
}

public enum ProcessingStatus: String, Codable, Sendable, CaseIterable {
    case pending, processed, skipped, error
}

public enum TransactionType: String, Codable, Sendable, CaseIterable {
    case expense, income, transfer, payment, fee, refund, unknown
}

public enum ValidationStatus: String, Codable, Sendable, CaseIterable {
    case valid, needsReview = "needs_review", rejected
}

public enum ReviewStatus: String, Codable, Sendable, CaseIterable {
    case none, pending, resolved
}

public enum BalanceType: String, Codable, Sendable, CaseIterable {
    case checking, savings, creditAvailable = "credit_available", creditBalance = "credit_balance", unknown
}

public enum ReviewTargetType: String, Codable, Sendable, CaseIterable {
    case transaction, assetSnapshot = "asset_snapshot", sourceDocument = "source_document"
}

public enum ReviewIssueType: String, Codable, Sendable, CaseIterable {
    case lowConfidence = "low_confidence"
    case missingField = "missing_field"
    case duplicateRisk = "duplicate_risk"
    case anomaly
    case unclearCategory = "unclear_category"
}

public enum Severity: String, Codable, Sendable, CaseIterable {
    case low, medium, high
}

public enum ReviewItemStatus: String, Codable, Sendable, CaseIterable {
    case pending, resolved, ignored
}

public enum CorrectionTargetType: String, Codable, Sendable, CaseIterable {
    case transaction, merchantRule = "merchant_rule", assetSnapshot = "asset_snapshot", anomaly, sourceDocument = "source_document"
}

public enum CompletenessStatus: String, Codable, Sendable, CaseIterable {
    case complete, partial, unknown
}

public enum MaintainabilityFlag: String, Codable, Sendable, CaseIterable {
    case ok, watch, concern, unknown
}

public enum AnomalyType: String, Codable, Sendable, CaseIterable {
    case duplicateCharge = "duplicate_charge"
    case spendingSpike = "spending_spike"
    case balanceDrop = "balance_drop"
    case recurringChange = "recurring_change"
    case missingData = "missing_data"
}

public enum AnomalyStatus: String, Codable, Sendable, CaseIterable {
    case open, resolved, ignored
}

public enum RunStatus: String, Codable, Sendable, CaseIterable {
    case success, partialSuccess = "partial_success", failed
}

public enum ScreenshotKind: String, Codable, Sendable, CaseIterable {
    case creditCard = "credit_card"
    case bankActivity = "bank_activity"
    case mixed
    case unknown
}

public enum SpendingCategory: String, Codable, Sendable, CaseIterable {
    case groceries, dining, utilities, transportation, rent, subscriptions, shopping, healthcare, transfer, income, fees, miscellaneous, uncategorized
}

public struct EvidenceRegion: Codable, Sendable, Equatable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x; self.y = y; self.width = width; self.height = height
    }
}

public struct SourceDocumentRecord: Codable, Sendable, Equatable, Identifiable {
    public var id: String { sourceDocumentId }
    public var sourceDocumentId: String
    public var sourceType: SourceType
    public var fileName: String
    public var mimeType: String
    public var localRelativePath: String?
    public var createdTime: Date
    public var modifiedTime: Date
    public var processedAt: Date?
    public var status: ProcessingStatus
    public var errorSummary: String?
    public var rawText: String?

    public init(
        sourceDocumentId: String,
        sourceType: SourceType,
        fileName: String,
        mimeType: String,
        localRelativePath: String? = nil,
        createdTime: Date = Date(),
        modifiedTime: Date = Date(),
        processedAt: Date? = nil,
        status: ProcessingStatus = .pending,
        errorSummary: String? = nil,
        rawText: String? = nil
    ) {
        self.sourceDocumentId = sourceDocumentId
        self.sourceType = sourceType
        self.fileName = fileName
        self.mimeType = mimeType
        self.localRelativePath = localRelativePath
        self.createdTime = createdTime
        self.modifiedTime = modifiedTime
        self.processedAt = processedAt
        self.status = status
        self.errorSummary = errorSummary
        self.rawText = rawText
    }
}

public struct TransactionRecord: Codable, Sendable, Equatable, Identifiable {
    public var id: String { transactionId }
    public var transactionId: String
    public var sourceDocumentId: String
    public var observedMonth: String
    public var transactionDate: String
    public var merchantRaw: String
    public var merchantNormalized: String
    public var amount: Double
    public var transactionType: TransactionType
    public var accountLabel: String
    public var category: SpendingCategory
    public var categoryConfidence: Double
    public var extractionConfidence: Double
    public var validationStatus: ValidationStatus
    public var reviewStatus: ReviewStatus
    public var evidenceText: String
    public var evidenceRegion: String?
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        transactionId: String,
        sourceDocumentId: String,
        observedMonth: String,
        transactionDate: String,
        merchantRaw: String,
        merchantNormalized: String,
        amount: Double,
        transactionType: TransactionType,
        accountLabel: String,
        category: SpendingCategory = .uncategorized,
        categoryConfidence: Double = 0,
        extractionConfidence: Double,
        validationStatus: ValidationStatus,
        reviewStatus: ReviewStatus,
        evidenceText: String,
        evidenceRegion: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.transactionId = transactionId
        self.sourceDocumentId = sourceDocumentId
        self.observedMonth = observedMonth
        self.transactionDate = transactionDate
        self.merchantRaw = merchantRaw
        self.merchantNormalized = merchantNormalized
        self.amount = amount
        self.transactionType = transactionType
        self.accountLabel = accountLabel
        self.category = category
        self.categoryConfidence = categoryConfidence
        self.extractionConfidence = extractionConfidence
        self.validationStatus = validationStatus
        self.reviewStatus = reviewStatus
        self.evidenceText = evidenceText
        self.evidenceRegion = evidenceRegion
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct AssetSnapshotRecord: Codable, Sendable, Equatable, Identifiable {
    public var id: String { assetSnapshotId }
    public var assetSnapshotId: String
    public var sourceDocumentId: String
    public var observedMonth: String
    public var observedDate: String
    public var accountLabel: String
    public var balance: Double
    public var balanceType: BalanceType
    public var confidence: Double
    public var evidenceText: String
    public var evidenceRegion: String?
    public var createdAt: Date

    public init(
        assetSnapshotId: String,
        sourceDocumentId: String,
        observedMonth: String,
        observedDate: String,
        accountLabel: String,
        balance: Double,
        balanceType: BalanceType,
        confidence: Double,
        evidenceText: String,
        evidenceRegion: String? = nil,
        createdAt: Date = Date()
    ) {
        self.assetSnapshotId = assetSnapshotId
        self.sourceDocumentId = sourceDocumentId
        self.observedMonth = observedMonth
        self.observedDate = observedDate
        self.accountLabel = accountLabel
        self.balance = balance
        self.balanceType = balanceType
        self.confidence = confidence
        self.evidenceText = evidenceText
        self.evidenceRegion = evidenceRegion
        self.createdAt = createdAt
    }
}

public struct ReviewItemRecord: Codable, Sendable, Equatable, Identifiable {
    public var id: String { reviewItemId }
    public var reviewItemId: String
    public var targetType: ReviewTargetType
    public var targetId: String
    public var issueType: ReviewIssueType
    public var severity: Severity
    public var question: String
    public var suggestedOptions: [String]
    public var status: ReviewItemStatus
    public var userAnswer: String?
    public var createdAt: Date
    public var resolvedAt: Date?

    public init(
        reviewItemId: String,
        targetType: ReviewTargetType,
        targetId: String,
        issueType: ReviewIssueType,
        severity: Severity,
        question: String,
        suggestedOptions: [String] = [],
        status: ReviewItemStatus = .pending,
        userAnswer: String? = nil,
        createdAt: Date = Date(),
        resolvedAt: Date? = nil
    ) {
        self.reviewItemId = reviewItemId
        self.targetType = targetType
        self.targetId = targetId
        self.issueType = issueType
        self.severity = severity
        self.question = question
        self.suggestedOptions = suggestedOptions
        self.status = status
        self.userAnswer = userAnswer
        self.createdAt = createdAt
        self.resolvedAt = resolvedAt
    }
}

public struct CorrectionRecord: Codable, Sendable, Equatable, Identifiable {
    public var id: String { correctionId }
    public var correctionId: String
    public var targetType: CorrectionTargetType
    public var targetId: String
    public var fieldName: String
    public var oldValue: String
    public var newValue: String
    public var applyFuture: Bool
    public var createdAt: Date

    public init(
        correctionId: String,
        targetType: CorrectionTargetType,
        targetId: String,
        fieldName: String,
        oldValue: String,
        newValue: String,
        applyFuture: Bool,
        createdAt: Date = Date()
    ) {
        self.correctionId = correctionId
        self.targetType = targetType
        self.targetId = targetId
        self.fieldName = fieldName
        self.oldValue = oldValue
        self.newValue = newValue
        self.applyFuture = applyFuture
        self.createdAt = createdAt
    }
}

public struct MonthlySummaryRecord: Codable, Sendable, Equatable {
    public var month: String
    public var category: String
    public var totalAmount: Double
    public var transactionCount: Int
    public var reviewedCount: Int
    public var unresolvedCount: Int
    public var monthOverMonthDelta: Double?
    public var completenessStatus: CompletenessStatus

    public init(month: String, category: String, totalAmount: Double, transactionCount: Int, reviewedCount: Int, unresolvedCount: Int, monthOverMonthDelta: Double?, completenessStatus: CompletenessStatus) {
        self.month = month; self.category = category; self.totalAmount = totalAmount
        self.transactionCount = transactionCount; self.reviewedCount = reviewedCount
        self.unresolvedCount = unresolvedCount; self.monthOverMonthDelta = monthOverMonthDelta
        self.completenessStatus = completenessStatus
    }
}

public struct QuarterlySummaryRecord: Codable, Sendable, Equatable {
    public var quarter: String
    public var category: String
    public var totalAmount: Double
    public var transactionCount: Int
    public var quarterOverQuarterDelta: Double?
    public var completenessStatus: CompletenessStatus

    public init(quarter: String, category: String, totalAmount: Double, transactionCount: Int, quarterOverQuarterDelta: Double?, completenessStatus: CompletenessStatus) {
        self.quarter = quarter; self.category = category; self.totalAmount = totalAmount
        self.transactionCount = transactionCount; self.quarterOverQuarterDelta = quarterOverQuarterDelta
        self.completenessStatus = completenessStatus
    }
}

public struct CashFlowSummaryRecord: Codable, Sendable, Equatable {
    public var month: String
    public var spendingTotal: Double
    public var incomeTotal: Double
    public var refundTotal: Double
    public var transferTotal: Double
    public var paymentTotal: Double
    public var feeTotal: Double
    public var netCashFlow: Double
    public var transactionCount: Int
    public var unresolvedCount: Int
    public var completenessStatus: CompletenessStatus

    public init(month: String, spendingTotal: Double, incomeTotal: Double, refundTotal: Double, transferTotal: Double, paymentTotal: Double, feeTotal: Double, netCashFlow: Double, transactionCount: Int, unresolvedCount: Int, completenessStatus: CompletenessStatus) {
        self.month = month; self.spendingTotal = spendingTotal; self.incomeTotal = incomeTotal
        self.refundTotal = refundTotal; self.transferTotal = transferTotal; self.paymentTotal = paymentTotal
        self.feeTotal = feeTotal; self.netCashFlow = netCashFlow; self.transactionCount = transactionCount
        self.unresolvedCount = unresolvedCount; self.completenessStatus = completenessStatus
    }
}

public struct AssetTrendRecord: Codable, Sendable, Equatable {
    public var month: String
    public var accountLabel: String
    public var endingBalance: Double
    public var priorMonthBalance: Double?
    public var monthlyChange: Double
    public var relatedSpendingTotal: Double
    public var maintainabilityFlag: MaintainabilityFlag

    public init(month: String, accountLabel: String, endingBalance: Double, priorMonthBalance: Double?, monthlyChange: Double, relatedSpendingTotal: Double, maintainabilityFlag: MaintainabilityFlag) {
        self.month = month; self.accountLabel = accountLabel; self.endingBalance = endingBalance
        self.priorMonthBalance = priorMonthBalance; self.monthlyChange = monthlyChange
        self.relatedSpendingTotal = relatedSpendingTotal; self.maintainabilityFlag = maintainabilityFlag
    }
}

public struct AnomalyRecord: Codable, Sendable, Equatable, Identifiable {
    public var id: String { anomalyId }
    public var anomalyId: String
    public var anomalyType: AnomalyType
    public var severity: Severity
    public var month: String
    public var relatedRecordIds: [String]
    public var summary: String
    public var suggestedAction: String
    public var status: AnomalyStatus
    public var createdAt: Date

    public init(anomalyId: String, anomalyType: AnomalyType, severity: Severity, month: String, relatedRecordIds: [String], summary: String, suggestedAction: String, status: AnomalyStatus = .open, createdAt: Date = Date()) {
        self.anomalyId = anomalyId; self.anomalyType = anomalyType; self.severity = severity
        self.month = month; self.relatedRecordIds = relatedRecordIds; self.summary = summary
        self.suggestedAction = suggestedAction; self.status = status; self.createdAt = createdAt
    }
}

public struct RunStateRecord: Codable, Sendable, Equatable, Identifiable {
    public var id: String { runId }
    public var runId: String
    public var startedAt: Date
    public var finishedAt: Date?
    public var status: RunStatus
    public var filesSeen: Int
    public var filesProcessed: Int
    public var transactionsCreated: Int
    public var reviewItemsCreated: Int
    public var anomaliesCreated: Int
    public var errorSummary: String?

    public init(runId: String, startedAt: Date = Date(), finishedAt: Date? = nil, status: RunStatus, filesSeen: Int, filesProcessed: Int, transactionsCreated: Int, reviewItemsCreated: Int, anomaliesCreated: Int, errorSummary: String? = nil) {
        self.runId = runId; self.startedAt = startedAt; self.finishedAt = finishedAt; self.status = status
        self.filesSeen = filesSeen; self.filesProcessed = filesProcessed; self.transactionsCreated = transactionsCreated
        self.reviewItemsCreated = reviewItemsCreated; self.anomaliesCreated = anomaliesCreated; self.errorSummary = errorSummary
    }
}

public struct DashboardInsight: Codable, Sendable, Equatable, Identifiable {
    public var id: String { insightId }
    public var insightId: String
    public var priority: InsightPriority
    public var title: String
    public var detail: String
    public var actionLabel: String
    public var actionRoute: String

    public init(insightId: String, priority: InsightPriority, title: String, detail: String, actionLabel: String, actionRoute: String) {
        self.insightId = insightId; self.priority = priority; self.title = title
        self.detail = detail; self.actionLabel = actionLabel; self.actionRoute = actionRoute
    }
}

public enum InsightPriority: String, Codable, Sendable, CaseIterable {
    case critical, high, medium, low, info
}
