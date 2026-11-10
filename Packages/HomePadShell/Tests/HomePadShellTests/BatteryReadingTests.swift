import Testing
@testable import HomePadShell

/// What the battery indicator in the top right corner shows.
@Suite struct BatteryReadingTests {
    @Test func percentAndGlyphFollowTheCharge() {
        let reading = BatteryReading(level: 0.82, power: .unplugged)
        #expect(reading.percentText == "82%")
        #expect(reading.symbolName == "battery.75percent")
        #expect(!reading.isLow)
        #expect(BatteryReading(level: 1, power: .unplugged).symbolName == "battery.100percent")
        #expect(BatteryReading(level: 0.05, power: .unplugged).symbolName == "battery.0percent")
    }

    @Test func lowOnlyWhenNotCharging() {
        #expect(BatteryReading(level: 0.2, power: .unplugged).isLow)
        #expect(!BatteryReading(level: 0.2, power: .charging).isLow)
        #expect(BatteryReading(level: 0.2, power: .charging).symbolName == "battery.100percent.bolt")
        #expect(BatteryReading(level: 0.2, power: .charging).accessibilityLabel == "Battery 20 percent, charging")
    }
}
