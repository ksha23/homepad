import HomePadCore
import SwiftUI

/// A rounded-square app icon drawn from an SF Symbol on a tinted gradient,
/// in the HomeView / iPadOS style. Use `AppIconTile` when you also want the label.
///
/// No drop shadows: a page of shadowed icons is redrawn on every frame it
/// scrolls, which halved the Home Screen's frame rate on an M4 iPad.
///
/// At night the icon is dark with a light symbol. Night mode turns the screen
/// red, and a white symbol on an orange, pink or yellow icon came out the same
/// red as its background, so the symbol vanished.
public struct AppIcon: View {
    private let systemImage: String
    private let tint: Color
    private let size: CGFloat
    @Environment(\.displayCondition) private var condition

    /// - Parameters:
    ///   - systemImage: SF Symbol drawn in the middle.
    ///   - tint: Background color. A light-to-dark gradient is derived from it.
    ///   - size: Edge length in points.
    public init(systemImage: String, tint: Color, size: CGFloat = 96) {
        self.systemImage = systemImage
        self.tint = tint
        self.size = size
    }

    public var body: some View {
        let isNight = condition == .night
        RoundedRectangle(cornerRadius: Theme.Radius.icon(size), style: .continuous)
            .fill(isNight ? AnyShapeStyle(Color(white: 0.14)) : AnyShapeStyle(tint.gradient))
            .overlay {
                Image(systemName: systemImage)
                    .font(.system(size: size * 0.46, weight: .medium))
                    .foregroundStyle(.white)
                    .symbolRenderingMode(.hierarchical)
            }
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Radius.icon(size), style: .continuous)
                    .strokeBorder(.white.opacity(isNight ? 0.12 : 0.25), lineWidth: 1)
            }
            .frame(width: size, height: size)
    }
}

/// An app icon with its label underneath, for Home Screens and app grids.
///
/// On a wallpaper (the Home Screen) the label is white with a soft shadow in
/// either appearance, as on iPadOS. Elsewhere, such as a glass panel or a
/// sheet, pass `isOnWallpaper: false` for a `.primary` label.
///
///     AppIconTile(title: "Music", systemImage: "music.note", tint: .pink)
///     AppIconTile(title: "Messages", systemImage: "message.fill", tint: .green, badge: .locked)
///     AppIconTile(title: "Photos", systemImage: "photo", tint: .orange, isOnWallpaper: false)
public struct AppIconTile: View {
    /// A small marker drawn on the icon's corner.
    public enum Badge: Equatable, Sendable {
        case none
        /// Personal app that needs recognition before it opens.
        case locked
        /// Edit mode: the icon can be removed.
        case remove
        /// A count, like unread messages.
        case count(Int)
    }

    private let title: String
    private let systemImage: String
    private let tint: Color
    private let iconSize: CGFloat
    private let badge: Badge
    private let isOnWallpaper: Bool
    private let onRemove: (() -> Void)?
    private var menu: AnyView?

    /// - Parameters:
    ///   - title: Label under the icon.
    ///   - systemImage: SF Symbol for the icon.
    ///   - tint: Icon background color.
    ///   - iconSize: Icon edge length. The label scales with it.
    ///   - badge: Corner marker.
    ///   - isOnWallpaper: White label with a shadow for a wallpaper. False
    ///     draws a `.primary` label for glass panels and sheets.
    ///   - onRemove: Called when the `.remove` badge is tapped.
    public init(
        title: String, systemImage: String, tint: Color, iconSize: CGFloat = 96,
        badge: Badge = .none, isOnWallpaper: Bool = true, onRemove: (() -> Void)? = nil
    ) {
        self.title = title
        self.systemImage = systemImage
        self.tint = tint
        self.iconSize = iconSize
        self.badge = badge
        self.isOnWallpaper = isOnWallpaper
        self.onRemove = onRemove
    }

    public var body: some View {
        VStack(spacing: iconSize * 0.1) {
            AppIcon(systemImage: systemImage, tint: tint, size: iconSize)
                .overlay(alignment: .topLeading) { badgeView }
                .modifier(IconMenu(menu: menu, cornerRadius: Theme.Radius.icon(iconSize)))
            label
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(badge == .locked ? "\(title), locked" : title)
    }

    @ViewBuilder
    private var label: some View {
        let text = Text(title)
            .font(.system(size: max(14, iconSize * 0.19), weight: .medium))
            .lineLimit(1)
        if isOnWallpaper {
            text.foregroundStyle(.white).wallpaperLabelShadow()
        } else {
            text.foregroundStyle(.primary)
        }
    }

    /// The iPadOS long-press menu on the icon itself, so the lifted preview is the
    /// rounded icon and the menu opens right beside it. On the whole tile, which
    /// a grid stretches to fill its cell, the menu opened well away from the icon.
    public func iconMenu<Menu: View>(@ViewBuilder _ menu: () -> Menu) -> AppIconTile {
        var copy = self
        copy.menu = AnyView(menu())
        return copy
    }

    @ViewBuilder
    private var badgeView: some View {
        let badgeSize = max(26, iconSize * 0.3)
        switch badge {
        case .none:
            EmptyView()
        case .locked:
            Image(systemName: "lock.fill")
                .font(.system(size: badgeSize * 0.45, weight: .bold))
                .frame(width: badgeSize, height: badgeSize)
                .glassEffect(.regular, in: Circle())
                .offset(x: iconSize - badgeSize * 0.7, y: -badgeSize * 0.3)
        case .remove:
            RemoveBadge("Remove \(title)", size: badgeSize) { onRemove?() }
                .offset(x: -badgeSize * 0.3, y: -badgeSize * 0.3)
        case .count(let value):
            Text(value > 99 ? "99+" : "\(value)")
                .font(.system(size: badgeSize * 0.5, weight: .bold))
                .foregroundStyle(.white)
                .padding(.horizontal, badgeSize * 0.25)
                .frame(minWidth: badgeSize, minHeight: badgeSize)
                .background(.red, in: Capsule())
                .offset(x: iconSize - badgeSize * 0.7, y: -badgeSize * 0.3)
        }
    }
}

/// `AppIconTile.iconMenu(_:)`: a context menu previewed as the rounded icon.
private struct IconMenu: ViewModifier {
    let menu: AnyView?
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        if let menu {
            content
                .contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .contextMenu { menu }
        } else {
            content
        }
    }
}
