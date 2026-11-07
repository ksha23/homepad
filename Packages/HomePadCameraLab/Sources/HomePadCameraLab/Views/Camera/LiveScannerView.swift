import HomePadUI
import SwiftUI
import VisionKit

/// What the live scanner found.
enum ScannedItem: Equatable {
    case barcode(payload: String)
    case text(String)
}

/// VisionKit's `DataScannerViewController` (Live Text) in HomePad chrome:
/// rounded corners, a "Scanning" badge, and HomePad overlays on top.
/// Barcodes are reported as they appear. Text is reported when tapped. Like
/// `CameraViewport`, it stays dark in Light, overlays included.
struct LiveScannerView<Overlay: View>: View {
    let recognizes: Set<DataScannerViewController.RecognizedDataType>
    let onItem: (ScannedItem) -> Void
    private let overlay: Overlay

    init(recognizes: Set<DataScannerViewController.RecognizedDataType>, onItem: @escaping (ScannedItem) -> Void,
         @ViewBuilder overlay: () -> Overlay = { EmptyView() }) {
        self.recognizes = recognizes
        self.onItem = onItem
        self.overlay = overlay()
    }

    var body: some View {
        DataScannerRepresentable(recognizes: recognizes, onItem: onItem)
            .overlay(alignment: .topLeading) {
                StatusBadge("Scanning", color: .green)
                    .padding(Theme.Spacing.m)
            }
            .overlay { overlay }
            .environment(\.colorScheme, .dark)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.tile, style: .continuous))
            .nightModeAware()
    }
}

private struct DataScannerRepresentable: UIViewControllerRepresentable {
    let recognizes: Set<DataScannerViewController.RecognizedDataType>
    let onItem: (ScannedItem) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: recognizes, qualityLevel: .balanced, recognizesMultipleItems: true,
            isHighFrameRateTrackingEnabled: false, isPinchToZoomEnabled: true, isGuidanceEnabled: true,
            isHighlightingEnabled: true
        )
        scanner.delegate = context.coordinator
        scanner.overrideUserInterfaceStyle = .dark
        return scanner
    }

    func updateUIViewController(_ scanner: DataScannerViewController, context: Context) {
        context.coordinator.onItem = onItem
        if !scanner.isScanning, DataScannerViewController.isAvailable {
            try? scanner.startScanning()
        }
    }

    static func dismantleUIViewController(_ scanner: DataScannerViewController, coordinator: Coordinator) {
        scanner.stopScanning()
    }

    func makeCoordinator() -> Coordinator { Coordinator(onItem: onItem) }

    @MainActor
    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        var onItem: (ScannedItem) -> Void

        init(onItem: @escaping (ScannedItem) -> Void) {
            self.onItem = onItem
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            for item in addedItems {
                if case .barcode(let barcode) = item, let payload = barcode.payloadStringValue {
                    onItem(.barcode(payload: payload))
                }
            }
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didTapOn item: RecognizedItem) {
            switch item {
            case .text(let text): onItem(.text(text.transcript))
            case .barcode(let barcode): barcode.payloadStringValue.map { onItem(.barcode(payload: $0)) }
            @unknown default: break
            }
        }
    }
}
