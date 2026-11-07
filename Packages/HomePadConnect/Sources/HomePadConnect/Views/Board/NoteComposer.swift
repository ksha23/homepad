import HomePadCore
import HomePadUI
import SwiftUI

/// The note being written and its options, fitted to the room the sheet has
/// above the keyboard. The note is the hero: a larger copy of the sticky it
/// becomes, in the board's paper, fonts and byline.
///
/// - When the room is wider than tall, as in landscape with the keyboard up,
///   the options are a narrow column beside the note: the colors in rows of
///   three, Pin to Top and Delete Note.
/// - Otherwise, as in portrait or without an on-screen keyboard, they sit
///   under the note: the colors in one row, then the buttons.
///
/// The note is scaled to fill the rest (`NoteDraftScale`) and shrinks as
/// lines are added, so the whole note stays in view. One layout holds both
/// arrangements, so the text field keeps its focus, and the keyboard stays
/// up, when the arrangement changes.
struct NoteComposer: View {
    @Binding var text: String
    @Binding var color: NoteColor
    @Binding var isPinned: Bool
    let author: String
    /// When the note last changed. Nil for a note still being written.
    let date: Date?
    /// Deletes the note. Nil for a new note.
    let onDelete: (() -> Void)?
    let focus: FocusState<Bool>.Binding

    @ScaledMetric(relativeTo: .title) private var noteWidth = StickyNoteStyle.board.idealWidth
    @ScaledMetric(relativeTo: .title) private var textSize = StickyNoteStyle.boardPointSizes.text
    @ScaledMetric(relativeTo: .headline) private var authorSize = StickyNoteStyle.boardPointSizes.author
    @ScaledMetric(relativeTo: .body) private var timeSize = StickyNoteStyle.boardPointSizes.time
    @State private var metrics = NoteDraftMetrics()
    @State private var optionsSize = CGSize.zero

    static let prompt = "Write a note for everyone"
    /// The options go beside the note when the room is at least this much wider than tall.
    static let besideRatio: CGFloat = 1.2

    var body: some View {
        GeometryReader { proxy in
            let isBeside = proxy.size.width >= proxy.size.height * Self.besideRatio
            let room = noteRoom(in: proxy.size, isBeside: isBeside)
            let layout = isBeside
                ? AnyLayout(HStackLayout(alignment: .top, spacing: Theme.Spacing.l))
                : AnyLayout(VStackLayout(spacing: Theme.Spacing.l))
            layout {
                note(in: room)
                    .frame(width: room.width, alignment: isBeside ? .center : .top)
                options(isColumn: isBeside, height: proxy.size.height)
                    .onGeometryChange(for: CGSize.self) { $0.size } action: { optionsSize = $0 }
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
        }
        .background { measurement }
    }

    /// The room left for the note beside or above the options.
    private func noteRoom(in size: CGSize, isBeside: Bool) -> CGSize {
        if isBeside {
            CGSize(width: max(0, size.width - optionsSize.width - Theme.Spacing.l), height: size.height)
        } else {
            CGSize(width: size.width, height: max(0, size.height - optionsSize.height - Theme.Spacing.l))
        }
    }

    private var draftScale: NoteDraftScale {
        NoteDraftScale(width: noteWidth, padding: StickyNoteStyle.board.padding,
                       spacing: StickyNoteStyle.board.spacing, metrics: metrics)
    }

    private func note(in room: CGSize) -> some View {
        let sizing = draftScale
        let scale = sizing.scale(in: room)
        return NoteDraftCard(
            text: $text, color: color, author: author, date: date, isPinned: isPinned,
            textFont: textFont(scale), bylineFonts: bylineFonts(scale),
            width: noteWidth * scale, padding: sizing.padding * scale, spacing: sizing.spacing * scale,
            maxLines: sizing.maxLines(in: room, scale: scale), focus: focus
        )
    }

    @ViewBuilder
    private func options(isColumn: Bool, height: CGFloat) -> some View {
        let options = NoteOptions(color: $color, isPinned: $isPinned, onDelete: onDelete, isColumn: isColumn)
        if isColumn {
            // Scrolls rather than run under the keyboard if the room is shorter still.
            ScrollView { options }
                .scrollBounceBehavior(.basedOnSize)
                .scrollIndicators(.hidden)
                .fixedSize(horizontal: true, vertical: false)
                .frame(maxHeight: height, alignment: .top)
        } else {
            options
        }
    }

    // MARK: Type

    /// The board's note text, `scale` times as large.
    private func textFont(_ scale: CGFloat) -> Font {
        .system(size: textSize * scale, weight: .semibold, design: .rounded)
    }

    /// The board's byline, `scale` times as large.
    private func bylineFonts(_ scale: CGFloat) -> StickyNoteBylineFonts {
        StickyNoteBylineFonts(author: .system(size: authorSize * scale, weight: .semibold),
                              time: .system(size: timeSize * scale))
    }

    /// The note at the board's size, never shown: how tall its byline, its
    /// text and one line are, which sets the scale. It depends only on the
    /// text, so measuring it never moves what it measures.
    private var measurement: some View {
        let font = textFont(1)
        return VStack(alignment: .leading, spacing: 0) {
            StickyNoteByline(author: author, date: date, isPinned: isPinned, fonts: bylineFonts(1))
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { metrics.byline = $0 }
            // A text field shows the empty line after a return, and a text does not.
            Text(text.isEmpty ? Self.prompt : text.hasSuffix("\n") ? text + " " : text)
                .font(font)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { metrics.text = $0 }
            Text(verbatim: "A")
                .font(font)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { metrics.line = $0 }
        }
        .frame(width: max(0, noteWidth - 2 * StickyNoteStyle.board.padding), alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .hidden()
        .accessibilityHidden(true)
    }
}

/// The note being written: the board's sticky note at a larger size, with
/// the text field where the note's text goes.
private struct NoteDraftCard: View {
    @Binding var text: String
    let color: NoteColor
    let author: String
    let date: Date?
    let isPinned: Bool
    let textFont: Font
    let bylineFonts: StickyNoteBylineFonts
    let width: CGFloat
    let padding: CGFloat
    let spacing: CGFloat
    /// Lines before the text scrolls inside the note.
    let maxLines: Int
    let focus: FocusState<Bool>.Binding

    var body: some View {
        VStack(alignment: .leading, spacing: spacing) {
            StickyNoteByline(author: author, date: date, isPinned: isPinned, fonts: bylineFonts)
            TextField(text: $text, prompt: Text(NoteComposer.prompt).foregroundStyle(.black.opacity(0.4)), axis: .vertical) {
                Text("Note")
            }
            .font(textFont)
            .lineLimit(1...maxLines)
            .focused(focus)
            .accessibilityIdentifier("board.noteText")
        }
        .padding(padding)
        .frame(width: width, alignment: .topLeading)
        .frame(minHeight: width * StickyNoteStyle.minimumHeightRatio, alignment: .topLeading)
        .stickyNotePaper(color, cornerRadius: Theme.Radius.card)
    }
}

/// The note's color, the pin and Delete Note: a narrow column beside the
/// note, or rows under it.
private struct NoteOptions: View {
    @Binding var color: NoteColor
    @Binding var isPinned: Bool
    let onDelete: (() -> Void)?
    let isColumn: Bool

    var body: some View {
        if isColumn {
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                NoteColorPicker(selection: $color, columns: 3)
                pin
                delete
            }
            // The selected swatch's ring reaches past its circle.
            .padding(Theme.Spacing.xs)
        } else {
            VStack(spacing: Theme.Spacing.m) {
                NoteColorPicker(selection: $color)
                HStack(spacing: Theme.Spacing.s) {
                    pin
                    delete
                }
            }
            .padding(Theme.Spacing.xs)
        }
    }

    /// Lit while the note is pinned, like Shuffle in Up Next: filled with the
    /// primary color, white in Dark and black in Light.
    private var pin: some View {
        GlassCapsuleButton("Pin to Top", systemImage: isPinned ? "pin.fill" : "pin", size: .regular,
                           isProminent: isPinned, tint: .primary) {
            isPinned.toggle()
        }
        .accessibilityAddTraits(isPinned ? .isSelected : [])
    }

    @ViewBuilder
    private var delete: some View {
        if let onDelete {
            Button(role: .destructive, action: onDelete) {
                Label("Delete Note", systemImage: "trash").foregroundStyle(.red)
            }
            .buttonStyle(.glassCapsule(size: .regular))
        }
    }
}

/// What the composer measures of the note being written at the board's
/// size, in points: its byline, its text and one line of text.
struct NoteDraftMetrics: Equatable {
    var byline: CGFloat = 0
    var text: CGFloat = 0
    var line: CGFloat = 0
}

/// How large the composer draws the note being written. It is the board's
/// note magnified: a board column wide, in the board's fonts, times a scale,
/// so its lines break where they will on the board. The scale fills the room
/// the composer has, up to `range.upperBound`, and shrinks as lines are added
/// so the whole note stays in view. At `range.lowerBound` the text scrolls
/// inside the note instead.
struct NoteDraftScale {
    static let range: ClosedRange<CGFloat> = 0.8...1.6

    /// The note's width at the board's size.
    let width: CGFloat
    /// Around the byline and text, at the board's size.
    let padding: CGFloat
    /// Between the byline and the text, at the board's size.
    let spacing: CGFloat
    let metrics: NoteDraftMetrics

    /// Everything but the text, at the board's size.
    var chrome: CGFloat {
        padding * 2 + metrics.byline + spacing
    }

    /// The note's height at the board's size: at least half its width, like a note on the board.
    var height: CGFloat {
        max(chrome + metrics.text, width * StickyNoteStyle.minimumHeightRatio)
    }

    /// The scale at which the whole note fits in `room`, kept within `range`.
    func scale(in room: CGSize) -> CGFloat {
        guard width > 0, height > 0 else { return 1 }
        let fit = min(room.width / width, room.height / height)
        return min(max(fit, Self.range.lowerBound), Self.range.upperBound)
    }

    /// The lines of text the note shows at `scale` in `room` before its text scrolls.
    func maxLines(in room: CGSize, scale: CGFloat) -> Int {
        guard metrics.line > 0, scale > 0 else { return 1 }
        let lines = (room.height - chrome * scale) / (metrics.line * scale)
        // A hair over a whole line, so a note scaled to fit exactly keeps its last line.
        return max(1, Int((lines + 0.001).rounded(.down)))
    }
}
