import Foundation
import HomePadCore
import Observation
import os

/// Connects the store to whoever is recognized at the iPad. When nobody is, or
/// the person is only picked by hand, the store is locked and holds nothing.
@MainActor
@Observable
public final class CommsRuntime {
    public let services: AppServices
    public let store: CommsStore
    public let credentials: HubCredentialStore
    private let log = Log.make("Comms")

    public init(services: AppServices, store: CommsStore? = nil, credentials: HubCredentialStore = HubCredentialStore()) {
        self.services = services
        // The demo's conversations are never cached, so they never show in place of real ones.
        self.store = store ?? CommsStore(cache: Self.demoCredentials == nil ? CommsCache() : nil)
        self.credentials = credentials
    }

    /// A person took the ID the household knows them by, as this HomePad
    /// joined a household that already had them. Their Mac hub and saved
    /// conversations here stay theirs, on this iPad only.
    func moveMember(from old: UUID, to new: UUID) {
        if let saved = credentials.credentials(for: old), credentials.save(saved, for: new) {
            credentials.save(nil, for: old)
        }
        store.moveSavedMessages(from: old, to: new)
    }

    /// Starts following the household. Call once, after launch.
    public func start() {
        #if DEBUG
        if CommsDemo.isOn { CommsDemo.start() }
        #endif
        sync()
        track()
    }

    /// The stand-in hub's credentials in a demo launch (`CommsDemo`), for everyone. Nil otherwise.
    private static var demoCredentials: HubCredentials? {
        #if DEBUG
        CommsDemo.isOn ? CommsDemo.credentials : nil
        #else
        nil
        #endif
    }

    /// Re-reads who is unlocked and connects or locks to match. Does nothing when the
    /// person and their credentials are the same as the connection already running:
    /// presence sensing re-confirms the same member many times a minute, and each of
    /// those would otherwise drop and rebuild the connection.
    public func sync() {
        guard let member = currentMember else {
            if connection != nil || store.phase != .locked { store.lock() }
            connection = nil
            return
        }
        CommsLaunchSeed.apply(household: services.household, current: member, credentials: credentials)
        let saved = Self.demoCredentials ?? credentials.credentials(for: member.id)
        log.info("sync member=\(member.name, privacy: .public) hasCredentials=\(saved != nil, privacy: .public)")
        if let connection, connection.member == member.id, connection.credentials == saved { return }
        connection = Connection(member: member.id, credentials: saved)
        store.connect(saved, member: member.id)
    }

    private struct Connection: Equatable {
        var member: UUID
        var credentials: HubCredentials?
    }

    private var connection: Connection?

    /// Whose messages to show: the recognized member, or the one picked by hand when
    /// recognition is not required.
    var currentMember: HouseholdMember? {
        let household = services.household
        if requiresRecognition { return household.unlockedMember }
        return household.activeMember ?? household.members.first
    }

    /// True when messages show only to a recognized member: the choice in Settings, else on
    /// once the household has more than one person. One person alone can pick themselves.
    var requiresRecognition: Bool {
        services.settings[CommsSettings.requireRecognition] ?? (services.household.members.count > 1)
    }

    private func track() {
        withObservationTracking {
            _ = currentMember?.id
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.sync()
                self?.track()
            }
        }
    }
}
