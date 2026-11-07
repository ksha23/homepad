# HomePadCore

The contracts every HomePad module builds against: models, service protocols, the module registry, the event bus, settings, the keychain, the microphone hub, the audio session, the camera arbiter, app state, and background work. Modules never import each other, only this package and HomePadUI. [docs/ARCHITECTURE.md](../../docs/ARCHITECTURE.md) has the rules.

It builds for iOS, macOS and watchOS, so the Watch app and the tests on a Mac can use it.

## Structure

```
Sources/HomePadCore/
  Module/        HomePadModule, ModuleLoader, ModuleRegistry (apps, faces, widgets, settings panes,
                 overlays, Control Center tiles, assistant tools, screen contexts, shared documents), AppServices
  Models/        household and member session, the shared part of a person (SharedMember), presence, smart home,
                 media, personal content, tracked devices, photo access (PhotoAccessPolicy)
  Services/      service protocols and their demo stand-ins
  Background/    background work: task descriptors, the scheduling rules, the runner, iOS launches
  Events/        the event bus
  Storage/       settings, app state, keychain
  Hardware/      microphone hub, audio session, camera arbiter
  SwiftUI/       environment values, @AppState, scroll position restoration
  Extensions/    names and payloads other modules share (`<Module>/`)
  Debug/         traces, the frame rate monitor
```

## Who sees which photos

`PhotoAccessPolicy` (`Models/PhotoAccess.swift`) is the one rule for photos from the iPad, for every module:

| Person at the screen | Sees |
| --- | --- |
| The library owner, recognized | The whole library, Favorites, their albums, videos, recents, the system photo picker, Allow More Photos, and the shared albums |
| Another recognized member | iCloud Shared Albums only |
| A guest, or a member only picked in the People menu | Nothing |

Each `PhotoSource` is one case: `.library` (anything from the iPad's own library), `.sharedAlbums`, and `.memberDevice(id)` for photos a member's own iPhone shares, which only that member sees.

- The library owner is the member whose Apple Account the iPad's library belongs to. It is picked in Settings, Personal Info, Photos (`PhotoLibraryOwner.setting`, `core.photos.libraryOwner`, not synced). Until someone picks, or once that member leaves, it is the first admin, then the first member (`PhotoLibraryOwner.resolve`).
- `services.photoAccess` is the policy for the person at the screen right now: the owner and `household.unlockedMember`. Reading it in a view body redraws the view when someone is recognized, leaves or the owner changes.
- `PhotoAccessPolicy.householdSources(ownerID:)` is what background work may read ahead of time: the sources at least one member may see.
- Photos faces and the Photo widget are picture frames. They show the sources picked for them to whoever is in the room and do not ask the policy.

`PhotoAccessPolicyTests` cover the owner, another member, a guest, each source and who owns the library.

## Background work

HomePad runs in front all day as a kiosk, so most of its background work happens while the app is on screen and nobody is using it. `services.backgroundWork` (`BackgroundWork`) runs the tasks modules register, one at a time, and the same tasks in the launches iOS gives HomePad while it is in the background.

### Registering a task

```swift
services.backgroundWork.register(BackgroundTaskDescriptor(
    id: "personal.photoSync", title: "Photo Sync",
    summary: "Reads new photos and prepares their thumbnails.",
    interval: { 3600 }, conditions: .displayIdle, systemLaunches: [.appRefresh, .processing],
    prepare: { photos.startSyncing() }
) { context in
    await photos.sync(context)
})
```

- `interval` is read each time, so a setting can change it. `retryInterval` comes sooner after a failure.
- `conditions`: `.displayIdle` (nobody is using the screen: the face, dimmed, night or asleep), `.displayAsleep`, `.onPower`.
- `systemLaunches`: `.appRefresh` and `.processing`, the `BGTaskScheduler` launches the task may run in while HomePad is in the background. Empty means only while HomePad is on screen.
- `prepare` runs once when the shell starts background work on the iPad, for something long-lived such as a change observer. The iPhone and Mac companions never start it.
- `run` returns a `BackgroundTaskOutcome`: `.done`, `.skipped`, `.failed` or `.stopped`, each with a sentence for Settings.
- `requestRun(_:reason:)` asks for a run as soon as the conditions allow, for example after the photo library changed. `runNow(_:)` is Settings' Run Now: it skips the time and the conditions.

### When a task runs

The rules are pure, in `BackgroundSchedule`, and tested in `BackgroundScheduleTests`:

- A task is due when it never ran, a module asked, its last run stopped part way, or its interval (or retry interval after a failure) passed since its last run.
- Nothing starts while an app zooms open or closed, right after a touch, or while the iPad is hot. Then the task's own conditions must hold. In the background the display is not HomePad's, so only power counts.
- Among the due tasks that may start, the most overdue goes first. One runs at a time.

### While a task runs

Runs start on the main actor at `BackgroundWork.priority` (`.utility`). The heavy part of a run belongs off the main actor at that priority, so it never takes a frame from the screen. Between steps a task calls `await context.checkpoint()`: it waits while an app zooms, a touch has just landed or the iPad is hot, and returns false when the run should end, because one of its conditions stopped holding (someone started using the screen) or iOS's time for a background launch ran out.

### Who drives it

The shell (`BackgroundWorkHost`) starts it on the iPad, reports what the iPad is doing on every kiosk tick (`update(_:)` with a `BackgroundEnvironment`), and asks iOS for the next background launches as HomePad leaves the screen (`scheduleSystemLaunches()`). `registerSystemLaunches()` registers the two identifiers in Info.plist's `BGTaskSchedulerPermittedIdentifiers`, the bundle identifier plus `.background.refresh` and `.background.processing`, during launch. Each launch runs every due task that allows that kind of launch. A processing launch asks for the network, and for power when a task waits for it.

Records (last run, when it ended, the outcome, a pending request) live in Application Support/BackgroundWork/records.json, not in settings, since a settings write redraws every view that reads one. Settings, Background Tasks lists every task with them and has Run Now.

## The household's shared setup

Paired HomePads share the household's people, Home Screens and faces. Core holds the contracts and Connect carries them (see "The household's setup" in the Connect README).

- `SharedDocumentDescriptor` (`Module/SharedDocument.swift`): a module registers one per kind of document with `registry.register(sharedDocument:)`, with a `read` and an `apply` for the household (`SharedDocumentOwner.household`) and each person. `read` returns `.none` for nothing saved, `.content` for what every HomePad shows, or `.onlyThisHomePad` for something that belongs to this iPad for now, such as a photo wallpaper. Reading right after applying must return what was applied. `JSONValue(encoding:)` and `decoded(as:)` turn Codable values into a document's content and back.
- Same on All HomePads (`Module/WidgetSettingsOnEachHomePad.swift`): a widget whose switch is off keeps its own settings on each HomePad. `WidgetSettings.isSameOnAllHomePads` and `setSameOnAllHomePads(_:)` read and change it, through a mark under the reserved key `homepad.eachHomePad` with an ID that is the same on every HomePad. A descriptor whose document holds widget settings calls `sharingWidgetSettings()` on what `read` returns, so such a widget carries the copy it had when the switch went off, and `keepingOwnWidgetSettings(from:)` on what `apply` gets, with this iPad's current document, so it keeps this iPad's own. Both work on the JSON tree, so a widget's settings are found wherever they sit, in a stack or not. `AppServices.homePadsSharingSetup` says how many other HomePads share the setup, and Edit Widget shows the switch only while it is more than zero.
- `HomePadDocumentDescriptor` (`Module/HomePadDocument.swift`): a document each HomePad keeps about itself, registered with `registry.register(homePadDocument:)`. `read` returns this HomePad's own, or `.onlyThisHomePad` while it is not known yet to keep the copy shared before. `apply` receives every other HomePad's, with its device ID. Only the HomePad it describes writes it, so HomePads never overwrite each other's. The Smart Home module shares the names it knows its HomeKit objects by this way.
- `SmartHomeService.localID(for:)`: the ID this HomePad knows an accessory, scene or camera by, for an ID saved on any HomePad. HomeKit gives one accessory a different identifier on every iPad, so a favorite, a widget's accessory or a face's camera picked on one HomePad is read through it on the others. `accessory(_:)`, `favorites` and `localIDs(for:)` use it. The default returns the ID unchanged.
- `SharedMember` (`Models/SharedMember.swift`): what of a person HomePads share. Face enrollment and the current face kind (`HouseholdMember.facePreferenceKey`) are each iPad's own. `Household.applyShared` adds or updates a person from another HomePad and keeps them.
- `Household.changeMemberID(from:to:)` gives a person the ID the household knows them by when this HomePad joins its setup. Handlers registered with `Household.onMemberIDChange` run first and move each module's data for that person on this iPad. Core moves its own: app state (`AppStateStore`) and the photo library's owner.
- `SettingsStore.contains(_:)`, `keyNames(withPrefix:)` and `moveValue(fromKeyNamed:toKeyNamed:)` help with both. `stopICloudSync(forKeyNamed:)` stops taking a key from iCloud once the household shares it instead. `CoreSettings.defaultFaceID` no longer syncs through iCloud, since each HomePad sets it from the shared faces.

## Tests

`make core-test` runs the Core tests on the Mac. `scripts/build-package.sh HomePadCore test` runs them on the iPad simulator.
