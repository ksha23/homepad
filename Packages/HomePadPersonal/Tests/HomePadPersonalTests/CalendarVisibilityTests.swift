import Foundation
import Testing
@testable import HomePadPersonal

/// The pure calendar-to-member filtering rules.
@Suite struct CalendarVisibilityTests {
    let kyle = UUID()
    let sam = UUID()

    func source(_ id: String, kind: CalendarSource.Kind = .events, suggested: CalendarAudience? = nil) -> CalendarSource {
        CalendarSource(id: id, title: id, colorHex: "#FFFFFF", kind: kind, suggestedAudience: suggested)
    }

    func unlocked(_ id: UUID, admins: Set<UUID> = []) -> CalendarViewer {
        CalendarViewer(memberID: id, isUnlocked: true, adminIDs: admins)
    }

    @Test func sharedCalendarsShowForEveryoneIncludingGuests() {
        let policy = CalendarVisibilityPolicy(assignments: ["family": .everyone])
        #expect(policy.isVisible(source("family"), to: .guest))
        #expect(policy.isVisible(source("family"), to: unlocked(kyle)))
    }

    @Test func personalCalendarNeedsItsOwnerRecognized() {
        let policy = CalendarVisibilityPolicy(assignments: ["work": .members([kyle])])
        let work = source("work")
        #expect(!policy.isVisible(work, to: .guest))
        #expect(policy.isVisible(work, to: unlocked(kyle)))
        #expect(!policy.isVisible(work, to: unlocked(sam)))
        // Picking Kyle in the People switcher is not recognition.
        #expect(!policy.isVisible(work, to: CalendarViewer(memberID: kyle, isUnlocked: false)))
    }

    @Test func calendarCanBelongToSeveralMembers() {
        let policy = CalendarVisibilityPolicy(assignments: ["couple": .members([kyle, sam])])
        #expect(policy.isVisible(source("couple"), to: unlocked(kyle)))
        #expect(policy.isVisible(source("couple"), to: unlocked(sam)))
        #expect(!policy.isVisible(source("couple"), to: .guest))
    }

    @Test func hiddenAndUnclaimedCalendarsNeverShow() {
        let policy = CalendarVisibilityPolicy(assignments: ["old": .hidden, "orphan": .members([])], unassigned: .everyone)
        #expect(!policy.isVisible(source("old"), to: unlocked(kyle)))
        #expect(!policy.isVisible(source("orphan"), to: unlocked(kyle)))
    }

    @Test func unassignedCalendarsBelongToAdminsByDefault() {
        let policy = CalendarVisibilityPolicy()
        let new = source("new")
        #expect(policy.isVisible(new, to: unlocked(kyle, admins: [kyle])))
        #expect(!policy.isVisible(new, to: unlocked(sam, admins: [kyle])))
        #expect(!policy.isVisible(new, to: CalendarViewer(memberID: nil, isUnlocked: false, adminIDs: [kyle])))
        // With no admins nobody can ever be recognized, so they show for everyone
        // instead of never showing.
        #expect(policy.audience(for: new, adminIDs: []) == .everyone)
        #expect(policy.isVisible(new, to: .guest))
    }

    @Test func unassignedPolicyCanShareOrHide() {
        #expect(CalendarVisibilityPolicy(unassigned: .everyone).isVisible(source("new"), to: .guest))
        #expect(!CalendarVisibilityPolicy(unassigned: .hidden).isVisible(source("new"), to: unlocked(kyle, admins: [kyle])))
    }

    @Test func suggestionsApplyUntilSomeoneAssigns() {
        let holidays = source("holidays", suggested: .everyone)
        #expect(CalendarVisibilityPolicy().isVisible(holidays, to: .guest))
        let assigned = CalendarVisibilityPolicy(assignments: ["holidays": .members([sam])])
        #expect(!assigned.isVisible(holidays, to: .guest))
        #expect(assigned.isVisible(holidays, to: unlocked(sam)))
    }

    @Test func suggestedAudiencesFromWellKnownNames() {
        #expect(CalendarSource.suggestedAudience(title: "US Holidays", kind: .events, isSubscribed: true) == .everyone)
        #expect(CalendarSource.suggestedAudience(title: "Family", kind: .events, isSubscribed: false) == .everyone)
        #expect(CalendarSource.suggestedAudience(title: "Groceries", kind: .reminders, isSubscribed: false) == .everyone)
        #expect(CalendarSource.suggestedAudience(title: "Work", kind: .events, isSubscribed: false) == nil)
    }

    @Test func visibleKeepsOrder() {
        let policy = CalendarVisibilityPolicy(assignments: ["a": .everyone, "b": .members([kyle]), "c": .everyone])
        let result = policy.visible([source("a"), source("b"), source("c")], to: .guest)
        #expect(result.map(\.id) == ["a", "c"])
    }

    // MARK: Chooser selections

    @Test func chooserPreselectsEachRowsCalendars() {
        let sources = [source("family", suggested: .everyone), source("work"), source("gym")]
        let policy = CalendarVisibilityPolicy(assignments: ["gym": .members([sam])])
        #expect(policy.selection(for: .everyone, among: sources, adminIDs: [kyle]) == ["family"])
        #expect(policy.selection(for: .member(kyle), among: sources, adminIDs: [kyle]) == ["work"])
        #expect(policy.selection(for: .member(sam), among: sources, adminIDs: [kyle]) == ["gym"])
    }

    @Test func pickingForAMemberMakesASharedCalendarPersonal() {
        let sources = [source("family", suggested: .everyone), source("work")]
        var policy = CalendarVisibilityPolicy(unassigned: .hidden)
        policy.apply(selection: ["family", "work"], for: .member(kyle), among: sources, adminIDs: [])
        #expect(policy.assignments["family"] == .members([kyle]))
        #expect(policy.assignments["work"] == .members([kyle]))
        policy.apply(selection: ["work"], for: .member(sam), among: sources, adminIDs: [])
        #expect(policy.assignments["work"] == .members([kyle, sam]))
    }

    @Test func unpickingRemovesOnlyThatRowsClaim() {
        let sources = [source("couple"), source("family")]
        var policy = CalendarVisibilityPolicy(assignments: ["couple": .members([kyle, sam]), "family": .everyone])
        policy.apply(selection: [], for: .member(kyle), among: sources, adminIDs: [])
        #expect(policy.assignments["couple"] == .members([sam]))
        #expect(policy.assignments["family"] == .everyone)
        policy.apply(selection: [], for: .everyone, among: sources, adminIDs: [])
        #expect(policy.assignments["family"] == .members([]))
        #expect(!policy.isVisible(source("family"), to: .guest))
    }

    @Test func pickingForEveryoneShares() {
        let sources = [source("work")]
        var policy = CalendarVisibilityPolicy(assignments: ["work": .members([kyle])])
        policy.apply(selection: ["work"], for: .everyone, among: sources, adminIDs: [])
        #expect(policy.assignments["work"] == .everyone)
    }

    @Test func untouchedCalendarsKeepTheirSuggestion() {
        let sources = [source("holidays", suggested: .everyone), source("work")]
        var policy = CalendarVisibilityPolicy(unassigned: .hidden)
        policy.apply(selection: ["holidays", "work"], for: .everyone, among: sources, adminIDs: [])
        #expect(policy.assignments["holidays"] == nil)
        #expect(policy.assignments["work"] == .everyone)
    }
}
