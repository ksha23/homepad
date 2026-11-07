import HomePadUI
import SwiftUI
import UIKit
import Vision

/// Reads QR codes and explains them: Wi-Fi details, links, and Matter or
/// HomeKit setup codes. Display only.
struct QRScannerView: View {
    @Environment(CameraLab.self) private var lab
    @State private var results: [QRScanResult] = []
    @State private var message: String?

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.l) {
            VStack(spacing: Theme.Spacing.m) {
                if lab.capabilities.supportsLiveScanner {
                    QRLiveScanner(onPayload: add)
                } else {
                    GlassTile {
                        EmptyStateView(
                            "Live Scanner Unavailable",
                            message: "Choose a photo of a QR code, paste a code, or try a sample.",
                            systemImage: "qrcode.viewfinder"
                        )
                    }
                }
                HStack(spacing: Theme.Spacing.m) {
                    PhotoPickerButton(title: "Choose Photo", onImage: detect)
                    Button("Paste", systemImage: "doc.on.clipboard") {
                        if let text = UIPasteboard.general.string { add(text) }
                    }
                    .buttonStyle(.glass)
                    Menu {
                        ForEach(QRScanResult.samples, id: \.self) { sample in
                            Button(QRScanResult(raw: sample).title) { add(sample) }
                        }
                    } label: {
                        Label("Samples", systemImage: "sparkles")
                    }
                    .buttonStyle(.glass)
                }
                .controlSize(.large)
                if let message { Text(message).foregroundStyle(.secondary) }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            ScrollView {
                VStack(spacing: Theme.Spacing.m) {
                    if results.isEmpty {
                        Text("Scanned codes appear here.")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, minHeight: 200)
                    }
                    ForEach(results) { QRResultCard(result: $0) }
                }
            }
            .scrollIndicators(.hidden)
            .frame(width: 460)
        }
        .padding([.horizontal, .bottom], Theme.Spacing.l)
        .animation(.smooth, value: results)
    }

    private func add(_ raw: String) {
        message = nil
        results.removeAll { $0.raw == raw }
        results.insert(QRScanResult(raw: raw), at: 0)
    }

    private func detect(in image: UIImage) {
        guard let cgImage = image.cgImage else { return }
        Task {
            var request = DetectBarcodesRequest()
            request.symbologies = [.qr]
            let payloads = (try? await request.perform(on: cgImage))?.compactMap(\.payloadString) ?? []
            if payloads.isEmpty { message = "No QR code found in that photo." }
            payloads.forEach(add)
        }
    }
}

/// The live QR scanner, holding the camera while visible.
private struct QRLiveScanner: View {
    let onPayload: (String) -> Void
    @State private var access: CameraBroker.Access?

    var body: some View {
        Group {
            switch access {
            case .granted:
                LiveScannerView(recognizes: [.barcode(symbologies: [.qr])]) { item in
                    if case .barcode(let payload) = item { onPayload(payload) }
                }
            case .denied(let reason):
                GlassTile { EmptyStateView("Camera Busy", message: reason, systemImage: "video.slash") }
            case nil:
                Color.clear
            }
        }
        .holdsCamera("cameralab.qr", title: "QR Scanner", usesSystemCapture: true, access: $access)
    }
}

/// One scanned code.
struct QRScanResult: Identifiable, Equatable {
    let raw: String
    let payload: QRPayload
    var id: String { raw }

    init(raw: String) {
        self.raw = raw
        payload = QRPayload.parse(raw)
    }

    var title: String {
        switch payload {
        case .wifi(let network): "Wi-Fi: \(network.ssid)"
        case .url(let url): url.host ?? "Link"
        case .matter: "Matter Accessory"
        case .homeKit(let homeKit): "HomeKit \(homeKit.categoryName)"
        case .text: "Text"
        }
    }

    /// Example codes for trying the scanner without a camera.
    static let samples = [
        "WIFI:T:WPA;S:HomePad Guest;P:fresh-basil-42;;",
        "MT:M5L90MP500K64J00000",
        "X-HM://00522H1VMHOME",
        "https://www.home-assistant.io",
    ]
}
