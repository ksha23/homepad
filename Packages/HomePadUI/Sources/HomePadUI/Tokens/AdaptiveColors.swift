import SwiftUI
import UIKit

/// Colors that follow the app's appearance (Settings > Kiosk & Display >
/// Appearance). Screens use these instead of fixed black and white, so Light
/// shows white pages with dark text and Dark keeps HomePad's black pages.
/// Text uses `.primary`, `.secondary` and `.tertiary`, which follow it too.
/// Fixed black and white stay only where the color belongs to the content:
/// faces, photos, artwork, video and camera views, white text over pictures,
/// dimming scrims, and surfaces that keep themselves dark (the assistant
/// overlay, Music's player). Night always shows dark, whatever the setting.
/// See "Light and dark" in DESIGN.md.
public extension Color {
    /// An app screen's page: black in Dark, white in Light.
    static let screenBackground = Color(uiColor: .systemBackground)
    /// A page that holds grouped forms, such as Settings: black in Dark, and
    /// in Light the light gray that sets off a form's white rows.
    static let groupedBackground = Color(uiColor: .systemGroupedBackground)
    /// A surface raised on a page where glass does not fit, such as a row or a
    /// card: dark gray in Dark, light gray in Light.
    static let raisedBackground = Color(uiColor: .secondarySystemBackground)
    /// A row on a grouped page or sheet drawn outside a `List`, in the color a
    /// list draws its rows: white in Light, dark gray in Dark.
    static let groupedRow = Color(uiColor: .secondarySystemGroupedBackground)
    /// Hairline borders and dividers on a page.
    static let hairline = Color(uiColor: .separator)

    /// Black or white, whichever reads on `fill` in `scheme`: black on light
    /// fills (white, yellow, `.primary` in Dark), white on the rest (the
    /// accent, orange, `.primary` in Light). For symbols and titles on a
    /// filled button or a lit toggle.
    ///
    ///     .foregroundStyle(Color.foreground(on: tint, in: colorScheme))
    static func foreground(on fill: Color, in scheme: ColorScheme) -> Color {
        var environment = EnvironmentValues()
        environment.colorScheme = scheme
        let color = fill.resolve(in: environment)
        let luminance = 0.2126 * color.linearRed + 0.7152 * color.linearGreen + 0.0722 * color.linearBlue
        return luminance > 0.5 ? .black : .white
    }
}

public extension ShapeStyle where Self == Color {
    /// An app screen's page (`Color.screenBackground`).
    static var screenBackground: Color { Color.screenBackground }
    /// A page of grouped forms (`Color.groupedBackground`).
    static var groupedBackground: Color { Color.groupedBackground }
    /// A raised surface (`Color.raisedBackground`).
    static var raisedBackground: Color { Color.raisedBackground }
    /// A row outside a `List` on a grouped page (`Color.groupedRow`).
    static var groupedRow: Color { Color.groupedRow }
}
