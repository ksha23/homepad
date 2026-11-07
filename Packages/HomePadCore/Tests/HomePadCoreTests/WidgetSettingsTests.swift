import Foundation
import SwiftUI
import Testing
@testable import HomePadCore

/// A placed widget's own settings: typed keys with defaults, stored as plain JSON.
@MainActor @Suite struct WidgetSettingsTests {
    static let list = WidgetSettingKey<String?>("list", default: nil)
    static let accessories = WidgetSettingKey<[String]?>("accessories", default: nil)
    static let rows = WidgetSettingKey<Int>("rows", default: 4)

    @Test func unsetKeysReadTheirDefaults() {
        let settings = WidgetSettings()
        #expect(settings.isEmpty)
        #expect(settings[Self.list] == nil)
        #expect(settings[Self.accessories] == nil)
        #expect(settings[Self.rows] == 4)
    }

    @Test func valuesSurviveARoundTrip() throws {
        var settings = WidgetSettings()
        settings[Self.list] = "demo.errands"
        settings[Self.accessories] = ["demo:lock.front", "demo:light.kitchen"]
        settings[Self.rows] = 6
        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(WidgetSettings.self, from: data)
        #expect(decoded == settings)
        #expect(decoded[Self.list] == "demo.errands")
        #expect(decoded[Self.accessories] == ["demo:lock.front", "demo:light.kitchen"])
        #expect(decoded[Self.rows] == 6)
        // Stored as a plain object, so a saved layout reads clearly.
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(object?["list"] as? String == "demo.errands")
    }

    /// Setting the default removes the key, so the widget follows a changed default again.
    @Test func settingTheDefaultRemovesTheKey() {
        var settings = WidgetSettings()
        settings[Self.list] = "demo.errands"
        #expect(!settings.isEmpty)
        settings[Self.list] = nil
        #expect(settings.isEmpty)
        settings[Self.rows] = 4
        #expect(settings.isEmpty)
    }

    /// A value saved in another shape (a later version, a renamed type) reads as the default.
    @Test func aValueThatNoLongerDecodesReadsAsTheDefault() throws {
        let settings = try JSONDecoder().decode(WidgetSettings.self, from: Data(#"{"rows":"many","list":7}"#.utf8))
        #expect(settings[Self.rows] == 4)
        #expect(settings[Self.list] == nil)
    }

    @Test func aWidgetHasSettingsOnlyWithASettingsPage() {
        let plain = WidgetDescriptor(id: "plain", title: "Plain", systemImage: "square") { _ in EmptyView() }
        #expect(!plain.hasSettings)
        let configurable = WidgetDescriptor(id: "list", title: "List", systemImage: "checklist") { _ in
            EmptyView()
        } settings: { settings in
            Text(settings.wrappedValue[Self.list] ?? "Default")
        }
        #expect(configurable.hasSettings)
        #expect(configurable.supportedSizes == WidgetSize.standard)
    }
}
