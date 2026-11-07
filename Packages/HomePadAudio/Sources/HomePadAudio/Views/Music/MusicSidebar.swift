import HomePadCore
import HomePadUI
import SwiftUI

/// The Music app's sidebar, like Apple Music on iPad: the main sections, the
/// iPad-only sections, and at the bottom the optional Music Assistant web
/// panel. What plays shows in the mini player at the bottom of the content.
struct MusicSidebar: View {
    @Binding var selection: MusicSection
    let openMusicAssistant: () -> Void
    @Environment(AudioMediaService.self) private var media
    @Environment(AppServices.self) private var services

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sidebarRowGap) {
            ForEach(MusicSection.primary) { row($0) }
            SectionHeader("On This iPad")
                .padding(.top, Theme.Spacing.m)
                .padding(.leading, Theme.Spacing.s)
            ForEach(MusicSection.onThisIPad) { row($0) }
            Spacer(minLength: Theme.Spacing.m)
            if media.musicSource == .musicAssistant, !services.settings[AudioSettings.musicAssistantURL].isEmpty {
                Button(action: openMusicAssistant) {
                    Label("Open Music Assistant", systemImage: "arrow.up.forward.app")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .padding(.leading, Theme.Spacing.s)
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private func row(_ section: MusicSection) -> some View {
        let isSelected = section == selection
        return Button {
            withAnimation(Theme.Motion.standard) { selection = section }
        } label: {
            Label(section.title, systemImage: section.systemImage)
                .font(.title3.weight(.semibold))
        }
        .buttonStyle(.sidebarRow(isSelected: isSelected))
        .foregroundStyle(isSelected ? Color.primary : Color.secondary)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
