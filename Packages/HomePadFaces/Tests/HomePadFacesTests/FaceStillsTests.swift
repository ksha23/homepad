import Foundation
import HomePadCore
import SwiftUI
import Testing
import UIKit
@testable import HomePadFaces

/// The cards' pictures (`FaceStills`): one face built at a time, in the order
/// the cards asked, and pictures kept by look and minute, the oldest dropped first.
@MainActor
@Suite struct FaceStillsTests {
    @Test func cardsBuildOneAtATimeInTheOrderAsked() async {
        let stills = FaceStills()
        let first = UUID()
        let second = UUID()
        stills.request(first)
        stills.request(second)
        stills.request(second)
        // Not in the update that asked.
        #expect(stills.building == nil)
        await Self.nextMainQueueTurn()
        #expect(stills.building == first)
        stills.didBuild(first)
        // The next card builds in a later update, never the same one.
        #expect(stills.building == nil)
        await Self.nextMainQueueTurn()
        #expect(stills.building == second)
        stills.didBuild(second)
        await Self.nextMainQueueTurn()
        #expect(stills.building == nil)
    }

    @Test func aCardThatLeavesGivesUpItsTurnAndItsPlace() async {
        let stills = FaceStills()
        let first = UUID()
        let second = UUID()
        let third = UUID()
        stills.request(first)
        stills.request(second)
        stills.request(third)
        stills.cancel(second)
        stills.cancel(first)
        await Self.nextMainQueueTurn()
        #expect(stills.building == third)
    }

    @Test func aPictureIsKeptForItsLookAndMinute() {
        let stills = FaceStills()
        let minute = FaceStills.minute(of: Date())
        stills.store(UIImage(), for: Self.look(1), minute: minute)
        #expect(stills.still(for: Self.look(1))?.minute == minute)
        #expect(stills.still(for: Self.look(2)) == nil)
    }

    @Test func theOldestPictureGoesPastCapacity() {
        let stills = FaceStills()
        for index in 0...FaceStills.capacity {
            stills.store(UIImage(), for: Self.look(index), minute: 0)
        }
        #expect(stills.still(for: Self.look(0)) == nil)
        #expect(stills.still(for: Self.look(1)) != nil)
        #expect(stills.still(for: Self.look(FaceStills.capacity)) != nil)
    }

    @Test func minutesTurnOnTheWholeMinute() {
        let start = Date(timeIntervalSinceReferenceDate: 60 * 1000)
        #expect(FaceStills.minute(of: start.addingTimeInterval(59.9)) == FaceStills.minute(of: start))
        #expect(FaceStills.minute(of: start.addingTimeInterval(60)) == FaceStills.minute(of: start) + 1)
    }

    /// A look that differs from others only in its width in pixels.
    private static func look(_ pixelWidth: Int) -> FaceStills.Look {
        FaceStills.Look(configuration: .unsaved("faces.modular"), canvasWidth: 1376, canvasHeight: 1032,
                        insets: [44, 64, 44, 64], proximity: .near, hidesWidgets: false, condition: .ambient,
                        colorScheme: .dark, showsPersonal: false, pixelWidth: pixelWidth)
    }

    /// After whatever the main queue already holds, as the next card's turn is.
    private static func nextMainQueueTurn() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
    }
}
