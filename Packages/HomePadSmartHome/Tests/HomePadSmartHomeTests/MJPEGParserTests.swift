import Foundation
import Testing
@testable import HomePadSmartHome

@Suite("MJPEG multipart parser")
struct MJPEGParserTests {
    /// Fake JPEG frames: start marker, some bytes that include CR LF and dashes, end marker.
    static let frames: [Data] = (1...3).map { index in
        Data([0xFF, 0xD8, 0xFF, 0xE0]) + Data("frame \(index)\r\n--not-a-boundary\r\n".utf8) + Data(repeating: UInt8(index), count: 300 * index) + Data([0xFF, 0xD9])
    }

    static func stream(boundary: String, contentLength: Bool, preamble: String = "") -> Data {
        var data = Data(preamble.utf8)
        for frame in frames {
            data += Data("--\(boundary)\r\nContent-Type: image/jpeg\r\n".utf8)
            if contentLength { data += Data("Content-Length: \(frame.count)\r\n".utf8) }
            data += Data("\r\n".utf8) + frame + Data("\r\n".utf8)
        }
        if !contentLength { data += Data("--\(boundary)\r\n".utf8) }
        return data
    }

    /// Feeds the stream in chunks of the given size and collects every frame.
    static func parse(_ data: Data, contentType: String?, chunk: Int) -> [Data] {
        var parser = MJPEGParser(contentType: contentType)
        var frames: [Data] = []
        var offset = 0
        while offset < data.count {
            let end = min(offset + chunk, data.count)
            frames += parser.append(data.subdata(in: offset..<end))
            offset = end
        }
        return frames
    }

    @Test(arguments: [1, 7, 64, 1000, 100_000])
    func homeAssistantStyleWithContentLength(chunk: Int) {
        let data = Self.stream(boundary: "frame", contentLength: true)
        #expect(Self.parse(data, contentType: "multipart/x-mixed-replace;boundary=frame", chunk: chunk) == Self.frames)
    }

    @Test(arguments: [1, 13, 4096])
    func boundaryOnlyWithoutContentLength(chunk: Int) {
        let data = Self.stream(boundary: "myboundary", contentLength: false, preamble: "junk before the first part\r\n")
        #expect(Self.parse(data, contentType: "multipart/x-mixed-replace; boundary=\"myboundary\"", chunk: chunk) == Self.frames)
    }

    @Test func boundaryDeclaredWithLeadingDashes() {
        // Some cameras declare `boundary=--myboundary` and then write `--myboundary`.
        var data = Data()
        for frame in Self.frames {
            data += Data("--myboundary\r\nContent-Length: \(frame.count)\r\n\r\n".utf8) + frame + Data("\r\n".utf8)
        }
        #expect(Self.parse(data, contentType: "multipart/x-mixed-replace;boundary=--myboundary", chunk: 50) == Self.frames)
    }

    @Test func headerNamesAreCaseInsensitive() {
        let frame = Self.frames[0]
        let data = Data("--frame\r\ncontent-length: \(frame.count)\r\n\r\n".utf8) + frame
        #expect(Self.parse(data, contentType: "multipart/x-mixed-replace;boundary=frame", chunk: 10) == [frame])
    }

    @Test(arguments: [1, 5, 333])
    func fallsBackToJPEGMarkersWithoutABoundary(chunk: Int) {
        var data = Data("HTTP noise".utf8)
        for frame in Self.frames { data += frame + Data("\r\n".utf8) }
        #expect(Self.parse(data, contentType: "image/jpeg", chunk: chunk) == Self.frames)
    }

    @Test func incompleteFrameWaitsForMoreBytes() {
        var parser = MJPEGParser(contentType: "multipart/x-mixed-replace;boundary=frame")
        let data = Self.stream(boundary: "frame", contentLength: true)
        let firstPartEnd = data.count / 6
        #expect(parser.append(data.prefix(firstPartEnd)).isEmpty)
        #expect(parser.bufferedByteCount == firstPartEnd)
        #expect(parser.append(data.dropFirst(firstPartEnd)) == Self.frames)
    }

    @Test func runawayBufferIsDropped() {
        var parser = MJPEGParser(contentType: "multipart/x-mixed-replace;boundary=frame")
        _ = parser.append(Data(repeating: 0x41, count: MJPEGParser.maximumBufferSize + 1))
        #expect(parser.bufferedByteCount == 0)
    }

    @Test func boundaryParsing() {
        #expect(MJPEGParser.boundary(fromContentType: "multipart/x-mixed-replace;boundary=frame") == "frame")
        #expect(MJPEGParser.boundary(fromContentType: "multipart/x-mixed-replace; charset=x; Boundary=\"--abc\"") == "abc")
        #expect(MJPEGParser.boundary(fromContentType: "image/jpeg") == nil)
        #expect(MJPEGParser.boundary(fromContentType: nil) == nil)
        #expect(MJPEGParser(contentType: "multipart/x-mixed-replace;boundary=frame").delimiter == Data("--frame".utf8))
    }
}
