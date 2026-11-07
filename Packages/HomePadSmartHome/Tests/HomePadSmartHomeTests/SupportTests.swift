import Foundation
import HomePadCore
import Testing
@testable import HomePadSmartHome

@Suite("Support types")
struct SupportTests {
    @Test func backendIDs() {
        #expect(BackendID.make(.homeAssistant, "light.kitchen") == "ha:light.kitchen")
        #expect(BackendID.make(.homeKit, "1234") == "hk:1234")
        #expect(BackendID.backend(of: "ha:light.kitchen") == .homeAssistant)
        #expect(BackendID.backend(of: "demo:lock.front") == .demo)
        #expect(BackendID.backend(of: "light.kitchen") == nil)
        #expect(BackendID.localID(of: "ha:light.kitchen") == "light.kitchen")
        #expect(BackendID.localID(of: "hk:AB:CD") == "AB:CD")
        #expect(BackendID.localID(of: "unknown:x") == "unknown:x")
    }

    @Test func urlNormalization() {
        #expect(HomeAssistantConfiguration.normalizedURL(from: "homeassistant.local:8123")?.absoluteString == "http://homeassistant.local:8123")
        #expect(HomeAssistantConfiguration.normalizedURL(from: " https://ha.example.com/lovelace/0?x=1 ")?.absoluteString == "https://ha.example.com")
        #expect(HomeAssistantConfiguration.normalizedURL(from: "") == nil)
        #expect(HomeAssistantConfiguration.normalizedURL(from: "ftp://ha.local") == nil)
    }

    @Test func authorizedRequests() {
        let configuration = HomeAssistantConfiguration(baseURL: URL(string: "http://ha.test:8123")!, token: "secret")
        let request = configuration.request(path: "api/camera_proxy/camera.front")
        #expect(request.url?.absoluteString == "http://ha.test:8123/api/camera_proxy/camera.front")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer secret")
    }

    @Test func bonjourTXTRecords() {
        let instance = HomeAssistantDiscovery.instance(serviceName: "Home._home-assistant._tcp", txt: [
            "location_name": "Maple Street", "uuid": "abc", "version": "2026.10.2",
            "internal_url": "http://192.168.1.20:8123", "base_url": "http://ha.local:8123",
        ])
        #expect(instance?.name == "Maple Street")
        #expect(instance?.url.absoluteString == "http://192.168.1.20:8123")
        #expect(instance?.id == "abc")
        #expect(HomeAssistantDiscovery.instance(serviceName: "x", txt: [:]) == nil)
        #expect(HomeAssistantDiscovery.instance(serviceName: "Fallback", txt: ["base_url": "http://ha:8123"])?.name == "Fallback")
    }

    @Test func securityPolicy() {
        let lock = HomeAccessory(id: "demo:lock", name: "Front Door", kind: .lock, backend: .demo, state: AccessoryState(lockState: .locked))
        #expect(SecurityPolicy.isSensitive(.unlock, on: lock))
        #expect(SecurityPolicy.isSensitive(.toggle, on: lock))
        #expect(!SecurityPolicy.isSensitive(.lock, on: lock))
        let garage = HomeAccessory(id: "demo:garage", name: "Garage", kind: .garageDoor, backend: .demo, state: AccessoryState(position: 0, doorState: .closed))
        #expect(SecurityPolicy.isSensitive(.open, on: garage))
        #expect(SecurityPolicy.isSensitive(.setPosition(0.5), on: garage))
        #expect(!SecurityPolicy.isSensitive(.close, on: garage))
        let alarm = HomeAccessory(id: "demo:alarm", name: "Alarm", kind: .securitySystem, backend: .demo, state: AccessoryState(isOn: true))
        #expect(SecurityPolicy.isSensitive(.setPower(false), on: alarm))
        let light = HomeAccessory(id: "demo:light", name: "Lamp", kind: .light, backend: .demo)
        #expect(!SecurityPolicy.isSensitive(.toggle, on: light))
    }

    @Test func sensitiveRawCalls() {
        let kinds: [String: AccessoryKind] = ["cover.garage_door": .garageDoor, "cover.blinds": .cover]
        let check = { (domain: String, service: String, ids: [String]) in
            SecurityPolicy.isSensitiveServiceCall(domain: domain, service: service, entityIDs: ids) { kinds[$0] }
        }
        #expect(check("lock", "unlock", ["lock.front"]))
        #expect(check("alarm_control_panel", "alarm_disarm", []))
        #expect(check("cover", "open_cover", ["cover.garage_door"]))
        #expect(!check("cover", "open_cover", ["cover.blinds"]))
        #expect(!check("lock", "lock", ["lock.front"]))
        #expect(!check("media_player", "join", ["media_player.kitchen"]))
    }

    @Test func homeLayout() {
        var layout = HomeLayout()
        layout.roomOrder = ["Office", "Kitchen"]
        #expect(layout.ordered(["Bedroom", "Kitchen", "Attic", "Office"]) == ["Office", "Kitchen", "Attic", "Bedroom"])
        let thermostat = HomeAccessory(id: "t", name: "T", kind: .thermostat, backend: .demo)
        #expect(layout.tileSize(for: thermostat) == .wide)
        layout.tileSizes["t"] = .small
        #expect(layout.tileSize(for: thermostat) == .small)
    }

    @Test func favoriteDefaults() {
        let accessories = [
            HomeAccessory(id: "s", name: "Sensor", kind: .sensor, backend: .demo),
            HomeAccessory(id: "l", name: "Light", kind: .light, backend: .demo),
            HomeAccessory(id: "k", name: "Lock", kind: .lock, backend: .demo),
            HomeAccessory(id: "t", name: "Thermostat", kind: .thermostat, backend: .demo),
        ]
        #expect(FavoriteDefaults.accessoryIDs(from: accessories) == ["t", "k", "l"])
    }

    @Test func jsonFromFoundation() {
        let value = JSONValue(foundation: ["on": NSNumber(value: true), "level": NSNumber(value: 1), "name": "x", "none": NSNull(), "list": [1.5]])
        #expect(value["on"] == .bool(true))
        #expect(value["level"] == .number(1))
        #expect(value["none"] == .null)
        #expect(value["list"] == [1.5])
    }

    @Test func sceneSymbols() {
        #expect(SceneSymbol.symbol(icon: "mdi:weather-night", name: "Bedtime") == "moon.stars.fill")
        #expect(SceneSymbol.symbol(icon: nil, name: "Dinner Party") == "fork.knife")
        #expect(SceneSymbol.symbol(icon: nil, name: "Zebra") == nil)
    }

    @Test func dashboardThemeUsesHomePadTokens() {
        let css = DashboardTheme.homeAssistantCSS(accent: .orange)
        #expect(css.contains("--ha-card-border-radius: 28px"))
        #expect(css.contains("-apple-system"))
        // Black in Dark and white in Light, picked by the web view's appearance.
        #expect(css.contains("@media (prefers-color-scheme: dark)"))
        #expect(css.contains("--primary-background-color: #000000"))
        #expect(css.contains("@media (prefers-color-scheme: light)"))
        #expect(css.contains("--primary-background-color: #ffffff"))
        #expect(!DashboardTheme.earlySetupScript.contains("dark: true"))
        #expect(DashboardTheme.hex(.white) == "#FFFFFF")
        #expect(DashboardTheme.styleScript("a { color: red }").contains("homepad-theme"))
    }

    @Test func webPanelURLs() {
        #expect(WebPanel(name: "Frigate", symbol: .video, url: "frigate.local:5000").resolvedURL?.absoluteString == "http://frigate.local:5000")
        #expect(WebPanel(name: "Empty", symbol: .globe, url: "  ").resolvedURL == nil)
    }
}
