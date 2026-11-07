import HomePadCore
import HomePadUI
import SwiftUI

/// Hours, minutes and seconds wheels with an optional label and a Start button,
/// like the Clock app's timer picker.
struct NewTimerComposer: View {
    var onStart: (() -> Void)?
    /// Taller wheels and larger text, for the Timers app's own screen.
    var isLarge = false
    @Environment(AppServices.self) private var services
    @State private var hours = 0
    @State private var minutes = 5
    @State private var seconds = 0
    @State private var label = ""

    private var total: TimeInterval { TimeInterval(hours * 3600 + minutes * 60 + seconds) }

    var body: some View {
        VStack(spacing: Theme.Spacing.l) {
            HStack(spacing: 0) {
                wheel($hours, range: 0..<24, unit: "hours")
                wheel($minutes, range: 0..<60, unit: "min")
                wheel($seconds, range: 0..<60, unit: "sec")
            }
            .frame(height: isLarge ? 300 : 216)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))

            TextField("Label", text: $label)
                .font(isLarge ? .title2 : .title3)
                .padding(Theme.Spacing.m)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
                .submitLabel(.go)
                .onSubmit(start)

            GlassCapsuleButton("Start", systemImage: "play.fill", size: isLarge ? .extraLarge : .large,
                               isProminent: true, tint: .orange, action: start)
                .disabled(total == 0)
        }
    }

    private func wheel(_ value: Binding<Int>, range: Range<Int>, unit: String) -> some View {
        HStack(spacing: Theme.Spacing.xs) {
            Picker(unit, selection: value) {
                ForEach(range, id: \.self) { Text("\($0)").font(isLarge ? .title : .title2).tag($0) }
            }
            .pickerStyle(.wheel)
            .frame(maxWidth: isLarge ? 140 : 110)
            .clipped()
            Text(unit).font(isLarge ? .title3.weight(.semibold) : .headline).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func start() {
        guard total > 0 else { return }
        services.timers.start(duration: total, label: label)
        label = ""
        onStart?()
    }
}
