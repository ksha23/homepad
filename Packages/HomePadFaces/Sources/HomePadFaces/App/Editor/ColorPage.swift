import HomePadCore
import HomePadUI
import SwiftUI

/// The Color page of a face that lets people color more than its background:
/// a row of swatches for each part (Background, Text, Accent), so the whole
/// combination shows at once under the preview, which follows every tap.
///
/// Text and Accent start with Automatic, the colors designed with the
/// background. Text colors too close to the background to read are dimmed and
/// cannot be picked, and accent swatches show the shade the face draws on the
/// chosen background (`FaceColorChoice`).
struct ColorPage: View {
    let option: FaceOption
    let backgrounds: [FaceColor]
    let roles: FaceColorRoles
    @Binding var face: FaceConfiguration

    /// The ID of the Automatic swatch in the Text and Accent rows.
    private static let automatic = "automatic"

    var body: some View {
        let choice = face.colors(option)
        let preset = choice.background.preset
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            SwatchRow(title: "Background", value: choice.background.title, selection: choice.background.rawValue) {
                ForEach(backgrounds) { background in
                    ColorSwatch(title: background.title, fill: background.swatch,
                                isSelected: background == choice.background) {
                        face.values[option.id] = background.rawValue
                    }
                    .id(background.rawValue)
                }
            }
            if roles.contains(.text) {
                SwatchRow(title: "Text", value: choice.effectiveText?.title ?? "Automatic",
                          selection: choice.effectiveText?.rawValue ?? Self.automatic) {
                    ColorSwatch(title: "Automatic", fill: choice.background.swatch, dot: preset.ink.color,
                                isSelected: choice.effectiveText == nil) {
                        face.values[FaceColorChoice.textKey] = nil
                    }
                    .id(Self.automatic)
                    ForEach(FaceTextColor.allCases) { text in
                        ColorSwatch(title: text.title, fill: text.rgb.color, isSelected: text == choice.effectiveText,
                                    isAvailable: FaceColorChoice.isReadable(text, on: choice.background)) {
                            face.values[FaceColorChoice.textKey] = text.rawValue
                        }
                        .id(text.rawValue)
                    }
                }
            }
            if roles.contains(.accent) {
                SwatchRow(title: "Accent", value: choice.accent?.title ?? "Automatic",
                          selection: choice.accent?.id ?? Self.automatic) {
                    let fillsTiles = roles.contains(.accentFillsTiles)
                    ColorSwatch(title: "Automatic", fill: choice.background.swatch,
                                dot: (fillsTiles ? preset.tile : preset.accent).color,
                                isSelected: choice.accent == nil) {
                        face.values[FaceColorChoice.accentKey] = nil
                    }
                    .id(Self.automatic)
                    ForEach(FaceAccent.all) { accent in
                        let shown = fillsTiles ? accent.rgb : FaceColorChoice.shade(of: accent, on: choice.background)
                        ColorSwatch(title: accent.title, fill: shown.color,
                                    isSelected: accent == choice.accent) {
                            face.values[FaceColorChoice.accentKey] = accent.id
                        }
                        .id(accent.id)
                    }
                }
            }
            Text(roles.contains(.accent) && !roles.contains(.accentFillsTiles)
                 ? "Text colors too close to the background are dimmed. Accents deepen or lighten to stay readable."
                 : "Text colors too close to the background are dimmed.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .animation(Theme.Motion.standard, value: choice)
        .sensoryFeedback(.selection, trigger: choice)
    }
}

/// One part's row: its name and current color, then its swatches. The row
/// scrolls when the swatches do not fit, starting at the chosen one.
private struct SwatchRow<Swatches: View>: View {
    let title: String
    let value: String
    /// The ID of the chosen swatch, to scroll it into view.
    let selection: String
    @ViewBuilder let swatches: Swatches

    var body: some View {
        HStack(spacing: Theme.Spacing.m) {
            VStack(alignment: .leading, spacing: 0) {
                Text(title).font(.headline)
                Text(value).font(.subheadline).foregroundStyle(.secondary)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .frame(width: EditorMetrics.colorLabelWidth, alignment: .leading)
            .accessibilityElement(children: .combine)
            ScrollViewReader { proxy in
                ScrollView(.horizontal) {
                    HStack(spacing: 0) { swatches }
                }
                .scrollIndicators(.hidden)
                .onAppear { proxy.scrollTo(selection, anchor: .center) }
            }
        }
        .frame(height: EditorMetrics.swatchRowHeight)
    }
}

/// A round swatch with a ring in the text color when chosen, drawn like
/// `PaletteSwatchPicker`'s. Automatic shows the background with a dot of the
/// color designed with it. A swatch that cannot be picked keeps its outline
/// but fades its color and is struck through, so it stays findable on the
/// editor's page, dark or light.
private struct ColorSwatch<Fill: ShapeStyle>: View {
    let title: String
    let fill: Fill
    var dot: Color?
    let isSelected: Bool
    var isAvailable = true
    let action: () -> Void

    private let size = EditorMetrics.swatchSize
    private let ring = EditorMetrics.swatchRing

    var body: some View {
        Button(action: action) {
            Circle()
                .fill(fill)
                .overlay {
                    if let dot { Circle().fill(dot).padding(size * 0.28) }
                }
                .opacity(isAvailable ? 1 : 0.3)
                .overlay { Circle().strokeBorder(.primary.opacity(isAvailable ? 0.3 : 0.45)) }
                .overlay {
                    if !isAvailable {
                        Capsule().fill(.primary.opacity(0.7)).frame(width: 2).rotationEffect(.degrees(45))
                    }
                }
                .frame(width: size, height: size)
                .overlay {
                    Circle().strokeBorder(.primary, lineWidth: 3).padding(-ring).opacity(isSelected ? 1 : 0)
                }
                .padding(ring)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!isAvailable)
        .accessibilityLabel(title)
        .accessibilityHint(isAvailable ? "" : "Too close to the background to read")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
