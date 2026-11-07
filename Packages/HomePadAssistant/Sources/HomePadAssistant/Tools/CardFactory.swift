import Foundation
import HomePadCore

/// Builds `AssistantCard`s with a fixed payload shape per kind, so the card
/// views know exactly what to read.
enum CardFactory {
    static func accessories(_ accessories: [HomeAccessory], title: String) -> AssistantCard {
        AssistantCard(kind: .accessory, title: title, payload: ["accessories": .array(accessories.prefix(12).map { accessory in
            [
                "id": .string(accessory.id), "name": .string(accessory.name), "room": .string(accessory.room ?? ""),
                "status": .string(accessory.statusText), "kind": .string(accessory.kind.rawValue),
                "isOn": .bool(accessory.state.isOn ?? (accessory.state.lockState == .unlocked)),
            ]
        })])
    }

    static func weather(_ weather: WeatherSnapshot) -> AssistantCard {
        var payload: [String: JSONValue] = [
            "temperature": .number(weather.temperature), "condition": .string(weather.conditionText),
            "symbol": .string(weather.symbolName), "unit": .string(weather.unit == .celsius ? "C" : "F"),
        ]
        if let high = weather.high { payload["high"] = .number(high) }
        if let low = weather.low { payload["low"] = .number(low) }
        payload["hourly"] = .array(weather.hourly.prefix(6).map { hour in
            ["time": .number(hour.date.timeIntervalSince1970), "temperature": .number(hour.temperature), "symbol": .string(hour.symbolName)]
        })
        return AssistantCard(kind: .weather, title: weather.locationName, subtitle: weather.conditionText, payload: .object(payload))
    }

    static func calendar(_ items: [CalendarItem], title: String) -> AssistantCard {
        AssistantCard(kind: .calendar, title: title, payload: ["events": .array(items.prefix(12).map { item in
            [
                "title": .string(item.title), "start": .number(item.start.timeIntervalSince1970),
                "end": .number(item.end.timeIntervalSince1970), "allDay": .bool(item.isAllDay),
                "location": .string(item.location ?? ""), "color": .string(item.colorHex ?? ""),
                "reminder": .bool(item.isReminder),
            ]
        })])
    }

    static func timers(_ timers: [HomeTimer]) -> AssistantCard {
        AssistantCard(kind: .timer, title: timers.count == 1 ? timers[0].label : "Timers", payload: ["timers": .array(timers.map { timer in
            [
                "label": .string(timer.label), "end": .number(timer.endDate?.timeIntervalSince1970 ?? 0),
                "remaining": .number(timer.remaining()), "status": .string(timer.status.rawValue),
            ]
        })])
    }

    static func link(_ url: URL, title: String? = nil) -> AssistantCard {
        AssistantCard(kind: .link, title: title ?? url.host() ?? url.absoluteString, subtitle: url.host(), url: url)
    }
}
