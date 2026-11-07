import HomePadCore
import HomePadUI
import SwiftUI

// Stand-in widgets and tiles for `DemoContent`. They use HomePadUI pieces so
// screenshots show the intended look.

struct DemoWeatherWidget: View {
    let size: WidgetSize
    @Environment(AppServices.self) private var services

    var body: some View {
        let weather = services.weather.current
        GlassTile {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text(weather?.locationName ?? "Weather").font(.tileTitle)
                Text("\(Int(weather?.temperature.rounded() ?? 0))°").font(.display(size == .small ? 48 : 64))
                Spacer(minLength: 0)
                Label(weather?.conditionText ?? "", systemImage: weather?.symbolName ?? "cloud")
                    .symbolRenderingMode(.multicolor)
                    .font(.subheadline.weight(.medium))
            }
        }
        .background(LinearGradient(colors: [.blue, .cyan.opacity(0.6)], startPoint: .top, endPoint: .bottom))
    }
}

struct DemoCalendarWidget: View {
    var body: some View {
        GlassTile {
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                Text(Date(), format: .dateTime.weekday(.wide)).font(.headline).foregroundStyle(.red).textCase(.uppercase)
                Text(Date(), format: .dateTime.day()).font(.display(44))
                event("Standup", "9:00 to 9:30 AM", .green)
                event("Pick up groceries", "5:00 to 6:00 PM", .yellow)
                Spacer(minLength: 0)
            }
        }
    }

    private func event(_ title: String, _ time: String, _ color: Color) -> some View {
        HStack(spacing: Theme.Spacing.s) {
            Capsule().fill(color).frame(width: 4)
            VStack(alignment: .leading) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(time).font(.caption).foregroundStyle(.secondary)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

struct DemoMusicWidget: View {
    var body: some View {
        GlassTile {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Image(systemName: "music.note")
                    .font(.title)
                    .frame(width: 56, height: 56)
                    .background(Color.pink.gradient, in: RoundedRectangle(cornerRadius: Theme.Radius.tileControl, style: .continuous))
                Spacer(minLength: 0)
                Text("Today's Hits").font(.tileTitle)
                Text("Apple Music").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

struct DemoLockTile: View {
    let name: String
    @State private var isLocked = true

    var body: some View {
        ToggleTile(name, subtitle: isLocked ? "Locked" : "Unlocked", systemImage: isLocked ? "lock.fill" : "lock.open.fill",
                   isOn: $isLocked, style: .wide, onTint: .teal)
    }
}
