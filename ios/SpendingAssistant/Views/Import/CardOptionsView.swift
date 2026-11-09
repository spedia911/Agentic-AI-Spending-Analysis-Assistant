import SwiftUI
import SpendingDomain

struct CardOptionsView: View {
    @Binding var cardName: String
    @Binding var layout: ScreenshotLayout
    @Binding var month: String
    var body: some View {
        Menu("Choose card preset") {
            Button("Apple Card") { cardName = "Apple Card"; layout = .appleCard }
            Button("Capital One Venture X") { cardName = "Capital One Venture X"; layout = .capitalOne }
            Button("Other card") { cardName = ""; layout = .automatic }
        }
        TextField("Account name (optional)", text: $cardName).accessibilityIdentifier("cardName")
        Picker("Screenshot layout", selection: $layout) {
            ForEach(ScreenshotLayout.allCases, id: \.self) { Text($0.title).tag($0) }
        }
        StatementPeriodPicker(period: $month)
        Text("Import one card per batch. Layout detection does not identify the exact card product. Choose a year, and a month if needed, for date headers without a year. Screen totals and reward percentages are ignored; account numbers are masked.")
            .font(.footnote).foregroundStyle(.secondary)
    }
}
