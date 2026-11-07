import Foundation
import SQLite3

/// A read-only handle on one SQLite file. Messages' chat.db is owned by
/// imagent, so the hub never writes to it.
final class SQLiteConnection {
    enum Failure: Error, CustomStringConvertible {
        case open(String)
        case prepare(String)

        var description: String {
            switch self {
            case .open(let message): "cannot open database: \(message)"
            case .prepare(let message): "bad query: \(message)"
            }
        }
    }

    private var handle: OpaquePointer?
    /// Requests, the event watcher and attachment lookups all share this connection
    /// from different threads, and SQLite does not allow that unguarded.
    private let lock = NSLock()

    init(path: String) throws {
        let status = sqlite3_open_v2(path, &handle, SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX, nil)
        guard status == SQLITE_OK else {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "code \(status)"
            sqlite3_close(handle)
            throw Failure.open(message)
        }
        sqlite3_busy_timeout(handle, 2000)
    }

    deinit { sqlite3_close(handle) }

    /// Runs `sql` with `bindings`, calling `row` for each result row.
    func query(_ sql: String, _ bindings: [SQLiteValue] = [], row: (Row) -> Void) throws {
        lock.lock()
        defer { lock.unlock() }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else {
            throw Failure.prepare(String(cString: sqlite3_errmsg(handle)))
        }
        defer { sqlite3_finalize(statement) }
        for (index, value) in bindings.enumerated() { value.bind(to: statement, at: Int32(index + 1)) }
        while sqlite3_step(statement) == SQLITE_ROW { row(Row(statement: statement)) }
    }
}

enum SQLiteValue {
    case int(Int64)
    case text(String)

    fileprivate func bind(to statement: OpaquePointer?, at index: Int32) {
        switch self {
        case .int(let value):
            sqlite3_bind_int64(statement, index, value)
        case .text(let value):
            sqlite3_bind_text(statement, index, value, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        }
    }
}

/// The current row of a statement. Valid only inside the `row` closure.
struct Row {
    fileprivate let statement: OpaquePointer?

    func int(_ column: Int32) -> Int64 { sqlite3_column_int64(statement, column) }

    func text(_ column: Int32) -> String? {
        guard let bytes = sqlite3_column_text(statement, column) else { return nil }
        return String(cString: bytes)
    }

    func data(_ column: Int32) -> Data? {
        guard let bytes = sqlite3_column_blob(statement, column) else { return nil }
        return Data(bytes: bytes, count: Int(sqlite3_column_bytes(statement, column)))
    }
}
