import Foundation
import HAKit
import HomePadCore

extension JSONValue {
    /// Converts a `JSONSerialization` value (what HAKit hands back) into a `JSONValue`.
    /// Booleans are told apart from numbers by their Core Foundation type.
    init(foundation value: Any?) {
        switch value {
        case nil, is NSNull:
            self = .null
        case let number as NSNumber:
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                self = .bool(number.boolValue)
            } else {
                self = .number(number.doubleValue)
            }
        case let string as String:
            self = .string(string)
        case let array as [Any]:
            self = .array(array.map { JSONValue(foundation: $0) })
        case let dictionary as [String: Any]:
            self = .object(dictionary.mapValues { JSONValue(foundation: $0) })
        case let bool as Bool:
            self = .bool(bool)
        case let int as Int:
            self = .number(Double(int))
        case let double as Double:
            self = .number(double)
        default:
            self = .string(String(describing: value!))
        }
    }

    /// Converts HAKit's loosely typed response data.
    init(haData: HAData) {
        switch haData {
        case .dictionary(let dictionary): self = JSONValue(foundation: dictionary)
        case .array(let array): self = .array(array.map(JSONValue.init(haData:)))
        case .primitive(let value): self = JSONValue(foundation: value)
        case .empty: self = .null
        }
    }

    /// A string array, for attributes such as `supported_color_modes`.
    var stringArray: [String] {
        arrayValue?.compactMap(\.stringValue) ?? []
    }
}
