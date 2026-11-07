import HomePadCore
import HomePadUI
import SwiftUI

/// The accessories an answer touched, as small home tiles showing their new state.
struct AccessoryCardView: View {
    let card: AssistantCard

    var body: some View {
        let items = card.payload["accessories"]?.arrayValue ?? []
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), spacing: Theme.Spacing.m)], spacing: Theme.Spacing.m) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                tile(item)
            }
        }
    }

    private func tile(_ item: JSONValue) -> some View {
        let kind = item["kind"]?.stringValue.flatMap(AccessoryKind.init(rawValue:)) ?? .other
        let isOn = item["isOn"]?.boolValue ?? false
        return GlassTile(isHighlighted: isOn, tint: Theme.tint(for: kind)) {
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                Image(systemName: kind.systemImage)
                    .font(.title)
                    .foregroundStyle(isOn ? Theme.tint(for: kind) : .secondary)
                    .frame(width: 48, height: 48)
                    .background(isOn ? AnyShapeStyle(.white) : AnyShapeStyle(.primary.opacity(0.12)), in: Circle())
                Spacer(minLength: 0)
                Text(item["name"]?.stringValue ?? "").font(.headline).lineLimit(2)
                Text(item["status"]?.stringValue ?? "").font(.tileDetail).opacity(0.75)
            }
            // Black on the lit tint, the appearance's primary color on glass.
            .foregroundStyle(isOn ? Color.black : Color.primary)
        }
        .frame(height: 150)
    }
}
