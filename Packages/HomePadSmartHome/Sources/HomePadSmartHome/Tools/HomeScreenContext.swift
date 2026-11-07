import HomePadCore
import SwiftUI

/// What the Home app shows full screen, so the assistant can tell what "this"
/// is. The Home app keeps it current with `reportsScreenFocus(_:)`.
struct HomeScreenFocus: Equatable {
    var accessoryID: HomeAccessory.ID?
    var cameraID: HomeCamera.ID?
    var showsAllCameras = false
}

/// What the Home app and the doorbell show, for the assistant: an accessory's
/// controls, a camera full screen with the doors beside it, the camera grid,
/// or the doorbell ringing. "Unlock this door" then finds the lock.
@MainActor
enum HomeScreenContext {
    static func provider(service: UnifiedSmartHomeService) -> ScreenContextProvider {
        ScreenContextProvider(appID: SmartHomeModule.homeAppID) { summary(of: service.screenFocus, service: service) }
    }

    /// The doorbell shows over every screen, so it speaks up whatever app is open.
    static func doorbell(_ presenter: DoorbellPresenter, service: UnifiedSmartHomeService) -> ScreenContextProvider {
        ScreenContextProvider(id: "smarthome.doorbell", appID: nil) {
            guard let ring = presenter.ring else { return nil }
            let camera = service.camera(ring.cameraID).map { "the \($0.name) camera" } ?? "its camera"
            let lock = service.doorbellLock.map { " Its door lock: \(describe($0))." } ?? ""
            return "The doorbell is ringing, and \(camera) shows over the screen.\(lock)"
        }
    }

    static func summary(of focus: HomeScreenFocus, service: UnifiedSmartHomeService) -> String? {
        if let id = focus.accessoryID, let accessory = service.allAccessories.first(where: { $0.id == id }) {
            return "The full-screen controls for \(describe(accessory))."
        }
        if let id = focus.cameraID, let camera = service.camera(id) {
            let doors = doors(beside: camera, service: service).map(describe)
            return "The \(camera.name) camera, live and full screen."
                + (doors.isEmpty ? "" : " Doors beside it: \(doors.joined(separator: "; ")).")
        }
        if focus.showsAllCameras, !service.cameras.isEmpty {
            return "Every camera in a grid: \(service.cameras.map(\.name).joined(separator: ", "))."
        }
        return nil
    }

    /// "Front Door (lock in the Entryway, Locked)", by the name control_device takes.
    private static func describe(_ accessory: HomeAccessory) -> String {
        let room = accessory.room.map { " in the \($0)" } ?? ""
        let status = accessory.statusText.isEmpty ? "" : ", \(accessory.statusText)"
        return "\(accessory.name) (\(accessory.kind.rawValue)\(room)\(status))"
    }

    /// Locks and garage doors in the camera's room, and the doorbell's lock for a doorbell camera.
    private static func doors(beside camera: HomeCamera, service: UnifiedSmartHomeService) -> [HomeAccessory] {
        var doors = service.accessories.filter { [.lock, .garageDoor].contains($0.kind) && camera.room != nil && $0.room == camera.room }
        let isDoorbell = camera.isDoorbell || service.doorbell.cameraID == camera.id
        if isDoorbell, let lock = service.doorbellLock, !doors.contains(lock) {
            doors.append(lock)
        }
        return doors
    }
}

extension View {
    /// Keeps the service's `screenFocus` in step with what the Home app shows full screen.
    func reportsScreenFocus(_ focus: HomeScreenFocus) -> some View {
        modifier(HomeScreenFocusReporter(focus: focus))
    }
}

private struct HomeScreenFocusReporter: ViewModifier {
    let focus: HomeScreenFocus
    @Environment(UnifiedSmartHomeService.self) private var service

    func body(content: Content) -> some View {
        content
            .onChange(of: focus, initial: true) { service.screenFocus = focus }
            .onDisappear { service.screenFocus = HomeScreenFocus() }
    }
}
