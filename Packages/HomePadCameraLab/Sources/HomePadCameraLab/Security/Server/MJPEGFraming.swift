import Foundation

/// HTTP status codes the camera server sends.
enum HTTPStatus: Int, Sendable {
    case ok = 200
    case badRequest = 400
    case unauthorized = 401
    case notFound = 404
    case methodNotAllowed = 405
    case serviceUnavailable = 503

    var reason: String {
        switch self {
        case .ok: "OK"
        case .badRequest: "Bad Request"
        case .unauthorized: "Unauthorized"
        case .notFound: "Not Found"
        case .methodNotAllowed: "Method Not Allowed"
        case .serviceUnavailable: "Service Unavailable"
        }
    }
}

/// Builds the bytes of HTTP responses and of the `multipart/x-mixed-replace`
/// MJPEG stream that Home Assistant's MJPEG IP Camera integration reads.
///
/// A stream is one header followed by parts, each part being:
///
///     --homepadframe\r\n
///     Content-Type: image/jpeg\r\n
///     Content-Length: <n>\r\n
///     \r\n
///     <n bytes of JPEG>\r\n
enum MJPEGFraming {
    static let boundary = "homepadframe"

    private static let noCacheHeaders = [
        ("Cache-Control", "no-cache, no-store, must-revalidate"),
        ("Pragma", "no-cache"),
        ("Connection", "close"),
    ]

    /// The response header that opens a stream.
    static func streamHeader() -> Data {
        head(status: .ok, headers: [("Content-Type", "multipart/x-mixed-replace; boundary=\(boundary)")] + noCacheHeaders)
    }

    /// One frame of the stream.
    static func part(jpeg: Data) -> Data {
        var data = Data("--\(boundary)\r\nContent-Type: image/jpeg\r\nContent-Length: \(jpeg.count)\r\n\r\n".utf8)
        data.append(jpeg)
        data.append(Data("\r\n".utf8))
        return data
    }

    /// A complete response with a body (or only its headers for HEAD requests).
    static func response(status: HTTPStatus, contentType: String, body: Data, includeBody: Bool = true,
                         extraHeaders: [(String, String)] = []) -> Data {
        var headers = [("Content-Type", contentType), ("Content-Length", String(body.count))] + noCacheHeaders
        headers += extraHeaders
        var data = head(status: status, headers: headers)
        if includeBody { data.append(body) }
        return data
    }

    /// A short plain text response for errors.
    static func textResponse(status: HTTPStatus, message: String, extraHeaders: [(String, String)] = []) -> Data {
        response(status: status, contentType: "text/plain; charset=utf-8", body: Data((message + "\n").utf8), extraHeaders: extraHeaders)
    }

    private static func head(status: HTTPStatus, headers: [(String, String)]) -> Data {
        var text = "HTTP/1.1 \(status.rawValue) \(status.reason)\r\n"
        for (name, value) in headers { text += "\(name): \(value)\r\n" }
        text += "\r\n"
        return Data(text.utf8)
    }
}
