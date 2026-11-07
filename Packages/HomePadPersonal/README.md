# HomePadPersonal

Calendar, reminders, weather, world clock, photos and Find My for HomePad. The module installs `services.calendar` and `services.weather`, and registers six apps, six widgets, the Personal Info settings pane, six assistant tools and three background tasks.

No third-party dependencies. Everything uses Apple frameworks (EventKit, EventKitUI, WeatherKit, Core Location, MapKit, PhotoKit, PhotosUI) and plain `URLSession` for Open-Meteo. Find My reads Home Assistant through `services.smartHome`, the Smart Home module's one connection.

## Features

| Area | What it does |
| --- | --- |
| Calendar service | EventKit calendars and reminders, filtered per household member. Shared calendars always show. Personal ones show only while their owner is recognized. The recognized person's own iPhone calendars and lists join them (see [Calendars and reminders from each person's iPhone](#calendars-and-reminders-from-each-persons-iphone)). |
| Weather service | WeatherKit first, Open-Meteo automatically when WeatherKit fails. Current, 48 hours and 10 days. Disk cache, refresh cadence, unit choices. |
| Calendar app | Day, week and month views. A Calendars button lists the calendars the viewer may see, grouped by account, to show or hide each one. Adding and editing use Apple's event editor (`EKEventEditViewController`) for the iPad's calendars, and HomePad's own (`PhoneEventEditorSheet`) for the recognized person's phone calendars. |
| Reminders app | Smart tiles (Today, Scheduled, All, the default list), every visible list, big check circles, quick add, Add List. It reopens on the list each person chose last. With nothing chosen, or a list that is gone or not theirs to see, it opens on Today when something is due or overdue, else on All, and keeps that view for the visit, so checking off the last thing due does not switch away. |
| Weather app | Animated sky. From across the room it shows city, temperature and conditions in huge type. Up close it adds the hourly Conditions panel, the 10-day forecast and detail tiles (`ProximityAdaptive`). The 10-day panel never gets narrower than its rows, so it fits the 11-inch iPad, and in portrait the detail tiles go below it in a row of three where two columns do not fit. Clouds are one layer at no more than 60 percent over the sky, and the header has a light shade, so white text reads over them. |
| World Clock app | Cities as analog, minimal or digital clocks, light by day and dark by night. Add cities by search, long-press a city to remove it. Times use proportional digits, like the faces, so 11:07 does not spread apart, and they roll when they change. |
| Photos app | What it shows follows [who sees which photos](#who-sees-which-photos): everything for the library's owner, shared albums for other members, and the recognition gate for guests. The photo library first, then favorites, shared albums and albums, a photo grid, and picking photos with the system photo picker. With limited access it offers "Allow More Photos". Albums list videos too, badged with their length, and count them apart ("6 photos, 1 video"). A photo or video opens full screen over the grid (`PhotoViewer`), growing out of its thumbnail. Swipe anywhere on the screen for the next or previous one in grid order, with the ones beside it loaded ahead. Pulled down it follows the finger, and let go (or on Close) it lands on its thumbnail in one spring from where it was, carrying the finger's speed, with the grid scrolled to it (`PhotoViewerGeometry`). A video plays with the system controls at its own size, only while it is the one on screen, and its sound mixes with music while the microphone keeps listening (`PhotoVideoPlayer`). Play Slideshow uses the same viewer, with crossfades and a slow zoom, each photo whole over a soft copy of itself, and waits for each video to end. The slideshow from Settings' sources, the Photo widget and the faces show photos only. While a member is recognized and their own iPhone shares its photos, "From Kyle's iPhone" comes first (see [Photos from each person's iPhone](#photos-from-each-persons-iphone)). |
| Find My app | A live map of the household's phones, iPads and watches from Home Assistant, a list like Apple's Devices tab, a card with the address and Play Sound, and an Open Find My link for AirTags and AirPods. See [Find My](#find-my). |

## The one-account reality of an iPad

An iPad is signed in to one Apple Account. EventKit only sees the calendars and reminders lists of that account, plus anything shared with it, plus other accounts added in the Settings app. It cannot read each family member's iCloud directly. HomePad works with that in two ways. The simplest is each person's own iPhone: they check in HomePad on their iPhone which of their calendars and lists the HomePad may show, and nothing is shared between Apple Accounts (see [Calendars and reminders from each person's iPhone](#calendars-and-reminders-from-each-persons-iphone)). The other is sharing with the iPad's account:

1. Sign the HomePad iPad in to one Apple Account. A dedicated household account works best, or the account of whoever set it up.
2. Each family member shares the calendars they want on the HomePad with that account from their own iPhone:
   - Calendar app, Calendars, tap the info button next to a calendar, Add Person, enter the HomePad's Apple Account email. Accept the invitation on the iPad (it arrives in the Calendar app's inbox and by email).
   - Reminders app, long-press a list, Share List, invite the same account.
   - With Family Sharing, the automatic Family calendar and any shared family lists already appear.
3. Other services work too. Add a Google, Outlook or Exchange account in iPad Settings, under Calendar, Calendar Accounts. Subscribed calendars (school, sports, holidays) also appear.
4. In HomePad Settings, Personal Info, choose who each calendar and list belongs to with Apple's calendar chooser: one row for Shared with Everyone and one row per member.

Read-only sharing is enough to show a calendar. Adding events from HomePad needs "View & Edit" permission.

All Calendars on This iPad, under the rows in Personal Info, lists every calendar EventKit gives HomePad with its account (iCloud, Subscribed Calendars, Other and so on), who it belongs to, whether it shows right now and why, and a menu to change it. A calendar missing from that list is not on the iPad at all, so the fix is in the iPad's Settings app, not in HomePad. The Calendar app says how many calendars it leaves out and why, and the Calendar and Modular faces say when personal events are waiting for their owner.

## Privacy model

Every read and write goes through `CalendarVisibilityPolicy`. A calendar's audience resolves in this order:

1. The assignment chosen in Settings (`everyone`, `members([ids])` or `hidden`).
2. A suggestion from well-known names: holiday calendars, the Family calendar and Groceries are shared.
3. The policy for calendars nobody chose. The default treats them as personal to the household's admins, because the iPad's account usually belongs to whoever set it up. With nobody added in People there is no admin who could ever be recognized, so they show for everyone instead of never showing.

Nothing is saved for a calendar until someone chooses, so a calendar added to the iPad later (a new subscription, say) follows these same rules and shows up without any setup.

A calendar personal to a member shows only while `household.isPersonalContentUnlocked` is true for that member. Picking a name in the People switcher is not enough. Unlocking lasts while the person is detected and ends the Switch to Guest After time later (30 s by default, see "Who is signed in" in the Presence README). A touch counts while the camera sees no face, so a person verified with Face ID keeps Up Next while they use the screen. Guests see shared calendars only. Writes follow the same rule: a guest can add "milk" to Groceries but cannot add to, or check off, anything in a personal list.

The recognized member's own iPhone calendars and lists follow a stricter rule: they show only while the member they belong to is the one recognized here, never for an admin, and never in Settings.

Up Next and Reminders widgets set `isPersonal: true`, and their content is filtered as well. Find My sets `requiresRecognizedMember: true` and has its own rules for whose devices each person sees (see [Find My](#find-my)).

Calendar and Photos tell the assistant what they show (`PersonalScreenContext`): the view and day in Calendar ("the Day view of Thursday, October 22") and the open album in Photos. Both are marked personal, so the assistant hears them only while someone is recognized, and the album is named only when the person asking may see it (`PhotoAccessPolicy`).

## Who sees which photos

The iPad's photo library belongs to one Apple Account, so it is one person's. `PhotoAccessPolicy` in HomePadCore decides, for this module and every other one:

- **The library owner**, while recognized, sees everything from the library: the whole library, Favorites, their own albums, videos, the photos picked by hand, Choose Photos (the system photo picker) and Allow More Photos. And the shared albums.
- **Another recognized member** sees iCloud Shared Albums only. Photos says so when there are none ("No Shared Albums Yet"), and Play plays the shared albums among the slideshow's sources, or every shared album.
- **A guest**, or a member only picked in the People menu, sees nothing. Photos sets `requiresRecognizedMember: true`, so it is hidden for guests and opens behind the recognition gate, like Find My.
- **Photos faces and the Photo widget** are picture frames. They show the sources picked for them to whoever is in the room, unchanged.

The owner is picked in Settings, Personal Info, Photos (Photo Library Owner), and is the first admin until someone picks. The same section offers the library's own albums, Selected Photos and Allow More Photos only while the owner is recognized, so another admin never browses the owner's library from Settings.

`PhotoLibraryService.albums` keeps every album for the frames, and the app shows `albums(for:)`, the ones the person at the screen may see. When someone else takes over the screen, a photo open full screen closes. The other places that read the library follow the same rule: the system photo picker in the Home Screen's wallpaper, a recipe card's photo, Messages' composer, the assistant's Attach Photo, Camera Lab's Choose Photo and the Photos face editor shows only while the owner is recognized, and the face editor offers other members the shared albums only. `PhotoAccessRulesTests` cover the app's rules.

One caveat: Apple's event editor lists every writable calendar on the account in its calendar picker, so a person adding an event can see other calendars' names (not their events). HomePad preselects the right calendar (the recognized member's own, else the default or a shared one).

## Photos from each person's iPhone

The iPad's library belongs to one Apple Account. A second source is each person's own iPhone: while a member is recognized at the HomePad and their iPhone, linked to them and with Show My Photos on, has answered, the Photos app shows their phone's library above the iPad's albums. The Connect module reads it on the phone and brings it over the peer link (`services.phonePhotos`, see "Each person's photos from their own iPhone" in the Connect README for the Bluetooth wake, the protocol and the limits).

- **What shows.** "From Kyle's iPhone" with Recents and Favorites on wide covers, then "Albums on Kyle's iPhone" with the person's own albums on square covers. Empty albums are left out. An album opens on the same grid and the same viewer as the iPad's own albums, growing out of its thumbnail, with Play Slideshow (`PhoneAlbumScreen`). Grids show thumbnails, and the viewer shows the thumbnail at once, then the full image when the phone has sent it (`PhotoView`, `PhotoRef.phone`). Photos only, no videos.
- **Who sees it.** Only the member recognized here, and only their own phone (`PhoneLibraryVisibility`). Someone picked in People, a guest or another member sees nothing of it. It shows once the phone has answered during the visit, and is gone the moment the person stops being recognized, with an open phone album and its viewer closing with it. When this iPad shows no photos of its own, or has no photo access, the phone's section still shows for its owner.
- **The access rule.** `PhoneLibraryAccess` asks one question: may this viewer see this owner's phone library. `OwnPhoneOnly`, the owner alone, is in force. The Photos access rule being added on another branch (the iPad's library for its owner, shared albums for every recognized member, nothing for guests) connects here: make that policy type conform to `PhoneLibraryAccess`, or assign it to `PhoneLibraryVisibility.access`.
- **Never elsewhere.** The phone's photos never feed the slideshow sources in Settings, the Photo widget or the faces, which anyone in the room sees.
- **Nothing to set up on the iPad.** Each person turns on Show My Photos in the HomePad's remote on their iPhone.

## Calendars and reminders from each person's iPhone

A person's own calendars and reminders lists live on their own iPhone, under their own Apple Account. While a member is recognized at the HomePad and their iPhone, linked to them, shares calendars or lists with it, those show beside the iPad's own. The Connect module reads them on the phone and brings them over the peer link in the same visit as their photos (`services.phoneCalendars`, see "Each person's data from their own iPhone" in the Connect README for the wake, the protocol and the limits). `HouseholdCalendarService+Phone` merges them.

- **What shows, and where.** Everywhere the owner's personal calendars show: the Calendar app's day, week and month, Up Next and the Calendar and Modular faces (through `agenda(from:to:)` and `events(from:to:)`), the glance, the Reminders app and widget, and the assistant ("what's on my calendar", "what's on my Errands list", "check off the books"). In the Calendars list they are grouped under the phone's name, "Kyle's iPhone", each "On Kyle's iPhone, only while recognized", and can be unchecked like any other. A reminders list on a phone has an iPhone mark in Reminders.
- **At once, and while the phone sleeps.** What the HomePad saved, in the member's encrypted cache, shows the moment they are recognized, before the phone answers. Each visit fetches the past week to six weeks ahead of events and the open reminders. A day, week or month that reaches past that says "Events from Kyle's iPhone show for Oct 29 to Dec 17." (`PhoneWindowFootnote`).
- **Shown once.** An event the iPad also has, such as an iCloud calendar on both the iPad's account and the phone, is matched by EventKit's external identifier and start and shows once, from the iPad.
- **Who sees it.** Only the member recognized here, and only their own phone (`phoneSnapshot` checks the snapshot's member against `viewer.unlockedMemberID`). Someone picked in People, a guest or another member sees nothing of it, and it is never in Settings, Personal Info, so an admin cannot browse it. It is gone from memory the moment the person stops being recognized. The cache stays sealed on the iPad until they stop sharing, unlink the phone or are removed.
- **Adding and changing events.** New events go to the recognized member's own iPad calendar first, then their phone's default calendar, then a shared one. When they go to the phone, Add Event opens HomePad's editor (`PhoneEventEditorSheet`): title, location, all day, start, end and the calendar, listing the phone's writable calendars and, on a real iPad, the iPad's own. Tapping a phone event opens the same editor. A change to a repeating event changes that day only. The assistant's `add_event`, Camera Lab's flyer scanner and anything else that calls `addEvent` reach the phone the same way.
- **Reminders.** Checking one off, the quick add field in one of the phone's lists, and the assistant's `add_reminder` and `complete_reminder` with a list only the phone has go to the phone. The default list (Groceries) is always the iPad's, the household's, even when someone's phone has a list with the same name.
- **Pending and failed.** A change shows at once, marked "Saving on Kyle's iPhone" (`PhoneChangeLabel`) until the phone saved it, waking it if needed. When the phone cannot be reached it says "Waiting for Kyle's iPhone" and is sent when the phone is back, even after the person walked away and came back. When the phone answers that it cannot save it, it says "Not saved on Kyle's iPhone" with the reason. Waiting and failed changes offer Try Again and Discard Change, in the event's editor and in a reminder's menu.
- **Nothing to set up on the iPad.** Each person checks calendars and lists in Show My Calendars, in the HomePad's remote on their iPhone.

## Find My

Apple has no public API for Find My locations or Play Sound, so HomePad gets them from Home Assistant, through the Smart Home module's existing connection: `services.smartHome.trackedDevices`, `zones` and `playSound(onTrackedDevice:)`. There is no second connection and nothing polls. When Home Assistant reports a tracker's new state, its pin moves.

### Where devices come from

GPS device trackers in Home Assistant:

- **The iCloud integration** (part of Home Assistant core). One tracker per device on the Apple Account, Family Sharing devices included, with battery, owner and accuracy. Home Assistant refreshes it about every 30 minutes. Sign in with the account's main password and the six-digit code. App-specific passwords do not work. Advanced Data Protection does not block Find My locations.
- **The Home Assistant app** (the Companion app) on an iPhone or iPad. It reports its own location on zone changes and big moves, with battery sensors.
- **Others with GPS**, such as the Life360 custom integration. They show on the map but cannot ring.

Router and Bluetooth trackers (Bermuda included) have no coordinates and are left out. AirTags and AirPods are not in Home Assistant at all, so the header's Open Find My button opens Apple's app for them.

### The app

- A full-screen MapKit map with a pin per device in its owner's color, zones as faint circles and a house at home. Pins that would overlap at the current zoom fan out around their middle (`FindMyPinSpread`), worked out when the map stops moving, so a household's devices at home stay apart and tappable.
- A glass panel lists the devices like Apple's Devices tab: My Devices, then each person's, then Other Devices. It sits on the leading side in landscape and across the bottom in portrait, and the map frames its pins in the part the panel leaves free.
- Tapping a row or a pin centers the map on it and opens its card: the street address (MapKit reverse geocoding, looked up once per spot and only for the card and the assistant), the zone, when it was last seen, battery, accuracy, where the location came from, and Play Sound.
- The map is still at rest. Pins have no motion of their own, and "last seen" labels redraw once a minute.

### Play Sound

- iCloud devices: `icloud.play_sound` with the Apple Account (the iCloud config entry's title) and the device's Find My name. The device plays a sound for about two minutes.
- Home Assistant app devices: a critical notification through `notify.mobile_app_<device>`, which rings at full volume even on silent.
- Others say they cannot ring instead of offering the button.
- The card shows Sending, then when it was sent, or why it failed: Home Assistant is offline, the notify action does not exist, and so on.

### Who sees whose devices

`FindMyVisibilityPolicy` decides, for the app and the assistant alike:

- Nobody recognized: nothing. The app sits behind the recognition gate, and picking a name in the People switcher is not enough.
- A recognized member sees their own devices.
- Admins see every device. They set up Home Assistant, which already shows them every tracker.
- Devices that belong to nobody show only to admins.
- With Share Devices with Everyone on, every recognized member sees every member's devices, as Family Sharing does. It is off by default, so a roommate never sees where the others are.
- Hidden devices never show.

HomePad finds each device's owner among the household's members: the Home Assistant person that lists the tracker, then iCloud's owner name, then the name in front of the device's own name ("Kyle's iPhone"). First names are enough. In Settings, Personal Info, Find My, an admin can pick a device's owner instead, mark it as nobody's (admins only) or hide it, and turn on sharing.

### What to set up in Home Assistant

1. Settings, Devices & services, Add integration, Apple iCloud. Enter the Apple Account's email and main password, then the six-digit code. Every device on the account, and on its Family Sharing members' accounts, appears.
2. Or install the Home Assistant app on each iPhone and iPad, sign in, allow location Always, and allow notifications with Critical Alerts for Play Sound.
3. Optional: in Settings, People, pick each person's trackers, so HomePad knows whose each device is.
4. Optional: zones such as Work (Settings, Areas, labels & zones, Zones), so the app and the assistant say "at Work".

Until then the app explains what is missing: "Connect Home Assistant", "No Devices Yet", or "No Devices for" a person who owns none.

### Demo

With demo data on (the default in the simulator), six devices sit around Madison with fixed addresses, so screenshots need no network. Five belong to the household's first three members (Alex, Sam and Jordan with `-HomePadDemoContent YES`), and a Kitchen iPad belongs to nobody, so only admins see it. Play Sound pretends to send.

## Reopening where you left off

Every app reopens where it was left, through `@AppState` (keys in `PersonalAppState`). The personal apps keep it for each recognized member, and one shared copy while nobody is recognized (picking a name by hand counts as not recognized), so one person's list, album, contact or device never shows for someone else. Something restored that is gone or not visible to this person falls back to the app's default without a word.

| App | Reopens on | Not restored |
|---|---|---|
| Calendar | Day, week or month, and the day it was on. The day is a time position: after four hours, or on another day, Calendar opens on today in the view it was left in (`AppStateStore.timePositionLifetime`) | The Calendars list and the event editor |
| Reminders | The smart list or list chosen last. Otherwise Today when something is due, else All | A half-typed reminder |
| Photos | The open album, and in this launch the photo at the top of its grid (saved once scrolling stops). The albums when the album is gone | The viewer and the slideshow |
| Find My | The selected device's card while it is still visible to this person. Otherwise, in this launch, where the map was left | Play Sound's progress |
| Weather | The place chosen in the app or Settings (`personal.weather.location`, already a setting) | Near and far follow whoever is in the room |
| World Clock | The clock style (`personal.worldclock.style`, already a setting) and the cities | Nothing else to keep |

`-HomePadCalendarMode`, `-HomePadPhotosAlbum` and `-HomePadFindMyDevice` win over what was restored, and any shell argument that opens a screen starts every app from its defaults.

## Showing and hiding calendars

The Calendar app's Calendars button opens a list like Apple Calendar's: the calendars the current viewer may see, grouped by account (iCloud, other accounts, subscribed calendars, then Other), each with its color, who it belongs to and a checkmark to show or hide it, plus Show All and Hide All in its header. Changes apply at once.

- The choice belongs to the active member (recognized or picked in the People switcher), and to guests while nobody is selected. It is saved per person in `personal.calendar.unchecked`, which stores only unchecked calendars, so a calendar added later shows.
- It applies to everything that shows events: the Calendar app, Up Next and the Calendar and Modular faces (through `events(from:to:)`), and the assistant's calendar answers.
- It never changes who may see a calendar. A calendar personal to someone else, or hidden in Settings, is not listed at all, and Show All and Hide All touch only the listed calendars, so a member's own calendars keep their checkmark while they are not recognized. The list says that ownership is set in Settings, under Personal Info.
- The recognized person's phone calendars are listed under the phone's name, and which of them the HomePad may see at all is chosen on that phone.
- New events go to a checked calendar first, so they show where they were added.

## Weather

- `PersonalWeatherService` tries `WeatherKitProvider` and then `OpenMeteoProvider`. WeatherKit needs the WeatherKit capability on the App ID (enabled in the developer portal) and a profile that includes it. Development builds and the simulator usually fail with an authorization error, and Open-Meteo takes over silently.
- Forecasts are stored in metric and converted for display. Units: Automatic (from the iPad's region), °F with mph, or °C with km/h.
- The weather background task refreshes every 15, 30 or 60 minutes (at least 10), and 5 minutes after a failure. Weather and the weather widget refresh a stale forecast as they appear. The last forecast is cached in Caches so weather shows immediately after relaunch.
- Location is never requested at launch. The Weather app first asks where weather should be for: "Use My Location" (then iPadOS asks for when-in-use access) or a city found with MapKit geocoding.
- Attribution: Apple Weather's legal link for WeatherKit, "Weather data by Open-Meteo.com" (CC BY 4.0) for Open-Meteo.
- The widget's text stays white on its sky, as in Apple's widget. A black shade between the sky and the text keeps it readable on a bright sky: at each height as dark as `WeatherPalette.textShade` works out from the sky's gradient under its clouds at their strongest, so that white reaches 4.5 to 1 (WCAG for text below its large size). Dark skies get none, and a snowy day about 0.4. The Weather face does the same on its own sky (see the Faces README). `WeatherTextShadeTests` checks it on every sky.

## Background tasks

The module registers three tasks with Core's background work (`PersonalBackgroundTasks`, see "Background work" in the Core README). Settings, Background Tasks shows each one's last run and result, and has Run Now.

| Task | Every | Waits for | In the background | What it does |
|---|---|---|---|---|
| Photo Sync (`personal.photoSync`) | hour, and whenever the library changes | nobody using the screen | app refresh, processing | Reads the albums again, then prepares every album's cover and the first screen of thumbnails of the library and of each album that gained photos |
| Calendars and Reminders (`personal.calendarSync`) | 15 minutes | nothing | app refresh | Asks EventKit to pull from the iPad's accounts when its copy is out of date (`refreshSourcesIfNecessary`). New events come back through EventKit's change notification |
| Weather (`personal.weather`) | the refresh setting, 5 minutes after a failure | nothing | app refresh | Refreshes the forecast for the faces, widgets and Weather |

### Photo sync

Before, Photos read the library and started watching it for changes only once it was opened, so a photo added on an iPhone showed up only after Photos had read everything while someone waited. Now:

- At launch, on the iPad that shows HomePad, `startSyncing()` reads the albums and registers the PhotoKit change observer, as long as the household has someone who may see photos (`PhotoAccessPolicy.householdSources`).
- When the library changes (iCloud brings in a photo, someone joins a shared album), the observer reads the albums again a quiet second later, at background priority, and asks for a sync.
- The sync runs while nobody uses the screen. It prepares every album's cover at the cover size, and the first screen of thumbnails of the library and of albums that gained photos, at the grid's size, in `PHCachingImageManager` (`PhotoGridMetrics` keeps the sizes the views and the sync share). It allows network access, so pictures that live only in iCloud download then. It stops between albums when someone starts using the screen, drops older prepared pictures before each sync, and drops them all on a memory warning.

What it cannot do: HomePad cannot make iCloud Photos download sooner. iOS's own photo service decides when new photos reach the iPad, and PhotoKit has no call that starts it. Whether a PhotoKit fetch nudges that service is not verified. The one report found (Apple Developer Forums thread 701975, unanswered) says plain fetches did not bring in new iCloud items until the Photos app or the system photo picker was opened, which suggests fetches alone do not. The simulator has no iCloud Photos, so it could not be tested here.

## Structure

```
Sources/HomePadPersonal/
  PersonalModule.swift           registration
  PersonalApps.swift             app descriptors
  Shared/                        settings keys, errors, service container, background tasks, debug launch arguments
  Calendar/
    Models/                      CalendarSource, CalendarAudience + CalendarVisibilityPolicy, events, reminders, date math, Up Next, account groups
    Backends/                    CalendarBackend protocol, EventKit backend (+ EventKitUI support), demo backend
    Services/                    HouseholdCalendarService (+ reminders, + mapping, + day lists, + shown calendars, + phone)
    Views/                       Calendar app, day / week / month views, Calendars list, event editor and chooser wrappers,
                                 HomePad's editor for phone events, a change's state, the phone's window
  Reminders/Views/               Reminders app
  Weather/
    Models/                      forecast, condition, place, units
    Backends/                    WeatherKit, Open-Meteo (+ response decoding), demo
    Services/                    PersonalWeatherService, location, MapKit place search, cache
    Views/                       Weather app, far and near layouts, panels, animated sky
  WorldClock/                    city model, time zone math, offline city catalog, store, views
  Photos/                        album model, who sees which album, paging, PhotoKit service and photo sync, demo photos,
                                 grid and its sizes, video player and length badge
    Views/Viewer/                full-screen viewer and slideshow, thumbnail frames to grow from and land on, pull and landing geometry
    Phone/                       the recognized person's iPhone: who may see it, its rows in the album grid, an album's screen
  FindMy/                        Find My app
    Models/                      devices, owners, visibility, kinds, wording, pin spreading, spoken matching
    Services/                    FindMyService, addresses, Play Sound states, demo devices
    Views/                       map, pins, list, panel layout, card, labels, setup states
  Widgets/                       six widgets
  Settings/                      Personal Info pane and its sections
  Assistant/                     tools (Find My's too), forecast and world time wording, reminder matching
```

### Shared UI

Personal builds on HomePadUI: `GlassIconButton`, `PermissionPrompt` before iPadOS asks for access, `systemSheetStyle()` for Apple's system controllers, and `AnalogClock` for World Clock (the same dial the World Clock face uses).

### Light and Dark

Every screen follows the Appearance setting (Settings > Kiosk & Display), with text in `.primary` and `.secondary` and fills in `.primary` at a low opacity, so Calendar in Light is a white page with dark text and red accents like Apple's Calendar, and Reminders, World Clock, Contacts, the Photos grid, Find My's map and panel, and every sheet go light with it. Event titles take a light tint of their calendar's color on a dark page and a deep shade of it on a white one.

Three things stay dark in Light, as in Apple's apps: Weather (its sky is a picture, with white text and dark glass on it), the photo viewer and slideshow (photos on black), and video. White also stays where it sits on a color or a picture: the selected day's number on its red circle, the Reminders tiles, a calendar's check, the weather widget's sky and the pins on the Find My map.

## Widgets

| ID | Sizes | Personal |
| --- | --- | --- |
| `personal.weather` | small, medium, large | no |
| `personal.upnext` | small, medium, large, tall | yes |
| `personal.reminders` | small, medium, large, tall | yes |
| `personal.worldclock` | small, medium, large | no |
| `personal.photo` | small, medium, large | no |
| `personal.date` | small, medium, large | no |

Each widget draws its own tile and fills the frame it is given, so the host should not wrap it in another `GlassTile`. The calendar widgets, Up Next and Date, are solid cards like HomeView's Calendar widget (`GlassTile(surface: .solid)`): white with dark text and the red accent, and black at night, so the red night tint never turns them into bright red blocks.

Up Next and the Calendar app read the same day lists (`HouseholdCalendarService.events(on:)`), so the widget never lists an event under a day that the app's day view leaves out. Up Next shows today's all-day events and the ones that have not ended, like the faces. Once today has nothing left it shows tomorrow's events under a Tomorrow label, as Apple's Up Next widget does. The tall size (two cells wide, three tall) lists more of the day, and when today's events leave room it goes on with tomorrow's under a Tomorrow label (`upNextFollowingDay(after:)`, which leaves out an event already listed, such as a trip across both days). It reloads every minute, so events drop off as they end and the list moves on at midnight. The app's day view shows whole titles (up to three lines), like the widget and the faces.

Up Next has no settings of its own: it lists the calendars left checked in the Calendar app, so there is one place to choose them.

In a widget stack, Up Next and Weather ask Smart Rotate to show them (`PersonalWidgetRelevance`, see "Smart Stacks" in HomePadUI's DESIGN.md). Up Next asks in the half hour before a timed event and while it runs (`.timely`), and asks again half an hour before the next one. Weather asks while rain, snow or sleet is forecast in the next two hours (`.timely`), and more urgently for storms, hail, freezing rain or heavy snow (`.needsLook`), since the forecast carries no weather alerts. All-day events never ask.

Reminders lists as many reminders as fit its tile, up to 8, and up to 16 on the tall size. Its Edit Widget page (`RemindersWidgetSettingsView`) picks the list each widget shows, so one can follow Groceries and another Errands. It saves the list's identifier (the setting `list` in `RemindersWidgetSettings`), so a renamed list stays chosen, and nothing for the default list, so the widget follows a new default. The page offers only the lists the person at the screen may see. The widget shows its list only while the person at the screen may see it, and the default list otherwise (`RemindersWidgetSettings.shownList`), so a list only its owner may see never shows for a guest or another member, and neither does its name.

## Settings (pane id `personal`, admin only)

Weather location, units and refresh. Calendars and reminders lists per member, and the policy for calendars nobody chose. Default reminders list. World Clock cities and style. Find My sharing and each device's owner. The photo library's owner, photo sources (the whole library, favorites, shared albums, chosen albums, picked photos) and slideshow speed. When none of the chosen sources has photos, the slideshow and the Photo widget show the library. Demo data.

| Key | Type | Default |
| --- | --- | --- |
| `personal.demoData` | Bool | true in the simulator, false on device |
| `personal.calendar.audiences` | [calendar id: CalendarAudience] | empty |
| `personal.calendar.unassigned` | UnassignedCalendarPolicy | admins |
| `personal.calendar.unchecked` | [member id or "guest": Set of calendar ids], set from the Calendar app | empty |
| `personal.reminders.defaultList` | String (synced) | Groceries |
| `personal.weather.location` | WeatherLocationChoice | undecided |
| `personal.weather.units` | WeatherUnitSystem (synced) | automatic |
| `personal.weather.refreshMinutes` | Int | 30 |
| `personal.worldclock.cities` | [WorldClockCity] (synced) | New York, London, Tokyo, Sydney |
| `personal.worldclock.style` | WorldClockStyle (synced) | analog |
| `core.photos.libraryOwner` | member ID (`PhotoLibraryOwner.setting`, in Core) | nil: the first admin |
| `personal.photos.sources` | PhotoSourceSelection | favorites and shared albums, the library when those are empty |
| `personal.photos.slideshowInterval` | Double seconds | 8 |
| `personal.findmy.owners` | [tracked device id: FindMyOwnerChoice], set in Personal Info | empty (automatic) |
| `personal.findmy.shareWithEveryone` | Bool | false |

## For other modules

- Add groceries with `services.calendar.addReminder(title: "Milk", due: nil, listName: nil)`. A nil list uses the default list, which is created and shared with everyone if missing. Name a list to target it.
- `services.calendar.events(from:to:)` returns only events from calendars the current viewer may see and left checked in Calendars, their own phone's included. `reminders(includeCompleted:)` returns only what the current viewer may see.
- Add a full event with `services.calendar.addEvent(EventDraft(title:start:end:isAllDay:location:calendarID:))` (`EventDraft` is in Core). `writableEventCalendars()` lists the calendars the current viewer may add to (visible, not subscribed, not read-only), the one their new events usually go to first, with their phone's writable calendars. A calendar the viewer may not see is refused. One on their phone is sent there and returns at once, and the Calendar app shows how it stands. Camera Lab's flyer scanner uses both.
- `services.weather.current` is a `WeatherSnapshot` in the household's units with 24 hourly entries.

## Assistant tools

| Tool | Recognition | Purpose |
| --- | --- | --- |
| `get_daily_forecast` | no | Day-by-day forecast, 1 to 10 days |
| `list_reminders` | required | Open (or all) reminders, optionally one list |
| `complete_reminder` | required | Check off a reminder by loose title ("the milk") |
| `world_time` | no | Local time in a city and the offset from home. Works offline for zone cities and common aliases. |
| `find_device` | required | Where devices are, in Find My's words: "Kyle's iPhone is at home, last seen 2 minutes ago, with 82% battery." Zones by name ("at Work"), else a street address. Takes a device ("iPhone", "Kitchen iPad") and an owner (a name, "me" or "everyone"). |
| `play_sound_on_device` | required | Play Sound on one device ("ping my iPad"). Asks which one when several match, and says when a device cannot ring. |

Both Find My tools answer only about the devices the recognized person may see in the Find My app, so "where is everyone's phone" lists only what that person could see on screen. `FindMyDeviceMatcher` reads "my iPad", "Kyle's iPhone", "everyone's phone" and "the kitchen tablet". Every word that is not a kind of device must be in the device's name, so a request for someone else's phone never falls back to the asker's own.

The generic `get_weather`, `get_calendar`, `add_reminder` and `add_event` tools belong to the Assistant module.

## Simulator and debug launch arguments

The simulator has no accounts, so demo data is on by default there: calendars, reminders, photos, Find My devices and a demo forecast until a location is chosen.

```
-HomePadOpenApp calendar|reminders|weather|worldclock|photos|findmy
-HomePadProximity far|near            Weather far and near layouts
-HomePadRecognize Kyle                recognize a member (added as admin if missing) to see personal calendars
-HomePadDemoWeekday 3                 demo calendar: today follows this weekday (3 is Tuesday, long Canvas titles)
-HomePadCalendarMode day|week|month   open Calendar in that view
-HomePadCalendarsList YES             open Calendar's Calendars list
-HomePadUncheckCalendars "Work"       leave exactly these calendars unchecked (comma separated, or none) for whoever is active
-HomePadCalendarReport YES            write calendar-report.txt (every calendar, why it shows, whether it is checked) to Documents, in every build
-HomePadSeedCalendars YES             simulator: turn demo data off and add real "Canvas" and "Family" calendars
                                      (grant access first: xcrun simctl privacy <sim> grant calendar com.ksha23.homepad)
-HomePadWeatherCity "Madison, WI"     real weather for a city (WeatherKit, then Open-Meteo)
-HomePadPersonalGallery YES           adds debug apps personal.widgets and personal.settings
-HomePadPhotosAlbum "Summer Trips"    open Photos on an album, by title or kind (library, favorites)
-HomePadPhotosSlideshow YES           start the Photos slideshow
-HomePadPhotosViewer 5                with -HomePadPhotosAlbum, open its fifth photo full screen
-HomePadFindMyDevice "Sam's iPhone"   open Find My on a device's card, by name or ID
```

All but `-HomePadCalendarReport` work in debug builds only. Find My, Photos and the personal widgets need a recognized member: add the shell's `-HomePadDemoContent YES -HomePadMember Alex -HomePadRecognized YES` (Alex is an admin, so Find My shows every demo device, and the first admin, so Alex owns the photo library). `-HomePadMember Sam` shows Photos as another member sees it, with the Family Shared album only. The demo albums hold photos only, so a video and its length badge need the simulator's own library (below).

`-personal.demoData '<66616c7365>'` (the JSON `false` as property list data) turns demo data off for one launch, so Photos reads the simulator's own library. `xcrun simctl addmedia` adds photos to it. `xcrun simctl privacy <sim> grant photos com.ksha23.homepad` writes a grant with `auth_version` 1, but PhotoKit's read and write check on the iOS 26 simulator asks for version 2, so the app still asks for access. Setting `auth_version=2` on that row of the simulator's `data/Library/TCC/TCC.db` makes the grant count. Reboot the simulator after changing a row, because tccd caches it.

## Needs testing on a real iPad

- WeatherKit with a provisioned build, and the switch to Open-Meteo when it is not.
- Calendar and Reminders permission prompts, `EKEventEditViewController` adding and editing, `EKCalendarChooser` mapping, and change notifications from other devices.
- The Calendars list with real accounts: grouping by EventKit's account names (iCloud, Gmail, Subscribed Calendars, Other) and a Canvas feed.
- Shared iCloud calendars and lists accepted on the iPad's account.
- iCloud Shared Albums and favorites through PhotoKit, including limited library access and "Allow More Photos".
- Photos as the owner, as another member (shared albums only) and as a guest (the gate), and the pickers in the wallpaper, recipe card, Messages, the assistant, Camera Lab and the face editor disappearing for anyone but the owner.
- Photo sync with iCloud Photos: add a photo on an iPhone, wait until it reaches the iPad, then open Photos and check it shows at once. Also how long iCloud takes to deliver while HomePad sits idle in front, which HomePad cannot change.
- The weather and calendar tasks in the background, and whether iOS gives HomePad app refresh and processing launches at all while it usually sits in front.
- A person's own iPhone photos: the section appearing within a few seconds of recognition with the iPhone in a pocket, and going away when they walk off. The Connect README lists the phone's side.
- A person's own iPhone calendars and lists: saved ones at once on recognition and fresh ones a few seconds later, an event added at the HomePad appearing in the phone's Calendar with the phone in a pocket, Waiting when the phone is force quit, an iCloud calendar on both the iPad's account and the phone showing once, and HomePad's editor with real calendars.
- A library of tens of thousands of photos: album loading, the Library grid and the Photo widget.
- The Messages composer.
- Core Location prompt and reverse geocoding.
- Find My against a real Home Assistant: iCloud and Home Assistant app trackers, pins moving as they update, Play Sound on both kinds, owners matched from Home Assistant people, and the map with a whole household at home.
- Animated sky performance on the 11-inch iPad Pro.

## Known gaps

- Reminders are read and checked off, but their due dates, notes and priorities cannot be edited in HomePad.
- A person's phone calendars show the past week to six weeks ahead only. Their events and reminders are added, changed and checked off from HomePad, not deleted, and notes stay on the phone.
- The month view shows up to three events per day. There is no hour-by-hour timeline view.
- PhotoKit has no public API for Memories or the system's Featured Photos, so the Photos app shows neither.
- Weather has no severe weather alerts or precipitation map.
- Find My cannot see AirTags, AirPods or items, and cannot mark a device as lost. iCloud locations are only as fresh as Home Assistant's polling, about every 30 minutes.
- The iCloud integration has open bugs in Home Assistant 2026.10: sessions lost after a restart (home-assistant/core#187890), repeated "allow access to iCloud data" prompts with Advanced Data Protection (#185844), and correct six-digit codes rejected or accounts with security keys unable to sign in, both fixed in the development branch and expected in 2026.11 (#186146).
