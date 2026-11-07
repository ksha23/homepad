import Foundation
import HomePadCore

/// Assistant tools contributed by Connect: intercom, the Family Board and Shortcuts.
@MainActor
enum ConnectTools {
    static func make(runtime: ConnectRuntime) -> [AssistantTool] {
        [announce(runtime), addNote(runtime), readBoard(runtime), runShortcut(runtime)]
    }

    private static func announce(_ runtime: ConnectRuntime) -> AssistantTool {
        AssistantTool(
            name: "intercom_announce",
            description: "Speak a short announcement on other HomePads in the house, for example \"Dinner is ready\". Optionally only in one room.",
            parameters: Schema.object([
                "text": Schema.string("What to announce."),
                "room": Schema.string("Room of the HomePad to announce on, for example Kitchen. Omit for every room."),
            ], required: ["text"])
        ) { [weak runtime] arguments in
            guard let runtime, let text = arguments["text"]?.stringValue else { return "Nothing to announce." }
            try await runtime.intercom.announce(text: text, audio: nil, to: arguments["room"]?.stringValue)
            return "Announced to \(arguments["room"]?.stringValue ?? "every room")."
        }
    }

    private static func addNote(_ runtime: ConnectRuntime) -> AssistantTool {
        AssistantTool(
            name: "board_add_note",
            description: "Pin a sticky note to the household's Family Board.",
            parameters: Schema.object([
                "text": Schema.string("The note."),
                "color": Schema.string("Note color.", enumValues: NoteColor.allCases.map(\.rawValue)),
            ], required: ["text"])
        ) { [weak runtime] arguments in
            let color = arguments["color"]?.stringValue.flatMap(NoteColor.init(rawValue:)) ?? .yellow
            guard let note = runtime?.board.add(arguments["text"]?.stringValue ?? "", color: color) else { return "The note was empty." }
            return "Added \"\(note.text)\" to the Family Board."
        }
    }

    private static func readBoard(_ runtime: ConnectRuntime) -> AssistantTool {
        AssistantTool(name: "board_read_notes", description: "Read the notes on the household's Family Board.") { [weak runtime] _ in
            let notes = runtime?.board.visibleNotes ?? []
            guard !notes.isEmpty else { return "The Family Board is empty." }
            return notes.map { "- \($0.text) (from \($0.author))" }.joined(separator: "\n")
        }
    }

    private static func runShortcut(_ runtime: ConnectRuntime) -> AssistantTool {
        AssistantTool(
            name: "run_shortcut",
            description: "Run one of the household's saved Apple Shortcuts by name.",
            parameters: Schema.object(["name": Schema.string("The shortcut name exactly as saved in HomePad's Shortcuts app.")], required: ["name"])
        ) { [weak runtime] arguments in
            guard let runtime, let name = arguments["name"]?.stringValue else { return "Which shortcut?" }
            return await runtime.shortcuts.run(name) ? "Running \(name)." : (runtime.shortcuts.lastError ?? "Could not run \(name).")
        }
    }
}
