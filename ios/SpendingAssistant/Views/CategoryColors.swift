import SwiftUI
import SpendingDomain

enum CategoryColors {
    static func color(for category: SpendingCategory) -> Color {
        switch category {
        case .groceries: return Color(red: 0.20, green: 0.55, blue: 0.30)
        case .dining: return Color(red: 0.85, green: 0.40, blue: 0.20)
        case .utilities: return Color(red: 0.25, green: 0.45, blue: 0.75)
        case .transportation: return Color(red: 0.15, green: 0.55, blue: 0.70)
        case .rent: return Color(red: 0.45, green: 0.30, blue: 0.55)
        case .subscriptions: return Color(red: 0.70, green: 0.30, blue: 0.50)
        case .shopping: return Color(red: 0.80, green: 0.55, blue: 0.15)
        case .healthcare: return Color(red: 0.75, green: 0.25, blue: 0.35)
        case .transfer: return Color(red: 0.45, green: 0.50, blue: 0.55)
        case .income: return Color(red: 0.15, green: 0.60, blue: 0.45)
        case .fees: return Color(red: 0.55, green: 0.20, blue: 0.20)
        case .miscellaneous: return Color(red: 0.40, green: 0.45, blue: 0.40)
        case .uncategorized: return Color(red: 0.60, green: 0.60, blue: 0.60)
        }
    }
}
