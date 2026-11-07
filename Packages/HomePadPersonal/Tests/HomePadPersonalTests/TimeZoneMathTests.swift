import Foundation
import Testing
@testable import HomePadPersonal

@Suite struct TimeZoneMathTests {
    let chicago = TimeZone(identifier: "America/Chicago")!
    let london = TimeZone(identifier: "Europe/London")!
    let tokyo = TimeZone(identifier: "Asia/Tokyo")!
    let kolkata = TimeZone(identifier: "Asia/Kolkata")!
    let kathmandu = TimeZone(identifier: "Asia/Kathmandu")!
    let honolulu = TimeZone(identifier: "Pacific/Honolulu")!

    /// 2026-10-20 08:30 UTC, which is 3:30 AM in Chicago.
    let tuesdayMorning = Date(timeIntervalSince1970: 1_792_485_000)

    func date(_ iso: String) -> Date {
        try! Date(iso, strategy: .iso8601)
    }

    @Test func offsetsFollowDaylightSavingInBothZones() {
        // Both on summer time: BST is UTC+1, CDT is UTC-5.
        #expect(TimeZoneMath.offset(of: london, from: chicago, at: date("2026-10-20T12:00:00Z")) == 6 * 3600)
        // Europe falls back on October 25, the US on November 1.
        #expect(TimeZoneMath.offset(of: london, from: chicago, at: date("2026-10-28T12:00:00Z")) == 5 * 3600)
        #expect(TimeZoneMath.offset(of: london, from: chicago, at: date("2026-11-03T12:00:00Z")) == 6 * 3600)
        #expect(TimeZoneMath.offset(of: chicago, from: tokyo, at: tuesdayMorning) == -14 * 3600)
    }

    @Test func fractionalHourZones() {
        let utc = TimeZone(identifier: "UTC")!
        #expect(TimeZoneMath.offsetText(seconds: TimeZoneMath.offset(of: kolkata, from: utc, at: tuesdayMorning)) == "+5 hrs 30 min")
        #expect(TimeZoneMath.offsetText(seconds: TimeZoneMath.offset(of: kathmandu, from: utc, at: tuesdayMorning)) == "+5 hrs 45 min")
    }

    @Test func offsetText() {
        #expect(TimeZoneMath.offsetText(seconds: 0) == "Same time")
        #expect(TimeZoneMath.offsetText(seconds: 3600) == "+1 hr")
        #expect(TimeZoneMath.offsetText(seconds: -3 * 3600) == "\u{2212}3 hrs")
        #expect(TimeZoneMath.offsetText(seconds: -1800) == "\u{2212}30 min")
    }

    @Test func dayRelation() {
        // 3:30 AM Tuesday in Chicago is 5:30 PM Tuesday in Tokyo.
        #expect(TimeZoneMath.dayRelation(of: tokyo, from: chicago, at: tuesdayMorning) == .today)
        // 8 PM Tuesday in Chicago is 10 AM Wednesday in Tokyo.
        let tuesdayEvening = date("2026-10-21T01:00:00Z")
        #expect(TimeZoneMath.dayRelation(of: tokyo, from: chicago, at: tuesdayEvening) == .tomorrow)
        // 8 AM Wednesday in Tokyo is 1 PM Tuesday in Honolulu.
        let tokyoMorning = date("2026-10-20T23:00:00Z")
        #expect(TimeZoneMath.dayRelation(of: honolulu, from: tokyo, at: tokyoMorning) == .yesterday)
        #expect(TimeZoneMath.subtitle(for: tokyo, from: chicago, at: tuesdayEvening) == "Tomorrow, +14 hrs")
    }

    @Test func wallClock() {
        let time = TimeZoneMath.wallClock(at: tuesdayMorning, in: chicago)
        #expect(time.hour == 3 && time.minute == 30 && time.second == 0)
        let london = TimeZoneMath.wallClock(at: tuesdayMorning, in: self.london)
        #expect(london.hour == 9 && london.minute == 30)
    }

    @Test func daytime() {
        #expect(!TimeZoneMath.isDaytime(at: tuesdayMorning, in: chicago))
        #expect(TimeZoneMath.isDaytime(at: tuesdayMorning, in: tokyo))
    }

    @Test func timeText() {
        #expect(TimeZoneMath.timeText(at: tuesdayMorning, in: tokyo, locale: Locale(identifier: "en_GB")) == "17:30")
    }

    @Test func cityCatalogFindsZonesAndAliases() {
        #expect(CityCatalog.bestMatch("tokyo")?.timeZoneID == "Asia/Tokyo")
        #expect(CityCatalog.bestMatch("San Francisco")?.timeZoneID == "America/Los_Angeles")
        #expect(CityCatalog.bestMatch("madison")?.timeZoneID == "America/Chicago")
        #expect(CityCatalog.bestMatch("Sao Paulo")?.timeZoneID == "America/Sao_Paulo")
        #expect(CityCatalog.search("new").contains { $0.name == "New York" })
        #expect(CityCatalog.search("").isEmpty)
    }

    @Test func worldTimeSentence() {
        let london = WorldClockCity(name: "London", timeZoneID: "Europe/London")
        let sentence = ForecastSummary.worldTime(city: london, at: tuesdayMorning, home: chicago, locale: Locale(identifier: "en_US"))
        #expect(sentence.contains("9:30"))
        #expect(sentence.contains("Tuesday"))
        #expect(sentence.hasSuffix("6 hrs ahead of here."))
    }
}
