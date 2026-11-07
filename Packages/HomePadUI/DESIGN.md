# HomePad design system

HomePadUI is the one visual language every HomePad module shares. A person should never be able to tell where one module ends and another begins. This document says what the tokens and components are, when to use each, and what to avoid.

The reference is Apple HomeView (October 2026): dark, glassy, big type you can read from across a room, generous spacing and calm motion. HomePad also runs in Light (see [Light and dark](#light-and-dark)). HomePad runs on 11-inch and 13-inch iPads, in landscape and portrait, so it scales the same language up.

## Principles

1. **Glanceable first.** The face and the Home Screen are read from three meters away. Use big numerals and short labels. Put detail behind proximity (`ProximityAdaptive`) or a tap.
2. **Dark first, light too.** Dark is the default and the look HomePad was made in: black pages, dark wallpapers and content on Liquid Glass. Settings > Kiosk & Display > Appearance also offers Light and Match iPad, and every screen follows it. Night is always dark. See [Light and dark](#light-and-dark).
3. **One accent at a time.** Each household member picks one accent color from a fixed palette. Use semantic tints (`Theme.tint(for:)`) for accessory kinds. Never invent new colors.
4. **Calm motion.** Things fade, settle and drift. Nothing bounces hard or snaps.
5. **Night is red.** In a dark room the whole display goes red and dim. Every surface must survive that tint.
6. **Curated choices, not theming.** People choose from short lists (8 colors, 6 wallpapers, 4 text sizes, a widget gallery). No free-form colors, fonts or CSS.

## Tokens

All tokens live on `Theme` and `Font`. Use them instead of literals.

### Spacing (`Theme.Spacing`)

| Token | Points | Use |
|---|---|---|
| `xs` | 6 | Icon to label, lines inside a tile |
| `s` | 10 | Rows inside a panel, button groups |
| `m` | 16 | Tile padding, gaps between related items |
| `l` | 24 | Screen padding on every screen (`AppScreen`, Home Screen, Control Center, panels), grid gutters |
| `xl` | 36 | Sections in a panel, space inside large cards. Never a screen edge |
| `controlGap` | 10 (`s`) | Between controls that share a tile: Favorites rows, scene tiles, timer presets, notes. Every widget uses it |
| `sidebarRowGap` | 10 (`s`) | Between the rows of a sidebar of sections (Settings, Music), so a finger at arm's length lands on one row and not the next |
| `screenMargin` | 20 top, 40 sides, 12 bottom | Added by the shell as safe area around every screen. Never apply it again. Backgrounds that `ignoresSafeArea()` still reach the edge, and content that respects the safe area moves in. |

### Corner radius (`Theme.Radius`)

Like iPadOS 26, HomePad rounds things with a few radii, the same in every package. Each kind of element always takes its own step, a shape nested in another is concentric with it, and every corner is continuous (`style: .continuous`, Apple's squircle). Never type a number for a radius: pick the step for what the shape is.

| Step | Token | Points | Where it is used |
|---|---|---|---|
| Tile and panel | `tile` | 28 | Widgets and their previews, Control Center modules, `GlassTile`, `GlassPanel`, `GlassBanner` and every banner (Messages on the Home Screen and the face), glass panels that sit straight on a screen (weather, clocks, Camera Lab, People, Play On), camera views, hero artwork (Now Playing), a full-screen surface's corners while it is swiped down |
| Row, card and selection | `card` | 22 | List and sidebar rows and the highlight on the chosen one (`.sidebarRow`), option cards and swatches, face previews, shelf artwork and photos, chat bubbles with the photos and link cards in a thread, text fields and the Messages composer |
| Control in a tile | `tileControl` | 12 (`tile` less `Spacing.m`) | Anything in a tile's padding: controls, artwork, thumbnails. `GlassTile` sets `\.controlCornerRadius` to it, so rows and buttons that read that value pick it up inside a tile and keep `card` elsewhere |
| Thumbnail | `thumbnail` | 12 | Small images under about 80 points (mini player art, queue rows, attachments), dense image grids (Photos, the inner corners of a photo grid in Messages). Also the smallest radius a nested shape takes |
| Capsule | `pill` | 999 | Capsules and round artwork (artists), and the buttons of web pages styled to match (Music Assistant). Use `Capsule()` and `Circle()` directly when you can |
| Nested | `concentric(in:inset:)` | outer less inset, at least `thumbnail` | A shape in a container's corner with some other padding, such as a photo in a `GlassBanner` or an event in a week column |
| App icon | `icon(_:)` | 26% of the edge | `AppIcon` and `SettingsIcon` |

Sheets, alerts and popovers keep the system's corners. HomePad does not draw them.

#### The concentric rule

A shape inside another is rounded by the outer radius less the inset between them, so the two corners run parallel, as Apple's are. `Theme.Radius.concentric(in:inset:)` works it out, and the common nestings already have a token:

- A control in a tile: `tile` less `Spacing.m` is `tileControl` (12).
- Art in a card padded by `Spacing.s`: `card` less 10 is `thumbnail` (12), like the art in the Control Center media tile or a product photo in a grocery row.
- A selection or highlight is the row's own shape, so it takes the row's radius (`card`). The highlight on a chosen sidebar row and the outline of a chosen card use `strokeBorder` inside that same shape, never a stroke that spills past it.

The rule holds while the inset is under `Spacing.l`. At `Spacing.l` or more, outer less inset leaves almost nothing (28 less 24 is 4), and a row there would turn square. The corners are far enough apart not to read as a pair, so the row keeps its own step: `card` for a row in a `GlassPanel`, `thumbnail` for a picture.

- Buttons are circles (`GlassIconButton`, `RoundControlButton`) or capsules (`GlassCapsuleButton`, glass buttons, chips). Pills, badges and `StatusBanner` are capsules, and so are search and address fields. A circle inside a capsule, like the composer's send button, is concentric when its inset is about the capsule's radius less its own.
- Concentric radii come from the tokens, not from `ConcentricRectangle` or `.containerShape`. That shape draws square corners wherever no container shape is set, and rows such as `CompactAccessoryRow` and the sidebar rows are drawn both inside rounded containers and on their own.
- A `List` never draws the selection in a sidebar. Its platter and focus ring take UIKit's radius, which is not on this scale. Make each row a button with `.sidebarRow(isSelected:)`, as Settings, Music and Messages do.

#### What keeps its own corners

- Shapes that must match something outside HomePad: `icon(_:)` and the `AppIcon` mask, the zoom between an app's icon and its window (`AppZoomGeometry`), whose window corners match the iPad's display corners, and system sheets.
- Circles and capsules.
- Drawings that are not interface (face backdrops and shapes, clock digits, critters, demo camera frames, demo photos) use their own numbers.

### Sizes (`Theme.Size`)

| Token | Points | Use |
|---|---|---|
| `minTapTarget` | 44 | Apple's floor. Only dense chrome used up close: the top pills, items in a toolbar group, editor handles, map pins. See [Walk-up sizes](#walk-up-sizes) |
| `toolbarItem` | 48 | Every header toolbar item and every close button. See [Headers](#headers) |
| `tapTarget` | 64 | The walk-up minimum: every control on an app screen, panel, widget or Control Center (buttons, chips, list rows, sidebar rows, segment options, swatches) |
| `roundControl` | 72 | Round toggles, round buttons in system surfaces, secondary transport (previous, next), the buttons on Music's mini player |
| `heroControl` | 88 | The main control of a screen: play, shutter, answer the doorbell. Also the height of Music's mini player, a bar used from a few steps back |
| `appIcon` | 96 | App icon on an 11-inch iPad. The Home Screen scales up from it |
| `nowPlayingZone` | 176 | The width every header leaves empty at its top center for the timer and Now Playing pills |
| `faceNowPlayingRoom` | 68 | How far a face's content moves down while the face shows the timer or Now Playing pill: the full pill and `Spacing.m` (`\.faceNowPlayingRoom`) |
| `faceNowPlayingWidth` | 364 | The widest the pills get on a face, up close. A face's widget grid keeps the cells under them free |

`GlassIconButton` takes one of `minTapTarget`, `toolbarItem`, `tapTarget` (its default outside headers), `roundControl` or `heroControl`. Never pass a literal. In a header it is always `toolbarItem`.

### Typography

Use Dynamic Type styles so the Kiosk & Display text size setting and the iPad's own setting both apply. HomePad offers four curated sizes (Match iPad, Large, Extra Large, Huge).

| Style | Definition | Use |
|---|---|---|
| `Font.display(size, weight:)` | SF Rounded at a fixed size | Huge numerals only: clocks, temperatures, timers |
| `Font.screenTitle` | Large Title, bold | `AppScreen` titles |
| `Font.glanceTitle` | Large Title, rounded, bold | The one big line on a surface ("Good morning, Margot") |
| `Font.glanceSubtitle` | Title 2, rounded, semibold | The line under a glance title (date, condition) |
| `Font.tileTitle` | Title 3, semibold | The name of a thing in a tile, row or card. The smallest primary text on a walk-up surface |
| `Font.tileDetail` | Body | The secondary line in a tile, row or card: status, subtitle, time, place. The smallest text that carries information on a walk-up surface |
| `Font.tileValue` | Title 2, rounded, semibold | A value inside a tile ("72°", "Locked") |
| `.headline` uppercased with `.tracking(0.6)` | | Small date lines over a greeting, Control Center's date |
| `.subheadline`, `.footnote` | | Only where [Walk-up sizes](#walk-up-sizes) allows them: dense overviews and fine print |

For clock text, use `Date.clockTime()`, which follows the locale's 12 or 24 hour preference without AM or PM. Add `.contentTransition(.numericText())` to numbers that change.

Big display numerals (clock times, dates, temperatures on faces) use proportional digits, like the Lock Screen. Tabular digits give a 1 the width of a 0, which spreads a time like 11:07 apart. Use `.monospacedDigit()` only on numbers that tick every second (timers, seconds) or line up in columns (hourly strips, tables), where width changes would jitter.

### Color

- `Theme.Palette.swatches`: the eight member colors (Blue, Purple, Pink, Red, Orange, Yellow, Green, Teal). `PaletteSwatchPicker` picks one. Member colors tint the avatar, the Home Screen accent and the "My Color" wallpaper.
- `Theme.tint(for: AccessoryKind)`: the accent for an accessory tile.
- `Theme.nightRed`: the night palette. Do not use it for anything else.
- Pages use the adaptive colors in `Tokens/AdaptiveColors.swift`: `Color.screenBackground` for an app's page, `Color.groupedBackground` for a page of grouped forms (Settings), `Color.raisedBackground` for a raised row or card where glass does not fit, `Color.groupedRow` for a row drawn outside a `List` on a grouped page or sheet (white in Light, like a list's rows), and `Color.hairline` for borders and dividers.
- Text is `.primary`, `.secondary` or `.tertiary`, which follow the appearance. White text is for pictures and wallpapers only. Use `.tint` for interactive accents.
- `Color.foreground(on:in:)` picks black or white for a symbol or title on a filled control.

### Materials

- **Liquid Glass** (`.glassEffect`) for anything floating: panels, pills, round controls, toolbars. `GlassPanel`, `GlassBanner`, `GlassIconButton`, `ToggleTile`, `RoundControlButton`, `RemoveBadge`, `PageDots`, `GlassPill`, `StatusBadge` and `StatusBanner` all use it.
- `.buttonStyle(.glass)` for secondary buttons and `.buttonStyle(.glassProminent)` for the one primary action on a screen. `GlassCapsuleButton` and `glassButtonStyle(isProminent:tint:)` pick between them. A round icon button is always a `GlassIconButton`, and `isProminent` (the app's accent) or a `tint` makes it the primary action.
- `\.appAccent` is the app's own color, the tint of its icon (Calendar red, World Clock indigo). The shell sets it from `AppDescriptor.tint` for every app it hosts, so apps need no call of their own. `.appAccent(_:)` overrides it for a surface that needs another color. Settings keeps HomePad's accent, since its icon is gray. Prominent buttons fill with it, so a header's primary action matches its app instead of a bright green that every app shares.
- `GlassTile` (ultra thin material with a hairline border) for content tiles that fill a grid cell, such as widgets and accessory tiles.
- Full-screen backdrops behind panels use `.ultraThinMaterial` with a 30% overlay of the page color (`Color.screenBackground`), so they are dark in Dark and light in Light. Control Center's stays dark in both.

### Motion (`Theme.Motion`)

| Token | Curve | Use |
|---|---|---|
| `standard` | smooth, 0.35 s | Toggles, selection, small layout changes |
| `screen` | smooth, 0.5 s | Face to Home Screen, opening an app, the gate |
| `settle` | spring, response 0.42, damping 0.86 | Panels, sliders, drags, Control Center |
| `settleSpring` | `settle` as a `Spring` | A surface let go mid-drag, which carries on at the finger's speed: `.interpolatingSpring(Theme.Motion.settleSpring, initialVelocity:)` |
| `follow` | interactive spring, response 0.15 | Something following a finger that may take over a page still settling, such as the Photos viewer's pages |
| `proximity` | smooth, 0.7 s | Someone walking up or away: a face or widget moving between its far and near layouts |
| `ambient` | ease in out, 2.5 s | Burn-in drift, wallpaper, presence fades |

Respect Reduce Motion. `jiggle` and `editPulse` already do.

Motion follows events. Something changes, the change plays once and the screen goes still again: a number rolls (`.contentTransition(.numericText())` inside an animation), a symbol turns into the next one (`.contentTransition(.symbolEffect(.replace))`, or `.replace.magic` for a bulb filling or a shackle opening), a tile glows (`changeGlow`), a button sinks while pressed (`.pressable`). Put the animation on the value that changed (`.animation(Theme.Motion.standard, value:)`), not on a whole screen, so nothing else animates with it, such as a clock hand sweeping back from 59 to 0.

Motion that runs on its own costs power all day on an always-on display. Use it only where it is worth it, draw it from a `TimelineView` at 15 frames a second or less, hold it still when `\.allowsContinuousMotion` is false, and never put it on a page that scrolls. A `repeatForever` animation or an endless symbol effect redraws the screen at 60.

## Components

Sources are grouped by concern under `Sources/HomePadUI/`: `Tokens`, `Chrome`, `Buttons`, `Status`, `Tiles`, `Controls`, `Progress`, `Clock`, `Layout`, `System` and `Modifiers`.

### Chrome

| Component | What it is | Use it for | Notes |
|---|---|---|---|
| `AppScreen` | The header row and the content | Every full-screen app | Leave `onClose` nil inside HomePad. The shell supplies `\.closeApp`, and `AppScreen` shows the close button top right and tells the shell not to draw its own. Put actions in `accessory` and a view picker in `titleAccessory`, as described in [Headers](#headers). `onBack` adds a back button for a pushed screen |
| `AppHeader` | Back button, big title, title accessory, toolbar, close button | A screen pushed inside an app that lays out its own content (Camera Lab tools), a full-bleed screen with its title elsewhere (the recipe card), or an app with its own chrome (Settings, Now Playing) | `AppScreen` draws it for you. `onBack` adds the back button. An empty title draws only the buttons |
| `DetailHeader` | Title and status on the leading side, toolbar and close button on the trailing side, optional detail centered under them | A full-screen detail inside an app: an accessory, a camera, cooking mode | Lays out like `AppHeader`. Closing returns to the app. It tells the shell it draws its own close button, so a detail never shows two |
| `SheetScreen` | The sheet header above the sheet's content | Every sheet and modal form: a composer, an editor, a picker, a gallery | The first trailing closure is the toolbar with the one prominent action (Post, Add, Save), the second the content. With one closure there is no toolbar. The content reaches the sheet's edges, so a `List` or `Form` keeps its own insets, on the sheet's background like the header. In Light that background is `Color.groupedBackground`, so a form's white rows stand out. Closing dismisses the sheet unless `onClose` is set. See [Headers](#headers) |
| `SheetHeader` | Title on the leading side, toolbar and close button on the trailing side, no Now Playing zone | A sheet that lays out its own content | `SheetScreen` draws it for you. The same item size, stages and More menu as `AppHeader`. `onBack` adds a back button for a page pushed inside the sheet |
| `CloseButton` | `GlassIconButton` with an xmark at `toolbarItem` | Dismissing a full-screen surface, a banner or an overlay | The same size everywhere. Pass a label such as "Dismiss" when it does not close an app |
| `HeaderPicker` | A menu showing the current choice and a chevron, or its symbol when short of room | What a screen shows: Day, Week or Month, a clock style, whose faces, which music source or AI provider | Goes in `titleAccessory`, never in the toolbar |
| `HeaderMenu` | A header toolbar menu: a round symbol, or a capsule with its title | A More menu of a screen's own (the recipe card) | Becomes a submenu when the toolbar moves it into its own More menu |
| `ToolbarGroup` | Related header items in one glass capsule | Previous, Today and next. Icon buttons that act on the same thing | Its items lose their own glass. No prominent action inside |
| `.headerItem()`, `.toolbarItemPriority(_:)` | Bar or More menu placement | Any other view in a toolbar (`PhotosPicker`), and items that should leave the bar first | |
| `.showsRunningTimers()` | Tells the shell the screen shows its running timers (`ShowsRunningTimersKey`) | A screen with its own timer pills, such as cooking mode | The shell's timer pill steps aside while it is on top, as the Now Playing pill does inside Music |
| `.coverScreenMargin()` | The shell's `screenMargin` as safe area | The content of every `fullScreenCover` | UIKit presents a cover above the shell, so the margin the shell adds never reaches it. Without this its close button sits 24 points from the bezel instead of 64 |
| `.coverHomeBar(colorScheme:)`, `HomeBar` | The app's home bar, drawn over a cover with the shell's actions (`\.homeBar`) | The content of every `fullScreenCover` an app presents | The shell's bar sits under a cover, which UIKit draws above the shell. With this a tap or a swipe up goes Home from the cover, and the window shrinks into the app's icon with the cover in it. Pass `.dark` for a cover that stays black in every appearance (a photo or video viewer), so the bar reads on it. Draws nothing outside an app |
| `.swipeDownToDismiss(isEnabled:style:onDismiss:)` | Swipe down to close, as iPadOS closes sheets and the Music player | Full-screen surfaces that go back to where they were opened: Now Playing, a camera full screen, an accessory's or group's controls. `.panel` for a panel such as Play On | See [Gestures](#gestures). `onDismiss` runs once the surface has slid away. A full-screen surface puts `.fullScreenSurfaceContent()` on its content, which moves and shrinks with the card while the page stays still under it |
| `.transition(.fullScreenSurface)`, `.fullScreenSurfaceContent()` | The surface fades in and out while its content zooms from 97% | Every full-screen surface shown over a screen: an accessory's controls, a camera, a ringing timer or alarm, the assistant | Put `.fullScreenSurfaceContent()` on the content, inside the page. The page only fades: SwiftUI gives a view under a scale other than 1 no safe area, so a scaled page that ignores the safe area stops at the shell's margin until the zoom settles. `.fullScreenSurface(scale:)` zooms from another scale, such as 1.04 for an alert that settles in. A swipe down (`swipeDownToDismiss`) moves and shrinks the same content |
| `DirectionalPan`, `SwipeDismissPolicy` | A pan that takes only drags starting its way, and the swipe's values | A surface that pages and closes (the Photos viewer), or closes into something | Use the modifier unless the surface draws its own close |
| `SectionHeader` | Icon and title in secondary color, Title 3 semibold | Groups of tiles and shelves | As large as the tile titles under it, so it reads from arm's length |
| `AvatarView` | Emoji avatar in the member's color | People, profile buttons | Guest shows a person glyph |
| `@AppState`, `AppStateKey` | `@State` that is saved, so the app reopens where it was left | Everything an app shows that a person chose or moved to: view mode, filter, tab, the date, the open album, the pane | In HomePadCore. `scope: .member` for personal apps, `storage: .session` for values that change often, `lifetime: .timePosition` for a date. See [Navigation](#navigation) |
| `.restoresScrollPosition(_:)` | Scrolls back to the top item saved last time, and saves it once scrolling stops | A long list or grid worth coming back to, such as an album's photos | In HomePadCore. Bind it to a session `@AppState` and put `.scrollTargetLayout()` on the lazy stack or grid |

### Buttons

| Component | What it is | Use it for | Notes |
|---|---|---|---|
| `GlassIconButton`, `.buttonStyle(.glassIcon())` | Round Liquid Glass button with one symbol | Every round icon button: header actions, banner actions, media and camera controls | Sizes come from `Theme.Size`. `isProminent` fills it with the app's accent for the primary action, and `tint` with another color, with a black symbol on light fills (white, yellow, `.primary` in Dark) and a white one on the rest. The style form fits `ShareLink`, `PhotosPicker` and `Menu` labels. In a header it takes the toolbar metrics on its own |
| `GlassCapsuleButton`, `.buttonStyle(.glassCapsule())` | Capsule glass button with a symbol and a title | Labeled actions read from across a room: "Ingredients", "+1 min", "Not Now", "Edit" | Drawn like `GlassIconButton`. `.regular`, `.toolbar`, `.large` and `.extraLarge` are as tall as `minTapTarget`, `toolbarItem`, `tapTarget` and `roundControl`, so capsules line up with round buttons. `.large`, the default, is the walk-up size. `.regular` is only for dense chrome used up close. `isProminent` for the primary action. In a header it is `.toolbar` and shows only its symbol when the toolbar is short of room |
| `glassButtonStyle(isProminent:tint:)` | Switches between `.glass` and `.glassProminent` | Any button whose prominence follows state | |
| `RoundControlButton` | Round one-shot button with a label under it, matching `ToggleTile` | Actions in Control Center rows (open Mirror, run a scene) | |
| `.buttonStyle(.sidebarRow(isSelected:tint:))` | A sidebar row: the whole row is the target, at least `tapTarget` tall, with a quiet gray highlight on the chosen row and a fainter one while pressed | Every sidebar: Settings and Music sections, Messages conversations | Rounded by `Radius.card`. Stack rows `Spacing.sidebarRowGap` apart. The label sets its own font and color. `tint` fills the chosen row with a color and turns its label black or white, as Messages does in blue. Use it in a `List` too, instead of the list's own selection |
| `.buttonStyle(.pressable)` | A plain button that sinks a little and dims while pressed | Tiles, rows, icons and artwork that draw their own look, instead of `.plain`, which gives no feedback | `.pressable(scale:)` sinks large tiles less (0.97 or 0.98). With Reduce Motion it only dims |

### Status and feedback

| Component | What it is | Use it for | Notes |
|---|---|---|---|
| `GlassBanner` | Floating glass card with a tinted icon, title, detail, optional content and actions | Something that just happened: intercom, a shared photo, a sound alert, a speaker suggestion | Text grows from across the room. Add padding and a transition where you place it |
| `StatusBanner` | Glass capsule with icon and one sentence | Persistent conditions (not charging, demo data, Home Assistant offline) | Not for errors that need action |
| `PermissionPrompt` | Explanation before iPadOS asks, "Open Settings" after a no | Every permission | `.page` fills a screen, `.row` sits in a `Form`. `init(feature:systemImage:reason:isDenied:)` writes the standard wording |
| `EmptyStateView` | System `ContentUnavailableView` with a Title title and a Title 3 message | Missing setup, no data | One action at most, drawn as a prominent `GlassCapsuleButton` |
| `GlassPill` | Small glass capsule with a symbol and a word or two | Provider names, hardware features, filters that are not buttons | Put a status symbol in `trailing` |
| `StatusBadge` | Glass capsule with a colored dot and an uppercase word in Subheadline bold | "LIVE" (`StatusBadge.live`), "Scanning", "Security Camera On" | Capitals at Subheadline are as tall as Body in lower case. `pulses` for something happening right now. The pulse runs at 12 frames a second and rests while `allowsContinuousMotion` is false |
| `.changeGlow(_:tint:in:)` | The shape lights in a tint for about a second when a value changes | An accessory turning on or off, a scene running | Plays once per change and draws nothing at rest. Change the trigger only for changes worth noticing |

### Tiles and containers

| Component | What it is | Use it for | Notes |
|---|---|---|---|
| `GlassTile` | Filling tile with material and border | Widgets, accessory tiles, grid cells | Fills its frame. Night-aware. `surface: .solid` draws an opaque card instead, with the same radius, padding and border: white with dark text by day and black with light text at night, so the red night tint never makes a bright red block. The calendar widgets (Up Next, Date) use it, as HomeView's Calendar widget is a white card |
| `GlassPanel` | Hugging Liquid Glass container | Menus, panels, Control Center media tile | Pass `tint` sparingly |
| `widgetGlass(in:)` | `GlassTile`'s glass in any shape | Something that sits among widgets without being a tile, such as a face's mini widget | Clear Liquid Glass, darker over a dark backdrop, over thin material unless the backdrop is blurred, content in the backdrop's scheme, night-aware. `GlassTile` draws its glass with it |
| `FeatureTile` | `GlassTile` with an app icon, title, description and status | Launcher grids of tools (Camera Lab) | `isActive` adds a pulsing "On" badge |
| `ArtworkTile` | Square artwork with title and subtitle under it | Albums, stations, playlists, recipes | Any view is the artwork. `isActive` adds a waveform badge |
| `AppIcon`, `AppIconTile` | Gradient rounded-square icon, with label | Home Screen, app grid, galleries | Badges: `.locked`, `.remove`, `.count`. The label is white with a shadow for a wallpaper. `isOnWallpaper: false` draws it in `.primary` for glass and sheets (the app grid, Add App) |
| `SettingsIcon` | Small rounded square with a white symbol | Leading icons in `Form` and `List` rows | iOS Settings style |

### Controls

| Component | What it is | Use it for | Notes |
|---|---|---|---|
| `BigSlider` | Fat glass slider filled from one end | Brightness, volume, dimmers, blinds | Whole surface is the target. `showsValue` draws the HomeView style percentage for full-screen accessory controls. Commit to devices in `onEditingChanged(false)`. Inside a `GlassTile` it is a control on glass: its empty part takes `controlSurface` and its corners `\.controlCornerRadius`. Its drag starts as the finger lands, so it keeps the touch from the pages, taps and holds around it (see [Gestures](#gestures)) |
| `VolumeRow`, `VolumeSlider` | A slider between a quiet and a loud speaker symbol | Every volume slider: speakers, Now Playing, sleep sounds | Pass the `Slider`, which decides what it is bound to and when to send. `VolumeSlider` draws a bound volume in a `VolumeSliderStyle`: `.row` is a `VolumeRow`, `.bar(axis)` a `BigSlider` with the speaker for the level, for widgets and Control Center. `SystemVolumeSlider` and Now Playing's sliders take the style |
| `ToggleTile` | Round or wide toggle | Control Center toggles, accessory on/off | `.round` for system toggles, with a Body label. `.wide` with subtitle for accessories, in `Font.tileTitle` and `Font.tileDetail` |
| `ChoiceChips` | Row of capsules, one selected | Short curated choices on a screen: music sections and filters, intercom destinations, a tool's mode | `GlassCapsuleButton`'s `.large` size, `tapTarget` tall with Title 3 text. The selected chip fills with the app's accent. Use it instead of a segmented control outside forms |
| `SuggestionChips` | Wrapping glass buttons | Example questions, quick replies | `GlassCapsuleButton`'s `.large` size, like `ChoiceChips` |
| `OptionCarousel`, `OptionCard` | Snapping row of cards, one selected | Style and color choices in editors (watchOS face editor style) | |
| `LabeledSegmentedPicker` | Label with a segmented control at the large control size | Two to four presets in a settings row | Forms only. On a screen use `ChoiceChips` |
| `PaletteSwatchPicker` | Row of the eight member colors | Any per-person color choice | Stores "#RRGGBB" |
| `PageDots` | Glass capsule of dots | Paged content, recipe steps | Draws nothing for one page. Long runs show a window of dots |
| `CopyableValueRow` | Label, monospaced value and a copy button | Setup values typed into another app | `displayValue` masks secrets |
| `GlassSearchField` | A search field on a glass capsule, with a clear button once something is typed | Search in a sheet, first in its content | As tall as a header item. Sheets have no navigation bar for `.searchable` |
| `RemoveBadge`, `.jiggle(_:isPaused:)` | Edit-mode minus button and wiggle | Rearrangeable grids of icons and widgets (Home Screen, Shortcuts, a face's widgets) | Every item wiggles on one shared clock. `isPaused` holds a lifted item still. The minus is a plain translucent circle, as on iPadOS, not glass |
| `.editPulse(_:)`, `.editPulseBorder(in:)` | Edit mode that keeps items still and pulses their outlines | Control Center, as on iPadOS | Items stay Liquid Glass. Shared components draw the pulse in their own shape, and only an item's outermost shape pulses |
| `.tileGlassEffect(_:in:)` | Liquid Glass, or `GlassTile`'s frosted material while jiggling | Rounded rectangles that can jiggle (sliders, panels) | Glass cannot rotate. Under the wiggle it smeared past the tile, so jiggling tiles use the material |
| `.levelFill(_:tint:in:)`, `.fillAwareForeground()` | A control filled from its leading edge to a level, text black over the fill and `.primary` past it | Lights in Favorites rows and accessory tiles | Put the empty part's surface behind it |
| `.controlSurface(_:)` | A translucent fill, lighter than a dark tile and darker than a light one, worked out from the tile's surface | Controls in a tile with nothing to show off (a light that is off, a scene) | See [Controls on glass](#controls-on-glass) |

### Progress and time

| Component | What it is | Use it for | Notes |
|---|---|---|---|
| `TickRing` | Ring of ticks lit in proportion to progress | Timers and countdowns | Orange by default, like Apple's timers |
| `SegmentedProgressRing` | Ring of segments that fill step by step | Multi-step setup such as face enrollment | Green by default, like Face ID |
| `AnalogClock` | Round analog clock for any time zone | World clocks, clock widgets | Day and night dials, or explicit colors for a face palette |
| `ClockHands`, `DialTicks`, `DialNumerals`, `ClockMath` | The parts every analog clock uses | Custom clock faces | Use them instead of drawing new hands. The hands have a thin neck and a wide rounded body, like Apple Watch's. `DialNumerals` puts numerals around a circle or along the view's rounded rectangle (`DialNumeralPath`), for a dial that fills a screen |
| `LiveTime` | Redraws four times a second while active | Countdowns and elapsed time | |
| `Date.clockTime()` | "4:11" without AM or PM | Big digital clocks | Follows the locale's 12 or 24 hour setting |

### Layout

| Component | What it is | Use it for | Notes |
|---|---|---|---|
| `AdaptiveStack` | Side by side when wide, stacked when tall | Two-pane app screens | |
| `TileGridLayout`, `.tileSpan(_:)` | Grid of one and two column tiles packed in order | Accessory grids | |
| `ShelfRow` | Titled horizontal scroller | Rows of `ArtworkTile`s | |
| `FlowLayout` | Wraps items into rows | Chips and tags | |
| `.labelStyle(.trailingIcon)` | Icon after the title | "Madison" with a location arrow | |
| `ProximityAdaptive` | Far and near variants with a crossfade | Faces and widgets whose far and near share no text | Far: one big fact. Near: detail. See [Proximity](#proximity) |

### Widgets

| Component | What it is | Use it for | Notes |
|---|---|---|---|
| `WidgetGallery` | The iPadOS widget gallery: every widget as a big live preview, then a page per widget to swipe through its sizes and Add Widget | Adding widgets anywhere: the Home Screen and a face's Widgets page | Present it page-sized (`.presentationSizing(.page)`). It has its own navigation and a sheet header on each page, with a back button on a widget's page. `tileSize` draws previews at the size the widget will have where it goes. `unavailableReason` keeps Add Widget off for a size with no room and says why |
| `WidgetPreview` | A live widget drawn at its real size and scaled to fit a box, never larger | Previews of widgets outside the place they sit | Sets `\.isThumbnail` and turns off touches |
| `EditWidgetSheet` | Edit Widget, as on iPadOS: the widget's own settings page (`WidgetDescriptor(…, settings:)`) beside a live preview with those settings, under the sheet header with only the close button | A placed widget's settings: a tap on it in Home Screen edit mode, Edit Widget under a face editor's preview | Present it page-sized. Wide (landscape) the preview takes the leading 40 percent, narrow it sits above. Changes apply as they are made. A settings page is a `List` or `Form`, with a `GlassSearchField` first when it is long, and it offers only what the person at the screen may see. `onBack` and `onClose` let Edit Stack push it as a page. While this HomePad shares its setup with another, Same on All HomePads sits under the preview (`SameOnAllHomePadsSwitch`): a `Color.groupedRow` row with the switch and a footnote. It changes only the settings binding, so every host gets it |
| `WidgetStackView`, `WidgetStackItem` | A widget stack, as an iPadOS Smart Stack: one widget at a time, a vertical swipe to flip, page dots beside it while it moves, and Smart Rotate | A `WidgetStack` on the Home Screen or a face | See [Smart Stacks](#smart-stacks). Draw it unclipped, since it rounds itself and draws its dots outside its frame. `isInteractive: false` in edit modes and previews holds it still |
| `EditStackSheet` | Edit Stack, as on iPadOS: the stack's widgets with previews, to drag into order, remove or open in Edit Widget, the Smart Rotate switch, and the widgets that can join | A tap on a stack in Home Screen edit mode, Edit Stack under a face editor's preview | Present it page-sized. Changes apply as they are made. The place holding the stack turns it back into a widget when one is left, and the sheet closes |
| `SmartStackOffer` | The Smart Stack in `WidgetGallery`, first, as on iPadOS | Both galleries | Its widgets for each size come from `WidgetStack.suggested`. A size with fewer than two is not offered. Its preview is the first widget with the stack's dots |

### Mini widgets

A mini widget fits a header instead of a grid cell: one row. In the Home Screen header it is as tall as the profile button (`Theme.Size.profileButton`) and comes small, medium or large, where the size changes how much it says, never its height. On a face it is always small and one line in the face's top margin. Bigger ones are regular widgets in widget slots. Core's `MiniWidgetDescriptor` describes one and `registry.register(miniWidget:)` adds it. The glance is the first and, for now, the only one.

- **Where.** Right of the Home Screen header's lines, on the wallpaper in the lines' white capitals with their shadow. And in a face's top margin at its leading side: a 36 point capsule ending where the face's content starts, on the glass the face's widgets are on (`widgetGlass(in:)`, shared with `GlassTile`). Nothing of the face is laid out there, so the face never moves for it. It drifts with the face, turns red at night and is left out under the Home Screen's frost.
- **Room.** It takes the room it is offered and shows less before anything is cut off: fewer words, then a symbol and a count, then fewer things. In the header that is what the lines, pills and avatar leave. On a face it stops `Spacing.l` short of the pills' zone (`faceNowPlayingWidth`), whether or not they show, so its glass hugs what it shows and never reaches them.
- **Drawing one.** The place that draws it hands it a `MiniWidgetContext`: the size, the surface (`.wallpaper` or `.glass`), the text size (the header lines', or the size that fits one line in the face's capsule with `Spacing.s` around it) and how a tap opens an app. Taps open apps only in the header and on the face on the wall, and each part that opens one reports itself with `.zoomSource`. Personal parts stay out until someone is recognized, as the glance's do.

### Smart Stacks

A widget stack holds up to ten widgets of one size in one place on the Home Screen or a face, as an iPadOS Smart Stack does, so a widget can show only when it matters. Core's `WidgetStack` is the model, `WidgetStackRotation` the rules and HomePadUI's `WidgetStackView` draws it.

- **Flipping.** A vertical swipe flips to the next or the one before, with paging, and small page dots show beside the trailing edge while it moves and a moment after. It is a vertical paging scroll view, as the pages are horizontal ones (see [Gestures](#gestures)). A tap acts on the widget on top: its own buttons, or its app, which zooms out of the stack. The Home Screen's label under a stack names the widget on top.
- **Making one.** On the Home Screen, hold a widget over another of its size in edit mode: the others hold still while it is over that widget, after a moment it grows a little, and letting go stacks them with the dropped widget on top. Passing over moves things aside as before. Both widget galleries offer a Smart Stack first, prefilled for its size (`WidgetStack.suggested`). A tap on a stack in edit mode, or Edit Stack under a face editor's preview, opens Edit Stack (`EditStackSheet`).
- **Smart Rotate.** A widget says how relevant it is with `WidgetDescriptor(…, relevance:)`, a hook that returns a `WidgetRelevance` (a score and an optional time it holds until) from a `WidgetRelevanceContext` (the time, its settings and the services). The stack calls it inside a view, so a hook that reads `@Observable` models is asked again when they change, and again at the time an answer gives. Use the steps, so modules compare fairly: `.needsLook` (1, a doorbell ring, an open door, a weather alert), `.timely` (0.75, a timer running, an event within half an hour or under way, rain on the way), `.ongoing` (0.5, music playing), and `.notYet(until:)` for nothing now but something later.
- **The rules.** The stack rests on the person's widget: the one they last flipped to, or its first. It turns to the most relevant widget when that is more relevant than theirs, and back once it passes. A relevance with a time stays until then even when its hook stops saying it, such as the camera after the doorbell's banner closed. A flip by hand holds for `WidgetStackRotation.manualHold` (10 minutes) before Smart Rotate turns the stack again. Each stack can turn Smart Rotate off in Edit Stack. What a stack remembers lives in `AppServices.widgetStacks` while HomePad runs, so the same stack drawn twice shows the same widget, and after a restart a stack rests on its first widget.
- **Who sees what.** Personal widgets in a stack follow the widget rules: left out for guests, drawn locked for a member picked by hand, and never turned to while locked. A stack with nothing to show is left out like a hidden widget.
- **Saving.** A stack saves as a widget of its first widget's ID with its widgets beside it, so a HomePad from before stacks shows that widget. A stack with one widget left becomes that widget, keeping its settings.

### System views

| Component | What it is | Use it for | Notes |
|---|---|---|---|
| `AirPlayButton` | The system route picker | Choosing speakers | `isGlass` puts it on a glass circle next to `GlassIconButton`s |
| `SystemVolumeSlider` | The system volume slider between speaker symbols, or a bar | Volume anywhere | `style: .bar(.vertical)` is Control Center's volume |
| `CameraPreview` | Live capture preview kept level as the iPad turns | Mirror, enrollment, Camera Lab | Claim the camera through `services.capture` first |
| `.systemSheetStyle()` | Form sheet for Apple's controllers, in the app's appearance | EventKitUI, PhotosUI | Never a full-screen jump. The controllers take the appearance from the window, so `homePadDarkAppearance()` does nothing now and is deprecated |
| `.nightModeAware()` | Red, dim tint in `.night` | Any surface that does not draw its own night palette | |
| `.keepsDisplayActive(_:)` | Holds the display awake while shown | Hands-busy screens such as cooking mode | |

### Environment values

- `\.displayCondition`: `.active`, `.ambient`, `.dimmed`, `.night` or `.sleeping`, from the shell's kiosk controller.
- `\.proximity`: `.far`, `.mid` or `.near`. It is `.near` in apps and on the Home Screen until a minute after someone's last touch, even when the camera loses them (in a dark room it cannot see the person at the iPad). The face follows the camera instead, so it goes back to its far layout as soon as the camera sees nobody.
- `\.isThumbnail`: true inside face and widget pickers. Skip live streams and animation there.
- `\.isFrosted`: true for the face kept behind the Home Screen as its wallpaper. Like HomeView's, it draws only its picture or background, never its time, text, tiles or widgets (Faces' `faceBackdrop` and `faceForeground()`), and redraws rarely, since motion barely shows through the blur.
- `\.allowsContinuousMotion`: false in thumbnails, behind the frost and while the display is dimmed, at night or asleep. Anything that animates on its own on a face or a widget (`repeatForever`, drifts, particles) checks it and holds still when it is false.
- `\.faceInsets`: where a face's content starts from its edges. Faces draw outside the shell's margin, so inset edge content (text, tiles, grids) by this, never by a padding of their own. It matches every other screen (64 points at the sides, 44 top and bottom) and includes the burn-in overscan. While the face shows the Now Playing pill its top grows by `\.faceNowPlayingRoom`, and while a face has widgets beside its content it grows by the room they take. Full-bleed art can ignore it. Content centered on the whole face, such as a dial, still fits what is left, shrinking around its center rather than moving. The shell's profile dot (who is recognized) sits centered in the top right corner of that margin on every face, so faces draw no recognition hints of their own. A face can also have a [mini widget](#mini-widgets) in its top left corner, which its widgets and content keep clear of in the same way.
- `\.faceNowPlayingRoom`: the part of `faceInsets.top` the timer and Now Playing pills take while the face shows one, otherwise zero. A face's widgets keep their cells whether or not music plays, so the widget grid is laid out from the insets without it.
- `\.closeApp`: closes the current app (go Home). Nil outside apps.
- `\.homeBar`: the home bar's tap and swipe (`HomeBarActions`), for `coverHomeBar()`. Nil outside apps.
- `\.appAccent`: the app's own color, set by the shell from the app's icon tint. Prominent buttons fill with it. HomePad's accent color outside apps.

## Night mode

When the room is dark or the night schedule applies, `\.displayCondition` is `.night` and brightness drops to a few percent. Surfaces either draw a red monochrome version themselves (faces with `supportsNightMode`) or let `.nightModeAware()` tint them. Check every new surface with `-HomePadCondition night`. Avoid thin, low-contrast secondary text that disappears in red. Faces on the wall keep their far layout at night, and their secondary text is the same red as the rest (`FacePalette.night`), like HomeView's night face.

## Light and dark

Settings > Kiosk & Display > Appearance picks Dark (the default), Light or Match iPad (`ShellSettings.appearance`). The shell applies it once, with `.preferredColorScheme` in `ShellContentView`, and night is always dark, since night mode's red tint would turn a white page bright red. Every screen follows it.

- **Pages** are `Color.screenBackground`: black in Dark, white in Light. The shell draws it behind every app, so most apps need no background of their own. Settings uses `Color.groupedBackground`, and sheets take it in Light, so a form's white rows stand out as in iPadOS. A raised row or card where glass does not fit is `Color.raisedBackground`, a row outside a list on a grouped page or sheet is `Color.groupedRow`, and a border or divider is `Color.hairline`.
- **Text** is `.primary`, `.secondary` and `.tertiary`, never `.white` or `.white.opacity(x)`. Strokes and fills on pages are `.primary.opacity(x)`, which keeps Dark exactly as it was. Where that reads too heavy in Light, take a smaller opacity there, as the Settings sidebar's highlight does. Controls on glass follow the surface they sit on instead (see Controls on glass).
- **Glass and materials adapt by themselves.** Symbols and labels on glass are `.primary`, which also follows the glass when it turns light over a bright background. A white symbol on light glass disappears.
- **Glass on a backdrop follows the backdrop.** Over a face or a wallpaper, `GlassTile`'s glass is dark with light text over a dark backdrop and light with dark text over a bright one, in either appearance, as iPadOS widgets are on a wallpaper. Never hard-code it per face or per wallpaper. Whatever draws a backdrop reports how bright it is with `backdropTone(_:)` (a `BackdropTone`, from colors it already has), and the view that lays glass on it passes that to `glassBackdrop(_:)`, which sets `\.backdropScheme`. Faces report theirs (see the Faces README), `FaceHost` hands it to the face's widgets, and the Home Screen hands its wallpaper's to its widgets. The split is `BackdropTone.midpoint`, about 0.18 luminance, where black and white text read equally well, and glass already light or dark keeps its look until the backdrop is `hysteresis` past it. Glass on a page has no backdrop and follows the appearance, solid cards always do, and at night glass is dark. Put `glassBackdrop` on the views with glass, not on one that presents a sheet.
- **Filled controls** pick black or white for their fill with `Color.foreground(on:in:)`: black on white, yellow or `.primary` in Dark, white on the accent, orange or `.primary` in Light. `GlassIconButton`, `GlassCapsuleButton`, `ToggleTile` and `BigSlider` do it already, so a button lit with `tint: .primary` reads in both.
- **Scrims and frosts.** A scrim that only dims stays black (the People menu's backdrop, a scrim over a photo). Under white text on a picture that can turn bright, such as a weather sky, the scrim is only as dark as `BackdropTone.whiteTextShade` works out from the picture's own colors: none on a dark picture, and on a bright one just enough for the text to reach its contrast. Never pick it per picture. A frost behind a panel takes the page color, dark in Dark and light in Light (the app grid, the recognition gate, onboarding).
- **Fixed black and white stay only where the color belongs to the content:** faces, photos, artwork, video and camera views, white text or symbols over a picture, sticky note paper, and dimming scrims over pictures. The Home Screen sits on the member's wallpaper (a face, a gradient or a photo), so its labels stay white with their shadow, as on iPadOS. `AppIconTile` takes `isOnWallpaper: false` for a `.primary` label on glass or in a sheet.
- **Surfaces that stay dark** set `.environment(\.colorScheme, .dark)` on themselves: Control Center (as on iPadOS), the timer and Now Playing pills (like Live Activities), the assistant overlay, Music's full-screen player and the doorbell overlay. Put it on the surface only, never on a view that presents a sheet, or the sheet's text turns light on a light sheet.
- **No `.preferredColorScheme` below the shell's root.** In the main window it sets the whole window's scheme, and in a sheet it fights the app's. Sheets, covers and system controllers (`systemSheetStyle()`) take the appearance from the window.
- **Check both.** Shoot every screen you change in Light and Dark. The setting is JSON in UserDefaults, so pass it as plist data: `-shell.display.appearance '<226c6967687422>'` for Light and `'<226461726b22>'` for Dark. Check night with `-HomePadCondition night`.

## Controls on glass

A control inside a glass widget that has nothing lit to show (an accessory that is off, the empty part of a dimmed light, a scene) sits on `controlSurface(_:)`. Its fill has to stand out from the widget's own glass on any backdrop, and glass over a bright photo is nearly white, where a fixed white fill vanished.

- **The fill is Apple's kind of fill.** It is white or black at an opacity (`ControlFill`), like `systemFill`: a translucent gray that darkens a light surface and lightens a dark one. iOS draws a control on a white surface in Light that way, and Control Center draws its modules lighter than its dark glass. Being translucent, it keeps the glass and its blur showing through the row.
- **It follows the tile's surface, not a list.** `glassBackdrop(_:)` passes the backdrop's tone along with its scheme (`\.glassBackdropTone`). `GlassTile` works out what its own surface looks like over it (`GlassSurface`, from the look of the glass and whether the backdrop is already blurred) and hands that to its content (`\.tileSurfaceTone`). Outside a tile (Control Center, a popover, a detail page) the control takes glass over the page color.
- **The rule.** A surface darker than `BackdropTone.midpoint` gets a lighter fill and a brighter one a darker fill. The opacity is the faintest that reaches `ControlFill.minimumContrast` (1.4 to 1 in WCAG terms) against the surface, and never under `ControlFill.faintest`, the white at 12 percent that dark glass always had. So dark glass keeps its rows, light glass gets gray rows at about 15 percent black, and dark glass over a bright face in Dark gets darker rows, which also give its white text more contrast. At night glass is taken as dark over black, so the red rows do not change.
- **Why 1.4.** It is what the rows on dark glass already reached (1.42 to 1.47 measured), so Light reads like Dark. Apple's `systemFill` on white is about 1.28, and HomePad is read from a few steps away. The rows on light glass were at 1.0 to 1.08.
- **Why not the alternatives.** White rows on a toned down surface would gray every light widget, including those with no controls, and need nearly opaque white rows that hide the blur. A hairline edge is too thin to read from across the room, and Liquid Glass already draws a rim of its own.
- **The glass model.** `GlassSurface` was measured from `GlassTile` in the iPadOS 27 simulator over flat face backgrounds and wallpapers, and agrees with a device screenshot over a photo: light glass pulls its backdrop about 65 percent of the way to white (60 percent on a blurred backdrop), and dark glass about 61 percent of the way to a gray of sRGB 0.27 (35 percent on a blurred backdrop). Measure again if `GlassTile`'s layers change.
- The level fill (`levelFill`) draws over the control's fill, and its text stays black over the color and `.primary` past it.

## Proximity

Design two levels for anything glanceable. From across the room show one big fact (time, temperature, "Front Door Locked") much larger than up close. From arm's length show detail and controls. Check both with `-HomePadProximity far` and `-HomePadProximity near`, and the move between them with `-HomePadSimulatePresence`.

The change is one continuous move on `Theme.Motion.proximity`: the big fact glances smaller and slides aside as the detail fades in.

- Keep the text that shows at both distances as one view and change its size and place. Draw it at its far size and shrink it with `scaleEffect` and `position`, or give it an animatable font size. A changed font size or a view swapped with `if` jumps instead of moving.
- Fade in only what is new up close (the date, events, seconds), late in the move once the big fact has made room. Faded in from the start, detail shows through the big fact still sitting where the detail lands. Widgets a person chose stay at every distance, and the big fact leaves room for them.
- `ProximityAdaptive` crossfades two separate views. Use it only when far and near share no text, since two copies of a time or a temperature blur through each other.
- Faces get the curve from their host. Anything else applies `.animation(Theme.Motion.proximity, value: proximity)` once, not a curve per part.

## Walk-up sizes

HomePad hangs on a wall or stands on a counter. People use it standing at arm's length, 50 to 70 cm away, often in passing, and read it from a few steps back. An iPad in the hand is about 35 cm away, so anything sized for the hand reads about half as large here. These are the floors at the default text size (Match iPad, where Body is 17 points). The larger curated text sizes scale them up.

Where the numbers come from:

- **Apple's guidance.** The HIG's smallest target is 44 by 44 points on iPadOS and 60 on visionOS, where pointing is less precise. iPadOS body text is 17 points, and tvOS, read from across a room, uses 29.
- **HomeView.** Measured from Apple's product images and converted to their size on an 11-inch iPad Pro (one point is 0.19 mm): round buttons about 55 points, the segmented control 48 tall, the recipe card's action capsules 82 tall, button, row and secondary text about 21 points, and section titles about 34, taken from Apple's recipe card and near Weather images. Its 7-inch screen is 1088 pixels square at 220 ppi.
- **StandBy.** Apple's other display read from across a room shows a few facts in large type and leaves small text out.
- **Reading distance.** Text stops reading comfortably when its lowercase letters fall under about 0.2 degrees of view. At 60 cm that is SF Pro at about 20 points (Title 3), and at 50 cm about 17 (Body).
- **Kyle's read.** Music's mini player, a 72 point bar with 17 and 15 point text, is too small.

### Touch

| Where | Smallest target | Token |
|---|---|---|
| Controls on an app screen, panel, widget, Control Center, or a sheet used standing: buttons, chips, list rows, sidebar rows, segment options, swatches | 64 | `Theme.Size.tapTarget` |
| Header and sheet header items, close and back buttons | 48 | `Theme.Size.toolbarItem` |
| Dense chrome used up close: the top pills, items in a toolbar group, editor handles, map pins | 44 | `Theme.Size.minTapTarget` |

- `GlassIconButton` defaults to `tapTarget` and `GlassCapsuleButton` to `.large`, the walk-up sizes. Pass a smaller size only for the third row of the table.
- On a screen, use `ChoiceChips` for a short choice, never a system segmented control, slider or stepper. A system segmented control is 32 points tall, and 46 at `.controlSize(.large)`, still under the floor. They belong in forms, at the large size.
- A control drawn smaller than its target, like the transport in a small widget, pads its touch area out to the target without moving anything: pad it, set `contentShape`, then take the padding back.
- Rows in a list or a sidebar are at least `tapTarget` tall, like Settings rows. Several controls in one row (a Smart Rotation rule) each get a line that tall.

### Text

| Role | Smallest | Token |
|---|---|---|
| The one big fact on a glance surface | Large Title (34) and up | `Font.glanceTitle`, `Font.display` |
| A section title over tiles or rows | Title 3 semibold (20) | `SectionHeader` |
| Primary text: the name of a thing in a tile, row or card, a button or chip label, a value | Title 3 (20) | `Font.tileTitle`, `GlassCapsuleButton` `.large` |
| Secondary text: status, subtitle, time, place, a line under a control | Body (17) | `Font.tileDetail` |
| Dense overviews: a month grid, a floor plan, a map, the Home app's accessory tiles, small widgets, uppercase badges | Subheadline (15) | |
| Fine print nobody needs at a glance: data attribution, legal text, Settings footers | Footnote (13) | |

- Caption and Caption 2 (12 and 11 points) never appear outside debug overlays.
- Headers keep their Headline toolbar text and their 48 point items. See [Headers](#headers).
- Something that lists items gets fewer items, not smaller text. Fit as many as the frame holds with `ViewThatFits` over counts, as Up Next, Timers and the month grid do.
- Proximity moves sizes up from these floors for across the room, never below them up close.
- Settings' forms and forms in sheets keep the system's text sizes, since they are read up close on purpose. Settings rows are `tapTarget` tall (see [Settings spacing](#settings-spacing)). The Settings sidebar's names are Title 3, like Music's, since the sidebar is how people find their way.

### Symbols

- A symbol that carries meaning is at least as large as the text beside it. A status dot is at least 11 points.

### Checking

Shoot every change on the 11-inch in landscape (1210 by 834) and at the Extra Large text size. No title may be cut off that fit before, and every list still shows at least one whole item. Where a name no longer fits, let it take a second line or shrink a step (`minimumScaleFactor`, a tighter `ViewThatFits` variant) before it is cut off.

## Navigation

- **Leaving is top right, everywhere.** The control that leaves an app or a full-screen surface is a `CloseButton` (glass xmark, `toolbarItem`) in the top right corner, its edges 64 points from the right and 44 from the top: the shell's `screenMargin` plus `Theme.Spacing.l`. `AppScreen`, `AppHeader` and `DetailHeader` put it there, and the shell adds it for apps that draw their own chrome (`AppContainerView`, as for Mirror). Never put it top left or in a system toolbar. An app's own close button shows only when `\.showsAppCloseButton` is true (Show Close Buttons, off by default), since a swipe up from the bottom edge closes any app. Sheets, details and overlays always keep theirs.
- **Back is top left.** Going back a level inside an app (`onBack` on `AppScreen` and `AppHeader`) stays before the title, as on iPadOS. A NavigationStack's own back button is fine there too.
- **Header actions sit just before the close button**, in `accessory` or `trailing`. See [Headers](#headers).
- **Full-screen covers** apply `.coverScreenMargin()` so their close button lines up with every other screen, and `.coverHomeBar()` so the home bar goes Home from them as from the app. Going Home closes what the app presented once its window has landed, so the app opens again on its page.
- **A full-screen surface opened from a view** (a player, a photo, a camera) draws over that view, or presents over the app that opened it (`AppDescriptor.presentsOverOpener`), so swiping it down shows what it covers and closing finds it exactly as it was. See [Gestures](#gestures).
- **Apps reopen where they were left.** What a person chose (view mode, filter, sort, tab) and where they were (the date, the open album, recipe, room or pane) go in `@AppState`, never in `@State`, which starts over each time the app opens. Personal apps keep it for each recognized member. A date is a time position and goes back to today after a few hours or the next day, keeping the view mode. Something restored that is gone or hidden from this person falls back to the app's default, a launch argument or a request naming what to show wins, and no app reopens straight into the iPad's own camera.
- **Settings** draws the standard header row ("Settings" and the close button) across the top, with two plain columns under it on `Color.groupedBackground` (black in Dark, light gray in Light): a sidebar of sections with a quiet gray highlight (see [Settings spacing](#settings-spacing)), and the chosen pane in its own `NavigationStack`. Each pane's title heads the detail column (`inlineLarge`), below the Now Playing pill. It is not a `NavigationSplitView`: the system's glass sidebar started abruptly under the header and its columns did not fade in with the app.

## Gestures

HomePad keeps its gestures few, and each means the same everywhere. A new one needs Kyle's go-ahead.

| Gesture | Where | Does |
|---|---|---|
| Down from the top edge, right third | Every screen | Opens Control Center (`EdgeGestureLayer` in the shell) |
| Down from the top edge, left or center | Every screen | Talks to the assistant (the shell) |
| Up from the bottom edge | Every screen, and an app's full-screen covers (`coverHomeBar()`) | Goes Home, or opens the app grid on the Home Screen |
| Press and hold | The face | Opens the Faces app |
| Sideways | Home Screen pages, faces, cooking steps, the Photos viewer | The next or previous page |
| Sideways | Music's mini player | The next song (left) or the one before (right), as in Apple Music and CarPlay. The cover and title follow the finger a little and spring back (`MiniPlayerSwipe` in HomePadAudio) |
| Up or down | A widget stack on the Home Screen or a face | The next or previous widget in the stack, as an iPadOS Smart Stack. See [Smart Stacks](#smart-stacks) |
| Down on a full-screen surface | Now Playing, the Photos viewer and slideshow, a camera full screen, an accessory's or group's controls, the Play On panel | Closes it, back to where it was opened |

Controls keep their own drags. A `BigSlider` (Control Center's sliders, the Now Playing widget's volume) takes the touch as the finger lands, and SwiftUI gives a view's own gesture precedence over those around it, so the pages, a stack's swipe, a widget's tap and the holds that edit the Home Screen or open Faces never see it. A light's row in a widget slides only after a short hold (`accessoryLevelDrag`), so a quick swipe on it still turns the page or flips the stack.

A stack's swipe is a vertical paging scroll view inside the horizontal pages, so each drag goes to the one along its axis: up and down flips the stack and never moves the page, and sideways from a stack still turns the page. The edge swipes start in strips along the screen's top and bottom edges, outside every stack, so a swipe in a stack never opens Control Center or goes Home. A swipe is not a tap, so it opens no app, and in edit mode the stack takes no touches, so a press lifts it and a tap opens Edit Stack.

### Swipe down to close

- **What gets it.** Surfaces opened from a view or a control they go back to: a player, a photo, a camera, an accessory's or group's controls. Use `.swipeDownToDismiss(isEnabled:style:onDismiss:)`. Not apps opened from the Home Screen (swipe up goes Home), pages with a back button, editors with unsaved changes, alerts that need an answer (the doorbell, a finished timer, a smoke alarm), live scans, chats or web pages.
- **It goes back to the state before.** Draw the surface over the view that opened it rather than replacing it, so the page, the album and the scroll position are still there. Music's full-screen player is a real presentation that zooms out of the mini player, so iPadOS handles the drag down and its own menus open over it. An app that presents over another (`presentsOverOpener`) keeps that app alive underneath. The Photos viewer also scrolls the grid to the photo on screen and shrinks back into its thumbnail.
- **It moves like iPadOS.** The surface follows the finger, shrinks toward 90 percent and rounds its corners while the black backdrop fades and what it covers shows through. Letting go past 140 points, or with a downward flick faster than 700 points a second, slides it away. Anything shorter springs back on `settleSpring`, at the finger's speed. With Reduce Motion it fades in place instead. The values live in `SwipeDismissPolicy`.
- **It moves as one card.** The card's outline and the content move and shrink together, and the page's color reaches the card's rounded edges, the shell's margin included, for the whole pull and the spring back. The page itself never moves or scales: it stays where it is and shows through the card, and only its content (`.fullScreenSurfaceContent()`) moves and scales. A scaled page loses the safe area and stops at the margin, and a page moved down stops at its own top edge. Keep a full-screen surface's page a plain color, since a picture behind the content would stay still inside the moving card. A glow or picture that belongs to the card, such as an accessory's color glowing from the top, goes in `.fullScreenSurfaceContent(background:)`, which draws it behind the content to the screen's edges and moves and shrinks it with the card.
- **It leaves other drags alone:**
  - Drags starting within 44 points of the top or bottom of the window are left to the edge swipes.
  - A drag starting on a control, such as a slider, an accessory's level, a scrubber or a video's controls, stays with the control.
  - In content that is not scrolled to its top a pull down scrolls, as in an iPadOS sheet. At the top the pull closes.
  - Sideways drags page or do nothing.
- **Paging and closing never fight.** A drag locks to the axis it starts along: `DirectionalPan(.horizontal)` pages, `DirectionalPan(.down)` closes. A surface that closes into something, like the Photos viewer, builds on those two and `SwipeDismissPolicy` so it feels the same.
- **It never starts the assistant**, and taps work everywhere.

## Headers

Every app's top row is the same header, modeled on iPadOS 26 Liquid Glass toolbars and fitted around the pills the shell draws at the top center of every screen: Now Playing while music plays, and the soonest running timer (about 100 to 170 points wide together in apps, 30 to 74 points from the top, as tall as `minTapTarget`). Beside a timer the Now Playing pill shrinks to its cover, so the pair stays inside the zone below. A screen that shows its timers itself, such as cooking mode, applies `.showsRunningTimers()` and the timer pill steps aside.

- **The center is reserved.** `AppHeader` and `DetailHeader` lay their row out in two halves around `Theme.Size.nowPlayingZone` (176 points: the pill plus `Spacing.l` each side). Nothing in a header may enter that zone, whether or not music plays, so the layout never jumps when the pill appears.
- **Title leading, toolbar trailing.** The leading half holds the back button, the title (`Font.screenTitle`) and the title accessory. The trailing half holds the toolbar and the close button. Each is proposed only its half.
- **One item size.** Every item, the back button and the close button are `Theme.Size.toolbarItem` (48) tall: Apple's 44 point bar items plus 4 for a display tapped at arm's length. Symbols are 20 points semibold and titles are `.headline`, Apple's 17 point bar text in semibold. Titles longer than 260 points are cut off, so a speaker name never fills the toolbar. Header controls are used at arm's length, so they stay compact and leave the room-reading size to content. Header text stops growing at the Huge text size (`xxxLarge`).
- **Groups.** Related icon buttons share one glass capsule (`ToolbarGroup`), as previous, Today and next do in Calendar. Unrelated items are separate glass shapes `Spacing.s` apart, inside one `GlassEffectContainer`. The close button is always the rightmost item, on its own.
- **One prominent action at most**, filled with the app's accent (`isProminent`, `\.appAccent`): Add Event, Add City, Play Slideshow, Add Favorite, or Done while editing. Everything else is plain glass.
- **Pickers sit by the title, actions in the toolbar.** A choice of what the screen shows (Day, Week or Month, a clock style, whose faces, a music source, an AI provider) is a `HeaderPicker` in `titleAccessory`: a menu that shows the current choice with a chevron. Segmented controls are too wide for a half and do not go in headers.
- **Running out of room** works like an iPadOS toolbar. The trailing half tries four stages and uses the first that fits: everything, then text buttons with a symbol show only the symbol, then items marked `.toolbarItemPriority(.low)` move into a More menu (an ellipsis at the start of the toolbar), then everything but the prominent action moves there. The leading half shows pickers as their symbol, then lets the title shrink to 70 percent and cut off. Every action stays reachable and keeps its VoiceOver label.
- **What goes in a toolbar.** `GlassIconButton`, `GlassCapsuleButton`, `HeaderMenu`, `HeaderPicker` and `ToolbarGroup` know how to draw themselves in the bar and in the More menu. Pass them without a stack around them. Wrap anything else (`PhotosPicker`, `ShareLink`) with `.buttonStyle(.glassIcon())` and `.headerItem()`.
- **Full-bleed apps** keep the header too. Weather draws its sky behind an `AppScreen`.
- **Sheets** have the same header, drawn by `SheetScreen`, and never Cancel and Done in their corners. The title is leading. The toolbar ends with the close button, which also cancels. The action that commits the sheet (Post, Add, Save) is the one prominent item, in the app's color, and it stays in place dimmed while it cannot run, such as Post for an empty note. Use Done only when no verb fits. A sheet whose changes apply as they are made (Wallpaper, Calendars, Favorites) has no action, only the close button. UIKit presents sheets above the shell, so the Now Playing pill never covers one, and a sheet's row keeps no zone for it. Its sides are `Spacing.l` apart and the toolbar takes what the title leaves, so beside a short title an action keeps its words ("Add 3 to Groceries"). A long title keeps 60 percent and shrinks, the toolbar never gets less than the 160 points Post and the close button need, and a sheet with only the close button gives the title the rest. The title is measured on its own and each side still has a fixed width, so the toolbar stages are measured at one width as in every header. Keep a sheet's toolbar to its one action where you can, and put the rest in its content: in a form sheet (580 points wide) a second item can leave the action only its symbol. A page pushed inside a sheet's `NavigationStack` gets a back button (`onBack`) and the same close button. `.searchable` has no navigation bar to sit in, so a sheet puts a `GlassSearchField` first in its content. Present a sheet or a confirmation dialog from the screen or from the row that opens it, never from a `Section`. A section hands its modifiers to every row: several sheets on one binding present none, and a dialog still opens, but on iPad its popover points at another row of the section. An alert has no arrow, so one on a section works.

## Settings spacing

Settings keeps the system `Form` and `List` in the app's appearance, and gives every pane the same room (`SettingsPaneLayout` in the shell):

- Rows are at least `Theme.Size.tapTarget` (64) tall, so they are easy to tap from arm's length.
- Sections sit `Theme.Spacing.xl` (36) apart.
- The detail column gets `Theme.Spacing.xs` of extra safe area at the sides. With the Form's own section inset (16 in a narrow column, 20 in a wide one), cards sit about `Theme.Spacing.l` from the sidebar and about 64 points from the screen's right edge, in line with the close button.
- The sidebar takes about a third of the width (`SettingsSidebar` in the shell): 300 points in portrait, where the panes need the room, about 360 on an 11-inch iPad in landscape and 400 on a 13-inch.
- Sidebar rows use `.buttonStyle(.sidebarRow(isSelected:))`, so they are `Theme.Size.tapTarget` tall like the panes' rows and `Theme.Spacing.sidebarRowGap` apart. Their names are Title 3 beside a 36 point `SettingsIcon`. In landscape they do not all fit, so the sidebar scrolls, and it brings the chosen row into view.
- Forms stay full width in the detail column, like iPadOS Settings. A centered narrow column would leave the system large title stranded at the leading edge.

Panes do not add their own `contentMargins`, horizontal padding or row heights. Content margins also reach the sheets a pane presents, which squeezes their forms by the sidebar's width.

## Layout

- Every screen pads `Theme.Spacing.l` inside the shell's `screenMargin`, so content starts 64 points from the sides and 44 from the top on every screen. Respect the safe area for content and ignore it only for backgrounds.
- Grids use `Theme.Spacing.l` gutters. The Home Screen has six columns in landscape and four in portrait, one fewer at the largest text sizes.
- A horizontal pager reaches the screen edges and pads each page by the margin itself, so a page is exactly one screen wide. A scroll view that stops at the margin still draws into it, and the edge of the next page shows there.
- Widget sizes are small (1x1), medium (2x1), large (2x2) and tall (2x3) cells. Tall is for a widget whose extra height shows more, never the same content drawn bigger: Home Favorites shows more controls, Up Next goes on into tomorrow, Reminders lists more. A widget opts into it in `supportedSizes`, which is `WidgetSize.standard` (small, medium, large) by default. Draw a widget to fill its frame and let the shell clip it to `Theme.Radius.tile`. On a face, widgets sit on the face's own grid, six cells by four in landscape and four by six in portrait, at every distance (see the HomePadFaces README).
- Controls that share a widget sit `Theme.Spacing.controlGap` apart, inside the tile's `Theme.Spacing.m` padding, with `\.controlCornerRadius` corners. Never pick a tighter gap for one widget: Favorites at 6 next to Scenes at 10 read as two designs.
- Keep the top center of an app empty. The timer and Now Playing pills appear there (compact inside apps), and headers leave `nowPlayingZone` free for them. Content below the header row can use the full width.
- Support portrait and landscape. Never fix a width to a device size.
- Kyle's iPads run in landscape: 1366 by 1024 points on the 12.9-inch and 1210 by 834 on the 11-inch M4, less 20 points at the bottom for the home indicator and the shell's `screenMargin`. Design for that first.
- Front cameras sit on the short edge on older iPad Pros and on the long (landscape top) edge on the M4. Never assume either. Rotate camera images with `AVCaptureDevice.RotationCoordinator` (`CameraPreview` and the presence `OrientationTracker` do).
- Use landscape width with intent: panes side by side (`AdaptiveStack`), larger controls, more columns. A narrow centered column with empty sides, or a few small cards in a corner, wastes the screen.
- Size from the space you have. When a screen shows a handful of things (recipes, clocks, cameras), read the size with `GeometryReader` and pick the columns and tile size so they fill the screen. Many things can scroll.
- Things with a size of their own keep it, however few there are. Family Board notes are the size of a sticky note: columns that aim for about 13 characters of note text a line and widen with the text size, each note as tall as its text, from half its width up to six lines. One note is a small note at the top of the board, not a card that fills the screen. See the Connect README.
- A widget that lists things shows as many whole items as its frame holds, like Up Next, Timers and the Family Board (`ViewThatFits` over counts), and Up Next and the Family Board count the rest in their header. Faces give widgets frames of other shapes than the Home Screen does, so size from the frame, not from the `WidgetSize`.
- Anything on a page that scrolls stays cheap to move. No `.shadow` on icons or tiles, and a label that needs one uses `wallpaperLabelShadow()`, which draws it once. Other shadows near motion (faces, artwork) use `flattenedShadow(color:radius:y:)`, which also draws once. Live shadows are redrawn on every frame, and a page of them made the Home Screen page at 49 fps on an M4 iPad. `HomeScreenScrollPerfTests.testPagingHitchesOnDevice` measures paging on a device.
- Nothing may run off the bottom. Content that might not fit scrolls (`ScrollView`) or scales (`minimumScaleFactor`). Check at the Extra Extra Large text size too.
- Check every screen with `-HomePadForceLandscape YES` on both the 13-inch and the 11-inch simulator (rotate the screenshot 90 degrees clockwise), and in portrait. Forced landscape cannot give UIKit-backed navigation (Settings, Camera Lab) the shell's margin, so check those in portrait.

## Do

- Use `AppScreen` for every app and let the shell provide the close action. Use `DetailHeader` for a full-screen detail inside an app, and `SheetScreen` for every sheet.
- Keep the close button top right and back buttons top left.
- Use tokens for every spacing, radius, size and font.
- Use system components (Form, List, pickers, `PhotosPicker`, `MPVolumeView`, LocalAuthentication) and present them as sheets in the app's appearance.
- Offer a few curated choices with great defaults.
- Write labels in plain sentences, with no em dashes and no semicolons.

## Don't

- Don't hard-code colors, radii, fonts or sizes.
- Don't draw a second close button inside an `AppScreen`, and don't hand-roll round glass buttons, banners, pills or permission prompts.
- Don't put a close button top left or in a system toolbar.
- Don't hard-code black pages, white text or `.preferredColorScheme`. Use the adaptive colors, and keep fixed black and white for content (see [Light and dark](#light-and-dark)).
- Don't animate continuously on the face except slow drift. It costs power and attention.
- Don't scale a view whose background ignores the safe area, with `scaleEffect` or a `.scale` transition. While the scale is not 1 the background stops at the shell's margin, and the margin shows what is underneath. Moved down with `offset`, the background stops at the view's own top edge in the same way. Zoom and move the content only, as `.fullScreenSurface` and `.swipeDownToDismiss` do.
- Don't put personal data on a surface without checking `household.isPersonalContentUnlocked`.
- Don't put text under the [walk-up floors](#walk-up-sizes) on a screen people stand at: nothing below Body for information, nothing below Subheadline even in a dense overview, and never Caption.
- Don't size a control on a screen below `Theme.Size.tapTarget`, and don't use a system segmented control, slider or stepper outside a form.

## Adding components

A module that needs a generic-looking component HomePadUI lacks builds it under `Views/Components/` with a doc comment saying "candidate for HomePadUI", using the tokens above. The lead promotes it into the right folder here, migrates every caller, deletes the module copy and adds a row to the tables above. Components that carry one module's identity, such as the assistant's orb and edge glow or the intercom's push-to-talk button, stay in their module.
