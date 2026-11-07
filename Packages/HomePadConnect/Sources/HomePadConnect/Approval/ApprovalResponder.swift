import Foundation
import HomePadCore
import Observation

/// On a phone or Mac: answers HomePads' approval requests for the member this
/// device is linked to, and links it to a member on each HomePad.
///
/// A request shows as `prompt` (the sheet over the companion, and a local
/// notification when the app is not in front) only when it comes from the
/// HomePad it names, for the member this device is linked to there, has not
/// been seen before, and is still inside its lifetime counted from arrival.
@MainActor
@Observable
public final class ApprovalResponder {
    /// A request on screen.
    public struct Prompt: Identifiable, Equatable {
        public let request: ApprovalRequest
        public let memberName: String
        /// When the prompt goes away, on this device's clock.
        public let deadline: Date

        public var id: UUID { request.id }
        public var homePadID: String { request.homePadID }
    }

    public private(set) var prompt: Prompt?
    /// Why the last approval did not go through, shown in the prompt.
    public private(set) var promptError: String?
    public private(set) var isApproving = false
    /// What each HomePad holds for this device, by HomePad ID.
    public private(set) var states: [String: ApprovalLinkState] = [:]
    /// Why linking failed on a HomePad, by HomePad ID.
    public private(set) var linkErrors: [String: String] = [:]

    @ObservationIgnored private let services: AppServices
    @ObservationIgnored private let link: PeerLink
    /// Sends one message to one HomePad, the link by default. Tests put a HomePad in memory behind it.
    @ObservationIgnored var transmit: @MainActor (PeerMessage, String) async throws -> Void
    @ObservationIgnored var now: () -> Date = Date.init
    /// Verifies the person and signs. Face ID or the passcode by default.
    @ObservationIgnored var sign: @MainActor (Data, String) async throws -> Data = DeviceApprovalKey.signApproval
    @ObservationIgnored var publicKey: @MainActor () throws -> Data = DeviceApprovalKey.publicKey
    /// Shows a request as a system notification while the app is not in front, and takes it away.
    @ObservationIgnored var notifications: ApprovalNotifying = ApprovalNotifications()
    /// Requests already shown, by when they arrived, so a repeat is ignored.
    @ObservationIgnored private var seen: [UUID: Date] = [:]
    @ObservationIgnored private var expiry: Task<Void, Never>?
    @ObservationIgnored private let log = Log.make("Approval")

    /// Device-local: who this device approves for, by HomePad ID, as each HomePad last said.
    static let linkedMembersKey = SettingKey<[String: UUID]>("connect.approval.linkedMembers", default: [:])

    init(services: AppServices, link: PeerLink) {
        self.services = services
        self.link = link
        self.transmit = { [weak link] message, peerID in
            guard let link else { throw PeerLinkError.notConnected }
            try await link.send(message, to: peerID)
        }
        #if DEBUG
        if UserDefaults.standard.bool(forKey: "ConnectApprovalSkipVerify") {
            sign = { data, _ in try DeviceApprovalKey.signWithoutVerifying(data) }
        }
        #endif
    }

    func start() {
        link.on(.approvalState) { [weak self] message, peer in
            guard peer.kind == .homePad, let state = try? message.content(ApprovalLinkState.self) else { return }
            self?.receive(state, from: peer.id)
        }
        link.on(.approvalRequest) { [weak self] message, peer in
            guard let request = try? message.content(ApprovalRequest.self) else { return }
            self?.receive(request, from: peer)
        }
        link.on(.approvalClosed) { [weak self] message, peer in
            guard let closed = try? message.content(ApprovalClosed.self),
                  self?.prompt?.id == closed.requestID, self?.prompt?.homePadID == peer.id else { return }
            self?.close(closed.requestID)
        }
        link.onConnect { [weak self] peer in
            guard peer.kind == .homePad else { return }
            Task { await self?.requestState(of: peer.id) }
        }
    }

    // MARK: Linking

    /// Who this device approves for on a HomePad.
    public func linkedMember(on homePadID: String) -> UUID? {
        states[homePadID]?.linkedMemberID ?? services.settings[Self.linkedMembersKey][homePadID]
    }

    /// Asks a HomePad what it holds for this device, including its household.
    public func requestState(of homePadID: String) async {
        guard let message = try? link.message(.approvalStateRequest, [String: String]()) else { return }
        try? await transmit(message, homePadID)
    }

    /// Asks a HomePad to let this device approve for `member`, or with nil, to stop.
    public func linkMember(_ member: ApprovalMember?, on homePadID: String) async {
        linkErrors[homePadID] = nil
        do {
            let kind = link.identity.kind
            let body = ApprovalLinkRequest(
                memberID: member?.id,
                deviceName: member.map { "\($0.name)'s \(kind.displayName)" } ?? kind.displayName,
                publicKey: try publicKey()
            )
            try await transmit(try link.message(.approvalLink, body), homePadID)
            var state = states[homePadID] ?? ApprovalLinkState()
            state.message = nil
            if let member {
                state.pendingMemberID = member.id
            } else {
                state.linkedMemberID = nil
                state.pendingMemberID = nil
            }
            states[homePadID] = state
        } catch {
            log.error("Linking failed: \(error.localizedDescription, privacy: .public)")
            linkErrors[homePadID] = error.localizedDescription
        }
    }

    func receive(_ state: ApprovalLinkState, from homePadID: String) {
        states[homePadID] = state
        if let message = state.message { linkErrors[homePadID] = message }
        var linked = services.settings[Self.linkedMembersKey]
        guard linked[homePadID] != state.linkedMemberID else { return }
        linked[homePadID] = state.linkedMemberID
        services.settings[Self.linkedMembersKey] = linked
    }

    // MARK: Requests

    func receive(_ request: ApprovalRequest, from peer: PeerDevice) {
        let now = now()
        seen = seen.filter { now.timeIntervalSince($0.value) < 600 }
        guard peer.kind == .homePad, request.homePadID == peer.id else {
            log.info("Ignored a request that did not come from the HomePad it names")
            return
        }
        guard let member = linkedMember(on: peer.id), member == request.memberID else {
            log.info("Ignored a request for someone this device does not approve for")
            return
        }
        guard seen[request.id] == nil, request.lifetime > 0 else { return }
        seen[request.id] = now
        let lifetime = min(request.lifetime, ApprovalPolicy.requestLifetime)
        let name = states[peer.id]?.linkedMember?.name ?? "you"
        let prompt = Prompt(request: request, memberName: name, deadline: now.addingTimeInterval(lifetime))
        if let old = self.prompt { notifications.remove(old.id) }
        log.info("Showing request \(request.id.uuidString.prefix(8), privacy: .public) from \(peer.name, privacy: .public)")
        self.prompt = prompt
        promptError = nil
        notifications.show(prompt)
        expiry?.cancel()
        expiry = Task { [weak self] in
            try? await Task.sleep(for: .seconds(lifetime))
            guard !Task.isCancelled else { return }
            self?.close(request.id)
        }
        #if DEBUG
        if let answer = ApprovalDebug.automaticAnswer {
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(3))
                guard let self, self.prompt?.id == request.id else { return }
                if answer == .approve { await self.approve() } else { await self.deny() }
            }
        }
        #endif
    }

    /// Verifies the person, signs the request and sends the approval.
    public func approve() async {
        guard let prompt, !isApproving else { return }
        guard now() < prompt.deadline else { return close(prompt.id) }
        isApproving = true
        defer { isApproving = false }
        promptError = nil
        let request = prompt.request
        do {
            let signature = try await sign(request.signedBytes(for: .approve), "Unlock \(request.appTitle) on \(request.homePadName)")
            // The request may have run out or closed while Face ID was up.
            guard self.prompt?.id == request.id, now() < prompt.deadline else { return }
            let response = ApprovalResponse(requestID: request.id, decision: .approve, signature: signature)
            try await transmit(try link.message(.approvalResponse, response), request.homePadID)
            close(request.id)
        } catch DeviceApprovalKey.Failure.cancelled {
            // Face ID was cancelled. The prompt stays so the person can try again or say no.
        } catch {
            log.error("Approving failed: \(error.localizedDescription, privacy: .public)")
            promptError = error.localizedDescription
        }
    }

    /// Says no. The HomePad shows that the person declined.
    public func deny() async {
        guard let prompt else { return }
        close(prompt.id)
        let response = ApprovalResponse(requestID: prompt.id, decision: .deny)
        do {
            try await transmit(try link.message(.approvalResponse, response), prompt.homePadID)
        } catch {
            log.error("Denying failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func close(_ id: UUID) {
        guard prompt?.id == id else { return }
        log.info("Closed request \(id.uuidString.prefix(8), privacy: .public)")
        prompt = nil
        promptError = nil
        expiry?.cancel()
        notifications.remove(id)
    }
}
