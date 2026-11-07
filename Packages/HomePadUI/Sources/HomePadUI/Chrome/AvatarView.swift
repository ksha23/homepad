import HomePadCore
import SwiftUI

/// A round member avatar (emoji) filled with the member's color. Nil shows
/// the guest glyph.
///
///     AvatarView(member: household.activeMember, size: Theme.Size.tapTarget)
public struct AvatarView: View {
    private let member: HouseholdMember?
    private let size: CGFloat

    /// - Parameters:
    ///   - member: The person to show, or nil for a guest.
    ///   - size: Diameter in points.
    public init(member: HouseholdMember?, size: CGFloat = 44) {
        self.member = member
        self.size = size
    }

    public var body: some View {
        ZStack {
            Circle().fill(member.map { Color(hex: $0.colorHex) } ?? .gray.opacity(0.5))
            if let member {
                Text(member.avatar).font(.system(size: size * 0.5))
            } else {
                Image(systemName: "person.fill").font(.system(size: size * 0.45)).foregroundStyle(.white)
            }
        }
        .frame(width: size, height: size)
        .overlay(Circle().strokeBorder(.white.opacity(0.6), lineWidth: 2))
        .accessibilityLabel(member?.name ?? "Guest")
    }
}
