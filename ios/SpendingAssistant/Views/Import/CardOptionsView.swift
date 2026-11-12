import SwiftUI
import SpendingDomain

struct CardOptionsView: View {
    @Binding var accountId: String
    var suggestedCurrency: String?
    var showsAccount = true
    @Binding var cardName: String
    @Binding var layout: ScreenshotLayout
    @Binding var month: String
    var body: some View {
        if showsAccount { AccountSelector(accountId: $accountId, suggestedName: cardName, suggestedCurrency: suggestedCurrency) }
        Menu("Choose card preset") {
            Button("Apple Card") { cardName = "Apple Card"; layout = .appleCard }
            Button("Capital One Venture X") { cardName = "Capital One Venture X"; layout = .capitalOne }
            Button("Other card") { cardName = ""; layout = .automatic }
        }
        Picker("Screenshot layout", selection: $layout) {
            ForEach(ScreenshotLayout.allCases, id: \.self) { Text($0.title).tag($0) }
        }
        StatementPeriodPicker(period: $month)
        Text("Use the selected account only for single-account image or PDF batches. Standalone AI JSON is mapped after import. Layout detection does not identify the exact card product. Choose a year, and a month if needed, for date headers without a year. Screen totals and reward percentages are ignored; account numbers are masked.")
            .font(.footnote).foregroundStyle(.secondary)
    }
}
