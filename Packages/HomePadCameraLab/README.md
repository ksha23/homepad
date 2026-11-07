# HomePadCameraLab

Back-camera features HomeView does not have. HomeView's camera only does calls and recognition. HomePad uses the iPad's back camera, and LiDAR on iPad Pro, for seven tools in the Camera Lab app (app id `cameralab`), plus the Floor Plan app (app id `floorplan`).

## Features

| Tool | What it does | Frameworks |
|---|---|---|
| Ask About This | Live back-camera view. Freeze a frame (or pick a photo), ask by voice or typing, read the streamed answer in big type. Example chips: "What plant is this?", "Is this avocado ripe?", "How do I fix this?" | AVFoundation, `services.assistant.ask(AssistantRequest(text:images:))`, Speech on `services.microphone` |
| Recipe and Document Scanner | VisionKit document camera, then Vision `RecognizeDocumentsRequest` (iOS 26, the newest document API in the iOS 27 SDK) with a `RecognizeTextRequest` fallback. Recipe Card mode posts `.custom(name: "kitchen.importRecipeText", payload: .string(text))`. Calendar Events mode finds the events on a flyer, an invitation or a school letter for review (see [Calendar events from paper](#calendar-events-from-paper)). Copy Text mode copies or shares. | VisionKit `VNDocumentCameraViewController`, Vision, `NSDataDetector`, `services.calendar` |
| Grocery Scanner | Live Text barcode scanner. Looks products up in Open Food Facts and adds them to Reminders with `services.calendar.addReminder(title:due:listName:)`. Each item waits 5 seconds before it is added, so Undo really takes it back. Tapping printed words adds them too. | VisionKit `DataScannerViewController`, URLSession |
| Security Camera | Motion detection by frame differencing, confirmed by Vision person detection. Token-protected MJPEG server for Home Assistant. Ring buffer of motion snapshots, optional webhook, `.motionDetected(source: "cameralab.security")`. Schedules: Always, At Night, When Away. | AVFoundation, Vision, Network.framework |
| Floor Plan | RoomPlan scan of one or more rooms on a shared ARSession, converted to a 2D plan (walls, doors, windows, furniture) saved as JSON. Drag accessories from `services.smartHome.accessories` onto it. Pins show live state, tap to toggle. Demo plan without LiDAR. | RoomPlan `RoomCaptureView`, ARKit |
| Timelapse | Back-camera stills at a curated interval into a Photos album, and a player that steps through them like a video. | AVFoundation, Photos |
| QR Scanner | Wi-Fi details, links, Matter (`MT:`) and HomeKit (`X-HM://`) setup codes, decoded and shown. Display only. | VisionKit, Vision |

### Calendar events from paper

Calendar Events is the scanner's middle mode. Point the back camera at a flyer, an invitation or a school letter (or choose a photo), and the events on it open in an Events sheet to review before they go to a calendar.

- **Reading the page stays on the iPad.** Vision recognizes the text, then `FlyerEventExtractor` finds the events in it with `NSDataDetector` (dates, times, ranges and street addresses) and the lines around each date. The detector picks years and fills in missing days inconsistently, so each date is read again from what the page wrote: a date without a year is the next one from today on, and the one whose weekday matches when the page names it ("Saturday, April 18"). A weekday alone is the next such day, "tomorrow" counts from today, and a time on its own ("10 AM - 2 PM" under "Saturday, April 18", or "leaves at 9:15 AM and returns by 2:30 PM") belongs to the date just above it. The detector skips any date right after the word "due", so it reads a copy of the text with "due" written as "by " (the same length, so every date keeps its place in the real text).
- **Titles and places.** An event takes its title from the words beside its date ("Picture Day: Thursday, September 17", one event per line in a list of dates), a "What:" label, or the flyer's headline: the line above the first date most like an event's name ("SPRING BAKE SALE" over "LINCOLN ELEMENTARY PTA", never "You're Invited!" or "Dear Families,"), with shouted capitals set in title case. A letter's long line uses its sentence ("Second grade class will visit the Henry Vilas Zoo"). The place is "at" or "in" after the date, a "Where:" label, or the street address with the place named on the line above it ("Lincoln Elementary School Gym, 1234 Maple Ave, Madison, WI 53711"). A date with no time is an all-day event, a range of days ("October 22-23") spans them, and a time with no end lasts an hour, like the assistant's events.
- **Deadlines.** "RSVP by April 26" and "Permission slips are due Monday, October 5" become their own all-day events ("RSVP for Maya's 7th Birthday Party", "Permission slips due"), listed but switched off, so only the event itself is added unless the person wants the deadline too.
- **Review.** Each event's title, start, end, all day and location can be changed in the sheet, with the words it came from under it, and a switch for whether to add it. Moving the start moves the end with it. The calendar is picked once, from `services.calendar.writableEventCalendars()`: the person's own calendars and the shared ones, the one their new events usually go to first. "Add 2 to Calendar" is the sheet's one action. Added events leave the list, so a second tap cannot add them twice. With no date found, "Add an Event by Hand" starts a blank one. Find Events beside the text runs it again after the text is edited.
- **Personal.** Adding needs a recognized member, like every other calendar write. Until then the sheet says so, lists only shared calendars and keeps Add dimmed. Writes go through `services.calendar.addEvent(_:)` with an `EventDraft` (title, start, end, all day, location and the chosen calendar), which Personal checks against what the person may see.
- **An AI provider, when asked.** With an assistant set up, Read Again with Claude (or whichever provider answers) sends the recognized text, never the photo, as a self-contained text task (`AssistantRequest.textTask`): the provider gets a prompt with today's date and the text, and nothing about the household, no tools and no chat history (`AssistantEventReader`). Its JSON replaces the list. An unusable reply leaves the on-device events in place.

### Reopening where you left off

Camera Lab never reopens straight into the camera. Closing it on a tool that shows the camera as it appears (Ask About This, Grocery Scanner, Security Camera, Timelapse, QR Scanner) goes back to the hub, so the next opening starts there. The Recipe and Document Scanner and Floor Plan, which only use a camera when tapped, reopen as they were, in the same launch and after a relaunch (`CameraLabAppState.tool`, an `@AppState` shared by the household). A tool asked for while the app is closed, such as the assistant's `scan_groceries`, and `-CameraLabTool` still open straight into it.

The Floor Plan app has nothing to restore: the plan itself is saved, and Arrange mode ends when the app closes.

Also registered:

- Settings pane "Camera Lab" (pane id `cameralab`).
- Assistant tools: `look_with_camera`, `scan_groceries`, and `security_camera` (on, off or status, recognized members only).
- Overlay `cameralab.securityIndicator`: a red "Security Camera On" pill at the top center of every screen while it watches.
- Control Center tile `cameralab.security`: tap to turn Security Camera on or off. It fills red while on and reads Off, Scheduled or Watching.

## How the camera is shared

`CameraBroker` is the one place that starts and stops cameras. Every tool asks it with an owner name, and it mirrors the newest claim into `services.capture.claim(owner, camera:)`, so the presence sensor yields while any tool holds a camera and resumes when the last one releases.

- Tools that read frames (Ask About This, Security Camera, Timelapse, `look_with_camera`) share one `AVCaptureSession` when they want the same camera. Security Camera and Timelapse can run together on the back camera.
- Tools whose Apple UI owns the camera (document camera, Live Text scanner, RoomPlan) need it exclusively. If Security Camera is watching, they show "Security Camera is using the back camera. Stop it first."
- The broker re-claims if another module releases over it, and stops when the Control Center privacy switch turns cameras off.
- A tool screen holds its camera only while it is on screen and the display is awake (`holdsCamera`). Security Camera and Timelapse keep theirs while the display sleeps, since that is their job.
- In the simulator there is no camera, so a labeled synthetic "Demo Feed" (a room with a figure walking through every 12 seconds) stands in. Motion detection, the MJPEG server, snapshots and timelapse all work end to end on it.

## Light and Dark

The tool pages follow the Appearance setting (Settings > Kiosk & Display): the hub, the grocery list, the document text, the security and timelapse settings, and the floor plan, whose walls and furniture are drawn in white on the dark page and in black on the white one. What a camera shows stays dark in Light, like the Camera app: `CameraViewport` and `LiveScannerView` keep the dark scheme for the picture and the controls on it, and the document camera, the RoomPlan scanner, the snapshot viewer and the timelapse player stay dark too.

## Structure

```
Sources/HomePadCameraLab/
  CameraLabModule.swift        registration, launch arguments
  CameraLab.swift              shared state handed to every view
  Capture/                     broker, live session, demo feed, frame encoding, stills, capabilities
  Hub/                         Camera Lab app: tool list, router, hub screen
  AskAboutThis/                model, spoken question listener, screen
  Documents/                   document camera sheet, text recognizer, screen
    Events/                    events from text (extractor, text patterns), assistant reading, review state and sheet
  Groceries/                   Open Food Facts client and models, session with undo, screens
  Security/
    Motion/                    luma grid, motion detector, sensitivity levels, person check
    Server/                    HTTP parser, token, routes, MJPEG framing, NWListener server, HA setup values
    Storage/                   snapshot ring buffer
    Schedule/                  schedule presets
    Alerts/                    webhook
    Views/                     screen, settings sections (shared with the Settings pane), indicator, tile
  FloorPlan/
    Model/                     plan model, converter, RoomPlan adapter, store, demo plan
    Scan/                      RoomPlan controller and screen
    Views/                     drawing, pins, palette, canvas, app screen
  Timelapse/                   intervals, Photos album, controller, player, screen
  QRScanner/                   payload parsing (Wi-Fi, Matter, HomeKit), result card, screen
  Assistant/                   assistant tools
  Settings/                    setting keys and the Settings pane
  Views/Camera/                camera viewport, demo feed, Live Text scanner, photo picker
```

Shared UI comes from HomePadUI: `FeatureTile` for the tool grid, `GlassPill` for the capability row, `StatusBadge`, `GlassIconButton`, `SuggestionChips`, `CopyableValueRow`, `GlassPanel` for the tool panels, `CameraPreview` and `glassButtonStyle(isProminent:)`.

## Settings

All keys start with `cameralab.`. Choices are curated:

- Ask About This: read answers aloud (on by default).
- Grocery Scanner: Reminders list name (default "Groceries").
- Security Camera: on or off, camera (back by default, front optional), schedule (Always, At Night 11 PM to 7 AM, When Away after 20 quiet minutes), sensitivity (Low, Medium, High), only alert for people, snapshots kept (20, 50, 100, 200), port (8081, 8080, 8090, 8888, 9000).
- Timelapse: interval (30 sec, 1 min, 5 min, 15 min, 1 hour) and album name.
- Floor Plan: use the demo plan or delete the plan.

Secrets live in `services.keychain`: the stream token (`cameralab.security.streamToken`) and the webhook URL (`cameralab.security.webhookURL`). Security Camera and Timelapse remember that they were on and resume after a relaunch.

## Home Assistant

The Security Camera screen and the Settings pane show the exact values for Settings, Devices and services, Add integration, MJPEG IP Camera:

- MJPEG URL: `http://<ipad-ip>:8081/stream.mjpeg?token=<token>`
- Still Image URL: `http://<ipad-ip>:8081/snapshot.jpg?token=<token>`
- Username and password empty, Verify SSL off.

A wrong or missing token gets 401. "Make New Token" disconnects every viewer. The optional webhook receives JSON with `event`, `source`, `person_detected`, `changed_fraction`, `time` and `snapshot_url`.

## Launch arguments

- `-HomePadOpenApp cameralab -CameraLabTool <ask|documents|groceries|security|floorPlan|timelapse|qr>` opens a tool.
- `-CameraLabSecurity on` turns Security Camera on at launch.
- `-CameraLabTool documents -CameraLabDemoFlyer YES` reads a sample birthday invitation as if scanned and opens the event review (debug builds). Add `-HomePadDemoContent YES -HomePadMember Alex -HomePadRecognized YES` for a recognized person and the demo calendars. The demo calendars are read-only, so adding there says so. `-HomePadSeedCalendars YES` (see the Personal README) gives the simulator real calendars to add to.

In the simulator, `-HomePadOpenApp cameralab -CameraLabTool security -CameraLabSecurity on` serves the demo feed at `http://127.0.0.1:8081/stream.mjpeg?token=<token shown on screen>`.

## Tests

Swift Testing covers events from four scanned pages saved as text fixtures (a bake sale flyer, a birthday invitation with an RSVP, a school letter with a due date, and a school's list of dates), years and weekdays counted from a fixed today, all-day drafts, what the assistant is sent and how its reply is read, and adding only for a recognized person to the chosen calendar. Also HTTP request parsing, MJPEG framing, routes and the token check, motion detection on synthetic frames (moving object, brightness change, noise, scene change, background adaptation, sensitivity order, BGRA to luma), Open Food Facts decoding from recorded fixtures, floor plan conversion with synthetic transforms and JSON persistence, QR payloads (Matter SDK test vector, spec manual code, HomeKit URI, Wi-Fi escapes), schedules, the snapshot ring buffer, and the webhook payload.

## Dependencies

None beyond Apple frameworks. Considered and not used:

- FlyingFox (MIT) as the HTTP server. It has no documented way to stream an open-ended `multipart/x-mixed-replace` body, which is the whole point here, and the hand-written server is under 300 lines with tests.
- HomeKit Secure Video interop. An iOS app cannot publish itself as a HomeKit camera accessory, so Home Assistant over MJPEG is the bridge (Home Assistant can then expose it to HomeKit through its HomeKit Bridge integration).

## Needs real-device testing

- Live preview orientation and frame rotation on a wall-mounted iPad in each orientation.
- Motion thresholds and Vision person confirmation in real rooms and low light. Hours-long thermal behavior of Security Camera at 15 fps.
- Local network permission prompt and the MJPEG stream in Home Assistant, including several viewers.
- `DataScannerViewController` barcode reading (EAN-13, UPC-E) and the Reminders write through the Personal module.
- Document camera and `RecognizeDocumentsRequest` quality on recipe cards.
- Calendar Events on real paper: glossy flyers, script fonts, two-column school newsletters and handwritten invitations, read through the document camera. The fixtures are typed text, so how Vision orders lines on a busy flyer (and whether the time still lands under its date) needs the iPad's camera. Then adding to a real iCloud calendar shared with the HomePad account.
- RoomPlan on an iPad Pro with LiDAR, multi-room scans on one ARSession, and wall orientation in the converted plan.
- Photos album creation and long-running timelapse.
- Spoken questions on the shared microphone while the wake word also listens.

## Known gaps

- iOS stops the camera when HomePad is not in the foreground, so Security Camera assumes the kiosk stays in front (Guided Access).
- When Away uses presence and screen touches. Presence is paused while the camera watches, so touching the screen is what ends it.
- Undo cannot remove an item that already reached Reminders, because `CalendarService` has no delete.
- `look_with_camera` returns a text description because tool results are text only.
- Calendar Events reads English pages. Titles come from rules about lines and labels, so a flyer laid out unusually can get its organization's name as the title, and a letter's title is its whole clause. Every field can be edited before adding, and the assistant can read the page again when one is set up.
- A time range across midnight without a written end day, and repeating events ("every Tuesday"), are not recognized as such.
- The stream is plain HTTP on the LAN. The token is the only protection.
