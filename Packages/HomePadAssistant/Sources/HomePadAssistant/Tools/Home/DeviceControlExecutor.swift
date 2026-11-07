import Foundation
import HomePadCore

/// Runs a batch of device instructions: resolve targets, map commands, ask
/// once per sensitive command, perform, and summarize what happened.
@MainActor
struct DeviceControlExecutor {
    /// One requested change aimed at a spoken target.
    struct Step: Sendable {
        var device: String?
        var room: String?
        var instruction: DeviceInstruction
    }

    /// What happened, for the model's tool result and the accessory card.
    struct Report: Equatable {
        var done: [String] = []
        var skipped: [String] = []
        var declined: [String] = []
        var touchedIDs: [HomeAccessory.ID] = []

        var summary: String {
            var lines: [String] = []
            if !done.isEmpty { lines.append("Done: " + done.joined(separator: "; ") + ".") }
            if !declined.isEmpty { lines.append("Not done, the person said no: " + declined.joined(separator: ", ") + ".") }
            if !skipped.isEmpty { lines.append("Skipped: " + skipped.joined(separator: " ")) }
            return lines.isEmpty ? "Nothing matched." : lines.joined(separator: "\n")
        }
    }

    let smartHome: any SmartHomeService
    let confirm: @MainActor (String) async -> Bool

    func run(_ steps: [Step]) async -> Report {
        var report = Report()
        var planned: [(HomeAccessory, AccessoryCommand)] = []
        for step in steps {
            let targets = DeviceTargetResolver.resolve(device: step.device, room: step.room, in: smartHome.accessories)
            if targets.isEmpty {
                let place = step.room.map { " in \($0)" } ?? ""
                report.skipped.append("No device matches \"\(step.device ?? "everything")\"\(place).")
                continue
            }
            // Devices that cannot do this (a lock in "turn off everything") are skipped quietly
            // unless nothing in the step could.
            var firstError: DeviceCommandMapper.MappingError?
            let before = planned.count
            for accessory in targets {
                switch DeviceCommandMapper.command(for: step.instruction, on: accessory) {
                case .success(let command): planned.append((accessory, command))
                case .failure(let error): firstError = firstError ?? error
                }
            }
            if planned.count == before, let firstError { report.skipped.append(firstError.description) }
        }

        let approved = await approve(planned, report: &report)
        for (accessory, command) in approved {
            do {
                try await smartHome.perform(command, on: accessory.id)
                report.done.append("\(accessory.name) \(Self.describe(command))")
                report.touchedIDs.append(accessory.id)
            } catch {
                report.skipped.append("\(accessory.name) failed: \(error.localizedDescription)")
            }
        }
        return report
    }

    /// Asks one question per sensitive command type ("Unlock the Front Door and the Back Door?").
    private func approve(_ planned: [(HomeAccessory, AccessoryCommand)], report: inout Report) async -> [(HomeAccessory, AccessoryCommand)] {
        let sensitive = planned.filter { SensitiveActionPolicy.requiresConfirmation($0.1, on: $0.0) }
        guard !sensitive.isEmpty else { return planned }
        var rejected = Set<HomeAccessory.ID>()
        for command in sensitive.map(\.1).uniqued() {
            let accessories = sensitive.filter { $0.1 == command }.map(\.0)
            if await !confirm(SensitiveActionPolicy.question(for: command, accessories: accessories)) {
                rejected.formUnion(accessories.map(\.id))
                report.declined += accessories.map(\.name)
            }
        }
        return planned.filter { !rejected.contains($0.0.id) }
    }

    /// Past-tense description, for example "turned off" or "set to 40%".
    static func describe(_ command: AccessoryCommand) -> String {
        switch command {
        case .setPower(let on): on ? "turned on" : "turned off"
        case .toggle: "toggled"
        case .setBrightness(let value): "set to \(Int((value * 100).rounded()))%"
        case .setColorTemperature(let kelvin): "set to \(kelvin)K white"
        case .setHueSaturation: "color changed"
        case .setTargetTemperature(let value): "set to \(value.formatted(.number.precision(.fractionLength(0...1))))°"
        case .setHVACMode(let mode): mode == .off ? "turned off" : "set to \(mode.rawValue)"
        case .lock: "locked"
        case .unlock: "unlocked"
        case .setPosition(let value): "set to \(Int((value * 100).rounded()))% open"
        case .open: "opened"
        case .close: "closed"
        case .stop: "stopped"
        case .setVolume(let value): "volume \(Int((value * 100).rounded()))%"
        case .play: "playing"
        case .pause: "paused"
        case .nextTrack: "skipped ahead"
        case .previousTrack: "went back"
        }
    }
}

extension Sequence where Element: Hashable {
    /// Unique elements in first-seen order.
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
