import Foundation

/// One calendar or one reminder list, independent of EventKit.
public struct CalendarSource: Identifiable, Hashable, Codable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case events
        case reminders
    }

    /// Where the calendar lives, from EventKit's calendar type.
    public enum CalendarType: String, Codable, Sendable {
        /// Only on this iPad.
        case local
        /// A synced account such as iCloud or Google.
        case calDAV
        case exchange
        /// A subscribed feed, such as a school, Canvas or holiday calendar.
        case subscription
        /// Birthdays from Contacts.
        case birthday

        /// A word for Settings, or nil when the account name says enough.
        public var label: String? {
            switch self {
            case .local: "On this iPad"
            case .calDAV: nil
            case .exchange: "Exchange"
            case .subscription: "Subscribed"
            case .birthday: "Birthdays"
            }
        }
    }

    /// Stable identifier (`EKCalendar.calendarIdentifier` for EventKit).
    public var id: String
    public var title: String
    public var colorHex: String
    public var kind: Kind
    /// Account it lives in, for example "iCloud" or "Gmail".
    public var accountName: String?
    public var allowsModifications: Bool
    /// Subscribed calendars such as holidays are read-only.
    public var isSubscribed: Bool
    public var calendarType: CalendarType
    /// Audience to use when nobody assigned one in Settings.
    public var suggestedAudience: CalendarAudience?
    /// Set for a calendar or list on the recognized person's own iPhone,
    /// which only they see, and only while they are recognized.
    public var phone: PhoneOrigin?

    /// The phone a calendar or list comes from.
    public struct PhoneOrigin: Hashable, Codable, Sendable {
        public var memberID: UUID
        /// Such as "Kyle's iPhone".
        public var deviceName: String
        /// The phone's default calendar or list for new items.
        public var isDefault: Bool

        public init(memberID: UUID, deviceName: String, isDefault: Bool = false) {
            self.memberID = memberID
            self.deviceName = deviceName
            self.isDefault = isDefault
        }
    }

    public init(
        id: String, title: String, colorHex: String, kind: Kind, accountName: String? = nil,
        allowsModifications: Bool = true, isSubscribed: Bool = false, calendarType: CalendarType = .calDAV,
        suggestedAudience: CalendarAudience? = nil, phone: PhoneOrigin? = nil
    ) {
        self.id = id
        self.title = title
        self.colorHex = colorHex
        self.kind = kind
        self.accountName = accountName
        self.allowsModifications = allowsModifications
        self.isSubscribed = isSubscribed
        self.calendarType = calendarType
        self.suggestedAudience = suggestedAudience
        self.phone = phone
    }

    /// Account and kind for Settings, such as "Subscribed Calendars · Read only".
    public var accountDetail: String {
        let account = accountName ?? "No account"
        var parts = [account]
        if let label = calendarType.label, !account.localizedCaseInsensitiveContains(label) { parts.append(label) }
        if !allowsModifications { parts.append("Read only") }
        return parts.joined(separator: " · ")
    }

    /// Audience suggested from well-known calendar names. Holidays and the
    /// Family Sharing calendar are household content, and so is Groceries.
    public static func suggestedAudience(title: String, kind: Kind, isSubscribed: Bool) -> CalendarAudience? {
        let lowered = title.lowercased()
        switch kind {
        case .events:
            if lowered.contains("holiday") { return .everyone }
            if lowered == "family" || lowered == "household" { return .everyone }
        case .reminders:
            if lowered == "groceries" || lowered == "grocery" || lowered == "shopping" || lowered == "family" { return .everyone }
        }
        return nil
    }
}
