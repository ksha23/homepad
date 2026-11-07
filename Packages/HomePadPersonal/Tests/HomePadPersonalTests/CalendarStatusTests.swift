import Foundation
import Testing
@testable import HomePadPersonal

/// Why a calendar shows or not: subscribed and newly added calendars, the
/// reasons Settings and the apps give, and the per-calendar choice in Settings.
@Suite struct CalendarStatusTests {
    let kyle = UUID()
    let sam = UUID()
    var names: [UUID: String] { [kyle: "Kyle", sam: "Sam"] }

    func source(_ id: String, suggested: CalendarAudience? = nil) -> CalendarSource {
        CalendarSource(id: id, title: id.capitalized, colorHex: "#FFFFFF", kind: .events, suggestedAudience: suggested)
    }

    /// A Canvas feed added with Settings, Calendar, Add Subscribed Calendar.
    var canvas: CalendarSource {
        CalendarSource(id: "canvas", title: "Canvas", colorHex: "#E43D30", kind: .events, accountName: "Subscribed Calendars",
                       allowsModifications: false, isSubscribed: true, calendarType: .subscription)
    }

    func unlocked(_ id: UUID, admins: Set<UUID>) -> CalendarViewer {
        CalendarViewer(memberID: id, isUnlocked: true, adminIDs: admins)
    }

    func guest(admins: Set<UUID>) -> CalendarViewer {
        CalendarViewer(memberID: nil, isUnlocked: false, adminIDs: admins)
    }

    // MARK: Subscribed and new calendars

    @Test func subscribedReadOnlyCalendarsFollowTheSameRulesAsAnyOther() {
        let policy = CalendarVisibilityPolicy()
        #expect(policy.isVisible(canvas, to: unlocked(kyle, admins: [kyle])))
        #expect(!policy.isVisible(canvas, to: guest(admins: [kyle])))
        #expect(CalendarVisibilityPolicy(unassigned: .everyone).isVisible(canvas, to: guest(admins: [kyle])))
        #expect(CalendarVisibilityPolicy(assignments: ["canvas": .everyone]).isVisible(canvas, to: .guest))
    }

    @Test func calendarAddedAfterChoicesWereSavedFollowsTheDefault() {
        var policy = CalendarVisibilityPolicy()
        let before = [source("family", suggested: .everyone), source("work")]
        policy.apply(selection: ["family", "work"], for: .everyone, among: before, adminIDs: [kyle])
        // Canvas shows up on the iPad later. Nothing was saved for it, so it is
        // the admins' until someone chooses, and shows while Kyle is recognized.
        #expect(policy.assignments["canvas"] == nil)
        #expect(policy.origin(for: canvas) == .unassignedRule)
        #expect(policy.audience(for: canvas, adminIDs: [kyle]) == .members([kyle]))
        #expect(policy.isVisible(canvas, to: unlocked(kyle, admins: [kyle])))
    }

    @Test func noPeopleSetUpMeansNewCalendarsShowForEveryone() {
        let status = CalendarVisibilityPolicy().status(of: canvas, for: .guest)
        #expect(status == CalendarStatus(audience: .everyone, origin: .unassignedRule, isVisibleNow: true))
        #expect(CalendarAudienceText.explanation(for: status, unassigned: .admins, names: [:])
                == "Shows for everyone, because nobody in People is an admin yet.")
    }

    // MARK: Reasons

    @Test func originSaysWhoDecided() {
        let policy = CalendarVisibilityPolicy(assignments: ["work": .everyone])
        #expect(policy.origin(for: source("work")) == .assigned)
        #expect(policy.origin(for: source("holidays", suggested: .everyone)) == .suggested)
        #expect(policy.origin(for: canvas) == .unassignedRule)
    }

    @Test func hiddenCalendarsAreSplitByReason() {
        let sources = [source("family", suggested: .everyone), source("work"), source("old"), source("orphan"), canvas, source("gym")]
        let policy = CalendarVisibilityPolicy(assignments: ["old": .hidden, "orphan": .members([]), "gym": .members([sam])])
        let forGuest = policy.hidden(sources, from: guest(admins: [kyle]))
        #expect(forGuest.awaitingOwner.map(\.id) == ["work", "canvas", "gym"])
        #expect(forGuest.hiddenInSettings.map(\.id) == ["old", "orphan"])
        let forKyle = policy.hidden(sources, from: unlocked(kyle, admins: [kyle]))
        #expect(forKyle.awaitingOwner.map(\.id) == ["gym"])
        #expect(forKyle.hiddenInSettings.map(\.id) == ["old", "orphan"])
        #expect(policy.hidden([source("family", suggested: .everyone)], from: .guest).isEmpty)
    }

    @Test func hiddenByTheRuleForCalendarsNobodyChoseCountsAsHiddenInSettings() {
        let hidden = CalendarVisibilityPolicy(unassigned: .hidden).hidden([canvas], from: unlocked(kyle, admins: [kyle]))
        #expect(hidden.hiddenInSettings.map(\.id) == ["canvas"])
        #expect(hidden.awaitingOwner.isEmpty)
    }

    @Test func explanationsSayWhoSeesItAndWhy() {
        func explain(_ audience: CalendarAudience, _ origin: CalendarAudienceOrigin, unassigned: UnassignedCalendarPolicy = .admins) -> String {
            CalendarAudienceText.explanation(for: CalendarStatus(audience: audience, origin: origin, isVisibleNow: false),
                                             unassigned: unassigned, names: names)
        }
        #expect(explain(.everyone, .assigned) == "Shows for everyone, guests included.")
        #expect(explain(.everyone, .unassignedRule, unassigned: .everyone) == "Shows for everyone, because Calendars Nobody Chose are shared.")
        #expect(explain(.members([kyle]), .assigned) == "Shows only while Kyle is recognized.")
        #expect(explain(.members([kyle]), .unassignedRule)
                == "Shows only while Kyle is recognized. Nobody chose who it belongs to, so it belongs to the admins.")
        #expect(explain(.members([kyle, sam]), .assigned) == "Shows only while Kyle or Sam is recognized.")
        #expect(explain(.hidden, .assigned) == "Hidden, because it was set to Hidden here.")
        #expect(explain(.hidden, .unassignedRule, unassigned: .hidden) == "Hidden, because Calendars Nobody Chose is set to Hidden.")
        #expect(explain(.members([]), .assigned) == "Hidden, because it was unchecked for everyone it belonged to.")
        #expect(explain(.members([UUID()]), .assigned) == "Hidden, because it belongs to someone no longer in People.")
    }

    @Test func shortLabelsForTheMenu() {
        #expect(CalendarAudienceText.short(.everyone, names: names) == "Everyone")
        #expect(CalendarAudienceText.short(.members([sam, kyle]), names: names) == "Kyle and Sam")
        #expect(CalendarAudienceText.short(.members([]), names: names) == "Hidden")
        #expect(CalendarAudienceText.short(.members([UUID()]), names: names) == "Hidden")
        #expect(CalendarAudienceText.short(.hidden, names: names) == "Hidden")
    }

    @Test func notesUnderTheAppsCountWhatIsHidden() {
        let none = HiddenCalendars()
        #expect(CalendarAudienceText.hiddenNote(none, kind: .events, showsNames: false) == nil)
        let one = HiddenCalendars(awaitingOwner: [canvas])
        #expect(CalendarAudienceText.hiddenNote(one, kind: .events, showsNames: false)
                == "1 personal calendar is hidden until its owner is recognized.")
        let mixed = HiddenCalendars(awaitingOwner: [canvas, source("work")], hiddenInSettings: [source("old"), source("gym")])
        #expect(CalendarAudienceText.hiddenNote(mixed, kind: .events, showsNames: false)
                == "2 personal calendars are hidden until their owners are recognized. 2 calendars are hidden in Settings, under Personal Info.")
        #expect(CalendarAudienceText.hiddenNote(mixed, kind: .events, showsNames: true)
                == "2 personal calendars are hidden until their owners are recognized. Old and Gym are hidden in Settings, under Personal Info.")
        let list = HiddenCalendars(hiddenInSettings: [source("errands")])
        #expect(CalendarAudienceText.hiddenNote(list, kind: .reminders, showsNames: false) == "1 list is hidden in Settings, under Personal Info.")
    }

    // MARK: Per-calendar choice in Settings

    @Test func choiceMatchesTheSavedAssignment() {
        #expect(CalendarAudienceChoice(assignment: nil) == .automatic)
        #expect(CalendarAudienceChoice(assignment: .everyone) == .everyone)
        #expect(CalendarAudienceChoice(assignment: .hidden) == .hidden)
        #expect(CalendarAudienceChoice(assignment: .members([])) == .hidden)
        #expect(CalendarAudienceChoice(assignment: .members([kyle])) == .member(kyle))
        #expect(CalendarAudienceChoice(assignment: .members([kyle, sam])) == .several([kyle, sam]))
        #expect(CalendarAudienceChoice.automatic.assignment == nil)
        #expect(CalendarAudienceChoice.member(sam).assignment == .members([sam]))
    }

    @Test func assigningNilGoesBackToAutomatic() {
        var policy = CalendarVisibilityPolicy(assignments: ["canvas": .hidden])
        #expect(!policy.isVisible(canvas, to: unlocked(kyle, admins: [kyle])))
        policy.assign(nil, toCalendar: "canvas")
        #expect(policy.assignments.isEmpty)
        #expect(policy.isVisible(canvas, to: unlocked(kyle, admins: [kyle])))
        policy.assign(.everyone, toCalendar: "canvas")
        #expect(policy.isVisible(canvas, to: .guest))
    }

    // MARK: Account details

    @Test func accountDetailNamesTheAccountAndKind() {
        #expect(canvas.accountDetail == "Subscribed Calendars · Read only")
        let birthdays = CalendarSource(id: "b", title: "Birthdays", colorHex: "#FFFFFF", kind: .events, accountName: "Other",
                                       allowsModifications: false, isSubscribed: true, calendarType: .birthday)
        #expect(birthdays.accountDetail == "Other · Birthdays · Read only")
        let local = CalendarSource(id: "l", title: "Calendar", colorHex: "#FFFFFF", kind: .events, accountName: "Default", calendarType: .local)
        #expect(local.accountDetail == "Default · On this iPad")
        let icloud = CalendarSource(id: "i", title: "Home", colorHex: "#FFFFFF", kind: .events, accountName: "iCloud")
        #expect(icloud.accountDetail == "iCloud")
    }
}
