# HomePadConnect

Ties HomePad into the Apple ecosystem: Siri and Shortcuts, a secure local link between HomePads and the iPhone and Mac companions, intercom, Send to HomePad, Handoff, the Family Board, each person's photos, calendars, reminders, Apple Music and Spotify sign-in from their own iPhone, alert relay, a Shortcuts launcher and the Apple Watch app.

No third-party dependencies. Everything uses Apple frameworks: Network, CryptoKit, Core Bluetooth, PhotoKit, EventKit, MusicKit, AppIntents, CloudKit, WatchConnectivity, AVFoundation, UserNotifications, PhotosUI and the system share sheet.

## Features

### Siri and App Intents

Seven intents, all usable from Siri, Shortcuts, Spotlight and the Action button:

| Intent | What it does | On a companion |
| --- | --- | --- |
| Ask HomePad | Sends the question to `services.assistant` and returns the answer as dialog | Uses the companion's own assistant |
| Announce | Speaks a typed message on HomePads, optionally one room | Same |
| Start Timer | Starts a timer with `services.timers` | Starts it on every HomePad |
| Show Cameras | Opens `cameras`, the Home app's camera grid (falls back to `home`) | Opens it on every HomePad |
| Run Scene | `SceneEntity` over `services.smartHome.scenes` | Also offers scenes HomePads report |
| Control Accessory | `AccessoryEntity` plus an action (on, off, toggle, lock, unlock, open, close). Needs an unlocked device | Uses the companion's own smart home |
| Set Face | `FaceEntity` over the registry's faces | Faces reported by HomePads |

App Shortcuts phrases include "Ask HomePad", "Announce with HomePad", "Run Good Night with HomePad" and "Show the Photos face on HomePad".

A shortcut saved on one HomePad keeps that HomePad's HomeKit IDs, which differ on the others. `AccessoryQuery` and `SceneQuery` look each one up through `SmartHomeService.localID(for:)` and answer under the ID the shortcut asked for, so a shortcut that reaches another HomePad through iCloud runs there too.

The intents live in this package (`Intents/`) and are listed by `HomePadConnectIntents: AppIntentsPackage`. Two files in the app target finish the job:

- `App/Sources/AppIntentsPackages.swift` includes the package so its intents and entities are extracted.
- `App/Sources/HomePadShortcuts.swift` holds the `AppShortcutsProvider`. The Xcode 27 build merges a package's intents and entities into the app but drops its App Shortcuts, so the provider has to be in the app target. That is why the intents are `public`.

`HomePadApp.init` sets `ConnectModule.updateShortcutParameters` so the package can refresh scene, accessory and face names for Siri after the smart home loads.

Verified in the built app: `HomePad.app/Metadata.appintents/extract.actionsdata` lists 7 actions, 3 entities and 7 App Shortcuts.

### Local-network peer link (`Link/`)

- **Discovery**: every device runs an `NWListener` advertising Bonjour `_homepad._tcp` and an `NWBrowser`. The TXT record carries the device ID, name (the room for HomePads), kind, household ID and whether a pairing code is showing. No secrets.
- **Messages**: `PeerMessage` is a versioned envelope with a JSON body and a binary attachment, so AAC audio and JPEG photos are never base64-inflated. Layout: magic `HP`, envelope version, two lengths, the JSON header, the raw payload. Types are string-backed so newer devices can add types that older ones ignore. On the TCP stream each envelope is length-prefixed (`FrameDecoder`).
- **Household pairing**: a HomePad shows a 6-digit code for three minutes. The joining device enters it. Both sides do an ephemeral X25519 agreement, derive a pairing key with HKDF-SHA256 from the shared secret plus the code, salted with the handshake transcript, and prove it with HMAC-SHA256. The host then sends the 32-byte household key sealed with ChaChaPoly. Five wrong codes close the window.
- **Sessions**: every connection repeats the X25519 agreement, mixes in the household key, proves it with HMAC in both directions, and then seals every frame with ChaChaPoly using per-direction keys and counter nonces (replays and reordering are rejected). When two devices dial each other at the same moment, both keep the session the device with the lower ID dialed (`PeerLink.keepsNewSession`), so they always talk on the same one.
- **Same Apple Account**: the household key is stored in the keychain through `services.keychain`, which syncs with iCloud Keychain, so a second device on the same account is already paired.
- The handshake is a pure state machine (`HandshakeEngine`) with no sockets, so it is unit tested end to end.
- Companions keep a session open to each HomePad while the app runs, so HomePads can push alerts and status. HomePads connect to each other once (the lower device ID dials).

### The household's setup, shared between HomePads (`Setup/`)

Paired HomePads show the same people, Home Screens and faces. Change a Home Screen, a wallpaper, a face or a person on one, and the others show it a moment later.

**What is shared.** Each piece is a document with a kind and an owner (the household, one person, or one HomePad). Modules describe their kinds with Core's `SharedDocumentDescriptor` (a `read` and an `apply` for each owner) or, for what a HomePad says about itself, `HomePadDocumentDescriptor`. Connect shares people itself from `Household`.

| Kind | Owners | What | From |
| --- | --- | --- | --- |
| `core.member` | each person | Name, avatar, color, admin, and preferences such as the assistant provider, About Me and the music source (`SharedMember`) | Connect, from `Household` |
| `shell.homeScreen` | guest and each person | Pages, apps, widgets, stacks, each widget's settings (unless its Same on All HomePads is off) and the header's mini widget | Shell |
| `shell.wallpaper` | guest and each person | Face or a gradient. A photo stays on the iPad whose library it came from | Shell |
| `faces.library` | household and each person | Saved faces with every option, widget layout, stack and mini widget, and which face is current. A Photos face's album and picked photos stay on each iPad, and so do the settings of a widget whose Same on All HomePads is off | Faces |
| `faces.rotation` | household | Smart Rotation's rules and fallback | Faces |
| `smarthome.favorites` | household | The Home app's favorite accessories and scenes | Smart Home |
| `smarthome.homeKitDirectory` | each HomePad | What that HomePad calls each of its HomeKit objects, so the others can read the HomeKit IDs it saves (see "The same accessory on every HomePad" in the Smart Home README) | Smart Home |

**A HomePad's own documents.** A document of a HomePad (`HomePadDocumentDescriptor`) travels as a household document whose kind also names the HomePad, `<kind>@<device ID>`, such as `smarthome.homeKitDirectory@<UUID>/household` (`HomePadDocumentKind`). Each HomePad writes only its own, so the last writer rule never has two HomePads competing for one, and every HomePad keeps the latest of every other, passing on what it holds of one that is off. One that comes back older than this HomePad's own copy is recorded and answered with the current one. A module's `read` returns `.onlyThisHomePad` while it does not know yet (Apple Home still loading), so a restart never shares an empty copy. A HomePad from before these documents reads the key as usual and leaves it out as a kind it does not know.

**What stays on each HomePad.** The settings of a widget whose Same on All HomePads is off (below), the room name, face data (templates, embeddings, learned looks and enrollment samples) and who is set up for face recognition there, the current face kind it shows (set from the shared faces), the Home Assistant device registration, Messages hub links and saved conversations, Spotify sign-in, the photo library's owner, linked phones, calendar assignments, alarms, assistant history, Control Center's layout, and everything about the screen and hardware (brightness, night schedule, kiosk, text size).

**One widget's settings on each HomePad.** Edit Widget has a Same on All HomePads switch under the preview while this HomePad shares its setup with at least one other (`AppServices.homePadsSharingSetup`, which `HouseholdSetupSync` reports as the count Settings shows). It is on for every widget at first. Off, each HomePad keeps its own settings for that widget, such as Home Favorites with the kitchen's lights in the kitchen and the bedroom's in the bedroom, on the Home Screen or a face, and for each widget in a stack on its own. The widget's place, its size and the switch are still shared.

- The settings carry a mark with an ID that is the same on every HomePad (Core's `WidgetSettingsOnEachHomePad.swift`). On each iPad they are that iPad's own, and the mark keeps beside them the copy the shared document carries: the settings the widget had when the switch went off. A descriptor shares that copy (`sharingWidgetSettings()`) and keeps this iPad's own when the document arrives (`keepingOwnWidgetSettings(from:)`, found by the mark's ID wherever the widget sits now).
- So an edit to such a widget changes nothing shared and sends nothing. Another HomePad starts from the settings it showed when the switch went off. Turning the switch back on drops the mark, and that HomePad's settings reach the others like any change.
- An older HomePad reads the layout as it always did and shows the shared copy, which is what every HomePad showed when the switch went off. The mark sits in the widget's settings, which older builds keep key for key, so what an older HomePad saves and sends back still has it, and the newer HomePads keep their own settings and the switch. A change the older HomePad makes to the widget becomes the shared copy, which only it shows.

**Why the peer link, and not iCloud.**

- The household is the peer link's pairing. iCloud key-value storage follows an Apple Account, so it would reach an iPad on that account that is not in the household and miss a HomePad on another account. The peer link works the same on one Apple Account or several.
- Shared documents need a version per document, deletions and a join that matches people by name. iCloud key-value storage keeps one value per key, decides by its own clock and knows nothing of the household's people, whose IDs differ from iPad to iPad until they are shared.
- Two channels writing the same keys with no shared versions lose edits: an older copy arriving late on one overwrites a newer edit that came on the other. So the saved faces (`faces.library`), Smart Rotation (`faces.auto.rules`), the current face kind (`core.display.defaultFace`) and the Home favorites (`smarthome.favorites.accessories`, `smarthome.favorites.scenes`) no longer sync through iCloud, and a HomePad ignores what an older HomePad still writes there (`SettingsStore.stopICloudSync(forKeyNamed:)`).
- HomePads are always on and at home on one network, which is all the peer link needs. A HomePad that was off catches up when it reconnects.

**Versions and conflicts.** Every document carries a `SetupVersion`: how many times it changed, and the device and time of its last change, in whole milliseconds. The last writer wins per document: the later time, then the higher number, then the higher device ID, so every HomePad picks the same one. A change made after seeing a version is stamped at least a millisecond after it, so it wins even when this iPad's clock is behind. A deletion (a layout reset to its default, a person removed) is a version with no content, a tombstone, kept for good so a HomePad that was off for months still learns of it. The rules (`SetupMerge`) are commutative, associative and idempotent.

**How changes travel.**

1. `HouseholdSetupSync` scans: it reads every document, and one whose content differs from the shared copy in its ledger gets a new version. It watches what the reads touch with Observation, so a change here is shared 0.6 seconds later (`localChangeDelay`), a burst of edits such as paging through faces in one message. A document a module reports as `onlyThisHomePad` (a photo wallpaper) is left as it was shared.
2. Changes go to every HomePad of the household (`setup.documents`). The receiver applies a newer version and records it as it reads back, so it never sends it on or back as a change of its own. An older version is answered with the newer one. Nothing goes back and forth.
3. When a session between two HomePads opens, both send `setup.hello` with the version of every document they hold, and each answers the other's with what it lacks or holds older. This is how a HomePad that was off catches up.

The ledger (`SetupLedger`) is one JSON file, Application Support/HomePadConnect/HouseholdSetup.json: the shared copy of every document, the household it shares with, and the HomePads it synced with. It holds no face data and no secrets.

**Joining a household that already has a setup.** A HomePad that does not share the household's setup yet, because it was set up on its own (as a second iPad that joined through iCloud Keychain) or was just paired with a code, joins it the first time it meets a HomePad that does.

- Who keeps its setup (`SetupStanding`): a HomePad that already shares the household's setup always does. Between two that do not yet, as with two HomePads set up apart that update to this version together, the one that hosts the household wins, having shown a pairing code for it, the first of which made the household's key (`connect.setup.hostedHousehold`), then the one installed first (when iOS made its Documents folder), then the lower device ID. Both decide the same way from each other's hello. So Show Pairing Code on the HomePad whose setup should win, before the other first shares, settles it.
- The winner sends its complete set (`isComplete`). The newcomer then:
  1. Matches its people to the household's by name, ignoring case, accents and spacing, one to one and in order (`SetupJoinPlan`). Someone with the household's ID already is a match without a change.
  2. Gives each matched person the household's ID (`Household.changeMemberID`). Every module first moves what it keeps for them on this iPad (`Household.onMemberIDChange`): face templates and learned looks (Presence), Home Screen layout, wallpaper and wallpaper photo (Shell), saved faces (Faces), linked phones, phone photo sharing and Use My Apple Music (Connect), the Messages hub and saved conversations (Comms), alarms (Kitchen), calendar assignments, unchecked calendars and Find My owners (Personal), the music queue (Audio), assistant history (Assistant), and app state and the photo library's owner (Core). Face data is moved on this iPad and never sent.
  3. Applies the household's documents. The household's people, layouts, wallpapers and faces replace its own wherever the household has them, deletions included.
  4. Shares what the household lacks: its people with no match, with their Home Screens, wallpapers and faces, and its own layout, wallpaper or faces for a matched person or the guest where the household never had one.
- So the newcomer's own Home Screens and faces survive only where the household had none. Nothing of a matched person's is lost on this iPad that is not shared: their face data, Messages, alarms and history stay theirs.
- A join can take a household past six people (`Household.applyShared`), so nobody is dropped. Add Person stays off while there are six or more.

**Screen sizes.** Nothing is copied point for point. A Home Screen layout is logical pages of apps and widgets in order. Every iPad lays it out on its own grid: six columns in landscape and four in portrait, and as many rows as its screen holds, 3 on an 11-inch iPad in landscape and 4 on a 12.9 or 13 inch one. A page that fills a 13-inch screen goes on to a second screen on an 11-inch, in the same order (`HomeScreenPages.render`). A face's widgets are saved by cell on a grid that is six by four in landscape and four by six in portrait on every iPad, and its cells only grow with the screen. Each iPad works out which cells the face's own content needs at its size, and a widget whose cell is needed there moves to a free area or steps down a size without changing what was saved (`FaceWidgetBoard`). What can differ between iPads: how many screens a Home Screen page takes, where a face widget waits when its cell is taken, and the text size, whose largest settings drop a Home Screen column on that iPad.

**Status.** Settings > Devices & Sharing > Shared Setup says "Synced with 1 HomePad" with the last sync time, names the HomePads in the footer, and lists who still needs face recognition set up on this HomePad (`SharedSetupSection`). The same count is `AppServices.homePadsSharingSetup`, for modules that show something only while HomePads share their setup.

**Versions.** `SetupHello.currentVersion` is 1. HomePads from before this ignore the `setup.*` messages, so they neither send nor change anything. A hello with another version is ignored.

### Personal device approval (`Approval/`, installed as `services.personalDevices`)

The recognition gate's Use Personal Device, as on HomeView: someone opening a personal app approves it on their own iPhone or Mac.

**Linking a device to a person** (once per HomePad):

1. On the iPhone, open the HomePad's remote. Its Unlock With This iPhone card lists the HomePad's household (`approval.state`). Pick who uses the iPhone.
2. The iPhone makes its approval key if it has none (`DeviceApprovalKey`) and sends the public half with the member (`approval.link`).
3. The HomePad shows a banner: "Let Kyle's iPhone unlock Kyle's apps?" (`LinkRequestOverlay`). Allow works only if that member is recognized at the HomePad right now, or the iPad's owner passes Face ID or the passcode. Don't Allow, or two minutes without an answer, turns it down.
4. The HomePad keeps the link (`LinkedDeviceStore`, setting `connect.approval.devices`: device ID, name, member, public key, protocol version) and tells the iPhone (`approval.state`). Settings > Devices & Sharing > Personal Devices lists links and removes them. Stop Unlocking on the iPhone removes its own. Removing a person drops their links.

**Approving** (each time):

1. The gate shows Use Personal Device only when the member has a linked device that speaks `RemoteProtocol.personalDevices` (`approvingDeviceName(for:)`).
2. Tapping it sends an `ApprovalRequest` to that member's linked devices: a new request ID, a 32-byte random nonce, the member, the HomePad and the app. `ApprovalLedger` opens it for 30 seconds on the HomePad's clock.
3. The iPhone shows it only when it came from the HomePad it names, is for the member this iPhone is linked to there, is new to it, and is inside its lifetime counted from arrival. In front it is a sheet, "Unlock Messages?", with Unlock and Don't Allow side by side. In the background, while the app still runs, it is also a local notification. It closes after 30 seconds.
4. Unlock asks for Face ID or the passcode (LocalAuthentication), then signs the request with the device's key and sends `approval.response`. Don't Allow or the close button sends a denial. The sheet needs an answer, so it does not swipe away.
5. The HomePad accepts an answer only if it answers an open request (`unknownRequest`, `replayed`), before its 30 seconds end (`expired`), from a device linked to that request's member (`wrongDevice`), and for an approval, with a valid signature from that device's key over the request (`badSignature`). Answers that fail are dropped and the request stays open, so a forged answer cannot end it.
6. Approved, the gate calls `household.recognize`, as Use Face ID does, and the app opens. Denied shows "Kyle's iPhone didn't allow it.", no answer shows "Kyle's iPhone didn't answer in time.", and an unreachable device shows "Kyle's iPhone isn't reachable. Open HomePad on it, then try again." Closing the gate, or using Continue or Face ID instead, withdraws the request. When a request ends, the HomePad sends `approval.closed` so other prompts go away.

**The approval key.** On an iPhone or Mac with a Secure Enclave the P256 key is made inside it with `.privateKeyUsage` and `.userPresence`, and only on a device with a passcode. It cannot be read out, and it signs only after Face ID, Touch ID or the passcode. The gate's prompt passes the already verified `LAContext` to the key, so the person is asked once. The simulator has no Secure Enclave, so there the key is a software key. Both are kept in a keychain item that is this device only and never syncs.

**Threat model.**

- *What it protects.* Personal content on a HomePad (messages, calendars, reminders), the same thing Use Face ID unlocks. Approving unlocks that member's personal content on that HomePad until the household's session ends (see "Who is signed in" in the Presence README), not only the app named.
- *Trusted.* Paired devices share one household key, so on the peer link any of them can say it is any device. The link keeps strangers out (see Sessions). It does not tell household devices apart. Approval adds that with the per-device key: only the linked device's key signs, so another member's phone, a HomePad or any household device cannot approve for someone else even when it uses the phone's device ID.
- *Replays.* Each request has a fresh ID and nonce, is single use and lasts 30 seconds. The signature covers the ID, the nonce, the member, the HomePad and the app as the phone showed them, so an approval fits one request only and a changed app or room name breaks it.
- *Linking.* This is the trust step. A household device can ask to be anyone's, so the HomePad waits for someone at it: the member recognized there, or the iPad's owner with Face ID or the passcode. An iPad without a passcode allows it with a tap, as it allows Use Face ID.
- *A lost or stolen iPhone.* It approves only with its own Face ID or passcode, and only on the home network with the household key. Remove it in Personal Devices.
- *Push fatigue.* Someone at the HomePad can send a request to a member's phone and hope they tap Unlock. The prompt says who is asking, where and what it unlocks, and asks to approve only if it is you.
- *Denials and drops.* A denial is not signed, so a household device that says it is the phone could deny a request. That stops an unlock, never grants one, as any household device could already disrupt the link.
- *Not covered.* Someone who already holds the household key and controls the network can block or delay requests. Face recognition itself is weaker than Face ID (see the Presence README), and Use Personal Device does not change it.

**When the iPhone app is closed.** The HomePad reaches a companion only over its open session, which iOS ends soon after the app leaves the screen. While the app is open, the prompt shows at once. Just after it goes to the background and while it still runs, a local notification shows, and tapping it opens the app on the prompt. Once iOS suspends or closes the app there is no session, and the gate says the phone isn't reachable. Waking a closed app needs push notifications (APNs) from a server, which HomePad does not have.

**The HomePad's key.** Each HomePad also has its own P256 signing key (`HomePadKey`), a software key in its Keychain that never syncs. `approval.state` carries its public half (`homePadKey`), and a linked phone keeps the first one it sees. Phone visits use it (below).

**Versions.** `RemoteProtocol.personalDevices` (3) adds the `approval.*` messages. A HomePad that reports an older version shows "Update HomePad on Kitchen" in the card instead. The iPhone sends its version when it links, and the gate offers only devices that linked at version 3 or later. HomePads and phones before version 3 ignore the new message types.

### Each person's data from their own iPhone (`PhoneVisit/`)

As on HomeView, a person's own photos, calendars and reminders show at the HomePad while they are recognized there, read on their own iPhone and sent over the encrypted peer link. Nothing goes to a server. Each kind is chosen on the iPhone, and the HomePad reaches the phone in one **visit** that carries every kind it shares: one Bluetooth wake, one signed challenge and one session.

**What the person does on their iPhone, once per HomePad:**

1. Link the iPhone to themselves in the HomePad's remote (Unlock With This iPhone, above).
2. Under it, turn on **Show My Photos** (`PhonePhotosCard`), and in **Show My Calendars** (`PhoneCalendarsCard`) check the calendars and reminders lists that HomePad may show. iOS asks for photo access, full Calendar and Reminders access as each is first chosen, and then for Bluetooth.

After that they do nothing. Whenever the HomePad recognizes them, its Photos app shows "From Kyle's iPhone", and its Calendar, Up Next, Reminders, the glance, the faces and the assistant include the checked calendars and lists (see the Personal README for the screens).

**The visit** (`PhoneVisitClient` on the HomePad, `PhoneVisitServer` on the phone). A visit starts when `household.unlockedMember` has a linked phone that shares something, and ends when that changes. Each kind is a part: `PhonePhotosClient` and `PhoneCalendarsClient` on the HomePad (`PhoneVisitPart`), `PhoneLibraryServer` and `PhoneCalendarServer` on the phone (`PhoneVisitServing`). The visit owns what they share: which phones share what (`SharedPhone`, with its kinds), the Bluetooth wake, the handshake, the session, request and answer matching, and closing. Each part keeps its own state for the visit and its own encrypted cache. A woken app gets about 10 seconds, up to about 30 with a background task and never guaranteed, so after the phone opens, each part fetches what it needs first, in order: calendars and reminders (a few small answers that Up Next and the glance show at once), then photos (the album list and many images). Then the HomePad closes the session, once no change waits for an answer.

**How the HomePad reaches a phone that is not open.** iOS suspends the companion soon after it leaves the screen and closes its sockets, so the peer link alone reaches a phone only while HomePad is open on it. The HomePad wakes it over Bluetooth instead (`Wake/`):

- The HomePad is a Core Bluetooth peripheral (`HomePadWakeBeacon`). It offers one service, `ProximityWake.service`, with a `wake` characteristic to subscribe to and a `hello` characteristic to write, and advertises only the service's UUID, never the room or a name. It runs only while some linked phone shares something, so nobody else is asked for Bluetooth. iOS advertises only while the app is in front, which a HomePad always is.
- The iPhone is a central with the `bluetooth-central` background mode and a restore identifier (`PhoneWakeListener`). While anyone shares, it scans for the service, connects to each HomePad it finds, writes its wake tags to `hello` and subscribes to `wake`. A waiting connection never times out, so a HomePad that comes back in range reconnects by itself. iOS keeps scanning and connecting for the app after it ends it, and relaunches the app in the background for these events (state restoration).
- Each tag is 16 random bytes the iPhone made for one HomePad and sent in its offers. Photos and calendars use the same tag for the same HomePad. Only that HomePad can tell whose phone wrote it. Nothing else crosses Bluetooth.
- When a member who shares is recognized, the HomePad notifies `wake` to the phone that wrote their tag, at most every 15 seconds. iOS wakes the app, which begins a background task (`AppBackgroundWindow`), starts the peer link over (`PeerLink.restart()`, because a suspended app's sockets may be dead) and waits for the HomePad to ask. When the phone is already connected on the peer link, the HomePad says hello first and wakes it only if it does not answer within 3 seconds. A change made on the HomePad later in the visit opens the phone the same way.

**Opening a visit** (`PhoneVisitMessages.swift`), always on one sealed session. The handshake kept the `photos.*` names it had when photos were the only kind, so phones and HomePads from before calendars still open photos with newer ones:

1. HomePad, visit hello (`photos.hello`): the member recognized here, and the kinds it wants (`kinds`, missing from older HomePads, which then mean photos).
2. iPhone, visit challenge (`photos.challenge`) with a fresh 32-byte nonce, or visit refused (`photos.refused`) with the reason: not linked to that member there (`notLinked`), sharing none of those kinds with that HomePad (`notSharing`), no access to what it shares (`noPhotoAccess`, `noCalendarAccess`, `noReminderAccess`), no key kept for that HomePad (`notVerified`).
3. HomePad, visit open (`photos.open`): its signature with `HomePadKey` over the nonce, the request, the member and both device IDs. The kinds are not signed: the phone decides them from its own settings. The HomePad signs only during a visit, that is only while that member is recognized.
4. iPhone, visit opened (`photos.opened`) with the kinds it opened: the ones asked for that the person shares with that HomePad and HomePad on the phone may read. It checked the signature with the key it kept when it linked. The grant belongs to that session only (`PhoneGrantBook`), for ten minutes at most, and ends when the session closes or the HomePad sends visit close (`photos.close`).
5. Each kind's own requests follow (below). Every request is checked again against the grant for its kind, the link and the person's choice, and every answer goes back on the session the request came in on (`PeerLink.send(_:to:onSession:)`), never to a newer session with the same device ID.

Unknown kind names are skipped on both sides, so a kind a newer device adds never stops an older one from reading the rest.

#### Photos (`PhonePhotos/`, installed as `services.phonePhotos`)

`photos.offer` says whether the phone shares its photos, with its wake tag. Then the HomePad sends `photos.request` for the album list, one album's photos, or up to 24 images at thumbnail (360 pixels) or screen size (2048 pixels). The iPhone answers `photos.reply` with albums or photos, and one `photos.image` per image with the JPEG as the attachment.

**What a visit fetches** (`PhonePhotosClient`): the album list, the photos of Recents and Favorites, thumbnails for the album covers, the newest 90 of Recents and 45 of Favorites, then screen-size images of the newest 6. An album opened later, the next thumbnails as the grid scrolls, and full images in the viewer are asked for on demand, waking the phone again when needed. Cells drawn together share one request. What is fetched is saved in the member's encrypted cache, so the next visit shows at once and asks only for what is missing. `library` is nil until the phone has opened its photos during the visit.

#### Calendars and reminders (`PhoneCalendars/`, installed as `services.phoneCalendars`)

The person checks calendars and lists one by one in Show My Calendars. The phone sends `calendar.offer` with the identifiers of what it shares (identifiers only, never names) and its wake tag, on every connect and on every change, so a HomePad that missed a change while the phone was away catches up the next time it is reachable. The HomePad drops what it saved of anything no longer listed at once.

| Message | From | What |
| --- | --- | --- |
| `calendar.request`, `calendar.reply` | HomePad, phone | The shared calendars, the phone's default first, and their events between two days, each occurrence on its own, at most 2000 and at most 400 days |
| `reminders.request`, `reminders.reply` | HomePad, phone | The shared lists, their open reminders and those checked off in the past week, at most 1000 |
| `calendar.change`, `calendar.changed` | HomePad, phone | Add an event, or change one occurrence (title, place, all day, start, end, calendar). The answer is the event as saved, or why not |
| `reminders.change`, `reminders.changed` | HomePad, phone | Add a reminder, or check one off or back on. The answer is the reminder as saved, or why not |

Events carry their title, place, times, calendar, whether they repeat and EventKit's external identifier (so an iCloud event the iPad also has shows once). Notes stay on the phone.

**What a visit fetches** (`PhoneCalendarsClient`). The saved copy shows the moment the visit starts, before the phone answers and while it sleeps. Once the phone opens, the visit first sends the changes that wait for it, then asks for the past week to six weeks ahead of events (`PhoneCalendarsPolicy.window`) and the open reminders, and saves them in the member's encrypted cache.

**Changes made on the HomePad** go to the phone and are saved there with EventKit (`PhoneCalendarStore`):

- Each change goes into the member's outbox, in their encrypted cache, and shows at once on the event or reminder: sending, then gone once the phone saved it.
- They go one at a time and in order, on the visit's session, opening the phone first and waking it over Bluetooth if needed.
- A phone that cannot be woken or does not open in 12 seconds leaves the change **waiting**: "Kyle's iPhone isn't reachable. HomePad sends this when it is." It is sent again when the phone joins the peer link, at the next visit, or on Try Again, and it waits in the outbox across visits.
- A phone that opens but does not answer in 15 seconds also leaves it waiting. The phone saves each change ID once (`connect.calendars.applied`, the last 200), and the next fetch says which of the HomePad's waiting changes it saved already, so a change whose answer got lost is never added twice or shown twice.
- A phone that answers it cannot save a change marks it **failed**, with the reason: gone from the phone, read-only there, no longer shared, no access, or EventKit said no. A failed change is not sent again by itself. The person sees what they meant with "Not saved on Kyle's iPhone", and picks Try Again or Discard Change.
- The phone saves only inside what the person shares with that HomePad: a new event's calendar, a changed event's own calendar and the one it moves to, a reminder's list. Anything else is refused as not shared. A change to a repeating event changes that day only.

#### Privacy

- Only the member recognized at the HomePad (face recognition, Face ID, or Use Personal Device) sees their phone's photos, calendars and lists. Picking someone in People is not enough, and a guest or another member never sees them. Each service's copy is nil until the visit starts (photos: until the phone opens them) and nil again the moment the person stops being recognized, with everything held in memory dropped. Never in Settings, so an admin cannot browse someone's phone calendars there.
- Everything stays on the local network: the peer link's sealed sessions, ChaChaPoly per frame. Nothing goes to a server, not even a push service.
- On the iPad, each member's caches work like Messages' (`CommsCache`), through `SealedMemberFiles`: a random 256-bit key per member and per kind in this iPad's Keychain, never iCloud Keychain, and AES-GCM sealed files. Photos keep one index and one file per image, named by a hash so the folder does not list the phone's photo identifiers, at most 800 thumbnails and 60 full images, oldest first out. Calendars keep one sealed index with the window's events, the lists' reminders and the outbox. What is saved of a kind is deleted when the person stops sharing it, and a member's whole folder and key when they share nothing more, when the phone stops being linked to them, and when they are removed from the household. Writes go through one queue per kind, so no write lands after a delete, and a change still on its way when the person leaves never writes back a deleted cache.
- Faces and face data are not involved.
- Only the Photos app shows the phone's photos, to their owner. The faces, the slideshow sources and the Photo widget never use them. The phone's calendars show wherever the owner's personal calendars show: Calendar, Up Next, Reminders, the glance, the Calendar and Modular faces, and the assistant, only while they are recognized.

#### Threat model

- *Another household device asking.* Any paired device holds the household key and can say it is the HomePad. It cannot sign the challenge with the HomePad's key, so the phone refuses it, and a new session that takes over the HomePad's device ID starts with no grant.
- *A forged wake.* Someone in Bluetooth range who learned a phone's tag can wake its app. A wake only makes the app look for HomePads on the peer link, where the rules above apply. It costs a little battery.
- *Tags over Bluetooth.* A tag is written in the clear when the phone connects to the HomePad. It is random and per HomePad, but fixed, so someone in Bluetooth range could tell the same phone connected again.
- *Changes.* A HomePad that opened a visit can change only what the person shares with it, as above. Someone recognized at the HomePad can add to and check off only their own phone's lists.
- *Not covered.* Someone who already holds the household key and controls the network could, at link time only, answer as the HomePad with their own key, since the phone keeps the first key it sees. The HomePad does not check that photos or events really come from the phone, so a household device could show made-up ones in someone's section.

#### What iOS allows, and the limits

| Phone state | What happens |
| --- | --- |
| HomePad open on the phone | The session is open, and photos and calendars arrive about a second after recognition |
| In the background, or ended by iOS | Woken over Bluetooth on recognition, ready in a few seconds |
| Locked | The same. Reading photos and calendars while locked needs a device check (see below) |
| Force quit by the person | Not woken. iOS does not relaunch a force-quit app for Bluetooth (TN3115). Saved calendars still show, and changes wait, until HomePad is opened on the phone once |
| Restarted | Woken again after the first unlock |
| Bluetooth turned off, or toggled in Control Center or with Airplane Mode | Not woken until HomePad is opened once. From iOS 26, TN3115 keeps those relaunches for AccessorySetupKit apps |
| Away from home, or on another Wi-Fi | Photos do not show. Saved calendars show, and changes wait |

Why Core Bluetooth and not an iBeacon. An iBeacon region the phone monitors would also relaunch a force-quit app, but it needs Location Always with precise location, and iOS keeps reminding the person that HomePad uses their location in the background. It wakes the app only on entering the region, so a phone at home all evening is woken once, and the next entry waits for an exit that takes 30 seconds to minutes. Core Location also relaunches an app at most once every 3 to 5 minutes when region events come back to back, and entry on a locked phone takes about 5 to 10 seconds. Core Bluetooth needs only Bluetooth, and wakes the phone on every recognition, at once, while it is connected. Its gap is a force-quit app. AccessorySetupKit could close it, since from iOS 26 iOS relaunches apps that set up their accessory with it, but whether an iPad running HomePad can be set up as such an accessory is untested.

**Versions.** `RemoteProtocol.phonePhotos` (4) adds the visit and the `photos.*` messages, and `homePadKey`. `RemoteProtocol.phoneCalendars` (5) adds the kinds in the visit hello and opened, and the `calendar.*` and `reminders.*` messages. The cards say "Update HomePad on Kitchen" for an older HomePad. Older devices ignore the new message types and the new fields, and a HomePad from before calendars still opens photos on a newer phone.

### Each person's own Apple Music from their own iPhone (`AppleMusic/`, installed as `services.memberMusic`)

The iPad plays Apple Music only through its own Apple Account, and no app can sign in another one. So a person's own Apple Music reaches a HomePad as a Music User Token: MusicKit makes it on their iPhone, for the account in that iPhone's Media & Purchases, and the iPhone hands it to the HomePad over the encrypted peer link. With it the HomePad's Music app reads their library, playlists, recently played and recommendations from the Apple Music API while it recognizes them (the Audio README has the screens). What plays still plays through the iPad's account.

**What the person does on their iPhone, once per HomePad:**

1. Link the iPhone to themselves in the HomePad's remote (Unlock With This iPhone, above).
2. Turn on **Show my Apple Music on Kitchen** in the Use My Apple Music card (`AppleMusicCard`), under Show My Photos. iOS asks for Apple Music access the first time.

The card says what it does, that plays there count toward the iPad's Apple Music account and not theirs, that songs they uploaded cannot play there, and that the token goes over the home network only, stays on that iPad and is deleted when they turn it off. It notes when Sync Library is off, since then the HomePad sees no library. Kyle has nothing else to do beyond what Apple Music on the iPad already needs: the MusicKit App Service on for `com.ksha23.homepad`, which makes the developer token on both devices.

**The token.** On the iPhone, `MusicKitUserTokens` asks `MusicAuthorization.request()` if needed, then `DefaultMusicTokenProvider().developerToken(options:)` and `userToken(for:options:)` (`MusicUserTokenProvider`, iOS 15 and later, the same in the iOS 26 and 27 SDKs). `.ignoreCache` asks for a fresh one when a HomePad found the old one turned down.

- *Developer token.* MusicKit makes it for HomePad's App ID. Apple caps a developer token at six months (`exp` at most 15777000 seconds). MusicKit renews it. The HomePad uses its own, made the same way, never the phone's.
- *User token.* Apple documents no lifetime. Developers report about six months, with no refresh token. It also stops working when the person turns off HomePad in Settings > Privacy & Security > Media & Apple Music, signs out, or their subscription lapses (the API answers 401 or 403). MusicKit makes a new one on its own when its cached one is no good.
- *Keeping it current.* The phone keeps a 12-byte SHA-256 fingerprint of the token it sent last (`AppleMusicShareChoice.tokenDigest`), never the token. Each time it connects to a HomePad it shares with, it asks `music.state.request`, and sends again when the HomePad needs a token, has lost it, or MusicKit's token is no longer the one it sent. When the API turns a token down, the HomePad forgets it and tells the member's phones (`music.state` with `needsToken`), and the phone sends a fresh one with `.ignoreCache`. On its own the phone sends at most every six hours (`AppleMusicLinkPolicy.automaticResendInterval`), so a token the API keeps turning down is not sent over and over, and it never asks the person anything in the background.

**The handoff** (`music.*` messages, `AppleMusicLinkMessages.swift`), on one sealed session:

1. iPhone, `music.share`: the member it is linked to on that HomePad, and a fresh 32-byte nonce.
2. HomePad, `music.proof`: its signature with `HomePadKey` over the nonce, the request, the member and both device IDs, only when the phone is linked to that member there (`AppleMusicProofBook`). Otherwise `music.state` with the reason.
3. iPhone: the signature must check against the HomePad key it kept when it linked (the same key phone photos use), come from the HomePad it asked, for the member it is still linked to, within 30 seconds, once (`AppleMusicShareBook`). Then `music.token` with the token, on the session the proof came in on. A proof from any other device is ignored and leaves the request open for the real one.
4. HomePad: it keeps the token only on the proof's session, for the proof's member, from a device still linked to that member, once, within 30 seconds, and at most 4096 characters. Then `music.state`: linked.
5. Turning it off sends `music.unlink`, and the HomePad forgets the token. A phone that cannot reach the HomePad keeps the turn-off (`connect.music.pendingUnlinks`) and sends it on the next connection.

**On the HomePad** (`AppleMusicLinks`, installed as `services.memberMusic`):

- One Keychain item per member (`com.ksha23.homepad.music.tokens`, account `token.<member>`), this device only: never iCloud Keychain, and not restored to another device from a backup (`KeychainStore(thisDeviceOnly:)`). The link record (`connect.music.links`: the phone, its name, when the token came, whether a new one is needed) holds nothing secret.
- The token is deleted when the person turns it off, when the phone that sent it stops being linked to them (Stop Unlocking, Personal Devices, or a link to someone else), when they leave the household, and when the API turns it down. The Audio module deletes their encrypted listing cache at the same moments.
- Nothing logs, shows or sends on a token. `MusicTokenHandoff` leaves it out of its descriptions. The only place it goes is the `Music-User-Token` header of requests to `api.music.apple.com`.

**Threat model.**

- *Another household device asking for a token.* It can say it is the HomePad, but it cannot sign the nonce with the HomePad's key, so the phone sends nothing. A new session that takes over the HomePad's device ID gets nothing either, since the token goes only on the proof's session.
- *Another household device giving a token.* The HomePad takes a token for a member only from a device linked to that member there. Any paired device can say it is that phone, so it could put its own account's music in someone's section, as it could show made-up photos. It cannot read anyone's token.
- *What the token allows.* It reads and changes that person's Apple Music library through the API, for as long as it works. HomePad only reads. Taking it off the iPad needs this iPad's Keychain.
- *Not covered.* Someone who already holds the household key and controls the network could relay a share between the phone and the real HomePad (the HomePad's signature covers both device IDs, but not the sealed session itself), and so receive the token. Signing the session's handshake transcript would close this, for photos too.

**Joining a household's setup.** When the HomePad gives a person the household's ID, their token and link move to it in this iPad's Keychain. The HomePad tells each of their linked phones the new ID along with the IDs it knew them by before (`ApprovalLinkState.formerMemberIDs`), and a phone that shared for one of those goes on sharing under the new one. A phone that finds itself linked to someone else stops sharing, as before.

**Versions.** `RemoteProtocol.memberAppleMusic` (5) adds the `music.*` messages. The card says "Update HomePad on Kitchen" for an older HomePad, and older devices ignore the new message types.

### Spotify from each person's iPhone (`Spotify/`)

Each member can use their own Spotify account on a HomePad (Audio README, Each person's own account). They sign in on their own iPhone, so nobody types a password on the wall, and the HomePad keeps the sign-in for that member only.

**What the person does on their iPhone, once per HomePad:**

1. Link the iPhone to themselves in the HomePad's remote (Unlock With This iPhone, above).
2. Under **My Spotify** (`SpotifySignInCard`), choose Sign In to Spotify, sign in to their own account on Spotify's page, and confirm with Face ID.

The card then shows the account, what it does there, and Sign Out on Kitchen. When Spotify ends the sign-in after six months, the card offers Sign In Again. A HomePad that does not answer `spotify.state` gets "Update HomePad on Kitchen".

**How it travels** (`spotify.*` messages, `SpotifyHandoffMessages.swift`):

1. iPhone, `spotify.state.request`. HomePad, `spotify.state`: whether the phone is linked to someone there, and that member's Spotify (`SpotifyMemberAccount`): set up or not, the household's client ID, the account's name, signed in, or ended.
2. The phone runs Spotify's sign-in itself, for that client ID, with PKCE (`SpotifyPKCE` in Core). The browser session shares Safari's, so a Spotify sign-in Safari already has is offered, and `show_dialog` makes Spotify ask which account.
3. iPhone, `spotify.hello`: the member it is linked to, a fresh 32-byte nonce and a one-time X25519 public key.
4. HomePad, `spotify.challenge`: its own one-time X25519 public key and nonce, signed with its key (`HomePadKey`) over both keys, both nonces, the member and both device IDs. Or `spotify.refused`: not linked to that member there (`notLinked`), Spotify not set up (`notSetUp`), no key (`notVerified`).
5. The phone checks the signature with the key it kept when it linked (the same key phone photos use). Then it derives a key from the two X25519 halves with HKDF-SHA256 salted with the request and both nonces, seals Spotify's one-time code and the PKCE verifier with ChaChaPoly (`SpotifyHandoffSeal`), and signs the exchange and the sealed bytes with its approval key after Face ID.
6. iPhone, `spotify.handoff`, on the session the challenge came on (`PeerLink.send(_:to:onSession:)`).
7. The HomePad takes it only from the device linked to that member there, on the session its hello came on, within 60 seconds, signed with that device's key, and opening with its own one-time key (`SpotifyHandoffBook`, tested). Each hello is used once, and a failed answer leaves it open. The Audio module's media service (`SpotifyMemberAccounts` in Core) exchanges the code for tokens and keeps the refresh token in this iPad's Keychain for that member.
8. HomePad, `spotify.result`: the member's Spotify there now, or why not, such as an account missing from the developer app's user list.

Sign Out on the card sends `spotify.signOut` with the member. The HomePad acts on it only from a device linked to that member, and answers with `spotify.state`.

**Privacy.**

- The password is typed on the person's own phone, on Spotify's own page. The HomePad never sees it.
- What crosses the link is Spotify's one-time code and verifier, sealed to that HomePad. The HomePad exchanges them itself, so the refresh token is made on the HomePad and never exists on the phone. The phone keeps nothing.
- On the HomePad the refresh token is in this iPad's Keychain under the member's ID, never iCloud Keychain, never logged, and removed when they sign out or leave the household. Logs say only that a sign-in linked or why it did not.
- Nothing goes to any server but Spotify's.

**Threat model.**

- *Another household device asking as the HomePad.* It cannot sign the challenge with the HomePad's key, so the phone sends nothing.
- *A household device in the middle.* It can open its own sessions to both and pass messages on, since every paired device holds the household key. The sign-in is sealed to the HomePad's one-time key, which the HomePad's signature covers, so the device in the middle cannot read the code or swap in its own key.
- *Another household device handing over a sign-in as Kyle's phone.* It cannot sign with Kyle's phone's approval key, so the HomePad drops it. A phone can hand over a sign-in only for the member it is linked to there, so Kyle's phone cannot fill Sam's account.
- *Sign-out.* It is not signed, so a household device that says it is Kyle's phone could sign Kyle's Spotify out on a HomePad. That only ends a sign-in, as any household device could already disrupt the link.
- *State.* `spotify.state` tells the asking device its member's Spotify name and the household's client ID, which is not a secret under PKCE. A household device that says it is Kyle's phone could read Kyle's Spotify name.
- *Not covered.* As for phone photos, someone who holds the household key and controls the network at link time could answer as the HomePad with their own key, since the phone keeps the first key it sees.

**Versions.** No `RemoteProtocol` bump: the phone asks with `spotify.state.request`, and a HomePad that does not answer is too old. Older devices ignore the new message types.

### Intercom (`Intercom/`, installed as `services.intercom`)

- Push to talk records from the shared `services.microphone` tap into AAC (.m4a) on a background queue, then sends to one room or every HomePad.
- Clips play on arrival with an "Intercom from Kitchen" glass banner (`connect.intercom` overlay). With Quiet in Night Mode the banner offers a Play button instead.
- Typed announcements are spoken with `AVSpeechSynthesizer` ("Kitchen says: dinner is ready").
- Intercom app (`intercom`): room chips, a big push-to-talk button (the primary color on frosted material at rest, white on the accent while recording), a typed announcement field and history with replay. It reopens on the room it was set to (`ConnectAppState.intercomTarget`, an `@AppState` shared by the household, on the companion too), or Everywhere once that HomePad is out of reach. A half-typed announcement is not kept.
- Also an "Intercom, Everywhere" small widget and Control Center tile, like HomeView's Home Modular face. Hold to talk.
- Posts `.intercomReceived` and `.wake`.

### Send to HomePad (`Sharing/`, `ShareKit/`)

- Companions send a link, recipe link, note or photo (`PhotosPicker`, scaled to 2048 px JPEG).
- The HomePad posts `kitchen.importRecipeURL` or `kitchen.importRecipeText` for recipes and `connect.photoReceived` (`{"path", "from"}`) for photos, then shows the item in a glass banner with Share and Pin to Board actions.
- Remote commands (`RemoteCommand`): show face, open app, go to face, start or cancel a timer, ask the assistant, run a scene, and music (`.media(command:)`). They map to `.showFace`, `.openApp`, `.goAmbient`, `.invokeAssistant`, `services.timers`, `services.smartHome` and `services.media`. HomePads answer with a `HomePadStatus` (faces, apps, timers, scenes, now playing, protocol version).

### Remote music (`Remote/`)

The iPhone and Mac companions control each HomePad's music, through the HomePad's `services.media` only, so it works whatever the Audio module does inside.

- **Commands** (`MediaCommand`): play, pause, next, previous, seek, volume, move to a speaker (`MediaService.outputs`) and play a search (`MediaService.playSearch`). The HomePad checks every value first: volume is clamped, positions must be finite, searches are trimmed and at most 200 characters, and a speaker must be one of its outputs.
- **Replies**: the HomePad answers each command with a `CommandReply` (`command.reply`, matched by the command's message ID): done with a sentence such as "Playing Blue in Green.", failed with the reason, or unsupported. The companion waits 10 seconds, and accepts a reply only from the HomePad it asked.
- **Live status**: a screen that shows a HomePad's music sends `media.subscribe`. While anything watches, the HomePad pushes a `RemoteMediaStatus` (`media.status`) on each change: title, artist, cover, progress, volume, where it plays and its outputs. It finds changes with Observation, plus a check every 2 seconds for a jump in position, and sends nothing for steady progress, which the phone moves on by itself. Leaving the screen, the app going to the background or the session closing ends the watch. Web covers travel as their address (Apple Music's `musicKit://` covers as the catalog image inside them). Covers in a file go once per cover as a 600 pixel JPEG attachment.
- **Versions** (`RemoteProtocol`): HomePads report `remoteVersion` in their status. Version 2 adds music, and a HomePad that sends no version speaks version 1. The companion checks the version before it sends a music command and says "Update HomePad on Kitchen to use this from here." instead. A HomePad answers a command it cannot read with `.unsupported`, so a newer command fails politely. Kinds of source and speaker travel as text, so a kind a newer HomePad adds never stops an older phone from reading the rest.
- **Seek** works when the media service adopts Core's `MediaSeeking` and says `canSeek`. The Audio module's `AudioMediaService` does, so a song shows a scrubber and live radio a plain progress bar.

### Share extension "Send to HomePad"

Target `HomePadShare` in `Extensions/HomePadShare`, linking only `HomePadShareKit` (a nested package in `ShareKit/`). The flow:

1. In any app's share sheet, Send to HomePad reads the URL, text or image, guesses recipe or link from the URL, and offers the HomePads the app last saw (`Outbox/targets.json`).
2. It writes the item to `group.com.ksha23.homepad/Outbox/<id>.json` (and `<id>.jpg`) and posts the Darwin notification `com.ksha23.homepad.outbox.didEnqueue`.
3. The app delivers the outbox over the peer link when that notification arrives, when it becomes active, and on `homepad://outbox`. Items stay queued until a HomePad accepts them.

The extension never touches the household key or the network, which keeps it small and keeps secrets in the app.

### Handoff (`Handoff/`)

- Advertises `com.ksha23.homepad.recipe` (with the recipe's `webpageURL`, so Safari on a Mac can open it), `com.ksha23.homepad.nowplaying` (with an Apple Music search URL) and `com.ksha23.homepad.assistant`.
- Kitchen and the assistant announce content by posting `HomePadEvent.handoffRecipe(title:url:)` or `.handoffAssistant(prompt:answer:)` (in Core, see below). Now playing comes from `services.media`.
- Activities handed to HomePad post `.handoffReceived(activityType:payload:)` with the user info as JSON.

### `homepad://` URLs (`DeepLinks/`)

The app posts `.custom(name: "openURL", ...)`. `DeepLinkHandler` routes:

| URL | On a HomePad | On a companion |
| --- | --- | --- |
| `homepad://app/<id>` | `.openApp` | Sent to HomePads |
| `homepad://face/<id>` | `.showFace` | Sent to HomePads |
| `homepad://ask?q=` | `.invokeAssistant` | Sent to HomePads |
| `homepad://recipe?url=` | `kitchen.importRecipeURL` | Sent to HomePads as a recipe |
| `homepad://timer?minutes=5&label=Tea` | Starts a timer | Sent to HomePads |
| `homepad://outbox` | Delivers queued shares | Same |

### Family Board (`Board/`, app id `board`)

- Sticky notes in a fixed six-color palette, pinned first, signed by the recognized member or the room.
- Notes are the size of a sticky note, however many there are. They sit in columns that aim for 240 points (about 13 characters of note text a line) and widen with the text size, so landscape holds four columns on the 11-inch and five on the 13-inch, and portrait three and four. Each note is as tall as its text, at least half its width and at most six lines, then an ellipsis. `MasonryLayout` (in `Views/Components/`, a HomePadUI candidate) puts each note under the shortest column. A few notes leave the board empty below them, and many scroll.
- The line over a note's text says who wrote it, when, and whether it is pinned. The text is Title size for reading across a kitchen.
- The composer and the editor (a tap on a note) are a sheet with HomePad's header: Post (Save for a note that exists) beside the close button, dimmed while the note is empty. Command-Return posts from a hardware keyboard.
- The note being written is the hero (`NoteComposer`): the board's note magnified, a board column wide in the board's paper, fonts and byline times a scale, so its lines break where they will on the board. The scale fills the room above the keyboard, up to 1.6 times, and shrinks as lines are added so the whole note stays in view. Below 0.8 times the text scrolls inside the note instead.
- Its options follow the room. When the room is wider than tall, as in landscape with the on-screen keyboard up, the colors in rows of three, Pin to Top and Delete Note are a narrow column beside the note. Otherwise, as in portrait or with a hardware keyboard, they sit under it. One layout holds both, so the keyboard stays up when they move. Nothing sits under the keyboard.
- Notes keep their paper colors and black text in either appearance, like real sticky notes, while the board, the sheet and the options around them follow it. The selected color's ring and a lit Pin to Top use the primary color.
- At night every note is drawn on white paper, so the red night tint gives each the same readable red. Blue and green paper would go black under it.
- A note from another device fades in while the others move to make room.
- Sync over the peer link (full state on connect, after each edit, and a reply from a device that holds newer notes) and through the CloudKit private database (`iCloud.com.ksha23.homepad`, custom zone `FamilyBoard`) for devices on the same Apple Account.
- `BoardMerge` is last-writer-wins per note with tombstones, deterministic tie breaks, and 30-day tombstone pruning. Commutative, associative and idempotent, and tested as such.
- CloudKit fails gracefully: no iCloud account, a missing entitlement or no network only changes the status line in Settings.
- Also a Family Board widget (medium and large) with the board's notes at widget size: columns that aim for 150 points, at most three lines a note, and the time as "12m ago". It shows as many whole notes as its frame holds, so a tall slot on a face fills with notes and a short one never spills. The header counts the notes that did not fit, and gives way when keeping it would cost a note.

### Alert relay (`Alerts/`)

On a HomePad, `.soundDetected` for smoke or carbon monoxide (confidence 0.6 or more) and `.doorbellRang` are sent to paired iPhones and Macs, at most once a minute per alert. Companions show a system notification (time sensitive for alarms) and an in-app banner. Optionally a Home Assistant notify service (for example `notify.mobile_app_your_iphone`) is called through `services.smartHome.callService`, which reaches phones away from home.

### Shortcuts app (app id `shortcuts`)

Big tiles that run the household's saved Apple Shortcuts by name through `shortcuts://run-shortcut?name=`. The list syncs through iCloud settings. It has nothing else to restore: Edit mode ends when the app closes. The Family Board is the same, with its notes already saved.

### Companion (`CompanionRootView`)

On iPhone and Mac the app shows a tabbed remote: HomePads (pairing, status, per-HomePad remote with music, faces, apps, timers and Ask), Send, Intercom, Home (scenes and timers) and Board. Settings opens Devices & Sharing as a sheet. It uses the same HomePadUI tokens and glass components as the kiosk, and follows the phone's or the Mac's own light or dark appearance, approval prompts and sheets included.

Each HomePad's remote starts with a Music card, like a HomePod in the Home app: cover, title, artist, where it plays, and play or pause. It opens the music screen (`Views/Companion/Music/`): the cover, title, the speakers it plays on, progress, previous, play or pause, next, and volume, then Play On (move the music to another output, with a check only on the speakers that play it and In Use on a speaker busy with something else) and Play Music (a search the HomePad plays, with recent searches as chips). When a search finds nothing, "Ask Kitchen Instead" sends "Play ..." to the HomePad's assistant. A HomePad too old for music control shows an update notice, and its search goes to the assistant.

At the end of each remote, Unlock With This iPhone links the iPhone to a person on that HomePad for Use Personal Device, and an approval request shows as a sheet over every tab (see [Personal device approval](#personal-device-approval-approval-installed-as-servicespersonaldevices)). Once linked, an iPhone shows four cards under it (see [Each person's data](#each-persons-data-from-their-own-iphone-phonevisit)):

- **Show My Photos**: one switch, what it does, whether Bluetooth can wake the phone, and when it last sent photos.
- **Show My Calendars**: what it does, then Calendars and Reminders, each with a Choose button that asks for full access first, then a switch per calendar or list with its color and account. Turning one off takes it off the HomePad at once. Then whether Bluetooth can wake the phone, and when it last sent calendars or saved a change.
- **Use My Apple Music**: one switch, what it shows and that plays count toward the iPad's account, and whether the HomePad has a working token (see [Each person's own Apple Music](#each-persons-own-apple-music-from-their-own-iphone-applemusic-installed-as-servicesmembermusic)).
- **My Spotify**: sign in to the person's own Spotify there, or sign it out (see [Spotify from each person's iPhone](#spotify-from-each-persons-iphone-spotify)).

### Apple Watch app

Target `HomePadWatch` in `Watch/` (watchOS 26 SwiftUI, bundle `com.ksha23.homepad.watchkitapp`), embedded in the iOS app and built by the default scheme. Three vertical pages: intercom push to talk (records with `AVAudioRecorder` and hands the file to the iPhone with `transferFile`), a timers glance and scene buttons. The iPhone's `WatchBridge` answers over WatchConnectivity and forwards clips over the peer link. The watch keys are mirrored in `Watch/WatchProtocol.swift` and `Watch/WatchBridge.swift`.

### Assistant tools

`intercom_announce`, `board_add_note`, `board_read_notes` and `run_shortcut`.

## Structure

```
Sources/HomePadConnect/
  ConnectModule.swift       registration (apps, overlays, settings, widgets, control, tools)
  ConnectRuntime.swift      composition root, reachable from intents as ConnectRuntime.current
  ConnectSettings.swift     setting keys and the curated RelayedAlert list
  ConnectTools.swift        assistant tools
  Link/                     PeerLink (+Discovery, +Pairing), PeerDevice, DeviceKind, LocalDevice
    Protocol/               PeerMessage, MessageCodec, FrameDecoder, handshake bodies
    Security/               HandshakeEngine, KeySchedule, SecureChannel, PairingCode, HouseholdCredentials
    Transport/              PeerConnection (NWConnection wrapper)
  Setup/                    The household's shared setup: SetupDocument (keys, versions), SetupMerge, SetupJoin (the join
                            plan and standing), SetupMessages, SetupLedger, SharedSetupSource, HomePadDocumentKind (each
                            HomePad's own documents), HouseholdSetupSync and its peer link transport
  Approval/                 Use Personal Device: messages, ApprovalLedger and LinkedDeviceStore, PersonalDeviceApprover (HomePad),
                            ApprovalResponder, DeviceApprovalKey and notifications (companion), HomePadKey, debug launch arguments
  PhoneVisit/               One visit to a person's own iPhone for every kind it shares: the handshake messages
    HomePad/                PhoneVisitClient (+Wire), PhoneVisit and PhoneVisitPart, SharedPhone, SealedMemberFiles
    Phone/                  PhoneVisitServer and PhoneVisitServing, PhoneGrantBook
    Wake/                   ProximityWake, HomePadWakeBeacon (peripheral), PhoneWakeListener (central), AppBackgroundWindow
  AppleMusic/               Each person's own Apple Music: the music.* messages
    HomePad/                AppleMusicLinks (services.memberMusic, the tokens), AppleMusicProofBook
    Phone/                  AppleMusicSharing, AppleMusicShareBook, MusicUserTokens (MusicKit)
  PhonePhotos/              Their photos: the photos.* messages
    HomePad/                PhonePhotosClient (+Wire), PhonePhotosCache
    Phone/                  PhoneLibraryServer, PhoneLibraryReader (PhotoKit)
  PhoneCalendars/           Their calendars and reminders lists: the calendar.* and reminders.* messages
    HomePad/                PhoneCalendarsClient (+Wire), PhoneCalendarsCache with the outbox
    Phone/                  PhoneCalendarServer, PhoneCalendarStore (EventKit)
  Spotify/                  Each person's Spotify sign-in from their iPhone: the spotify.* messages, SpotifyHandoffSeal,
                            SpotifyHandoffBook and SpotifyHandoffReceiver (HomePad), PhoneSpotifySignIn (iPhone)
  Intercom/                 IntercomHub, ClipRecorder, IntercomPlayback, models
  Remote/                   RemoteCommand, MediaCommand, CommandReply, HomePadStatus, RemoteMediaStatus, RemoteProtocol,
                            CommandExecutor, server and MediaStatusPublisher (HomePad), RemoteHomePads and RemoteMusic (companion)
  Sharing/                  ShareCenter
  DeepLinks/                DeepLink parser, DeepLinkHandler
  Handoff/                  HandoffCenter, view modifier
  Board/                    BoardNote, BoardMerge, BoardStore, CloudBoardSync
  Alerts/                   AlertRelay (HomePad), AlertNotifier (companion)
  Shortcuts/                ShortcutsLauncher
  Watch/                    WatchBridge (iPhone side)
  Support/                  debug-only demo data
  Intents/                  intents, entities, queries
  Views/                    Intercom, Board, Shortcuts, Settings, Pairing, Companion, Overlays, Approval
    Components/             PushToTalkButton (the intercom's own control) and MasonryLayout (the board's columns, a HomePadUI candidate).
                            Banners, chips and buttons come from HomePadUI
ShareKit/                   nested package: SharedItem, ShareOutbox
Tests/HomePadConnectTests/  codec, pairing and security, deep links, board merge, masonry columns, the composer's note scale, remote music,
                            personal device approval, phone photos, phone calendars, the Apple Music and Spotify handoffs
                            (an in-memory phone and HomePad), and the shared setup: versions, merge, encoding, the join plan,
                            HomePads joining, editing and catching up in memory, Same on All HomePads between two
                            HomePads, one of them an older build, and each HomePad's own documents reaching the others
                            without overwriting one another
```

## Settings (pane id `connect`, "Devices & Sharing")

| Key | Default | Meaning |
| --- | --- | --- |
| `connect.roomName` | empty | This HomePad's room, picked from smart home rooms plus common ones |
| `connect.link.enabled` | true | Run the local network link |
| `connect.setup.hostedHousehold` | empty | The household this HomePad showed a pairing code for, whose setup it keeps when HomePads first share one |
| `connect.intercom.autoPlay` | true | Play messages on arrival |
| `connect.intercom.quietAtNight` | true | Hold messages in night mode |
| `connect.intercom.speakText` | true | Speak typed announcements |
| `connect.intercom.maxSeconds` | 20 | 10, 20 or 30 seconds |
| `connect.alerts.relayed` | all | Which of smoke, carbon monoxide and doorbell relay (iCloud synced) |
| `connect.alerts.haNotifyService` | empty | Optional Home Assistant notify service |
| `connect.handoff.recipes`, `.nowPlaying`, `.assistant` | true | Handoff toggles |
| `connect.board.iCloud` | true | Mirror the board to iCloud |
| `connect.shortcuts.names` | empty | Saved shortcut names (iCloud synced) |
| `connect.music.recentSearches` | empty | On a companion: the last six music searches, newest first |
| `connect.approval.devices` | empty | On a HomePad: the phones and Macs that approve for each person, with their public keys |
| `connect.approval.linkedMembers` | empty | On a companion: who it approves for on each HomePad, as the HomePad last said |
| `connect.photos.sharing` | empty | On an iPhone: the HomePads Show My Photos is on for, with the wake tag made for each |
| `connect.calendars.sharing` | empty | On an iPhone: the calendars and lists checked for each HomePad, by identifier, with the same wake tag |
| `connect.calendars.applied` | empty | On an iPhone: the last 200 changes saved from HomePads, by change ID, so one sent again is saved once |
| `connect.photos.homePadKeys` | empty | On an iPhone: each linked HomePad's public key, kept from the first link state, for every kind |
| `connect.photos.sharingDevices` | empty | On a HomePad: the linked phones that share, with their member, wake tag and kinds (records from before calendars mean photos) |
| `connect.music.links` | empty | On a HomePad: whose Apple Music is linked, from which phone, since when, and whether it needs a new token. No tokens |
| `connect.music.sharing` | empty | On an iPhone: the HomePads Use My Apple Music is on for, with the member and the fingerprint of the token sent last |
| `connect.music.pendingUnlinks` | empty | On an iPhone: turn-offs waiting to reach a HomePad |

The Spotify handoff adds no settings. The phone reads the HomePad keys phone photos keep (`connect.photos.homePadKeys`), and the HomePad reads its links.

The shared setup's ledger is a file, Application Support/HomePadConnect/HouseholdSetup.json, not a setting.

The household key lives in the keychain (`connect.household`), never in settings. A companion's approval key lives in its own keychain item (`com.ksha23.homepad.approval`), this device only. A HomePad's own key (`com.ksha23.homepad.identity`) and each member's photo and calendar cache keys (`com.ksha23.homepad.phonephotos`, `com.ksha23.homepad.phonecalendars`) are Keychain items that never sync. Each member's Music User Token is a Keychain item of its own (`com.ksha23.homepad.music.tokens`), this device only.

The app's Info.plist has `NSBluetoothAlwaysUsageDescription` and the `bluetooth-central` background mode for the wake, and its photo library, calendars and reminders texts say what the iPhone does with them. No entitlement is needed.

## Core additions

`Packages/HomePadCore/Sources/HomePadCore/Services/PersonalDeviceService.swift`: the `PersonalDeviceService` the shell's recognition gate calls (`services.personalDevices`), its outcome `PersonalDeviceApproval`, and `NoPersonalDevices` until Connect installs its own.

`Packages/HomePadCore/Sources/HomePadCore/Services/PhonePhotosService.swift`: `PhonePhotosService` (`services.phonePhotos`), which the Personal module's Photos app reads, its models `PhoneLibrary`, `PhoneAlbum` and `PhonePhoto`, and `NoPhonePhotos` until Connect installs its own.

`Packages/HomePadCore/Sources/HomePadCore/Services/MemberMusicService.swift`: `MemberMusicService` (`services.memberMusic`), which the Audio module's Music app reads, its `MemberMusicLink`, and `NoMemberMusic` until Connect installs its own. `KeychainStore` takes `thisDeviceOnly`, for items that must not leave the device in a sync or a backup.

`Packages/HomePadCore/Sources/HomePadCore/Services/PhoneCalendarsService.swift`: `PhoneCalendarsService` (`services.phoneCalendars`), which the Personal module's calendar service merges with the iPad's own, its models `PhoneCalendarSnapshot`, `PhoneCalendar`, `PhoneEvent`, `PhoneReminder` and `PhoneWriteStatus`, and `NoPhoneCalendars` until Connect installs its own.

`Packages/HomePadCore/Sources/HomePadCore/Services/SpotifyAccounts.swift`: `SpotifyPKCE` (Spotify's sign-in page and callback, shared with the Audio module), `SpotifyMemberAccount` and `SpotifyMemberAccounts`, which the Audio module's media service adopts and `SpotifyHandoffReceiver` calls through `services.media as? any SpotifyMemberAccounts`.

`Packages/HomePadCore/Sources/HomePadCore/Module/AppServices.swift`: `homePadsSharingSetup`, how many other HomePads share the household's setup with this one, which Connect sets from the shared setup and Edit Widget reads for Same on All HomePads.

`Packages/HomePadCore/Sources/HomePadCore/Extensions/Connect/ConnectEvents.swift`: event names (`kitchen.importRecipeURL`, `kitchen.importRecipeText`, `connect.photoReceived`, `connect.handoff.recipe`, `connect.handoff.assistant`, `openURL`) and the helpers `HomePadEvent.handoffRecipe(title:url:)` and `.handoffAssistant(prompt:answer:)`.

## Simulator entry points

- `-HomePadOpenApp intercom`, `board` or `shortcuts` on an iPad.
- On an iPhone, `-HomePadOpenApp homepads|send|intercom|home|board` picks the companion tab, and `devices` opens Devices & Sharing. `homepad` and `music` open the first HomePad's remote or its music screen as soon as it is found.
- `-ConnectDemoData YES` (debug builds only) seeds shortcuts and, on an empty board, eight sample notes of mixed lengths by Alex, Sam and Jordan. With it:
  - `-ConnectDemoNotes <n>` puts exactly the first n of twelve sample notes on the board at every launch, to check one note, a few or many.
  - `-ConnectDemoEditor new` or `first` opens the composer or the first note's editor. Sheets come out sideways with `-HomePadForceLandscape`, so check them in portrait. For landscape with the keyboard up, `BoardComposerUITests` turns the simulator and types into the note. XCTest screenshots leave out the keyboard, so the test holds the screen for `xcrun simctl io <sim> screenshot`.
  - `-ConnectDemoArrival <seconds>` adds a note that long after launch, as if from another device, to record its arrival with `xcrun simctl io <sim> recordVideo`.
- Two simulators pair through the real pairing flow with no typing (debug builds only): `-ConnectPairingCode 123456` on the iPad shows that code at launch, and `-ConnectJoinCode 123456` on the iPhone, or on a second iPad, joins the first HomePad that shows a code. Two iPads paired this way share their setup, and the second joins the first's. Simulators of other checkouts on the same Mac share its network and may show codes too, so give the iPad a room of its own with `-connect.roomName '<2243616c656e646172204c616222>'` (the JSON string "Calendar Lab" as data) and add `-ConnectJoinHomePad "Calendar Lab"` on the iPhone to join only that one. Add `-HomePadAudioDemo YES -HomePadAudioDemoArtwork YES` on the iPad for music, and `-HomePadOpenApp music` on the iPhone to open the music remote.
- Use Personal Device between two simulators (debug builds only), after pairing them as above:
  - On the iPad, `-HomePadDemoContent YES -HomePadShowGate messages -HomePadMember Alex` opens the gate as Alex, `-ConnectAllowLinks YES` allows link requests 3 seconds after they arrive, and `-HomePadGateAction personalDevice` taps Use Personal Device once Alex has a device.
  - On the iPhone, `-HomePadOpenApp homepad -ConnectLinkMember Alex` links to Alex, `-ConnectApprovalSkipVerify YES` approves without Face ID (the simulator has no passcode), and `-ConnectApprovalAnswer approve` or `deny` answers each prompt after 3 seconds.
- Phone photos between two simulators, after pairing and linking them as above with `-HomePadRecognized YES` on the iPad: `-ConnectSharePhotos YES` on the iPhone turns on Show My Photos once it is linked, and `-ConnectPhonePhotosDemo YES` serves made-up photos instead of the simulator's empty library. Simulators have no Bluetooth, so this checks the peer link with the iPhone app open. `-ConnectRemoteAtEnd YES` keeps the HomePad's remote at its end, where the Show My Photos and Show My Calendars cards are.
- Phone calendars the same way: `-ConnectShareCalendars YES` on the iPhone checks every calendar and list for the first HomePad it is linked to, and `-ConnectPhoneCalendarsDemo YES` gives it made-up calendars (Personal, Climbing Club, Work) and lists (Errands, Reading), with changes kept in memory. Add `-HomePadOpenApp calendar` or `reminders` on the iPad.
- Apple Music between two simulators, after pairing and linking them as above with `-HomePadRecognized YES` on the iPad: `-ConnectShareAppleMusic YES -ConnectAppleMusicDemo YES` on the iPhone turns on Use My Apple Music once it is linked, with a made-up token since MusicKit cannot sign in on a simulator. Add `-HomePadMemberMusicDemo YES` on the iPad so its Music app answers from made-up Apple Music instead of sending that token to Apple.
- Spotify from the iPhone between two simulators, after pairing and linking them as above: `-HomePadSpotifyDemoAccounts YES -HomePadDemoContent YES` on the iPad turns Spotify on with a made-up client ID, and `-ConnectRemoteAtEnd YES` on the iPhone shows My Spotify. The sign-in itself needs a real Spotify account.
- `-ConnectDemoSyncedHomePads <n>` (debug builds only) makes one iPad simulator count as synced with n HomePads, so what shows only while HomePads share their setup can be seen without a second simulator. With the shell's `-HomePadEditWidget smarthome.favorites` it opens Edit Widget with Same on All HomePads.
- For screenshots with one simulator: `-ConnectDemoPersonalDevice YES` on the iPad gives the first person a made-up iPhone, so the gate shows Use Personal Device (it cannot answer), and `-ConnectDemoApprovalPrompt YES` on the iPhone shows a made-up prompt from Kitchen for 30 seconds.
- The app is a companion only on an iPhone or a Mac (`DeviceKind`, from the device idiom), so the remote needs an iPhone simulator. An iPad simulator always runs as a HomePad.

## Needs real-device testing

- Bonjour discovery, pairing and sealed sessions between two real devices, including the Local Network permission prompt and denial message.
- Remote music with real Apple Music and AirPlay: the volume slider moving the HomePods Apple Music plays to, the scrubber, moving music to a Music Assistant speaker, covers from the catalog, and that pushes stop when the phone locks.
- Intercom recording quality and AAC encoding from the shared microphone on iPad, playback routing with AirPlay, and night quiet mode.
- Handoff between devices on the same Apple Account (recipe to Mac Safari, now playing).
- CloudKit board sync on two devices on one account, and behavior with iCloud signed out.
- Siri phrases, Shortcuts parameters (scene, accessory and face names) and the authentication prompt for Control Accessory.
- Share extension from Safari and Photos on iPhone, and delivery after reopening the app.
- Apple Watch: install from the iPhone, microphone permission, `transferFile` delivery, and that the signed device build provisions the watch bundle ID.
- Alert notifications on iPhone, including time-sensitive delivery.
- Phone photos: the Bluetooth wake with the iPhone app in the background, ended by iOS, and locked, how long the woken app runs and how much it sends in that time, that a force-quit app is not woken and the card's advice is right, the Bluetooth prompts on both devices, PhotoKit reads while the phone is locked, iCloud-only originals for full images, and a library of tens of thousands of photos.
- Each person's own Apple Music, with a second Apple Account on an iPhone: the Apple Music prompt on the iPhone, that the token MusicKit makes there works with the iPad's own developer token, that the card notices Sync Library being off, that turning it off removes the library from the HomePad, and what the HomePad shows when the token runs out or HomePad's access is turned off on the iPhone (it should ask for a new one and get it the next time HomePad opens there).
- Phone calendars: one wake on recognition bringing calendars, reminders and photos inside the woken app's time, calendars first. EventKit reads and saves on a locked phone in the background (calendar data should be readable after the first unlock, not verified here). A change made at the HomePad reaching a sleeping phone and saved in its Calendar, and the waiting state when the phone is force quit. The full access prompts for Calendars and Reminders from the card. An iCloud calendar on both the iPad and the phone showing once. A repeating event changed for one day. A busy calendar near the 2000 event limit.
- Spotify from the iPhone: Spotify's page in the phone's browser session (Safari's sign-in offered, `show_dialog` asking which account), the Face ID prompt, the code reaching the HomePad and its exchange there, an account missing from the developer app's user list, and Sign Out from the card.
- Use Personal Device: that Face ID is asked once (the Secure Enclave key reuses the verified `LAContext`), the approval prompt on iPhone and on a Mac with Touch ID, the notification when the app was just sent to the background, the link banner and Allow on the iPad, and what an iPhone without a passcode says.
- The shared setup on two real HomePads: the first join of two that were set up apart (which one keeps its setup, the people matched by name, face recognition still working for a matched person on the HomePad that joined, Messages and alarms still theirs there), a Home Screen edit and a face swipe arriving on the other, a HomePad that was off catching up, and Home favorites and Home Favorites widgets picked on one showing the same accessories on the other (see the steps under "Needs testing on a real iPad" in the Smart Home README). Same on All HomePads on two real HomePads: the switch showing once they are synced, turning it off on one and picking different lights on each, both keeping theirs through a Home Screen edit on either and through a restart, and turning it back on on one.

## Known gaps

- Pairing resists passive eavesdroppers (ephemeral X25519), but an active attacker on the LAN during the three-minute window could brute force the 6-digit code offline from a captured proof. A PAKE (SPAKE2 or OPAQUE) would close this. CryptoKit has none.
- Phone photos and calendars do not reach a force-quit app, or one whose Bluetooth was turned off, until it is opened once. Changes made at the HomePad wait until then. AccessorySetupKit may close this from iOS 26, if an iPad can be set up as an accessory.
- A new Apple Music token reaches a HomePad only while HomePad runs on the phone. The phone is not woken over Bluetooth for it, so a token the API turned down stays missing until HomePad is opened there once. The saved library keeps showing meanwhile.
- The Apple Music handoff and phone photos sign both device IDs but not the sealed session, so someone with the household key who controls the network could relay them (see the threat model above).
- A visit goes to one phone per person. Someone who shares photos from one iPhone and calendars from another gets the one connected at the time.
- Phone calendars cover the past week to six weeks ahead. Further out the Calendar app says so, and shows the iPad's own calendars only. Events and reminders on the phone are added, changed and checked off from the HomePad, not deleted, and a reminder's due date, notes and priority are not edited there.
- Phone photos list at most 500 photos per album and 40 of the person's albums. Videos, shared albums on the phone and Memories stay on the phone.
- Alerts, intercom and approval requests reach a companion only while its app is running. iPhones in the background need push (APNs) or the Home Assistant notify fallback. Use Personal Device says the phone isn't reachable once iOS has suspended the app.
- The Share extension queues items. Delivery waits until the companion app runs. A follow-up could send directly from the extension with a shared keychain group.
- CloudKit sync saves with `.allKeys` after a local merge. Two devices editing the same note offline can briefly overwrite each other until the next peer sync. `CKSyncEngine` would be the next step.
- Intercom history is in memory only.
- The shared setup moves whole documents. Two HomePads that edit the same person's Home Screen while apart keep the later one, not both edits.
- A Reminders widget's list is an identifier from this iPad's EventKit, so on another HomePad it shows the default list until someone picks the list there. A Photos face's album and picked photos are picked on each HomePad.
- Shared setup tombstones are never pruned. Each is a key and a version.
- A HomePad that joins while its face templates are locked (an iPad locked with a passcode) cannot move them, and says to set up that face again.
- `WatchMessage` keys are duplicated between the watch target and `WatchBridge`.
- Speakers move one at a time (`MediaService.select`). Grouping speakers and adding AirPlay speakers happen on the HomePad.
- Search plays the best match (`MediaService.playSearch`). A list of results to pick from needs a search call in Core's `MediaService`.
