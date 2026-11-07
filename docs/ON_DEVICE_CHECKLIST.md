# On-device checklist

Everything below builds, passes its unit tests, and was checked in the iPad simulator. These items need real hardware: cameras, microphone, HomeKit, AirPlay speakers, Face ID, OLED panels, or two devices. Each package README has more detail.

## First 30 minutes

1. **Install** with `make device DEVICE=<id>` (see the README). Confirm the app launches into onboarding.
2. **Onboarding**: name the household, add yourself as an admin, then skip or fill the rest.
3. **AI**: Settings > AI Assistant. Add one API key, tap Test, then pull down from the top and ask "what's the weather". Try "Hey HomePad".
4. **Home Assistant**: Settings > Smart Home. Your instance should appear under Discovered. Paste a long-lived token. Check that the Home app fills with rooms and that a light toggles.
5. **AirPlay**: play a radio station in Music, then pick a HomePod with the AirPlay button. Try two HomePods at once. Then turn on "Keep Microphone On" and confirm the wake word still works with one speaker.
6. **Presence**: Settings > Presence & Privacy > Live Status. Walk toward and away from the iPad. Distance and proximity should follow, including with the lights off. Then enroll your face and check that "Hello, <name>" appears when you walk up.
7. **Kiosk**: turn on Guided Access, triple-click inside HomePad, and leave it for an hour. Check that the screen dims, that night mode turns red after dark, and that it wakes when you approach.

## By area

### Shell and kiosk
- Brightness ramps and restore (the simulator ignores brightness), and how night mode feels in a dark bedroom.
- Guided Access, and the Single App Mode button on a supervised iPad with an MDM profile allowing `com.ksha23.homepad`.
- Edge swipes with real fingers, with and without Guided Access.
- The system volume slider and AirPlay picker in Control Center.
- Face ID sheets for admin panes and the recognition gate.
- The not-charging banner, heat reactions, and burn-in drift over long sessions on the OLED iPad Pro.
- Turning the iPad between portrait and landscape. The simulator refuses programmatic rotation, so landscape was checked with `-HomePadForceLandscape YES`, which cannot give UIKit-backed navigation (Settings, Camera Lab) the shell's margin.
- Live reorder with a finger on the Home Screen and in Control Center: press to lift, drag, and hold at a side of the screen to turn the page.
- Edit Widget in Home Screen edit mode: a quick tap on Home Favorites or Reminders opens it, and a press on the same widget still lifts it at once. Check with a real finger that the tap never delays the lift.
- Tall widgets (Home Favorites, Up Next, Reminders) in landscape on the 11-inch and the 13-inch, at the Extra Large and Huge text sizes, where a page has fewer rows.

### Faces
- Vision segmentation (time behind the subject) on real photos, and iCloud Shared Albums.
- Flow and weather animation frame rates on both iPad sizes.
- Swiping between saved faces alongside the shell's gestures.
- Nine real camera feeds on the Cameras face, and the live-versus-still switch as you approach.

### Assistant
- Speech recognition accuracy, end-of-speech timing, and the first-use speech model download.
- Wake phrase false triggers and power use.
- Saying "stop" over HomePad's own voice.
- Handoffs between speaking, listening and AirPlay music.
- Personal Voice, Apple Intelligence on supported iPads, and every cloud provider with a real key.
- AirPods nod and shake to confirm unlocking.

### Smart home
- HomeKit: permission, homes, writes, notifications, camera video, talk, snapshots, doorbell button events, and the Add Accessory sheet.
- Home Assistant: reconnects after Wi-Fi drops, HLS cameras, nine MJPEG feeds at once, and the themed Dashboards view.
- The doorbell popup with a real doorbell.

### Audio
- Multi-room AirPlay 2 with first and second generation HomePods, HomePod minis and Sonos.
- Apple Music following HomePad's AirPlay route. Requires turning on MusicKit for `com.ksha23.homepad` in the Developer portal first.
- Sleep sounds to AirPods and AirPlay, and their behavior when AirPods disconnect.
- Shazam from the shared microphone.
- Playing on a HomePod or Sonos through Music Assistant.

### Presence
- ARKit distance and gaze accuracy against a tape measure, in light and dark.
- The low-power depth scan noticing people walking past, and its power draw over a day.
- Face recognition thresholds for your household, and the liveness check against a printed photo and a phone screen.
- Enrollment and recognition on both camera layouts: the 12.9-inch (camera on the short edge) and the 11-inch M4 (camera on the long edge). The enrollment preview must show your face upright in both.
- Hand gestures at 1 to 2.5 m, and AirPods head gesture axes.
- Your real smoke alarm, CO alarm and doorbell sounds.
- 24 hours on the stand: heat and battery.

### Kitchen
- AlarmKit: timers ring with HomePad in the background or the iPad locked, and stop from the Lock Screen.
- Live Activities on iPad and on the iPhone companion.
- The timer chime while music plays to AirPlay speakers.
- Importing from real recipe sites.

### Calendar, weather and photos
- WeatherKit provisioning, with Open-Meteo taking over if it fails.
- The Calendars, Reminders, Photos and Location permission prompts.
- Shared iCloud calendars and albums, and assigning calendars to people.

### Camera Lab
- Preview orientation on a wall-mounted iPad.
- Security Camera motion thresholds in real rooms, its heat over hours, and the stream added to Home Assistant as an MJPEG camera.
- Barcode reading and the Groceries list.
- RoomPlan on an iPad Pro with LiDAR.
- Long-running timelapse.

### Across devices
- Pairing a HomePad and an iPhone with the 6-digit code, then intercom both ways.
- Handoff of a recipe to the iPhone or Mac.
- Family Board sync over iCloud.
- Siri phrases ("Ask HomePad ...", "Run Good Night with HomePad").
- The Send to HomePad share extension from Safari on iPhone.
- The Apple Watch app: install, microphone permission, intercom.
- Doorbell and smoke alerts on the iPhone.
- Two HomePads sharing their setup: after both update, the one installed first keeps its people, Home Screens and faces, and the other matches its people by name. On the second, a matched person is still recognized, and their Messages and alarms are still theirs. Settings > Devices & Sharing says "Synced with 1 HomePad" on both.
- A Home Screen edit, a widget added to a face, and a swipe to another face on one HomePad show on the other within a few seconds. A photo wallpaper stays where it was picked. Turn one HomePad off, edit on the other, turn it back on, and it catches up.

## Known limits (by design or by iOS)

- iOS does not let apps choose an AirPlay speaker silently, so HomePad shows the system picker.
- AirPlay 2 multi-room needs an audio mode without the microphone. While music plays to several speakers, the wake word pauses. Pull down from the top to talk instead, or turn on "Keep Microphone On" to use one speaker.
- Security Camera and every camera feature run only while HomePad is on screen. Guided Access keeps it there.
- Face recognition uses Vision feature prints, because iOS has no face identity API. It is good enough to switch Home Screens, but it is not Face ID. The Use Face ID fallback stays available.
- Pairing codes are 6 digits, valid for three minutes, and five wrong guesses close the window. Someone on the network guessing gets about a 1 in 200,000 chance, so open the pairing window only while you pair.
