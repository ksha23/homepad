import Foundation

/// Rebuilds complete tool calls from streamed fragments.
///
/// OpenAI-style streams send a call's id and name once, then the JSON
/// arguments in pieces, keyed by `index`. Some compatible servers omit the
/// index or send each call whole, so lookups fall back to the id and then to
/// the most recent call.
struct ToolCallAccumulator: Sendable {
    private struct Slot: Sendable {
        var id: String?
        var name: String = ""
        var arguments: String = ""
    }

    private var slots: [Slot] = []
    private var slotForIndex: [Int: Int] = [:]

    var isEmpty: Bool { slots.isEmpty }

    /// Applies one fragment. Returns the tool name when this fragment started a new call.
    @discardableResult
    mutating func apply(index: Int?, id: String?, name: String?, argumentsDelta: String?) -> String? {
        let position: Int
        var isNew = false
        if let index, let existing = slotForIndex[index] {
            position = existing
        } else if index == nil, let id, let existing = slots.firstIndex(where: { $0.id == id }) {
            position = existing
        } else if index == nil, id == nil, !slots.isEmpty {
            position = slots.count - 1
        } else {
            slots.append(Slot())
            position = slots.count - 1
            if let index { slotForIndex[index] = position }
            isNew = true
        }
        if let id, !id.isEmpty { slots[position].id = id }
        if let name, !name.isEmpty, name != slots[position].name { slots[position].name += name }
        if let argumentsDelta { slots[position].arguments += argumentsDelta }
        return isNew ? slots[position].name : nil
    }

    /// The finished calls in arrival order. Missing ids are generated, empty arguments become `{}`.
    func calls() -> [ToolCall] {
        slots.enumerated().compactMap { offset, slot in
            guard !slot.name.isEmpty else { return nil }
            let arguments = slot.arguments.trimmingCharacters(in: .whitespacesAndNewlines)
            return ToolCall(id: slot.id ?? "call_\(offset)", name: slot.name, arguments: arguments.isEmpty ? "{}" : arguments)
        }
    }
}
