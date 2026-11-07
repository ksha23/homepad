import HomePadCore
import HomePadUI
import SwiftUI

/// The Calendar app: day, week and month views over the calendars the current
/// viewer may see and left checked in the Calendars list, with Apple's event
/// editor for adding and editing on the iPad's calendars, and HomePad's own
/// for the recognized person's phone calendars (`PhoneEventEditorSheet`).
///
/// It reopens in the view and on the day it was left, for each person. The
/// day goes back to today after a few hours or the next day
/// (`AppStateLifetime.timePosition`), and the view stays.
struct CalendarAppView: View {
    @Environment(HouseholdCalendarService.self) private var calendar
    @AppState(PersonalAppState.calendarMode) private var mode
    @AppState(PersonalAppState.calendarDate) private var selectedDate
    @State private var events: [PersonalEvent] = []
    @State private var editorRequest: EventEditorSheet.Request?
    @State private var phoneEditor: PhoneEventEditorSheet.Mode?
    @State private var isChoosingCalendars = PersonalDebugLaunch.showsCalendarsList

    var body: some View {
        AppScreen(title, accessory: { accessory }, titleAccessory: { modePicker }) {
            if !calendar.hasAccess && calendar.phoneSnapshot == nil {
                CalendarAccessPrompt()
            } else if calendar.visibleCalendars.isEmpty {
                noCalendars
            } else if calendar.shownCalendars.isEmpty {
                EmptyStateView("No Calendars Shown", message: "Every calendar is unchecked in Calendars.",
                               systemImage: "calendar", actionTitle: "Show All", action: calendar.showAll)
            } else {
                content
                PhoneWindowFootnote(mode: mode, date: selectedDate)
                PrivacyFootnote(kind: .events)
            }
        }
        .task(id: "\(calendar.reloadKey)|\(mode.rawValue)|\(selectedDate.timeIntervalSinceReferenceDate)") { reload() }
        // `-HomePadCalendarMode` wins over the view it was left in.
        .onAppear { if let launchMode = PersonalDebugLaunch.calendarMode { mode = launchMode } }
        .reportsScreenFocus(CalendarFocus(mode: mode, date: selectedDate), at: \.calendar)
        .sheet(isPresented: $isChoosingCalendars) {
            CalendarsListSheet().environment(calendar)
        }
        .sheet(item: $editorRequest) { request in
            if let backend = calendar.eventKitBackend {
                EventEditorSheet(store: backend.eventStore, event: request.event) { changed in
                    editorRequest = nil
                    if changed { calendar.noteExternalEdit() }
                }
                .systemSheetStyle()
            }
        }
        .sheet(item: $phoneEditor) { mode in
            PhoneEventEditorSheet(mode: mode).environment(calendar)
        }
    }

    private var title: String {
        selectedDate.formatted(.dateTime.month(.wide).year())
    }

    @ViewBuilder
    private var content: some View {
        switch mode {
        case .day:
            DayAgendaView(selectedDate: $selectedDate, events: events, onSelect: edit)
        case .week:
            WeekAgendaView(selectedDate: $selectedDate, events: events, onSelect: edit) { day in
                selectedDate = day
                mode = .day
            }
        case .month:
            MonthGridView(selectedDate: selectedDate, events: events) { day in
                selectedDate = day
                mode = .day
            }
        }
    }

    /// Day, Week and Month next to the title, as a menu clear of the Now Playing pill.
    private var modePicker: some View {
        HeaderPicker("View", selection: $mode, title: mode.title, systemImage: mode.systemImage) {
            ForEach(CalendarDisplayMode.allCases) { Label($0.title, systemImage: $0.systemImage).tag($0) }
        }
    }

    /// Calendars first, the item that gives way first when the header is short
    /// of room. Then previous, Today and next in one group, and Add Event, the
    /// one prominent action.
    @ViewBuilder
    private var accessory: some View {
        if !calendar.visibleCalendars.isEmpty {
            GlassIconButton("calendar.badge.checkmark", label: "Calendars") { isChoosingCalendars = true }
                .toolbarItemPriority(.low)
        }
        ToolbarGroup {
            GlassIconButton("chevron.left", label: "Previous") { select(CalendarDateMath.step(selectedDate, mode: mode, by: -1)) }
            GlassCapsuleButton("Today") { select(Date()) }
            GlassIconButton("chevron.right", label: "Next") { select(CalendarDateMath.step(selectedDate, mode: mode, by: 1)) }
        }
        if (calendar.eventKitBackend != nil && calendar.hasAccess) || calendar.hasWritablePhoneCalendar {
            GlassIconButton("plus", label: "Add Event", isProminent: true, action: addEvent)
        }
    }

    @ViewBuilder
    private var noCalendars: some View {
        if calendar.allEventCalendars.isEmpty {
            EmptyStateView(
                "No Calendars on This iPad",
                message: "Add an account or a subscribed calendar in the Settings app, under Apps, Calendar, Calendar Accounts. It shows here right away.",
                systemImage: "calendar.badge.plus"
            )
        } else {
            let reason = calendar.hiddenNote(.events) ?? "Shared calendars appear for everyone. Personal calendars appear once their owner is recognized."
            EmptyStateView(
                "No Calendars to Show",
                message: "\(reason) Choose who each calendar belongs to in Settings, under Personal Info.",
                systemImage: "calendar.badge.exclamationmark"
            )
        }
    }

    /// Moves to another day, week or month the way tapping a day does: the
    /// day number rolls and the selection slides.
    private func select(_ date: Date) {
        withAnimation(Theme.Motion.standard) { selectedDate = date }
    }

    /// Events fade in and out as the day changes, rather than switching.
    private func reload() {
        let next = calendar.events(for: mode, around: selectedDate)
        guard next != events else { return }
        withAnimation(Theme.Motion.standard) { events = next }
    }

    /// Apple's editor for the iPad's calendars. When new events go to the
    /// person's own phone, HomePad's editor, which lists the phone's calendars.
    private func addEvent() {
        guard let backend = calendar.eventKitBackend, calendar.preferredCalendarForNewEvents()?.phone == nil else {
            phoneEditor = .new(selectedDate)
            return
        }
        let draft = backend.draftEvent(on: selectedDate, calendarID: calendar.preferredCalendarForNewEvents()?.id)
        editorRequest = EventEditorSheet.Request(event: draft)
    }

    private func edit(_ event: PersonalEvent) {
        if event.isOnPhone { return phoneEditor = .edit(event) }
        guard let backend = calendar.eventKitBackend, let ekEvent = backend.ekEvent(for: event) else { return }
        editorRequest = EventEditorSheet.Request(event: ekEvent)
    }
}
