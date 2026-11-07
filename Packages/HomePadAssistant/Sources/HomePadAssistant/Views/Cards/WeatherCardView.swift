import HomePadCore
import HomePadUI
import SwiftUI

/// Current conditions with big numerals and the next few hours.
struct WeatherCardView: View {
    let card: AssistantCard

    var body: some View {
        let payload = card.payload
        GlassTile {
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                HStack(alignment: .center, spacing: Theme.Spacing.l) {
                    Image(systemName: payload["symbol"]?.stringValue ?? "cloud.sun.fill")
                        .symbolRenderingMode(.multicolor)
                        .font(.system(size: 64))
                    VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                        Text(degrees(payload["temperature"]?.doubleValue)).font(.display(72))
                        Text(card.subtitle ?? "").font(.title3)
                    }
                    Spacer(minLength: 0)
                    VStack(alignment: .trailing, spacing: Theme.Spacing.xs) {
                        Text(card.title).font(.title3.weight(.semibold))
                        if let high = payload["high"]?.doubleValue, let low = payload["low"]?.doubleValue {
                            Text("H \(degrees(high))  L \(degrees(low))").font(.title3).foregroundStyle(.secondary)
                        }
                    }
                }
                let hours = payload["hourly"]?.arrayValue ?? []
                if !hours.isEmpty {
                    HStack {
                        ForEach(Array(hours.enumerated()), id: \.offset) { _, hour in
                            VStack(spacing: Theme.Spacing.xs) {
                                Text(Date(timeIntervalSince1970: hour["time"]?.doubleValue ?? 0).formatted(.dateTime.hour()))
                                    .font(.callout).foregroundStyle(.secondary)
                                Image(systemName: hour["symbol"]?.stringValue ?? "cloud").symbolRenderingMode(.multicolor).font(.title2)
                                Text(degrees(hour["temperature"]?.doubleValue)).font(.title3.weight(.semibold))
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                }
            }
        }
    }

    private func degrees(_ value: Double?) -> String {
        value.map { "\(Int($0.rounded()))°" } ?? "--"
    }
}
