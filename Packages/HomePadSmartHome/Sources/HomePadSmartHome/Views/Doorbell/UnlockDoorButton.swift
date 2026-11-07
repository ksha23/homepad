import HomePadCore
import HomePadUI
import SwiftUI

/// "Unlock Front Door", which turns into a quiet "Unlocked" once it is open.
struct UnlockDoorButton: View {
    @Environment(\.accessoryCommand) private var send
    let lock: HomeAccessory

    var body: some View {
        let isUnlocked = lock.state.lockState == .unlocked
        Button {
            send(.unlock, on: lock)
        } label: {
            Label(isUnlocked ? "\(lock.name) Unlocked" : "Unlock \(lock.name)", systemImage: isUnlocked ? "lock.open.fill" : "lock.fill")
                .contentTransition(.symbolEffect(.replace))
        }
        // The size of a full-screen alert's main action.
        .buttonStyle(.glassCapsule(size: .extraLarge))
        .disabled(isUnlocked || !lock.state.isReachable)
    }
}
