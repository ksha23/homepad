import Foundation
import HomePadCore
import Observation

/// Whose Apple Music the Music app shows on This iPad: the recognized
/// member's own, when they linked it from their iPhone, else this iPad's own,
/// as before.
///
/// The tokens come from `services.memberMusic` (the Connect module). The
/// listings read with them are kept in each member's encrypted cache
/// (`MemberMusicCache`), which goes when their Apple Music is unlinked or they
/// leave the household.
@MainActor
@Observable
final class MemberAppleMusic {
    /// The library Music shows now, nil for this iPad's own.
    private(set) var shown: MemberMusicLibrary?
    /// Why the last play of one of their items did not start, until the next one does.
    var notice: String?

    @ObservationIgnored private unowned let services: AppServices
    @ObservationIgnored var cache = MemberMusicCache()
    /// Every cache write and delete, in order, so a save never lands after the delete that forgets a person.
    @ObservationIgnored private let cacheQueue = DispatchQueue(label: "com.ksha23.homepad.membermusic.cache", qos: .utility)
    @ObservationIgnored var makeAPI: (String) -> AppleMusicAPI = { AppleMusicAPI(userToken: $0) }
    /// `-HomePadMemberMusicDemo YES`: the recognized member has a made-up Apple Music.
    @ObservationIgnored private let isDemo: Bool

    init(services: AppServices, isDemo: Bool = MemberMusicDemo.isEnabled) {
        self.services = services
        self.isDemo = isDemo
        if isDemo {
            makeAPI = { MemberMusicDemo.api(userToken: $0) }
            cache = MemberMusicCache(directory: FileManager.default.temporaryDirectory.appendingPathComponent("MemberMusicDemo"))
        }
    }

    func start() {
        update()
        observe()
    }

    /// The member whose own Apple Music Music shows, or nil for this iPad's
    /// own: the member recognized here, when their Apple Music is linked.
    /// Someone picked in People without being recognized does not count, so
    /// nobody sees another person's library by picking them.
    nonisolated static func shownMember(unlocked: UUID?, linked: Set<UUID>) -> UUID? {
        guard let unlocked, linked.contains(unlocked) else { return nil }
        return unlocked
    }

    /// The members whose Apple Music is linked here.
    var links: [UUID: MemberMusicLink] {
        var links = services.memberMusic.links
        if isDemo, let member = services.household.unlockedMember, links[member.id] == nil {
            links[member.id] = MemberMusicLink(deviceID: "demo", deviceName: "\(member.name)'s iPhone", linkedAt: .distantPast)
        }
        return links
    }

    /// Shows the right person's library, and forgets the caches of people
    /// whose Apple Music is no longer linked or who left.
    func update() {
        let links = links
        let members = services.household.members
        let kept = Set(links.keys).intersection(members.map(\.id))
        let cache = cache
        cacheQueue.sync { cache.prune(keeping: kept) }
        guard let id = Self.shownMember(unlocked: services.household.unlockedMember?.id, linked: Set(links.keys)),
              let member = members.first(where: { $0.id == id }), let link = links[id] else {
            if shown != nil {
                shown = nil
                notice = nil
            }
            return
        }
        if let shown, shown.memberID == id, shown.link == link { return }
        let token = isDemo ? "demo" : services.memberMusic.userToken(for: id)
        let library = MemberMusicLibrary(
            memberID: id, memberName: member.name, link: link, snapshot: cache.load(member: id) ?? MemberMusicSnapshot(),
            api: token.map(makeAPI),
            save: { [weak self] snapshot in self?.write(snapshot, member: id) },
            onRejected: { [weak self] in self?.services.memberMusic.tokenRejected(for: id) }
        )
        shown = library
        notice = nil
        Task { await library.refreshHome() }
    }

    private func write(_ snapshot: MemberMusicSnapshot, member: UUID) {
        // A person who stopped being linked while a read was out leaves nothing behind.
        guard links[member] != nil else { return }
        let cache = cache
        cacheQueue.async { cache.save(snapshot, member: member) }
    }

    /// Follows who is recognized, who is in the household and whose Apple Music is linked.
    private func observe() {
        withObservationTracking {
            _ = services.household.unlockedMember?.id
            _ = services.household.members.map(\.id)
            _ = services.memberMusic.links
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.update()
                self?.observe()
            }
        }
    }
}
