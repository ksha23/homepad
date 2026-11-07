import Foundation
import Testing
@testable import HomePadCameraLab

@Suite struct MJPEGFramingTests {
    @Test func streamHeaderAnnouncesMultipartBoundary() {
        let header = String(decoding: MJPEGFraming.streamHeader(), as: UTF8.self)
        #expect(header.hasPrefix("HTTP/1.1 200 OK\r\n"))
        #expect(header.contains("Content-Type: multipart/x-mixed-replace; boundary=homepadframe\r\n"))
        #expect(header.contains("Cache-Control: no-cache"))
        #expect(header.hasSuffix("\r\n\r\n"))
    }

    @Test func partWrapsJPEGWithBoundaryAndLength() {
        let jpeg = Data([0xFF, 0xD8, 0x01, 0x02, 0x03, 0xFF, 0xD9])
        let part = MJPEGFraming.part(jpeg: jpeg)
        let prefix = Data("--homepadframe\r\nContent-Type: image/jpeg\r\nContent-Length: 7\r\n\r\n".utf8)
        #expect(part.prefix(prefix.count) == prefix)
        #expect(part.dropFirst(prefix.count).prefix(jpeg.count) == jpeg)
        #expect(part.suffix(2) == Data("\r\n".utf8))
        #expect(part.count == prefix.count + jpeg.count + 2)
    }

    @Test func consecutivePartsSplitOnTheBoundary() {
        let stream = MJPEGFraming.part(jpeg: Data("one".utf8)) + MJPEGFraming.part(jpeg: Data("two".utf8))
        let text = String(decoding: stream, as: UTF8.self)
        let pieces = text.components(separatedBy: "--homepadframe\r\n").filter { !$0.isEmpty }
        #expect(pieces.count == 2)
        #expect(pieces[0].hasSuffix("\r\n\r\none\r\n"))
        #expect(pieces[1].hasSuffix("\r\n\r\ntwo\r\n"))
    }

    @Test func snapshotResponseHasLengthAndBody() {
        let body = Data([1, 2, 3, 4])
        let response = MJPEGFraming.response(status: .ok, contentType: "image/jpeg", body: body)
        let text = String(decoding: response.prefix(response.count - body.count), as: UTF8.self)
        #expect(text.contains("Content-Type: image/jpeg\r\n"))
        #expect(text.contains("Content-Length: 4\r\n"))
        #expect(response.suffix(4) == body)
    }

    @Test func headResponseOmitsTheBodyButKeepsTheLength() {
        let body = Data(repeating: 7, count: 10)
        let response = MJPEGFraming.response(status: .ok, contentType: "image/jpeg", body: body, includeBody: false)
        let text = String(decoding: response, as: UTF8.self)
        #expect(text.contains("Content-Length: 10\r\n"))
        #expect(text.hasSuffix("\r\n\r\n"))
    }

    @Test func errorResponsesCarryStatusLine() {
        let text = String(decoding: MJPEGFraming.textResponse(status: .unauthorized, message: "Nope"), as: UTF8.self)
        #expect(text.hasPrefix("HTTP/1.1 401 Unauthorized\r\n"))
        #expect(text.hasSuffix("Nope\n"))
    }
}

@Suite struct AccessTokenTests {
    @Test func generatedTokensAreLongRandomAndURLSafe() {
        let first = AccessToken.generate()
        let second = AccessToken.generate()
        #expect(first.count == 32)
        #expect(first != second)
        #expect(first.allSatisfy { AccessToken.alphabet.contains($0) })
        #expect(first.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) == first)
    }

    @Test func matchesOnlyTheExactToken() {
        let token = "ABCDEFGHJKLMNPQRSTUVWXYZabcdefgh"
        #expect(AccessToken.matches(token, expected: token))
        #expect(!AccessToken.matches(nil, expected: token))
        #expect(!AccessToken.matches("", expected: token))
        #expect(!AccessToken.matches(String(token.dropLast()), expected: token))
        #expect(!AccessToken.matches(token + "x", expected: token))
        #expect(!AccessToken.matches(token.lowercased(), expected: token))
        #expect(!AccessToken.matches("ABCDEFGHJKLMNPQRSTUVWXYZabcdefgX", expected: token))
    }

    @Test func shortExpectedTokensNeverMatch() {
        #expect(!AccessToken.matches("", expected: ""))
        #expect(!AccessToken.matches("short", expected: "short"))
    }
}

@Suite struct MJPEGRouteTests {
    private let token = "ABCDEFGHJKLMNPQRSTUVWXYZabcdefgh"

    private func route(_ method: String, _ target: String) -> MJPEGRoute {
        let text = "\(method) \(target) HTTP/1.1\r\nHost: ipad\r\n\r\n"
        guard case .complete(let request) = HTTPRequestParser.parse(Data(text.utf8)) else { return .notFound }
        return MJPEGRoute.resolve(request, token: token)
    }

    @Test func routesStreamAndSnapshotWithTheToken() {
        #expect(route("GET", "/stream.mjpeg?token=\(token)") == .stream(headOnly: false))
        #expect(route("GET", "/snapshot.jpg?token=\(token)") == .snapshot(headOnly: false))
        #expect(route("HEAD", "/snapshot.jpg?token=\(token)") == .snapshot(headOnly: true))
    }

    @Test func rejectsMissingOrWrongTokens() {
        #expect(route("GET", "/stream.mjpeg") == .unauthorized)
        #expect(route("GET", "/stream.mjpeg?token=") == .unauthorized)
        #expect(route("GET", "/snapshot.jpg?token=guess") == .unauthorized)
        #expect(route("GET", "/snapshot.jpg?other=\(token)") == .unauthorized)
    }

    @Test func unknownPathsAndMethods() {
        #expect(route("GET", "/?token=\(token)") == .notFound)
        #expect(route("GET", "/stream.mjpeg/extra?token=\(token)") == .notFound)
        #expect(route("POST", "/stream.mjpeg?token=\(token)") == .methodNotAllowed)
    }

    @Test func homeAssistantSetupUsesTheServedPaths() {
        let setup = HomeAssistantCameraSetup(host: "192.168.1.40", port: 8081, token: token)
        #expect(setup.streamURL == "http://192.168.1.40:8081/stream.mjpeg?token=\(token)")
        #expect(setup.snapshotURL == "http://192.168.1.40:8081/snapshot.jpg?token=\(token)")
        #expect(HomeAssistantCameraSetup(host: nil, port: 8081, token: token).streamURL == nil)
    }
}
