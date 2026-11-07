import Foundation

/// What the camera server does with a request.
enum MJPEGRoute: Equatable {
    /// `GET /stream.mjpeg?token=...`: a multipart MJPEG stream.
    case stream(headOnly: Bool)
    /// `GET /snapshot.jpg?token=...`: the latest frame as one JPEG.
    case snapshot(headOnly: Bool)
    case unauthorized
    case notFound
    case methodNotAllowed

    static let streamPath = "/stream.mjpeg"
    static let snapshotPath = "/snapshot.jpg"

    /// Routes a parsed request. Unknown paths get 404 before the token is
    /// checked, and known paths need the exact token.
    static func resolve(_ request: HTTPRequest, token: String) -> MJPEGRoute {
        let headOnly = request.method == "HEAD"
        guard request.method == "GET" || headOnly else { return .methodNotAllowed }
        guard request.path == streamPath || request.path == snapshotPath else { return .notFound }
        guard AccessToken.matches(request.query["token"], expected: token) else { return .unauthorized }
        return request.path == streamPath ? .stream(headOnly: headOnly) : .snapshot(headOnly: headOnly)
    }
}
