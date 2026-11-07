import Foundation

/// Splits a `multipart/x-mixed-replace` MJPEG byte stream into JPEG frames.
/// Feed it bytes as they arrive and it returns every frame that became complete.
/// Uses `Content-Length` when a part has one and the boundary otherwise. With no
/// boundary at all it falls back to JPEG start and end markers.
struct MJPEGParser {
    /// Drops buffered bytes past this size, so a broken stream cannot grow memory forever.
    static let maximumBufferSize = 8 * 1024 * 1024

    /// The delimiter line, `--` followed by the boundary token.
    let delimiter: Data?
    private var buffer = Data()

    private static let headerEnd = Data("\r\n\r\n".utf8)
    private static let lineBreak = Data("\r\n".utf8)
    private static let startOfImage = Data([0xFF, 0xD8])
    private static let endOfImage = Data([0xFF, 0xD9])

    /// - Parameter contentType: The response's `Content-Type`, for example
    ///   `multipart/x-mixed-replace; boundary=frame`.
    init(contentType: String?) {
        delimiter = Self.boundary(fromContentType: contentType).map { Data("--\($0)".utf8) }
    }

    /// The boundary token without leading dashes or quotes.
    static func boundary(fromContentType contentType: String?) -> String? {
        guard let contentType else { return nil }
        for parameter in contentType.split(separator: ";") {
            let parts = parameter.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count == 2, parts[0].lowercased() == "boundary" else { continue }
            let token = parts[1].trimmingCharacters(in: CharacterSet(charactersIn: "\"")).drop { $0 == "-" }
            return token.isEmpty ? nil : String(token)
        }
        return nil
    }

    /// Bytes waiting for the rest of a frame.
    var bufferedByteCount: Int { buffer.count }

    mutating func append(_ data: Data) -> [Data] {
        buffer.append(data)
        let frames = delimiter.map { extractParts(delimiter: $0) } ?? extractByMarkers()
        if buffer.count > Self.maximumBufferSize { buffer = Data() }
        return frames
    }

    private mutating func extractParts(delimiter: Data) -> [Data] {
        var frames: [Data] = []
        while let start = buffer.range(of: delimiter) {
            guard let headerEnd = buffer.range(of: Self.headerEnd, in: start.upperBound..<buffer.endIndex) else { break }
            let headers = String(decoding: buffer[start.upperBound..<headerEnd.lowerBound], as: UTF8.self)
            let bodyStart = headerEnd.upperBound
            if let length = Self.contentLength(in: headers) {
                guard buffer.endIndex - bodyStart >= length else { break }
                frames.append(Data(buffer[bodyStart..<(bodyStart + length)]))
                buffer = Data(buffer[(bodyStart + length)...])
            } else {
                guard let next = buffer.range(of: delimiter, in: bodyStart..<buffer.endIndex) else { break }
                var bodyEnd = next.lowerBound
                if bodyEnd - bodyStart >= 2, buffer[(bodyEnd - 2)..<bodyEnd] == Self.lineBreak { bodyEnd -= 2 }
                if bodyEnd > bodyStart { frames.append(Data(buffer[bodyStart..<bodyEnd])) }
                buffer = Data(buffer[next.lowerBound...])
            }
        }
        return frames
    }

    private mutating func extractByMarkers() -> [Data] {
        var frames: [Data] = []
        while let start = buffer.range(of: Self.startOfImage) {
            guard let end = buffer.range(of: Self.endOfImage, in: start.upperBound..<buffer.endIndex) else {
                buffer = Data(buffer[start.lowerBound...])
                return frames
            }
            frames.append(Data(buffer[start.lowerBound..<end.upperBound]))
            buffer = Data(buffer[end.upperBound...])
        }
        // Keep a trailing 0xFF in case the next chunk starts with 0xD8.
        buffer = buffer.last == 0xFF ? Data([0xFF]) : Data()
        return frames
    }

    private static func contentLength(in headers: String) -> Int? {
        for line in headers.split(whereSeparator: \.isNewline) {
            let parts = line.split(separator: ":", maxSplits: 1)
            if parts.count == 2, parts[0].trimmingCharacters(in: .whitespaces).lowercased() == "content-length" {
                return Int(parts[1].trimmingCharacters(in: .whitespaces))
            }
        }
        return nil
    }
}
