#if os(iOS)
import Foundation
import HomePadCore
import WatchConnectivity

/// On the iPhone companion: answers the HomePad Apple Watch app over
/// WatchConnectivity and forwards its intercom clips over the peer link.
///
/// The watch speaks a tiny dictionary protocol. Keep `WatchMessage` in sync with
/// `Watch/WatchProtocol.swift` in the watch target.
@MainActor
final class WatchBridge: NSObject {
    private let services: AppServices
    private let link: PeerLink
    private let remote: RemoteHomePads
    private let intercom: IntercomHub
    private let log = Log.make("Watch")

    init(services: AppServices, link: PeerLink, remote: RemoteHomePads, intercom: IntercomHub) {
        self.services = services
        self.link = link
        self.remote = remote
        self.intercom = intercom
    }

    func start() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    /// Scenes, timers and HomePads for the watch's glances.
    private func snapshot() async -> [String: Any] {
        await remote.refresh()
        let localScenes = services.smartHome.scenes.filter { $0.backend != .demo }
        let scenes = localScenes.isEmpty ? remote.scenes : localScenes
        return [
            WatchMessage.scenes: scenes.map { ["id": $0.id, "name": $0.name, "symbol": $0.systemImage] },
            WatchMessage.timers: remote.timers.map { entry in
                ["label": entry.timer.label, "room": entry.homePad, "status": entry.timer.status.rawValue,
                 "remaining": entry.timer.remaining(), "end": entry.timer.endDate?.timeIntervalSince1970 ?? 0]
            },
            WatchMessage.homePads: link.homePads.map { ["id": $0.id, "name": $0.name] },
        ]
    }

    private func runScene(_ id: String) async -> Bool {
        if services.smartHome.scenes.contains(where: { $0.id == id }) {
            return (try? await services.smartHome.activateScene(id)) != nil
        }
        return (try? await remote.send(.runScene(id: id))) != nil
    }

    private func handle(_ message: [String: Any]) async -> [String: Any] {
        switch message[WatchMessage.request] as? String {
        case WatchMessage.snapshot:
            return await snapshot()
        case WatchMessage.runScene:
            let ok = await runScene(message["id"] as? String ?? "")
            return [WatchMessage.ok: ok]
        default:
            return [WatchMessage.ok: false]
        }
    }

    private func forwardClip(at url: URL, metadata: [String: Any]) async {
        let target = (metadata["target"] as? String).flatMap { $0 == "all" ? nil : IntercomTarget.device(id: $0) } ?? .everyone
        let duration = metadata["duration"] as? Double ?? 0
        do {
            try await intercom.sendClip(at: url, duration: duration, to: target)
        } catch {
            log.error("Watch intercom forward failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}

extension WatchBridge: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {}
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}
    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        nonisolated(unsafe) let message = message
        nonisolated(unsafe) let reply = replyHandler
        Task { @MainActor in reply(await self.handle(message)) }
    }

    nonisolated func session(_ session: WCSession, didReceive file: WCSessionFile) {
        // The file is deleted when this method returns, so copy it first.
        let copy = FileManager.default.temporaryDirectory.appendingPathComponent("watch-\(UUID().uuidString).m4a")
        guard (try? FileManager.default.copyItem(at: file.fileURL, to: copy)) != nil else { return }
        nonisolated(unsafe) let metadata = file.metadata ?? [:]
        Task { @MainActor in await self.forwardClip(at: copy, metadata: metadata) }
    }
}

/// Keys shared with the watch app. Mirrors `Watch/WatchProtocol.swift`.
enum WatchMessage {
    static let request = "request"
    static let snapshot = "snapshot"
    static let runScene = "runScene"
    static let ok = "ok"
    static let scenes = "scenes"
    static let timers = "timers"
    static let homePads = "homePads"
}
#endif
