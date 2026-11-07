import HomePadCore
import HomePadUI
import SwiftUI

/// The analog clock tile, with numerals in the theme's ink.
struct HomeClockTile: View {
    let palette: FacePalette
    @Environment(\.proximity) private var proximity

    var body: some View {
        FaceTimeline(proximity >= .mid ? .second : .minute) { date in
            ZStack {
                DialTicks(color: palette.secondary.opacity(0.7))
                DialNumerals(radiusFraction: 0.72) { numeral, radius in
                    Text("\(numeral)")
                        .font(.display(radius * 0.22, weight: .medium))
                        .foregroundStyle(palette.ink)
                }
                ClockHands(angles: ClockMath.angles(for: date), style: .standard(
                    ink: palette.ink, accent: palette.accent,
                    showsSecond: proximity >= .mid))
            }
            .aspectRatio(1, contentMode: .fit)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

/// The thermostat tile: target temperature, name and room, and big up and
/// down buttons in the corners. The room and the current temperature fade in
/// up close.
struct ThermostatTile: View {
    let accessory: HomeAccessory
    let palette: FacePalette
    let cellHeight: CGFloat

    @Environment(AppServices.self) private var services
    @Environment(\.proximity) private var proximity

    var body: some View {
        let state = accessory.state
        let isActive = (state.hvacMode ?? .off) != .off
        let ink = HomeTileInk(palette: palette, isOn: isActive)
        let isNear = proximity >= .mid
        GlassTile(isHighlighted: true, tint: HomeTileInk.fill(palette: palette, isOn: isActive)) {
            HStack(alignment: .bottom) {
                stepButton("chevron.down", delta: -1, color: ink.title)
                VStack(spacing: cellHeight * 0.02) {
                    Text(state.targetTemperature.map { "\(Int($0.rounded()))°" } ?? "--")
                        .font(.display(cellHeight * 0.38, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(ink.title)
                        .contentTransition(.numericText())
                    Text(accessory.name)
                        .font(.display(cellHeight * 0.1, weight: .semibold))
                        .foregroundStyle(ink.title)
                    Text(detail)
                        .font(.display(cellHeight * 0.085, weight: .medium))
                        .foregroundStyle(ink.subtitle)
                        .opacity(isNear ? 1 : 0)
                }
                .offset(y: isNear ? 0 : cellHeight * HomeTileView.subtitleRoom / 2)
                .frame(maxWidth: .infinity)
                stepButton("chevron.up", delta: 1, color: ink.title)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var detail: String {
        let room = accessory.room ?? "Home"
        guard let current = accessory.state.currentTemperature else { return room }
        let mode = accessory.state.hvacMode.map { $0 == .off ? "" : " · \($0.rawValue.capitalized)" } ?? ""
        return "\(room) · Now \(Int(current.rounded()))°\(mode)"
    }

    private func stepButton(_ symbol: String, delta: Double, color: Color) -> some View {
        Button {
            guard let target = accessory.state.targetTemperature else { return }
            Task { try? await services.smartHome.perform(.setTargetTemperature(target + delta), on: accessory.id) }
        } label: {
            Image(systemName: symbol)
                .font(.system(size: cellHeight * 0.13, weight: .bold))
                .foregroundStyle(color)
                .frame(width: cellHeight * 0.32, height: cellHeight * 0.32)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(delta > 0 ? "Warmer" : "Cooler")
    }
}

/// A camera tile: the camera's latest still, with its name up close. From
/// across the room it is just the picture, like HomeView's. The Smart Home
/// module's shared camera view draws it (HomeKit pictures only show in Apple's
/// own camera view; turned into an image they came out black), and polled
/// snapshots stand in when that module is absent. While the display sleeps
/// under its black cover the still is left out, so it is not fetched all night.
struct CameraTile: View {
    let camera: HomeCamera
    let image: UIImage?
    let palette: FacePalette
    @Environment(\.displayCondition) private var condition
    @Environment(\.proximity) private var proximity
    @Environment(\.isFrosted) private var isFrosted

    /// Live once someone is near, as on the Cameras face, and a still that refreshes from across the
    /// room, at night (the wall keeps its far look then) and behind the Home Screen's frost.
    private var isLive: Bool {
        proximity >= .mid && !isFrosted
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.tile, style: .continuous)
        ZStack(alignment: .bottomLeading) {
            shape.fill(palette.tile.opacity(0.4))
                .overlay {
                    if condition == .sleeping {
                        EmptyView()
                    } else if SmartHomeCameraView.renderer != nil {
                        SmartHomeCameraView(cameraID: camera.id, mode: isLive ? .live : .still)
                    } else if let image {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .saturation(palette.isNight ? 0 : 0.85)
                    } else {
                        Image(systemName: "video.fill").font(.largeTitle).foregroundStyle(palette.secondary)
                    }
                }
            if proximity >= .mid {
                GlassPill(camera.name, systemImage: "video.fill")
                    .foregroundStyle(.white)
                    .padding(Theme.Spacing.s)
                    .transition(.proximityDetail)
            }
        }
        .clipShape(shape)
        .nightModeAware()
    }
}
