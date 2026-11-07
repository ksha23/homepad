import HomePadCore
import HomePadUI
import SwiftUI

/// "TUE 20" in small caps, the date complication used by the analog faces.
struct DateBadge: View {
    let date: Date
    let palette: FacePalette

    var body: some View {
        HStack(spacing: Theme.Spacing.xs) {
            Text(date, format: .dateTime.weekday(.abbreviated)).foregroundStyle(palette.accent)
            Text(date, format: .dateTime.day()).foregroundStyle(palette.ink)
        }
        .textCase(.uppercase)
    }
}
