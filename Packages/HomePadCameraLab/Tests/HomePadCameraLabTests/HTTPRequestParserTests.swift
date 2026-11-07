import Foundation
import Testing
@testable import HomePadCameraLab

@Suite struct HTTPRequestParserTests {
    private func parse(_ text: String) -> HTTPRequestParser.Outcome {
        HTTPRequestParser.parse(Data(text.utf8))
    }

    @Test func parsesHomeAssistantStreamRequest() throws {
        let outcome = parse("GET /stream.mjpeg?token=abc123 HTTP/1.1\r\nHost: 192.168.1.40:8081\r\nUser-Agent: HomeAssistant/2026.10\r\nAccept: */*\r\n\r\n")
        guard case .complete(let request) = outcome else {
            Issue.record("Expected a complete request, got \(outcome)")
            return
        }
        #expect(request.method == "GET")
        #expect(request.path == "/stream.mjpeg")
        #expect(request.query == ["token": "abc123"])
        #expect(request.version == "HTTP/1.1")
        #expect(request.headers["host"] == "192.168.1.40:8081")
        #expect(request.headers["user-agent"] == "HomeAssistant/2026.10")
    }

    @Test func waitsForTheEndOfTheHeaderBlock() {
        #expect(parse("GET /snapshot.jpg HTTP/1.1\r\nHost: x\r\n") == .incomplete)
        #expect(parse("") == .incomplete)
    }

    @Test func decodesPercentEscapesAndPlusInQuery() {
        guard case .complete(let request) = parse("GET /a%20b?name=two+words&x=%3D%26&flag HTTP/1.0\r\n\r\n") else {
            Issue.record("Expected a complete request")
            return
        }
        #expect(request.path == "/a b")
        #expect(request.query["name"] == "two words")
        #expect(request.query["x"] == "=&")
        #expect(request.query["flag"] == "")
    }

    @Test func firstQueryValueWins() {
        let query = HTTPRequestParser.parseQuery("token=right&token=wrong")
        #expect(query["token"] == "right")
    }

    @Test func joinsRepeatedHeadersAndIgnoresBody() {
        guard case .complete(let request) = parse("GET / HTTP/1.1\r\nAccept: a\r\naccept: b\r\n\r\nbody bytes") else {
            Issue.record("Expected a complete request")
            return
        }
        #expect(request.headers["accept"] == "a, b")
    }

    @Test func rejectsMalformedRequests() {
        let malformed = [
            "GET /stream.mjpeg\r\n\r\n",                     // missing version
            "get / HTTP/1.1\r\n\r\n",                        // lowercase method
            "GET / HTTP/2\r\n\r\n",                          // unsupported version
            "GET http://example.com/ HTTP/1.1\r\n\r\n",      // absolute form
            "GET / HTTP/1.1\r\nNoColonHere\r\n\r\n",         // bad header
            "GET  / HTTP/1.1\r\n\r\n",                       // double space
        ]
        for text in malformed {
            guard case .invalid = parse(text) else {
                Issue.record("Expected invalid for \(text.debugDescription)")
                continue
            }
        }
    }

    @Test func rejectsOversizedHeaders() {
        let huge = "GET / HTTP/1.1\r\nX-Pad: " + String(repeating: "a", count: HTTPRequestParser.maximumHeaderBytes + 10)
        guard case .invalid = parse(huge) else {
            Issue.record("Expected invalid for an oversized header block")
            return
        }
    }
}
