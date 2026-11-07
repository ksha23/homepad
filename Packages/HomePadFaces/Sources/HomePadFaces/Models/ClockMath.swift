import Foundation
import HomePadUI

extension ClockMath {
    /// The angular distance in hours (0...6) between a numeral and a dial position in hours.
    static func hourDistance(_ numeral: Int, to hours: Double) -> Double {
        let raw = abs(Double(numeral % 12) - hours.truncatingRemainder(dividingBy: 12))
        return min(raw, 12 - raw)
    }
}

/// Time strings for big digital clocks, without the AM/PM suffix.
enum ClockText {
    struct Parts: Equatable {
        var hours: String
        var minutes: String
        /// "AM" or "PM" in 12-hour locales, nil in 24-hour ones.
        var period: String?

        var joined: String { "\(hours):\(minutes)" }
    }

    static func parts(for date: Date, uses24Hour: Bool, calendar: Calendar = .current) -> Parts {
        let hour = calendar.component(.hour, from: date)
        let minute = calendar.component(.minute, from: date)
        let minutes = String(format: "%02d", minute)
        if uses24Hour {
            return Parts(hours: String(format: "%02d", hour), minutes: minutes, period: nil)
        }
        let twelve = hour % 12 == 0 ? 12 : hour % 12
        return Parts(hours: "\(twelve)", minutes: minutes, period: hour < 12 ? "AM" : "PM")
    }

    /// True when the locale writes times on a 24-hour clock.
    static func localeUses24Hour(_ locale: Locale = .current) -> Bool {
        let format = DateFormatter.dateFormat(fromTemplate: "j", options: 0, locale: locale) ?? ""
        return !format.contains("a")
    }
}
