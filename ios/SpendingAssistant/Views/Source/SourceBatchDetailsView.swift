import SwiftUI
import SwiftData
import SpendingDomain

struct SourceBatchDetailsView: View {
    @Environment(ImportCoordinator.self) private var imports
    @Query(sort: \SDSourceDocument.createdTime, order: .reverse) private var sources: [SDSourceDocument]
    @State private var selected: Set<String> = []
    @State private var changePeriod = false
    @State private var changeAccount = false
    @State private var period = ""
    @State private var account = ""
    @State private var search = ""
    @State private var confirm = false
    @State private var message: String?

    var body: some View {
        let eligible = sources.filter {
            $0.mimeType.hasPrefix("image/") || (!changePeriod && $0.mimeType == "application/pdf")
        }
        let visible = eligible.filter {
            search.isEmpty || ($0.fileName + " " + ($0.cardName ?? "")).localizedCaseInsensitiveContains(search)
        }
        let selection = selected.intersection(eligible.map(\.sourceDocumentId))
        List {
            Section("Details to apply") {
                Toggle("Set year or month", isOn: $changePeriod)
                if changePeriod {
                    StatementPeriodPicker(period: $period)
                    Text("Applies to screenshot dates missing a year. Printed and manually edited dates stay unchanged.").font(.footnote)
                }
                Toggle("Set account", isOn: $changeAccount)
                if changeAccount {
                    AccountSelector(accountId: $account, allowsUnmapped: false)
                }
            }
            Section("\(selection.count) sources selected") {
                if !visible.isEmpty {
                    Button("Select all shown") { selected.formUnion(visible.map(\.sourceDocumentId)) }
                    if !selection.isEmpty { Button("Clear selection") { selected = [] } }
                }
                ForEach(visible, id: \.sourceDocumentId) { source in
                    Button {
                        if !selected.insert(source.sourceDocumentId).inserted { selected.remove(source.sourceDocumentId) }
                    } label: {
                        Label {
                            VStack(alignment: .leading) {
                                Text(source.fileName)
                                Text([source.cardName ?? "Unknown account", source.observedMonthHint ?? "No year set",
                                      source.statusRaw.displayTitle].joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: selection.contains(source.sourceDocumentId) ? "checkmark.circle.fill" : "circle")
                        }
                    }.accessibilityAddTraits(selection.contains(source.sourceDocumentId) ? .isSelected : [])
                }
            }
            if let message { Text(message).font(.footnote) }
            Button("Apply to \(selection.count) sources") { confirm = true }
                .disabled(selection.isEmpty || (!changePeriod && !changeAccount)
                    || (changePeriod && !Normalizer.isValidStatementDateHint(period))
                    || (changeAccount && account.isEmpty) || imports.isBusy)
        }
        .navigationTitle("Edit multiple sources")
        .searchable(text: $search, prompt: "Source or account")
        .onChange(of: changePeriod) { _, enabled in
            if enabled { selected.formIntersection(sources.filter { $0.mimeType.hasPrefix("image/") }.map(\.sourceDocumentId)) }
        }
        .alert("Update \(selection.count) sources?", isPresented: $confirm) {
            Button("Apply details") { apply(selection) }.disabled(imports.isBusy)
            Button("Cancel", role: .cancel) {}
        } message: { Text("Only the enabled details will change. Screenshots with all required details can finish importing.") }
    }

    private func apply(_ selection: Set<String>) {
        let period = changePeriod ? period : nil
        let account = changeAccount ? account : nil
        Task {
            do {
                let results = try await imports.updateSources(ids: selection, period: period, account: nil, accountId: account)
                let imported = results.count(where: { $0.status == .imported })
                let waiting = results.count(where: { $0.status == .needsDetails })
                let failed = results.count(where: { $0.status == .failed })
                message = "Updated \(selection.count) sources. \(imported) imported, \(waiting) still need details, \(failed) could not finish."
                selected = []
            } catch { message = PrivacyRedactor.safeErrorDetail(error) }
        }
    }
}
