import Foundation
import HomePadCore

/// The words Find My and the assistant use for where a device is and when it
/// was last seen, so both say the same thing: "Kyle's iPhone is at home, last
/// seen 2 minutes ago."
enum FindMyWording {
    /// "at home", "at Work", "near 120 State St" or "away from home".
    static func place(_ device: TrackedDevice, address: String?) -> String {
        switch device.place {
        case .home: "at home"
        case .zone(let name): "at \(name)"
        case .away: address.map { "near \($0)" } ?? "away from home"
        case .unknown: "not sharing a location right now"
        }
    }

    /// A short label for a list row: "Home", "Work", the address, or "Away".
    static func placeLabel(_ device: TrackedDevice, address: String?) -> String {
        switch device.place {
        case .home: "Home"
        case .zone(let name): name
        case .away: address ?? "Away"
        case .unknown: "No location"
        }
    }

    /// "120 State St" from "120 State St, Madison", for narrow rows.
    static func street(_ address: String) -> String {
        address.split(separator: ",").first.map { $0.trimmingCharacters(in: .whitespaces) } ?? address
    }

    /// "just now", "2 minutes ago", "yesterday".
    static func lastSeen(_ date: Date, now: Date = Date()) -> String {
        if now.timeIntervalSince(date) < 60 { return "just now" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        formatter.dateTimeStyle = .named
        return formatter.localizedString(for: date, relativeTo: now)
    }

    /// The full sentence, for the assistant and VoiceOver.
    static func sentence(title: String, device: TrackedDevice, address: String?, now: Date = Date()) -> String {
        var sentence: String
        if device.place == .unknown {
            sentence = "\(title) is not sharing a location right now. Home Assistant last heard from it \(lastSeen(device.lastUpdated, now: now))"
        } else {
            sentence = "\(title) is \(place(device, address: address)), last seen \(lastSeen(device.lastUpdated, now: now))"
        }
        if let battery = battery(device) { sentence += ", with \(battery) battery" }
        return sentence + "."
    }

    /// "82%", or "82% and charging".
    static func battery(_ device: TrackedDevice) -> String? {
        guard let level = device.batteryLevel else { return nil }
        let percent = level.formatted(.percent.precision(.fractionLength(0)))
        return device.isCharging == true ? "\(percent) and charging" : percent
    }

    /// "Within 12 m" (or feet where the region uses them).
    static func accuracy(_ meters: Double) -> String {
        let distance = Measurement(value: meters, unit: UnitLength.meters)
        return "Within \(distance.formatted(.measurement(width: .abbreviated, usage: .road)))"
    }

    /// Where the location comes from, for the device card.
    static func source(_ device: TrackedDevice) -> String {
        switch device.source {
        case .iCloud: "Located by iCloud through Home Assistant"
        case .companionApp: "Located by the Home Assistant app"
        case .other: "Located by \(sourceName(device))"
        }
    }

    /// "iCloud", "Home Assistant app" or "Life360", for Settings.
    static func sourceName(_ device: TrackedDevice) -> String {
        switch device.source {
        case .iCloud: "iCloud"
        case .companionApp: "Home Assistant app"
        case .other: device.integration.map(integrationName) ?? "Home Assistant"
        }
    }

    /// `life360` becomes "Life360", `owntracks` becomes "Owntracks".
    private static func integrationName(_ domain: String) -> String {
        let known = ["life360": "Life360", "owntracks": "OwnTracks", "gpslogger": "GPSLogger", "traccar": "Traccar"]
        return known[domain] ?? domain.replacingOccurrences(of: "_", with: " ").capitalized
    }
}
