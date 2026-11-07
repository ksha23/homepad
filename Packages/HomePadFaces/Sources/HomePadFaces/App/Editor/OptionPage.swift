import HomePadCore
import HomePadUI
import SwiftUI

/// The controls for one editor page. Choices that change the face's look show
/// a small picture of the face with that choice applied, colors show swatches
/// (a row per part when the face colors more than its background, `ColorPage`),
/// slots show what is in them, and custom pages draw themselves.
struct OptionPage: View {
    let option: FaceOption
    @Binding var face: FaceConfiguration
    /// The screen the preview is laid out on, so the cards match it.
    let screen: CGSize
    /// The distance the preview shows, so the cards show the same.
    let proximity: ProximityLevel

    var body: some View {
        switch option.kind {
        case .choices(let choices):
            choiceCarousel(choices)
        case .colors(let colors, let roles) where roles.isEmpty:
            OptionCarousel(items: colors, selection: selection, cardWidth: 150) { color, isSelected in
                OptionCard(title: color.title, isSelected: isSelected) {
                    Circle().fill(color.swatch).overlay(Circle().strokeBorder(.primary.opacity(0.3)))
                }
            }
        case .colors(let colors, let roles):
            ColorPage(option: option, backgrounds: colors, roles: roles, face: $face)
        case .slots(let slots, let gallery):
            SlotsPage(slots: slots, gallery: gallery, note: option.note, face: $face)
        case .custom(let makeView):
            makeView($face)
        case .widgetGrid:
            // The editor draws the widgets page itself, with the preview (`WidgetsPage`).
            EmptyView()
        }
    }

    @ViewBuilder
    private func choiceCarousel(_ choices: [FaceChoice]) -> some View {
        switch option.cardStyle {
        case .faceThumbnail:
            let size = EditorMetrics.thumbnailSize(screen: screen)
            OptionCarousel(items: choices, selection: selection, cardWidth: EditorMetrics.cardWidth(thumbnail: size)) { choice, isSelected in
                OptionCard(title: choice.title, isSelected: isSelected, iconSize: size) {
                    // Thumbnail cadence: drawn once a minute, with no motion.
                    FaceThumbnail(faceID: face.faceID, configuration: applying(choice), canvas: screen, proximity: proximity)
                        // The card reads as its title.
                        .accessibilityHidden(true)
                }
            }
        case .symbol:
            OptionCarousel(items: choices, selection: selection) { choice, isSelected in
                OptionCard(title: choice.title, isSelected: isSelected) {
                    Image(systemName: choice.systemImage ?? "circle.dashed").font(.largeTitle)
                }
            }
        }
    }

    /// The face as it is, with one choice changed.
    private func applying(_ choice: FaceChoice) -> FaceConfiguration {
        var configuration = face
        configuration.values[option.id] = choice.id
        return configuration
    }

    private var selection: Binding<String?> {
        Binding(get: { face.value(option) }, set: { if let value = $0 { face.values[option.id] = value } })
    }
}
