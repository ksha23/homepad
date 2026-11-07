import HomePadCore
import HomePadUI
import SwiftUI

/// Sheets the Home Screen presents while editing.
enum HomeScreenSheet: String, Identifiable {
    /// `addItems` is the widget gallery (its name predates Add App).
    case addItems, addApps, wallpaper
    var id: String { rawValue }
}

/// The active member's Home Screen: greeting, date and time, avatar, and pages
/// of apps and widgets on their wallpaper. Long-press enters edit mode
/// (jiggle) to remove, reorder and resize, add widgets from the gallery, and
/// pick a wallpaper. Each member's layout is saved separately.
///
/// The wallpaper is drawn here. Everything on it is `HomeScreenContent`, in a host
/// of its own that sits back while an app is open (`HomeScreenHost`).
struct HomeScreenView: View {
    @Environment(Household.self) private var household
    @Environment(ShellNavigator.self) private var navigator
    @Environment(SettingsStore.self) private var settings
    @Environment(WallpaperPhotoStore.self) private var photos
    private let initialPage: Int

    /// - Parameter initialPage: The page to start on, so returning from an app lands
    ///   on the same page without scrolling there (scrolling after the screen's
    ///   own transition made the icons shake).
    init(initialPage: Int = 0) {
        self.initialPage = initialPage
    }

    var body: some View {
        let memberID = household.activeMemberID
        let wallpaper = settings[ShellSettings.wallpaper(for: memberID)]
        ZStack {
            HomeWallpaperView(memberID: memberID, accent: Self.accent(of: household))
                .nightModeAware()
            // Sits back while an app is open over it. The wallpaper stays put. The page on screen and the
            // edit state live inside, so using the Home Screen never rebuilds its host.
            HomeScreenHost(receded: navigator.screen.appID != nil) {
                HomeScreenContent(initialPage: initialPage)
            }
        }
        // Laid out from the screen's edges with its own margins, so it takes no safe area.
        .ignoresSafeArea()
        // A photo wallpaper's tone is measured once, off the main thread.
        .task(id: PhotoToneKey(memberID: memberID, revision: photos.revision, isPhoto: wallpaper == .photo)) {
            if wallpaper == .photo { await photos.measureTone(for: memberID) }
        }
    }

    /// The member's color, or the first swatch for a guest.
    static func accent(of household: Household) -> Color {
        household.activeMember.map { Color(hex: $0.colorHex) } ?? Theme.Palette.swatches[0].color
    }

    /// Space from every screen edge to the Home Screen's content: the shell's side
    /// margin plus the screen padding, the same distance the grid has at the sides.
    static let edgeMargin = Theme.Spacing.screenContent.leading
}

/// The Home Screen's header and pages of apps and widgets, inside its host. It holds the page on
/// screen and the edit state, so a swipe between pages changes nothing outside the host: a page
/// change that rebuilt the host set the scroll position again under the finger, and a swipe jumped
/// to the next page before it was halfway there.
struct HomeScreenContent: View {
    @Environment(ModuleRegistry.self) private var registry
    @Environment(Household.self) private var household
    @Environment(ShellNavigator.self) private var navigator
    @Environment(HomeScreenLayoutStore.self) private var layouts
    @Environment(SettingsStore.self) private var settings
    @Environment(WallpaperPhotoStore.self) private var photos
    @Environment(\.frostedFaceTone) private var frostedFaceTone
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var pageIndex: Int?
    /// The page the pages start on. Kept from the first time they are drawn, since only the first layout
    /// uses it, and a later value from outside moved the pages under a finger mid-swipe.
    @State private var startPage: Int

    init(initialPage: Int) {
        _pageIndex = State(initialValue: initialPage)
        _startPage = State(initialValue: initialPage)
    }
    /// Layout page index for each rendered page, for edits made on screen.
    @State private var logicalPages: [Int] = [0]
    @State private var sheet: HomeScreenSheet?
    /// The widget Edit Widget or Edit Stack is open for, from a tap in edit mode.
    @State private var editingWidget: HomeWidgetEditRequest?
    /// Opens Edit Stack or Edit Widget once the pages are drawn (`-HomePadEditStack`, `-HomePadEditWidget`, for screenshots).
    @State private var firstEdit: HomeFirstEdit?
    /// The live reorder in edit mode.
    @State private var reorder = HomeReorderSession()
    /// The pager's size, for the icon size the header is sized from.
    @State private var pagerSize: CGSize = .zero

    var body: some View {
        let memberID = household.activeMemberID
        let accent = HomeScreenView.accent(of: household)
        let wallpaper = settings[ShellSettings.wallpaper(for: memberID)]
        let hasPhoto = wallpaper == .photo && photos.image(for: memberID) != nil
        let tone = HomeWallpaperView.tone(wallpaper, accent: accent, hasPhoto: hasPhoto,
                                          photoTone: photos.tone(for: memberID), faceTone: frostedFaceTone, scheme: colorScheme)
        let miniWidget = layouts.layout(for: memberID).miniWidget
        // HomeView leaves about a third of an icon between the header and the first row.
        VStack(spacing: Theme.Spacing.l) {
            Group {
                if navigator.isEditingHomeScreen {
                    HomeScreenEditBar(
                        miniWidget: miniWidget,
                        textSize: HomeScreenHeader.textSize(iconSize: headerIconSize),
                        onMiniWidgetChange: { changed in layouts.update(for: memberID) { $0.setMiniWidget(changed) } },
                        onAddWidget: { sheet = .addItems },
                        onAddApp: { sheet = .addApps },
                        onWallpaper: { sheet = .wallpaper },
                        onNewPage: addPage,
                        onDone: finishEditing
                    )
                } else {
                    // Their name and avatar show only while they are recognized. A person
                    // picked by hand, or whose recognition lapsed, keeps their layout but
                    // the header shows the neutral avatar.
                    HomeScreenHeader(member: household.isPersonalContentUnlocked ? household.activeMember : nil,
                                     iconSize: headerIconSize, miniWidget: miniWidget,
                                     onAvatar: { navigator.toggle(.people) },
                                     onShowFace: { navigator.goAmbient() })
                }
            }
            // The shell's side margin, which the Home Screen adds itself since it takes no safe area.
            .padding(.horizontal, Theme.Spacing.screenMargin.leading)
            pager(memberID: memberID, wallpaperTone: tone, isBlurred: wallpaper == .face)
        }
        // One visible margin on all four sides: the header sits as far from the
        // top edge, and the page dots from the bottom edge, as the grid does
        // from the sides. Measured from the screen's edges, so the shell's
        // smaller top and bottom margins and the home indicator do not show.
        .padding(.vertical, HomeScreenView.edgeMargin)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // The host fills the window, so icons measured here are in window coordinates, whatever the scale.
        .coordinateSpace(.named(HomeIconSpace.name))
        .environment(\.zoomSourceSpace, .named(HomeIconSpace.name))
        // Preferences stop at the host, so the icons are handed to the navigator from here.
        .onPreferenceChange(ZoomSourcesKey.self) { navigator.homeSources = $0 }
        .tint(accent)
        // Color filters do not reach into the host from outside, so night mode is applied here too.
        .nightModeAware()
        .onAppear {
            sheet = navigator.pendingHomeSheet
            navigator.pendingHomeSheet = nil
            if let edit = navigator.pendingFirstEdit {
                firstEdit = edit
                navigator.pendingFirstEdit = nil
            }
            if let page = navigator.pendingHomePage {
                pageIndex = page
                navigator.pendingHomePage = nil
            }
        }
        .onChange(of: pageIndex) { _, page in
            if let page { navigator.lastHomePages[pageKey] = page }
        }
        .onChange(of: navigator.isEditingHomeScreen) { _, editing in
            if !editing { reorder.cancel() }
        }
        .sheet(item: $sheet) { sheet in
            switch sheet {
            case .addItems:
                AddToHomeScreenSheet(kind: .widgets, memberID: memberID, page: currentLogicalPage(memberID: memberID))
                    .presentationSizing(.page)
            case .addApps:
                AddToHomeScreenSheet(kind: .apps, memberID: memberID, page: currentLogicalPage(memberID: memberID))
                    .presentationSizing(.page)
            case .wallpaper:
                WallpaperPickerSheet(memberID: memberID, accent: accent)
                    .presentationSizing(.page)
            }
        }
    }

    /// The pages reach the screen edges, so each page is exactly one screen
    /// wide and keeps the shell's margin as padding of its own. A pager that
    /// stopped at the margin still drew into it (scroll views extend into the
    /// safe area), so the edge of the neighboring page showed there.
    /// - Parameter wallpaperTone: How bright the wallpaper is, for the widgets' glass.
    /// - Parameter isBlurred: True when the wallpaper is already blurred (Face wallpaper), so glass doesn't double-blur.
    private func pager(memberID: HouseholdMember.ID?, wallpaperTone: BackdropTone?, isBlurred: Bool) -> some View {
        GeometryReader { proxy in
            pages(memberID: memberID, size: proxy.size, leading: HomeScreenView.edgeMargin,
                  trailing: HomeScreenView.edgeMargin, wallpaperTone: wallpaperTone, isBlurred: isBlurred)
        }
        .onGeometryChange(for: CGSize.self) { $0.size } action: { pagerSize = $0 }
    }

    private func gridMetrics(gridSize: CGSize) -> HomeGridMetrics {
        HomeGridMetrics(size: gridSize, prefersLargerCells: dynamicTypeSize >= .xxLarge)
    }

    /// The icons' size, for the header. The pager reaches the screen's edges and keeps the margin as padding.
    private var headerIconSize: CGFloat {
        guard pagerSize != .zero else { return Theme.Size.appIcon }
        let gridSize = CGSize(width: pagerSize.width - 2 * HomeScreenView.edgeMargin, height: pagerSize.height)
        return gridMetrics(gridSize: gridSize).iconSize
    }

    private func pages(memberID: HouseholdMember.ID?, size: CGSize, leading: CGFloat, trailing: CGFloat,
                       wallpaperTone: BackdropTone?, isBlurred: Bool) -> some View {
        // The grid runs down to the bottom margin, as far from the bottom edge as
        // the header is from the top. The page dots sit inside that margin. Below
        // the grid, they made the bottom look larger than the top.
        let gridSize = CGSize(width: size.width - leading - trailing, height: size.height)
        let metrics = gridMetrics(gridSize: gridSize)
        let saved = layouts.layout(for: memberID)
        let access = PersonalAccess(household)
        // While an item is moved, the pages are drawn with it in the slot it would land in.
        let pages = HomeScreenPages.render(reorder.working(saved), registry: registry, access: access, metrics: metrics)
        let liftedID = reorder.lift?.tile.id
        let screen = HomeReorderSession.Screen(
            isEditing: navigator.isEditingHomeScreen, memberID: memberID, layouts: layouts,
            saved: { [registry] in HomeScreenPages.shownItems(saved, registry: registry, access: access) },
            pages: pages, metrics: metrics, page: min(max(pageIndex ?? startPage, 0), pages.count - 1),
            gridOrigin: CGPoint(x: leading, y: 0), width: size.width,
            showPage: { page, animated in
                var transaction = Transaction(animation: animated ? Theme.Motion.screen : nil)
                transaction.disablesAnimations = !animated
                withTransaction(transaction) { pageIndex = page }
            }
        )
        // Handed over on every draw, so a page turned mid-drag counts at once. The
        // gesture's own update runs only when a touch arrives.
        reorder.screen = screen
        return ZStack(alignment: .bottom) {
            ScrollView(.horizontal) {
                LazyHStack(spacing: 0) {
                    ForEach(pages) { page in
                        HomeScreenPageView(page: page, metrics: metrics, memberID: memberID, liftedID: liftedID,
                                           stackTargetID: reorder.stackTargetID, onEditWidget: { editingWidget = $0 })
                            .padding(.leading, leading)
                            .padding(.trailing, trailing)
                            .frame(width: size.width, height: gridSize.height, alignment: .topLeading)
                            // Whatever a tile draws past its page stays on that page.
                            .clipShape(SideClip())
                            .id(page.index)
                    }
                }
                .scrollTargetLayout()
            }
            // Pages clip their own sides, so edit badges above the top row are not cut off.
            .scrollClipDisabled()
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: $pageIndex)
            // A starting id alone is ignored before the lazy pages exist, so the
            // first layout is placed at the starting page by its offset instead.
            .defaultScrollAnchor(Self.anchor(page: startPage, of: pages.count), for: .initialOffset)
            .scrollIndicators(.hidden)
            // The finger moves the lifted item, not the pages. Holding it at a side turns the page.
            .scrollDisabled(reorder.isActive)
            .onScrollPhaseChange { _, phase in reorder.isScrolling = phase != .idle }
            .gesture(HomeReorderGesture(session: reorder, space: .named(Self.reorderSpace)))
            .frame(height: gridSize.height)
            // Centered in the bottom margin, below the grid.
            PageDots(count: pages.count, selection: Binding(
                get: { min(pageIndex ?? 0, pages.count - 1) },
                set: { index in withAnimation(Theme.Motion.screen) { pageIndex = index } }
            ))
            .frame(height: PageDots.height)
            .offset(y: (HomeScreenView.edgeMargin + PageDots.height) / 2)
        }
        .overlay(alignment: .topLeading) {
            HomeReorderLiftedTile(session: reorder, metrics: metrics, memberID: memberID)
        }
        // Widget glass takes its light or dark look from the wallpaper, as on
        // iPadOS. The Edit Widget sheet is presented outside it, so the sheet
        // follows the appearance.
        .glassBackdrop(wallpaperTone)
        .backdropBlurred(isBlurred)
        .coordinateSpace(.named(Self.reorderSpace))
        .task(id: pages.map(\.logicalPage)) { logicalPages = pages.map(\.logicalPage) }
        .task(id: firstEdit) {
            guard let edit = firstEdit,
                  let entry = pages.lazy.flatMap(\.tiles).first(where: { edit.matches($0.tile.item) }) else { return }
            // Once the pages have settled, as a tap would find them.
            try? await Task.sleep(for: .milliseconds(800))
            let frame = metrics.frame(for: entry.placement)
            editingWidget = HomeWidgetEditRequest(id: entry.tile.id,
                                                  tile: CGSize(width: frame.width, height: frame.height - metrics.widgetLabelHeight))
            firstEdit = nil
        }
        // Here rather than with the edit bar's sheets, so the two never share one view.
        .sheet(item: $editingWidget) { request in
            HomeEditWidgetSheet(request: request, memberID: memberID)
                .presentationSizing(.page)
        }
    }

    /// The pager's space, from its top left corner at the screen's side: where a
    /// lifted item is drawn and where the reorder gesture reports the finger.
    private static let reorderSpace = "HomeScreenReorder"

    /// The unit point whose offset is `page` screens in: 0 is the first page, 1 the last.
    private static func anchor(page: Int, of count: Int) -> UnitPoint {
        guard count > 1 else { return .topLeading }
        return UnitPoint(x: CGFloat(min(max(page, 0), count - 1)) / CGFloat(count - 1), y: 0)
    }

    /// Whose remembered page this is.
    private var pageKey: String { household.activeMemberID?.uuidString ?? "guest" }

    /// The layout page that edits apply to: the one on screen.
    private func currentLogicalPage(memberID: HouseholdMember.ID?) -> Int {
        let index = min(max(pageIndex ?? 0, 0), max(logicalPages.count - 1, 0))
        return logicalPages.isEmpty ? 0 : logicalPages[index]
    }

    private func addPage() {
        let memberID = household.activeMemberID
        layouts.update(for: memberID) { $0.appendPage() }
        withAnimation(Theme.Motion.screen) { pageIndex = logicalPages.count }
    }

    private func finishEditing() {
        layouts.update(for: household.activeMemberID) { $0.removeEmptyPages() }
        navigator.isEditingHomeScreen = false
    }
}

/// What the photo wallpaper's tone is measured for.
private struct PhotoToneKey: Hashable {
    var memberID: HouseholdMember.ID?
    var revision: Int
    var isPhoto: Bool
}

/// Clips a page at its sides only, so neighbors never show each other's
/// content while edit badges can still rise above the top row.
private struct SideClip: Shape {
    func path(in rect: CGRect) -> Path {
        Path(rect.insetBy(dx: 0, dy: -Theme.Spacing.l))
    }
}
