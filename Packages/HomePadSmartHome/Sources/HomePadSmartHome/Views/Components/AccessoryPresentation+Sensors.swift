import HomePadCore

/// A read-only accessory's reading, the way Apple Home shows sensors in a room's
/// header: a symbol and a short value such as "72°", "41%", "Closed" or "Motion".
struct SensorReading: Equatable {
    var symbol: String
    var value: String
    /// Something to notice: motion, an open door, a leak, smoke, a ringing doorbell.
    var isAlert: Bool
}

extension AccessoryPresentation {
    /// Whether the accessory has anything to control. Sensors and doorbells only
    /// report, so the Home app shows them as compact readings instead of tiles.
    static func isControllable(_ accessory: HomeAccessory) -> Bool {
        primaryCommand(for: accessory) != nil || !accessory.capabilities.isEmpty
    }

    /// The symbol and short value of a sensor or doorbell.
    static func reading(for accessory: HomeAccessory) -> SensorReading {
        let state = accessory.state
        let symbol = sensorSymbol(for: accessory)
        guard state.isReachable else { return SensorReading(symbol: symbol, value: "No Response", isAlert: false) }
        if accessory.kind == .doorbell {
            let isRinging = state.isActive == true
            return SensorReading(symbol: symbol, value: isRinging ? "Ringing" : "Doorbell", isAlert: isRinging)
        }
        if let text = measurement(of: accessory) {
            return SensorReading(symbol: symbol, value: text, isAlert: false)
        }
        if let isOpen = contactIsOpen(state) {
            return SensorReading(symbol: symbol, value: isOpen ? "Open" : "Closed", isAlert: isOpen)
        }
        if let isActive = state.isActive {
            let words = binaryWords(accessory.deviceClass)
            return SensorReading(symbol: symbol, value: isActive ? words.on : words.off, isAlert: isActive)
        }
        if let battery = state.batteryLevel {
            return SensorReading(symbol: symbol, value: "\(Int((battery * 100).rounded()))%", isAlert: battery < 0.2)
        }
        return SensorReading(symbol: symbol, value: "Unknown", isAlert: false)
    }

    /// "72°", "41%", "612 ppm": the value a numeric sensor reports, rounded for a glance.
    static func measurement(of accessory: HomeAccessory) -> String? {
        let state = accessory.state
        if let temperature = temperature(of: accessory) { return "\(Int(temperature.rounded()))°" }
        if let humidity = state.humidity ?? (accessory.deviceClass == "humidity" ? state.sensorValue : nil) {
            return "\(Int(humidity.rounded()))%"
        }
        guard let value = state.sensorValue else { return nil }
        let number = value.formatted(.number.precision(.fractionLength(0...1)))
        guard let unit = state.sensorUnit, !unit.isEmpty else { return number }
        // Symbols hug the number ("45%"), words get a space ("612 ppm").
        return unit.hasPrefix("%") || unit.hasPrefix("°") ? number + unit : "\(number) \(unit)"
    }

    /// A temperature sensor's reading. Some report only a value in degrees.
    static func temperature(of accessory: HomeAccessory) -> Double? {
        let state = accessory.state
        if let current = state.currentTemperature { return current }
        let isDegrees = state.sensorUnit?.hasPrefix("°") ?? false
        return isDegrees || accessory.deviceClass == "temperature" ? state.sensorValue : nil
    }

    /// Open or closed for a door or window contact, nil for other sensors.
    private static func contactIsOpen(_ state: AccessoryState) -> Bool? {
        guard let door = state.doorState, door != .unknown else { return nil }
        return door == .open || door == .opening
    }

    /// What a binary sensor says when it detects something and when it does not.
    private static func binaryWords(_ deviceClass: String?) -> (on: String, off: String) {
        switch deviceClass {
        case "motion": ("Motion", "Clear")
        case "occupancy", "presence": ("Occupied", "Clear")
        case "moisture": ("Leak", "Dry")
        case "smoke": ("Smoke", "Clear")
        case "carbon_monoxide": ("CO", "Clear")
        case "gas": ("Gas", "Clear")
        case "battery": ("Low", "Normal")
        case "problem": ("Problem", "OK")
        case "sound": ("Sound", "Quiet")
        case "vibration": ("Vibration", "Still")
        case "light": ("Light", "Dark")
        default: ("Detected", "Clear")
        }
    }

    /// A symbol for what the sensor measures, filled while it detects something.
    static func sensorSymbol(for accessory: HomeAccessory) -> String {
        let state = accessory.state
        if accessory.kind == .doorbell { return "bell.fill" }
        if temperature(of: accessory) != nil { return "thermometer.medium" }
        if state.humidity != nil || accessory.deviceClass == "humidity" { return "humidity.fill" }
        if let isOpen = contactIsOpen(state) {
            switch accessory.deviceClass {
            case "window": return isOpen ? "window.vertical.open" : "window.vertical.closed"
            case "garage_door": return isOpen ? "door.garage.open" : "door.garage.closed"
            default: return isOpen ? "door.left.hand.open" : "door.left.hand.closed"
            }
        }
        let isActive = state.isActive == true
        switch accessory.deviceClass {
        case "illuminance", "light": return "sun.max.fill"
        case "battery": return batterySymbol(state.batteryLevel)
        case "carbon_dioxide": return "carbon.dioxide.cloud.fill"
        case "carbon_monoxide": return "carbon.monoxide.cloud.fill"
        case "pm25", "pm10", "pm1", "aqi", "volatile_organic_compounds", "volatile_organic_compounds_parts": return "aqi.medium"
        case "power", "energy", "voltage", "current": return "bolt.fill"
        case "pressure", "atmospheric_pressure": return "gauge.with.dots.needle.33percent"
        case "motion": return isActive ? "figure.walk.motion" : "figure.stand"
        case "occupancy", "presence": return isActive ? "person.fill" : "person"
        case "moisture": return isActive ? "drop.triangle.fill" : "drop"
        case "smoke": return "smoke.fill"
        case "gas": return "flame.fill"
        case "problem": return "exclamationmark.triangle.fill"
        case "sound": return "waveform"
        case "vibration": return "waveform.path"
        default: break
        }
        if state.sensorValue != nil { return "gauge.with.dots.needle.50percent" }
        if state.isActive != nil { return isActive ? "figure.walk.motion" : "figure.stand" }
        if state.batteryLevel != nil { return batterySymbol(state.batteryLevel) }
        return AccessoryKind.sensor.systemImage
    }

    private static func batterySymbol(_ level: Double?) -> String {
        guard let level else { return "battery.75percent" }
        return switch level {
        case ..<0.13: "battery.0percent"
        case ..<0.38: "battery.25percent"
        case ..<0.63: "battery.50percent"
        case ..<0.88: "battery.75percent"
        default: "battery.100percent"
        }
    }
}
