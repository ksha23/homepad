import HomePadCore
import HomePadUI
import SwiftUI

/// HomePad's event editor, for the recognized person's own iPhone calendars,
/// which Apple's editor cannot see: a title, a place, all day or not, when,
/// and the calendar. A change is sent to the phone and saved there, waking it
/// if needed. Until it is, the event shows as saving, waiting or not saved,
/// and this sheet offers Try Again and Discard Change.
///
/// A new event can also go to one of the iPad's own calendars from here, so
/// a person whose new events go to their phone can still pick the family's.
struct PhoneEventEditorSheet: View {
    enum Mode: Identifiable {
        case new(Date)
        case edit(PersonalEvent)

        var id: String {
            switch self {
            case .new(let day): "new|\(day.timeIntervalSinceReferenceDate)"
            case .edit(let event): "edit|\(event.id)"
            }
        }
    }

    @Environment(HouseholdCalendarService.self) private var calendar
    @Environment(\.dismiss) private var dismiss
    let mode: Mode
    @State private var title = ""
    @State private var location = ""
    @State private var isAllDay = false
    @State private var start = Date()
    @State private var end = Date()
    @State private var calendarID = ""
    @State private var error: String?
    @State private var isSaving = false

    init(mode: Mode) {
        self.mode = mode
        switch mode {
        case .new(let day):
            let start = EventKitCalendarBackend.suggestedStart(on: day)
            _start = State(initialValue: start)
            _end = State(initialValue: start.addingTimeInterval(3600))
        case .edit(let event):
            _title = State(initialValue: event.title)
            _location = State(initialValue: event.location ?? "")
            _isAllDay = State(initialValue: event.isAllDay)
            _start = State(initialValue: event.start)
            _end = State(initialValue: max(event.end, event.start))
            _calendarID = State(initialValue: event.calendarID)
        }
    }

    var body: some View {
        SheetScreen(isNew ? "New Event" : "Edit Event") {
            GlassCapsuleButton(isNew ? "Add" : "Save", isProminent: true, action: save)
                .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || calendarID.isEmpty
                          || isSaving || shownEvent?.phoneStatus?.state == .sending)
        } content: {
            Form {
                if let event = shownEvent, let status = event.phoneStatus, let phone = event.phoneDeviceName {
                    statusSection(status, phone: phone)
                }
                Section {
                    TextField("Title", text: $title)
                    TextField("Location", text: $location)
                }
                Section {
                    Toggle("All-day", isOn: $isAllDay)
                    DatePicker("Starts", selection: $start, displayedComponents: isAllDay ? .date : [.date, .hourAndMinute])
                    DatePicker("Ends", selection: $end, in: start..., displayedComponents: isAllDay ? .date : [.date, .hourAndMinute])
                }
                Section {
                    Picker("Calendar", selection: $calendarID) {
                        ForEach(choices) { source in
                            Text(source.phone == nil ? source.title : "\(source.title), \(source.accountName ?? "iPhone")").tag(source.id)
                        }
                    }
                } footer: {
                    Text(footer)
                }
                if let error {
                    Section { Text(error).foregroundStyle(.red) }
                }
            }
        }
        .presentationSizing(.page)
        .onAppear {
            if calendarID.isEmpty { calendarID = calendar.preferredCalendarForNewEvents().flatMap { preferred in
                choices.contains(where: { $0.id == preferred.id }) ? preferred.id : nil
            } ?? choices.first?.id ?? "" }
        }
        // Keeps the end after the start as the start moves, like Apple's editor.
        .onChange(of: start) { old, new in
            if end < new { end = new.addingTimeInterval(max(end.timeIntervalSince(old), 0)) }
        }
    }

    private var isNew: Bool {
        if case .new = mode { return true }
        return false
    }

    /// The event as it shows now, with the state of a change waiting for the phone.
    private var shownEvent: PersonalEvent? {
        guard case .edit(let event) = mode else { return nil }
        return calendar.events(on: event.start).first { $0.id == event.id } ?? event
    }

    /// Where the event may go. A phone event stays on that phone. A new one
    /// may go to the phone's calendars or, where Apple's editor would have
    /// been used, the iPad's own.
    private var choices: [CalendarSource] {
        let writable = calendar.writableCalendars
        if !isNew { return writable.filter { $0.phone != nil } }
        return calendar.eventKitBackend == nil ? writable.filter { $0.phone != nil } : writable
    }

    private var footer: String {
        guard let chosen = choices.first(where: { $0.id == calendarID }), let phone = chosen.phone else {
            return "Saved on this iPad's calendar."
        }
        var sentences = ["Saved on \(phone.deviceName). HomePad wakes it if needed, and the event shows as saving until it is."]
        if case .edit(let event) = mode, event.isRecurring { sentences.append("This changes this day's event only.") }
        return sentences.joined(separator: " ")
    }

    @ViewBuilder
    private func statusSection(_ status: PhoneWriteStatus, phone: String) -> some View {
        Section {
            PhoneChangeLabel(status: status, deviceName: phone).font(.headline)
            if let message = status.message {
                Text(message).foregroundStyle(.secondary)
            }
            if status.state != .sending {
                Button("Try Again", systemImage: "arrow.clockwise") { calendar.retryPhoneChange(status.writeID) }
                Button("Discard Change", systemImage: "trash", role: .destructive) {
                    calendar.discardPhoneChange(status.writeID)
                    dismiss()
                }
            }
        }
    }

    private func save() {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let place = location.trimmingCharacters(in: .whitespacesAndNewlines)
        let draft = EventDraft(title: trimmed, start: start, end: max(end, start), isAllDay: isAllDay,
                               location: place.isEmpty ? nil : place, calendarID: calendarID)
        isSaving = true
        error = nil
        Task {
            defer { isSaving = false }
            do {
                if case .edit(let event) = mode {
                    try calendar.updatePhoneEvent(shownEvent ?? event, with: draft)
                } else {
                    try await calendar.addEvent(draft)
                }
                dismiss()
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}
