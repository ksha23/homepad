import Foundation

/// Rules for `POST /v1/conversations/{id}/attachments`, shared so the iPad and the hub agree.
public enum CommsUpload {
    /// The largest file the hub accepts, in bytes.
    public static let maxBytes = 100 * 1024 * 1024
    /// Header carrying the original file name.
    public static let filenameHeader = "X-Filename"

    /// A file name that is safe to write inside one folder: no path parts, no control
    /// characters, no leading dots, at most 120 characters. Falls back to `fallback`.
    public static func sanitizedFilename(_ raw: String?, fallback: String = "attachment") -> String {
        let removed = CharacterSet(charactersIn: "/\\:").union(.controlCharacters).union(.newlines)
        var name = (raw ?? "").unicodeScalars.map { removed.contains($0) ? "_" : String($0) }.joined()
        name = name.trimmingCharacters(in: .whitespaces)
        while name.hasPrefix(".") { name.removeFirst() }
        if name.count > 120 {
            let ext = (name as NSString).pathExtension
            if ext.isEmpty || ext.count > 10 {
                name = String(name.prefix(120))
            } else {
                name = String(name.prefix(119 - ext.count)) + "." + ext
            }
        }
        return name.isEmpty ? fallback : name
    }

    /// True when `size` bytes fit under the cap.
    public static func allows(_ size: Int) -> Bool { size > 0 && size <= maxBytes }
}
