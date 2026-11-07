import HomePadCore
import HomePadUI
import SwiftUI

/// The Family Board: sticky notes in columns, each as tall as its text. Used
/// by the HomePad app and the companion tab.
///
/// Notes keep a sticky note's size however many there are. A few leave the
/// rest of the board empty, many scroll. Columns aim for
/// `StickyNoteStyle.board.idealWidth`, so landscape holds four or five.
struct BoardView: View {
    @Environment(ConnectRuntime.self) private var connect
    @Binding var isComposing: Bool
    @State private var editing: BoardNote?
    @ScaledMetric(relativeTo: .title) private var noteWidth = StickyNoteStyle.board.idealWidth

    var body: some View {
        Group {
            if connect.board.visibleNotes.isEmpty {
                EmptyStateView(
                    "No Notes Yet",
                    message: "Leave a note for the household. It shows up on every HomePad, iPhone and Mac.",
                    systemImage: "note.text",
                    actionTitle: "New Note"
                ) { isComposing = true }
            } else {
                ScrollView {
                    MasonryLayout(idealColumnWidth: noteWidth, spacing: Theme.Spacing.m,
                                  minimumHeightRatio: StickyNoteStyle.minimumHeightRatio) {
                        ForEach(connect.board.visibleNotes) { note in
                            StickyNoteCard(note: note)
                                .onTapGesture { editing = note }
                                .contextMenu { menu(for: note) }
                        }
                    }
                    // A note from another device fades in and the rest make room.
                    .animation(Theme.Motion.settle, value: connect.board.visibleNotes.map(\.id))
                    .padding(.bottom, Theme.Spacing.l)
                }
            }
        }
        .sheet(isPresented: $isComposing) { NoteEditorSheet() }
        .sheet(item: $editing) { NoteEditorSheet(existing: $0) }
        #if DEBUG
        .task { openDemoEditor() }
        #endif
    }

    #if DEBUG
    /// `-ConnectDemoEditor`, for screenshots of the composer and the editor.
    private func openDemoEditor() {
        switch DemoData.editorOnLaunch {
        case "new": isComposing = true
        case "first": editing = connect.board.visibleNotes.first
        default: break
        }
    }
    #endif

    @ViewBuilder
    private func menu(for note: BoardNote) -> some View {
        Button(note.isPinned ? "Unpin" : "Pin", systemImage: note.isPinned ? "pin.slash" : "pin") {
            connect.board.update(note.id, isPinned: !note.isPinned)
        }
        ShareLink(item: note.text)
        Button("Delete", systemImage: "trash", role: .destructive) {
            connect.board.delete(note.id)
        }
    }
}

/// The Family Board app on a HomePad.
struct BoardAppView: View {
    @State private var isComposing = false

    var body: some View {
        AppScreen("Family Board", accessory: {
            GlassCapsuleButton("New Note", systemImage: "plus") { isComposing = true }
        }) {
            BoardView(isComposing: $isComposing)
        }
    }
}

/// Widget with the newest notes, for the Home Screen and the faces. Notes are
/// small sticky notes in columns, like the board's, and the widget shows as
/// many whole notes as its tile holds, so a tall tile on a face fills with
/// notes and a short one never spills. The header counts the rest, and gives
/// way when it would cost a note. Medium and large differ only in their frame.
struct BoardWidgetView: View {
    @Environment(ConnectRuntime.self) private var connect
    @ScaledMetric(relativeTo: .title3) private var noteWidth = StickyNoteStyle.widget.idealWidth

    /// More than the largest tile holds.
    private static let maxNotes = 12

    var body: some View {
        let notes = connect.board.visibleNotes
        GlassTile {
            if notes.isEmpty {
                header(more: 0)
                Text("No notes").font(.title3).foregroundStyle(.secondary)
            } else {
                ViewThatFits(in: .vertical) {
                    ForEach(Array((1...min(notes.count, Self.maxNotes)).reversed()), id: \.self) { count in
                        board(notes, count: count, showsHeader: true)
                        board(notes, count: count, showsHeader: false)
                    }
                    board(notes, count: 1, showsHeader: false, lineLimit: 1)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                // A note from another device fades in and the rest make room.
                .animation(Theme.Motion.settle, value: notes.map(\.id))
            }
        }
    }

    /// The widget's name and how many notes did not fit.
    private func header(more: Int) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.xs) {
            Label("Family Board", systemImage: "note.text").font(.headline)
            if more > 0 {
                Text("· \(more) more").font(.subheadline)
            }
        }
        .foregroundStyle(.secondary)
        .lineLimit(1)
    }

    /// The first `count` notes, with or without the header.
    private func board(_ notes: [BoardNote], count: Int, showsHeader: Bool, lineLimit: Int? = nil) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            if showsHeader { header(more: notes.count - count) }
            MasonryLayout(idealColumnWidth: noteWidth, spacing: Theme.Spacing.controlGap,
                          minimumHeightRatio: StickyNoteStyle.minimumHeightRatio) {
                ForEach(notes.prefix(count)) { StickyNoteCard(note: $0, style: .widget, lineLimit: lineLimit) }
            }
        }
    }
}
