import Foundation
import HomePadCore
import Observation

/// Turns HomeKit IDs saved on another HomePad into this HomePad's own.
///
/// It holds this HomePad's `HomeKitDirectory`, which the household's other
/// HomePads receive, and the directory of every other HomePad, kept on this
/// iPad. Each foreign ID that `HomeKitIDMatcher` pairs with one of this
/// HomePad's objects goes in `table`, and `localID(for:)` reads it.
///
/// Pairs it once made are remembered on this iPad. HomeKit's IDs never change,
/// so a pair stays true, and it keeps working when an accessory is renamed
/// while the HomePad that saved it is off and its directory still has the old
/// name, or when a second accessory with the same name joins the room. A fresh
/// pair from the directories replaces a remembered one, and a remembered pair
/// goes once its object is gone from this HomePad.
@MainActor
@Observable
final class HomeKitIDTranslator {
    /// This HomePad's ID for each foreign HomeKit ID it can pair.
    private(set) var table: [String: String]
    /// This HomePad's own directory, the last one Apple Home loaded since
    /// launch. Nil until then, when the copy shared before stays shared.
    private(set) var local: HomeKitDirectory?
    /// `local` as the shared setup carries it, made once per change, since
    /// the setup reads it on every scan.
    private(set) var sharedContent: JSONValue?

    /// Called after another HomePad's directory arrived and changed `table`.
    @ObservationIgnored var onChange: (() -> Void)?

    @ObservationIgnored private var others: [String: HomeKitDirectory]
    @ObservationIgnored private var remembered: [String: String]
    @ObservationIgnored private let settings: SettingsStore

    init(settings: SettingsStore) {
        self.settings = settings
        others = settings[SmartHomeSettings.homeKitOtherDirectories]
        remembered = settings[SmartHomeSettings.homeKitTranslations]
        table = remembered
    }

    /// This HomePad's ID for a saved one, or the ID itself.
    func localID(for id: String) -> String {
        table[id] ?? id
    }

    /// Takes this HomePad's directory after Apple Home loaded or changed.
    func updateLocal(_ directory: HomeKitDirectory) {
        guard directory != local else { return }
        local = directory
        sharedContent = try? JSONValue(encoding: directory)
        recompute()
    }

    /// Another HomePad's directory, from the shared setup. Nil when it has none any more.
    func receive(_ directory: HomeKitDirectory?, from homePad: String) {
        guard others[homePad] != directory else { return }
        others[homePad] = directory
        settings[SmartHomeSettings.homeKitOtherDirectories] = others
        if recompute() { onChange?() }
    }

    /// The directories this HomePad holds from others, by HomePad.
    var otherDirectories: [String: HomeKitDirectory] { others }

    /// Pairs the foreign IDs again. Returns true when `table` changed.
    @discardableResult
    private func recompute() -> Bool {
        let next = local.map(translations(local:)) ?? remembered
        if next != remembered {
            remembered = next
            settings[SmartHomeSettings.homeKitTranslations] = next
        }
        guard next != table else { return false }
        table = next
        return true
    }

    /// Fresh pairs from every other HomePad's directory, over the remembered
    /// pairs whose object is still on this HomePad. An object removed from a
    /// home leaves every iPad, so that is when its pairs go.
    private func translations(local: HomeKitDirectory) -> [String: String] {
        let localIDs = Set(local.entries.map(\.id))
        var result = remembered.filter { localIDs.contains($0.value) }
        for directory in others.values {
            let fresh = HomeKitIDMatcher.translations(from: directory, to: local)
            result.merge(fresh) { _, fresh in fresh }
        }
        // This HomePad's own IDs always stand for themselves.
        return result.filter { !localIDs.contains($0.key) }
    }
}
