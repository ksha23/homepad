import HomePadUI
import SwiftUI

/// Stand-in for Apple's calendar chooser while demo data is on, since
/// `EKCalendarChooser` can only list real EventKit calendars. Save applies
/// the checked calendars, and the close button leaves them as they were.
struct DemoCalendarChooser: View {
    let title: String
    let sources: [CalendarSource]
    let onFinish: (Set<String>?) -> Void
    @State private var selection: Set<String>

    init(title: String, sources: [CalendarSource], selectedIDs: Set<String>, onFinish: @escaping (Set<String>?) -> Void) {
        self.title = title
        self.sources = sources
        self.onFinish = onFinish
        _selection = State(initialValue: selectedIDs)
    }

    var body: some View {
        SheetScreen(title, onClose: { onFinish(nil) }) {
            GlassCapsuleButton("Save", isProminent: true) { onFinish(selection) }
        } content: {
            List(sources) { source in
                Button {
                    if selection.contains(source.id) { selection.remove(source.id) } else { selection.insert(source.id) }
                } label: {
                    HStack {
                        Circle().fill(Color(hex: source.colorHex)).frame(width: 12, height: 12)
                        Text(source.title).foregroundStyle(.primary)
                        Spacer()
                        if selection.contains(source.id) { Image(systemName: "checkmark").foregroundStyle(.tint) }
                    }
                }
            }
        }
    }
}
