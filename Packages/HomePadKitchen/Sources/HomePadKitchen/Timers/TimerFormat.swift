import Foundation

/// Text for timers: "04:47" countdowns, "15 MIN" totals, "5 min" default labels.
public enum TimerFormat {
    /// "04:47", or "1:04:47" past an hour. Rounds up so a timer never shows 00:00 while running.
    public static func countdown(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded(.up))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        if hours > 0 { return String(format: "%d:%02d:%02d", hours, minutes, secs) }
        return String(format: "%02d:%02d", minutes, secs)
    }

    /// "15 min", "1 hr 30 min", "45 sec", "6 min 30 sec".
    public static func spoken(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        var parts: [String] = []
        if hours > 0 { parts.append("\(hours) hr") }
        if minutes > 0 { parts.append("\(minutes) min") }
        if secs > 0 && hours == 0 { parts.append("\(secs) sec") }
        return parts.isEmpty ? "0 sec" : parts.joined(separator: " ")
    }

    /// "15 MIN", the total shown under a countdown.
    public static func total(_ seconds: TimeInterval) -> String {
        spoken(seconds).uppercased()
    }

    /// The label for a timer started without a name.
    public static func defaultLabel(for seconds: TimeInterval) -> String {
        spoken(seconds)
    }
}
