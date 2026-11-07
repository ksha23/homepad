import Foundation
import HomePadUI

/// The kind of sky the Weather face paints, from a weather symbol or text.
enum SkyCondition: String, CaseIterable, Sendable {
    case clear, partlyCloudy, cloudy, rain, snow, thunder, fog

    /// Maps an SF Symbol name (WeatherKit style) or condition text to a sky.
    static func from(symbolName: String, conditionText: String = "") -> SkyCondition {
        let text = (symbolName + " " + conditionText).lowercased()
        if text.contains("bolt") || text.contains("thunder") { return .thunder }
        if text.contains("snow") || text.contains("sleet") || text.contains("hail") || text.contains("flurr") { return .snow }
        if text.contains("rain") || text.contains("drizzle") || text.contains("shower") { return .rain }
        if text.contains("fog") || text.contains("haze") || text.contains("smoke") || text.contains("mist") { return .fog }
        if text.contains("sun") && text.contains("cloud") || text.contains("partly") || text.contains("moon") && text.contains("cloud") {
            return .partlyCloudy
        }
        if text.contains("cloud") || text.contains("overcast") { return .cloudy }
        return .clear
    }

    /// Soft cloud puffs to draw.
    var cloudCount: Int {
        switch self {
        case .clear: 1
        case .partlyCloudy: 4
        case .fog: 3
        case .snow: 5
        case .cloudy, .rain, .thunder: 7
        }
    }

    var isDark: Bool { self == .rain || self == .thunder }
}

/// Coarse time of day for sky colors.
enum SkyTime: String, CaseIterable, Sendable {
    case dawn, day, dusk, night

    /// How long dawn and dusk colors last on each side of sunrise and sunset.
    static let twilight: TimeInterval = 40 * 60

    /// A rough guess from the hour alone, for when the weather has no sun times.
    static func at(hour: Double) -> SkyTime {
        switch hour {
        case 5..<7.5: .dawn
        case 7.5..<17: .day
        case 17..<19.5: .dusk
        default: .night
        }
    }

    /// The sky for a moment, from the best information the weather has:
    /// sunrise and sunset first, then whether it is daylight, then the moon
    /// in the condition symbol, and only then the hour.
    static func at(_ date: Date, sunrise: Date?, sunset: Date?, isDaylight: Bool?, symbolName: String = "",
                   calendar: Calendar = .current) -> SkyTime {
        if let sunrise, let sunset {
            let rise = sameTimeOfDay(sunrise, on: date, calendar: calendar)
            let set = sameTimeOfDay(sunset, on: date, calendar: calendar)
            if abs(date.timeIntervalSince(rise)) <= twilight { return .dawn }
            if abs(date.timeIntervalSince(set)) <= twilight { return .dusk }
            return date > rise && date < set ? .day : .night
        }
        let hour = Double(calendar.component(.hour, from: date)) + Double(calendar.component(.minute, from: date)) / 60
        let byHour = at(hour: hour)
        guard let isUp = isDaylight ?? (symbolName.contains("moon") ? false : nil) else { return byHour }
        if !isUp { return .night }
        return byHour == .night ? .day : byHour
    }

    /// `time`'s hour and minute on `date`'s day, so yesterday's sunrise still
    /// works after midnight until the forecast refreshes.
    private static func sameTimeOfDay(_ time: Date, on date: Date, calendar: Calendar) -> Date {
        let parts = calendar.dateComponents([.hour, .minute, .second], from: time)
        return calendar.date(bySettingHour: parts.hour ?? 0, minute: parts.minute ?? 0, second: parts.second ?? 0, of: date) ?? time
    }
}

/// A sky's colors: its gradient and clouds, and the shade its white text needs.
enum SkyPalette {
    /// How bright a sky is as a backdrop, from its gradient, for glass laid over it.
    static func tone(_ condition: SkyCondition, _ time: SkyTime) -> BackdropTone {
        let colors = colors(condition, time)
        return .gradient([FaceRGB(hex: colors.top).tone, FaceRGB(hex: colors.bottom).tone])
    }

    static func colors(_ condition: SkyCondition, _ time: SkyTime) -> (top: String, bottom: String) {
        switch (time, condition) {
        case (.night, .clear), (.night, .partlyCloudy): ("#0A1330", "#25365F")
        case (.night, .snow), (.night, .fog): ("#1E2636", "#46506A")
        case (.night, _): ("#121823", "#2F3746")
        case (.dawn, .clear), (.dawn, .partlyCloudy): ("#3D4E8C", "#F2A27A")
        case (.dusk, .clear), (.dusk, .partlyCloudy): ("#2B2E6B", "#E77F6B")
        case (.dawn, _), (.dusk, _): ("#4A4F66", "#9C8F94")
        case (.day, .clear): ("#2A6AD4", "#8EC8F4")
        case (.day, .partlyCloudy): ("#3470C2", "#93BEE8")
        case (.day, .cloudy): ("#6B7F96", "#AEBBCA")
        case (.day, .rain): ("#4A596D", "#8592A3")
        case (.day, .snow): ("#8EA2BB", "#D7E0EA")
        case (.day, .thunder): ("#2D3345", "#5A617B")
        case (.day, .fog): ("#9AA5B1", "#CDD4DB")
        }
    }

    /// The clouds' color, and how opaque the strongest puff is.
    static func clouds(_ condition: SkyCondition, _ time: SkyTime) -> (tone: FaceRGB, opacity: Double) {
        let isDim = condition.isDark || time == .night
        let tone = isDim ? FaceRGB(hex: "#5B6475") : .white
        let opacity = condition == .fog ? 0.5 : (isDim ? 0.6 : 0.85)
        return (tone, opacity)
    }

    /// The brightest color the sky draws at a height, from 0 at the top to 1
    /// at the bottom: the gradient there, under the strongest cloud puff that
    /// drifts across that height. The sun and moon are left out, since they
    /// are a small spot and not a band the text sits on.
    /// - Parameter aspectRatio: The sky's width over its height. Puffs are sized by the width.
    static func brightest(_ condition: SkyCondition, _ time: SkyTime, at height: Double, aspectRatio: Double) -> FaceRGB {
        let ends = colors(condition, time)
        let gradient = FaceRGB(hex: ends.top).mixed(with: FaceRGB(hex: ends.bottom), by: height)
        var strongest = 0.0
        for index in 0..<condition.cloudCount {
            let puff = CloudLayout.puff(index, condition: condition)
            let distance = abs(Double(puff.y) - height)
            let reach = Double(puff.reach) * aspectRatio
            if distance <= reach {
                strongest = max(strongest, puff.opacity)
            }
        }
        let cloud = clouds(condition, time)
        return gradient.mixed(with: cloud.tone, by: cloud.opacity * strongest)
    }

    /// How dark a shade the Weather face lays between its sky and its white
    /// text, at `stops` evenly spaced heights from the top to the bottom. At
    /// each height it is just enough for white to reach `contrast` on the
    /// brightest color the sky draws there (`brightest`), and none where white
    /// already reads, so a dark sky has none at all.
    static func textShade(_ condition: SkyCondition, _ time: SkyTime, aspectRatio: Double,
                          contrast: Double = FaceColorChoice.minimumContrast, stops: Int = 21) -> [Double] {
        (0..<stops).map { index in
            let height = Double(index) / Double(max(stops - 1, 1))
            let color = brightest(condition, time, at: height, aspectRatio: aspectRatio)
            return BackdropTone.whiteTextShade(red: color.red, green: color.green, blue: color.blue, contrast: contrast)
        }
    }
}

/// Fixed positions for cloud puffs, so each condition always looks composed.
/// Positions are shares of the sky's width and height, sizes shares of its width.
enum CloudLayout {
    struct Puff {
        var x: CGFloat, y: CGFloat, width: CGFloat, aspect: CGFloat, opacity: Double, drift: CGFloat

        /// How far up and down from its center the puff reaches with its
        /// blur, as a share of the sky's width.
        var reach: CGFloat { width * aspect / 2 + CloudLayout.blur }
    }

    /// The puffs' blur radius, as a share of the sky's width.
    static let blur: CGFloat = 0.03

    static func puff(_ index: Int, condition: SkyCondition) -> Puff {
        let puffs: [Puff] = [
            Puff(x: 0.25, y: 0.12, width: 0.55, aspect: 0.28, opacity: 1, drift: 0.04),
            Puff(x: 0.7, y: 0.2, width: 0.5, aspect: 0.3, opacity: 0.9, drift: 0.06),
            Puff(x: 0.45, y: 0.3, width: 0.6, aspect: 0.22, opacity: 0.7, drift: 0.03),
            Puff(x: 0.9, y: 0.08, width: 0.45, aspect: 0.3, opacity: 0.8, drift: 0.05),
            Puff(x: 0.1, y: 0.35, width: 0.4, aspect: 0.3, opacity: 0.6, drift: 0.07),
            Puff(x: 0.55, y: 0.05, width: 0.7, aspect: 0.25, opacity: 0.9, drift: 0.02),
            Puff(x: 0.8, y: 0.4, width: 0.5, aspect: 0.25, opacity: 0.5, drift: 0.05),
        ]
        var puff = puffs[index % puffs.count]
        if condition == .fog {
            puff.y += 0.45
            puff.aspect *= 0.6
            puff.width *= 1.6
        }
        if condition == .clear { puff.opacity *= 0.35 }
        return puff
    }
}
