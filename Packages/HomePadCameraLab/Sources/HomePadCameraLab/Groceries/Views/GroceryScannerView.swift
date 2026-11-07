import HomePadUI
import SwiftUI
import VisionKit

/// Scan grocery barcodes (and tap printed words) into the Groceries list.
struct GroceryScannerView: View {
    @Environment(CameraLab.self) private var lab

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.l) {
            Group {
                if lab.capabilities.supportsLiveScanner {
                    GroceryLiveScanner()
                } else {
                    BarcodeEntryPanel()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            GroceryListPanel()
                .frame(width: 420)
        }
        .padding([.horizontal, .bottom], Theme.Spacing.l)
    }
}

/// The live barcode and text scanner, holding the camera while visible.
private struct GroceryLiveScanner: View {
    @Environment(CameraLab.self) private var lab
    @State private var access: CameraBroker.Access?

    var body: some View {
        Group {
            switch access {
            case .granted:
                LiveScannerView(
                    recognizes: [.barcode(symbologies: [.ean13, .ean8, .upce]), .text()],
                    onItem: handle
                ) {
                    VStack {
                        Spacer()
                        Text("Hold a barcode in view, or tap printed words to add them.")
                            .font(.title3.weight(.medium))
                            .padding(.horizontal, Theme.Spacing.l)
                            .padding(.vertical, Theme.Spacing.s)
                            .glassEffect(.regular, in: Capsule())
                            .padding(Theme.Spacing.l)
                    }
                }
            case .denied(let reason):
                GlassTile { EmptyStateView("Camera Busy", message: reason, systemImage: "video.slash") }
            case nil:
                Color.clear
            }
        }
        .holdsCamera("cameralab.groceries", title: "Grocery Scanner", usesSystemCapture: true, access: $access)
    }

    private func handle(_ item: ScannedItem) {
        switch item {
        case .barcode(let payload): lab.groceries.add(barcode: payload)
        case .text(let text): lab.groceries.add(text: text)
        }
    }
}

/// Without the live scanner (the simulator), type a barcode or try a sample.
private struct BarcodeEntryPanel: View {
    @Environment(CameraLab.self) private var lab
    @State private var barcode = ""
    @State private var sampleIndex = 0

    /// Real products, so the Open Food Facts lookup can be tried without a camera.
    private static let samples = ["3017624010701", "041196910759", "5449000000996"]

    var body: some View {
        GlassTile {
            VStack(spacing: Theme.Spacing.l) {
                EmptyStateView(
                    "Live Scanner Unavailable",
                    message: "This device cannot run the live barcode scanner. Type a barcode, or try a sample product.",
                    systemImage: "barcode.viewfinder"
                )
                .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: Theme.Spacing.m) {
                    TextField("Barcode digits", text: $barcode)
                        .keyboardType(.numberPad)
                        .font(.title3.monospaced())
                        .padding(Theme.Spacing.m)
                        .glassEffect(.regular, in: Capsule())
                        .onSubmit(lookUp)
                    Button("Look Up", action: lookUp)
                        .buttonStyle(.glassProminent)
                        .disabled(!Barcode.isPlausibleGTIN(barcode))
                }
                Button("Try a Sample Product") {
                    lab.groceries.add(barcode: Self.samples[sampleIndex % Self.samples.count])
                    sampleIndex += 1
                }
                .buttonStyle(.glass)
            }
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func lookUp() {
        guard Barcode.isPlausibleGTIN(barcode) else { return }
        lab.groceries.add(barcode: barcode)
        barcode = ""
    }
}
