import SwiftUI

/// A settings row with the label on the left and a compact segmented
/// control on the right, for a few curated choices (Low, Medium, High).
///
///     LabeledSegmentedPicker("Sensitivity", selection: $level, options: Level.allCases) { $0.title }
public struct LabeledSegmentedPicker<Value: Hashable & Identifiable>: View {
    private let title: String
    @Binding private var selection: Value
    private let options: [Value]
    private let optionTitle: (Value) -> String

    /// - Parameters:
    ///   - title: The row's label.
    ///   - selection: The chosen option.
    ///   - options: Two to four options, in order.
    ///   - optionTitle: The short title of an option.
    public init(_ title: String, selection: Binding<Value>, options: [Value], optionTitle: @escaping (Value) -> String) {
        self.title = title
        self._selection = selection
        self.options = options
        self.optionTitle = optionTitle
    }

    public var body: some View {
        LabeledContent(title) {
            Picker(title, selection: $selection) {
                ForEach(options) { Text(optionTitle($0)).tag($0) }
            }
            .pickerStyle(.segmented)
            // Large: 46 points tall instead of the default 32.
            .controlSize(.large)
            .labelsHidden()
            .frame(maxWidth: 360)
        }
    }
}
