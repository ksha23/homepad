import Foundation
import HomePadCore

/// Seeds members' hub credentials from launch arguments, so a developer can set up an
/// iPad from the Mac without typing a token on the glass. Launch arguments exist only
/// for that launch, and the credentials are then kept in the Keychain like any other.
///
/// One member (the first one recognized, or the named one):
///
///     -HomePadCommsURL http://macbook:8787 -HomePadCommsToken <token> [-HomePadCommsMember Kyle]
///
/// Several members at once, each with their own hub:
///
///     -HomePadCommsSeeds '[{"member":"Kyle","url":"http://macbook:8787","token":"..."},
///                          {"member":"Sam","url":"http://mini:8787","token":"..."}]'
enum CommsLaunchSeed {
    private struct Seed: Decodable {
        var member: String
        var url: String
        var token: String
    }

    /// The text after `name` on the command line, untouched. `UserDefaults` may reinterpret a value
    /// that looks like a property list, so JSON is read from the raw arguments first.
    private static func rawArgument(_ name: String, arguments: [String] = ProcessInfo.processInfo.arguments) -> String? {
        guard let index = arguments.firstIndex(of: name), index + 1 < arguments.count else { return nil }
        return arguments[index + 1]
    }

    /// Launch arguments reach `UserDefaults` as text, but a value that looks like a property list
    /// can arrive already parsed into an array. Both are accepted.
    private static func seeds(from value: Any?) -> [Seed]? {
        if let text = value as? String, let data = text.data(using: .utf8) {
            return try? JSONDecoder().decode([Seed].self, from: data)
        }
        if let list = value as? [[String: Any]] {
            return list.compactMap { entry in
                guard let member = entry["member"] as? String, let url = entry["url"] as? String, let token = entry["token"] as? String else { return nil }
                return Seed(member: member, url: url, token: token)
            }
        }
        return nil
    }

    /// Saves every seed that names a household member, and the single-member seed for `current`.
    @MainActor
    static func apply(household: Household, current: HouseholdMember?, credentials: HubCredentialStore, defaults: UserDefaults = .standard) {
        if let seeds = seeds(from: rawArgument("-HomePadCommsSeeds") ?? defaults.object(forKey: "HomePadCommsSeeds")) {
            for seed in seeds {
                guard let member = household.members.first(where: { $0.name.lowercased() == seed.member.lowercased() }),
                      let url = URL(string: seed.url), !seed.token.isEmpty else { continue }
                credentials.save(HubCredentials(baseURL: url, token: seed.token), for: member.id)
            }
        }
        guard let current, let address = defaults.string(forKey: "HomePadCommsURL"),
              let token = defaults.string(forKey: "HomePadCommsToken"),
              let url = URL(string: address), !token.isEmpty else { return }
        if let wanted = defaults.string(forKey: "HomePadCommsMember"), wanted.lowercased() != current.name.lowercased() { return }
        credentials.save(HubCredentials(baseURL: url, token: token), for: current.id)
    }
}
