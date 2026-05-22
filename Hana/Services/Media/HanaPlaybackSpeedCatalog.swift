import AVKit
import Foundation

enum HanaPlaybackSpeedCatalog {
    static var longPressRates: [Double] {
        systemRates
            .filter { $0 > 1 }
            .sorted()
    }

    static var defaultLongPressRate: Double {
        normalizedLongPressRate(2)
    }

    static func normalizedLongPressRate(_ value: Double) -> Double {
        let rates = longPressRates
        precondition(!rates.isEmpty, "AVPlaybackSpeed.systemDefaultSpeeds must include rates above 1x.")
        return rates.min { abs($0 - value) < abs($1 - value) }!
    }

    static func title(for rate: Double) -> String {
        if rate.rounded(.towardZero) == rate {
            return "\(Int(rate))x"
        }
        return "\(rate.formatted(.number.precision(.fractionLength(0...2))))x"
    }

    private static var systemRates: [Double] {
        AVPlaybackSpeed.systemDefaultSpeeds.reduce(into: [Double]()) { result, speed in
            let rate = Double(speed.rate)
            guard !result.contains(where: { abs($0 - rate) < 0.001 }) else { return }
            result.append(rate)
        }
    }
}
