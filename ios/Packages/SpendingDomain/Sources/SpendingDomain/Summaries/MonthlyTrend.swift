import Foundation

public struct MonthlyPoint: Equatable, Sendable {
    public let month: String
    public let value: Double

    public init(month: String, value: Double) {
        self.month = month
        self.value = value
    }
}

public enum MonthlyTrend {
    public static func offset(_ month: String, by months: Int) -> String? {
        guard let index = monthIndex(month), index + months >= 12 else { return nil }
        return label(index + months)
    }

    public static func yearOverYear(_ series: [MonthlyPoint], month: String) -> (amount: Double, fraction: Double?)? {
        guard let priorMonth = offset(month, by: -12),
              let current = series.first(where: { $0.month == month })?.value,
              let prior = series.first(where: { $0.month == priorMonth })?.value else { return nil }
        let change = current - prior
        return (change, prior == 0 ? nil : change / abs(prior))
    }

    /// Least squares on calendar month indices. Missing months never enter the fit as zeroes.
    public static func regression(_ series: [MonthlyPoint], futureMonths: Int = 0) -> [MonthlyPoint] {
        let samples = series.compactMap { point -> (Int, Double)? in
            guard let index = monthIndex(point.month), point.value.isFinite else { return nil }
            return (index, point.value)
        }
        guard let start = samples.map(\.0).min(), let end = samples.map(\.0).max(),
              Set(samples.map(\.0)).count >= (futureMonths > 0 ? 3 : 2) else { return [] }
        let xMean = samples.reduce(0.0) { $0 + Double($1.0 - start) } / Double(samples.count)
        let yMean = samples.reduce(0.0) { $0 + $1.1 } / Double(samples.count)
        let variance = samples.reduce(0.0) { $0 + pow(Double($1.0 - start) - xMean, 2) }
        let covariance = samples.reduce(0.0) { $0 + (Double($1.0 - start) - xMean) * ($1.1 - yMean) }
        let slope = covariance / variance
        let indices = futureMonths > 0 ? [end, end + futureMonths] : [start, end]
        return indices.map { MonthlyPoint(month: label($0), value: yMean + slope * (Double($0 - start) - xMean)) }
    }

    private static func monthIndex(_ month: String) -> Int? {
        guard month.count == 7, month.dropFirst(4).first == "-",
              let year = Int(month.prefix(4)), year > 0, let number = Int(month.suffix(2)), (1...12).contains(number) else { return nil }
        return year * 12 + number - 1
    }

    private static func label(_ index: Int) -> String {
        String(format: "%04d-%02d", index / 12, index % 12 + 1)
    }
}
