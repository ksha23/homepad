import Foundation
import Observation
import WatchConnectivity

/// The watch side of WatchConnectivity. Everything goes through the paired
/// iPhone, which forwards to HomePads over the local peer link.
@MainActor
@Observable
final class WatchLink: NSObject {
    var scenes: [WatchScene] = []
    var timers: [WatchTimer] = []
    var homePads: [WatchHomePad] = []
    var isReachable = false
    var message: String?

    func activate() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    /// Asks the iPhone for scenes, timers and HomePads.
    func refresh() {
        guard WCSession.default.isReachable else {
            message = "Open HomePad on your iPhone."
            return
        }
        WCSession.default.sendMessage([WatchMessage.request: WatchMessage.snapshot]) { reply in
            nonisolated(unsafe) let reply = reply
            Task { @MainActor in self.apply(reply) }
        } errorHandler: { error in
            Task { @MainActor in self.message = error.localizedDescription }
        }
    }

    func runScene(_ scene: WatchScene) {
        WCSession.default.sendMessage([WatchMessage.request: WatchMessage.runScene, "id": scene.id]) { reply in
            let ok = reply[WatchMessage.ok] as? Bool ?? false
            Task { @MainActor in self.message = ok ? "\(scene.name) is on." : "Could not run \(scene.name)." }
        } errorHandler: { error in
            Task { @MainActor in self.message = error.localizedDescription }
        }
    }

    /// Hands a recorded clip to the iPhone. `transferFile` queues it even if the phone is briefly away.
    func sendIntercom(_ url: URL, duration: TimeInterval, to homePadID: String?) {
        WCSession.default.transferFile(url, metadata: ["kind": "intercom", "target": homePadID ?? "all", "duration": duration])
        message = "Sent"
    }

    private func apply(_ reply: [String: Any]) {
        message = nil
        scenes = (reply[WatchMessage.scenes] as? [[String: Any]] ?? []).compactMap { entry in
            guard let id = entry["id"] as? String, let name = entry["name"] as? String else { return nil }
            return WatchScene(id: id, name: name, symbol: entry["symbol"] as? String ?? "sparkles")
        }
        timers = (reply[WatchMessage.timers] as? [[String: Any]] ?? []).map { entry in
            let end = (entry["end"] as? Double).flatMap { $0 > 0 ? Date(timeIntervalSince1970: $0) : nil }
            return WatchTimer(label: entry["label"] as? String ?? "Timer", room: entry["room"] as? String ?? "",
                              isRunning: entry["status"] as? String == "running", end: end,
                              remaining: entry["remaining"] as? Double ?? 0)
        }
        homePads = (reply[WatchMessage.homePads] as? [[String: Any]] ?? []).compactMap { entry in
            guard let id = entry["id"] as? String, let name = entry["name"] as? String else { return nil }
            return WatchHomePad(id: id, name: name)
        }
    }
}

extension WatchLink: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        let reachable = session.isReachable
        Task { @MainActor in
            self.isReachable = reachable
            self.refresh()
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        let reachable = session.isReachable
        Task { @MainActor in
            self.isReachable = reachable
            if reachable { self.refresh() }
        }
    }
}
