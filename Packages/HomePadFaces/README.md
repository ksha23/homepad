# HomePadFaces

The always-on faces, HomeView's signature feature, plus the Faces app (My Faces and the face editor), the Faces settings pane and the Clock widget.

## Faces

Every face supports the red night palette (`\.displayCondition == .night`), all in one red, and at night the face on the wall keeps its far layout whoever walks up, like HomeView's night face (`HostedFace.shownProximity`). Every face shows one big fact from across the room and the detail up close (`\.proximity`, see [Far and near](#far-and-near)), works in landscape and portrait, and redraws as rarely as it can (once a minute, once a second only when someone is close). Motion (Flow, clouds and rain, Sprig, Ken Burns) holds still in thumbnails, behind the Home Screen, beside the face on the wall and while the display is dimmed, red for the night or asleep (`FaceCadence`, `faceAllowsMotion` over Core's `allowsContinuousMotion`). Behind the Home Screen a face shows only its picture or background (see [Behind the Home Screen](#behind-the-home-screen)).

| ID | Face | What it does |
| --- | --- | --- |
| `faces.auto` | Smart Rotation | Picks a face by rules: doorbell rang, night mode, a recognized person's own face, mornings, then a fallback. |
| `faces.modular` | Modular | Far: the date and an analog or digital clock filling the face, or the part beside its widgets. Near: they move to the top half, with today's events and the forecast (or only one of them) under them. The default face. |
| `faces.homeModular` | Home | Tiles for accessories and scenes (tap to toggle, thermostat up and down, lock state), a clock, a camera, Intercom and the Home app. Tiles that are on fill with the accent, and tiles that are off are neutral gray with gray symbols, like HomeView's. Far, and always at night: symbol, name and fill, a lock's state, and the camera's picture alone, refreshed every few seconds. Near: every tile's status, the camera live with its name (WebRTC for Home Assistant cameras, as on the Cameras face) and the clock's second hand. Up to eight chosen tiles in order, or the Home favorites when none are chosen. The camera can be chosen too. |
| `faces.cameras` | Cameras | Up to nine cameras, chosen and ordered in the editor or the first nine. A doorbell that just rang moves to the front. Tap opens the Home app's cameras. Far, and always at night: snapshots alone, refreshed every few seconds, almost to the screen's edges with thin dividers, like HomeView's, keeping the burn-in overscan. Near, with the screen on: rounded feeds inside the face insets, with live video, names and times. Home Assistant cameras play over WebRTC without sound, falling back to MJPEG and then stills (the Smart Home module's README has the order). Only the feeds on the face stream, and none while the doorbell screen covers it. |
| `faces.photos` | Photos | Ken Burns slideshow of featured photos, the whole library, favorites, Portrait mode photos, an album (iCloud Shared Albums too), picked photos or one framed photo, with the time drawn behind the subject in frosted glass, like HomeView's. Photos only, never videos. Far: the time as large as the face allows, centered in the face's height like HomeView's, or at the top above widgets along the bottom. Near: the time about half that size under the date, the two centered together. |
| `faces.weather` | Weather | Animated sky for the condition and time of day, at the iPad's location or a chosen city. Far: the place, a big frosted glass temperature and the time in the top corner, as on HomeView. Near: the temperature and the time smaller, the temperature higher, and the hourly forecast. |
| `faces.calendar` | Calendar | Month grid with today circled and drawn large behind the grid, filling the face from afar, with today's events beside it up close. Up Next shows the date in large type, centered from afar and beside today's events up close. |
| `faces.flow` | Flow | Swaying mesh gradient with the time built from Liquid Glass drops, like HomeView's: a 1 is a tall slab with a dot, a 0 a rounded block, 6 and 9 a bowl with a slab and a dot, the colon two small spheres (`FlowGlyph`). In one line in landscape, the hours over the minutes in portrait (`FlowClockLayout`). The drops bob gently and the digits change once a minute. Richer, and the time larger, as you approach, a ripple on motion. |
| `faces.analog` | Analog | Large numerals pressed into the surface, following the face's rounded edge like HomeView's, so a landscape screen's sides are not empty (or smaller ones around a ticked dial, the Precision style). While the face has widgets, the numerals keep inside the dial's cells. Near: second hand and date. |
| `faces.numerals` | Numerals | Giant overlapping 12, 3, 6 and 9 with bold hands. Near: second hand and date. |
| `faces.digital` | Digital | Big rounded digits, alone from afar. Near: smaller, with the date, seconds and weather. |
| `faces.fade` | Fade | Sundial: numerals near the hour are lit and the light sweeps across the day. Near: second hand and date. |
| `faces.worldclock` | World Clock | Up to six cities with day and night dials (or digits) and names. Near: smaller dials with each city's time and offset. |
| `faces.night` | Night | A minimal dim red clock for bedrooms. Near, outside night hours: smaller, with the date and temperature. |
| `faces.critters` | Critters | Sprig, an original sprout creature drawn in SwiftUI shapes, beside a giant date or time. It sleeps, stretches, reads, holds an umbrella, dresses up for holidays and cheers when a timer finishes. Near: the date or time smaller, with a date and weather line. |

## Customization (curated, like watchOS)

- Each face declares a few `FaceOption`s: style variants, colors (below), slots (cities, accessories and scenes, cameras), or a custom page (photo source, rotation rules). No free-form colors or fonts. Every face but Smart Rotation ends with a Widgets page (see [Widgets](#widgets)).
- An empty choice means automatic, so a saved face without a value for an option still looks right: no tiles chosen shows the Home favorites, no cameras the first nine, no city the iPad's own weather. A slot with an automatic meaning says so (`FaceSlot.automaticTitle`, such as Automatic or Current Location). Chosen items that no longer exist are skipped, and when none is left the face is automatic again. New options store under new keys of the face configuration.
- Accessories, scenes and cameras in slots are saved by the ID of the HomePad they were picked on. HomeKit's differ from iPad to iPad, so the Home and Cameras faces and the editor's slots read them through `services.smartHome.localID(for:)` (`HomeTile.localID`, `SlotItem.localID`), and a face picked on one HomePad shows the same tiles and cameras on the others.
- A saved face is a `FaceConfiguration`. `FaceLibrary` keeps a saved list per owner: the household, or a member who edited their own. Untouched defaults look finished.
- The current saved face is mirrored into `CoreSettings.defaultFaceID` (household) or the member's `HouseholdMember.facePreferenceKey` preference (`faceID`), so the shell knows which kind to show.
- **The same on every HomePad.** Each owner's saved faces, with every option, widget layout, stack and mini widget, which face is current, and the Smart Rotation rules are shared with the household's other HomePads (`FaceSharing`, Core `SharedDocumentDescriptor`s that Connect carries over the peer link, see "The household's setup" in its README). Swiping to another face or editing one on any HomePad shows there on the others a moment later. Each HomePad sets the mirrored face kind from what arrives, so that kind is not shared itself.
- A Photos face's album, picked photos and one framed photo name photos in this iPad's library, so they stay on it (`FacePhotoPicks`). The source kind is shared: a face set to an album here shows Album on the others, where someone picks the album from that iPad's library, and each keeps its own picks when the face changes elsewhere.
- A face widget with Same on All HomePads off (on its Edit Widget page, while this HomePad shares its setup) keeps its own settings on each HomePad, such as Home Favorites with each room's lights, while where it sits and its size stay shared. In a stack each widget has its own switch. `FaceSharing.readLibrary` shares the copy each such widget had when its switch went off, which an older HomePad shows, and `applyLibrary` keeps this iPad's own when faces arrive, found by the widget's mark in the faces this iPad shows for that owner now. So a person's first own faces, copied from the household's, keep each HomePad's settings too. See Core's `WidgetSettingsOnEachHomePad.swift`. The mini widget has no settings, so it has no switch.
- They used to go through iCloud key-value storage, which reaches only one Apple Account and could overwrite a newer edit with an older copy. `FaceSharing` tells settings to ignore what an older HomePad still writes to iCloud for these keys.
- When this HomePad joins a household that already knew a person by another ID, that person's saved faces move to the household's ID (`FaceLibrary.moveOwner`), and the household's own replace them where it has them.
- On the wall the saved faces are pages, swiped between like the Home Screen's (`FacePager`): the face follows the finger with the next one beside it, a short slow swipe springs back, and a long or quick one settles on the next face. The faces go round: past the last comes the first, and back from the first comes the last. One saved face does not page. Once the pages come to rest, that face becomes the current saved face and the pager posts `.showFace(id:)` with its kind. A kind shown that has no saved face (the assistant can show any) gets a page after the saved ones.
- The pager lays out five pages, the face at rest and the two faces before and after it (`FacePageWindow.reach`), so a quick second flick, made while the first still glides, has a face to land on. With one face on each side it bounced back. When the pages rest on a face beside the middle one, the window moves along under it in the same update and the scroll offset moves with it, so the page on screen and its face are the same views and nothing on screen changes. With two saved faces the other one sits on both sides. Each page clips its face, so a face that draws past its edges (Flow's ripple) never shows on its neighbour.
- The page on screen lives in the pager, and only a request from outside moves it: the shell showing another kind, or another saved face of the kind on screen becoming current. Every kind registers the one view type `FaceHost`, so the shell switching kinds after a swipe keeps the pager and its page. The faces beside the one at rest are built while the pages rest, since building a face as a swipe revealed it held up the swipe's first frames. They hold still while none of them shows (`\.faceIsBeside`) and start moving as the first points of them show, so a face is already running when the pages rest on it. VoiceOver reads only the face on screen.
- The Faces app (app ID `faces`) is My Faces: a card for each saved face, drawn up close with its widgets as a picture of the face (see [Previews](#previews)), a checkmark beside the name of the face showing now, Add Face for the Face Gallery, and a picker for whose faces (Everyone or a person). Tap a face to show it. Customize under a card opens the editor, and holding a card offers Show Now, Customize and Remove. Holding the face on the wall opens this app (the shell's). It reopens on whose faces it was showing (`FacesAppState.owner`, an `@AppState` shared by the household, since anyone may pick anyone's faces), or Everyone once that person has left the household. The editor and the gallery are not reopened.
- Holding the face on the wall opens the editor for that face straight away (`FacesModule.editWallFaceID`, a redirect to Faces that sets `FacesRuntime.editsWallFace`), for the face showing for whoever the wall shows faces for (`FaceLibrary.activeOwner`). The editor is drawn straight in the app, not in a cover that slides up, and the shell fades the app in from the face instead of zooming it. Done, Show Now or the close button fade back to the face rather than going to My Faces. My Faces is the Faces app's own icon.
- The editor opens full screen: a big live preview laid out at the real screen's size, one page per option, swipe the preview to change pages, tap a card to pick a value, tap a slot to choose from a gallery (None empties it).
- Under the preview, Across the Room and Up Close show the face at either distance, moving between them like the face on the wall. A page whose option only shows at one distance can declare it (`FaceOption.previewDistance`), and the preview switches there while it is open. No face declares one. `EditorDistanceState` holds the rule.
- Choices that change the look show a small picture of the face with that choice applied (`FaceOption.cardStyle`). Choices a still picture cannot show (Weather's motion, Photos' shuffle timing) keep a symbol. Colors stay swatches.
- My Faces, the Face Gallery, the editor and its slot galleries follow the Appearance setting (Settings > Kiosk & Display): a white page with dark text in Light, black in Dark. Swatch rings, slot outlines and card borders use `.primary`. The faces in them are drawn as on the wall. The Widgets page's cell outlines and resize handle stay white, since they are drawn over the face. Framing the One Photo face stays dark, since it is the photo full screen.

## Colors

A face's Color page offers up to three parts, each from a short fixed list, as rows of swatches under the preview:

- **Background**: a `FaceColor` (Porcelain, Graphite, Ocean and the rest), stored under `color`. Each is a preset (`FacePreset`): the background with the text and accent colors designed with it.
- **Text**: Automatic (the preset's own) or a `FaceTextColor`, stored under `textColor`. Six light colors for dark backgrounds and six dark ones, which are the presets' own inks. Secondary text is the text color 40 percent of the way to the background, as the presets have it.
- **Accent**: Automatic or one of the eight member colors in `Theme.Palette`, stored under `accentColor` by swatch ID.

`FaceConfiguration.colors(_:)` reads the three (`FaceColorChoice`) and `FacePalette.resolve` turns them into what the face draws (`FaceColorSet` holds the numbers, so tests can check them). A face with no `textColor` or `accentColor` saved uses Automatic for both. Night mode draws the red palette whatever is chosen.

The readability rule keeps every combination legible. It measures WCAG contrast against both ends of the background's gradient, with 3 to 1 as the minimum (WCAG's floor for large text, and face text is large):

- A text color below it is unavailable on that background. The editor dims it with a stroke through it. If the background changes under a chosen text color, the face draws the preset's text and keeps the choice, which returns on a background it reads on.
- An accent keeps its hue but moves toward black on light backgrounds or toward white on dark ones, just far enough to reach the minimum. Its swatches show that shade.

Which parts each face colors:

| Face | Background | Text | Accent |
| --- | --- | --- | --- |
| Modular, Digital | yes | numerals and words | weekday or month, event bars and times, location, colon, AM or PM |
| Calendar | yes | today's circle, Up Next's day and month, and the events | the month and time, the big day, the grid's weekdays and days in bold (the background's color where they cross the big day), Up Next's weekday, event bars and times |
| Analog, Fade | yes | hands and numerals (still pressed into the surface) | second hand, and Analog's weekday |
| Numerals | yes | the four numerals | the hands (white while Automatic), weekday |
| Home | yes | the clock, and the text and symbols of tiles that are off (neutral gray while Automatic) | fill of tiles that are on, shown unshaded (`accentFillsTiles`), with black, white or the text color on it, whichever reads |
| Critters | yes | the date or time and Sprig's scenery | none |
| Flow | the mesh colors | none | none |
| Photos | the photo | the time: From Photo, or a light text color (option `tint`) | none |

Weather, Cameras, World Clock and Night keep their own colors.

## Widgets

Widgets from `registry.widgets` go on any face, sized and placed on a grid like widgets on the iPadOS Home Screen.

### The grid

- A face's grid (`FaceGrid`) fills its content area inside the face insets: six columns by four rows in landscape, four by six in portrait, `Theme.Spacing.l` apart. The counts are the same on every iPad, so a face shared with the household's other HomePads keeps its layout on an 11, a 12.9 and a 13 inch iPad. Cells come out nearly square, about 160 points on an 11-inch iPad and 190 to 210 on a 13-inch.
- A widget covers one cell (small), two side by side (medium), two by two (large) or two wide and three tall (tall), at the sizes its `WidgetDescriptor.supportedSizes` allow. Tall fits the widget column of the faces with a widget area in landscape and the three bottom rows of Photos in portrait. Where a face has no room for it, the gallery says so, and the other orientation steps it down to large (`FaceWidgetBoard.stepsDown`).
- Cells a face's own content needs are blocked, and no widget may cover them (`FaceGrid.blocked`). A cell is blocked when content reaches more than 6 percent of its shorter side into it.
- The cells under the Now Playing pill, at the top center, are blocked on every face, whether or not music plays (`FaceWidgetSupport.nowPlayingZone`). The grid is laid out from the face insets without the pill's room (`\.faceNowPlayingRoom`), so no widget moves when music starts or stops.

### How each face takes widgets

A face declares it in its definition (`FaceDefinition(widgets:)`, a `FaceWidgetSupport`). The face's content keeps its place whatever its widgets, and widgets show at every distance, so the cells a face blocks cover its content both across the room and up close.

| Face | Content | Widgets go |
| --- | --- | --- |
| Modular, Weather, Calendar, Home, Cameras, World Clock, Digital, Critters, Night | fills the screen, and keeps beside a widget area while the face has widgets | in a column of two cells on the trailing side in landscape, two rows along the bottom in portrait (`FaceWidgetArea`) |
| Photos | the photo full screen, the time above a widget area while the face has widgets | in the bottom row in landscape and the bottom three rows in portrait, where the time never reaches |
| Analog, Fade, Numerals | the dial stays put and blocks its cells (`FaceContentRegion`), and Numerals' date its corner. Analog's numerals follow the whole face without widgets and keep inside the dial's region with them (`\.faceHasWidgets`) | in a column on each side in landscape, in the rows above and below the dial in portrait. Mediums fit only in portrait |
| Flow | the time stays put and blocks its cells | above and below it in landscape, and beside it too in portrait |
| Smart Rotation | other faces | none of its own: the face it shows draws its widgets |

- A face with a widget area takes the whole screen while it has no widgets. With widgets, `HostedFace` adds the room they take to `\.faceInsets`, and the face lays its content out in the rest.
- Every face gets the room it keeps clear of in `\.faceKeepClear`: the widget area and the Now Playing pill. A face laid out by its insets needs nothing more. One that centers on the whole face sizes itself from what is left (`CGSize.leaving(_:)`). The dials shrink a little around their center for the pill rather than moving down, so they never reach a cell they did not block before.
- Night draws its widgets red at every hour, like the face (`isAlwaysNight`).

### Saving

- A face's widgets are `FaceConfiguration.widgetLayout`, a `FaceWidgetLayout`: a list of `FaceWidgetPlacement`s (widget, size and top leading cell) for each orientation.
- An orientation nobody arranged by hand shows the other one's widgets in reading order, each with no cell of its own. Widgets without a cell go together, in that order, into the narrowest band along the face's fill edge that holds them all (`FaceGridFill`): the bottom rows, or the trailing columns. So a few widgets sit against the edge and keep their order. Widgets anchored top leading (the [glance widgets](#glance-widgets)) take their corner first, and the rest fill their edge after them.
- Arranging a face in one orientation saves that orientation. A widget added there joins the other orientation with no cell, so it takes the first free area there, and a widget removed there leaves both.
- `FaceWidgetBoard` arranges saved placements on a grid. A widget placed by hand keeps its cell while that area is free and open. One that has no room steps down to a smaller size it supports. One that fits nowhere, or whose module is gone, stays saved and comes back when there is room, so nobody's choice is lost.
- This is also how a shared face lands on another iPad. Each iPad works out at its own size which cells the face's content needs, so a widget whose cell the clock reaches into on an 11-inch iPad but not on a 13-inch one waits in the nearest free area there and keeps its cell everywhere else. What was saved never changes because of the screen it is shown on.
- Each widget's own settings (Edit Widget) are `FaceWidgetLayout.widgetSettings`, by placement ID, once for both orientations, since a widget keeps its ID in both. They go when the widget leaves the face. Faces saved before settings have none and show what they did.
- A widget stack's widgets are `FaceWidgetLayout.stacks`, a Core `WidgetStack` by placement ID, once for both orientations, like settings. The placement itself names the stack's first widget, and `widgetSettings` keeps that widget's settings, so a HomePad from before stacks shows that widget in its place. A stack takes the sizes all its installed widgets come in (`FaceWidgetBoard.face`'s `stackSizes`). One with one widget left becomes that widget with its settings, and one with none leaves the face (`FaceWidgetLayout.setStack(_:for:)`). A stack goes with its placement. Faces saved before stacks have no `stacks` key and save without one.
- Older saved faces keep their widgets in the slots `widget1`, `widget2` and so on (four on Modular, three on Photos). `FaceWidgetMigration` turns them into placements in slot order, as medium widgets with no cell, so they land in the face's widget area. The editor moves them onto the grid and empties the slots when it opens such a face.

### On the wall and in previews

- `HostedFace` draws the widgets over every face (`FaceWidgetLayer`, `FaceWidgetTile`) at every distance, and the face's [mini widget](#the-mini-widget) in its top margin. Widgets keep their own buttons. The face's copy behind the Home Screen has none.
- Personal widgets follow `FaceWidgetAccess`: left out on the wall until someone is recognized, with their cells left empty so nothing moves, and drawn locked in previews (`LockedWidgetTile`, `facesKeepsPersonalPlaces`) so the layout is right without showing personal data.
- At night the widgets turn red with the face (`nightModeAware`) and dim further.
- Their glass takes its light or dark look from the face, not from the Appearance setting (see [Backdrop tone](#backdrop-tone)).
- Thumbnails draw the same layer, scaled, at the wall's size and insets, and a card's picture is taken of it (see [Previews](#previews)).

### Glance widgets

The shell's Glance and Home Status widgets (see the Shell README) summarize the day and the home, so they belong where a face is read first: its top left. Their descriptors say so with `WidgetAnchor.topLeading` (Core's `WidgetDescriptor.anchor`, `.faceFill` for every other widget).

- Added from the gallery, an anchored widget lands in the open area for its size nearest the grid's top leading corner, measured from the corner to the area's own (`FaceWidgetBoard.adding(_:size:id:anchor:)`). Ties go in reading order, so beside content before under it.
- A face whose content fills its top left puts it in the nearest open area instead: the top of the widget column on Modular and the other faces with a widget area in landscape (the top cell under the profile dot stays blocked, so a large one starts a row down), the first row of their widget rows in portrait, and the bottom row of Photos in landscape.
- Without a cell of its own, in the orientation nobody arranged, it takes the same corner there (`FaceWidgetBoard(placements:grid:fill:sizes:anchors:)`).
- It moves like any other widget in the editor afterwards, and every other widget goes where it always did. `FaceWidgetAnchorTests` checks both.

### Widget stacks

A face takes Smart Stacks as the Home Screen does (see "Smart Stacks" in HomePadUI's DESIGN.md): up to ten widgets of one size in one place (`FaceStackTile`, HomePadUI's `WidgetStackView`).

- **On the wall** a vertical swipe flips the stack, and the face's pages and its hold to choose a face never see it. A tap opens the app of the widget on top, which zooms out of the stack. Smart Rotate turns it to the widget that matters now and back.
- **Personal widgets** in a stack follow `FaceWidgetAccess`: left out on the wall until someone is recognized and drawn locked in previews. A stack with none of its widgets to show leaves its cells empty.
- **Previews and the editor** draw the widget the stack shows on the wall, still. The same stack in both places shows the same widget, since what stacks remember is shared (`AppServices.widgetStacks`).

### The mini widget

A face can have one [mini widget](../HomePadUI/DESIGN.md#mini-widgets) in its top margin at the leading side: the glance for now, always at its smallest size. It is off by default. A bigger glance is the Glance widget in the face's widget area.

- **Saved** with the face (`FaceConfiguration.miniWidget`, a Core `MiniWidgetPlacement`). Faces saved before it have none. A size saved by an earlier version is shown small.
- **Chosen** on the editor's Widgets page with Top Left (`TopLeftPicker`), a menu under the preview showing what is chosen ("Top Left: Glance"): None or a mini widget. There is no size to choose.
- **Placed** in the face's top margin (`FaceMiniWidgetLayer`, `FaceWidgetSupport.miniWidgetFrame`): a 36 point capsule (`miniWidgetHeight`) ending where the face's content starts (`Theme.Spacing.screenContent.top`, 44 points from the top), and from the shell's leading margin across to `Spacing.l` short of the Now Playing pill's zone, whether or not the pills show. No face lays anything out there, so no face and no widget moves for it, and the grid is the same with or without it. One line, with `Spacing.s` above and below its text and `Spacing.m` at its ends, on the glass the face's widgets are on (HomePadUI's `widgetGlass(in:)`, the same as `GlassTile`): darker over a dark face, light with dark text over a bright one. It hugs what it shows and shows fewer things before it would grow past its room.
- **Drawn by `HostedFace`** with the face, beside the widget layer, rather than by the shell like the profile dot. It belongs to the saved face, so it pages with the face, drifts with it, and shows in My Faces, the editor's preview and its Widgets page as on the wall. It is left out behind the Home Screen's frost. At night it turns red with the face, and on Night at every hour, like the widgets. Smart Rotation has none of its own: the face it shows draws its own.
- **Taps** on its parts open their apps on the wall only, as the widgets do (`.openApp`), and each part reports itself as a zoom source. Previews take no taps. The glance leaves out calendar, reminders and messages until someone is recognized.

### The Now Playing and timer pills

While music plays or a timer runs, the shell draws the Now Playing and timer pills at the top center of the face and adds their room (`\.faceNowPlayingRoom`) to the top of `\.faceInsets`. The face's content glides down as the first pill comes in and back as the last goes. Widgets never move for them, because the cells under the pills are blocked on every face.

### The Widgets page

The editor's Widgets page turns the preview into the place to arrange widgets, like the iPadOS Home Screen in jiggle mode (`WidgetEditCanvas`, `WidgetEditSession`, `EditableWidgetTile`):

- Every widget wiggles and has a minus badge that removes it.
- Drag a widget and it lifts, a little larger, and follows the finger. Where it would land is outlined, the open cells show faintly, and the cells of the face's own content show nothing. It snaps to the nearest area it fits, so over the clock it lands beside it. Widgets it lands on move aside to the free area nearest where they were, and when one has nowhere to go that spot is not offered. Letting go settles it in place.
- Tap a widget to select it. A white arc on its bottom trailing corner is the resize handle. Dragging it snaps between the sizes the widget supports and has room for, growing up or toward the leading edge at the grid's edge and pushing others aside.
- Top Left beside Add Widget picks the face's [mini widget](#the-mini-widget). The preview shows it.
- Add Widget's gallery offers a Smart Stack first, prefilled for its size with the widgets that can say when they matter (Core's `WidgetStack.suggested`). It lands in the first free area, selected. When the selected widget is a stack, Edit Stack appears beside Add Widget (`FaceEditStackSheet`, HomePadUI's `EditStackSheet`): its widgets to reorder, remove or open in Edit Widget, Smart Rotate, and widgets that can join it. The preview shows each change at once, and Done keeps them with the face. A stack moves, resizes between the sizes all its widgets come in, and is removed like any other widget.
- When the selected widget has settings, Edit Widget appears beside Add Widget under the preview and opens them (`FaceEditWidgetSheet`, HomePadUI's `EditWidgetSheet`): Home Favorites picks its accessories and Reminders its list. The preview shows each change at once, and Done keeps them with the face's other changes, Same on All HomePads included. A personal widget's Edit Widget stays off while nobody is recognized, as its preview stays locked.
- Add Widget under the preview opens the widget gallery (`FaceWidgetGallerySheet`, HomePadUI's `WidgetGallery`): every widget as a big live preview at its size on this face, then its sizes to swipe through and Add Widget. A size the face has no room for keeps Add Widget off with the reason. The new widget goes in the first free area, or nearest the top leading corner for a [glance widget](#glance-widgets), and is selected.
- Landscape and Portrait beside the distance pick the orientation to arrange, so a portrait layout can be set on an iPad mounted in landscape.
- VoiceOver offers Remove, Make Small, Medium, Large or Tall, and Move Up, Down, Left or Right on each widget.

## Far and near

From across the room each face shows one big fact, much larger than up close (HomeView's distance-aware faces). Up close the same view glances smaller and moves aside while the detail fades in: the date, events, seconds. Widgets stay at every distance, and the big fact leaves room for them.

Up close means within reach: the face on the wall is `.near` under about a meter (`ProximityLevel.near`) and `.far` at any distance past it, with nobody in view, or at night (the shell's `KioskController.faceProximity`). Faces test `proximity >= .mid`, so they see two looks. Counting the middle of the room as up close (`.mid`, up to 2.5 meters) showed the near look to anyone in the room, and the far look only to an empty one. Apps and the Home Screen keep three walk-up sizes.

- `HostedFace` animates every proximity change on one curve, `Theme.Motion.proximity`. Faces add no curve of their own for it.
- At night `HostedFace` holds the face on the wall, and its frosted copy behind the Home Screen, at its far layout (`shownProximity`). The near layouts add events, forecasts and other small text, which would have to be dim to keep a bedroom dark, and dim red text does not read. The editor and My Faces still show both distances at night.
- Text that shows at both distances is one view. Either it is drawn at its far size and shrunk into its near frame (`distanceFrame`, `DistanceFit`: the Photos time, Modular's date and clock), or its font size animates (`displayFont`: Weather, Digital, Night, Calendar, World Clock, Critters). A plain font change or a view swapped with `if` would jump.
- Only what is new up close fades in, with `if isNear` and `.transition(.proximityDetail)`: it fades in late in the move, once the big fact has made room, and out early when someone walks away.
- Motion drawn from the clock on every frame (Flow's drops) ignores transaction animations and eases a change of distance itself on `Theme.Motion.proximitySpring` (`FlowMotion.IntensityMove`).
- A face's timeline starts at the moment it is set up and then ticks on whole minutes or seconds (`FaceSchedule`), so a clock slowing from seconds to minutes as someone walks away keeps its hands where they are.
- The Photos time is placed by `PhotoClockLayout`, from the font's measured digits (`ClockFontMetrics`). The depth effect measures the numerals where they are drawn at the distance shown, so the wall, its thumbnails and the editor decide alike. Thumbnails take the wall's size and insets (`FacesRuntime.wallCanvas`, `wallInsets`). If walking up changes whether the subject leaves enough of the time showing, the subject cut-out fades with the move.

Check a face with `-HomePadProximity far` and `near`, and the move with `-HomePadSimulatePresence`, which steps through nobody, far, mid, near, mid and far, eight seconds each.

## Behind the Home Screen

With the Face wallpaper the shell keeps the face under the Home Screen, blurred, and sets `\.isFrosted` on it. Like HomeView's Home Screen, that copy shows the face's picture or background and nothing else: no time, date, temperature, text, dial, tiles, labels or widgets. Each face keeps its own colors, so the blur still looks like that face.

| Face | What shows behind the Home Screen |
| --- | --- |
| Modular, Calendar, Analog, Numerals, Digital, World Clock | the background color |
| Home | the background with its soft shapes |
| Night | black |
| Fade | the background and the sun's light, which moves with the hour |
| Photos | the photo, holding still where its slow move was |
| Weather | the sky for the weather and time of day, with its clouds and the sun or moon (black at night) |
| Flow | the swaying colors, without the drops that make the time |
| Critters | the scenery and Sprig, without the date, time or timer bubble |
| Cameras | the pictures alone in the far layout, refreshed every 30 seconds, without names, times or the doorbell's ring |
| Smart Rotation | the face it picked, as above, without the reason pill |

- Faces mark it with two modifiers in `Faces/Common/FaceBackdrop.swift`. A face whose background is a still color or gradient hands it to `faceBackdrop(_:)`, which draws it alone there. A face whose picture changes with its own state (Photos, Weather, Flow, Critters, Cameras, Fade's light) marks the parts over the picture with `faceForeground()`.
- Both keep the background in place while the rest fades in and out with the Home Screen, so the colors never dip.
- `HostedFace` leaves out the widget layer.
- What is hidden does not run: no clock timeline, no events or camera snapshot fetches for tiles. A timeline that asks for seconds ticks once a minute there, and motion runs at two frames a second (`FaceCadence`). The Photos slideshow still advances and prepares each photo's depth mask.
- The editor, My Faces and the face on the wall are not frosted, so they draw everything.
- `FaceBackdropTests` draws each face with a still background at two times and expects the same pixels behind the Home Screen and different ones on the wall.

Check a face with `-HomePadShowFace <id> -HomePadShowHome YES`.

## Backdrop tone

Glass on a face is dark with light text over a dark face and light with dark text over a bright one, like iPadOS widgets on a wallpaper, whatever the Appearance setting. That covers the face's widgets and the Home Screen's widgets over its frosted copy. Each face reports how bright its backdrop is with HomePadUI's `backdropTone(_:)`, worked out from colors it already draws, never from a list of light and dark faces.

| Face | Tone from |
| --- | --- |
| Modular, Home, Calendar, Analog, Fade, Numerals, Digital, Critters, World Clock | the background's luminance at both ends of its gradient (`FacePalette.tone`), which `faceBackdrop(tone:_:)` reports |
| Photos | the photo on screen, from its average color (`PhotoTint.tone`), and black until one loads |
| Weather | the sky's gradient for the condition and time of day (`SkyPalette.tone`), black at night |
| Flow | the average of the mesh's nine colors |
| Cameras, Night | black |
| Smart Rotation | the face it shows |

- `HostedFace` hands the report to the widget layer (`glassBackdrop(_:)`), and the editor's Widgets page does the same for the widgets it arranges. The report also rises from the frosted copy to the shell, which uses it for the Home Screen's widgets.
- At night glass is always dark.
- `FaceColorTests` checks that every background's tone agrees with how its preset was designed (`isLight`).

### White text on the sky

The Weather face keeps its text white, as Apple's Weather does, and lays a black shade between the sky and the text where the sky is too bright for it (`SkyTextShade`). The shade is worked out from the colors the sky draws, never chosen per condition:

- At 21 heights from top to bottom, `SkyPalette.brightest` takes the gradient's color there under the strongest cloud puff that drifts across that height (`CloudLayout`, sized by the face's width). The sun and moon are left out.
- `SkyPalette.textShade` gives each height the lightest shade that brings white to `FaceColorChoice.minimumContrast` on that color (HomePadUI's `BackdropTone.whiteTextShade`), and none where white already reads. Night skies, rain and thunder get none. A snowy day gets 0.2 to 0.4, and a partly cloudy one about 0.35 under its clouds and 0.2 at the bottom.
- The shade goes with the text (`faceForeground()`), so behind the Home Screen the sky shows as it is and the reported tone (`SkyPalette.tone`) is unchanged. Night mode is black with red text, without it.
- The hourly forecast's glass stays dark in Light and Dark, like the Weather app's panels. Light glass would wash out its white text.
- `SkyShadeTests` checks that white reaches the minimum on every sky at every height, and that dark skies get no shade.

## Previews

The editor's preview is the one live face in the Faces app. Every other face there is a card (My Faces, the Face Gallery, the editor's choice cards), and a card is a picture of its face (`FaceThumbnail`, `FaceStill`, `FaceStills`). Building a live face takes the main thread for about 25 to 85 ms, more with widgets, and My Faces once built every card on screen in one update (see [Performance](#performance)).

- `FaceThumbnail` lays the face out at the wall's size and insets (`FacesRuntime.wallCanvas`, `wallInsets`) and scales it. With `isLive` (the editor's preview) that is what shows. Otherwise the face is built only to take its picture.
- The picture is taken from the live face in a UIKit host of its own (`FaceStillCapture`, `drawHierarchy`), with the card's whole environment, so it shows the face, its widgets and mini widget, their glass and the locked personal widgets as a live card did. It is taken a frame after the face is built, as committed (`afterScreenUpdates: false`). Asking for screen updates instead made every host in the window lay out and render at once, 40 to 70 ms a picture. Then the live face goes, with its timelines, tasks and widgets.
- A picture is current for the minute it was taken in and for the look it was taken of (`FaceStills.Look`: the configuration, the size and insets, the distance, the display condition, the appearance and whether personal content shows). A card ticks on whole minutes like a face's clock. When its picture is out of date it builds the face again under the old picture and swaps when the new one is taken, so it never flickers. What the face reads (weather, events, accessories) shows as it was then, at most a minute old, as on the wall between a face's once-a-minute redraws.
- Cards take turns to build (`FaceStills.request`): one face per update, each in a later update than the one that asked, so no screen builds its faces all at once, or any face in the update that shows it. A card waiting for its first picture is black, the color a face is drawn on, and the cards fill in one after another.
- Only cards on screen build. One scrolled out of sight, or covered by the editor or the gallery (`\.facesPausesStills`, set by My Faces), keeps the picture it has until it shows again.
- A face that is still loading what it shows says so (`faceIsLoading`) and its picture waits for it: the Photos slideshow's first photo, camera snapshots, today's events and a chosen city's weather. One that never finishes loading stays live. A thumbnail of the Photos face shows its photo at once, without the slideshow's fade.
- Up to 48 pictures are kept (`FaceStills.capacity`), enough for My Faces, the gallery and a page of choices, the oldest dropped first and all of them on a memory warning.
- The face on the wall, its frosted copy behind the Home Screen and the faces beside it on the pager are live faces, as before.

## Performance

The Faces app was profiled before and after its cards became pictures (see [Previews](#previews)), with the same UI test, in an iPad Pro 11-inch (M5) simulator on iOS 27, on an optimized build with the debug launch options.

### What the tour does

`FacesPerfUITests.testFacesAppTour` opens Faces from the Home Screen, scrolls My Faces, opens the Face Gallery and scrolls it, opens the editor on Modular, Photos, Weather and Flow and swipes through their pages, and drags a widget on Modular's Widgets page and back. Every saved face carries three widgets and the mini widget, as faces in use do (`-HomePadFacesWidgets`, `-HomePadFacesMiniWidget`). Its taps on Up Close and Across the Room land on the picker's accessibility stand-in, whose segments do not line up with the drawn ones, so the preview's distance does not change in the tour.

### What was slow

Building a live face takes the main thread for about 25 to 85 ms, more with widgets. Every card was a live face, and a screen built all of its cards in one update:

- Opening Faces: one stretch of 457 ms building My Faces.
- The gallery: 265 ms as it opened, and up to 100 ms as rows scrolled in.
- The editor: about 150 ms as it opened, and 40 to 80 ms each page, since the choice cards are faces too.
- The time is SwiftUI building whole faces: graph updates, layout and the preferences that need layout (half of the opening stretch). No one function of the app's own stood out. The largest was `DialNumerals` (46 ms of the opening stretch, from the Analog and Numerals faces).
- Scrolling My Faces once its cards were built had no stretch over 21 ms. Its frame-rate hitches came from XCUITest's own reads.

### Before and after

The app's own main-thread work in each step of the tour, with XCUITest's reads left out. A stretch is main-thread work with no break, and one over 20 ms holds up at least one frame at 60 Hz.

| Step | Longest stretch | Stretches over 20 ms | Main thread |
| --- | --- | --- | --- |
| Opening Faces, the stretch that builds My Faces | 457 ms, now 228 | | |
| Scrolling My Faces | 21 ms, now 84 | 2 (41 ms), now 4 (194 ms) | 2383 ms, now 1134 |
| The gallery: opening, scrolling, closing | 265 ms, now 111 | 6 (508 ms), now 26 (884 ms) | 2436 ms, now 1840 |
| The editor on four faces and their pages | 152 ms, now 138 | 12 (625 ms), now 19 (851 ms) | 5456 ms, now 4598 |
| The Widgets page and two drags | 132 ms, now 134 | 7 (373 ms), now 13 (731 ms) | 1219 ms, now 1802 |
| The whole tour | | 39 (2762 ms), now 80 (3918 ms) | 13387 ms, now 10885 |

The frame rates the app wrote (Documents/fps-trace.txt), each step's sessions together:

| Step | Average | Hitches | Longest hitch |
| --- | --- | --- | --- |
| Scrolling My Faces (6 scrolls) | 44.1 fps, now 54.7 | 31, now 21 | 215 ms, now 149 |
| Editor pages (7 swipes) | 44.7 fps, now 50.0 | 63, now 41 | 317 ms, now 179 |
| The gallery (opening, 5 scrolls) | 53.4 fps, now 52.8 | 24, now 28 | 132 ms, now 210 |
| Widget drags (2) | 60 fps, still | none, still | none, still |

- The freezes as a screen opens are about halved: My Faces 457 to 228 ms, the gallery 265 to 111 ms. The worst editor page swipe went from 317 to 179 ms.
- The app does a fifth less work on the main thread over the tour, and XCUITest's reads of it take 4.1 s instead of 14.7 s, since a card is one picture.
- The work is spread into more, shorter stretches: a card builds its face when it first shows, and again once a minute while it shows, one card per update, and each picture costs a little. The gallery's frame-rate lines count from when the gallery is built since the change, and from when it appeared before, so its longest hitch now includes building it.
- The two 130 ms stretches at the end are the simulator turning back to portrait as the test ends. The app's own launch, 327 and then 295 ms, is left out.
- The editor still takes about 140 ms to open: its preview is a live face with its widgets.
- A card's first turn now comes in a later update than the screen that shows it, so a screen's opening stretch no longer includes building its first card. That came after these measurements and has not been measured.

### Simulator and device

- What carries over is CPU work on the main thread: building faces, layout, the cards' turns. The simulator runs the app on the Mac's own CPU.
- Rendering may not: glass, blur and shadows are drawn by the Mac's GPU in the simulator. A card's picture draws none of them, so scrolling should gain more on an iPad than here, which has not been measured. The Hitches instrument needs a device.
- XCUITest reads the app's whole accessibility tree before every step and turns on SwiftUI's accessibility work in every update. An iPad without VoiceOver does neither, so it should do less than these numbers in every step.

### Repeating the numbers

In the simulator, build optimized with the debug launch options, run the tour under Instruments, then split the trace into its steps:

```
scripts/build-slot.sh xcodebuild -project HomePad.xcodeproj -scheme HomePad -configuration Release \
  -destination 'platform=iOS Simulator,id=<UDID>' -derivedDataPath .build/DerivedData-Profile \
  SWIFT_ACTIVE_COMPILATION_CONDITIONS=DEBUG -quiet build-for-testing
scripts/profile-faces.sh <UDID> <new folder>
python3 scripts/trace_hotspots.py <that folder>
```

The folder gets the trace (`faces.trace`, to open in Instruments), the test's log and the frame rates. Each step is a Points of Interest signpost named `Faces` (`FacesPerfTrace`).

On an iPad:

- Launch with `-HomePadFacesTrace YES` (`xcrun devicectl device process launch --device <id> com.ksha23.homepad -HomePadFacesTrace YES`), or copy an empty file to Documents/HomePadFacesTrace.on to keep it on across restarts for a day (HomePadCore's `DebugTrace`).
- Use the Faces app: open it, scroll My Faces and the gallery, open the editor and swipe its pages, drag a widget.
- Fetch the frame rates with `xcrun devicectl device copy from --device <id> --domain-type appDataContainer --domain-identifier com.ksha23.homepad --source Documents/fps-trace.txt --destination fps-trace.txt`. Each line is one step: `Faces.open`, `Faces.myFaces` and `Faces.gallery` (one for each scroll), `Faces.editor`, `Faces.editor.page`, `Faces.editor.distance` and `Faces.editor.widgetDrag`, with the average and lowest frame rate, the hitches (frames over 1.25 times the frame time) and the longest. Opening Faces, the gallery and the editor count from when they are built, so their lines include building them.
- For a profile, `xcrun xctrace record --template 'Time Profiler' --instrument 'Points of Interest' --instrument Hitches --device <id> --attach HomePad` while doing the same.

## Structure

```
Sources/HomePadFaces/
  FacesModule.swift      registration (faces, Faces app, settings pane, Clock widget)
  Catalog/               FaceDefinition and FaceCatalog (every face kind and its options)
  Models/                pure types and math: options, palette, rules engine, clock, grid, depth layout, sky, critters
  Models/WidgetGrid/     the widget grid: cells, areas, fills, the board, layouts, migration, each face's room
  Services/              FaceLibrary, RotationStore, FaceSharing (shared with the household's other HomePads), FaceActivityMonitor,
                         FacesRuntime, FaceStills (the cards' pictures)
  Services/Photos/       PhotoKit source, Vision depth processor and mask cache, demo scenes
  Faces/<Face>/          one folder per face, Faces/Common for shared face parts and the backdrop modifiers
  Views/Host/            FaceHost (wall or one face), FacePager and FacePageWindow (the wall's pages), HostedFace (config, widgets), FaceTimeline (cadence), environment and debug options
  Views/Widgets/         the widget layer every face draws, its tiles and stacks, the mini widget in the top margin, and the room faces keep clear
  App/                   Faces app, gallery, saved face cards, thumbnails and the pictures they show (FaceStill), the app's trace
  App/Editor/            the face editor: preview, page and distance bar, option pages, slots
  App/Editor/Widgets/    the Widgets page: the canvas over the preview, its tiles and handle, the gallery sheet
  Settings/              Faces settings pane, Smart Rotation rules editor
Tests/HomePadFacesTests/ rules engine, library, layout and time math, the widget grid, its anchors, stacks and migration, the backdrop behind the Home Screen,
                         and sharing (photo picks kept per iPad, a person's new ID, widgets on each iPad size, widgets with Same on All
                         HomePads off keeping each iPad's settings between two libraries, and tiles and cameras picked on another HomePad)
```

Clock hands, dial ticks and numerals, `ClockMath`, the option carousel and cards in the editor, and the trailing icon label style come from HomePadUI, so World Clock in Personal and the analog faces draw the same clock.

## Settings

Settings, Faces (pane id `faces`): the face showing now for everyone and for each person, the saved faces with their editor, Smart Rotation rules, photo access, and a note on shared calendars. Keys:

- `faces.library`: saved faces per owner, shared with the household's other HomePads (kind `faces.library`), not through iCloud.
- `faces.auto.rules`: Smart Rotation rules and fallback, shared with the household's other HomePads (kind `faces.rotation`), not through iCloud.

## Photos depth effect

`PhotoDepthProcessor` (an actor) loads each photo off the main thread, asks Vision for a subject mask (`VNGenerateForegroundInstanceMaskRequest`, then `VNGeneratePersonSegmentationRequest`), feathers it into an alpha mask, samples it at 64 by 64, and averages the photo's color for the numeral tint. Masks are cached on disk under hashed names, frames in memory. The face draws the photo, then the time, then the photo again masked to the subject, then the date, which never goes behind the subject. When the subject would hide a third or more of the numerals, the time stays in front.

The depth time, like the Weather face's temperature, is frosted glass (`GlassNumerals`): a light material masked to the numerals' outlines (`GlyphLine`, from the font's glyphs) and tinted, a bright bevel inside each stroke, and a shadow outside them. Nothing in it moves on its own: the frost redraws only while the photo or the sky behind it moves, and holds still with them. At night the time is flat red instead. Without photo access (the simulator) the face shows generated scenes that carry their own masks, so the effect is still visible.

## Debug launch arguments

`-HomePadShowFace <id>` and `-HomePadProximity far|mid|near` come from the shell. This module adds, in debug builds only:

- `-HomePadFacesNight YES` (the red palette), `-HomePadFacesPersonal YES` (personal calendar content), `-HomePadFacesTime 21:30`, `-HomePadFacesWeather rain|snow|clear|cloudy|thunder|fog`, `-HomePadFacesStyle <choice>` (a style choice such as `digital` instead of the saved one).
- `-HomePadFacesColors midnight,cream,orange` shows the face on the wall, and the face the editor opens, in that background, text and accent. An empty part keeps the saved one and `auto` picks Automatic.
- `-HomePadFacesLandscape YES` lays a face out in landscape and turns it to fit a portrait simulator (rotate the screenshot).
- `-HomePadOpenApp faces` with `-HomePadFacesEdit <faceID>`, `-HomePadFacesEditPage <n>`, `-HomePadFacesEditDistance near|far` or `-HomePadFacesAdd YES`. With `-HomePadForceLandscape YES` the editor turns with the shell (rotate the screenshot).
- `-HomePadFacesWidgets "personal.weather:medium@4,0;kitchen.timers:small"` puts widgets on the face on the wall, the face the editor opens and the My Faces cards: each a widget ID and a size, and optionally the column and row of its top leading cell. A second list after a bar (`|`) is the portrait layout. IDs joined by `+` make a stack: `"personal.upnext+personal.weather+audio.nowplaying:medium@4,0"`.
- `-HomePadFacesWidgetGalleryItem homepad.smartStack` opens the widgets page's gallery on the Smart Stack's sizes.
- `-HomePadFacesMiniWidget "shell.glance.mini"` puts a mini widget in the top margin of the same faces, or `off` takes it away. A size after a colon is accepted and shown small.
- `-HomePadFacesEditWidgets YES` opens the editor on the Widgets page. There `-HomePadFacesWidgetOrientation portrait`, `-HomePadFacesWidgetSelect <n>`, `-HomePadFacesWidgetDrag <n>@<x>,<y>` (a widget held lifted, moved that far in face points), `-HomePadFacesWidgetResize <n>@<x>,<y>`, `-HomePadFacesWidgetGallery YES`, `-HomePadFacesWidgetGalleryItem <widgetID>` and `-HomePadFacesWidgetGallerySize small|medium|large` hold a state for a screenshot (`WidgetEditDebug`). Widgets count in the face's saved order. The gallery sheet shows unturned with `-HomePadForceLandscape`, so check it in portrait.
- `-HomePadFacesTrace YES` writes the Photos depth decisions to Documents/faces-trace.txt and the Faces app's frame rates to Documents/fps-trace.txt (see [Performance](#performance)).

## Needs real-device testing

- Vision segmentation quality and speed on real photos (the simulator has no photo access and may lack the Neural Engine).
- PhotoKit with iCloud Shared Albums (network downloads) and limited library access.
- The glass time on real photos, dark ones especially, and the cost of its frost while the Ken Burns move runs. In the simulator it costs nothing at rest.
- Liquid Glass on the Flow drops, how its digits read from across the room, and the frame rate of Flow and the weather particles on the iPad Pro.
- Night mode brightness in a dark bedroom. Burn-in drift is the shell's.
- Swipe between saved faces together with the shell's own gestures, and how smoothly the Home face moves. In the simulator the pager moves it every frame, but a recording of a slow drag shows the screen updating in bursts with that face on it, while Numerals to Digital records at a steady 60 frames a second.
- Real camera snapshots and refresh cost with nine cameras, and nine live WebRTC feeds up close (heat and battery), switching from snapshots as someone walks up.
- The feel of dragging and resizing widgets on the Widgets page: the lift, the snap, the push aside and the settle, which a simulator screenshot cannot show.
- Flipping a widget stack on the wall with a finger: up and down without the face paging or opening Faces, and a sideways swipe from a stack still paging.
- The Faces app's frame rates on the iPad (see [Performance](#performance)): how the cards fill in as a screen opens and as they scroll in, the refresh each minute, and scrolling over pictures rather than live glass.

## Known gaps

- Flow draws with `MeshGradient` and Liquid Glass rather than a Metal shader, because the build Mac has no Metal Toolchain.
- PhotoKit has no "Featured Photos" album. Featured approximates it with Portrait photos and favorites from the last two years.

No third-party dependencies.
