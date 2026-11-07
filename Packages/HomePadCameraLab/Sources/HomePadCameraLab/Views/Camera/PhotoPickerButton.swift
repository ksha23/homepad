import HomePadCore
import PhotosUI
import SwiftUI
import UIKit

/// A glass button that opens the system photo picker and hands back the chosen
/// image. Tools offer it next to the camera, and in the simulator it stands in
/// for the camera. The picker runs out of process, so no photo permission is needed.
///
/// The picker browses the iPad's whole library, so the button shows only while
/// the library's owner is recognized (`PhotoAccessPolicy`).
struct PhotoPickerButton: View {
    let title: String
    var prominent = false
    let onImage: (UIImage) -> Void

    @Environment(AppServices.self) private var services
    @State private var selection: PhotosPickerItem?

    var body: some View {
        if services.photoAccess.allowsLibrary {
            picker
        }
    }

    private var picker: some View {
        PhotosPicker(selection: $selection, matching: .images, preferredItemEncoding: .compatible) {
            Label(title, systemImage: "photo.on.rectangle")
        }
        .glassButtonStyle(isProminent: prominent)
        .onChange(of: selection) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                    onImage(image)
                }
                selection = nil
            }
        }
    }
}
