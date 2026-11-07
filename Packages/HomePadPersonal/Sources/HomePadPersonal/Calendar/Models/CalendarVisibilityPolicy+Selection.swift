import Foundation

/// One row of the calendar mapping in Settings: the household as a whole, or one member.
public enum CalendarAudienceTarget: Hashable, Sendable {
    case everyone
    case member(UUID)
}

extension CalendarVisibilityPolicy {
    /// Calendars among `sources` that currently belong to `target`.
    /// This preselects the calendar chooser for that row.
    public func selection(for target: CalendarAudienceTarget, among sources: [CalendarSource], adminIDs: Set<UUID>) -> Set<String> {
        Set(sources.filter { includes(target, audience(for: $0, adminIDs: adminIDs)) }.map(\.id))
    }

    /// Applies what someone picked in the calendar chooser for one row.
    ///
    /// - Picking a calendar for Everyone makes it shared.
    /// - Picking it for a member makes it personal to that member (and to any
    ///   other members who already had it). A shared calendar picked for a
    ///   member stops being shared.
    /// - Unpicking removes only this row's claim. A calendar nobody claims is hidden.
    public mutating func apply(selection: Set<String>, for target: CalendarAudienceTarget, among sources: [CalendarSource], adminIDs: Set<UUID>) {
        for source in sources {
            let current = audience(for: source, adminIDs: adminIDs)
            let picked = selection.contains(source.id)
            guard picked != includes(target, current) else { continue }
            switch target {
            case .everyone:
                assignments[source.id] = picked ? .everyone : .members([])
            case .member(let id):
                var owners: Set<UUID> = []
                if case .members(let existing) = current { owners = existing }
                if picked { owners.insert(id) } else { owners.remove(id) }
                assignments[source.id] = .members(owners)
            }
        }
    }

    private func includes(_ target: CalendarAudienceTarget, _ audience: CalendarAudience) -> Bool {
        switch (target, audience) {
        case (.everyone, .everyone): true
        case (.member(let id), .members(let owners)): owners.contains(id)
        default: false
        }
    }
}
