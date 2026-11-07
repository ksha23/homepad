# HomePad architecture

HomePad turns an iPad into an always-on home display in the spirit of Apple HomeView, and goes further: any AI provider, Home Assistant as well as HomeKit, TrueDepth presence sensing, and back-camera features.

## Layout

```
App/                      Thin app target: @main, module list, App Shortcuts, Info.plist, entitlements, assets
Extensions/HomePadWidgets WidgetKit extension (kitchen timer Live Activity, Home Screen timers widget)
Extensions/HomePadShare   "Send to HomePad" share extension (links only HomePadShareKit and HomePadUI)
Watch/                    Apple Watch app: intercom, timers and scenes through the iPhone companion
UITests/                  UI tests that tap and drag real controls in the simulator
Packages/                 One local Swift package per feature
  HomePadCore             Contracts every module builds against (models, service protocols,
                          registry, event bus, settings, keychain, mic hub, audio session, camera arbiter,
                          background work). See Packages/HomePadCore/README.md
  HomePadUI               Shared design system (tiles, avatars, app chrome, night mode, proximity).
                          See Packages/HomePadUI/DESIGN.md
  HomePadShell            Navigation, kiosk / always-on controller, Home Screen, Control Center,
                          People switcher, Settings app, onboarding
  HomePadFaces            Always-on faces (photos, clocks, modular, home, cameras, weather, flow, night,
                          critters), the widget grid on faces, the Faces app and face editor
  HomePadAssistant        AI providers, tool calling, voice (speech in, speech out), assistant overlay
  HomePadSmartHome        HomeKit and Home Assistant backends, Home app, cameras, doorbell, dashboards,
                          device trackers and zones for Find My
  HomePadAudio            AirPlay 2 routing, Apple Music, Spotify, radio, Music library, Up Next,
                          Now Playing, HA media players
  HomePadPresence         TrueDepth / camera presence, distance, recognition, gestures, sound alerts, Mirror
  HomePadKitchen          Recipes, cooking mode, timers, Live Activities
  HomePadPersonal         Calendar, reminders, weather, photos, world clock, Find My
  HomePadConnect          Siri / App Intents, Handoff, iCloud, intercom, Family Board, iPhone / Mac / Watch
                          companions and the iPhone music remote.
                          ShareKit/ holds HomePadShareKit, the small package the share extension links
  HomePadCameraLab        Back-camera features (ask-about-this, scanners, security cam, LiDAR floor plan)
  HomePadComms            Messages through each person's Mac hub. CommsKit/ holds the wire models
                          and routes the hub shares (see docs/COMMS.md)
  ThirdParty              Vendored open source (see Dependencies)
Hub/                      homepad-hub, the macOS tool that reads and sends Messages for one Apple ID
docs/                     This file, the on-device checklist, Messages, the app zoom, README images
scripts/                  Build slots, package builds, simulator and device helpers, README screenshots
project.yml               XcodeGen spec (source of truth for HomePad.xcodeproj)
```

Dependency rule: feature packages depend on `HomePadCore` and `HomePadUI`, plus the outside libraries listed under [Dependencies](#dependencies). They never import each other. They talk through:

1. **Service protocols** in `HomePadCore/Services/ServiceProtocols.swift` (smart home, media, assistant, timers, presence, calendar, weather, intercom), plus personal devices in `PersonalDeviceService.swift` and each person's own iPhone photos in `PhonePhotosService.swift`. A module installs its implementation into `AppServices` during `register`. Other modules use `services.smartHome`, `services.media` and so on.
2. **The registry** (`ModuleRegistry`). Modules contribute apps, faces, widgets, settings panes, overlays, Control Center tiles and assistant tools. The shell and the assistant discover them at runtime. An `AppRedirect` keeps an app ID working after its screen moves inside another app: `cameras` opens the Home app on its cameras. A `ScreenContextProvider` says in a sentence or two what an app shows right now (the recipe card, the camera full screen), so the assistant knows what "this" is. The shell puts the app on screen in `AppServices.visibleAppID`, and the assistant asks that app's provider only when someone asks something. A provider without an app speaks over every screen, as the doorbell does. A `WidgetDescriptor` can have settings, like iPadOS's Edit Widget: its `settings:` closure draws the page that changes them, and the widget reads them from `\.widgetSettings` through typed `WidgetSettingKey`s with defaults (`HomePadCore/Module/WidgetSettings.swift`). Each placed copy has its own `WidgetSettings`, stored with its place: a Home Screen item, or a face's widget layout by placement ID. The host shows the page in HomePadUI's `EditWidgetSheet` and saves each change as it is made, and a key nobody set reads its default, so a widget placed before it had settings looks as it did. While HomePads share their setup, the page also has Same on All HomePads, which keeps that widget's settings on each HomePad (`HomePadCore/Module/WidgetSettingsOnEachHomePad.swift`).
3. **The event bus** (`services.events`). It carries broadcast signals such as `.doorbellRang`, `.timerFinished`, `.soundDetected` and `.openApp`. Module-private signals use `.custom` with a name declared in `HomePadCore/Extensions/<Module>/`, so other modules can post or match it without importing the module.
4. **Shared settings keys** in `HomePadCore/Storage/CoreSettings.swift`.
5. **Shared documents** (`HomePadCore/Module/SharedDocument.swift`). A module that owns part of the household's setup, such as the Home Screens or the saved faces, registers a `SharedDocumentDescriptor` that reads and applies it for the household and each person, and Connect shares it with the household's other HomePads over the peer link, with versions and the join rules (see "The household's setup" in the Connect README). A document that holds widget settings passes them through `sharingWidgetSettings()` and `keepingOwnWidgetSettings(from:)`, so a widget with Same on All HomePads off keeps each iPad's own. What a HomePad says about itself, such as the names it knows its HomeKit accessories by, is a `HomePadDocumentDescriptor` (`Module/HomePadDocument.swift`), one per HomePad, which only that HomePad writes. A module that keeps anything per person on this iPad also registers `Household.onMemberIDChange`, so it moves that data when the person takes the household's ID for them on joining. A saved smart home ID may be another HomePad's HomeKit ID, which differs on every iPad, so modules look saved IDs up through `services.smartHome.localID(for:)` or `accessory(_:)`, never with `==` against the accessory list.

## Module lifecycle

Each package exposes one `HomePadModule` type. `App/Sources/Modules.swift` lists them in order, and `ModuleLoader` calls `register(services:registry:)` on each one, then `didFinishLaunching` on each one. Look up other services lazily at call time, never cache them in `register`, because a later module may replace them.

## Shared hardware

- **Which device**: the same app is the HomePad on an iPad and the companion on an iPhone or Mac, and every module loads on both. `AppRole.current` in HomePadCore says which. The iPad's own sensing runs only on a HomePad: presence (camera and sounds) and the wake phrase never start on a companion, which opens the microphone only while someone holds the intercom's talk button.
- **Microphone**: subscribe to `services.microphone` (one AVAudioEngine tap fanned out to every subscriber). Never create your own input engine.
- **Audio session**: declare needs with `services.audioSession.claim(.record / .playback / .mediaPlayback / .longFormPlayback / .voice, owner:)` and `release(owner:)`. AirPlay 2 multi-room needs `.longFormPlayback`, which pauses recording. That is an iOS constraint, not a bug.
- **Cameras**: call `services.capture.claim(owner, camera:)` before starting a capture session and `release` after. The presence sensor yields while a claim is active. `claimWhenReady` also waits until the sensor has closed its camera, so the new session gets frames at once.
- **Display**: a screen that must stay awake (cooking mode) uses `.keepsDisplayActive(_:)`. Only the shell's kiosk controller sets brightness and Auto-Lock.

## Personal content

`services.household` tracks the active member. Who is signed in is one state machine, `MemberSession` in HomePadCore, fed by recognition, touches, the People menu, Face ID and a kiosk tick (see "Who is signed in" in the Presence README). Personal data (calendar, reminders) only shows when `household.isPersonalContentUnlocked` is true, which requires recognition (face) or Face ID. Messages follows its own Require face recognition setting (docs/COMMS.md). Apps that are personal set `requiresRecognizedMember: true` and the shell shows a recognition gate. Personal widgets set `isPersonal: true` and stay hidden or locked until then. Screen summaries of personal content (a calendar day, a photo album) set `isPersonal: true`, and the assistant leaves them out until then.

Photos from the iPad follow one rule, `PhotoAccessPolicy` in HomePadCore (`services.photoAccess`): the library's owner sees the whole library while recognized, other recognized members see iCloud Shared Albums only, and guests see nothing. Anything that browses the library, the system photo picker included, checks it. Photos faces and the Photo widget are picture frames and show the sources picked for them.

## Background work

Modules register background tasks with `services.backgroundWork` (Core's `BackgroundWork`): an interval, conditions such as an idle screen or power, and the iOS background launches they may run in. The shell runs them one at a time while HomePad is on screen and nobody needs it, never during an app zoom or right after a touch, and iOS runs them in its background launches. Heavy work goes off the main actor at `BackgroundWork.priority`. Settings, Background Tasks shows each one. See the Core README.

## Dependencies

Reuse before writing. Apple frameworks come first. When no framework covers a need, use a well-maintained open-source library under a permissive license (MIT, Apache 2.0, BSD), pinned to an exact version. Write our own only when neither fits.

| Library | License | Used by | For |
|---|---|---|---|
| [HAKit](https://github.com/home-assistant/HAKit) 0.4.19 | Apache 2.0 | HomePadSmartHome | Home Assistant's own Swift client for its WebSocket API |
| [mlx-swift](https://github.com/ml-explore/mlx-swift) 0.30.2 | MIT | HomePadAssistant | Runs the on-device natural voice |
| [MLXUtilsLibrary](https://github.com/mlalma/MLXUtilsLibrary) 0.0.6 | Apache 2.0 | HomePadAssistant | Reads the voice files (`.npz`), and MLX helpers Kokoro uses |
| KokoroSwift 1.0.11, vendored | MIT | HomePadAssistant | Kokoro-82M text to speech |
| MisakiSwift 1.0.6, vendored | Apache 2.0 | KokoroSwift | Pronunciation for Kokoro, without eSpeak |
| MLXSimulatorShims, ours | | KokoroSwift | Lets MLX link for the simulator, where the voice falls back to the Apple voice |
| [WebRTC](https://github.com/stasel/WebRTC) 155.0.0 | BSD 3-Clause | HomePadSmartHome | Google's WebRTC as a binary framework, for live Home Assistant cameras |
| [Hummingbird](https://github.com/hummingbird-project/hummingbird) 2.27.1 | Apache 2.0 | Hub | The hub's HTTP server |

They bring in Starscream (Apache 2.0) and PromiseKit (MIT) through HAKit, and swift-numerics (Apache 2.0) and ZIPFoundation (MIT) through the MLX packages.

Bundled data: `KokoroVoices.npz` (HomePadAssistant) holds ten voices from [Kokoro-82M](https://huggingface.co/hexgrad/Kokoro-82M) by hexgrad (Apache 2.0). The model weights are not in the repo: the Natural voice downloads them from a pinned Hugging Face revision of `mlx-community/Kokoro-82M-bf16` (Apache 2.0). Kitchen's test fixtures hold recipe pages and TheMealDB results, kept for tests as the Kitchen README describes.

Vendored packages live in `Packages/ThirdParty/` with their LICENSE, and their `Package.swift` says what was changed and why. A new dependency gets an exact version, a row in this table and its license checked first. Everything else is Apple frameworks and plain `URLSession`.

## Conventions

- Swift 5 language mode, Swift 6.4 toolchain, iPadOS 26 minimum (iOS 27 SDK). Gate newer APIs with `#available`.
- Services are `@MainActor @Observable final class`es. Views read them from the environment: `@Environment(AppServices.self) var services`.
- Every `Task`, observer and timer stops when its owner no longer needs it: the view disappears, the service stops or the display sleeps. No `Task.sleep` loop runs forever.
- Small files, one main type per file, folders by concern (`Services/`, `Views/`, `Backends/`, `Tools/`). Aim for files under about 300 lines.
- Doc comments on every public type and function.
- Settings go through a `SettingKey` and `services.settings`, never straight to `UserDefaults` (the store keeps decoded values). Name keys `<module>.<setting>`. Never rename a key or change a stored format: saved data on existing iPads must still load.
- What a person chose or moved to in an app (view mode, filter, tab, the date, the open album) goes in `@AppState` (`HomePadCore/SwiftUI/AppState.swift`), not `@State`, so the app reopens where it was left. Name keys `<app>.<state>`. Personal apps use `scope: .member`, values that change often use `storage: .session`, and dates use `lifetime: .timePosition`. Check that a restored item still exists and is visible to this person before showing it, and assign explicit requests (launch arguments, widgets, the assistant) when the view appears, so they win. Code outside views uses `services.appState`. Each package README says what its apps restore.
- Secrets go in `services.keychain` and never in settings or logs.
- Everything must build and run in the simulator: no camera means demo data or a clear empty state, never a crash.
- Log with `Log.make("<Category>")`. Device traces use `DebugTrace`, off unless a launch argument turns them on.
- Docs and user-facing prose: no em dashes and no semicolons.

## Build

```
make project       # regenerate the Xcode project after editing project.yml
make build         # app for the simulator
make run           # build, install and launch in the iPad simulator
make test          # Core tests on macOS, then every package's tests on the simulator
make ui-test       # UI tests in the simulator
make device-build  # signed build for a real iPad
scripts/build-package.sh HomePadSmartHome        # one package, iOS simulator
scripts/build-package.sh HomePadSmartHome test   # its tests
```

`scripts/build-slot.sh` caps concurrent xcodebuild runs (default 3, `HOMEPAD_BUILD_SLOTS`) so parallel work does not exhaust memory.
