import Foundation
import Testing
@testable import HomePadCameraLab

@Suite struct QRPayloadTests {
    @Test func parsesWiFiWithEscapes() {
        guard case .wifi(let network) = QRPayload.parse(#"WIFI:T:WPA;S:Kyle\;s Place;P:pa\:ss\\word;H:true;;"#) else {
            Issue.record("Expected Wi-Fi")
            return
        }
        #expect(network.ssid == "Kyle;s Place")
        #expect(network.security == "WPA")
        #expect(network.password == #"pa:ss\word"#)
        #expect(network.isHidden)
    }

    @Test func openWiFiHasNoPassword() {
        guard case .wifi(let network) = QRPayload.parse("WIFI:S:Cafe;T:nopass;P:;;") else {
            Issue.record("Expected Wi-Fi")
            return
        }
        #expect(network.ssid == "Cafe")
        #expect(network.security == nil)
        #expect(network.password == nil)
        #expect(!network.isHidden)
    }

    @Test func decodesMatterReferencePayload() throws {
        // The Matter SDK's default test vector: vendor 12, product 1, SoftAP,
        // discriminator 128, passcode 2048.
        guard case .matter(let matter) = QRPayload.parse("MT:M5L90MP500K64J00000") else {
            Issue.record("Expected Matter")
            return
        }
        #expect(matter.version == 0)
        #expect(matter.vendorID == 12)
        #expect(matter.productID == 1)
        #expect(matter.commissioningFlow == 0)
        #expect(matter.discoveryCapabilities == 1)
        #expect(matter.discriminator == 128)
        #expect(matter.passcode == 2048)
    }

    @Test func concatenatedMatterCodesUseTheFirst() throws {
        let matter = try #require(MatterSetupPayload(qrCode: "MT:M5L90MP500K64J00000*M5L90U.D010K4J00000"))
        #expect(matter.passcode == 2048)
    }

    @Test func matterManualCodeMatchesTheSpecExample() {
        // Passcode 20202021 with discriminator 3840 is the spec's 34970112332.
        #expect(MatterSetupPayload.manualCode(discriminator: 3840, passcode: 20202021) == "34970112332")
        #expect(Verhoeff.checkDigit(for: "236") == 3)
    }

    @Test func rejectsBrokenMatterCodes() {
        #expect(MatterSetupPayload(qrCode: "MT:") == nil)
        #expect(MatterSetupPayload(qrCode: "MT:M5L") == nil)
        #expect(MatterSetupPayload(qrCode: "MT:!!!!!!!!!!!!!!!!!!!") == nil)
    }

    @Test func decodesHomeKitSetupURI() {
        // Setup code 031-45-154, category 5 (light), Wi-Fi flag, setup ID HOME.
        let value: UInt64 = 3_145_154 | (1 << 28) | (5 << 31)
        let encoded = String(value, radix: 36).uppercased()
        let uri = "X-HM://" + String(repeating: "0", count: 9 - encoded.count) + encoded + "HOME"
        guard case .homeKit(let homeKit) = QRPayload.parse(uri) else {
            Issue.record("Expected HomeKit")
            return
        }
        #expect(homeKit.setupCode == "03145154")
        #expect(homeKit.formattedCode == "031-45-154")
        #expect(homeKit.category == 5)
        #expect(homeKit.categoryName == "Light")
        #expect(homeKit.setupID == "HOME")
        #expect(QRScanResult.samples.contains(uri))
    }

    @Test func linksAndPlainText() {
        #expect(QRPayload.parse("https://www.home-assistant.io/integrations/mjpeg") == .url(URL(string: "https://www.home-assistant.io/integrations/mjpeg")!))
        #expect(QRPayload.parse("javascript:alert(1)") == .text("javascript:alert(1)"))
        #expect(QRPayload.parse("  just some words ") == .text("just some words"))
    }
}
