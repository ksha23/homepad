import HomePadCore
import HomePadUI
import SwiftUI

/// Seconds, AM or PM, and the weather in one line, for faces seen up close.
struct NearDetailRow: View {
    let date: Date
    let period: String?
    let palette: FacePalette
    @Environment(AppServices.self) private var services

    var body: some View {
        HStack(spacing: Theme.Spacing.l) {
            if let period {
                Text(period).foregroundStyle(palette.accent)
            }
            Text(date, format: .dateTime.second(.twoDigits))
                .monospacedDigit()
                .foregroundStyle(palette.secondary)
            if let weather = services.weather.current {
                Label {
                    Text("\(Int(weather.temperature.rounded()))° \(weather.conditionText)")
                } icon: {
                    Image(systemName: weather.symbolName).symbolRenderingMode(palette.isNight ? .monochrome : .multicolor)
                }
                .foregroundStyle(palette.ink)
            }
        }
    }
}
