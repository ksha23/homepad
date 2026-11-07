import Testing
@testable import HomePadPersonal
import HomePadUI

/// The shade the weather widget lays between its sky and its white text:
/// just enough on a bright sky, none on a dark one.
@Suite struct WeatherTextShadeTests {
    private let stops = 5

    /// The brightest color the sky draws at a stop, as the palette measures it.
    private func brightest(_ condition: WeatherConditionKind, isDaylight: Bool, at index: Int) -> WeatherPalette.Channels {
        let ends = WeatherPalette.skyChannels(for: condition, isDaylight: isDaylight)
        let sky = WeatherPalette.mix(ends.top, ends.bottom, by: Double(index) / Double(stops - 1))
        let cover = condition.cloudiness > 0 ? WeatherSkyBackground.cloudCeiling : 0
        return WeatherPalette.mix(sky, WeatherPalette.cloudChannels(isDaylight: isDaylight, condition: condition), by: cover)
    }

    private func whiteContrast(_ color: WeatherPalette.Channels, shade: Double) -> Double {
        BackdropTone(red: color.red, green: color.green, blue: color.blue, opacity: 1 - shade).whiteTextContrast
    }

    @Test func whiteReadsOnEverySkyWithItsShade() {
        for condition in WeatherConditionKind.allCases {
            for isDaylight in [true, false] {
                let shade = WeatherPalette.textShade(for: condition, isDaylight: isDaylight, stops: stops)
                for (index, opacity) in shade.enumerated() {
                    let color = brightest(condition, isDaylight: isDaylight, at: index)
                    #expect(whiteContrast(color, shade: opacity) >= WeatherPalette.textContrast - 0.001,
                            "\(condition) daylight \(isDaylight) at stop \(index)")
                }
            }
        }
    }

    @Test func aSnowyDayGetsAShadeAndADarkSkyNone() {
        // White fails on the bottom of a snowy day's sky, where the hours sit.
        let snow = WeatherPalette.skyChannels(for: .snow, isDaylight: true)
        #expect(whiteContrast(snow.bottom, shade: 0) < WeatherPalette.textContrast)
        #expect(WeatherPalette.textShade(for: .snow, isDaylight: true).allSatisfy { $0 > 0 })
        // Clear nights are dark enough as they are.
        #expect(WeatherPalette.textShade(for: .clear, isDaylight: false).allSatisfy { $0 == 0 })
        #expect(WeatherPalette.textShade(for: .mostlyClear, isDaylight: false).allSatisfy { $0 == 0 })
    }
}
