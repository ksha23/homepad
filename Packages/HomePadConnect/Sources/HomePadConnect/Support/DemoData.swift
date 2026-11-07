#if DEBUG
import Foundation
import HomePadCore

/// Sample notes and shortcuts for simulator screenshots.
/// Debug builds only, and only with the launch argument `-ConnectDemoData YES`.
/// `-ConnectDemoNotes <n>` puts exactly the first n sample notes on the board
/// at every launch, to check the board with one note, a few or many.
/// `-ConnectDemoEditor new` opens the note composer when the board appears,
/// and `first` opens the first note's editor. `-ConnectDemoArrival <seconds>`
/// adds a note that long after launch, as if from another device, to watch
/// it arrive.
@MainActor
enum DemoData {
    static var isEnabled: Bool { UserDefaults.standard.bool(forKey: "ConnectDemoData") }

    /// The editor `-ConnectDemoEditor` asks for: "new", "first" or nil.
    static var editorOnLaunch: String? {
        isEnabled ? UserDefaults.standard.string(forKey: "ConnectDemoEditor") : nil
    }

    /// How many sample notes `-ConnectDemoNotes` asks for, or nil without it.
    private static var noteCount: Int? {
        UserDefaults.standard.object(forKey: "ConnectDemoNotes") == nil
            ? nil : max(UserDefaults.standard.integer(forKey: "ConnectDemoNotes"), 0)
    }

    static func seed(_ runtime: ConnectRuntime) {
        guard isEnabled else { return }
        if let count = noteCount {
            runtime.board.replaceForDemo(notes(count))
        } else if runtime.board.visibleNotes.isEmpty {
            runtime.board.replaceForDemo(notes(8))
        }
        if runtime.shortcuts.names.isEmpty {
            ["Leaving Home", "Movie Night", "Bedtime Story", "Morning Briefing"].forEach(runtime.shortcuts.add)
        }
        if let delay = arrivalDelay {
            Task {
                try? await Task.sleep(for: .seconds(delay))
                let arriving = BoardNote(text: "Leftover pizza in the fridge", color: .green, author: "Jordan",
                                         modifiedBy: "demo")
                runtime.board.replaceForDemo(runtime.board.notes + [arriving])
            }
        }
    }

    /// Seconds after launch for `-ConnectDemoArrival`, or nil without it.
    private static var arrivalDelay: Double? {
        UserDefaults.standard.object(forKey: "ConnectDemoArrival") == nil
            ? nil : max(UserDefaults.standard.double(forKey: "ConnectDemoArrival"), 0)
    }

    /// Notes of every length, from two words to more than a note shows, by
    /// the demo household's people, newest first after the pinned one.
    private static let samples: [(author: String, text: String, color: NoteColor, minutesAgo: Double, isPinned: Bool)] = [
        ("Sam", "Dentist Thursday 3:30. Leave by 3!", .pink, 120, true),
        ("Alex", "Out of oat milk and coffee beans", .yellow, 5, false),
        ("Jordan", "Feed Biscuit", .orange, 12, false),
        ("Alex", "Grandma lands Friday at 6:40 PM, terminal 2. Can someone pick her up? I have practice until 7.",
         .purple, 40, false),
        ("Sam", "Plumber coming Saturday morning", .blue, 65, false),
        ("Alex", "Great job on the science fair, Jordan!", .green, 180, false),
        ("Jordan", "Trash out tonight", .yellow, 300, false),
        ("Sam", "Pay the water bill by the 25th. The card on autopay expired, so update it first, then check that the payment went through. The login is in the shared passwords.",
         .green, 1_500, false),
        ("Jordan", "Back by 6", .orange, 1_600, false),
        ("Alex", "Wi-Fi password is on the fridge door", .blue, 2_900, false),
        ("Sam", "Movie night Friday. Jordan picks!", .pink, 4_400, false),
        ("Jordan", "Thanks for the cookies!", .purple, 5_800, false),
    ]

    private static func notes(_ count: Int, now: Date = Date()) -> [BoardNote] {
        samples.prefix(count).map { sample in
            let date = now.addingTimeInterval(-sample.minutesAgo * 60)
            return BoardNote(text: sample.text, color: sample.color, author: sample.author, isPinned: sample.isPinned,
                             createdAt: date, modifiedBy: "demo")
        }
    }
}
#endif
