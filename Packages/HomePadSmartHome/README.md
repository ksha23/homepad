# HomePadSmartHome

HomePad's smart home layer. It merges Apple Home (HomeKit) and Home Assistant into one `SmartHomeService`, installs it into `services.smartHome`, and contributes the Home app (with the cameras) and the Dashboards app, the doorbell overlay, Control Center tiles, widgets, the "Smart Home" settings pane and the `home_assistant_service` assistant tool. It also provides the device trackers, zones and Play Sound behind the Personal module's Find My, and can make the HomePad a device in Home Assistant with sensors and commands (see [This HomePad in Home Assistant](#this-homepad-in-home-assistant)).

## Features

- **One service, three backends.** `UnifiedSmartHomeService` merges HomeKit (`hk:`), Home Assistant (`ha:`) and demo data (`demo:`). IDs are backend-prefixed, and commands route by prefix. Home Assistant and demo IDs are the same on every HomePad. HomeKit's differ from iPad to iPad, and saved ones are read through `localID(for:)` (see [The same accessory on every HomePad](#the-same-accessory-on-every-homepad)). The demo backend fills in whenever no real backend is set up, so the simulator always has data.
- **Home Assistant** through HAKit: long-lived token auth, `subscribe_events` for `state_changed` and registry updates, REST `/api/states` and `/api/config` for the initial load, the area, device and entity registries for room names and hidden entities, `call_service` for commands, and HAKit's automatic reconnect with backoff and pings. Bonjour discovery of `_home-assistant._tcp` runs while Settings is open.
- **Domains:** light, switch, input_boolean, fan, climate (single target and ranges), lock, cover (blinds, and garage doors, gates and doors as `.garageDoor`), camera, media_player, numeric sensors, binary_sensor, alarm_control_panel, vacuum, scene, script, and doorbell event entities. For Find My: device_tracker, zone and person.
- **HomeKit:** `HMHomeManager` with lazy authorization (only after the person taps Connect Apple Home), a home picker, services mapped both ways through characteristics, live updates through characteristic notifications, action sets as scenes, cameras through `HMCameraView`, snapshots through `HMCameraSnapshotControl`, doorbell button events, and Apple's own accessory setup sheet (`HMAccessorySetupManager`, HomeKit and Matter). Anything HomePad does not show offers "Open in Home App".
- **Home app:** laid out like HomeView's and as compact as Apple Home on iPad, so accessories start in the top half of the screen. Under the title one line holds the status chips, the room picker and a Scenes button (`HomeOverviewRow`). Where the picker would get less than about three rooms of width, as in portrait on an 11-inch iPad, the status chips take a line of their own. Then come the cameras, the favorite scenes if there are any, Favorites and each room. A room's title carries its sensor readings as chips ("72°", "41%", "Closed", "Motion"), and everything with a control gets a tile: seven columns across a 13-inch landscape screen and six on an 11-inch from arm's length, fewer and larger from across the room. Status chips, readings, favorite scenes and room chips share one 44 point glass chip (`homeChip`). Problems with a backend show as a notice above the content, and the demo notice sits at the end of the page. Tapping a tile or a reading opens full-screen controls sized by `DetailControlMetrics`. The close button or a swipe down closes them back to the Home app as it was, and a drag that starts on a level control only sets the level.
- **Controls at HomeView's scale:** a light, a fan or a blind is one big `LevelControl`, the full height of the screen and at least half its width. Its color rises from the bottom to the level, the symbol rides the fill line, and the level reads in numerals about a fifth of the screen tall, dark over the color and in the page's text color above it. Turn Off and the color temperature and color presets sit in a column beside it. A thermostat fills the whole screen with its mode's color (blue cooling, orange heating, teal auto, dim gray off) behind a setpoint about a fifth of the screen tall, with the Off, Heat, Cool and Auto chips under it. Its text and glass stay light on the color in Light too, as on HomeView. At night the fill stays dim so the red numerals stand out.
- **Scenes:** none on the page by default, as in Apple Home. The Scenes button lists every scene in a popover, where a row runs its scene and a star makes it a favorite. Favorite scenes show as chips over Favorites on the whole home's page, and a chip's menu removes one. The Scenes widget and Control Center tile show favorites first, then other scenes, so they work before anything is a favorite. The assistant runs any scene.
- **Cameras:** inside the Home app, as on HomeView. On All Rooms a compact strip of snapshot tiles (about 130 points tall from arm's length) opens a camera full screen, and its "Cameras" header opens a live grid of up to nine feeds. Each snapshot is labeled with its age in its top corner, "Now" for the first minute and then "2m ago", from the time HomeKit took it, or for Home Assistant the time it arrived (Home Assistant sends no time with it). A camera that stops answering keeps its last snapshot, so its age grows. A room's page puts its cameras at the start of its tiles, each as wide as a wide tile, so one camera never leaves a strip empty. A room with nothing but cameras shows them large, filling the row. Feeds play only where they can be seen: thumbnails show one still, a face frosted behind the Home Screen shows refreshing stills, a feed under a full-screen camera, an accessory's controls or the doorbell screen holds one still, and nothing streams or polls while the display sleeps or HomePad is in the background. There is no Cameras app: the `cameras` ID is an `AppRedirect` to the Home app's grid, so the camera widget, faces, the doorbell's grid button, Siri and `homepad://app/cameras` land there. The full-screen view has a LIVE badge, sound from the start with a speaker button once the feed has sound, talk (hold to talk for Home Assistant, a toggle for HomeKit cameras with a speaker) and an "Open in Home Assistant" link, and a swipe down closes it back to the Home app or the grid as they were. HomeKit streams are shared between views by `HomeKitStreamHub`.
- **Home Assistant live view:** WebRTC first, through Home Assistant's own signaling, which reaches go2rtc (built into Home Assistant since 2024.11) or an integration's own WebRTC (Nest, Ring and others). Each feed asks `camera/capabilities`, then `camera/webrtc/get_client_config` for the ICE servers, then subscribes to `camera/webrtc/offer`, which answers with the session, the answer and candidates. HomePad's candidates go back with `camera/webrtc/candidate`, and unsubscribing closes the session. The fallback order (`HACameraFeedPlan`):

  | View | Tried in order |
  |---|---|
  | Full screen and the doorbell screen | WebRTC with sound, HLS (`camera/stream`), MJPEG (`/api/camera_proxy_stream`, with a small multipart decoder), stills |
  | The camera grid and faces up close | WebRTC without sound, MJPEG, stills. HLS starts slowly and costs Home Assistant a stream worker per feed |
  | Thumbnails, faces from afar and at night, the doorbell screen while the display sleeps | Stills every 10 seconds |

  A camera Home Assistant does not offer WebRTC for starts at the next step, so the only wait is one spinner. A WebRTC feed that Home Assistant refuses, or that shows no frame within 10 seconds (`WebRTCLiveSession.startTimeout`), falls to the next step, and so does an HLS item or an MJPEG stream that fails before its first frame. A WebRTC feed that played and then drops (Wi-Fi changes, Home Assistant restarts) starts a new session, the last frame held under a spinner, after 1 second and then longer while it keeps failing. Each new WebSocket connection to Home Assistant starts every Home Assistant feed over from WebRTC, since Home Assistant closes its sessions with the socket. Peer connections close when their view leaves, the display sleeps, HomePad goes to the background or another screen covers the feed.
- **Camera sound:** faces and grids ask for video alone, so go2rtc never transcodes sound nobody hears. Full screen and the doorbell screen ask for sound and play it unmuted. WebRTC's sound goes through `WebRTCAudioDevice` instead of WebRTC's own voice processing unit, which would take the microphone from `MicrophoneHub` (wake word, sound alerts, intercom), duck music and set the audio session itself. Camera sound plays on an `AVAudioEngine` of its own under a `.playback` claim held only while some view is unmuted, mixed with music. HLS sound takes the same kind of claim.
- **Talk to a Home Assistant camera:** hold to talk appears when Home Assistant reports `two_way_audio` for the camera (2026.11, the "Two-way audio" preview feature in Settings > System > Labs, for Reolink and Matter cameras so far) and the camera's answer takes sound. The offer then has audio both ways, and HomePad sends nothing until the button is held. Holding it puts a talk track on the sender, and WebRTC then records through `MicrophoneHub` like every other listener, under a `.voice` claim like a spoken request, so it works over AirPlay music too. The camera's own sound pauses while talking, as there is no echo canceller on this path. If a camera refuses an offer with sound both ways, HomePad asks again without it. The Control Center microphone switch and the microphone permission apply, as for intercom.
- **Doorbell overlay:** on `.doorbellRang(cameraID:)` it wakes the display, plays the chime, and shows the front door with end, talk, sound, all cameras and "Unlock Front Door". The door is live whenever the screen shows, from across the room and at night too, since a ring is when someone wants to see who is there and talk. Only a sleeping display shows stills. Its sound starts on, or muted at night so a late ring does not fill a dark room. Every other camera feed holds a still while it shows. It closes itself after the configured time without interaction, and holding Talk counts as interaction.
- **Doorbell chime:** HomePad's own two-note chime (`DoorbellChimeSound`, drawn from sine waves, about 2.6 seconds), played once per ring through the iPad, or AirPods when they are connected, with a `.playback` claim on `services.audioSession` held only while it sounds. It stays silent while Quiet Hours is on in Control Center and, unless "Quiet in Night Mode" is off, in night mode, as intercom does. It waits a moment after the ring so a sleeping display has woken and says whether it is night. Each HomePad has its own Chime switch under Settings > Smart Home > Doorbell, next to Test Doorbell.
- **Security:** unlocking a lock, opening a garage door or gate, and disarming an alarm need a recognized member. On screen a guest can confirm instead. Commands from other modules and the assistant have no confirmation step, so guests are refused. Raw service calls that unlock or open follow the same rule.
- **What is on screen, for the assistant:** `HomeScreenContext` tells the assistant what the Home app shows full screen: an accessory's controls, a camera with the locks and garage doors in its room (and the doorbell's lock for a doorbell camera), or the camera grid. While the doorbell rings it speaks over every screen, with its lock. "Unlock this door" while a camera is up then finds the lock by the name `control_device` takes.
- **Device trackers for Find My:** GPS `device_tracker` entities (the iCloud integration, the Companion app, and others such as Life360) become `TrackedDevice`s on `services.smartHome.trackedDevices`, with location, accuracy, battery (the tracker's `battery` or `battery_level`, else a battery sensor on the same device), when Home Assistant last heard from it, and an owner hint from the `person` that lists it or iCloud's `owner_fullname`. Router and Bluetooth trackers have no coordinates and are left out. Zones become `HomeZone`s on `services.smartHome.zones`. They update live from the same `state_changed` subscription as everything else. Only Home Assistant provides trackers and zones. HomeKit and the demo backend have none. `playSound(onTrackedDevice:)` calls `icloud.play_sound` with the Apple Account (the iCloud config entry's title) and the device's Find My name (its device registry name, since the tracker's `device_name` attribute holds the model), or `notify.mobile_app_<device>` with a critical sound for Companion app devices. It needs a recognized member. The Personal module's Find My app decides who sees what.
- **Shared camera view:** Core's `SmartHomeCameraView(cameraID:mode:)` (in `HomePadCore/Extensions/SmartHome/`) renders through this module, so the Faces module's Home and Cameras faces can show live HomeKit or Home Assistant video without importing it.
- **Widgets and controls:** Home Favorites (`smarthome.favorites`, in every size up to tall, two cells wide and three tall, which shows half as many rows again as large), Scenes (`smarthome.scenes`) and Camera (`smarthome.camera`) widgets, and Scenes and Home tiles for Control Center (`smarthome.scenes`, `smarthome.accessories`).
- **Home Favorites' Edit Widget:** each Home Favorites widget shows the Home app's favorites until someone picks its own accessories (`FavoritesWidgetSettingsView`, the setting `accessories` in `FavoritesWidgetChoice`). The page lists what the widget shows, to drag into order or swipe off, then every accessory by room with a check, and a search field for a home with more than eight accessories that finds a name, a room or a kind ("locks"). The first change keeps the favorites it showed and changes only that one, taking off the last accessory follows the favorites again, and Show Home Favorites Instead goes back. An accessory removed from the home drops off the widget. The Home app's favorites never change here.
- **Dashboards app:** Home Assistant's own frontend in a `WKWebView`, signed in through Home Assistant's external auth bridge with the stored token, themed with injected CSS (HomePad's page color, 28 point corners, the system font and accent) and with Home Assistant's header and sidebar hidden. It is an advanced view next to the native Home app. A few curated web panels (Frigate, Grafana, any address) sit beside it, each with a name and an icon from a fixed set, and a `HeaderPicker` beside the title switches between them.

## The same accessory on every HomePad

Paired HomePads share the household's setup (see "The household's setup" in the Connect README), so a favorite, a Home Favorites widget's accessories or a face's camera picked on one HomePad is saved with that HomePad's ID. HomeKit gives the same accessory a different `uniqueIdentifier` on every iPad, since its identifiers are specific to the app and the device. So each HomePad turns the HomeKit IDs other HomePads saved into its own. Home Assistant and demo IDs need nothing.

**How.** Each HomePad shares a directory of its own HomeKit objects (`HomeKitDirectory`): for every service the Home app shows, group, camera and scene in every home, its `hk:` ID with the home, room, name and kind (the HomeKit service type, or group, camera or scene), and for services and cameras the accessory's name. It travels as that HomePad's own document, `smarthome.homeKitDirectory`, which only it writes, so two HomePads never overwrite each other's, and each HomePad keeps the latest one of every other (`smarthome.homeKit.otherHomePads`). `HomeKitIDTranslator` pairs every foreign ID with this HomePad's object of the same home, room, name and kind (`HomeKitIDMatcher`), and `localID(for:)` reads the pairs.

- **Names as people read them.** Home, room and name ignore case, accents, width and extra spaces.
- **Never the wrong one.** Where two objects share home, room, name and kind, the accessory's name decides. If that still leaves more than one, the ID pairs with nothing and the favorite or tile shows nothing. The rule runs both ways, so two of the other HomePad's objects never pair with one here.
- **Renames.** HomeKit carries a rename to every iPad, and both HomePads share their new directory, so pairs hold. Pairs once made are also remembered on this iPad (`smarthome.homeKit.translations`), since HomeKit's IDs never change, so a pair holds through a rename while the HomePad that saved the ID is off and its directory has the old name, and through a second accessory with the same name joining the room. A pair goes when its object leaves this HomePad's home.
- **Restarts.** A HomePad shares its directory only once Apple Home has loaded homes, so a restart never sends an empty one. Until then the copy shared before stays.

**Where saved IDs are read.** Every lookup goes through the service: `accessory(_:)`, `camera(_:)`, `perform`, `activateScene`, the favorites and favorite scenes (`favoriteAccessoryIDs`, `favoriteSceneIDs`, `favorites`), the layout's hidden, pinned and tile sizes (`layout`), the doorbell's trigger, camera and lock (`doorbell`), a Home Favorites widget's accessories, and outside this module the Home face's tiles and camera, the Cameras face's cameras and the face editor's slots (Faces), and Siri's accessory and scene entities (Connect). Lists read through `localIDs(for:)`, which also drops one object saved under two HomePads' IDs. Rooms are saved by name, the same on every iPad.

**Changes.** A change made here saves this HomePad's IDs for everything it can name and keeps what it cannot as it was saved, so nothing another HomePad picked is lost. Unstarring a favorite takes it off under either HomePad's ID. Nothing saved before needs moving: a reference made on the 11-inch reads on another iPad as soon as the 11-inch shares its directory.

**Why not a portable ID.** HomeKit has no identifier that is the same on every iPad. One made from home, room and name would change with every rename, and the Accessory Information serial number is missing or the same for many bridged accessories and does not exist for scenes, groups or the separate services of one accessory. Every saved reference (favorites, the layout, widget settings inside the Home Screens and faces) would also need rewriting on the iPad that made it. The directory needs no change to what is saved, and the pairs it makes survive renames.

**Favorites** are the household's, shared with the setup (`smarthome.favorites`), not iCloud key-value storage, which reaches only iPads on one Apple Account. The layout, the doorbell and Dashboards still sync through iCloud.

## This HomePad in Home Assistant

Each HomePad can also be a device in Home Assistant, the way the Home Assistant app and Kiosk Satellite are: Home Assistant sees its sensors, and automations send it commands with `notify.mobile_app_<device>`. It is off until someone turns it on under Settings > Smart Home > This HomePad in Home Assistant (`HomeAssistantDevice`, in `Backends/HomeAssistant/MobileApp/`).

- **One device per iPad.** It registers with Home Assistant's `mobile_app` integration (`POST /api/mobile_app/registrations` with the long-lived token), with a device ID made once and kept on this iPad (`smarthome.homeAssistant.device.id`, not synced). Home Assistant tells registrations apart by app ID and device ID together and replaces a registration when the same pair registers again, so registering again never makes a second device. The answer's webhook ID is a credential: it stays in a keychain item on this iPad only (not iCloud Keychain) and is never logged.
- **Named after the room.** The device is "Kitchen HomePad" after the room picked in Settings > Devices & Sharing (`CoreSettings.roomName`), or "HomePad" before one is picked. Pick a room on every HomePad, since two named "HomePad" would share one notify action. A new room renames the device with `update_registration`, and Home Assistant renames the notify action with it. Entity IDs keep the name they were made with.
- **Sensors** go through the webhook: `register_sensor` for each one when reporting starts, then `update_sensor_states` with only what changed.
- **Commands** arrive over Home Assistant's local push, `mobile_app/push_notification_channel` on the WebSocket the backend already has (`HomeAssistantBackend+PushChannel`), so no push service is involved. HAKit opens the channel again after every reconnect. Confirmations are off: with them, Home Assistant closes the channel when an answer is late, for example while the app is suspended, and the connection would never know.
- **When Home Assistant forgets the device** (410 from the webhook, an empty answer, or "Webhook ID not found" on the channel), it registers again with the same device ID. Failures wait 30 seconds and then twice as long each time, up to 10 minutes.
- **Turning it off** marks every sensor unavailable and closes the channel, and keeps the registration. **Remove from Home Assistant** finds the device's config entry in the device registry by its device ID and deletes it (`DELETE /api/config/config_entries/entry/<id>`, which needs an administrator's token), then forgets the registration. Without an administrator's token, Settings says to delete the device under Settings > Devices & services > Mobile App.

### Sensors

Only what HomePad already knows and shows. `<device>` is the device name in Home Assistant's form, for example `kitchen_homepad`.

| Entity | Kind | State | Attributes | From |
|---|---|---|---|---|
| `binary_sensor.<device>_someone_present` | occupancy | on, off | | `services.presence.snapshot` |
| `sensor.<device>_proximity` | | nobody, far, mid, near | | the snapshot's proximity level |
| `sensor.<device>_recognized` | | the member's name, or Guest | | `household.unlockedMember`: recognized or verified, not a member only picked by hand |
| `sensor.<device>_room_light` | illuminance, lx | lux, unavailable while no camera measures it | `level`: dark, dim, normal, bright | the snapshot's light |
| `sensor.<device>_screen` | | face, home_screen, app, asleep, night | `display`: active, ambient, dimmed, night, sleeping | `services.displayCondition` and `services.kioskStatus` |
| `sensor.<device>_face` | | the face's name, such as Modular | `id`, such as faces.modular | `services.kioskStatus.faceID` |
| `sensor.<device>_app` | | the app's name, or None | `id` | `services.visibleAppID` |
| `sensor.<device>_brightness` | % | 0 to 100 | | `services.kioskStatus.brightness` |
| `sensor.<device>_battery` | battery, %, diagnostic | 0 to 100 | | `services.kioskStatus` |
| `binary_sensor.<device>_charging` | battery charging, diagnostic | on while the iPad is on power | `battery_state`: charging, full, unplugged | `services.kioskStatus` |

Asleep and night win over what is on screen. Unknown values are `unavailable`, as in the simulator's battery. The section lists every sensor with its value right now and the entity ID it gets.

**Rate limit** (`MobileAppReportThrottle`): only values Home Assistant has not heard go out, and room light only when it moves into another level or by a fifth. The first change after a quiet spell goes at once, so an automation waiting for someone to walk up runs right away. After that, at most one update every 5 seconds, carrying the values as they are by then, so someone stepping in and out of view in between sends nothing and a burst of changes is one request. A person at the edge of a proximity level costs at most twelve updates a minute.

### Commands

The notification's `message` names the command, and its `data` holds the options. The Home Assistant app's kiosk commands work where HomePad has the same thing, and HomePad adds its own (`MobileAppCommand`). Screens open through the shell's own events, so a personal app still waits behind the recognition gate.

| `message` | `data` | What HomePad does |
|---|---|---|
| `kiosk_show_screensaver` | | Sleeps now, its dim drifting clock. Someone already in front of it does not keep it awake. Someone arriving, a touch or a wake event wakes it. |
| `kiosk_hide_screensaver` | | Wakes the screen. |
| `kiosk_show_camera` | `entity_id`: a camera | Opens the Home app with that camera full screen. |
| `kiosk_hide_camera` | | Closes the full-screen camera. |
| `kiosk_set_brightness` | `level`: 0 to 100 | Sets the brightness as Control Center does. It holds until the display condition changes. |
| `kiosk_set_volume` | `volume`: 0 to 100 | Sets the volume (`services.media.setVolume`). |
| `kiosk_reload` | | Loads Home Assistant's states and registries again. |
| `kiosk_default` | | Shows the usual face, the person's own or the household's. |
| `homepad_show_face` | `face`: an ID or a name, optional | Shows that face, or the usual face. |
| `homepad_go_home` | | Shows the Home Screen. |
| `homepad_open_app` | `app`: an ID or a name | Opens the app. |
| `homepad_speak` | `text`, and `title` beside `message` | Says the text in the assistant's voice and shows it as a banner. During Quiet Hours, or while someone is talking to the assistant, only the banner shows. |
| anything else | `title` beside `message` | A banner at the top of every screen for 10 seconds, which wakes the screen. A tap closes it. |

`kiosk_set_screensaver_mode` and `kiosk_set_screensaver_brightness` are ignored, since HomePad's sleeping screen is always the dim clock. So are the messages Home Assistant sends every phone app, such as `request_location_update` and `clear_notification`. Commands arrive only while HomePad is open and connected. With no push service, Home Assistant reports a notification sent meanwhile as failed.

```yaml
automation:
  - alias: Driveway on the kitchen HomePad when a car arrives
    triggers:
      - trigger: state
        entity_id: binary_sensor.driveway_vehicle
        to: "on"
    actions:
      - action: notify.mobile_app_kitchen_homepad
        data:
          message: kiosk_show_camera
          data:
            entity_id: camera.driveway
      - delay: "00:01:00"
      - action: notify.mobile_app_kitchen_homepad
        data:
          message: kiosk_hide_camera

  - alias: Kitchen lights when someone walks up in the dark
    triggers:
      - trigger: state
        entity_id: binary_sensor.kitchen_homepad_someone_present
        to: "on"
    conditions:
      - condition: numeric_state
        entity_id: sensor.kitchen_homepad_room_light
        below: 20
    actions:
      - action: light.turn_on
        target:
          entity_id: light.kitchen

  - alias: Bedtime
    triggers:
      - trigger: time
        at: "23:00:00"
    actions:
      - action: notify.mobile_app_kitchen_homepad
        data:
          message: kiosk_show_screensaver

  - alias: Laundry done
    triggers:
      - trigger: state
        entity_id: sensor.washer_status
        to: "finished"
    actions:
      - action: notify.mobile_app_kitchen_homepad
        data:
          title: Laundry
          message: homepad_speak
          data:
            text: The washer is done.
```

### What goes to Home Assistant

- Registering: the app's ID, name and version, the device ID (random, made on this iPad), the device name, "Apple", the model identifier (such as iPad16,3), and the system name and version.
- The ten sensors above, and nothing else. Who is recognized is a name or Guest, a fact HomePad already shows on screen.
- Never: faces, face templates and embeddings, photos, camera frames, the microphone or any audio, assistant conversations, messages, calendars or locations. HomePad sends no location, so the device tracker Home Assistant makes for every phone app stays unknown.

### In Home Assistant

Nothing to set up there: `mobile_app` comes with `default_config`. The notify action and the entities appear once the switch is on. Home Assistant adds the new device's tracker to the person whose token HomePad uses. It never has a location, so it does not move that person, and it can be taken off them under Settings > People. Remove from Home Assistant needs that person to be an administrator.

## Light and Dark

Every screen follows Settings > Kiosk & Display > Appearance, and night is always dark. Pages, tiles, chips and controls use HomePadUI's adaptive colors. These stay dark in every appearance, because their color belongs to what they show:

- Camera views: the full screen, the tiles and the Camera widget show video on black, with light text and dark glass over it. The doorbell screen too.
- A thermostat filled with its mode's color keeps light text and glass on it. Off, it is the page's own color.
- Lit tiles keep the accessory's color, with a near black circle under the symbol.

Dashboards' injected theme has a dark and a light block picked by `prefers-color-scheme`, which the web view takes from the appearance, and it leaves Home Assistant's own theme on automatic so the frontend follows the same switch. Web panels get only the page color.

## Structure

```
Sources/HomePadSmartHome/
  SmartHomeModule.swift        registration of every surface
  Services/                    UnifiedSmartHomeService (+Commands, +Saved), backend driver protocol, what the module
                               shares (SmartHomeSharing)
    HomeKitIDs/                each HomePad's HomeKit directory, the matcher and the translator
  Backends/Demo/               demo backend on top of Core's DemoSmartHomeService
  Backends/HomeAssistant/      HAKit backend, state and command mapping, registries, doorbell detection,
                               camera feed plan and WebRTC signaling,
                               device trackers and Play Sound, requests and responses, discovery,
                               connection test, configuration, the push channel
    MobileApp/                 this HomePad as a device: registration, sensors, rate limit, commands,
                               transport, the stored registration
  Backends/HomeKit/            HomeKit backend, service and command mapping, delegate proxy, stream hub, directory builder
  Cameras/                     MJPEG parser and stream, HLS and HMCameraView views, CameraFeedView, the sound
                               control shared with camera screens, demo feed
  Cameras/WebRTC/              live session, peer connection, audio device, engine, SDP directions
  Dashboards/                  Dashboards app, themed web view with external auth, catalog, navigator
  Models/                      layout, doorbell and dashboard settings, backend status, camera feeds
  Support/                     IDs, settings keys, security policy, scene symbols, launch options
  Views/Home, Detail, Cameras, Doorbell, Surfaces, Components, HomeAssistant (the notification banner)
  Settings/                    the "Smart Home" pane and its sections and editors
  Tools/                       home_assistant_service
  Resources/DashboardFixture.html   local stand-in for Home Assistant's frontend (debug only)
Tests/HomePadSmartHomeTests/   Swift Testing suites and Fixtures/ (Home Assistant JSON)
```

Shared UI comes from HomePadUI: `GlassIconButton`, `StatusBadge.live`, `TileGridLayout` and `DetailHeader` for accessory and camera screens. `LevelControl` in `Views/Components` draws the full-height level of lights, fans and blinds, and is a candidate for HomePadUI in place of `BigSlider`'s `showsValue`.

## Settings

Pane id `smarthome` (admins only). Keys:

| Key | What |
| --- | --- |
| `smarthome.homeAssistant.url` | Home Assistant base URL. The token is in the keychain under `smarthome.homeAssistant.token`. |
| `smarthome.homeKit.enabled`, `smarthome.homeKit.homeID` | Whether Apple Home is connected, and which home. |
| `smarthome.favorites.accessories` | Favorite accessories in order. Unset means automatic (climate, locks, lights). Shared by the household's HomePads, not iCloud. |
| `smarthome.favorites.scenes` | Favorite scenes in order, shown in the Home app. Unset means none. Shared by the household's HomePads, not iCloud. |
| `smarthome.layout` | Room order, hidden rooms and accessories, pinned accessories, tile sizes (small or wide). Synced through iCloud. |
| `smarthome.doorbell` | Extra doorbell trigger, camera, lock to unlock, auto-dismiss time. Synced through iCloud. |
| `smarthome.homeKit.otherHomePads` | Every other HomePad's HomeKit directory, by its device ID, as it arrived. Not synced. |
| `smarthome.homeKit.translations` | Pairs of another HomePad's HomeKit ID and this HomePad's that were found once. Not synced. |
| `smarthome.doorbell.chime`, `smarthome.doorbell.chimeQuietAtNight` | Whether this HomePad chimes when the doorbell rings, and whether it stays silent in night mode. Not synced, so each HomePad keeps its own. |
| `smarthome.dashboards` | Home Assistant dashboard path (picked from a list of dashboards and views) and web panels. |
| `smarthome.homeAssistant.device.enabled` | Whether this HomePad is a device in Home Assistant. Off by default. Not synced. |
| `smarthome.homeAssistant.device.id` | The device ID it registers with, made once. Not synced, and kept after Remove. The registration and its webhook ID are in a keychain item on this iPad only (`smarthome.homeAssistant.device.registration`). |

Customization is curated: favorites, two tile sizes, room order and visibility, the doorbell entities, and web panel icons from a fixed set. Long press a tile for the same choices in place.

### Reopening where you left off

Both apps reopen as they were left (`@AppState`, keys in `SmartHomeAppState`, shared by the household like the home):

| App | Reopens on | Not restored |
|---|---|---|
| Home | The room picked, and the accessory's controls, the camera grid or the camera full screen that was open. A room no longer in the home shows All Rooms, and an accessory or camera no longer in it closes quietly | Scroll position, the Scenes popover |
| Dashboards | The page picked: Home Assistant or a web panel. A deleted panel shows the first page | A Home Assistant page another screen asked for, and the place inside the web page |

A widget or Control Center opening an accessory, the `cameras` link (the camera widget, faces, the doorbell, Siri) and the launch arguments below win over what was restored.

## Debug launch arguments

| Argument | Effect |
| --- | --- |
| `-HomePadOpenApp home` / `cameras` / `dashboards` | Opens an app (shell). `cameras` opens the Home app's camera grid. |
| `-HomePadSmartHomeAccessory demo:light.kitchen` | Opens the Home app on that accessory's controls. |
| `-HomePadSmartHomeRoom "Living Room"` | Opens the Home app on that room. |
| `-HomePadSmartHomeCamera demo:camera.yard` | Opens the Home app on that camera, full screen. |
| `-HomePadRingDoorbell demo:camera.front` | Rings the doorbell two seconds after launch. |
| `-HomePadDashboardFixture YES` | Shows the local stand-in page in Dashboards with the full theme. |
| `-HomePadSmartHomeSettings YES` | Shows the Smart Home settings pane on top. |
| `-HomePadSmartHomeSettingsSection device` | With it, scrolls to This HomePad in Home Assistant. |
| `-HomePadSmartHomeDevicePreview YES` | Draws that section as registered, without contacting anything. |
| `-HomePadSmartHomeFavorites "demo:lock.ultra,demo:light.desk"` | Uses these favorite accessories. |
| `-HomePadSmartHomeAdjusting demo:light.desk=45` | Draws that accessory's tiles mid-drag at 45 percent. |

## Dependencies

| Package | Version | License | Why |
| --- | --- | --- | --- |
| [HAKit](https://github.com/home-assistant/HAKit) | 0.4.19 (exact) | Apache 2.0 | Home Assistant's own client: WebSocket auth, subscriptions, REST, reconnects. |
| [Starscream](https://github.com/bgoncal/Starscream) (via HAKit) | 4.0.10 | Apache 2.0 | HAKit's WebSocket transport. |
| [PromiseKit](https://github.com/mxcl/PromiseKit) (resolved by HAKit, not linked) | 8.2.0 | MIT | Only used by HAKit's optional PromiseKit product. |
| [WebRTC](https://github.com/stasel/WebRTC) | 155.0.0 (exact) | BSD 3-Clause, with Google's patent grant ([webrtc.org/support/license](https://webrtc.org/support/license)). The build scripts are BSD 3-Clause too | Google's WebRTC M155, built unmodified from webrtc.googlesource.com and shipped as a binary xcframework (no vendored source). Home Assistant camera live view. It adds about 12 MB to the app (the signed arm64 framework), and the package download is 45 MB. |

The tests also use HAKit's `HAKit+Mocks` product.

## Tests

`scripts/build-package.sh HomePadSmartHome test` runs Swift Testing suites against fixtures in `Tests/HomePadSmartHomeTests/Fixtures/` (REST states, registry results, WebSocket event and result messages, config and history). Nothing connects to a real Home Assistant.

- `HAStateMapperTests`: every domain, rooms from entity and device areas, hidden and diagnostic entities, camera URLs, doorbell cameras.
- `HACommandMapperTests`: every command to its service call, including thermostat ranges and the `call_service` payload.
- `HAWebSocketDecodingTests`: state_changed events through HAKit, doorbell rings and restores, registries, camera stream, errors, config, history, dashboards.
- `HomeAssistantBackendTests`: the backend on HAKit's mock connection, from connect to commands.
- `HATrackerMapperTests`, `HAPlaySoundCallTests`, `HomeAssistantFindMyTests`: GPS trackers, zones, owners and batteries, the Play Sound action for iCloud and the Companion app, trackers moving with `state_changed`, and the recognition rule.
- `HAWebRTCSignalingTests`: camera capabilities with and without `two_way_audio`, ICE servers in every shape, the offer's events, go2rtc candidates without a line, and the negotiation through a fake transport and a fake peer: candidates held until the session and the answer, refusals, provider errors before and after the answer, and stopping. Session descriptions: which way sound and video flow, refused lines.
- `CameraFeedPlanTests` and `HomeAssistantBackendTests.cameraFeedsFallBackInOrder`: the fallback order for each view, cameras with native WebRTC and servers before 2024.11, and the backend asking for HLS only once it is next.
- `MobileAppSensorTests`, `MobileAppReportThrottleTests`, `MobileAppCommandTests`: every sensor's value and payload, the rate limit with explicit times, and every command, plain messages and what is ignored.
- `HomeAssistantDeviceTests`: the device on HAKit's mock connection and a fake `mobile_app` transport (`FakeMobileAppTransport`): registering once, a new room renaming it, a deleted registration registering the same device again, throttled updates, commands over the push channel, turning off and Remove.
- `MJPEGParserTests`: Content-Length and boundary-only parts, odd boundaries, chunking down to one byte, JPEG marker fallback, runaway buffers.
- `DoorbellChimeTests`: the chime's WAV data, its loudness and silent ends, and when Quiet Hours, night mode and the Chime switch keep it silent.
- `HomeKitIDMatcherTests`, `HomeKitIDTranslatorTests`: two HomePads in memory that see one home under different HomeKit IDs, trading directories. Pairs both ways, names ignoring case, accents and spaces, a different kind, room or home, duplicates pairing with nothing, the accessory's name telling two services apart, two of theirs never pairing with one of ours, renames with both on and with one off (and after a restart), a second accessory with the same name, a removed accessory and a third HomePad.
- `SavedIDTranslationTests`: the service with favorites, favorite scenes, the layout, the doorbell, a widget's accessories, commands and scenes saved under another HomePad's IDs, changes here keeping what this HomePad cannot show, and the favorites document read and applied on another HomePad.
- `HomeKitMappingTests`, `UnifiedSmartHomeServiceTests`, `SupportTests`, and the view math in `AccessoryGroupsTests`, `AccessoryLevelTests`, `CameraGridLayoutTests`, `HomeSummaryChipsTests`, `LevelControlLayoutTests`, `SensorReadingTests` and `SnapshotAgeTests`.

## Needs testing on a real iPad

- HomeKit end to end: permission prompt, homes, characteristic notifications, writes, scenes, `HMAccessorySetupManager`.
- HomeKit cameras: live video in `HMCameraView`, two-way talk, and JPEG snapshots drawn from an offscreen `HMCameraView` (other modules use these through `snapshot(cameraID:)`).
- HomeKit doorbell button events posting `.doorbellRang`.
- The doorbell chime through the iPad's speakers and AirPods, its loudness next to music, and staying silent with Quiet Hours on and in night mode.
- Dragging the full-height light, fan and blind controls, and how far a drag moves the level.
- Home Assistant against a real instance: auth, reconnects after Wi-Fi drops, registries, HLS playback, MJPEG performance with nine feeds.
- WebRTC live view with real cameras: time to the first frame (go2rtc and a cloud camera such as Ring or Nest), nine WebRTC feeds on a face or the grid (heat, battery, decoder limits), reconnecting after Wi-Fi changes and a Home Assistant restart, falling back when WebRTC cannot connect (remote access without a TURN server).
- Camera sound through `WebRTCAudioDevice`: loudness, staying in step with the picture, AirPods, music playing at the same time, and the wake word still hearing while a camera plays.
- Hold to talk on a Reolink or Matter camera with the Labs feature on: the door hearing HomePad, nothing heard back while holding, and the assistant and intercom still working after.
- The Dashboards app against a real frontend: external auth, and whether the kiosk script still finds `hui-root` in the current frontend version.
- Bonjour discovery and the local network permission prompt.
- The same accessory on two HomePads with Apple Home (the identifiers really differ only between real iPads):
  1. Install the build on both HomePads, open HomePad on both and wait until the Home app shows Apple Home's accessories on each. A HomePad shares its directory a moment after Apple Home loads.
  2. On the HomePad where the favorites and the Home Favorites widget were picked, nothing changes.
  3. On the other HomePad, the Home app's Favorites show the same accessories in the same order, the favorite scenes the same chips, the Home Favorites widget the same accessories, and its Edit Widget lists them under In This Widget. A Home face with picked tiles, a Cameras face with picked cameras and the doorbell's camera and lock in Settings show the same too.
  4. Star an accessory on the second HomePad and unstar one picked on the first. Both show the change on the other within a few seconds.
  5. Rename a favorite accessory in Apple's Home app. Both HomePads keep it, under the new name.
  6. Close HomePad on the first HomePad (or turn it off), rename another favorite in Apple's Home app, and restart HomePad on the second. It keeps showing that favorite.
- This HomePad in Home Assistant against a real instance: the registration, the sensors and their entity IDs, the push channel staying open across Wi-Fi drops and Home Assistant restarts, each command, the banner, the spoken message, Remove with an administrator's token and without one, and how often presence updates arrive while people move around.

## Known gaps

- Fan speed uses `AccessoryState.brightness` as a generic 0 to 1 level, and media playback state uses `isActive`, because Core has no dedicated fields.
- Text sensors (non-numeric states) are not shown as tiles.
- Talk with Home Assistant needs 2026.11, its two-way audio preview feature and an integration that declares it (Reolink, Matter). Other cameras have no talk.
- Talk is half duplex: the camera's sound pauses while HomePad sends, as nothing cancels the echo.
- The full-screen LIVE badge shows over every feed, stills included.
- Night mode tinting does not reach inside the Dashboards web view.
- The doorbell trigger choice takes effect for Home Assistant mapping at the next state change.
- A HomeKit ID saved on another HomePad shows nothing here until that HomePad has shared its directory once, and nothing while two objects here match it equally (the same kind, home, room, name and accessory name).
- A rename made before the two HomePads first paired an object, while the HomePad that saved it is off, waits for that HomePad to come back.
- Editing a Home Favorites widget saves what it shows, so a pick this HomePad cannot read yet (its HomePad never shared a directory) is dropped by an edit here.
- The layout, the doorbell and Dashboards still sync through iCloud, so only HomePads on one Apple Account share them. They read HomeKit IDs from any HomePad.
- HomeKit IDs saved on an iPhone or Mac companion, such as a shortcut made there, are not translated: companions share no directory. The Camera Lab floor plan stays on its iPad with that iPad's IDs.
- Companions take no part in the shared setup, so they no longer receive the favorites. Siri's accessory suggestions there list every accessory.
