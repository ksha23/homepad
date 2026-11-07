import Foundation

/// The fixed sticky-note palette. Curated like Apple's, no free color entry.
public enum NoteColor: String, Codable, CaseIterable, Sendable {
    case yellow, orange, pink, purple, blue, green

    public var displayName: String { rawValue.capitalized }
}

/// One sticky note on the Family Board.
///
/// Notes merge last-writer-wins per note. Deleting leaves a tombstone so the
/// deletion spreads to other devices instead of the note coming back.
public struct BoardNote: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var text: String
    public var color: NoteColor
    /// Who wrote it, for example "Kyle" or "Kitchen".
    public var author: String
    public var isPinned: Bool
    public var createdAt: Date
    public var modifiedAt: Date
    /// Device ID of the last writer. Breaks ties between equal timestamps.
    public var modifiedBy: String
    public var isDeleted: Bool

    public init(id: UUID = UUID(), text: String, color: NoteColor = .yellow, author: String, isPinned: Bool = false,
                createdAt: Date = Date(), modifiedAt: Date? = nil, modifiedBy: String, isDeleted: Bool = false) {
        self.id = id
        self.text = text
        self.color = color
        self.author = author
        self.isPinned = isPinned
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt ?? createdAt
        self.modifiedBy = modifiedBy
        self.isDeleted = isDeleted
    }

    /// Records an edit made on `device` at `date`.
    public mutating func touch(by device: String, at date: Date = Date()) {
        modifiedAt = max(date, modifiedAt.addingTimeInterval(0.001))
        modifiedBy = device
    }
}
