import HomePadCore
import HomePadUI
import SwiftUI

/// The Faces page in Settings: which face shows now, the saved faces with
/// their editor, a face for each person, Smart Rotation rules, photo access
/// and which calendars count as shared.
struct FacesSettingsPane: View {
    @Environment(FacesRuntime.self) private var runtime
    @Environment(AppServices.self) private var services
    @Environment(ModuleRegistry.self) private var registry
    @State private var editing: EditorTarget?
    @State private var photoAccess = PhotoLibrarySource.access

    var body: some View {
        let library = runtime.library
        let household = library.list(for: .household)
        Form {
            Section {
                Picker("Showing Now", selection: currentBinding(.household)) {
                    ForEach(household.faces) { face in Text(title(face)).tag(face.id) }
                }
                ForEach(household.faces) { face in
                    Button { editing = EditorTarget(face: face, owner: .household) } label: {
                        LabeledContent(title(face), value: FaceCatalog.definition(face.faceID)?.caption(for: face) ?? "")
                    }
                    .foregroundStyle(.primary)
                }
            } header: {
                Text("My Faces")
            } footer: {
                Text("Open the Faces app to add and remove faces. Swipe across a face to switch between them.")
            }
            if !services.household.members.isEmpty {
                Section("Each Person") {
                    ForEach(services.household.members) { member in
                        Picker("\(member.avatar) \(member.name)", selection: currentBinding(.member(member.id))) {
                            ForEach(library.list(for: .member(member.id)).faces) { face in Text(title(face)).tag(face.id) }
                        }
                    }
                }
            }
            Section {
                NavigationLink {
                    // Pushed onto Settings' stack, which does not carry this pane's environment.
                    RotationRulesEditor().navigationTitle("Smart Rotation").environment(runtime)
                } label: {
                    LabeledContent("Smart Rotation Rules", value: "\(runtime.rotation.current.rules.filter(\.isEnabled).count) on")
                }
            } footer: {
                Text("Smart Rotation shows the night face in a dark room, cameras when the doorbell rings, and more.")
            }
            Section {
                LabeledContent("Photos Access", value: accessText)
                if photoAccess == .notAsked {
                    Button("Allow Access to Photos") {
                        Task {
                            _ = await PhotoLibrarySource.requestAccess()
                            photoAccess = PhotoLibrarySource.access
                        }
                    }
                }
            } header: {
                Text("Photos")
            } footer: {
                Text("Choose favorites, a Shared Album or picked photos for each Photos face in its editor. Photos never leave this iPad.")
            }
            Section {
            } footer: {
                Text("Calendar events from calendars shared with everyone appear on faces for guests too. Choose which calendars are shared in Settings, Personal Info.")
            }
        }
        .sheet(item: $editing) { target in
            FaceEditorView(face: target.face, owner: target.owner)
                .presentationSizing(.page)
        }
    }

    private func currentBinding(_ owner: FaceOwner) -> Binding<UUID> {
        Binding(get: { runtime.library.current(for: owner).id }, set: { runtime.library.makeCurrent($0, for: owner) })
    }

    private func title(_ face: FaceConfiguration) -> String {
        FaceCatalog.definition(face.faceID)?.title ?? registry.face(face.faceID)?.title ?? face.faceID
    }

    private var accessText: String {
        switch photoAccess {
        case .allowed: "Full Access"
        case .limited: "Selected Photos"
        case .notAsked: "Not Asked Yet"
        case .denied: "Off"
        }
    }
}
