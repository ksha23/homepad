import HomePadCore
import HomePadUI
import SwiftUI

extension View {
    /// Glows in the accessory's color for a moment when it turns on or off,
    /// opens or closes, or locks or unlocks, from a tap here or a change
    /// anywhere else. It plays once per change (`changeGlow`), so an idle
    /// screen does no work for it.
    func accessoryChangeGlow(_ accessory: HomeAccessory, in shape: some InsettableShape) -> some View {
        modifier(AccessoryChangeGlow(accessory: accessory, shape: shape))
    }
}

private struct AccessoryChangeGlow<S: InsettableShape>: ViewModifier {
    let accessory: HomeAccessory
    let shape: S
    @State private var changes = 0

    /// What a glow follows: whether the accessory is on, and whether it answers.
    private struct Key: Equatable {
        var isReachable: Bool
        var isActive: Bool
    }

    func body(content: Content) -> some View {
        let key = Key(isReachable: accessory.state.isReachable, isActive: AccessoryPresentation.isActive(accessory))
        content
            .changeGlow(changes, tint: Theme.tint(for: accessory.kind), in: shape)
            .onChange(of: key) { old, new in
                // Not when it drops off or comes back: a reconnect would light
                // every tile at once.
                guard Self.glows(accessory.kind), old.isReachable, new.isReachable, old.isActive != new.isActive else { return }
                changes += 1
            }
    }

    /// Accessories people switch. Sensors and doorbells change on their own all
    /// day (motion, a door opening), and a glow for each would never rest.
    private static func glows(_ kind: AccessoryKind) -> Bool {
        kind != .sensor && kind != .doorbell
    }
}
