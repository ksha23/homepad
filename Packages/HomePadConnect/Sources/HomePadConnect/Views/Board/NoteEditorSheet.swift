import HomePadCore
import HomePadUI
import SwiftUI

/// Write a new note or change an existing one. The sheet's header has Post
/// (Save for an existing note) beside the close button, and Post stays dimmed
/// while the note is empty. Under it, `NoteComposer` fits the note and its
/// options in the room above the keyboard. The note being written is a
/// larger copy of the one on the board: the same paper, byline and text, so
/// what is typed looks like what everyone will see.
struct NoteEditorSheet: View {
    @Environment(ConnectRuntime.self) private var connect
    @Environment(\.dismiss) private var dismiss
    let existing: BoardNote?
    @State private var text: String
    @State private var color: NoteColor
    @State private var isPinned: Bool
    @FocusState private var focused: Bool

    init(existing: BoardNote? = nil) {
        self.existing = existing
        _text = State(initialValue: existing?.text ?? "")
        _color = State(initialValue: existing?.color ?? .yellow)
        _isPinned = State(initialValue: existing?.isPinned ?? false)
    }

    var body: some View {
        SheetScreen(existing == nil ? "New Note" : "Edit Note") {
            GlassCapsuleButton(existing == nil ? "Post" : "Save", isProminent: true, action: save)
                .disabled(isEmpty)
                // Command-Return posts from a hardware keyboard.
                .keyboardShortcut(.return, modifiers: .command)
        } content: {
            NoteComposer(
                text: $text, color: $color, isPinned: $isPinned,
                author: existing?.author ?? connect.board.author, date: existing?.modifiedAt,
                onDelete: existing.map { note in { delete(note) } }, focus: $focused
            )
            .padding([.horizontal, .bottom], Theme.Spacing.l)
        }
        .onAppear { focused = existing == nil }
        // On iPhone the sheet takes the whole height, so the keyboard leaves the composer room.
        .presentationDetents([.large])
    }

    private var isEmpty: Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func save() {
        if let existing {
            connect.board.update(existing.id, text: text, color: color, isPinned: isPinned)
        } else if let note = connect.board.add(text, color: color), isPinned {
            connect.board.update(note.id, isPinned: true)
        }
        dismiss()
    }

    private func delete(_ note: BoardNote) {
        connect.board.delete(note.id)
        dismiss()
    }
}
