import SwiftUI
import SpendingDomain

struct StatementPeriodPicker: View {
    @Binding var period: String

    private var year: Int { Int(period.prefix(4)) ?? 0 }
    private var month: Int { period.count == 7 ? Int(period.suffix(2)) ?? 0 : 0 }

    var body: some View {
        let latest = Calendar(identifier: .gregorian).component(.year, from: .now) + 1
        let years = (1900...max(latest, year)).reversed()
        Picker("Year", selection: Binding(get: { year }, set: { set(year: $0, month: month) })) {
            Text("Choose year").tag(0)
            ForEach(years, id: \.self) { Text(String($0)).tag($0) }
        }
        .pickerStyle(.navigationLink)
        .accessibilityIdentifier("statementYearPicker")
        Picker("Statement month", selection: Binding(get: { month }, set: { set(year: year, month: $0) })) {
            Text("Use year only").tag(0)
            ForEach(Array(Calendar(identifier: .gregorian).monthSymbols.enumerated()), id: \.offset) { entry in
                Text(entry.element).tag(entry.offset + 1)
            }
        }
        .pickerStyle(.menu)
        .disabled(year == 0)
        .accessibilityIdentifier("statementMonthPicker")
    }

    private func set(year: Int, month: Int) {
        period = year == 0 ? "" : month == 0 ? String(year) : String(format: "%04d-%02d", year, month)
    }
}
