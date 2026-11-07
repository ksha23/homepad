import CoreBluetooth
import Foundation
import UIKit

/// The Bluetooth service a HomePad offers so it can wake its people's phones.
///
/// iOS suspends the companion app soon after it leaves the screen, and closes
/// its sockets, so the peer link cannot reach it. Core Bluetooth can: a phone
/// with the `bluetooth-central` background mode that is connected to the
/// HomePad and subscribed to `wake` is woken by iOS for each notification,
/// even after iOS ended the app, through state restoration. The phone then
/// has about 10 seconds, up to about 30 with a background task, to join the
/// peer link and answer. Nothing personal travels over Bluetooth.
///
///     wake   notify  the HomePad wants this phone on the peer link
///     hello  write   the phone's wake tags, one 16-byte tag per HomePad it shares with
enum ProximityWake {
    static let service = CBUUID(string: "8F3C4A52-2D61-4E8B-9C6A-6B1F0E7D4A21")
    static let wake = CBUUID(string: "8F3C4A53-2D61-4E8B-9C6A-6B1F0E7D4A21")
    static let hello = CBUUID(string: "8F3C4A54-2D61-4E8B-9C6A-6B1F0E7D4A21")
    /// So iOS can hand the phone's Bluetooth state back after it ended the app.
    static let restoreIdentifier = "com.ksha23.homepad.wake"
    static let tagLength = 16

    /// Splits a `hello` write into its tags.
    static func tags(in value: Data) -> [Data] {
        stride(from: 0, to: value.count - tagLength + 1, by: tagLength).map {
            Data(value[(value.startIndex + $0)..<(value.startIndex + $0 + tagLength)])
        }
    }
}

/// On a phone: wakes the app when a HomePad it shares with asks.
@MainActor
protocol WakeListening: AnyObject {
    var onWake: @MainActor () -> Void { get set }
    /// Why the HomePad cannot wake this phone, in words, or nil.
    var problem: String? { get }
    /// Starts or updates listening with these tags.
    func listen(tags: [Data])
    func stop()
}

/// Keeps a woken app running while it answers, then lets iOS suspend it.
@MainActor
protocol BackgroundWindow: AnyObject {
    /// True when the app is not on screen.
    var isInBackground: Bool { get }
    func begin()
    func end()
}

/// `UIApplication.beginBackgroundTask`, which asks for up to about 30 seconds.
/// iOS may give less. It never keeps the app alive past that.
@MainActor
final class AppBackgroundWindow: BackgroundWindow {
    private var task: UIBackgroundTaskIdentifier = .invalid
    private var timeout: Task<Void, Never>?

    var isInBackground: Bool { UIApplication.shared.applicationState != .active }

    func begin() {
        guard isInBackground, task == .invalid else { return }
        task = UIApplication.shared.beginBackgroundTask(withName: "HomePad visit") { [weak self] in
            MainActor.assumeIsolated { self?.end() }
        }
        // Ends well inside iOS's limit, so the app is never ended for overrunning it.
        timeout = Task { [weak self] in
            try? await Task.sleep(for: .seconds(25))
            guard !Task.isCancelled else { return }
            self?.end()
        }
    }

    func end() {
        timeout?.cancel()
        timeout = nil
        guard task != .invalid else { return }
        UIApplication.shared.endBackgroundTask(task)
        task = .invalid
    }
}
