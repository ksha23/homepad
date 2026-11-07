# HomePadShell

The shell is everything that makes an iPad feel like HomeView: the always-on face, the per-person Home Screen, full-screen apps, the edge gestures, Control Center, the People switcher and recognition gate, the Settings app, first-launch onboarding, and the kiosk controller that keeps the display on, dims it, turns it red at night and puts it to sleep.

The app target shows `ShellRootView` and lists `ShellModule` last in `Modules.swift`.

## Features

### Navigation

- **Ambient face.** Shows the face from (first registered match wins) a `.showFace` request, the active member's `preferences["faceID"]`, `CoreSettings.defaultFaceID`, or the first registered face. The shell registers a built-in clock face (`shell.clock`), so there is always one. Tap goes to the Home Screen. Press and hold (0.6 s, the same hold as Home Screen edit mode) opens the editor for the face on screen with a light haptic, inside the Faces app (`faces.editWallFace`, a redirect to `faces` that asks for the editor). It fades in from the face rather than zooming (`open(appID:fromFace:fades:)`, `fadingAppID`), since the whole face was held, and closing the editor fades back to the face. My Faces is the Faces app's icon. Like a long press on an iPadOS widget, a hold that starts on one of the face's buttons opens the editor too and the button does not fire, a control that takes the press first (a light row's level slider) keeps it, and a swipe never opens it (`ChooseFaceGesture`). VoiceOver gets Show Home Screen and Customize Face. Over every face the shell draws a small profile dot (`AvatarView`, as in Control Center) centered in the top right corner of the face's margin: the guest glyph while nobody is recognized, the member's avatar once someone is. It drifts with the face, turns red at night, and is left out under the Home Screen's frost and before anyone is set up. Faces add no recognition hints of their own. A face can have a mini widget such as the glance in its top left corner, mirroring the dot, which the Faces module draws with the face (see [Header glance](#header-glance)). While a timer runs or music plays the face shows the [timer and Now Playing pills](#timer-and-now-playing-pills) too.
- **Home Screen.** Per member: HomeView's header, app icons from `registry.apps`, widgets from `registry.widgets`, pages with page dots, and the member's wallpaper. The greeting and the icon and widget labels stay white with a soft shadow in either appearance, since they sit on the wallpaper, as on iPadOS. Widget glass takes its light or dark look from the wallpaper, also as on iPadOS: dark with light text over a dark wallpaper, light with dark text over a bright one, in either appearance. Solid cards (Calendar, Reminders, Timers), sheets and the Liquid Glass buttons follow the appearance.
- **Header.** As on HomeView: two lines in SF Pro capitals, regular over semibold, about a quarter of an icon tall, so they keep HomeView's proportion to the icons on every iPad. They show the date over the time ("MONDAY, NOV 2" over "9:34 AM"), and for 8 seconds after someone is recognized "GOOD MORNING," over their name. The [glance](#header-glance) sits right of them. The pills and the avatar (`Theme.Size.profileButton`, about two thirds of an icon) sit on the lines' center line, with the avatar as far from the top as from the side. A third of an icon separates the header from the first row.
- **Appearance.** Settings > Kiosk & Display > Appearance picks Dark (the default), Light or Match iPad (`ShellSettings.appearance`). `ShellContentView` applies it once to the window with `.preferredColorScheme`, and to the onboarding cover, and night is always dark. Behind everything the root draws the page color (`Color.screenBackground`), and every app sits on it. See "Light and dark" in HomePadUI's DESIGN.md.
- **Apps** open full screen and close with a swipe up from the bottom edge or a tap on the home bar (HomePadUI's `HomeBar`). The bar reaches the full-screen covers an app presents too (Music's player, a photo or video viewer, the face editor, a room scan): their content applies HomePadUI's `.coverHomeBar()`, which draws the same bar with the shell's actions (`\.homeBar`). The window then shrinks into what the app was opened from with the cover in it, and a short swipe springs back to the cover. The close button top right (the shell's, or `AppScreen`'s via `\.closeApp`) shows only with Settings > Kiosk & Display > Show Close Buttons on, off by default (`ShellSettings.showsCloseButton`, handed to apps as `\.showsAppCloseButton`). Sheets, details and overlays keep their close buttons. Missing app IDs open a friendly "isn't available" screen. An app opened from another one goes back to it (`returnAppID`). Every other app closes to the Home Screen, wherever it was opened from, the face included. The one exception is Faces opened by holding the face, which closes back to the face. On a face, a tap on a widget outside its own buttons opens the widget's app, as on the Home Screen.
- **What apps present.** SwiftUI presents an app's sheets, covers and alerts through the app's own host (`AppHostingController`), but UIKit puts them above the whole shell, from the window's root, zoom included. The host keeps them, and the navigator shows only those of the app on screen (`AppHostRegistry`). While the zoom's picture of a swipe or a close stands in for the app they are hidden, and a short swipe that springs back shows them again. Once a closing app's window has landed and the app is suspended, they are dismissed, so Music opens again on its page without the player, and nothing an app presented stays over the Home Screen or the face, keeps a camera or a video going, or keeps a later sheet from showing. Its kept picture still shows them, so it is dropped and the next open grows a plain page. A presentation made while the app is still hidden under an open zoom (Now Playing opened from the pill while Music zooms open) shows at once.
- **Swipe down to close.** Full-screen views over an app (a camera full screen, the Photos viewer) close with a swipe down back to where they were opened (HomePadUI's `.swipeDownToDismiss` and `DirectionalPan`, see DESIGN.md). An app that presents over its opener (`presentsOverOpener`) keeps the opener alive underneath, hidden while covered (`appBehindID`), so the swipe shows it through and going back finds it on the same page and scroll position. An opener holding a camera (Mirror) is not kept, so the camera stops. Going Home or to the face drops it.
- **Edge gestures.** Down from the top-left or center: `services.assistant.startListening()` and `.invokeAssistant(prompt: nil)`. Down from the top-right: Control Center. Up from the bottom: an app goes Home, the face goes Home, the Home Screen opens the app grid.
- **Event routing.** `.openApp(id)`, `.showFace(id)`, `.goAmbient` and `.wake` from the bus, plus `homepad://app/<id>`, `homepad://face/<id>`, `homepad://home` and `homepad://settings/<pane>` URLs. `registry.overlays` draw above everything, sorted by `zIndex`.
- **What is on screen.** The navigator puts the app on screen in `AppServices.visibleAppID` whenever it changes, nil on the face, on the Home Screen and while a personal app waits behind the gate. The assistant reads it to know what "this" is.
- **Kiosk status.** On every kiosk tick the coordinator writes `AppServices.kioskStatus` (Core's `KioskStatus`) when it changed: what fills the screen (face, Home Screen or an app), the face that shows or sits under the Home Screen (`FaceResolver.current`, the same one `CurrentFaceView` draws), the brightness in whole percent, and the battery and power from `DeviceHealthMonitor`. Smart Home reports it to Home Assistant.
- **Kiosk requests.** Other modules post Core's `KioskRequest` events: `.sleepDisplay` sleeps the screen now (`KioskController.sleepNow()`), `.setBrightness(_:)` sets the brightness as Control Center does, and `.showDefaultFace` forgets a face asked for with `.showFace` and shows the usual one. Home Assistant's kiosk commands arrive this way.

### Header glance

A compact line of what is going on, right of the header's date or greeting (`Glance/`, `MiniGlanceView`). It is in the header's own white capitals with the wallpaper labels' shadow, so it reads as part of the header on any wallpaper.

- **A mini widget.** The glance is the first mini widget (`GlanceMiniWidget`, id `shell.glance.mini`, Core's `MiniWidgetDescriptor`, see "Mini widgets" in HomePadUI's DESIGN.md). The header's slot holds a mini widget rather than the glance itself, so another module's mini widget can take it later. The same view draws the glance in a face's top left corner when the face's editor puts it there (the Faces module draws it there on glass, see its README): `MiniWidgetContext.surface` picks the header's white capitals or the glass's `.primary`, and the context's text size, room and tap action come from the place that draws it.

- **What it says.** One shared model, `GlanceSummary`, built from plain values so it is tested without the services (`GlanceSummaryTests`), and fed by `GlanceReader`:
  - Events left today (all-day ones and those not over, as Up Next counts them) and the one on now or next, from `services.calendar`.
  - Reminders due today or overdue, and how many are overdue, from `services.calendar` too.
  - Unread messages, the Messages app's own badge (`AppDescriptor.badgeCount`), so the shell never imports Comms. The Messages store holds nothing while it may not show anyone's messages, so the count follows its Require Recognition setting by itself.
  - At home, from `services.smartHome.accessories`, each device once (groups left out) and only reachable ones: what is on by kind (lights, fans, plugs, speakers playing, thermostats heating or cooling, purifiers, vacuums) with their rooms, and what needs a look (smoke, a leak, an unlocked lock, an open garage, door or window) with its name.
  - Calendar, reminders and messages are personal and show only while `household.isPersonalContentUnlocked`, the rule personal widgets follow. Home always shows. A category with nothing to say is left out, and with nothing at all the glance shows a quiet check ("All quiet").
- **When it reloads.** Home redraws as accessories change. Events and reminders load again when calendars or who is looking change (`CalendarService.reloadKey`), and on their own only when the summary would change: when a timed event ends or a reminder falls due, or at midnight (`GlanceSummary.nextChange`).
- **Sizes.** Small is a symbol and a count for each thing. Medium adds short words ("3 EVENTS", "5 LIGHTS ON"). Large adds a second line under each with the detail: the next event's time and title, the rooms that are lit, the door that is open. A detail is cut off past about sixteen digits of the header's text. Small and medium are one line and large two, the lines' own height, so none makes the row taller.
- **Room.** The lines take what they need first, then the pills and the avatar, and the glance gets the room left between them (the header's lowest layout priority). When that is too little, the first things keep the chosen size and the rest shrink to a symbol and a count, one at a time from the end, then things drop from the end, then it shows nothing. So the most pressing things keep their words and detail longest, nothing is dropped while a count still fits, and the lines, pills and avatar are never cut off (`MiniGlanceContent.variants`). On a face's glass and in edit mode it keeps at least its first thing (`MiniWidgetContext.keepsSomething`). Timers are left out, since the timer pill sits in the same row.
- **Taps.** Each thing opens its app: Calendar, Reminders, Messages or Home, with the whole row's height as its target. The header opens it with `navigator.open(appID:)`, the face on the wall posts `.openApp`, and edit mode and previews open nothing. Each thing reports itself as a zoom source (`glance/<thing>`), so the app grows out of it.
- **Per member.** The header's mini widget and its size are saved with the member's Home Screen layout (`HomeScreenLayout.miniWidget`, a `MiniWidgetPlacement`), and nil once it is removed, saved as null so it stays removed. Until changed it is the glance, small. Layouts saved before mini widgets kept the glance under `glance` (whether it showed and its size), which they read as the glance at that size, or none when it was removed. Layouts saved before the glance show it small.
- **Editing.** The edit bar takes the header's place in edit mode, so the mini widget moves into the edit bar's leading end, where the lines were (`HeaderMiniWidgetEditItem`). It jiggles with the icons and widgets, a translucent minus removes it, and the size button beside it steps through the sizes it supports, as a widget's does. It gets the room the actions and Done leave and shrinks to fit, as in the header. Once removed, Add Glance comes first among the edit bar's actions and brings it back, small. Once more than one mini widget is registered, that action is Add Mini Widget and asks which.

### Glance and Home Status widgets

The shell registers the glance as two widgets for faces and the Home Screen (`GlanceWidgets`), small, medium, large and tall, on glass that follows the backdrop:

- **Glance** (`shell.glance`): everything the header shows, plus running timers and, on large and tall, the weather. Personal parts follow the same rule as the header, so the widget itself is not personal and shows home and timers to everyone.
- **Home Status** (`shell.homestatus`): what needs a look and what is on, naming the accessories rather than their rooms.
- Small is a symbol and a count, two to a row, and medium adds the words. At night every symbol takes the text's color, since the red tint turns cyan and green black. Large and tall are a row per thing with its detail under it up close (left out from across the room), each row a walk-up target that opens its app. Every size shows as many as fit, the most pressing first. Small and medium open the widget's own app (Calendar for Glance, Home for Home Status).
- Both are anchored top leading (`WidgetAnchor.topLeading`), so on a face they land in the open area nearest its top leading corner (see the Faces README).
- Home Status asks a widget stack to show it (`.needsLook`) while something at home needs a look: smoke, a leak, an unlocked lock, or an open garage, door or window (`GlanceWidgets.homeStatusRelevance`, the glance's own `attention` rules). Glance asks for nothing, since it always has something to say.

### Home Screen customization (per member, iPadOS style)

- Long-press on an app icon shows its context menu (Edit Home Screen, Remove App). Long-press on a widget or on empty space enters edit mode, so a widget's own controls keep their press.
- Edit mode wiggles every icon and widget and shows remove badges (a translucent minus, as on iPadOS) and widget resize buttons. A short press lifts an icon or widget and it follows the finger, while the others move aside at once to open the slot it would land in, widgets taking a slot of their size and icons flowing around them (`HomeReorderSession`, `GridReorder`). Letting go saves it there. Holding it at a side of the screen turns the page, and past the last page a new page opens (dropped again if nothing lands on it). A quick swipe still turns the page. VoiceOver gets Move Earlier and Move Later.
- In edit mode a tap on a widget with settings opens Edit Widget, as on iPadOS (`HomeEditWidgetSheet`, HomePadUI's `EditWidgetSheet`): its settings beside a live preview, applied as they change. Home Favorites picks its accessories and Reminders its list. The settings live with the widget's place in the member's layout (`HomeScreenItem.settings`), so they move with it and go when it is removed. A press still lifts the widget, and widgets without settings keep the tap off in edit mode. A locked personal widget does not open, and the sheet closes if its owner stops being recognized. VoiceOver gets Edit Widget too. While this HomePad shares its setup with another, the page has Same on All HomePads under the preview (see Same on All HomePads below).
- Add Widget opens the same visual gallery as the face editor (HomePadUI's `WidgetGallery`): every widget not on the Home Screen as a big live preview, and every widget with settings even when it is (each copy keeps its own, `HomeScreenItem.instance`), then its sizes to swipe through and Add Widget. Add App shows the apps that are not on the Home Screen. Both add to the page on screen.
- **Smart Stacks**, as on iPadOS (see "Smart Stacks" in HomePadUI's DESIGN.md). The gallery offers a Smart Stack first, prefilled for the size with the widgets this person may see that can say when they matter (Core's `WidgetStack.suggested`). In edit mode a widget held over another of its size makes a stack: the others hold still while it is over that widget, after `HomeReorderSession.stackDelay` it grows a little (`stackTargetID`), and letting go stacks them with the dropped widget on top (`HomeScreenLayout.stack(_:onto:)`, planned by `HomeReorderPlanner.stackTarget`). Passing over it reorders as before, and a stack holds at most ten. A tap on a stack in edit mode opens Edit Stack (`HomeEditStackSheet`, HomePadUI's `EditStackSheet`): its widgets to reorder, remove or edit, Smart Rotate, and widgets that can join. Its minus removes the whole stack, and its size button steps through the sizes all its widgets come in. Outside edit mode a vertical swipe flips it, a tap opens the app of the widget on top, and the label under it names that widget.
- A stack saves with its place in the member's layout: a `.widget` item whose `stack` holds its widgets (Core's `WidgetStack`, each with its own settings and Smart Rotate on or off), under the ID `stack:<instance>`. The item keeps its first widget in `targetID` and `settings`, so a HomePad from before stacks shows that widget in its place. A stack with one widget left becomes that widget with its settings and copy ID (`HomeScreenLayout.setStack(_:for:)`). Layouts saved before stacks decode and save exactly as they were.
- New Page, and empty pages are dropped on Done.
- Wallpaper: **Face** (the default) keeps the current face under the Home Screen with a plain blur (`FaceFrost`, a `BackdropBlur` over it), as on HomeView. Behind the Home Screen the face draws only its picture or background (`isFrosted`): no time, text, tiles or widgets, so its colors show through softly. It holds its near look and redraws rarely, so it never changes behind the icons as people move around. Or six curated gradients ("My Color" uses the member's accent), or one photo from the system photo picker. The picker browses the iPad's whole library, so it is offered only while the photo library's owner is recognized (Core's `PhotoAccessPolicy`). Anyone else keeps a photo wallpaper they already have.
- How bright the wallpaper is sets the widgets' glass (`HomeWallpaperView.tone`, HomePadUI's `glassBackdrop(_:)`): a gradient from its own colors, a photo from its average color (measured once from a 32 by 32 pixel copy off the main thread, `WallpaperPhotoStore.measureTone(for:)`), and the Face wallpaper from the tone the face reports (`BackdropToneKey`, read by `ShellContentView` and handed down as `\.frostedFaceTone`). Each counts the scrim drawn over it. Near middle gray the glass keeps the look it has, so it does not flip as a Photos face changes photos. Night keeps it dark.
- At night app icons turn dark with a light symbol (HomePadUI's `AppIcon`), so a white symbol never vanishes into a red icon.
- New apps from modules appear at the end automatically. Apps a person removed stay removed and remain in the app grid.
- Personal apps (`requiresRecognizedMember`) are hidden for guests and show a lock for a member picked by hand. Personal widgets work the same way.
- **The same on every HomePad.** Each person's Home Screen and the guest's, with their pages, apps, widgets, stacks, widget settings and header mini widget, and each wallpaper, are shared with the household's other HomePads (`HomeScreenSharing`, two Core `SharedDocumentDescriptor`s that Connect carries, see "The household's setup" in its README). An edit on one shows on the others a moment later, and a layout reset to the default resets on all of them.
- A layout is saved as logical pages, so it lands on each iPad's own grid rather than point for point: six columns in landscape and four in portrait on every iPad, and as many rows as the screen holds (3 on an 11-inch iPad in landscape, 4 on a 12.9 or 13 inch one). A page that fills a 13-inch screen goes on to the next screen of an 11-inch, in the same order. The saved layout encodes its known apps sorted, so the same layout always reads the same and is never sent as a change.
- **Same on All HomePads**, under the preview on Edit Widget while this HomePad shares its setup with at least one other, is on for every widget at first. Off, each HomePad keeps its own settings for that widget, such as Home Favorites with the kitchen's lights in the kitchen and the bedroom's in the bedroom. The widget itself, where it sits and its size, and the switch are still shared. Each other HomePad starts from the settings it showed when the switch went off, and turning it back on on one HomePad makes its settings the shared ones. In a stack the switch is on each widget's own Edit Widget page, not on the stack, since each widget in a stack has its own settings and a stack can hold a widget that differs by room beside one that does not. The settings carry a mark with an ID that is the same on every HomePad (Core's `WidgetSettingsOnEachHomePad.swift`), so the choice moves with the widget into a stack and out. `HomeScreenSharing` shares the copy the widget had when the switch went off (`sharingWidgetSettings`) and keeps this iPad's own when a layout arrives (`keepingOwnWidgetSettings`). An older HomePad shows that copy.
- A photo wallpaper is a picture from one iPad's library, so it stays on that iPad (`onlyThisHomePad`). The other HomePads keep the wallpaper they had, and a gradient or Face chosen later on any HomePad replaces the photo.
- When this HomePad joins a household that already knew a person by another ID, their layout, wallpaper and wallpaper photo move to that ID first (`HomeScreenSharing.moveMember`), and the household's own replace them where it has them.

### Control Center

Date and time (proportional digits, like the faces), edit button, profile button, and a grid of tiles in four columns, or six or eight when a tall list would not fit the screen's height: Now Playing (the playing module's cover, title, transport and the AirPlay button, and a tap on the cover or title opens Now Playing, or Music when nothing plays), brightness (`BigSlider`, held until the condition changes), system volume (`BigSlider` on `SystemVolumeLevel`), camera and microphone privacy toggles (write `CoreSettings.cameraEnabled`/`microphoneEnabled` and `services.capture.camerasAllowed`), night mode, quiet hours (`CoreSettings.quietHoursEnabled`), Mirror (opens app `mirror`), and every `registry.controls` tile. Edit mode keeps tiles still and pulses their outlines, as on iPadOS (HomePadUI's `editPulse`), so the glass tiles stay clear. The Home Screen wiggles instead. A translucent minus removes a tile, and a short press lifts one while the others move aside as it moves (`ControlCenterReorder`). "Add a Control" brings back hidden ones, in a sheet that follows the appearance. The layout is household-wide. Control Center itself stays dark in either appearance, as on iPadOS: a dimmed blur behind dark glass tiles with white symbols, so every module's tile looks the same.

### Timer and Now Playing pills

Dynamic Island style capsules at the top center, side by side (`TopPills`), like HomeView's Live Activities.

- **Timer pill** (`TimerPill`): the soonest running timer from `services.timers` (else the soonest paused one) as a small tick ring that empties as it counts and the time left ("14:47"), with "+2" when more timers are on. Tap opens `timers`. The countdown redraws once a second, on the second it changes, only while the pill is on screen and the timer runs. A finished timer leaves it for Kitchen's full-screen alert. It hides inside Timers and on a screen that shows its timers itself (`.showsRunningTimers()`, cooking mode).
- **Now Playing pill** (`NowPlayingPill`): while `services.media.nowPlaying?.isPlaying`. Tap opens `nowplaying`, which the Audio module redirects to Music with its full-screen player up (plain `music` without that redirect). It hides inside Music.
- Each scales and fades in and out on its own (`Theme.Motion.settle`).
- Both are dark glass with light text in either appearance, like Live Activities, so they read the same over a white page, a wallpaper or a face.
- Inside apps both are small, and beside a timer the Now Playing pill is its cover alone, so the pair (about 165 points) stays inside the 176 point zone headers keep clear. On the Home Screen they sit in the header. On the face they are small from across the room and larger up close, where the Now Playing pill drops its title beside a timer. They drift with the face, turn red at night, and the face makes room for them (`\.faceNowPlayingRoom`). They hide while asleep.
- The cover is the one the playing module registers (`registry.nowPlayingArtwork`, the same as the Now Playing widget), with a music note when none is registered.
- The bars (`LiveWaveform`) are Core Animation layers with rhythms of their own, so the app does no work per frame and nothing listens to the microphone. They rest when nothing plays, the display dims or Reduce Motion is on, and turn red at night.

### People

- People menu from the avatar: pick a member (`household.select`) or Guest, Add Person (up to 6), Manage People.
- Person editor: name, curated emoji, accent color from the eight-color palette, admin flag (the last admin cannot be demoted), face enrollment status, remove.
- People are the same on every HomePad paired in the household, with the same IDs, so their Home Screens and faces follow them (Connect shares them). Face recognition is set up on each HomePad, so the People pane and the editor say "not set up on this HomePad" for someone who still needs it here.
- Adding, editing and removing need an admin: a recognized admin at the screen, or Face ID or the passcode through the system sheet. With no admins yet (first setup) it is open.
- **Recognition gate** for personal apps: "Recognition Required to Open Messages", with the glyph, text and buttons in one group centered on the screen, as on HomeView, over a frost of the page color (dark in Dark, light in Light). The buttons:
  - Continue waits for `household.isPersonalContentUnlocked`, posts `.wake` and `.custom("shell.recognitionRequested", {"appID": ...})`, and suggests the other ways after 20 seconds.
  - Use Personal Device shows only when the member has a paired iPhone or Mac (`services.personalDevices`, from Connect). It asks that device, where the person approves with Face ID or a passcode, shows "Check Kyle's iPhone" while it waits, and then calls `household.recognize`. A denial, no answer in 30 seconds or an unreachable phone shows as a line under the buttons. Closing the gate withdraws the request.
  - Use Face ID runs LocalAuthentication, then `household.recognize`.

  The app opens as soon as content unlocks. If content relocks while a personal app is open, the gate comes back.

### Kiosk controller

`KioskController` computes `services.displayCondition` every second and on every input:

1. Nobody seen for `sleepAfterMinutes` and nobody interacting: `.sleeping` (near-black, faint drifting time).
2. Night (forced, or the night schedule unless the room is lit): `.night`. Darkness alone never starts it, since a hand over the camera looks like a dark room.
3. A touch or wake event within `returnToFaceAfter`: `.active`.
4. Nobody present and nobody seen for the dim delay: `.dimmed`.
5. Otherwise `.ambient`.

"Seen" means a touch, a wake event, someone at mid or near distance or looking at the screen, or the presence service's `lastActivity`. Touches come from a passive window gesture recognizer that never blocks other gestures. Wake events are `.wake`, `.doorbellRang`, `.timerFinished`, `.soundDetected`, `.intercomReceived`, `.invokeAssistant` and `.openApp`. The assistant listening, thinking or speaking, any camera claim (Mirror), or a screen that asked with `.keepsDisplayActive(_:)` (cooking mode) keeps the screen in use.

It also:

- keeps the idle timer (Auto-Lock) off while HomePad is in front, and gives it back in the background
- has `KioskBrightness` ramp the screen (fast up, slow down). By default iPadOS auto-brightness drives it while in use or on the face, and HomePad only dims below that level for nobody nearby, night and sleep. With that off it uses its own level per condition and follows the room's light. It saves the user's brightness on start and restores it in the background
- returns to the face when interaction times out
- shifts ambient content a few points every 90 seconds on a 16-step orbit against OLED burn-in, scaled just enough that no edge shows
- warns when the iPad runs on battery
- caps brightness when hot (50% serious, 30% critical) and pauses presence sensing at critical heat until it cools
- ticks the household's session once a second and reports touches to it, so it switches to Guest once its person has not been detected for Switch to Guest After (see "Who is signed in" in the Presence README). Screens pinned by navigation launch arguments keep the person signed in
- sleeps on request (`sleepNow()`, from Home Assistant's `kiosk_show_screensaver`). Unlike the sleep timer, someone already in front of the iPad does not keep it awake. Someone arriving, a touch, a wake event, a face asked for or a screen holding itself awake (cooking mode, the assistant) wakes it
- hosts background work (see below)

### Background work

The shell hosts Core's background work (`services.backgroundWork`, see "Background work" in the Core README) on the iPad that shows HomePad, through `BackgroundWorkHost`. The iPhone and Mac companions never run it.

- `ShellModule.register` registers the two background launches with iOS (`registerSystemLaunches()`), since iOS takes them only before the app finishes launching. The identifiers are in `project.yml` under `BGTaskSchedulerPermittedIdentifiers`, with the `processing` background mode next to `fetch`.
- The coordinator starts it with the kiosk, and on every kiosk tick reports what the iPad is doing: the display condition, power and heat from `DeviceHealthMonitor`, whether HomePad is in front, and whether an app is zooming (`ZoomAnimator.isActive`) or a touch landed within `Theme.Motion.screenDuration`, the time a tap's screen change takes. Due tasks start from that report, so nothing runs during an app zoom or right after a touch, and tasks that wait for an idle screen run only on the face, dimmed, at night or asleep.
- As HomePad goes to the background, the coordinator asks iOS for the next app refresh and processing launches, from the soonest due task of each kind.

The condition and proximity go into `\.displayCondition` and `\.proximity`. Proximity stays `.near` in apps and on the Home Screen until a minute after the last touch. The face follows the camera instead, with two looks (`faceProximity`): `.near` within reach (`ProximityLevel.near`, about a meter) and `.far` anywhere past it or with nobody in view. While the camera watches, that distance alone decides, whatever keeps the screen in use. Without the camera, a screen in use is `.near`.

### Settings app (`settings`)

A sidebar of `registry.settingsPanes`, iOS Settings style, sized for a finger at arm's length: about a third of the width (300 points in portrait, about 360 on an 11-inch iPad in landscape, 400 on a 13-inch) with rows 64 points tall and 10 apart (HomePadUI's `.sidebarRow` style, `SettingsSidebar`). In landscape the rows do not all fit, so the sidebar scrolls and brings the chosen row into view. Admin-only panes ask for Face ID or the passcode (system sheet) unless a recognized admin is present, and warn when the iPad has no passcode. Settings reopens on the pane it was left on (`@AppState`, shared by the household), or the first pane when that one is gone. A pane asked for by name (`homepad://settings/<pane>`, onboarding, `-HomePadSettingsPane`) wins. A restored admin pane shows its Unlock button instead of asking for Face ID as Settings opens, unless a recognized admin is there. The close button, when shown, is the shell's, top right like every app. Every pane gets rows at least 64 points tall, 36 points between sections and a little extra room at the sides (`SettingsPaneLayout`, see DESIGN.md). The sidebar and panes sit on the grouped page color (`Color.groupedBackground`): black in Dark, and in Light the light gray that sets off the forms' white rows, as in iPadOS Settings. The shell registers:

- **Pages a pane pushes** go onto the Settings stack, which takes the stack's environment, not the pane's. A pane that puts its module's runtime in its own environment (`.environment(runtime)` in its `SettingsPaneDescriptor`) passes it again to each page it pushes, or that page crashes looking for it (Devices & Sharing's Join a Household, Faces' Smart Rotation Rules, Spotify Setup do).
- **People** (`people`): who is using HomePad now, everyone in the household, add, edit and remove.
- **Kiosk & Display** (`kiosk`, admin only): live status, Guided Access status and setup guide, Autonomous Single App Mode request with an explanation of supervision and MDM, tips (Shortcuts "When charger connected, open HomePad", Auto-Lock, battery health), timing, night schedule, brightness per condition, appearance, text size, burn-in protection, charging warning, and Run Setup Again.
- **Background Tasks** (`background`): every background task modules registered, each with its last run, its result, when it runs next or what it waits for ("Due, waiting for nobody to be using the screen"), how often and under which conditions, and Run Now, which skips the time and the conditions (`BackgroundTasksPane`).
- **About** (`about`): version, household, assistant provider, module IDs, registration counts and a live event log.

### Onboarding

Shown once on first launch and skippable at every step: welcome, household name, add people (the first is an admin), sensing and privacy, choose a face, then shortcuts into the `assistant` and `smarthome` settings panes. It sits on a dusk gradient dimmed toward the page color, deep in Dark and a soft pastel in Light.

## Structure

```
Sources/HomePadShell/
  ShellModule.swift        registers the Settings app, clock face and settings panes
  Navigation/              root view, coordinator, navigator, edge gestures, touch observer, layers
  Kiosk/                   KioskController, policy, KioskBrightness and its ramp, burn-in, device health, warnings,
                           the background work host
  Ambient/                 face resolution, hold to choose a face, built-in clock face, sleeping screen
  Grid/                    grid spans, packing, geometry and the reorder planner, shared by Home Screen and Control Center
  HomeScreen/              layout model and store, pages, tiles, live reorder, wallpaper, sheets, app grid, and
                           HomeScreenSharing (layouts and wallpapers shared with the household's other HomePads)
  Glance/                  the glance: its model and reader, the glance as a mini widget, the Glance and Home Status widgets
  AppHost/                 full-screen app container, suspendable hosts and what apps present, missing-app screen
  ControlCenter/           layout model and store, grid, tiles, gallery
  NowPlaying/              the timer and Now Playing pills, their stack, and the waveform bars
  People/                  menu, editor, recognition gate, admin authorization, personal access
  Settings/                Settings app and the shell's panes
  Onboarding/              first-launch steps
  Models/                  settings keys, night schedule, brightness levels, wallpaper, text size
  Debug/                   launch arguments and screenshot demo content
Tests/HomePadShellTests/   kiosk state machine (injected clock and presence), models, layouts, navigation, and shared
                           layouts (reading, applying, a person's new ID, how a layout lands on each iPad size, and widgets with
                           Same on All HomePads off keeping each iPad's settings between two settings stores)
```

## Settings

Shared keys the shell reads or writes: `CoreSettings.defaultFaceID`, `returnToFaceAfter`, `sleepAfterMinutes`, `nightModeAutomatic`, `cameraEnabled`, `microphoneEnabled`, `householdName` and `quietHoursEnabled`.

Shell keys (`ShellSettings`): `shell.kiosk.keepScreenOn`, `dimAfterMinutes`, `nightSchedule`, `nightModeForced`, `brightness`, `adaptToRoomLight`, `followSystemBrightness`, `burnInProtection`, `burnInAmplitude`, `chargingWarning`, `shell.display.appearance`, `shell.display.textSize`, `shell.onboardingCompleted`, `shell.askedSensingPermissions`, `shell.controlCenter.layout`, `shell.homeScreen.<member or guest>`, `shell.wallpaper.<member or guest>`. Wallpaper photos are JPEG files in Application Support/Wallpapers. The Home Screen and wallpaper keys are shared with the household's other HomePads over Connect's peer link (`HomeScreenSharing`), a photo wallpaper excepted. Everything else here stays on this iPad.

App state (`ShellAppState`, see `@AppState` in HomePadCore): `settings.pane`, the pane Settings reopens on.

## Debug launch arguments

All of these keep working for other modules' screenshots. Any navigation argument skips onboarding, stops the screen from timing out, and starts every app from its defaults with its state kept in memory for that launch (`AppStateStore.startFresh()`), so screenshots and UI tests begin alike and never change what the iPad saved.

| Argument | Effect |
|---|---|
| `-HomePadOpenApp <appID>` | open an app |
| `-HomePadOpenAppDelay <seconds>` | open that app after a delay, from the Home Screen |
| `-HomePadShowFace <faceID>` | show a face |
| `-HomePadProximity far\|mid\|near` | pin proximity |
| `-HomePadShowHome YES` | the Home Screen |
| `-HomePadHomePage <n>` | the Home Screen on page n (0 is the first) |
| `-HomePadResetHomeScreen YES` | start from the default Home Screen layout |
| `-HomePadHomeWidgets <id:size,...>` | put these widgets first on the Home Screen. IDs joined by `+` make a stack, such as `personal.upnext+personal.weather+audio.nowplaying:medium`, which takes the place of those widgets |
| `-HomePadEditStack YES` | Home Screen edit mode with Edit Stack open for the first stack on the page |
| `-HomePadEditWidget <widgetID>` | Home Screen edit mode with Edit Widget open for the first copy of that widget on the page, such as `smarthome.favorites`. Add Connect's `-ConnectDemoSyncedHomePads 1` to see Same on All HomePads |
| `-HomePadHeaderGlance off\|small\|medium\|large` | the glance as the header's mini widget at that size, or no mini widget |
| `-HomePadShowPanel controlCenter\|people\|appGrid` | a panel |
| `-HomePadEditHomeScreen YES`, `-HomePadEditControlCenter YES` | edit modes |
| `-HomePadHomeSheet addItems\|addApps\|wallpaper` | widget gallery, app picker or wallpaper picker |
| `-HomePadShowGate <appID>` | the recognition gate |
| `-HomePadGateAction personalDevice` | tap Use Personal Device once the member has a paired device (debug builds) |
| `-HomePadSettingsPane <paneID>` | Settings on a pane |
| `-HomePadShowOnboarding YES`, `-HomePadOnboardingStep 0-5` | onboarding |
| `-HomePadCondition active\|ambient\|dimmed\|night\|sleeping` | pin the display condition |
| `-HomePadMember <name>`, `-HomePadRecognized YES` | pick or recognize a member |
| `-HomePadSimulateUnplugged YES` | the not-charging warning |
| `-HomePadDemoContent YES` | placeholder apps, widgets, tiles, three people and a song, filling only IDs no module registered |
| `-HomePadForceLandscape YES` | lay the UI out in landscape inside the portrait simulator (rotate screenshots 90 degrees) |
| `-shell.display.appearance '<226c6967687422>'` | Light. `'<226461726b22>'` is Dark and `'<226175746f6d6174696322>'` Match iPad: the setting's JSON as plist data |
| `-HomePadPresenceTrace YES` | log why the kiosk thinks someone is near to Documents/kiosk-trace.txt |

## Needs real-device testing

- Brightness ramps and restore (`UIScreen.brightness` does nothing in the simulator), and how they feel at night.
- Idle timer, Guided Access, and `requestGuidedAccessSession` on a supervised iPad with an MDM profile allowing `com.ksha23.homepad`.
- Edge swipes with `defersSystemGestures`, with and without Guided Access, and the passive touch observer with real fingers. Over a cover (Music's player) too, which asks for the same deferral itself (`coverHomeBar()`).
- `MPVolumeView` and the AirPlay picker (the simulator shows no slider). Whether `MPVolumeView` still draws its own route button next to `AVRoutePickerView`.
- Face ID sheets for admin panes and the recognition gate, and Use Personal Device with a real iPhone.
- Battery and thermal reactions, the not-charging banner, and pausing presence when hot.
- Burn-in drift on OLED (2024 and later iPad Pro) over long sessions.
- Turning the iPad. The simulator refuses programmatic rotation, so landscape is checked with `-HomePadForceLandscape YES`.
- Live reorder with a finger on the Home Screen and in Control Center, including turning the page at the screen's sides.
- Background launches: whether iOS gives HomePad app refresh and processing launches (Background App Refresh on, Settings > General), and that each runs the due tasks. The simulator refuses every request, which the log notes.
- Widget stacks with a finger: flipping one up and down without the page moving, a sideways swipe from a stack turning the page, a swipe starting on a widget's button or light row, the Now Playing volume in a stack, and holding a widget over another until it offers to stack (`stackDelay`) without stacking by accident while passing over.

## Known gaps

- A widget without settings is offered on its own once per Home Screen. Widgets with settings can be added more than once, and a Smart Stack may hold a widget that is also on the Home Screen, as on iPadOS.
- Which widget a stack shows is not saved, so after a restart each stack rests on its first widget until someone flips it or Smart Rotate turns it.
- Weather's relevance looks at the forecast's conditions. The forecast carries no weather alerts, so storms, hail, freezing rain and heavy snow stand in for one.
- Home Screen icon size scales with screen width only. The largest text sizes drop one column instead.
- The People pane does not run face enrollment. That belongs to the Presence module.
- The `assistant` and `smarthome` pane IDs in onboarding are assumed. Missing panes show "Coming Soon".

## Dependencies

Apple frameworks only (SwiftUI, UIKit, LocalAuthentication, PhotosUI, MediaPlayer, AVKit). No third-party packages.
