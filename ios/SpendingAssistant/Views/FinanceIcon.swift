import SwiftUI
import UIKit

/// The supplied artwork is a transparent 4 × 3 sprite sheet. Slice it at runtime
/// so the original remains intact, and let template rendering adapt to tint/dark mode.
enum FinanceIcon: Int, CaseIterable {
    case dashboard, importReceipt, cashFlow, wallet
    case bank, trend, review, categories
    case profile, history, transfer, report

    var image: Image { Image(uiImage: Self.images[self] ?? UIImage()) }

    private static let images: [FinanceIcon: UIImage] = {
        guard let sheet = UIImage(named: "FinanceIconSheet")?.cgImage else { return [:] }
        let width = CGFloat(sheet.width) / 4
        let height = CGFloat(sheet.height) / 3
        return Dictionary(uniqueKeysWithValues: allCases.compactMap { icon in
            let rect = CGRect(x: CGFloat(icon.rawValue % 4) * width,
                              y: CGFloat(icon.rawValue / 4) * height,
                              width: width, height: height)
            guard let cropped = sheet.cropping(to: rect) else { return nil }
            let glyph = UIImage(cgImage: cropped)
            let format = UIGraphicsImageRendererFormat()
            format.scale = 3
            let rendered = UIGraphicsImageRenderer(size: CGSize(width: 28, height: 28), format: format).image { _ in
                glyph.draw(in: CGRect(x: 0, y: 0, width: 28, height: 28))
            }
            return (icon, rendered.withRenderingMode(.alwaysTemplate))
        })
    }()
}
