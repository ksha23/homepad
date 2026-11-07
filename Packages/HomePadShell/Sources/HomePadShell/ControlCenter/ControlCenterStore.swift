import HomePadCore

/// Reads and writes the household's Control Center layout.
@MainActor
struct ControlCenterStore {
    let settings: SettingsStore
    let registry: ModuleRegistry

    /// Every tile that could show, in default order: built-ins, module tiles,
    /// then the trailing built-ins (so the grid packs without gaps).
    var availableIDs: [String] {
        let leading = BuiltInControl.allCases.filter { !$0.isTrailing }.map(\.rawValue)
        let trailing = BuiltInControl.allCases.filter(\.isTrailing).map(\.rawValue)
        return leading + registry.controls.map(\.id) + trailing
    }

    /// Visible tiles in order, skipping module tiles whose module is not loaded.
    var visibleIDs: [String] {
        let available = Set(availableIDs)
        return layout().tileIDs.filter(available.contains)
    }

    /// Tiles the user removed, for the gallery.
    var hiddenIDs: [String] {
        let visible = Set(layout().tileIDs)
        return availableIDs.filter { !visible.contains($0) }
    }

    func layout() -> ControlCenterLayout {
        let stored = settings[ShellSettings.controlCenterLayout] ?? .makeDefault(availableIDs: availableIDs)
        return stored.reconciled(withAvailableIDs: availableIDs)
    }

    func update(_ change: (inout ControlCenterLayout) -> Void) {
        var layout = layout()
        change(&layout)
        settings[ShellSettings.controlCenterLayout] = layout
    }

    func title(for id: String) -> String {
        BuiltInControl(rawValue: id)?.title ?? registry.controls.first { $0.id == id }?.title ?? id
    }

    func systemImage(for id: String) -> String {
        BuiltInControl(rawValue: id)?.systemImage ?? descriptor(id)?.systemImage ?? "square.grid.2x2.fill"
    }

    func span(for id: String) -> GridSpan {
        if let builtIn = BuiltInControl(rawValue: id) { return builtIn.span }
        guard let size = descriptor(id)?.size else { return BuiltInControl.moduleTileSpan }
        return GridSpan(columns: size.columns, rows: size.rows)
    }

    private func descriptor(_ id: String) -> ControlDescriptor? {
        registry.controls.first { $0.id == id }
    }
}
