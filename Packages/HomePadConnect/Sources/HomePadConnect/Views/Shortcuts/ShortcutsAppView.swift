import HomePadCore
import HomePadUI
import SwiftUI

/// The Shortcuts app: big tiles that run the household's favorite Apple Shortcuts.
struct ShortcutsAppView: View {
    @Environment(ConnectRuntime.self) private var connect
    @State private var isAdding = false
    @State private var newName = ""
    @State private var isEditing = false

    private var launcher: ShortcutsLauncher { connect.shortcuts }

    var body: some View {
        AppScreen("Shortcuts", accessory: accessory) {
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                if let error = launcher.lastError {
                    Label(error, systemImage: "exclamationmark.triangle.fill").font(.title3).foregroundStyle(.orange)
                }
                if launcher.names.isEmpty {
                    EmptyStateView(
                        "Add Your Shortcuts",
                        message: "Add a shortcut by its name in the Shortcuts app, for example Leaving Home. Tap a tile to run it.",
                        systemImage: "square.2.layers.3d",
                        actionTitle: "Add Shortcut"
                    ) { isAdding = true }
                } else {
                    grid
                }
            }
        }
        .alert("Add Shortcut", isPresented: $isAdding) {
            TextField("Name in the Shortcuts app", text: $newName)
            Button("Add") {
                launcher.add(newName)
                newName = ""
            }
            Button("Cancel", role: .cancel) { newName = "" }
        } message: {
            Text("Type the name exactly as it appears in the Shortcuts app.")
        }
    }

    private var grid: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: Theme.Spacing.m)], spacing: Theme.Spacing.m) {
                ForEach(Array(launcher.names.enumerated()), id: \.element) { index, name in
                    Button {
                        if !isEditing { Task { await launcher.run(name) } }
                    } label: {
                        GlassTile(tint: tint(index)) {
                            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                                Image(systemName: "square.2.layers.3d.fill")
                                    .font(.system(size: 36, weight: .semibold))
                                    .foregroundStyle(tint(index))
                                Spacer(minLength: 0)
                                Text(name).font(.title2.bold()).lineLimit(2)
                            }
                        }
                        .frame(height: 150)
                        .overlay(alignment: .topLeading) {
                            if isEditing {
                                RemoveBadge("Remove \(name)") { launcher.remove(name) }
                                    .offset(x: -10, y: -10)
                            }
                        }
                        .jiggle(isEditing)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button("Remove", systemImage: "trash", role: .destructive) { launcher.remove(name) }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func accessory() -> some View {
        if !launcher.names.isEmpty {
            GlassCapsuleButton(isEditing ? "Done" : "Edit", isProminent: isEditing) { isEditing.toggle() }
        }
        GlassIconButton("plus", label: "Add Shortcut") { isAdding = true }
    }

    /// Cycles the same fixed palette as Board notes so tiles feel like one family.
    private func tint(_ index: Int) -> Color {
        let palette = NoteColor.allCases
        return palette[index % palette.count].color
    }
}
