import HomePadCore

/// Extra demo accessories, cameras and scenes on top of Core's `DemoSmartHomeService`,
/// so the simulator shows every kind of control the Home app has.
enum DemoSeedData {
    /// An Apple Home style group, so the simulator shows a group tile and its members.
    static let groups: [(id: String, name: String)] = [("demo:group.living_lamps", "Sofa Lamps")]

    static let accessories: [HomeAccessory] = [
        HomeAccessory(id: "demo:light.floor_lamp", name: "Floor Lamp", room: "Living Room", kind: .light, backend: .demo,
                      capabilities: [.power, .brightness], state: AccessoryState(isOn: true, brightness: 0.6),
                      groupID: "demo:group.living_lamps"),
        HomeAccessory(id: "demo:light.reading_lamp", name: "Reading Lamp", room: "Living Room", kind: .light, backend: .demo,
                      capabilities: [.power, .brightness], state: AccessoryState(isOn: false, brightness: 0.4),
                      groupID: "demo:group.living_lamps"),
        HomeAccessory(id: "demo:light.bedroom", name: "Bedroom Lights", room: "Bedroom", kind: .light, backend: .demo,
                      capabilities: [.power, .brightness, .colorTemperature, .color],
                      state: AccessoryState(isOn: true, brightness: 0.35, colorTemperatureKelvin: 2700)),
        HomeAccessory(id: "demo:switch.coffee", name: "Coffee Maker", room: "Kitchen", kind: .switchOutlet, backend: .demo,
                      capabilities: [.power], state: AccessoryState(isOn: false)),
        HomeAccessory(id: "demo:media.living", name: "Living Room Speaker", room: "Living Room", kind: .mediaPlayer, backend: .demo,
                      capabilities: [.power, .playback, .volume],
                      state: AccessoryState(isOn: true, isActive: true, mediaTitle: "Weightless", mediaArtist: "Marconi Union", volume: 0.35, isPlaying: true)),
        HomeAccessory(id: "demo:garage.main", name: "Garage Door", room: "Garage", kind: .garageDoor, backend: .demo,
                      capabilities: [.position], state: AccessoryState(position: 0, doorState: .closed)),
        HomeAccessory(id: "demo:alarm.home", name: "Alarm", room: "Entryway", kind: .securitySystem, backend: .demo,
                      capabilities: [.power], state: AccessoryState(isOn: false)),
        HomeAccessory(id: "demo:vacuum.robot", name: "Robot Vacuum", room: "Living Room", kind: .vacuum, backend: .demo,
                      capabilities: [.power], state: AccessoryState(isOn: false, batteryLevel: 0.82)),
        HomeAccessory(id: "demo:purifier.bedroom", name: "Air Purifier", room: "Bedroom", kind: .airPurifier, backend: .demo,
                      capabilities: [.power], state: AccessoryState(isOn: true)),
        // Sensors of each sort, so every room header shows readings.
        HomeAccessory(id: "demo:sensor.living_humidity", name: "Living Room Humidity", room: "Living Room", kind: .sensor, backend: .demo,
                      state: AccessoryState(humidity: 41, sensorValue: 41, sensorUnit: "%"), deviceClass: "humidity"),
        HomeAccessory(id: "demo:sensor.porch_motion", name: "Porch Motion", room: "Entryway", kind: .sensor, backend: .demo,
                      state: AccessoryState(isActive: false), deviceClass: "motion"),
        HomeAccessory(id: "demo:sensor.front_door_contact", name: "Front Door Sensor", room: "Entryway", kind: .sensor, backend: .demo,
                      state: AccessoryState(doorState: .closed, isActive: false), deviceClass: "door"),
        HomeAccessory(id: "demo:sensor.hallway_motion", name: "Hallway Motion", room: "Hallway", kind: .sensor, backend: .demo,
                      state: AccessoryState(isActive: true), deviceClass: "motion"),
        HomeAccessory(id: "demo:sensor.hallway_smoke", name: "Smoke Alarm", room: "Hallway", kind: .sensor, backend: .demo,
                      state: AccessoryState(isActive: false, batteryLevel: 0.9), deviceClass: "smoke"),
        HomeAccessory(id: "demo:sensor.kitchen_leak", name: "Sink Leak Sensor", room: "Kitchen", kind: .sensor, backend: .demo,
                      state: AccessoryState(isActive: false), deviceClass: "moisture"),
        HomeAccessory(id: "demo:sensor.bedroom_temperature", name: "Bedroom Temperature", room: "Bedroom", kind: .sensor, backend: .demo,
                      state: AccessoryState(currentTemperature: 68.5, sensorValue: 68.5, sensorUnit: "°"), deviceClass: "temperature"),
        HomeAccessory(id: "demo:sensor.office_co2", name: "Office Air Quality", room: "Office", kind: .sensor, backend: .demo,
                      state: AccessoryState(sensorValue: 612, sensorUnit: "ppm"), deviceClass: "carbon_dioxide"),
        // Names as long as real ones, so tiles and widget rows are checked against them.
        HomeAccessory(id: "demo:lock.ultra", name: "Hallway Lock", room: "Hallway", kind: .lock, backend: .demo,
                      capabilities: [.lock], state: AccessoryState(lockState: .locked)),
        HomeAccessory(id: "demo:light.bedroom_ceiling", name: "Bedroom Ceiling Light", room: "Bedroom", kind: .light, backend: .demo,
                      capabilities: [.power, .brightness], state: AccessoryState(isOn: true, brightness: 0.8)),
        HomeAccessory(id: "demo:light.hue_1", name: "Hue color lamp 1", room: "Bedroom", kind: .light, backend: .demo,
                      capabilities: [.power, .brightness, .colorTemperature, .color],
                      state: AccessoryState(isOn: true, brightness: 0.45, hue: 30, saturation: 0.8)),
        HomeAccessory(id: "demo:light.hue_2", name: "Hue color lamp 2", room: "Bedroom", kind: .light, backend: .demo,
                      capabilities: [.power, .brightness, .colorTemperature, .color], state: AccessoryState(isOn: false)),
        HomeAccessory(id: "demo:light.desk", name: "Desk Lamp", room: "Office", kind: .light, backend: .demo,
                      capabilities: [.power, .brightness], state: AccessoryState(isOn: false)),
        HomeAccessory(id: "demo:light.table", name: "Table Lamp", room: "Living Room", kind: .light, backend: .demo,
                      capabilities: [.power, .brightness], state: AccessoryState(isOn: true, brightness: 0.3)),
        HomeAccessory(id: "demo:cover.bedroom", name: "Bedroom Blinds", room: "Bedroom", kind: .cover, backend: .demo,
                      capabilities: [.position], state: AccessoryState(position: 0.4, doorState: .open)),
    ]

    static let cameras: [HomeCamera] = [
        HomeCamera(id: "demo:camera.driveway", name: "Driveway", room: "Outside", backend: .demo),
        HomeCamera(id: "demo:camera.living", name: "Living Room", room: "Living Room", backend: .demo),
    ]

    static let scenes: [HomeScene] = [
        HomeScene(id: "demo:scene.movie", name: "Movie Night", backend: .demo, systemImage: "tv.fill"),
        HomeScene(id: "demo:scene.dinner", name: "Dinner", backend: .demo, systemImage: "fork.knife"),
    ]

    /// What each demo scene does, so tapping a scene visibly changes the tiles.
    static let sceneActions: [HomeScene.ID: [(HomeAccessory.ID, AccessoryCommand)]] = [
        "demo:scene.morning": [
            ("demo:light.kitchen", .setBrightness(0.8)), ("demo:cover.living", .open),
            ("demo:switch.coffee", .setPower(true)), ("demo:climate.living", .setTargetTemperature(70)),
        ],
        "demo:scene.night": [
            ("demo:light.kitchen", .setPower(false)), ("demo:light.living", .setPower(false)),
            ("demo:light.entry", .setPower(false)), ("demo:light.bedroom", .setPower(false)),
            ("demo:lock.front", .lock), ("demo:garage.main", .close), ("demo:cover.living", .close),
        ],
        "demo:scene.away": [
            ("demo:light.kitchen", .setPower(false)), ("demo:light.living", .setPower(false)),
            ("demo:light.bedroom", .setPower(false)), ("demo:lock.front", .lock), ("demo:alarm.home", .setPower(true)),
        ],
        "demo:scene.movie": [
            ("demo:light.living", .setBrightness(0.2)), ("demo:light.kitchen", .setPower(false)), ("demo:cover.living", .close),
        ],
        "demo:scene.dinner": [
            ("demo:light.kitchen", .setBrightness(0.6)), ("demo:light.kitchen", .setColorTemperature(kelvin: 2700)),
        ],
    ]
}
