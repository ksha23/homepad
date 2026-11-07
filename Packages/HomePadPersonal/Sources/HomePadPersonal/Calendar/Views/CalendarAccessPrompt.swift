import HomePadUI
import SwiftUI

/// Asks for calendar access, or explains "Add Events Only" access, under
/// which HomePad can save events but cannot read a single one.
struct CalendarAccessPrompt: View {
    @Environment(HouseholdCalendarService.self) private var calendar
    var style: PermissionPrompt.Style = .page

    var body: some View {
        if calendar.eventAccessState == .writeOnly {
            PermissionPrompt(
                "HomePad Can Only Add Events",
                message: "Calendar access for HomePad is set to Add Events Only, so no events can show. In the Settings app, set it to Full Access, then come back.",
                systemImage: "calendar", state: .denied, style: style
            )
        } else {
            PermissionPrompt(feature: "Calendar", systemImage: "calendar",
                             reason: "See the household's events and add new ones by touch or voice. Nothing leaves this iPad.",
                             isDenied: calendar.isEventAccessDenied, style: style) { _ = await calendar.requestAccess() }
        }
    }
}
