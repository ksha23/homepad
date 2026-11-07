import Foundation
import Testing
@testable import HomePadCore

/// The store keeps decoded values, so writes, resets and optional values must
/// still read back exactly what is stored.
@MainActor @Suite struct SettingsStoreTests {
    private let count = SettingKey<Int>("test.count", default: 3)
    private let name = SettingKey<String?>("test.name", default: "fallback")

    private func makeStore() -> (SettingsStore, UserDefaults) {
        let defaults = UserDefaults(suiteName: "test.settings.\(UUID())")!
        return (SettingsStore(defaults: defaults), defaults)
    }

    @Test func readsDefaultsThenWritesThenResets() {
        let (store, _) = makeStore()
        #expect(store[count] == 3)
        store[count] = 7
        #expect(store[count] == 7)
        store[count] = 8
        #expect(store[count] == 8)
        store.reset(count)
        #expect(store[count] == 3)
    }

    @Test func keepsOptionalValuesApartFromMissingOnes() {
        let (store, _) = makeStore()
        #expect(store[name] == "fallback")
        store[name] = nil
        #expect(store[name] == nil)
        store[name] = "Kitchen"
        #expect(store[name] == "Kitchen")
    }

    @Test func undecodableDataReadsAsTheDefault() {
        let (store, defaults) = makeStore()
        defaults.set(Data("not json".utf8), forKey: count.name)
        #expect(store[count] == 3)
        #expect(store[count] == 3)
    }

    @Test func everyWriteBumpsTheRevision() {
        let (store, _) = makeStore()
        let start = store.revision
        store[count] = 1
        store.reset(count)
        #expect(store.revision == start + 2)
    }
}
