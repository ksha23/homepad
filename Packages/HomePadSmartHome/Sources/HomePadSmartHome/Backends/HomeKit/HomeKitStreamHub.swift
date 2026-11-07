import Foundation
@preconcurrency import HomeKit
import Observation

/// Shares HomeKit camera streams between views. A camera's stream control has one
/// delegate and one stream, so the grid cell and the full-screen view of the same
/// camera borrow it here with reference counting instead of fighting over it.
@MainActor
@Observable
final class HomeKitStreamHub {
    private(set) var streams: [UUID: HMCameraStream] = [:]
    @ObservationIgnored private var users: [UUID: Int] = [:]
    @ObservationIgnored private var profileIDs: [ObjectIdentifier: UUID] = [:]
    @ObservationIgnored private let delegate = Delegate()

    init() {
        delegate.hub = self
    }

    func stream(for profile: HMCameraProfile) -> HMCameraStream? {
        streams[profile.uniqueIdentifier]
    }

    /// Starts the stream for the first user. Call `release` when the view goes away.
    func acquire(_ profile: HMCameraProfile) {
        guard let control = profile.streamControl else { return }
        let id = profile.uniqueIdentifier
        users[id, default: 0] += 1
        guard users[id] == 1 else { return }
        profileIDs[ObjectIdentifier(control)] = id
        control.delegate = delegate
        control.startStream()
    }

    /// Stops the stream when its last user leaves.
    func release(_ profile: HMCameraProfile) {
        let id = profile.uniqueIdentifier
        guard let count = users[id] else { return }
        if count > 1 {
            users[id] = count - 1
            return
        }
        users[id] = nil
        streams[id] = nil
        profile.streamControl?.stopStream()
    }

    fileprivate func controlDidChange(_ control: HMCameraStreamControl) {
        guard let id = profileIDs[ObjectIdentifier(control)] else { return }
        streams[id] = users[id] == nil ? nil : control.cameraStream
    }

    private final class Delegate: NSObject, HMCameraStreamControlDelegate {
        @MainActor weak var hub: HomeKitStreamHub?

        func cameraStreamControlDidStartStream(_ cameraStreamControl: HMCameraStreamControl) {
            Task { @MainActor in self.hub?.controlDidChange(cameraStreamControl) }
        }

        func cameraStreamControl(_ cameraStreamControl: HMCameraStreamControl, didStopStreamWithError error: Error?) {
            Task { @MainActor in self.hub?.controlDidChange(cameraStreamControl) }
        }
    }
}
