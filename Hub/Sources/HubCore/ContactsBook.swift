import Foundation

/// Names for phone numbers and emails, read from the Contacts databases on this Mac.
/// Phone numbers match on their last ten digits, so `+1 (314) 555-0100` finds `3145550100`.
public final class ContactsBook: @unchecked Sendable {
    private var byKey: [String: String] = [:]
    private var photoByKey: [String: Data] = [:]
    private let lock = NSLock()

    public init() { reload() }

    /// A display name for a handle (phone or email), or nil when it is not in Contacts.
    public func name(for handle: String) -> String? {
        lock.lock()
        defer { lock.unlock() }
        return byKey[Self.key(handle)]
    }

    /// The contact's picture (JPEG, PNG or HEIC bytes) for a handle, or nil when there is none.
    public func photo(for handle: String) -> Data? {
        lock.lock()
        defer { lock.unlock() }
        return photoByKey[Self.key(handle)]
    }

    /// Re-reads every Contacts source. Cheap enough to call every few minutes.
    public func reload() {
        var found: [String: String] = [:]
        var photos: [String: Data] = [:]
        for path in Self.databasePaths() {
            guard let db = try? SQLiteConnection(path: path) else { continue }
            let phones = """
                SELECT p.ZFULLNUMBER, r.ZFIRSTNAME, r.ZLASTNAME, r.ZNICKNAME, r.ZORGANIZATION, r.ZTHUMBNAILIMAGEDATA, r.ZIMAGEDATA
                FROM ZABCDPHONENUMBER p JOIN ZABCDRECORD r ON r.Z_PK = p.ZOWNER
                """
            let emails = """
                SELECT e.ZADDRESS, r.ZFIRSTNAME, r.ZLASTNAME, r.ZNICKNAME, r.ZORGANIZATION, r.ZTHUMBNAILIMAGEDATA, r.ZIMAGEDATA
                FROM ZABCDEMAILADDRESS e JOIN ZABCDRECORD r ON r.Z_PK = e.ZOWNER
                """
            for sql in [phones, emails] {
                try? db.query(sql) { row in
                    guard let handle = row.text(0) else { return }
                    let person = [row.text(1), row.text(2)].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " ")
                    let name = person.isEmpty ? (row.text(3) ?? row.text(4) ?? "") : person
                    if !name.isEmpty { found[Self.key(handle)] = name }
                    if let picture = Self.imageBytes(row.data(6), beside: path) ?? Self.imageBytes(row.data(5), beside: path) { photos[Self.key(handle)] = picture }
                }
            }
        }
        lock.lock()
        byKey = found
        photoByKey = photos
        lock.unlock()
    }

    /// Contacts stores some pictures behind a one byte prefix. This drops anything before the image header.
    /// Larger pictures are not stored inline. The record holds `02` and a UUID, and the image is the file
    /// of that name in `.AddressBook-v22_SUPPORT/_EXTERNAL_DATA` beside the database.
    static func imageBytes(_ data: Data?, beside databasePath: String) -> Data? {
        guard let data, data.count > 8 else { return nil }
        if data.first == 0x02, data.count >= 37, let name = String(data: data[data.startIndex + 1..<data.startIndex + 37], encoding: .ascii), !name.contains("/") {
            let folder = (databasePath as NSString).deletingLastPathComponent + "/.AddressBook-v22_SUPPORT/_EXTERNAL_DATA/"
            return try? Data(contentsOf: URL(fileURLWithPath: folder + name))
        }
        let headers: [[UInt8]] = [[0xFF, 0xD8, 0xFF], [0x89, 0x50, 0x4E, 0x47]]
        for start in 0..<min(4, data.count - 4) {
            let head = [UInt8](data[start..<start + 4])
            if headers.contains(where: { head.starts(with: $0) }) { return Data(data.dropFirst(start)) }
        }
        return nil
    }

    static func key(_ handle: String) -> String {
        if handle.contains("@") { return handle.lowercased() }
        let digits = handle.filter(\.isNumber)
        return String(digits.suffix(10))
    }

    private static func databasePaths() -> [String] {
        let root = NSHomeDirectory() + "/Library/Application Support/AddressBook"
        var paths = [root + "/AddressBook-v22.abcddb"]
        let sources = (try? FileManager.default.contentsOfDirectory(atPath: root + "/Sources")) ?? []
        paths += sources.map { root + "/Sources/\($0)/AddressBook-v22.abcddb" }
        return paths.filter { FileManager.default.fileExists(atPath: $0) }
    }
}
