import Foundation

public enum DemoSeed {
    public static func make(now: Date = Date()) -> (
        sources: [SourceDocumentRecord],
        transactions: [TransactionRecord],
        assets: [AssetSnapshotRecord],
        reviews: [ReviewItemRecord]
    ) {
        let sourceId = "demo_source_001"
        let source = SourceDocumentRecord(
            sourceDocumentId: sourceId,
            sourceType: .files,
            fileName: "demo-card-activity.png",
            mimeType: "image/png",
            localRelativePath: nil,
            createdTime: now,
            modifiedTime: now,
            processedAt: now,
            status: .processed,
            rawText: "Demo seed data"
        )

        let transactions = [
            TransactionRecord(
                transactionId: "txn_demo_1",
                sourceDocumentId: sourceId,
                observedMonth: month(now, offsetMonths: 0),
                transactionDate: day(now, offsetDays: -3),
                merchantRaw: "TRADER JOE'S",
                merchantNormalized: "Trader Joe's",
                amount: -54.23,
                transactionType: .expense,
                accountLabel: "Chase *1234",
                category: .groceries,
                categoryConfidence: 0.95,
                extractionConfidence: 0.9,
                validationStatus: .valid,
                reviewStatus: .none,
                evidenceText: "TRADER JOE'S 54.23",
                createdAt: now,
                updatedAt: now
            ),
            TransactionRecord(
                transactionId: "txn_demo_2",
                sourceDocumentId: sourceId,
                observedMonth: month(now, offsetMonths: 0),
                transactionDate: day(now, offsetDays: -2),
                merchantRaw: "BLUE BOTTLE OAKLAND",
                merchantNormalized: "Blue Bottle Oakland",
                amount: -6.75,
                transactionType: .expense,
                accountLabel: "Chase *1234",
                category: .miscellaneous,
                categoryConfidence: 0.45,
                extractionConfidence: 0.8,
                validationStatus: .needsReview,
                reviewStatus: .pending,
                evidenceText: "BLUE BOTTLE OAKLAND 6.75",
                createdAt: now,
                updatedAt: now
            ),
            TransactionRecord(
                transactionId: "txn_demo_3",
                sourceDocumentId: sourceId,
                observedMonth: month(now, offsetMonths: -1),
                transactionDate: day(now, offsetDays: -35),
                merchantRaw: "NETFLIX.COM",
                merchantNormalized: "Netflix.com",
                amount: -15.49,
                transactionType: .expense,
                accountLabel: "Chase *1234",
                category: .subscriptions,
                categoryConfidence: 0.94,
                extractionConfidence: 0.92,
                validationStatus: .valid,
                reviewStatus: .none,
                evidenceText: "NETFLIX.COM 15.49",
                createdAt: now,
                updatedAt: now
            ),
            TransactionRecord(
                transactionId: "txn_demo_4",
                sourceDocumentId: sourceId,
                observedMonth: month(now, offsetMonths: 0),
                transactionDate: day(now, offsetDays: -1),
                merchantRaw: "ACME PAYROLL",
                merchantNormalized: "Acme Payroll",
                amount: 3200,
                transactionType: .income,
                accountLabel: "Checking *9876",
                category: .income,
                categoryConfidence: 0.98,
                extractionConfidence: 0.9,
                validationStatus: .valid,
                reviewStatus: .none,
                evidenceText: "ACME PAYROLL 3200.00",
                createdAt: now,
                updatedAt: now
            )
        ]

        let assets = [
            AssetSnapshotRecord(
                assetSnapshotId: "asset_demo_1",
                sourceDocumentId: sourceId,
                observedMonth: month(now, offsetMonths: 0),
                observedDate: day(now, offsetDays: 0),
                accountLabel: "Checking *9876",
                balance: 4820.55,
                balanceType: .checking,
                confidence: 0.88,
                evidenceText: "Checking balance 4820.55",
                createdAt: now
            )
        ]

        let reviews = [
            ReviewItemRecord(
                reviewItemId: "review_demo_1",
                targetType: .transaction,
                targetId: "txn_demo_2",
                issueType: .unclearCategory,
                severity: .medium,
                question: "Is \"Blue Bottle Oakland\" best categorized as miscellaneous?",
                suggestedOptions: ["dining", "groceries", "miscellaneous"],
                status: .pending,
                createdAt: now
            )
        ]

        return ([source], transactions, assets, reviews)
    }

    private static func month(_ date: Date, offsetMonths: Int) -> String {
        var comps = Calendar(identifier: .gregorian).dateComponents([.year, .month], from: date)
        comps.month = (comps.month ?? 1) + offsetMonths
        let shifted = Calendar(identifier: .gregorian).date(from: comps) ?? date
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM"
        return formatter.string(from: shifted)
    }

    private static func day(_ date: Date, offsetDays: Int) -> String {
        let shifted = Calendar(identifier: .gregorian).date(byAdding: .day, value: offsetDays, to: date) ?? date
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: shifted)
    }
}
