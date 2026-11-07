import HomePadCore
import SwiftUI

/// Runs an accessory command from any HomePad control. Read it from the environment:
///
///     @Environment(\.accessoryCommand) private var send
///     send(.toggle, on: accessory)
struct AccessoryCommandAction {
    let run: @MainActor (AccessoryCommand, HomeAccessory) -> Void

    @MainActor
    func callAsFunction(_ command: AccessoryCommand, on accessory: HomeAccessory) {
        run(command, accessory)
    }
}

/// Opens an accessory's full controls in the Home app, for widgets and Control
/// Center rows whose tap has no quick action (a thermostat, a sensor).
struct ShowAccessoryControlsAction {
    let run: @MainActor (HomeAccessory) -> Void

    @MainActor
    func callAsFunction(_ accessory: HomeAccessory) {
        run(accessory)
    }
}

extension EnvironmentValues {
    @Entry var accessoryCommand = AccessoryCommandAction { _, _ in }
    @Entry var showAccessoryControls = ShowAccessoryControlsAction { _ in }
}

extension View {
    /// Installs `accessoryCommand` and `showAccessoryControls` for this screen. Commands
    /// that unlock, open or disarm ask a guest to confirm first. Failures show an alert.
    func accessoryCommandHost() -> some View {
        modifier(AccessoryCommandHost())
    }
}

private struct AccessoryCommandHost: ViewModifier {
    @Environment(UnifiedSmartHomeService.self) private var service
    @Environment(AppServices.self) private var services
    @State private var pending: PendingCommand?
    @State private var errorMessage: String?

    private struct PendingCommand: Identifiable {
        let id = UUID()
        let command: AccessoryCommand
        let accessory: HomeAccessory
        var verb: String { SecurityPolicy.confirmationVerb(for: accessory.kind) }
    }

    func body(content: Content) -> some View {
        content
            .environment(\.accessoryCommand, AccessoryCommandAction { command, accessory in
                if SecurityPolicy.isSensitive(command, on: accessory), !services.household.isPersonalContentUnlocked {
                    pending = PendingCommand(command: command, accessory: accessory)
                } else {
                    send(command, to: accessory, confirmed: false)
                }
            })
            .environment(\.showAccessoryControls, ShowAccessoryControlsAction { service.showControls(for: $0.id) })
            .alert(
                pending.map { "\($0.verb) \($0.accessory.name)?" } ?? "",
                isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }),
                presenting: pending
            ) { item in
                Button(item.verb, role: .destructive) { send(item.command, to: item.accessory, confirmed: true) }
                Button("Cancel", role: .cancel) {}
            } message: { item in
                Text("Nobody is recognized right now. Only continue if you mean to \(item.verb.lowercased()) \(item.accessory.name).")
            }
            .alert(
                "Something Went Wrong",
                isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
    }

    private func send(_ command: AccessoryCommand, to accessory: HomeAccessory, confirmed: Bool) {
        Task {
            do {
                try await service.perform(command, on: accessory.id, confirmed: confirmed)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
