import Foundation
import HomePadCore
import Observation
import UIKit

/// Takes a back-camera still at a fixed interval and saves it to a Photos
/// album. Long intervals hand the camera back to presence sensing between shots.
@MainActor
@Observable
final class TimelapseController {
    static let owner = "cameralab.timelapse"

    private(set) var isRunning = false
    private(set) var framesThisSession = 0
    private(set) var lastFrame: UIImage?
    private(set) var nextShotAt: Date?
    private(set) var problem: String?

    @ObservationIgnored private let services: AppServices
    @ObservationIgnored private let broker: CameraBroker
    @ObservationIgnored private var loop: Task<Void, Never>?
    @ObservationIgnored private let log = Log.make("CameraLab.Timelapse")

    init(services: AppServices, broker: CameraBroker) {
        self.services = services
        self.broker = broker
    }

    var interval: TimelapseInterval { services.settings[CameraLabSettings.timelapseInterval] }
    var albumName: String { services.settings[CameraLabSettings.timelapseAlbum] }

    /// Resumes a timelapse that was running when HomePad last quit.
    func restoreIfNeeded() {
        guard services.settings[CameraLabSettings.timelapseRunning], PhotoAlbumLibrary.hasAccess else { return }
        begin()
    }

    /// Asks for Photos access the first time, then starts shooting.
    func start() async {
        guard !isRunning else { return }
        guard await PhotoAlbumLibrary.requestAccess() else {
            problem = PhotoAlbumLibrary.LibraryError.accessDenied.errorDescription
            return
        }
        begin()
    }

    func stop() {
        loop?.cancel()
        loop = nil
        isRunning = false
        nextShotAt = nil
        services.settings[CameraLabSettings.timelapseRunning] = false
        broker.release(Self.owner)
    }

    private func begin() {
        isRunning = true
        problem = nil
        framesThisSession = 0
        services.settings[CameraLabSettings.timelapseRunning] = true
        loop = Task { [weak self] in
            while let self, !Task.isCancelled {
                await self.shoot()
                let wait = self.interval.seconds
                self.nextShotAt = Date().addingTimeInterval(wait)
                try? await Task.sleep(for: .seconds(wait))
            }
        }
    }

    private func shoot() async {
        let interval = interval
        do {
            if interval.keepsCameraBetweenShots,
               case .denied(let reason) = broker.acquire(Self.owner, title: CameraLabTool.timelapse.title, camera: .back) {
                throw CameraLabError.cameraUnavailable(reason)
            }
            if !interval.keepsCameraBetweenShots { broker.release(Self.owner) }
            let still = try await StillGrabber(broker: broker).grab(owner: Self.owner, title: CameraLabTool.timelapse.title, maxDimension: 2400)
            try await PhotoAlbumLibrary.save(jpeg: still.jpeg, toAlbum: albumName)
            lastFrame = still.image
            framesThisSession += 1
            problem = nil
        } catch {
            problem = error.localizedDescription
            log.error("Timelapse shot failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
