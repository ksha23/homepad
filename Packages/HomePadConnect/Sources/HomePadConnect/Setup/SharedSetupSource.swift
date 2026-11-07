import Foundation
import HomePadCore

/// The documents a HomePad shares, as the household setup sync reads and
/// applies them. The live one reads the household's people and every
/// module's `SharedDocumentDescriptor`. Tests use one in memory.
@MainActor
protocol SharedSetupSource: AnyObject {
    /// The kinds this HomePad shares, people included, with their owners.
    /// This HomePad's own documents (`HomePadDocumentKind`) count as household ones.
    var kinds: [String: SharedDocumentDescriptor.Owners] { get }
    /// True for a kind this HomePad takes from others: one of `kinds`, or
    /// another HomePad's own document of a kind this HomePad knows.
    func accepts(_ kind: String) -> Bool
    /// This iPad's people now, in order.
    var members: [HouseholdMember] { get }
    func read(_ key: SetupKey) -> SharedDocumentValue
    /// Shows a document from another HomePad. Nil content deletes it here.
    func apply(_ content: JSONValue?, to key: SetupKey)
    /// Gives a person the household's ID for them, moving this iPad's data with them.
    func changeMemberID(from old: UUID, to new: UUID)
}

extension SharedSetupSource {
    func accepts(_ kind: String) -> Bool {
        kinds[kind] != nil
    }

    /// Every document key this HomePad has now: each kind for the household
    /// and for each person, as the kind allows.
    var currentKeys: [SetupKey] {
        let people = members.map(\.id)
        return kinds.flatMap { kind, owners -> [SetupKey] in
            var keys: [SetupKey] = []
            if owners.contains(.household) { keys.append(SetupKey(kind: kind, owner: .household)) }
            if owners.contains(.members) { keys += people.map { SetupKey(kind: kind, owner: .member($0)) } }
            return keys
        }
    }
}

/// The household's people from `Household`, and every other kind from the
/// modules' descriptors in the registry, each HomePad's own documents included.
@MainActor
final class LiveSetupSource: SharedSetupSource {
    private let household: Household
    private let registry: ModuleRegistry
    /// This HomePad's peer-link device ID, which names its own documents.
    private let deviceID: String

    init(household: Household, registry: ModuleRegistry, deviceID: String) {
        self.household = household
        self.registry = registry
        self.deviceID = deviceID
    }

    var kinds: [String: SharedDocumentDescriptor.Owners] {
        var kinds = Dictionary(registry.sharedDocuments.map { ($0.id, $0.owners) }, uniquingKeysWith: { first, _ in first })
        kinds[SetupKey.memberKind] = .members
        for document in registry.homePadDocuments {
            kinds[HomePadDocumentKind.make(document.id, homePad: deviceID)] = .household
        }
        return kinds
    }

    func accepts(_ kind: String) -> Bool {
        if kinds[kind] != nil { return true }
        guard let split = HomePadDocumentKind.split(kind) else { return false }
        return homePadDescriptor(split.kind) != nil
    }

    var members: [HouseholdMember] { household.members }

    func read(_ key: SetupKey) -> SharedDocumentValue {
        if let split = HomePadDocumentKind.split(key.kind) {
            return readHomePadDocument(split.kind, of: split.homePad)
        }
        guard key.kind == SetupKey.memberKind else {
            return descriptor(key.kind)?.read(key.owner) ?? .none
        }
        guard let id = key.owner.memberID, let member = household.members.first(where: { $0.id == id }),
              let content = try? JSONValue(encoding: SharedMember(member)) else { return .none }
        return .content(content)
    }

    func apply(_ content: JSONValue?, to key: SetupKey) {
        if let split = HomePadDocumentKind.split(key.kind) {
            // Only the HomePad a document describes writes it.
            guard split.homePad != deviceID else { return }
            homePadDescriptor(split.kind)?.apply(split.homePad, content)
            return
        }
        guard key.kind == SetupKey.memberKind else {
            descriptor(key.kind)?.apply(key.owner, content)
            return
        }
        guard let id = key.owner.memberID else { return }
        guard let content else {
            household.remove(id)
            return
        }
        guard let shared = try? content.decoded(as: SharedMember.self), shared.id == id else { return }
        household.applyShared(shared)
    }

    func changeMemberID(from old: UUID, to new: UUID) {
        household.changeMemberID(from: old, to: new)
    }

    private func descriptor(_ kind: String) -> SharedDocumentDescriptor? {
        registry.sharedDocuments.first { $0.id == kind }
    }

    private func homePadDescriptor(_ kind: String) -> HomePadDocumentDescriptor? {
        registry.homePadDocuments.first { $0.id == kind }
    }

    /// This HomePad's own document as it is now. Another HomePad's stays as it
    /// was shared, since only that HomePad changes it.
    private func readHomePadDocument(_ kind: String, of homePad: String) -> SharedDocumentValue {
        guard homePad == deviceID else { return .onlyThisHomePad }
        return homePadDescriptor(kind)?.read() ?? .none
    }
}
