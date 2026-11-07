import HomePadCore
import HomePadUI
import SwiftUI

/// The Play On panel with Spotify as the source. This iPad comes first: the
/// Spotify app here plays, and the AirPlay button beside it picks the speakers,
/// HomePods included. Then the Spotify Connect devices that are on, with the
/// one Spotify plays to checked. Choosing one moves the music there.
///
/// Spotify lists only the devices of the account in use. When the Spotify app
/// on this iPad is signed in to someone else, This iPad says whose it is and
/// how to make it theirs, and the person's own devices follow.
struct SpotifyDevicePicker: View {
    @Environment(AudioMediaService.self) private var media

    var body: some View {
        let spotify = media.spotify
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Text(introduction)
                .font(.tileDetail)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            thisIPadRow
            ScrollView {
                VStack(spacing: Theme.Spacing.xs) {
                    ForEach(otherDevices) { device in row(device) }
                }
            }
            .frame(maxHeight: 360)
            .scrollBounceBehavior(.basedOnSize)
            if let problem = spotify.problem {
                Text(problem.localizedDescription).font(.callout).foregroundStyle(.orange)
            }
            GlassCapsuleButton("Refresh", systemImage: "arrow.clockwise") {
                Task { await spotify.refreshDevices() }
            }
        }
        .task { await spotify.refreshDevices() }
    }

    private var introduction: String {
        guard let other = media.spotify.thisIPadIsOthers else {
            return "Spotify plays on this iPad through the Spotify app, and AirPlay picks the speakers. Or choose a Spotify Connect device."
        }
        let whose = media.spotify.keptForPlayingMusic.map { "\($0) Spotify" } ?? "your Spotify"
        return "Spotify on this iPad is signed in as \(other), so it can't play \(whose). Choose one of the devices below, which are signed in to it, or open Spotify on your phone, computer or speaker."
    }

    /// Connect devices other than the Spotify app on this iPad.
    private var otherDevices: [SpotifyDevice] {
        media.spotify.devices.filter { $0.id != media.spotify.thisIPadID }
    }

    /// The Spotify app on this iPad, with where its sound goes and the AirPlay button.
    private var thisIPadRow: some View {
        let spotify = media.spotify
        let isTarget = spotify.targetsThisIPad
        return HStack(spacing: Theme.Spacing.m) {
            Button {
                Task { await chooseThisIPad() }
            } label: {
                HStack(spacing: Theme.Spacing.m) {
                    Image(systemName: "ipad.landscape")
                        .font(.title2)
                        .foregroundStyle(spotify.thisIPad?.isActive == true ? Theme.tint(for: .mediaPlayer) : .secondary)
                        .frame(width: Theme.Size.minTapTarget)
                    VStack(alignment: .leading, spacing: 0) {
                        Text("This iPad").font(.tileTitle)
                        Text(thisIPadDetail).font(.tileDetail).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: isTarget ? "checkmark.circle.fill" : "circle")
                        .font(.title2)
                        .foregroundStyle(isTarget ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(isTarget ? .isSelected : [])
            AirPlayButton(size: Theme.Size.minTapTarget)
        }
        .frame(minHeight: Theme.Size.tapTarget)
        .padding(Theme.Spacing.s)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous).fill(.primary.opacity(isTarget ? 0.08 : 0)))
    }

    private var thisIPadDetail: String {
        if let other = media.spotify.thisIPadIsOthers { return "Signed in to Spotify as \(other)" }
        switch media.spotify.hereState {
        case .open: return media.spotifyVolume.speakerName.map { "Spotify app, playing to \($0)" } ?? "Spotify app"
        case .notOpen: return "Spotify isn't open here"
        case .unknown: return "Play once in Spotify here"
        }
    }

    /// Makes this iPad the target. When Spotify is not open here, HomePad opens it first.
    private func chooseThisIPad() async {
        let spotify = media.spotify
        if let other = spotify.thisIPadIsOthers {
            // Only the Spotify app here can change whose music it plays.
            media.spotifyNotice = .signedInAsOther(other)
        } else if spotify.hereState == .open {
            await spotify.useThisIPad()
        } else {
            media.wakeSpotifyHere { [spotify] in await spotify.useThisIPad() }
        }
    }

    private func row(_ device: SpotifyDevice) -> some View {
        let isTarget = !media.spotify.targetsThisIPad && media.spotify.targetDevice?.id == device.id
        return Button {
            Task { await media.spotify.transfer(to: device) }
        } label: {
            HStack(spacing: Theme.Spacing.m) {
                Image(systemName: device.systemImage)
                    .font(.title2)
                    .foregroundStyle(device.isActive ? Theme.tint(for: .mediaPlayer) : .secondary)
                    .frame(width: Theme.Size.minTapTarget)
                VStack(alignment: .leading, spacing: 0) {
                    Text(device.name).font(.tileTitle)
                    Text(device.isActive ? "Playing" : device.type).font(.tileDetail).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: isTarget ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(isTarget ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
            }
            .frame(minHeight: Theme.Size.tapTarget)
            .padding(Theme.Spacing.s)
            .background(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous).fill(.primary.opacity(isTarget ? 0.08 : 0)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(device.isRestricted)
        .accessibilityAddTraits(isTarget ? .isSelected : [])
    }
}
