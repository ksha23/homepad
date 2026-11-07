import HomePadCore
import HomePadUI
import SwiftUI

/// One saved face in My Faces: a thumbnail that shows the face when
/// tapped, its name and choices (a checkmark beside the name of the face
/// showing now, under the card so it never covers the face), and a Customize
/// button that opens the editor.
///
/// The card does not jiggle. Jiggling means "drag to rearrange", My Faces has
/// no order to change, and it redrew every live face thumbnail 60 times a second.
struct SavedFaceCard: View {
    let face: FaceConfiguration
    let isCurrent: Bool
    let onShow: () -> Void
    let onCustomize: () -> Void

    @Environment(ModuleRegistry.self) private var registry

    var body: some View {
        let definition = FaceCatalog.definition(face.faceID)
        let title = definition?.title ?? registry.face(face.faceID)?.title ?? "Face"
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Button(action: onShow) {
                // Drawn up close, so the card shows everything the face was set
                // up with: widgets and events only appear near the iPad.
                // `-HomePadFacesWidgets` shows on the cards too, in debug builds.
                FaceThumbnail(faceID: face.faceID, configuration: FaceDebugOptions.withWidgetOverride(face), proximity: .near)
                    .overlay {
                        RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                            .strokeBorder(isCurrent ? Color.accentColor : .primary.opacity(0.15), lineWidth: isCurrent ? 3 : 1)
                    }
                    // The live face ignores touches, so the button needs a shape of its own to tap.
                    .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(title)
            .accessibilityValue(isCurrent ? "Showing now" : "")
            .accessibilityHint(isCurrent ? "" : "Shows this face")
            HStack(spacing: Theme.Spacing.s) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: Theme.Spacing.s) {
                        Text(title).font(.headline).lineLimit(1)
                        if isCurrent {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.headline)
                                .foregroundStyle(.tint)
                                .accessibilityHidden(true)
                                .transition(.opacity)
                        }
                    }
                    Text(definition?.caption(for: face) ?? "")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: Theme.Spacing.s)
                GlassIconButton("slider.horizontal.3", label: "Customize \(title)", size: Theme.Size.minTapTarget, action: onCustomize)
            }
        }
    }
}

/// Chooses whose faces to show and edit: the household, or one member.
struct OwnerPicker: View {
    @Binding var owner: FaceOwner
    @Environment(AppServices.self) private var services

    var body: some View {
        HeaderPicker("Faces For", selection: $owner, title: title, systemImage: "person.crop.circle") {
            Label("Everyone", systemImage: "house.fill").tag(FaceOwner.household)
            ForEach(services.household.members) { member in
                Text("\(member.avatar) \(member.name)").tag(FaceOwner.member(member.id))
            }
        }
    }

    private var title: String {
        switch owner {
        case .household: "Everyone"
        case .member(let id): services.household.members.first { $0.id == id }?.name ?? "Member"
        }
    }
}
