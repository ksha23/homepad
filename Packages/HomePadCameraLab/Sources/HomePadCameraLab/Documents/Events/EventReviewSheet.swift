import HomePadCore
import HomePadUI
import SwiftUI

/// The events found on a scanned page, for the person to check before they go
/// to a calendar: each one's title, start, end, all day and place can be
/// changed, and a switch says whether to add it. The calendar is picked once
/// for all of them. Add is the sheet's one action.
struct EventReviewSheet: View {
    @Bindable var review: EventScanReview

    var body: some View {
        // A short title, so the action beside it keeps its words.
        SheetScreen("Events") {
            GlassCapsuleButton(addTitle, systemImage: "calendar.badge.plus", isProminent: true) {
                Task { await review.add() }
            }
            .disabled(!review.canAdd)
        } content: {
            Form {
                if !review.isRecognized {
                    Section {
                        Label("Adding events needs someone HomePad recognizes. Look at the screen so it can see who you are.",
                              systemImage: "person.crop.circle.badge.questionmark")
                            .font(.body)
                    }
                }
                if !review.hasCalendarAccess {
                    Section {
                        PermissionPrompt(feature: "Calendar", systemImage: "calendar",
                                         reason: "HomePad adds the events you choose to a calendar on this iPad.",
                                         isDenied: review.accessWasRefused, style: .row) {
                            await review.requestCalendarAccess()
                        }
                    }
                }
                calendarSection
                if review.events.isEmpty {
                    emptySection
                }
                ForEach($review.events) { $event in
                    ScannedEventSection(event: $event)
                }
                if review.canAskAssistant {
                    assistantSection
                }
                if let status {
                    Section { Text(status).font(.body) }
                }
            }
        }
        .task(id: review.calendarsKey) { await review.loadCalendars() }
    }

    /// "Add 2 to Calendar", the events switched on.
    private var addTitle: String {
        switch review.phase {
        case .adding: return "Adding"
        default: return review.selectedCount == 0 ? "Add to Calendar" : "Add \(review.selectedCount) to Calendar"
        }
    }

    private var calendarSection: some View {
        Section {
            if review.calendars.isEmpty {
                Text(review.hasCalendarAccess ? "There is no calendar here you can add to." : "Calendars show once access is allowed.")
                    .foregroundStyle(.secondary)
            } else {
                Picker("Calendar", selection: $review.calendarID) {
                    ForEach(review.calendars) { calendar in
                        Text(calendar.title).tag(Optional(calendar.id))
                    }
                }
            }
        } footer: {
            Text(review.isRecognized
                 ? "Your calendars and the ones shared with everyone."
                 : "Only calendars shared with everyone show until someone is recognized.")
        }
    }

    private var emptySection: some View {
        Section {
            Text("No dates were found on the page.")
            Button("Add an Event by Hand", systemImage: "plus") { review.addBlankEvent() }
        }
    }

    private var assistantSection: some View {
        Section {
            Button {
                Task { await review.readWithAssistant() }
            } label: {
                HStack(spacing: Theme.Spacing.s) {
                    Label("Read Again with \(review.assistantName)", systemImage: "sparkles")
                    if review.phase == .reading { ProgressView() }
                }
            }
            .disabled(review.phase == .reading || review.text.isEmpty)
        } footer: {
            Text(review.readBy.map { "Read by \($0) from the recognized text only." }
                 ?? "Found on this iPad. \(review.assistantName) gets only the recognized text, never the photo.")
        }
    }

    private var status: String? {
        switch review.phase {
        case .added(let count): "Added \(count) \(count == 1 ? "event" : "events") to \(calendarTitle)."
        case .failed(let message): message
        case .reviewing, .reading, .adding: nil
        }
    }

    private var calendarTitle: String {
        review.calendars.first { $0.id == review.calendarID }?.title ?? "the calendar"
    }
}

/// One found event's fields, editable, with the words it came from under them.
private struct ScannedEventSection: View {
    @Binding var event: ScannedEvent

    var body: some View {
        Section {
            Toggle("Add This Event", isOn: $event.isSelected)
            TextField("Title", text: $event.title)
                .font(.title3.weight(.semibold))
            Toggle("All Day", isOn: allDay)
            DatePicker("Starts", selection: start, displayedComponents: components)
            DatePicker("Ends", selection: $event.end, in: event.start..., displayedComponents: components)
            TextField("Location", text: $event.location)
        } footer: {
            if !event.source.isEmpty {
                Text("From the page: \(event.source)")
                    .lineLimit(3)
            }
        }
    }

    private var components: DatePickerComponents {
        event.isAllDay ? [.date] : [.date, .hourAndMinute]
    }

    /// Moving the start moves the end with it, as Calendar does.
    private var start: Binding<Date> {
        Binding(get: { event.start }, set: { newStart in
            let length = event.end.timeIntervalSince(event.start)
            event.start = newStart
            event.end = newStart.addingTimeInterval(max(0, length))
        })
    }

    /// All day keeps the days. Timed starts at the next whole hour of the
    /// first day, like a new event in Calendar, and lasts an hour.
    private var allDay: Binding<Bool> {
        Binding(get: { event.isAllDay }, set: { isAllDay in
            let calendar = Calendar.current
            if isAllDay {
                event.start = calendar.startOfDay(for: event.start)
                event.end = max(calendar.startOfDay(for: event.end), event.start)
            } else {
                let hour = calendar.component(.hour, from: Date()) + 1
                let start = calendar.date(bySettingHour: min(hour, 23), minute: 0, second: 0, of: event.start) ?? event.start
                event.start = start
                event.end = start.addingTimeInterval(FlyerEventExtractor.defaultLength)
            }
            event.isAllDay = isAllDay
        })
    }
}
