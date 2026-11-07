import SwiftUI
import Testing
@testable import HomePadCore

/// Widget sizes and the cells they cover, which the Home Screen and the faces share.
@MainActor @Suite struct WidgetSizeTests {
    @Test func eachSizeCoversItsCells() {
        #expect(WidgetSize.allCases.map(\.columns) == [1, 2, 2, 2])
        #expect(WidgetSize.allCases.map(\.rows) == [1, 1, 2, 3])
        #expect(WidgetSize.allCases.map(\.title) == ["Small", "Medium", "Large", "Tall"])
    }

    /// Tall is for widgets that show more in it, so no widget claims it without asking.
    @Test func widgetsOptIntoTall() {
        #expect(WidgetSize.standard == [.small, .medium, .large])
        let plain = WidgetDescriptor(id: "plain", title: "Plain", systemImage: "square") { _ in EmptyView() }
        #expect(plain.supportedSizes == WidgetSize.standard)
        let tall = WidgetDescriptor(id: "list", title: "List", systemImage: "list.bullet",
                                    supportedSizes: [.medium, .tall]) { _ in EmptyView() }
        #expect(tall.supportedSizes == [.medium, .tall])
    }

    /// Saved layouts keep the raw value, so it must never change.
    @Test func theTallRawValueIsStable() {
        #expect(WidgetSize.tall.rawValue == "tall")
        #expect(WidgetSize(rawValue: "tall") == .tall)
    }
}
