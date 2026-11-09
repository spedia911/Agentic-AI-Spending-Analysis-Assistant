import SwiftUI
import SwiftData
import SpendingDomain

struct BatchAnomalyReviewView: View {
    @Query private var anomalies: [SDAnomaly]
    @Query(sort: \SDSourceDocument.createdTime, order: .reverse) private var sources: [SDSourceDocument]
    @Query private var transactions: [SDTransaction]

    var body: some View {
        let records = transactions.map { $0.toRecord() }
        let pairs = DuplicateBatch.suggestedPairs(transactions: records)
        let chargeGroups = DuplicateChargeGroup.from(
            anomalies: anomalies.map { $0.toRecord() },
            transactions: records
        )
        let sameImport = chargeGroups.filter(\.sameSource)
        let crossImportCharges = chargeGroups.filter { !$0.sameSource }
        let byId = Dictionary(uniqueKeysWithValues: sources.map { ($0.sourceDocumentId, $0) })

        List {
            Section {
                Text(introCopy(pairs: pairs.count, sameImport: sameImport.count))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if !sameImport.isEmpty {
                Section("Same-import duplicate charges") {
                    Text("These look alike inside one import. Compare the dates and decide whether both charges are real.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    ForEach(sameImport) { group in
                        NavigationLink {
                            DuplicateTransactionCompareView(anomalyId: group.anomalyId)
                        } label: {
                            sameImportLabel(group, source: group.sourceDocumentId.flatMap { byId[$0] })
                        }
                    }
                }
            }

            Section("Duplicate import pairs") {
                if pairs.isEmpty {
                    Text(sameImport.isEmpty
                         ? "No exact cross-source duplicates found. Pairs appear when two imports contain the same merchant, date, amount, and type once each."
                         : "No overlapping imports. Use the same-import list above for duplicates inside one screenshot.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(pairs) { pair in
                        NavigationLink {
                            DuplicatePairDetailView(keepSourceId: pair.keepSourceId, removeSourceId: pair.removeSourceId)
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(sourceTitle(byId[pair.keepSourceId]))
                                    .font(.headline)
                                Text("Keep this import")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                Text(sourceTitle(byId[pair.removeSourceId]))
                                    .font(.subheadline)
                                Text("Remove \(pair.matchCount) matching copies from this import")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(sourceMeta(byId[pair.keepSourceId], byId[pair.removeSourceId], matchCount: pair.matchCount))
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
            }

            if !crossImportCharges.isEmpty {
                Section("Other duplicate alerts") {
                    ForEach(crossImportCharges) { group in
                        NavigationLink {
                            DuplicateTransactionCompareView(anomalyId: group.anomalyId)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(group.summary).font(.subheadline)
                                Text(listedDates(group.dates))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }

            Section("Other anomaly categories") {
                ForEach(AnomalyType.allCases.filter { $0 != .duplicateCharge }, id: \.self) { type in
                    let count = anomalies.count(where: {
                        $0.anomalyTypeRaw == type.rawValue && $0.statusRaw == AnomalyStatus.open.rawValue
                    })
                    NavigationLink {
                        AnomalyGroupView(type: type)
                    } label: {
                        LabeledContent(type.rawValue.displayTitle, value: "\(count) open")
                    }
                }
            }
        }
        .navigationTitle("Anomaly review")
    }

    private func introCopy(pairs: Int, sameImport: Int) -> String {
        if sameImport > 0 && pairs == 0 {
            return "Open a same-import alert to compare the matching charges by date. Cross-source import pairs appear separately when two screenshots overlap."
        }
        if sameImport > 0 {
            return "Start with same-import charges when both rows came from one screenshot. Use import pairs when two imports share the same charges."
        }
        return "Pick an import pair that shares the same charges, confirm the matches, then remove the copies in one step. Other anomaly types can be closed by month or year without deleting rows."
    }

    private func sameImportLabel(_ group: DuplicateChargeGroup, source: SDSourceDocument?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(group.merchant).font(.headline)
            if !group.amountLabel.isEmpty {
                Text(group.amountLabel).font(.subheadline)
            } else {
                Text(group.summary).font(.subheadline)
            }
            Text(listedDates(group.dates))
                .font(.subheadline.weight(.semibold))
            Text([
                source.map { "Import: \($0.fileName)" },
                "\(group.relatedRecordIds.count) transactions"
            ].compactMap { $0 }.joined(separator: " · "))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

    /// Always list every related transaction date so same-day vs different-day is obvious.
    private func listedDates(_ dates: [String]) -> String {
        let ordered = dates.sorted()
        guard !ordered.isEmpty else { return "Dates unavailable" }
        if ordered.count == 1 { return "Date: \(ordered[0]) (only one date found)" }
        return "Dates: " + ordered.enumerated().map { "\($0.offset + 1) \($0.element)" }.joined(separator: " · ")
    }

    private func sourceTitle(_ source: SDSourceDocument?) -> String {
        guard let source else { return "Unknown import" }
        if let card = source.cardName, !card.isEmpty {
            return "\(source.fileName) · \(card)"
        }
        return source.fileName
    }

    private func sourceMeta(_ keep: SDSourceDocument?, _ remove: SDSourceDocument?, matchCount: Int) -> String {
        let keepDate = keep?.createdTime.formatted(.dateTime.month().day().year()) ?? "?"
        let removeDate = remove?.createdTime.formatted(.dateTime.month().day().year()) ?? "?"
        return "\(matchCount) matches · imported \(keepDate) vs \(removeDate)"
    }
}

private struct AnomalyGroupView: View {
    @Environment(ImportCoordinator.self) private var imports
    @Query private var anomalies: [SDAnomaly]
    let type: AnomalyType
    @State private var year = ""
    @State private var month = ""
    @State private var proposed: Set<String> = []
    @State private var confirm = false
    @State private var error: String?

    var body: some View {
        let open = anomalies.filter { $0.anomalyTypeRaw == type.rawValue && $0.statusRaw == AnomalyStatus.open.rawValue }
        let years = Array(Set(open.compactMap { yearToken($0.month) })).sorted(by: >)
        let months = Array(Set(open.map(\.month).filter { !$0.isEmpty && $0 != "unknown" })).sorted(by: >)
        let filtered = open.filter { row in
            if !year.isEmpty, yearToken(row.month) != year { return false }
            if !month.isEmpty, row.month != month { return false }
            return true
        }.sorted { $0.month > $1.month }

        List {
            Section("Filter") {
                Picker("Year", selection: $year) {
                    Text("All years").tag("")
                    ForEach(years, id: \.self) { Text($0).tag($0) }
                }
                Picker("Month", selection: $month) {
                    Text("All months").tag("")
                    ForEach(months.filter { year.isEmpty || $0.hasPrefix(year) }, id: \.self) { Text($0).tag($0) }
                }
                Text("Mark a filtered group as reviewed when you’ve checked the underlying transactions. This closes alerts only — it does not delete rows.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if filtered.isEmpty {
                Text("No open anomalies in this group.").foregroundStyle(.secondary)
            }
            if let error { Text(error).foregroundStyle(.red) }

            Section("\(filtered.count) anomalies") {
                ForEach(filtered, id: \.anomalyId) { row in
                    VStack(alignment: .leading, spacing: 5) {
                        Text(row.summary)
                        Text("\(row.month) · \(row.suggestedAction)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if !filtered.isEmpty {
                Button("Mark all \(filtered.count) as reviewed") {
                    proposed = Set(filtered.map(\.anomalyId))
                    confirm = true
                }
                .disabled(imports.isBusy)
            }
        }
        .navigationTitle(type.rawValue.displayTitle)
        .onChange(of: year) { _, value in
            if !month.isEmpty, !month.hasPrefix(value), !value.isEmpty { month = "" }
        }
        .alert("Mark these anomalies as reviewed?", isPresented: $confirm) {
            Button("Mark reviewed") {
                do { try imports.service.store.markAnomalyGroupReviewed(type, ids: proposed) }
                catch { self.error = PrivacyRedactor.safeErrorDetail(error) }
            }
            .disabled(imports.isBusy)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Closes these alerts without changing transactions or balances.")
        }
    }

    private func yearToken(_ month: String) -> String? {
        guard month.count >= 4, month.prefix(4).allSatisfy(\.isNumber) else { return nil }
        return String(month.prefix(4))
    }
}

/// Side-by-side comparison for duplicate charges found in the same import (or nearby dates).
struct DuplicateTransactionCompareView: View {
    @Environment(ImportCoordinator.self) private var imports
    @Query private var anomalies: [SDAnomaly]
    @Query private var transactions: [SDTransaction]
    @Query private var sources: [SDSourceDocument]

    let anomalyId: String
    @State private var year = ""
    @State private var month = ""
    @State private var deleteId: String?
    @State private var confirmBothReal = false
    @State private var message: String?

    private var anomaly: SDAnomaly? {
        anomalies.first { $0.anomalyId == anomalyId }
    }

    private var related: [SDTransaction] {
        guard let anomaly else { return [] }
        let ids = Set(anomaly.toRecord().relatedRecordIds)
        return transactions
            .filter { ids.contains($0.transactionId) && $0.validationStatusRaw != ValidationStatus.rejected.rawValue }
            .sorted { ($0.transactionDate, $0.transactionId) < ($1.transactionDate, $1.transactionId) }
    }

    private var filtered: [SDTransaction] {
        related.filter { row in
            if !year.isEmpty, !row.transactionDate.hasPrefix(year) { return false }
            if !month.isEmpty, !row.transactionDate.hasPrefix(month) { return false }
            return true
        }
    }

    var body: some View {
        let years = Array(Set(related.map { String($0.transactionDate.prefix(4)) }.filter { $0.count == 4 })).sorted(by: >)
        let months = Array(Set(related.map { String($0.transactionDate.prefix(7)) }.filter { $0.count == 7 })).sorted(by: >)
        let sourceIds = Set(related.map(\.sourceDocumentId))
        let sameSource = sourceIds.count <= 1
        let source = sourceIds.first.flatMap { id in sources.first { $0.sourceDocumentId == id } }

        List {
            Section {
                Text(sameSource
                     ? "These charges came from the same import. Compare dates and amounts, then keep both or remove a copy."
                     : "Compare the related charges by date. Remove a copy only when you are sure it is not a real charge.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                if let anomaly {
                    Text(anomaly.summary)
                    if let source {
                        LabeledContent("Import", value: source.fileName)
                    }
                    LabeledContent("Month", value: anomaly.month)
                }
                if related.count >= 2 {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Transaction dates").font(.caption).foregroundStyle(.secondary)
                        ForEach(Array(related.enumerated()), id: \.element.transactionId) { index, tx in
                            Text("\(index + 1). \(tx.transactionDate) · \(tx.amount.formatted(.currency(code: "USD")))")
                                .font(.subheadline.weight(.semibold))
                        }
                        if Set(related.map(\.transactionDate)).count == 1 {
                            Text("Both rows share this date — compare amounts/accounts carefully.")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("These rows have different dates.")
                                .font(.caption2)
                                .foregroundStyle(.orange)
                        }
                    }
                }
            }

            Section("Narrow by date") {
                Picker("Year", selection: $year) {
                    Text("All years").tag("")
                    ForEach(years, id: \.self) { Text($0).tag($0) }
                }
                Picker("Month", selection: $month) {
                    Text("All months").tag("")
                    ForEach(months.filter { year.isEmpty || $0.hasPrefix(year) }, id: \.self) { Text($0).tag($0) }
                }
                if !year.isEmpty || !month.isEmpty {
                    Button("Clear date filters") {
                        year = ""
                        month = ""
                    }
                }
            }

            if let message { Text(message).font(.footnote) }

            Section("\(filtered.count) transactions by date") {
                if filtered.isEmpty {
                    Text(related.isEmpty ? "Related transactions are no longer available." : "No transactions match the date filters.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(filtered, id: \.transactionId) { tx in
                        VStack(alignment: .leading, spacing: 6) {
                            NavigationLink {
                                TransactionDetailView(transactionId: tx.transactionId)
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(tx.transactionDate).font(.headline)
                                    Text("\(tx.merchantNormalized) · \(tx.amount.formatted(.currency(code: "USD")))")
                                    Text("\(tx.accountLabel) · \(tx.transactionTypeRaw.displayTitle)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    if !sameSource {
                                        Text("Import id: \(tx.sourceDocumentId)")
                                            .font(.caption2)
                                            .foregroundStyle(.tertiary)
                                    }
                                }
                            }
                            Button("Remove this copy", role: .destructive) {
                                deleteId = tx.transactionId
                            }
                            .disabled(imports.isBusy || related.count < 2)
                        }
                        .padding(.vertical, 2)
                    }
                }
            }

            if anomaly?.statusRaw == AnomalyStatus.open.rawValue {
                Section {
                    Button("Both charges are real — close alert") {
                        confirmBothReal = true
                    }
                    .disabled(imports.isBusy || related.isEmpty)
                }
            }
        }
        .navigationTitle("Compare charges")
        .onChange(of: year) { _, value in
            if !month.isEmpty, !month.hasPrefix(value), !value.isEmpty { month = "" }
        }
        .alert("Remove this copy?", isPresented: Binding(
            get: { deleteId != nil },
            set: { if !$0 { deleteId = nil } }
        )) {
            Button("Remove copy", role: .destructive) {
                guard let deleteId else { return }
                do {
                    try imports.service.store.deleteTransactions(ids: [deleteId])
                    try imports.service.store.resolveAnomalies(ids: [anomalyId], type: .duplicateCharge)
                    message = "Removed the copy and closed this duplicate alert."
                    self.deleteId = nil
                } catch {
                    message = PrivacyRedactor.safeErrorDetail(error)
                    self.deleteId = nil
                }
            }
            Button("Cancel", role: .cancel) { deleteId = nil }
        } message: {
            Text("Deletes only the selected transaction. Remaining matching charges stay.")
        }
        .alert("Keep both charges?", isPresented: $confirmBothReal) {
            Button("Both are real") {
                do {
                    try imports.service.store.resolveAnomalies(ids: [anomalyId], type: .duplicateCharge)
                    message = "Closed the duplicate alert. Both transactions remain."
                } catch {
                    message = PrivacyRedactor.safeErrorDetail(error)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Closes this alert without deleting either transaction.")
        }
    }
}

private struct DuplicatePairDetailView: View {
    @Environment(ImportCoordinator.self) private var imports
    @Query private var sources: [SDSourceDocument]
    @Query private var transactions: [SDTransaction]

    @State private var keepSourceId: String
    @State private var removeSourceId: String
    @State private var filter = DuplicateMatchFilter()
    @State private var selected: Set<String> = []
    @State private var proposed: [DuplicateBatchMatch] = []
    @State private var confirm = false
    @State private var message: String?
    @State private var didSelectAll = false

    init(keepSourceId: String, removeSourceId: String) {
        _keepSourceId = State(initialValue: keepSourceId)
        _removeSourceId = State(initialValue: removeSourceId)
    }

    var body: some View {
        let records = transactions.map { $0.toRecord() }
        let allMatches = DuplicateBatch.matches(keeping: keepSourceId, removing: removeSourceId, transactions: records)
        let matches = DuplicateBatch.matches(keeping: keepSourceId, removing: removeSourceId, transactions: records, filter: filter)
        let selection = matches.filter { selected.contains($0.id) }
        let years = Array(Set(allMatches.map { String($0.keep.transactionDate.prefix(4)) }.filter { $0.count == 4 })).sorted(by: >)
        let months = Array(Set(allMatches.map { String($0.keep.transactionDate.prefix(7)) }.filter { $0.count == 7 })).sorted(by: >)
        let accounts = Array(Set(allMatches.flatMap { [$0.keep.accountLabel, $0.remove.accountLabel] })).sorted {
            $0.localizedStandardCompare($1) == .orderedAscending
        }
        let keepSource = sources.first { $0.sourceDocumentId == keepSourceId }
        let removeSource = sources.first { $0.sourceDocumentId == removeSourceId }

        List {
            Section("Imports") {
                labeledSource("Keep", source: keepSource)
                labeledSource("Remove copies from", source: removeSource)
                Button("Swap keep / remove") {
                    swap(&keepSourceId, &removeSourceId)
                    selected = []
                    filter = DuplicateMatchFilter()
                    didSelectAll = false
                    message = nil
                }
                Text("Exact matches share merchant, date, amount, and type once in each import. Ambiguous repeats stay for individual review.")
                    .font(.footnote)
            }

            Section("Narrow this pair") {
                Picker("Year", selection: $filter.year) {
                    Text("All years").tag("")
                    ForEach(years, id: \.self) { Text($0).tag($0) }
                }
                Picker("Month", selection: $filter.month) {
                    Text("All months").tag("")
                    ForEach(months.filter { filter.year.isEmpty || $0.hasPrefix(filter.year) }, id: \.self) { Text($0).tag($0) }
                }
                Picker("Account", selection: $filter.account) {
                    Text("All accounts").tag("")
                    ForEach(accounts, id: \.self) { Text($0).tag($0) }
                }
                if filter.isActive {
                    Button("Clear filters") {
                        filter = DuplicateMatchFilter()
                        selected = Set(matches.map(\.id))
                    }
                }
            }

            if let message { Text(message).font(.footnote) }

            Section("\(matches.count) matching charges") {
                if matches.isEmpty {
                    Text(allMatches.isEmpty ? "No exact matches for this pair." : "No matches for the current filters.")
                        .foregroundStyle(.secondary)
                } else {
                    Button(selection.count == matches.count ? "Clear selection" : "Select all \(matches.count)") {
                        selected = selection.count == matches.count ? [] : Set(matches.map(\.id))
                    }
                    ForEach(matches) { match in
                        Button {
                            if !selected.insert(match.id).inserted { selected.remove(match.id) }
                        } label: {
                            HStack(alignment: .top) {
                                Image(systemName: selected.contains(match.id) ? "checkmark.circle.fill" : "circle")
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(match.keep.merchantNormalized).font(.headline)
                                    Text("\(match.keep.transactionDate) · \(match.keep.amount.formatted(.currency(code: "USD")))")
                                    Text("Keep account: \(match.keep.accountLabel)")
                                    Text("Copy account: \(match.remove.accountLabel)")
                                }
                                .font(.caption)
                            }
                            .foregroundStyle(.primary)
                        }
                        .accessibilityAddTraits(selected.contains(match.id) ? .isSelected : [])
                    }
                    Button("Remove \(selection.count) duplicate copies", role: .destructive) {
                        proposed = selection
                        confirm = true
                    }
                    .disabled(selection.isEmpty || imports.isBusy)
                }
            }
        }
        .navigationTitle("Duplicate pair")
        .onAppear {
            if !didSelectAll {
                selected = Set(matches.map(\.id))
                didSelectAll = true
            }
        }
        .onChange(of: filter) { _, _ in
            selected = Set(DuplicateBatch.matches(
                keeping: keepSourceId,
                removing: removeSourceId,
                transactions: records,
                filter: filter
            ).map(\.id))
        }
        .onChange(of: filter.year) { _, value in
            if !filter.month.isEmpty, !filter.month.hasPrefix(value), !value.isEmpty {
                filter.month = ""
            }
        }
        .alert("Remove \(proposed.count) duplicate copies?", isPresented: $confirm) {
            Button("Remove copies", role: .destructive) {
                do {
                    try imports.service.store.removeConfirmedDuplicates(
                        keeping: keepSourceId,
                        removing: removeSourceId,
                        matches: proposed
                    )
                    message = "Removed \(proposed.count) copies from \(removeSource?.fileName ?? "the copy import")."
                    selected = []
                } catch {
                    message = PrivacyRedactor.safeErrorDetail(error)
                }
            }
            .disabled(imports.isBusy)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Deletes only the selected rows in \(removeSource?.fileName ?? "the copy import"). The keep import and its matching rows stay.")
        }
    }

    @ViewBuilder
    private func labeledSource(_ title: String, source: SDSourceDocument?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            if let source {
                Text(source.fileName).font(.headline)
                Text([source.cardName, source.sourceTypeRaw.displayTitle, source.createdTime.formatted(.dateTime.month().day().year())]
                    .compactMap { $0 }
                    .joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                NavigationLink("Open import details") { SourceDetailView(source: source) }
            } else {
                Text("Import unavailable").foregroundStyle(.secondary)
            }
        }
    }
}
