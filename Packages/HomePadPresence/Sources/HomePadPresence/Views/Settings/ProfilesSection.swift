import HomePadCore
import SwiftUI

/// How long HomePad stays in a person's profile once it stops seeing them
/// (`CoreSettings.signOutAfter`, enforced by the household's `MemberSession`).
/// It applies to every way in: a recognized face, Face ID, a personal device
/// and a pick in the People menu.
struct ProfilesSection: View {
    @Environment(AppServices.self) private var services

    var body: some View {
        Section {
            Picker("Switch to Guest After", selection: services.settings.binding(CoreSettings.signOutAfter)) {
                ForEach(CoreSettings.signOutAfterChoices, id: \.self) { Text(Self.title(seconds: $0)).tag($0) }
            }
        } header: {
            Text("Profiles")
        } footer: {
            Text("How long HomePad keeps showing a person's Home Screen and personal content after it last saw them. A touch counts while the camera sees no face. Someone else's face switches at once: to their own profile when their face is set up, or to Guest when the camera is sure it does not know them.")
        }
    }

    private static func title(seconds: Double) -> String {
        Duration.seconds(seconds).formatted(.units(allowed: [.minutes, .seconds], width: .wide))
    }
}
