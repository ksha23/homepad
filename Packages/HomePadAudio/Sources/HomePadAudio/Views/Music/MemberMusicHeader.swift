import HomePadCore
import HomePadUI
import SwiftUI

/// At the top of Listen Now and the Library while Music shows a recognized
/// member's own Apple Music: whose it is, that what plays here counts toward
/// this iPad's account, and why it could not be read when it could not.
struct MemberMusicHeader: View {
    let library: MemberMusicLibrary
    /// "Kyle's Library" or "Kyle's Apple Music".
    let title: String
    @Environment(AudioMediaService.self) private var media
    @Environment(AppServices.self) private var services

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            HStack(spacing: Theme.Spacing.s) {
                AvatarView(member: services.household.members.first { $0.id == library.memberID }, size: 40)
                Text(title).font(.title2.weight(.bold))
            }
            Text("From \(library.link.deviceName). Songs play through this iPad's Apple Music, so they count toward its account.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if library.problem != nil {
                Label(Self.problemText(library), systemImage: "exclamationmark.triangle.fill")
                    .font(.subheadline)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let notice = media.memberMusic.notice {
                Label(notice, systemImage: "exclamationmark.circle")
                    .font(.subheadline)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    /// Why the library could not be read just now, and what helps.
    static func problemText(_ library: MemberMusicLibrary) -> String {
        switch library.problem {
        case .needsNewToken?:
            "\(library.memberName)'s Apple Music needs a new sign-in token. It arrives the next time HomePad is open on \(library.link.deviceName)."
        case .offline?:
            "Apple Music can't be reached right now. This is what HomePad saved last time."
        case .unavailable?, nil:
            "Apple Music didn't answer for \(library.memberName) just now. This is what HomePad saved last time."
        }
    }
}
