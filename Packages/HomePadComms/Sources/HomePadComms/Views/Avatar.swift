import SwiftUI

/// A round contact picture: initials, a person for numbers and addresses, or a group icon.
struct Avatar: View {
    let title: String
    let isGroup: Bool
    var size: CGFloat = 44
    /// A phone number or email whose Contacts picture to show, when there is one.
    var handle: String?
    @Environment(CommsRuntime.self) private var runtime
    @State private var picture: UIImage?

    var body: some View {
        ZStack {
            if let picture = picture ?? handle.flatMap({ runtime.store.attachments?.cachedContactPhoto($0) }) {
                Image(uiImage: picture).resizable().scaledToFill()
            } else {
                Circle().fill(LinearGradient(colors: [Color(red: 0.62, green: 0.66, blue: 0.74), Color(red: 0.45, green: 0.49, blue: 0.58)], startPoint: .top, endPoint: .bottom))
                if isGroup {
                    Image(systemName: "person.2.fill").foregroundStyle(.white)
                } else if let initials {
                    Text(initials).font(.headline).foregroundStyle(.white)
                } else {
                    Image(systemName: "person.fill").foregroundStyle(.white)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .task(id: handle) {
            guard let handle else { return }
            picture = await runtime.store.attachments?.contactPhoto(handle)
        }
    }

    /// Up to two initials from a name. Nil for numbers and addresses, which get a person icon.
    private var initials: String? {
        guard !title.contains("@"), !title.contains(where: \.isNumber) else { return nil }
        let letters = title.split(separator: " ").prefix(2).compactMap { $0.first }.filter { $0.isLetter }
        return letters.isEmpty ? nil : String(letters).uppercased()
    }
}
