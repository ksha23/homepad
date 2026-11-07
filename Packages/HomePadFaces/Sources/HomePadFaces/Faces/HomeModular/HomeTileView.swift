import HomePadCore
import os
import HomePadUI
import SwiftUI

/// Draws one Home face tile and handles its tap.
///
/// From across the room a tile shows its symbol, a little larger, and its
/// name, and its fill shows what is on. Up close the status ("On, 70%",
/// "Scene") fades in under them as they make room. A lock shows its state at
/// both distances: "Front Door Locked" is a fact worth reading from afar.
struct HomeTileView: View {
    let tile: HomeTile
    let palette: FacePalette
    let snapshots: CameraSnapshots
    let cellHeight: CGFloat

    @Environment(AppServices.self) private var services
    @Environment(\.proximity) private var proximity
    @Environment(\.facesShowPersonal) private var isRecognized
    @State private var notice: String?
    private let log = Log.make("Faces.Home")

    var body: some View {
        switch tile {
        case .clock:
            GlassTile(isHighlighted: true, tint: HomeTileInk.fill(palette: palette, isOn: false)) { HomeClockTile(palette: palette) }
        case .accessory(let accessory) where accessory.kind == .thermostat:
            ThermostatTile(accessory: accessory, palette: palette, cellHeight: cellHeight)
        case .accessory(let accessory):
            let isOn = isOn(accessory)
            button(isOn: isOn, fill: accessory.tileFill(isOn: isOn)) { tap(accessory) } label: { ink in
                label(symbol: symbol(for: accessory), title: accessory.name,
                      subtitle: notice ?? accessory.statusText, isOn: ink,
                      showsSubtitleFar: accessory.kind == .lock || notice != nil)
            }
        case .camera(let camera):
            CameraTile(camera: camera, image: snapshots.images[camera.id], palette: palette)
                .onTapGesture { services.events.post(.openApp(id: "cameras")) }
        case .intercom:
            button(isOn: false) { services.events.post(.openApp(id: "intercom")) } label: { ink in
                label(symbol: "waveform", title: "Intercom", subtitle: "Everywhere", isOn: ink)
            }
        case .scene(let scene):
            button(isOn: false) { activate(scene) } label: { ink in
                label(symbol: scene.systemImage, title: scene.name, subtitle: notice ?? "Scene", isOn: ink,
                      showsSubtitleFar: notice != nil)
            }
        case .home:
            button(isOn: false) { services.events.post(.openApp(id: "home")) } label: { ink in
                label(symbol: "house.fill", title: "Home", subtitle: "All Accessories", isOn: ink)
            }
        }
    }

    // MARK: Tile parts

    /// A tappable tile. `fill` is how much of it shows the "on" look, all of it
    /// or none by default. `label` draws the content in the "on" or "off" ink.
    private func button<Label: View>(isOn: Bool, fill: Double? = nil, action: @escaping () -> Void,
                                     @ViewBuilder label: @escaping (_ isOn: Bool) -> Label) -> some View {
        Button(action: action) {
            HomeLevelTile(palette: palette, fill: fill ?? (isOn ? 1 : 0), content: label)
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.impact(weight: .light), trigger: isOn)
    }

    /// - Parameter showsSubtitleFar: Keeps the subtitle from across the room
    ///   too: a lock's state, or a notice such as "No Response".
    private func label(symbol: String, title: String, subtitle: String, isOn: Bool,
                       showsSubtitleFar: Bool = false) -> some View {
        let ink = HomeTileInk(palette: palette, isOn: isOn)
        let showsSubtitle = proximity >= .mid || showsSubtitleFar
        return VStack(spacing: cellHeight * 0.04) {
            Image(systemName: symbol)
                .font(.system(size: cellHeight * 0.24, weight: .medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(ink.icon)
                .frame(height: cellHeight * 0.32)
                .contentTransition(.symbolEffect(.replace))
                .scaleEffect(showsSubtitle ? 1 : 1.15)
            Text(title)
                .font(.display(cellHeight * 0.1, weight: .semibold))
                .foregroundStyle(ink.title)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(subtitle)
                .font(.display(cellHeight * 0.085, weight: .medium))
                .foregroundStyle(ink.subtitle)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .opacity(showsSubtitle ? 1 : 0)
        }
        // Without the subtitle the symbol and the name sit centered.
        .offset(y: showsSubtitle ? 0 : cellHeight * Self.subtitleRoom / 2)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// The subtitle's line and the gap above it, as a share of the cell height.
    static let subtitleRoom: CGFloat = 0.14

    // MARK: Accessory state

    private func isOn(_ accessory: HomeAccessory) -> Bool {
        switch accessory.kind {
        case .lock: accessory.state.lockState == .unlocked
        case .cover, .garageDoor: (accessory.state.position ?? 0) > 0.01
        default: accessory.state.isOn ?? false
        }
    }

    private func symbol(for accessory: HomeAccessory) -> String {
        switch accessory.kind {
        case .lock: accessory.state.lockState == .unlocked ? "lock.open.fill" : "lock.fill"
        case .light: isOn(accessory) ? "lightbulb.max.fill" : "lightbulb.fill"
        case .cover: isOn(accessory) ? "blinds.horizontal.open" : "blinds.horizontal.closed"
        default: accessory.kind.systemImage
        }
    }

    // MARK: Actions

    private func tap(_ accessory: HomeAccessory) {
        let command: AccessoryCommand
        switch accessory.kind {
        case .lock:
            if accessory.state.lockState == .unlocked {
                command = .lock
            } else if isRecognized {
                command = .unlock
            } else {
                flash("Recognition Required")
                return
            }
        case .cover, .garageDoor:
            command = isOn(accessory) ? .close : .open
        case .light, .switchOutlet, .fan, .airPurifier:
            command = .toggle
        default:
            services.events.post(.openApp(id: "home"))
            return
        }
        Task {
            do {
                try await services.smartHome.perform(command, on: accessory.id)
            } catch {
                log.error("Home tile command failed: \(error.localizedDescription, privacy: .public)")
                flash("No Response")
            }
        }
    }

    private func activate(_ scene: HomeScene) {
        Task {
            do {
                try await services.smartHome.activateScene(scene.id)
                flash("Done")
            } catch {
                flash("No Response")
            }
        }
    }

    private func flash(_ text: String) {
        withAnimation { notice = text }
        Task {
            try? await Task.sleep(for: .seconds(2))
            withAnimation { notice = nil }
        }
    }
}

/// Text and icon colors for a tile in its on or off state. Tiles that are on
/// fill with the accent (the background's tile color unless one is chosen).
/// Tiles that are off are neutral gray with gray symbols and text, like
/// HomeView's, so on and off differ in color and not only in shade. A chosen
/// text color draws their text instead.
struct HomeTileInk {
    /// The tile fill: the accent when on, neutral gray when off, light on a
    /// light background and dark on a dark one.
    static func fill(palette: FacePalette, isOn: Bool) -> Color {
        if isOn { return palette.highlight }
        if palette.isNight { return palette.tile }
        return palette.isLight ? Color(white: 0.92) : Color(white: 0.2)
    }

    let icon: Color
    let title: Color
    let subtitle: Color

    init(palette: FacePalette, isOn: Bool) {
        if palette.isNight {
            icon = palette.ink
            title = palette.ink
            subtitle = palette.secondary
        } else if isOn {
            icon = palette.onHighlight
            title = palette.onHighlight
            subtitle = palette.onHighlight.opacity(0.65)
        } else if palette.hasChosenText {
            icon = palette.ink.opacity(0.85)
            title = palette.ink
            subtitle = palette.secondary
        } else {
            // Grays at least 3 to 1 against the gray fill.
            icon = palette.isLight ? Color(white: 0.42) : Color(white: 0.72)
            title = palette.isLight ? Color(white: 0.26) : Color(white: 0.92)
            subtitle = palette.isLight ? Color(white: 0.46) : Color(white: 0.64)
        }
    }
}
