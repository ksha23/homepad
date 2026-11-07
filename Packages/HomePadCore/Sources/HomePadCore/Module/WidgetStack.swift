import Foundation
import SwiftUI

/// A widget stack, as an iPadOS Smart Stack: several widgets of one size in
/// one place on the Home Screen or a face. A vertical swipe flips through
/// them, and Smart Rotate turns to the one that matters right now
/// (`WidgetRelevance`, `WidgetStackRotation`).
///
/// The place that holds the stack keeps its size and spot. The stack keeps
/// its widgets, in order, each with its own settings. The first is the one
/// it rests on until the person flips to another.
public struct WidgetStack: Codable, Hashable, Sendable {
    /// One widget in the stack.
    public struct Member: Codable, Hashable, Sendable, Identifiable {
        /// Tells two copies of one widget apart, and keeps the person's choice
        /// and its settings with it as the stack is reordered.
        public var id: String
        /// The widget's `WidgetDescriptor.id`.
        public var widgetID: String
        /// Its own settings, as Edit Widget changes them. Nil until one changes.
        public var settings: WidgetSettings?

        public init(id: String = UUID().uuidString, widgetID: String, settings: WidgetSettings? = nil) {
            self.id = id
            self.widgetID = widgetID
            self.settings = settings.flatMap { $0.isEmpty ? nil : $0 }
        }
    }

    /// The widgets, in order. The first is the one the stack rests on.
    public var members: [Member]
    /// Turns to the most relevant widget and back. On unless turned off in Edit Stack.
    public var smartRotate: Bool

    /// The most widgets a stack holds, as on iPadOS.
    public static let maxMembers = 10

    public init(members: [Member], smartRotate: Bool = true) {
        self.members = Array(members.prefix(Self.maxMembers))
        self.smartRotate = smartRotate
    }

    /// True when it holds as many widgets as it can.
    public var isFull: Bool { members.count >= Self.maxMembers }

    /// True when `count` more widgets fit.
    public func hasRoom(for count: Int) -> Bool {
        members.count + count <= Self.maxMembers
    }

    public func member(_ id: String) -> Member? {
        members.first { $0.id == id }
    }

    // MARK: Changing it

    /// Puts widgets on top, as a widget dropped on a stack lands there.
    /// Those that do not fit are left out.
    public mutating func putOnTop(_ added: [Member]) {
        members = Array((added + members).prefix(Self.maxMembers))
    }

    /// Adds a widget at the bottom, unless the stack is full.
    public mutating func append(_ member: Member) {
        guard !isFull else { return }
        members.append(member)
    }

    public mutating func remove(_ memberID: String) {
        members.removeAll { $0.id == memberID }
    }

    /// Reorders, as a list's drag does.
    public mutating func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        members.move(fromOffsets: source, toOffset: destination)
    }

    /// A widget's own settings, empty when none changed.
    public func settings(for memberID: String) -> WidgetSettings {
        member(memberID)?.settings ?? WidgetSettings()
    }

    public mutating func setSettings(_ settings: WidgetSettings, for memberID: String) {
        guard let index = members.firstIndex(where: { $0.id == memberID }) else { return }
        members[index].settings = settings.isEmpty ? nil : settings
    }

    // MARK: Sizes

    /// The sizes every one of these widgets supports, in `WidgetSize.allCases`
    /// order: the sizes a stack of them can take.
    public static func sizes(supportedByAll supported: [[WidgetSize]]) -> [WidgetSize] {
        WidgetSize.allCases.filter { size in supported.allSatisfy { $0.contains(size) } }
    }

    // MARK: Smart Stack

    /// The widgets a new Smart Stack starts with, in this order when they
    /// are registered. Calm ones come first, since the stack rests on its
    /// first widget, and the camera last, since a live picture costs the most.
    /// Widgets with a relevance hook that are not listed follow, in the order
    /// they registered.
    public static let suggestedOrder = [
        "personal.upnext", "personal.weather", "audio.nowplaying", "kitchen.timers", "shell.homestatus", "smarthome.camera",
    ]

    /// The widgets a new Smart Stack of `size` starts with: those that can
    /// say when they matter (`WidgetDescriptor.relevance`) and come in that
    /// size, from the ones offered, in `suggestedOrder`.
    public static func suggested(from widgets: [WidgetDescriptor], size: WidgetSize) -> [WidgetDescriptor] {
        let candidates = widgets.filter { $0.relevance != nil && $0.supportedSizes.contains(size) }
        func rank(_ widget: WidgetDescriptor) -> Int {
            suggestedOrder.firstIndex(of: widget.id) ?? suggestedOrder.count
        }
        let ordered = candidates.enumerated().sorted { (rank($0.element), $0.offset) < (rank($1.element), $1.offset) }
        return Array(ordered.map(\.element).prefix(maxMembers))
    }

    /// The sizes a Smart Stack is offered at: those with at least two widgets to stack.
    public static func smartStackSizes(from widgets: [WidgetDescriptor]) -> [WidgetSize] {
        WidgetSize.allCases.filter { suggested(from: widgets, size: $0).count >= 2 }
    }

    /// A new stack of these widgets, each with an ID of its own.
    public static func of(_ widgetIDs: [String], smartRotate: Bool = true) -> WidgetStack {
        WidgetStack(members: widgetIDs.map { Member(widgetID: $0) }, smartRotate: smartRotate)
    }
}

extension WidgetStack {
    private enum CodingKeys: String, CodingKey {
        case members, smartRotate
    }

    /// Smart Rotate reads as on when it is missing, as a new stack starts.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        members = try container.decode([Member].self, forKey: .members)
        smartRotate = try container.decodeIfPresent(Bool.self, forKey: .smartRotate) ?? true
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(members, forKey: .members)
        try container.encode(smartRotate, forKey: .smartRotate)
    }
}
