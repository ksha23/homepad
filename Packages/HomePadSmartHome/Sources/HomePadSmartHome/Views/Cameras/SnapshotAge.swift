import HomePadUI
import SwiftUI

/// How old a camera snapshot is, the way HomeView labels one: "Now" for the
/// first minute, then "2m ago", "1h ago" and "3d ago".
enum SnapshotAge {
    static func text(capturedAt: Date, now: Date = Date(), locale: Locale = .autoupdatingCurrent) -> String {
        guard now.timeIntervalSince(capturedAt) >= 60 else { return "Now" }
        var style = Date.AnchoredRelativeFormatStyle(anchor: capturedAt, presentation: .numeric, unitsStyle: .narrow)
        style.locale = locale
        return style.format(now)
    }
}

/// When the snapshot a still camera view shows was taken. Still views set it,
/// and `CameraTile` reads it to label the snapshot's age.
struct SnapshotDateKey: PreferenceKey {
    static let defaultValue: Date? = nil

    static func reduce(value: inout Date?, nextValue: () -> Date?) {
        value = nextValue() ?? value
    }
}

/// "2m ago" in white over a snapshot. It changes once a minute, counted from
/// when the snapshot was taken, and is otherwise still.
struct SnapshotAgeLabel: View {
    let capturedAt: Date

    var body: some View {
        TimelineView(.periodic(from: capturedAt, by: 60)) { context in
            Text(SnapshotAge.text(capturedAt: capturedAt, now: context.date))
                .font(.headline)
                .foregroundStyle(.white)
                .wallpaperLabelShadow()
        }
    }
}
