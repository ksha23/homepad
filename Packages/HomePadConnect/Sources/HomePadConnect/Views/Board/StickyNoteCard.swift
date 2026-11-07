import HomePadCore
import HomePadUI
import SwiftUI

extension NoteColor {
    /// The fill for a note. System colors so night mode and dark mode stay consistent.
    var color: Color {
        switch self {
        case .yellow: .yellow
        case .orange: .orange
        case .pink: .pink
        case .purple: .purple
        case .blue: .cyan
        case .green: .mint
        }
    }
}

/// How big a sticky note draws: on the board, or in its widget.
enum StickyNoteStyle {
    case board
    case widget

    /// The note's text. The board's is read from across a kitchen.
    var textFont: Font {
        switch self {
        case .board: .system(.title, design: .rounded, weight: .semibold)
        case .widget: .system(.title3, design: .rounded, weight: .semibold)
        }
    }

    /// Who wrote the note.
    var authorFont: Font {
        switch self {
        case .board: .headline
        case .widget: .subheadline.weight(.semibold)
        }
    }

    /// When it changed.
    var timeFont: Font {
        switch self {
        case .board: .body
        case .widget: .subheadline
        }
    }

    /// The byline's fonts.
    var bylineFonts: StickyNoteBylineFonts {
        StickyNoteBylineFonts(author: authorFont, time: timeFont)
    }

    /// The board's text, author and time styles in points at the default
    /// text size, for drawing a board note larger in the composer.
    static let boardPointSizes: (text: CGFloat, author: CGFloat, time: CGFloat) = (28, 17, 17)

    /// Lines of text before an ellipsis. Long notes grow to this, and the
    /// editor shows the rest.
    var lineLimit: Int {
        switch self {
        case .board: 6
        case .widget: 3
        }
    }

    var padding: CGFloat {
        switch self {
        case .board: Theme.Spacing.m
        case .widget: Theme.Spacing.s
        }
    }

    /// Between the byline and the text.
    var spacing: CGFloat {
        switch self {
        case .board: Theme.Spacing.xs
        case .widget: Theme.Spacing.xs / 2
        }
    }

    /// The column width the board and the widget aim for: about 13 characters
    /// of note text a line, like handwriting on a real sticky note. Read it
    /// through `@ScaledMetric`, so columns widen with the text size.
    var idealWidth: CGFloat {
        switch self {
        case .board: 240
        case .widget: 150
        }
    }

    /// A note is at most twice as wide as it is tall, so a one-line note
    /// still looks like a sticky note and not a label.
    static let minimumHeightRatio: CGFloat = 0.5

    /// "5 minutes ago" on the board. The widget's narrow notes say "5m ago",
    /// like a notification, so the name beside it stays whole.
    var timeFormat: Date.RelativeFormatStyle {
        switch self {
        case .board: .relative(presentation: .named)
        case .widget: .relative(presentation: .named, unitsStyle: .narrow)
        }
    }
}

/// One sticky note, as wide as its column and as tall as its text, like a
/// note on a fridge: a short note is small and a long one grows to the
/// style's line cap, then ends with an ellipsis.
struct StickyNoteCard: View {
    @Environment(\.controlCornerRadius) private var cornerRadius
    let note: BoardNote
    var style: StickyNoteStyle = .board
    /// Fewer lines than the style allows, for a widget short of room.
    var lineLimit: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: style.spacing) {
            StickyNoteByline(author: note.author, date: note.modifiedAt, isPinned: note.isPinned, style: style)
            Text(note.text)
                .font(style.textFont)
                .lineLimit(lineLimit ?? style.lineLimit)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(style.padding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .stickyNotePaper(note.color, cornerRadius: cornerRadius)
        .accessibilityElement(children: .combine)
    }
}

/// The fonts of a note's byline: who wrote it, and the pin and time.
struct StickyNoteBylineFonts {
    var author: Font
    var time: Font
}

/// The line over a note's text: a pin, who wrote it and when it changed.
/// The time stays whole and a long name gives way.
struct StickyNoteByline: View {
    let author: String
    /// Nil for a note still being written.
    var date: Date?
    var isPinned = false
    var style: StickyNoteStyle = .board
    /// Fonts in place of the style's, for the composer's larger copy of a board note.
    var fonts: StickyNoteBylineFonts?

    var body: some View {
        let fonts = fonts ?? style.bylineFonts
        HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.xs) {
            if isPinned {
                Image(systemName: "pin.fill")
                    .font(fonts.time)
                    .accessibilityLabel("Pinned")
            }
            Text(author)
                .font(fonts.author)
                .lineLimit(1)
            // The stack's spacing on both sides already keeps the name and time apart.
            Spacer(minLength: 0)
            if let date {
                Text(date, format: style.timeFormat)
                    .font(fonts.time)
                    .lineLimit(1)
                    .layoutPriority(1)
            }
        }
        .opacity(0.75)
    }
}

extension View {
    /// The paper of a sticky note: its color, black text and the note's corners.
    func stickyNotePaper(_ color: NoteColor, cornerRadius: CGFloat) -> some View {
        modifier(StickyNotePaper(color: color, cornerRadius: cornerRadius))
    }
}

private struct StickyNotePaper: ViewModifier {
    @Environment(\.displayCondition) private var condition
    let color: NoteColor
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .foregroundStyle(.black)
            // The night tint keeps only red, which turned blue and green paper
            // black under black text. At night every note is white paper, so
            // each turns the same bright red the yellow and pink notes do.
            .background(condition == .night ? Color.white.gradient : color.color.gradient,
                        in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .nightModeAware()
    }
}

/// The fixed palette as tappable swatches: one row of six, or rows of
/// `columns` for a narrow column beside the note being written.
struct NoteColorPicker: View {
    @Binding var selection: NoteColor
    /// Swatches in a row.
    var columns = NoteColor.allCases.count

    var body: some View {
        Grid(horizontalSpacing: Theme.Spacing.m, verticalSpacing: Theme.Spacing.m) {
            ForEach(rows, id: \.self) { row in
                GridRow {
                    ForEach(row, id: \.self) { swatch($0) }
                }
            }
        }
    }

    private var rows: [[NoteColor]] {
        let all = NoteColor.allCases
        let count = max(columns, 1)
        return stride(from: 0, to: all.count, by: count).map { Array(all[$0..<min($0 + count, all.count)]) }
    }

    private func swatch(_ color: NoteColor) -> some View {
        Button {
            selection = color
        } label: {
            Circle()
                .fill(color.color.gradient)
                .frame(width: Theme.Size.minTapTarget, height: Theme.Size.minTapTarget)
                .overlay {
                    if color == selection {
                        Circle().strokeBorder(.primary, lineWidth: 3).padding(-5)
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(color.displayName)
        .accessibilityAddTraits(color == selection ? .isSelected : [])
    }
}
