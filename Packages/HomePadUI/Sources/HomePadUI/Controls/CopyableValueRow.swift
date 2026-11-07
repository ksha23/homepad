#if os(iOS)
import SwiftUI
import UIKit

/// A label over a monospaced value with a copy button, for setup values
/// someone types into another app (a stream URL, a Wi-Fi password).
/// `displayValue` can mask a secret while the copy button still copies
/// the real value.
///
///     CopyableValueRow(label: "Password", value: password, displayValue: "••••••••")
public struct CopyableValueRow: View {
    private let label: String
    private let value: String
    private let displayValue: String?
    @State private var copied = false

    /// - Parameters:
    ///   - label: What the value is.
    ///   - value: The text the copy button puts on the pasteboard.
    ///   - displayValue: What to show instead of `value`, for example a masked secret.
    public init(label: String, value: String, displayValue: String? = nil) {
        self.label = label
        self.value = value
        self.displayValue = displayValue
    }

    public var body: some View {
        HStack(alignment: .center, spacing: Theme.Spacing.m) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(displayValue ?? value)
                    .font(.body.monospaced())
                    .textSelection(.enabled)
                    .lineLimit(3)
                    .minimumScaleFactor(0.7)
            }
            Spacer(minLength: 0)
            GlassIconButton(copied ? "checkmark" : "doc.on.doc", label: "Copy \(label)", size: Theme.Size.minTapTarget) {
                UIPasteboard.general.string = value
                copied = true
                Task {
                    try? await Task.sleep(for: .seconds(1.5))
                    copied = false
                }
            }
        }
    }
}
#endif
