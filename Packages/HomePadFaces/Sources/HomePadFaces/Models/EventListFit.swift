import CoreGraphics

/// One way to lay out a face's event list: how many events, how many lines
/// each title may take, and how large the text is. `EventsList` measures the
/// candidates in order and shows the first that fits its frame.
struct EventListFit: Equatable {
    /// Events listed. The rest are counted in an "N more events" line.
    let rows: Int
    /// Lines a title may wrap to before it is cut off.
    let titleLines: Int
    /// Text size as a fraction of the list's font size.
    let scale: CGFloat

    /// How small the text may get to keep titles whole.
    static let smallerScale: CGFloat = 0.85

    /// The events a list keeps before it gives up whole titles. Whole titles
    /// used to come first, and two long Canvas titles left room for one event.
    static let minimumRows = 3

    /// The layouts to try, best first:
    /// 1. the most events with whole titles (up to three lines), at full size
    ///    and then a little smaller, down to `minimumRows` events,
    /// 2. `minimumRows` events with titles on two lines, then on one,
    /// 3. only then fewer events, one line each.
    ///
    /// With fewer events than `minimumRows`, every event is listed first.
    static func candidates(eventCount: Int, maxRows: Int) -> [EventListFit] {
        let most = max(1, min(maxRows, eventCount))
        let floor = min(minimumRows, most)
        var result: [EventListFit] = []
        for rows in stride(from: most, through: floor, by: -1) {
            result.append(EventListFit(rows: rows, titleLines: 3, scale: 1))
            result.append(EventListFit(rows: rows, titleLines: 3, scale: smallerScale))
        }
        result.append(EventListFit(rows: floor, titleLines: 2, scale: smallerScale))
        result.append(EventListFit(rows: floor, titleLines: 1, scale: smallerScale))
        for rows in stride(from: floor - 1, through: 1, by: -1) {
            result.append(EventListFit(rows: rows, titleLines: 1, scale: smallerScale))
        }
        return result
    }
}
