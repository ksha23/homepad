import Foundation

/// "Good morning, Margot" and friends.
enum Greeting {
    /// "Good morning", "Good afternoon", "Good evening", or "Hello" at night.
    static func phrase(for date: Date, calendar: Calendar = .current) -> String {
        let hour = calendar.component(.hour, from: date)
        return switch hour {
        case 5..<12: "Good morning"
        case 12..<17: "Good afternoon"
        case 17..<24: "Good evening"
        default: "Hello"
        }
    }

    static func text(for date: Date, name: String?, calendar: Calendar = .current) -> String {
        let phrase = phrase(for: date, calendar: calendar)
        guard let name, !name.isEmpty else { return phrase }
        return "\(phrase), \(name)"
    }
}

/// The Home Screen header's two lines, as on HomeView: the date over the
/// time, or "Good morning," over the name for a moment after someone is
/// recognized. The view sets them in capitals.
struct HomeHeaderLines: Equatable {
    var top: String
    var bottom: String
    var isGreeting: Bool

    /// "Wednesday, Apr 1" over "10:09 AM".
    static func date(_ date: Date) -> HomeHeaderLines {
        HomeHeaderLines(top: date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()),
                        bottom: date.formatted(.dateTime.hour().minute()), isGreeting: false)
    }

    /// "Good morning," over the name.
    static func greeting(_ date: Date, name: String, calendar: Calendar = .current) -> HomeHeaderLines {
        HomeHeaderLines(top: Greeting.phrase(for: date, calendar: calendar) + ",", bottom: name, isGreeting: true)
    }
}
