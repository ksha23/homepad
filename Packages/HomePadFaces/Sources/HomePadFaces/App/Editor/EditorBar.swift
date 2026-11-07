import HomePadCore
import HomePadUI
import SwiftUI

/// The row under the editor's preview: the pages (Style, Color, Widgets) and
/// how the preview shows the face: from across the room or up close, and on
/// the widgets page, in landscape or portrait. Side by side when the screen
/// is wide, stacked when it is tall, with the pickers right under the preview.
struct EditorBar: View {
    let pages: [FaceOption]
    @Binding var page: Int
    @Binding var distance: EditorDistance
    /// The orientation the widgets page arranges, or nil on other pages.
    var orientation: Binding<FaceGrid.Orientation>?
    let isWide: Bool

    var body: some View {
        if isWide {
            HStack(spacing: Theme.Spacing.l) {
                pagePicker
                Spacer(minLength: 0)
                previewPickers
            }
        } else {
            VStack(spacing: Theme.Spacing.s) {
                previewPickers
                pagePicker
            }
        }
    }

    private var previewPickers: some View {
        HStack(spacing: Theme.Spacing.s) {
            if let orientation {
                EditorSegmentedPicker(options: FaceGrid.Orientation.allCases, selection: orientation,
                                      label: "Arrange For", title: \.title)
            }
            EditorSegmentedPicker(options: EditorDistance.allCases, selection: $distance,
                                  label: "Preview Distance", title: \.title)
        }
    }

    @ViewBuilder
    private var pagePicker: some View {
        if pages.count > 1 {
            ChoiceChips(pages.indices.map { ChoiceChips.Choice(id: $0, title: pages[$0].title) },
                        selection: Binding(get: { page }, set: { picked in
                            withAnimation(Theme.Motion.standard) { page = picked }
                        }))
                .fixedSize(horizontal: !isWide, vertical: false)
                .accessibilityLabel("Page")
        }
    }
}

/// A small choice of how the preview shows the face, such as Across the
/// Room or Up Close.
///
/// Drawn like a segmented control, but each option is as wide as its own
/// title plus the same padding. A system segmented control makes every
/// segment as wide as the longest title, so "Across the Room" filled its
/// segment while "Up Close" sat in a wide one.
struct EditorSegmentedPicker<Option: Hashable>: View {
    let options: [Option]
    @Binding var selection: Option
    /// What VoiceOver calls the choice.
    let label: String
    let title: (Option) -> String
    @Namespace private var selected

    /// The gap between the track and the selected option.
    private static var inset: CGFloat { 4 }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options, id: \.self) { option in
                Button {
                    selection = option
                } label: {
                    Text(title(option))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(option == selection ? .primary : .secondary)
                        .padding(.horizontal, Theme.Spacing.l)
                        .frame(maxHeight: .infinity)
                        .background {
                            if option == selection {
                                Capsule()
                                    .fill(.primary.opacity(0.2))
                                    .matchedGeometryEffect(id: "selected", in: selected)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(Self.inset)
        .frame(height: Theme.Size.toolbarItem)
        .glassEffect(.regular, in: Capsule())
        .fixedSize()
        .animation(Theme.Motion.standard, value: selection)
        .accessibilityRepresentation {
            Picker(label, selection: $selection) {
                ForEach(options, id: \.self) { option in
                    Text(title(option)).tag(option)
                }
            }
            .pickerStyle(.segmented)
        }
    }
}
