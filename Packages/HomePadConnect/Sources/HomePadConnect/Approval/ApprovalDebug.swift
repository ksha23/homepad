#if DEBUG
import CryptoKit
import Foundation
import HomePadCore

/// Launch arguments for checking Use Personal Device in simulators. Debug
/// builds only.
///
///     -ConnectDemoPersonalDevice YES     HomePad: the first member gets a made-up paired iPhone,
///                                        so the gate shows Use Personal Device (it cannot answer)
///     -ConnectAllowLinks YES             HomePad: allows link requests 3 seconds after they arrive, without Face ID
///     -ConnectLinkMember <name>          iPhone: links to that member on the first HomePad that lists them
///     -ConnectApprovalSkipVerify YES     iPhone: approves without Face ID (the simulator has no passcode)
///     -ConnectApprovalAnswer approve|deny   iPhone: answers each prompt 3 seconds after it shows
///     -ConnectDemoApprovalPrompt YES     iPhone: shows a made-up prompt from Kitchen, for screenshots
@MainActor
enum ApprovalDebug {
    static func start(_ runtime: ConnectRuntime) {
        let defaults = UserDefaults.standard
        if runtime.isHomePad, defaults.bool(forKey: "ConnectDemoPersonalDevice") {
            Task {
                // The shell adds its demo people after Connect starts.
                try? await Task.sleep(for: .seconds(2))
                seedDemoDevice(runtime)
            }
        }
        if !runtime.isHomePad, let name = defaults.string(forKey: "ConnectLinkMember") {
            Task { await link(runtime, to: name) }
        }
        if !runtime.isHomePad, defaults.bool(forKey: "ConnectDemoApprovalPrompt") {
            showDemoPrompt(runtime.approvals)
        }
    }

    /// The answer `-ConnectApprovalAnswer` asks for, if any.
    static var automaticAnswer: ApprovalDecision? {
        UserDefaults.standard.string(forKey: "ConnectApprovalAnswer").flatMap(ApprovalDecision.init(rawValue:))
    }

    private static func seedDemoDevice(_ runtime: ConnectRuntime) {
        guard let member = runtime.services.household.members.first,
              runtime.approver.store.devices(for: member.id).isEmpty else { return }
        runtime.approver.store.save(LinkedDevice(
            id: "demo-phone", name: "\(member.name)'s iPhone", kind: .iPhone, memberID: member.id,
            publicKey: P256.Signing.PrivateKey().publicKey.rawRepresentation,
            remoteVersion: RemoteProtocol.current, linkedAt: Date()
        ))
    }

    /// Waits up to two minutes for a HomePad that lists `name`, then links to them.
    private static func link(_ runtime: ConnectRuntime, to name: String) async {
        for _ in 0..<120 {
            if let pad = runtime.link.homePads.first(where: \.isConnected) {
                let approvals = runtime.approvals
                if approvals.linkedMember(on: pad.id) != nil { return }
                if let member = approvals.states[pad.id]?.members.first(where: { $0.name == name }) {
                    await approvals.linkMember(member, on: pad.id)
                    return
                }
                await approvals.requestState(of: pad.id)
            }
            try? await Task.sleep(for: .seconds(1))
        }
    }

    private static func showDemoPrompt(_ approvals: ApprovalResponder) {
        let pad = PeerDevice(id: "demo-kitchen", name: "Kitchen", kind: .homePad, isConnected: true)
        let kyle = ApprovalMember(id: UUID(), name: "Kyle", avatar: "🦊", colorHex: "#0A84FF")
        approvals.receive(ApprovalLinkState(members: [kyle], linkedMemberID: kyle.id), from: pad.id)
        approvals.receive(ApprovalRequest(memberID: kyle.id, homePadID: pad.id, homePadName: pad.name,
                                          appID: "messages", appTitle: "Messages"), from: pad)
    }
}
#endif
