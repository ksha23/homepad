import Foundation
import Testing
@testable import HomePadCore

/// A trace left on for a day reached 400 MB, past what the device copy
/// fetches. A trace file now keeps only its newest part.
@Suite struct DebugTraceRolloverTests {
    private func temporaryFile() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("trace-\(UUID().uuidString).txt")
    }

    private func lines(_ range: Range<Int>) -> String {
        range.map { String(format: "%8d line of the trace", $0) }.joined(separator: "\n") + "\n"
    }

    @Test func aFileUnderTheLimitIsLeftWhole() throws {
        let url = temporaryFile()
        DebugTrace.append(lines(0..<10), to: url, maximumBytes: 10_000)
        DebugTrace.append(lines(10..<20), to: url, maximumBytes: 10_000)
        let text = try String(contentsOf: url, encoding: .utf8)
        #expect(text == lines(0..<20))
    }

    @Test func pastTheLimitTheNewestHalfIsKeptInWholeLines() throws {
        let url = temporaryFile()
        // 200 lines of 26 bytes is 5,200 bytes, past a 4,000 byte limit.
        for start in stride(from: 0, to: 200, by: 20) {
            DebugTrace.append(lines(start..<(start + 20)), to: url, maximumBytes: 4_000)
        }
        let data = try Data(contentsOf: url)
        #expect(data.count <= 4_000)
        let text = try #require(String(data: data, encoding: .utf8))
        let kept = text.split(separator: "\n")
        #expect(kept.first?.hasPrefix("(older lines were dropped") == true)
        // Every kept line is whole, and the newest one is there.
        #expect(kept.dropFirst().allSatisfy { $0.hasSuffix("line of the trace") && $0.count == 26 })
        #expect(kept.last == Substring(String(format: "%8d line of the trace", 199)))
    }
}
