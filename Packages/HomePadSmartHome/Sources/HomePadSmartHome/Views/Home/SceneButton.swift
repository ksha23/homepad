import HomePadCore
import HomePadUI
import SwiftUI

/// A scene that runs when tapped. Shows a check for a moment after it runs.
struct SceneButton: View {
    enum Style {
        /// A Home app chip sized to its name, for the Home app's favorite scenes.
        case capsule
        /// Icon above the name, filling the space it is given, like a scene tile on HomeView.
        case tile
        /// Icon beside the name, filling the space it is given.
        case row
    }

    @Environment(UnifiedSmartHomeService.self) private var service
    @Environment(\.controlCornerRadius) private var cornerRadius
    let scene: HomeScene
    var style = Style.capsule
    @State private var didRun = false
    /// How many times it ran here, for the glow each run plays.
    @State private var runs = 0
    @State private var errorMessage: String?

    var body: some View {
        Button {
            Task {
                do {
                    try await service.activateScene(scene.id)
                    withAnimation(Theme.Motion.standard) {
                        didRun = true
                        runs += 1
                    }
                    try? await Task.sleep(for: .seconds(1.5))
                    withAnimation(Theme.Motion.standard) { didRun = false }
                } catch {
                    errorMessage = error.localizedDescription
                }
            }
        } label: {
            switch style {
            case .capsule: capsule
            case .tile: tile
            case .row: row
            }
        }
        .buttonStyle(.pressable)
        .alert("Scene Did Not Run", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
        .accessibilityLabel("Run \(scene.name)")
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    }

    private var symbolName: String { didRun ? "checkmark.circle.fill" : scene.systemImage }
    private var symbolColor: Color { didRun ? .green : .orange }

    private var symbol: some View {
        Image(systemName: symbolName)
            .foregroundStyle(symbolColor)
            .contentTransition(.symbolEffect(.replace))
    }

    private func badge(diameter: CGFloat, font: Font) -> some View {
        IconBadge(symbol: symbolName, color: symbolColor, diameter: diameter, font: font)
    }

    private var capsule: some View {
        HStack(spacing: Theme.Spacing.xs) {
            symbol
            Text(scene.name).foregroundStyle(Color.primary)
        }
        .homeChip(isInteractive: true)
        .changeGlow(runs, tint: .green, in: Capsule())
    }

    /// Tiles and rows fill their cell, so every scene in a widget is the same
    /// size, and names wrap to a second line instead of being cut off.
    private var tile: some View {
        VStack(spacing: Theme.Spacing.xs) {
            badge(diameter: Theme.Size.minTapTarget, font: .title2.weight(.semibold))
            name.multilineTextAlignment(.center)
        }
        .padding(Theme.Spacing.s)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .controlSurface(shape)
        .changeGlow(runs, tint: .green, in: shape)
        .contentShape(shape)
    }

    private var row: some View {
        HStack(spacing: Theme.Spacing.s) {
            badge(diameter: IconBadge.compactDiameter, font: .title3.weight(.semibold))
            name
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Theme.Spacing.s)
        .padding(.vertical, Theme.Spacing.xs)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .controlSurface(shape)
        .changeGlow(runs, tint: .green, in: shape)
        .contentShape(shape)
    }

    private var name: some View {
        Text(scene.name)
            .font(.headline)
            .lineLimit(2)
            .minimumScaleFactor(0.8)
            .foregroundStyle(Color.primary)
    }
}
