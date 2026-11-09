import Foundation

extension String {
    var displayTitle: String {
        let words = replacingOccurrences(of: "_", with: " ")
        return words.prefix(1).uppercased() + words.dropFirst()
    }
}
