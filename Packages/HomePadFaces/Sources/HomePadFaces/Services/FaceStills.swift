import HomePadCore
import Observation
import SwiftUI
import UIKit

/// Pictures of faces for the cards that show them: My Faces, the Face
/// Gallery and the editor's choice cards (`FaceStill`). A live face is a
/// whole screen of views, and building one takes the main thread for 25 to
/// 75 ms, more with widgets. My Faces built every card it showed in one
/// update, which froze the app for half a second as it opened. A picture
/// costs nothing to draw, to scroll or to show again.
///
/// Each picture is taken from the live face itself (`FaceStillCapture`), so
/// it looks exactly like it, widgets, glass and all. It stays current for the
/// minute it was taken in and for the look it was taken of (`Look`): a card
/// whose face changes, or whose minute has passed, builds its face again and
/// takes a new picture, showing the old one until then.
///
/// Building is one face at a time (`request(_:)`): a card waits for its turn,
/// builds its live face, and hands the turn on once that face is on screen.
/// The next card builds in a later update, so no update builds more than
/// one face and the screen keeps moving while the cards fill in.
@MainActor
@Observable
final class FaceStills {
    /// Everything a card's picture depends on but the time and the data the
    /// face reads (weather, events, accessories), which a picture shows as
    /// they were when it was taken, as a face on the wall shows them between
    /// its once-a-minute redraws.
    struct Look: Hashable {
        var configuration: FaceConfiguration
        var canvasWidth: CGFloat
        var canvasHeight: CGFloat
        var insets: [CGFloat]
        var proximity: ProximityLevel
        var hidesWidgets: Bool
        var condition: DisplayCondition
        var colorScheme: ColorScheme
        var showsPersonal: Bool
        /// The card's width in pixels, so a picture is never drawn larger than it was taken.
        var pixelWidth: Int
    }

    /// A picture of a face and the minute it shows.
    struct Still {
        let image: UIImage
        let minute: Int
        /// When it was stored, for dropping the oldest first.
        let order: Int
    }

    /// The pictures kept, newest last. Enough for My Faces, the gallery's
    /// fifteen faces and an editor page of choices, with room to go back
    /// and forth between them. At a card's size each picture is 1 to 2 MB.
    static let capacity = 48

    private(set) var stills: [Look: Still] = [:]
    /// The card building its live face now, if any.
    private(set) var building: UUID?
    @ObservationIgnored private var waiting: [UUID] = []
    @ObservationIgnored private var stored = 0

    init() {
        NotificationCenter.default.addObserver(forName: UIApplication.didReceiveMemoryWarningNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.stills.removeAll() }
        }
    }

    /// The minute a date falls in, as the faces' own timelines count minutes (`FaceSchedule`).
    static func minute(of date: Date) -> Int {
        Int((date.timeIntervalSinceReferenceDate / 60).rounded(.down))
    }

    func still(for look: Look) -> Still? {
        stills[look]
    }

    /// Asks for a turn to build a card's live face. Turns go in the order asked,
    /// the first in a later update than the one that asked, so a screen opening
    /// never builds a face in the same update as itself.
    func request(_ card: UUID) {
        guard building != card, !waiting.contains(card) else { return }
        waiting.append(card)
        DispatchQueue.main.async { [weak self] in self?.startNext() }
    }

    /// Gives up a card's turn, or its place in line, when it leaves the screen or no longer needs one.
    func cancel(_ card: UUID) {
        waiting.removeAll { $0 == card }
        if building == card { finishTurn() }
    }

    /// The card's live face is built and on screen: the next card may build.
    func didBuild(_ card: UUID) {
        guard building == card else { return }
        finishTurn()
    }

    /// Keeps a picture of a face as it looks in `minute`.
    func store(_ image: UIImage, for look: Look, minute: Int) {
        stored += 1
        stills[look] = Still(image: image, minute: minute, order: stored)
        if stills.count > Self.capacity, let oldest = stills.min(by: { $0.value.order < $1.value.order })?.key {
            stills[oldest] = nil
        }
    }

    private func finishTurn() {
        building = nil
        // In a later update than the face just built, so no update builds two.
        DispatchQueue.main.async { [weak self] in self?.startNext() }
    }

    private func startNext() {
        guard building == nil, !waiting.isEmpty else { return }
        building = waiting.removeFirst()
    }
}

/// True while something a face shows is still arriving: a photo, camera
/// snapshots, today's events. A card's picture waits until it is false
/// (`FaceStillCapture`), so it never shows a face half loaded.
struct FaceLoadingKey: PreferenceKey {
    static let defaultValue = false

    static func reduce(value: inout Bool, nextValue: () -> Bool) {
        value = value || nextValue()
    }
}

extension View {
    /// Marks the face as still loading what it shows (`FaceLoadingKey`).
    func faceIsLoading(_ isLoading: Bool) -> some View {
        preference(key: FaceLoadingKey.self, value: isLoading)
    }
}
