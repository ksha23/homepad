import Testing
@testable import HomePadAssistant

@Suite struct SSEParserTests {
    @Test func parsesNamedEventsAndDataOnlyEvents() {
        let body = """
        event: message_start
        data: {"a":1}

        data: {"b":2}

        """
        let events = SSEParser.parse(body)
        #expect(events == [SSEEvent(name: "message_start", data: #"{"a":1}"#), SSEEvent(data: #"{"b":2}"#)])
    }

    @Test func joinsMultiLineDataAndSkipsComments() {
        let body = ": keep-alive\ndata: first\ndata: second\n\n: OPENROUTER PROCESSING\n\n"
        #expect(SSEParser.parse(body) == [SSEEvent(data: "first\nsecond")])
    }

    @Test func handlesCRLFAndMissingTrailingBlankLine() {
        let body = "data: {\"x\":1}\r\n\r\ndata: last"
        #expect(SSEParser.parse(body) == [SSEEvent(data: #"{"x":1}"#), SSEEvent(data: "last")])
    }

    @Test func keepsValueWithoutLeadingSpace() {
        #expect(SSEParser.parse("data:tight\n\n") == [SSEEvent(data: "tight")])
    }

    @Test func lineSplitterKeepsEmptyLines() {
        var splitter = LineSplitter()
        var lines: [String] = []
        for byte in Array("a\n\nb".utf8) {
            if let line = splitter.append(byte) { lines.append(line) }
        }
        if let tail = splitter.finish() { lines.append(tail) }
        #expect(lines == ["a", "", "b"])
    }
}
