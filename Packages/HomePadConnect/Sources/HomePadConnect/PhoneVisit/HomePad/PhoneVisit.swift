import Foundation
import HomePadCore

/// On a HomePad: one visit of a recognized member whose phone shares some of
/// their data with it. One wake, one challenge and one session serve every
/// kind the phone shares. What each kind keeps lives in its own part
/// (`PhoneVisitPart`), and everything here lives only as long as the visit.
@MainActor
final class PhoneVisit {
    let memberID: UUID
    let deviceID: String
    let deviceName: String
    let wakeTag: Data
    /// What the phone said it shares with this HomePad, in its offers.
    let kinds: Set<PhoneDataKind>
    /// What the phone opened to the granted session.
    var grantedKinds: Set<PhoneDataKind> = []
    /// The phone opened at least once during this visit.
    var hasAnswered = false
    /// The session the phone opened on, while it is open.
    var grantedSession: UUID?
    /// The hello waiting for a challenge, and who waits for the phone to open.
    var helloID: UUID?
    var openWaiters: [UUID: CheckedContinuation<Bool, Never>] = [:]
    /// Requests waiting for their answer, by request ID.
    var replyWaiters: [UUID: CheckedContinuation<PeerMessage?, Never>] = [:]
    /// The first fetch of every part is done, so the session may close once
    /// nothing waits for an answer.
    var hasFetched = false
    /// The last Bluetooth wake, so a phone is not woken over and over.
    var lastWake: Date?

    init(memberID: UUID, deviceID: String, deviceName: String, wakeTag: Data, kinds: Set<PhoneDataKind>) {
        self.memberID = memberID
        self.deviceID = deviceID
        self.deviceName = deviceName
        self.wakeTag = wakeTag
        self.kinds = kinds
    }

    /// Lets everyone waiting go with nothing.
    func finish() {
        openWaiters.values.forEach { $0.resume(returning: false) }
        replyWaiters.values.forEach { $0.resume(returning: nil) }
        openWaiters = [:]
        replyWaiters = [:]
        grantedSession = nil
        grantedKinds = []
    }
}

/// On a HomePad: one kind of a person's data a phone visit carries. Each
/// keeps its own state for the visit and its own encrypted cache.
@MainActor
protocol PhoneVisitPart: AnyObject {
    /// The kinds this part asks the phone for.
    var kinds: Set<PhoneDataKind> { get }
    /// A visit began. Shows what was saved, if this kind may show before the phone answers.
    func visitStarted(_ visit: PhoneVisit)
    /// The visit's first fetch, inside the few seconds a woken phone runs.
    /// Called only when the phone opened one of `kinds`.
    func prefetch(_ visit: PhoneVisit) async
    /// The phone opened, joined or left the peer link: show it.
    func publish(_ visit: PhoneVisit)
    /// The phone joined the peer link again after the visit's first fetch.
    func phoneConnected(_ visit: PhoneVisit)
    /// The visit ended: drop everything of the person held in memory.
    func visitEnded(_ visit: PhoneVisit)
    /// Deletes what is saved of `member` for the kinds they stopped sharing.
    /// `kinds` is what they still share of this part's kinds, empty when nothing.
    func forget(_ member: UUID, keeping kinds: Set<PhoneDataKind>)
    /// Deletes what is saved of everyone not in `members`.
    func prune(keeping members: Set<UUID>)
}
