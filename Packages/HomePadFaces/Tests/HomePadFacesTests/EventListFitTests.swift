import CoreGraphics
import Testing
@testable import HomePadFaces

/// The order in which a face's event list trades whole titles for more events.
@Suite struct EventListFitTests {
    @Test func threeEventsComeBeforeWholeTitles() {
        let fits = EventListFit.candidates(eventCount: 6, maxRows: 8)
        #expect(fits.first == EventListFit(rows: 6, titleLines: 3, scale: 1))
        // Long Canvas titles left room for one event: every layout with three
        // events is tried before any with fewer.
        let lastThree = fits.lastIndex { $0.rows == 3 } ?? -1
        let firstFewer = fits.firstIndex { $0.rows < 3 } ?? fits.count
        #expect(lastThree < firstFewer)
        // At three events the titles get shorter, never the text smaller.
        #expect(fits.filter { $0.rows == 3 }.map(\.titleLines) == [3, 3, 2, 1])
        #expect(fits.last == EventListFit(rows: 1, titleLines: 1, scale: EventListFit.smallerScale))
    }

    @Test func fewerEventsAreAllListedFirst() {
        for count in 1...2 {
            let fits = EventListFit.candidates(eventCount: count, maxRows: 8)
            #expect(fits.first == EventListFit(rows: count, titleLines: 3, scale: 1))
            #expect(fits.allSatisfy { $0.rows <= count })
        }
    }

    @Test func anEmptyListStillHasALayout() {
        // The list draws its "No more events today" line in it.
        #expect(EventListFit.candidates(eventCount: 0, maxRows: 8).first?.rows == 1)
    }

    @Test func maxRowsCapsTheList() {
        let fits = EventListFit.candidates(eventCount: 20, maxRows: 8)
        #expect(fits.map(\.rows).max() == 8)
        #expect(EventListFit.candidates(eventCount: 20, maxRows: 2).map(\.rows).max() == 2)
    }

    @Test func textNeverShrinksPastTheSmallerScale() {
        let fits = EventListFit.candidates(eventCount: 12, maxRows: 12)
        #expect(fits.allSatisfy { $0.scale >= EventListFit.smallerScale })
        #expect(fits.allSatisfy { $0.titleLines >= 1 })
    }
}
