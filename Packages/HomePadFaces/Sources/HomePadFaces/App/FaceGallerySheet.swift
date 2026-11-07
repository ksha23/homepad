import HomePadCore
import HomePadUI
import SwiftUI

/// Every face kind with a thumbnail in its default look, like the
/// Watch app's Face Gallery. Picking one adds it to My Faces.
struct FaceGallerySheet: View {
    let onPick: (String) -> Void

    @Environment(ModuleRegistry.self) private var registry

    /// Made as the sheet is presented, so the frame rate covers building the gallery.
    init(onPick: @escaping (String) -> Void) {
        self.onPick = onPick
        FacesPerfTrace.moment("gallery")
    }

    var body: some View {
        SheetScreen("Face Gallery") {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 240), spacing: Theme.Spacing.l)], spacing: Theme.Spacing.xl) {
                    ForEach(registry.faces) { face in
                        Button { onPick(face.id) } label: {
                            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                                FaceThumbnail(faceID: face.id)
                                Label(face.title, systemImage: face.systemImage).font(.headline)
                                Text(FaceCatalog.definition(face.id)?.summary ?? "")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2, reservesSpace: true)
                                    .multilineTextAlignment(.leading)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(Theme.Spacing.l)
            }
            .facesScrollTrace("gallery")
        }
    }
}
