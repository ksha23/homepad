import Foundation
import os

/// Unified logging. Each module makes its own category:
///
///     private let log = Log.make("SmartHome")
///
/// View logs in Console.app with the subsystem filter `com.homepad`.
public enum Log {
    public static let subsystem = "com.homepad"

    public static func make(_ category: String) -> Logger {
        Logger(subsystem: subsystem, category: category)
    }
}
