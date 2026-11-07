import Foundation

/// chat.db stores dates as nanoseconds since 2001-01-01. Old databases used seconds.
enum AppleDate {
    private static let nanosecondThreshold: Int64 = 1_000_000_000_000

    static func date(_ raw: Int64) -> Date {
        let seconds = raw > nanosecondThreshold ? Double(raw) / 1_000_000_000 : Double(raw)
        return Date(timeIntervalSinceReferenceDate: seconds)
    }

    static func raw(_ date: Date) -> Int64 {
        Int64(date.timeIntervalSinceReferenceDate * 1_000_000_000)
    }
}
