import HomePadCore

/// What the Connect apps keep between openings (see `@AppState`). Shared by
/// the household. The Family Board and Shortcuts have nothing to restore:
/// their notes and tiles are already saved, and edit mode ends on closing.
enum ConnectAppState {
    /// Where push to talk goes: every HomePad, or one by its peer identifier.
    static let intercomTarget = AppStateKey("intercom.target", default: IntercomTarget.everyone)
}

extension IntercomTarget {
    /// This target while its HomePad is reachable, otherwise every HomePad.
    func reachable(among homePadIDs: [String]) -> IntercomTarget {
        guard case .device(let id) = self, !homePadIDs.contains(id) else { return self }
        return .everyone
    }
}
