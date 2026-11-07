import Foundation
import HomePadCore
import Testing
@testable import HomePadSmartHome

/// Reading what `notify.mobile_app_<device>` sends: the Home Assistant app's
/// kiosk commands, HomePad's own, and plain messages.
@Suite("Home Assistant device commands")
struct MobileAppCommandTests {
    private func parse(_ json: String) throws -> MobileAppCommand {
        MobileAppCommand.parse(try JSONValue.parse(json))
    }

    private func isIgnored(_ command: MobileAppCommand) -> Bool {
        if case .ignored = command { return true }
        return false
    }

    @Test func kioskCommands() throws {
        #expect(try parse(#"{"message": "kiosk_show_screensaver"}"#) == .sleep)
        #expect(try parse(#"{"message": "kiosk_hide_screensaver"}"#) == .wake)
        #expect(MobileAppCommand.parse(JSONValue(haData: Fixtures.eventData("ws_event_push_show_camera")))
            == .showCamera(entityID: "camera.front_door"))
        #expect(try parse(#"{"message": "kiosk_hide_camera"}"#) == .hideCamera)
        #expect(try parse(#"{"message": "kiosk_set_brightness", "data": {"level": 40}}"#) == .setBrightness(0.4))
        #expect(try parse(#"{"message": "kiosk_set_brightness", "data": {"level": "75"}}"#) == .setBrightness(0.75))
        #expect(try parse(#"{"message": "kiosk_set_brightness", "data": {"level": 140}}"#) == .setBrightness(1))
        #expect(try parse(#"{"message": "kiosk_set_volume", "data": {"volume": 30}}"#) == .setVolume(0.3))
        #expect(try parse(#"{"message": "kiosk_reload"}"#) == .reload)
        #expect(try parse(#"{"message": "kiosk_default"}"#) == .showDefaultFace)
    }

    @Test func kioskCommandsWithoutWhatTheyNeed() throws {
        #expect(isIgnored(try parse(#"{"message": "kiosk_show_camera", "data": {"entity_id": "light.kitchen"}}"#)))
        #expect(isIgnored(try parse(#"{"message": "kiosk_show_camera"}"#)))
        #expect(isIgnored(try parse(#"{"message": "kiosk_set_brightness"}"#)))
        #expect(isIgnored(try parse(#"{"message": "kiosk_set_screensaver_mode", "data": {"mode": "blank"}}"#)))
        #expect(isIgnored(try parse(#"{"message": "kiosk_something_new"}"#)))
    }

    @Test func homePadCommands() throws {
        #expect(try parse(#"{"message": "homepad_show_face", "data": {"face": "faces.night"}}"#) == .showFace("faces.night"))
        #expect(try parse(#"{"message": "homepad_show_face"}"#) == .showFace(nil))
        #expect(try parse(#"{"message": "homepad_go_home"}"#) == .goHome)
        #expect(try parse(#"{"message": "homepad_open_app", "data": {"app": "recipes"}}"#) == .openApp("recipes"))
        #expect(isIgnored(try parse(#"{"message": "homepad_open_app"}"#)))
        #expect(try parse(#"{"message": "homepad_speak", "title": "Kitchen", "data": {"text": "Dinner is ready"}}"#)
            == .speak("Dinner is ready", title: "Kitchen"))
        #expect(isIgnored(try parse(#"{"message": "homepad_speak", "data": {"text": "  "}}"#)))
    }

    @Test func plainMessagesAreBanners() throws {
        #expect(MobileAppCommand.parse(JSONValue(haData: Fixtures.eventData("ws_event_push_message")))
            == .banner(title: "Laundry", message: "The washer is done."))
        #expect(try parse(#"{"message": "Front door left open"}"#) == .banner(title: nil, message: "Front door left open"))
        // What Home Assistant sends every phone app is not for people to read.
        #expect(isIgnored(try parse(#"{"message": "request_location_update"}"#)))
        #expect(isIgnored(try parse(#"{"message": "clear_notification", "data": {"tag": "x"}}"#)))
        #expect(isIgnored(try parse(#"{"message": ""}"#)))
    }
}
