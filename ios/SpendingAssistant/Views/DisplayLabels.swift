import Foundation
import SpendingDomain

extension String {
    var displayTitle: String {
        let words = replacingOccurrences(of: "_", with: " ")
        return words.prefix(1).uppercased() + words.dropFirst()
    }
}


enum MoneyDisplay {
    static func format(_ amount: Double, currency: String?) -> String {
        guard let currency, Eligibility.validCurrency(currency) else { return amount.formatted() + " (currency unmapped)" }
        return amount.formatted(.currency(code: currency))
    }
}
