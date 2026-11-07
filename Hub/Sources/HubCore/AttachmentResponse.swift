import Foundation
import Hummingbird
import NIOCore

/// Serves an attachment file, with `Range` support so video can seek.
enum AttachmentResponse {
    static func make(file: URL, mimeType: String, rangeHeader: String?) throws -> Response {
        let size = try FileManager.default.attributesOfItem(atPath: file.path)[.size] as? Int ?? 0
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }

        var headers = HTTPFields()
        headers[.contentType] = mimeType
        headers[.acceptRanges] = "bytes"
        // An attachment never changes, so the iPad may keep it.
        headers[.cacheControl] = "private, max-age=31536000, immutable"

        guard let range = parse(rangeHeader, size: size) else {
            let data = try handle.read(upToCount: size) ?? Data()
            return Response(status: .ok, headers: headers, body: .init(byteBuffer: ByteBuffer(data: data)))
        }
        try handle.seek(toOffset: UInt64(range.lowerBound))
        let data = try handle.read(upToCount: range.count) ?? Data()
        headers[.contentRange] = "bytes \(range.lowerBound)-\(range.upperBound)/\(size)"
        return Response(status: .partialContent, headers: headers, body: .init(byteBuffer: ByteBuffer(data: data)))
    }

    /// `bytes=a-b`, `bytes=a-` and `bytes=-n`, clipped to the file. A single range only.
    /// Open-ended ranges are capped at 2 MB per response so one request never loads a whole video.
    static func parse(_ header: String?, size: Int) -> ClosedRange<Int>? {
        guard let header, header.hasPrefix("bytes="), size > 0 else { return nil }
        let parts = header.dropFirst(6).split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2 else { return nil }
        let cap = 2_000_000
        if parts[0].isEmpty, let suffix = Int(parts[1]), suffix > 0 {
            return max(0, size - suffix)...(size - 1)
        }
        guard let start = Int(parts[0]), start < size else { return nil }
        let end = Int(parts[1]).map { min($0, size - 1) } ?? (size - 1)
        return start...min(end, start + cap - 1)
    }
}
