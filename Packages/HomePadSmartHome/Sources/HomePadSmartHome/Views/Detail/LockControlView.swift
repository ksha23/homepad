import HomePadCore
import HomePadUI
import SwiftUI

/// The lock's state in a glass circle, with one deliberate button. Guests are asked to confirm before unlocking.
struct LockControlView: View {
    @Environment(\.accessoryCommand) private var send
    @Environment(\.detailControlMetrics) private var metrics
    let accessory: HomeAccessory

    private var lockState: LockState { accessory.state.lockState ?? .unknown }
    private var isLocked: Bool { lockState == .locked || lockState == .locking }
    /// Locking or unlocking: the few seconds a bolt takes to move.
    private var isMoving: Bool { lockState == .locking || lockState == .unlocking }

    var body: some View {
        VStack(spacing: Theme.Spacing.xl) {
            Spacer(minLength: 0)
            Image(systemName: isLocked ? "lock.fill" : "lock.open.fill")
                .font(.system(size: metrics.circle * 0.43, weight: .semibold))
                .foregroundStyle(isLocked ? Theme.tint(for: .lock) : .orange)
                // The shackle closes or opens, and breathes while the bolt moves.
                .contentTransition(.symbolEffect(.replace.magic(fallback: .replace.downUp)))
                .symbolEffect(.pulse, options: .speed(0.6), isActive: isMoving)
                .frame(width: metrics.circle, height: metrics.circle)
                .glassEffect(.regular, in: .circle)
            Text(lockState.rawValue.capitalized)
                .font(.display(metrics.statusSize))
                .contentTransition(.interpolate)
            Spacer(minLength: 0)
            Button {
                send(isLocked ? .unlock : .lock, on: accessory)
            } label: {
                Label(isLocked ? "Unlock" : "Lock", systemImage: isLocked ? "lock.open" : "lock")
                    .frame(minWidth: 160)
            }
            .buttonStyle(.glassCapsule(size: metrics.button, tint: .accentColor))
            .disabled(isMoving || !accessory.state.isReachable)
        }
        .animation(.smooth, value: lockState)
    }
}
