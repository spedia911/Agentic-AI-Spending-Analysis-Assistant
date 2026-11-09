import SwiftUI
import SwiftData
import SpendingDomain

struct ScreenshotDetailsView: View {
    @Environment(ImportCoordinator.self) private var imports
    @Environment(\.dismiss) private var dismiss
    @Query private var sources: [SDSourceDocument]
    @Query private var transactions: [SDTransaction]
    @Query private var assets: [SDAssetSnapshot]
    let request: ScreenshotImportDetails
    @State private var month: String
    @State private var account: String
    @State private var fallbackDate = Date()
    @State private var useSharedDate = false
    @State private var reusePeriod = false
    @State private var reuseAccount = false
    @State private var reviewDatesIndividually = false
    @State private var message: String?
    @State private var saving = false

    init(request: ScreenshotImportDetails) {
        self.request = request
        _month = State(initialValue: request.source.observedMonthHint ?? "")
        _account = State(initialValue: request.source.cardName ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(request.source.fileName)
                    Text("Add the missing details before importing. You can also finish this screenshot from Sources later.").font(.footnote)
                }
                if request.needsYear {
                    Section("Missing year") {
                        StatementPeriodPicker(period: $month)
                        Text("The month and day shown on each row are kept.").font(.footnote)
                    }
                }
                if request.needsDate {
                    Section("Unreadable dates") {
                        Toggle("Use one date for all unreadable rows", isOn: $useSharedDate)
                            .onChange(of: useSharedDate) { _, shared in if shared { reviewDatesIndividually = false } }
                        if useSharedDate { DatePicker("Transaction date", selection: $fallbackDate, displayedComponents: .date) }
                        Toggle("Review those dates individually", isOn: $reviewDatesIndividually)
                            .onChange(of: reviewDatesIndividually) { _, individually in if individually { useSharedDate = false } }
                    }
                }
                if request.needsAccount {
                    Section("Missing account") {
                        if !knownAccounts.isEmpty {
                            Menu("Choose a known account") {
                                ForEach(knownAccounts, id: \.self) { label in Button(label) { account = label } }
                            }
                        }
                        TextField("Account name", text: $account).accessibilityIdentifier("requiredAccount")
                    }
                }
                if (request.needsYear && imports.hasRemainingDates(in: request))
                    || (request.needsAccount && imports.hasRemainingAccounts(in: request)) {
                    Section("Use these details for this batch?") {
                        if request.needsYear && imports.hasRemainingDates(in: request) {
                            Toggle("Reuse year and month", isOn: $reusePeriod)
                        }
                        if request.needsAccount && imports.hasRemainingAccounts(in: request) {
                            Toggle("Reuse account", isOn: $reuseAccount)
                        }
                        Text("Only fills missing details in the remaining screenshots in this batch.").font(.footnote)
                    }
                }
                if let message { Text(message).foregroundStyle(.red) }
                Button("Import transactions") { finish() }.disabled(!canFinish)
            }
            .disabled(saving)
            .navigationTitle("Screenshot details")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Later") { dismiss() }.disabled(saving) }
            }
            .interactiveDismissDisabled(saving)
        }
    }

    private var knownAccounts: [String] {
        let labels = sources.compactMap(\.cardName) + transactions.map(\.accountLabel) + assets.map(\.accountLabel)
        var seen: Set<String> = ["unknown account"]
        return labels.map { PrivacyRedactor.maskAccountLabel($0) }
            .filter { seen.insert($0.lowercased()).inserted }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    private var canFinish: Bool {
        (!request.needsYear || Normalizer.isValidStatementDateHint(month.trimmingCharacters(in: .whitespacesAndNewlines)))
            && (!request.needsAccount || PrivacyRedactor.maskAccountLabel(account) != "Unknown account")
            && (!request.needsDate || reviewDatesIndividually || useSharedDate)
    }

    private func dateString(_ date: Date) -> String {
        let parts = Calendar(identifier: .gregorian).dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    private func finish() {
        saving = true
        Task {
            let result = await imports.finishDetails(request, account: account, month: month,
                fallbackDate: request.needsDate && useSharedDate ? dateString(fallbackDate) : nil, reusePeriod: reusePeriod, reuseAccount: reuseAccount)
            saving = false
            if result.status == .imported || result.status == .alreadyImported { dismiss() }
            else { message = result.error ?? "The screenshot still needs details." }
        }
    }
}
