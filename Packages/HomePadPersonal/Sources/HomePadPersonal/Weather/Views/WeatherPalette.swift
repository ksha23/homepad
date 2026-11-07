import HomePadUI
import SwiftUI

/// Sky colors for each condition, day and night. Weather backgrounds are
/// content (like a photo), so they own their colors instead of using Theme tints.
enum WeatherPalette {
    /// An sRGB color as channels from 0 to 1, so the sky's colors can be measured.
    typealias Channels = (red: Double, green: Double, blue: Double)

    /// Top and bottom of the sky gradient.
    static func sky(for condition: WeatherConditionKind, isDaylight: Bool) -> [Color] {
        let ends = skyChannels(for: condition, isDaylight: isDaylight)
        return [color(ends.top), color(ends.bottom)]
    }

    /// Top and bottom of the sky gradient, as channels.
    static func skyChannels(for condition: WeatherConditionKind, isDaylight: Bool) -> (top: Channels, bottom: Channels) {
        switch (condition, isDaylight) {
        case (.clear, true), (.mostlyClear, true):
            ((0.11, 0.40, 0.84), (0.42, 0.68, 0.96))
        case (.partlyCloudy, true), (.windy, true):
            ((0.18, 0.42, 0.76), (0.46, 0.66, 0.88))
        case (.mostlyCloudy, true), (.cloudy, true):
            ((0.36, 0.44, 0.55), (0.58, 0.64, 0.73))
        case (.fog, true), (.haze, true):
            ((0.50, 0.53, 0.58), (0.72, 0.72, 0.72))
        case (.snow, true), (.heavySnow, true), (.flurries, true), (.sleet, true):
            ((0.52, 0.60, 0.72), (0.80, 0.84, 0.91))
        case (.thunderstorm, _), (.hail, _):
            ((0.10, 0.12, 0.20), (0.27, 0.29, 0.39))
        case (_, true):
            ((0.22, 0.28, 0.38), (0.41, 0.48, 0.57))
        case (.clear, false), (.mostlyClear, false), (.partlyCloudy, false):
            ((0.02, 0.04, 0.14), (0.10, 0.17, 0.36))
        case (.snow, false), (.heavySnow, false), (.flurries, false):
            ((0.10, 0.13, 0.22), (0.27, 0.32, 0.43))
        default:
            ((0.05, 0.06, 0.11), (0.17, 0.19, 0.25))
        }
    }

    /// Cloud tint: white by day, slate at night.
    static func cloud(isDaylight: Bool, condition: WeatherConditionKind) -> Color {
        color(cloudChannels(isDaylight: isDaylight, condition: condition))
    }

    /// Cloud tint, as channels.
    static func cloudChannels(isDaylight: Bool, condition: WeatherConditionKind) -> Channels {
        if !isDaylight { return (0.55, 0.60, 0.70) }
        return condition.precipitation == .none ? (1, 1, 1) : (0.80, 0.83, 0.88)
    }

    /// WCAG's minimum contrast for text below its large size. The widget's
    /// hours, place and high and low are subheadlines and headlines.
    static let textContrast = 4.5

    /// How dark a shade the weather widget lays between its sky and its white
    /// text, at `stops` evenly spaced heights from the top to the bottom. At
    /// each height it is just enough for white to reach `textContrast` on the
    /// brightest color the sky draws there: the gradient under its clouds at
    /// their strongest (`WeatherSkyBackground.cloudCeiling`). Clouds on a tile
    /// are as big as the tile, so they count at every height. A dark sky gets
    /// no shade at all.
    static func textShade(for condition: WeatherConditionKind, isDaylight: Bool, stops: Int = 5) -> [Double] {
        let ends = skyChannels(for: condition, isDaylight: isDaylight)
        let cloud = cloudChannels(isDaylight: isDaylight, condition: condition)
        let cover = condition.cloudiness > 0 ? WeatherSkyBackground.cloudCeiling : 0
        return (0..<stops).map { index in
            let height = Double(index) / Double(max(stops - 1, 1))
            let sky = mix(ends.top, ends.bottom, by: height)
            let brightest = mix(sky, cloud, by: cover)
            return BackdropTone.whiteTextShade(red: brightest.red, green: brightest.green, blue: brightest.blue,
                                               contrast: textContrast)
        }
    }

    /// `from` moved `fraction` of the way to `to`, channel by channel.
    static func mix(_ from: Channels, _ to: Channels, by fraction: Double) -> Channels {
        (from.red + (to.red - from.red) * fraction,
         from.green + (to.green - from.green) * fraction,
         from.blue + (to.blue - from.blue) * fraction)
    }

    private static func color(_ channels: Channels) -> Color {
        Color(red: channels.red, green: channels.green, blue: channels.blue)
    }
}
