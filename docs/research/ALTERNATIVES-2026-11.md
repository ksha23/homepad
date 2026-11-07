# What else does what HomePad does

Survey date: 2026-11-05. Every status below was checked on the product's own page, store listing or repository today. GitHub numbers come from the GitHub API today (stars, license, date of the last commit on the default branch). Searches used generic terms only.

## The short version

- **Name collision.** A public App Store app is already called **"HomePad - Smart Home Dashboard"** (Quentin Van Eylen, $8.99, version 4.2.2 this week). It is also the closest App Store match: HomeKit plus Home Assistant, watch-style faces, cameras, AirPlay 2 and Spotify. ([App Store](https://apps.apple.com/us/app/id6749515480))
- **The closest whole product is Apple HomeView.** It is real: $299, pre-orders since October 13, ships November 13, 2026, and it is not sold in the EU. It is a separate device, not something an iPad gets. ([Apple Newsroom](https://www.apple.com/newsroom/2026/10/meet-apple-homeview-a-new-way-to-enjoy-entertainment-and-manage-the-home/))
- **Nothing else I found puts per-person Home Screens chosen by on-device face recognition on an iPad.** HomeView and the Echo Show 8 and 11 do face-based personal screens, each on its own hardware. No iPad app found does it.
- **The closest open-source project is Kiosk Satellite** (Android, 2,493 stars, created July 2026). It has a voice satellite, Music Assistant audio, intercom, a family calendar and presence wake. It is source-available under a non-commercial license, not OSI open source. ([GitHub](https://github.com/jxlarrea/kiosk-satellite))
- **The free iPad baseline got much better this year.** The Home Assistant app gained a kiosk mode in 2026.4.0, rebuilt it in 2026.7.0, and now has camera-motion wake and remote commands. ([HA companion docs](https://companion.home-assistant.io/docs/integrations/ios-kiosk-mode))
- **HomeView set off a wave of copies within three weeks**: a native SwiftUI iPad dashboard, an Android photo-frame version, and Home Assistant card sets (section 1, entry 12).
- **Spotify on HomePods.** The workable way for an iPad app to reach HomePods through its own Spotify Connect controls is a bridge that turns each HomePod into a Connect device. Music Assistant's Spotify Connect plugin and SpotConnect both do this, each with caveats (section 5).

## 1. The closest alternatives

### 1. Apple HomeView (hardware, ships Nov 13, 2026)
- **Link and status:** [apple.com/homeview](https://www.apple.com/homeview/). Announced October 13, $299 for both the tabletop and wall models, sales start November 13. Not sold in the EU "as Siri AI is currently unavailable in iOS in the EU". ([Newsroom](https://www.apple.com/newsroom/2026/10/meet-apple-homeview-a-new-way-to-enjoy-entertainment-and-manage-the-home/))
- **What it does well:**
  - Purpose-built hardware: a 7-inch square display that dims to 0.3 nits, an A18, a four-mic array and Thread. ([Newsroom](https://www.apple.com/newsroom/2026/10/meet-apple-homeview-a-new-way-to-enjoy-entertainment-and-manage-the-home/))
  - Faces (Photos, Flow, Snoopy, Home Modular, Home Camera with nine feeds). ([MacRumors](https://www.macrumors.com/2026/10/13/apple-announces-homeview-smart-home-hub/))
  - Personal Home Screens for six people.
  - Messages and FaceTime as the recognized person, multiroom AirPlay, Intercom and Siri AI (beta).
- **How it compares:**
  - **Recognition model:** personal content needs the face, plus that person's paired iPhone on the same Wi-Fi and recently unlocked. ([apple.com](https://www.apple.com/homeview/))
  - **iPhone requirement:** in practice that means an Apple Intelligence iPhone (15 Pro or later). People without one are not recognized at all. ([9to5Mac](https://9to5mac.com/2026/10/13/heres-how-homeviews-facial-recognition-works/), [iPhone in Canada](https://www.iphoneincanada.ca/2026/10/13/apple-homeview-iphone-15-pro-face-recognition/)) HomePad recognizes faces without a phone.
  - **Apps and AI:** HomeView has no App Store. Its only assistant is Siri. It has no Home Assistant except through Home Assistant's HomeKit Bridge. ([9to5Mac](https://9to5mac.com/2026/10/13/will-homeview-support-third-party-apps-heres-what-apple-says/), [HA HomeKit Bridge](https://www.home-assistant.io/integrations/homekit/))
  - **Where HomePad leads:** any LLM, Home Assistant, the back cameras, availability in the EU, and no new hardware.
  - **Where HomeView leads:** FaceTime, video apps, far-field mics, and acting as a HomeKit home hub and Thread border router.
- **Spotify:**
  - HomeView mirrors CarPlay-enabled audio and video apps "from a nearby, paired iPhone" with "no modifications to the app required". Spotify was shown running this way. ([MacRumors, Nov 2](https://macrumors.com/2026/11/02/spotify-on-apple-homeview/))
  - What browse, search and Now Playing look like is not documented. ([Macworld](https://macworld.com/article/3261804/homeview-and-third-party-apps-what-works-what-doesnt-and-what-we-dont-know.html))
  - Whether Spotify can go on from HomeView to HomePods, and whether Siri can start Spotify, are both unverified.

### 2. Amazon Echo Show 8 and Echo Show 11 with Alexa+ (on sale)
- **Link and status:** $179.99 and $219.99, shipped November 12, 2025. ([iClarified](https://www.iclarified.com/98670/amazon-overhauls-echo-lineup-with-new-aipowered-smart-speakers-and-displays-video)) Alexa+ has been open to everyone in the US since February 4, 2026. It is free with Prime and $19.99 a month otherwise. ([MacRumors](https://www.macrumors.com/2026/02/04/AMAZON-ALEXA-PLUS-PRIME/))
- **What it does well:**
  - "Alexa recognizes when you walk up to the device, greets you, and shows you the information you want" (Visual ID).
  - A smart home dashboard with cameras and Home, Away and Night modes, a calendar widget, Drop In calls, and conversational music discovery. ([aboutamazon](https://www.aboutamazon.com/news/devices/getting-started-echo-show-8-11-alexa-plus-features))
  - Visual ID is opt-in, runs on the device, and shows that person's calendars and reminders. ([Amazon help](https://digprjsurvey.amazon.com/csad/help/node/GVPZZGGU8N6A9QJK))
  - The Echo Hub is the wall-panel version. Its June 2026 update added resizable widgets and Ring AI event summaries. ([Android Authority](https://www.androidauthority.com/new-echo-hub-interface-3676972/))
- **How it compares:**
  - It is the cheapest dedicated screen with face-based personal content and an LLM assistant.
  - It has no HomeKit, no AirPlay and no iMessage, and the assistant is Alexa+ only. Reviewers note it does not support Apple HomeKit. ([Expert Reviews](https://www.expertreviews.co.uk/technology/headphones-audio/amazon-echo-show-11-review))
  - Personalization changes content, not a whole separate Home Screen per person.
- **Spotify:**
  - Built in through Alexa, and Spotify Free has been allowed since 2019. ([TechCrunch](https://techcrunch.com/2019/11/20/spotifys-free-music-service-will-now-stream-on-alexa-devices-plus-bose-and-sonos-smart-speakers))
  - Echo devices act as Spotify Connect targets. ([Spotify Community](https://community.spotify.com/t5/Other-Podcasts-Partners-etc/Spotify-Connect-can-t-find-Alexa-devices/td-p/5606285))
  - Users call the on-screen Spotify UI "cut down". ([Spotify Community](https://community.spotify.com/t5/Other-Podcasts-Partners-etc/Echo-Show-15-Spotify-Controls/td-p/5387352))
  - There is no route to HomePods.

### 3. HomePad - Smart Home Dashboard, by Quentin Van Eylen (App Store)
- **Link and status:** [App Store](https://apps.apple.com/us/app/id6749515480). $8.99 one-time, version 4.2.2 two days ago, iPadOS 17.6 or later, 4.6 stars from 44 ratings.
- **What it does well:**
  - **Faces and photos:** watch-style faces with complications (4.2.0), and a Photo Frame Mode that shows weather and the current music.
  - **Smart home:** HomeKit and Home Assistant together.
  - **Cameras:** up to four feeds, with a doorbell popup. 4.2.2 moved Home Assistant camera live view to WebRTC, Ring included, "faster and with audio".
  - **Music and timers:** AirPlay 2 multiroom (2.6.1), plus timers and a calendar.
  - **HomePad Guard:** exposes an old iPad's camera, mic and siren as a HomeKit accessory.
- **How it compares:**
  - It is the same idea on the App Store under the same name.
  - Not listed: profiles, face recognition, an AI assistant, intercom, recipes or iMessage.
  - HomePad Guard is notable because HomePad's own Camera Lab notes say an iOS app cannot publish itself as a HomeKit camera. How Van Eylen does it is not stated and is worth a look.
- **Spotify:**
  - 3.7.0 added Spotify "built into the app: your catalogue, playlists and recommendations, with the same player as Apple Music". The Spotify app must be installed. ([App Store](https://apps.apple.com/us/app/id6749515480))
  - Needing the installed app points to Spotify's iOS SDK (App Remote), but the listing does not say so.
  - Whether Spotify can then go to AirPlay speakers is not stated.

### 4. Home Assistant Companion app in kiosk mode, plus the Lovelace wall-panel stack (free)
- **Link and status:**
  - [App Store](https://apps.apple.com/us/app/home-assistant/id1099568401) and [GitHub](https://github.com/home-assistant/iOS): 2,398 stars, Apache-2.0, last commit today.
  - Kiosk mode arrived as a Labs feature in 2026.4.0, was "Kiosk Mode Rebuilt" in 2026.7.0, and 2026.10.3 adds a Labs foundation for two-way audio. ([version history](https://apps.apple.com/us/app/home-assistant/id1099568401?see-all=version-history))
- **What it does well:**
  - **Screensaver:** Clock, Dim and Blank modes, with camera-motion wake.
  - **Remote commands:** `kiosk_show_camera`, brightness, volume and screensaver control.
  - **Lock:** Face ID protects the kiosk settings. ([kiosk docs](https://companion.home-assistant.io/docs/integrations/ios-kiosk-mode))
  - **Dashboards on top:** [Mushroom](https://github.com/piitaya/lovelace-mushroom) (5,243 stars, Apache-2.0, Oct 20), [Bubble Card](https://github.com/Clooos/Bubble-Card) (4,696, MIT, Oct 31), [WallPanel](https://github.com/j-a-n/lovelace-wallpanel) (887, GPL-3.0, Oct 24: photo and video screensaver from Immich or HA media, plus motion detection), [kiosk-mode](https://github.com/NemesisRE/kiosk-mode) (827, MIT, Nov 3) and [browser_mod](https://github.com/thomasloven/hass-browser_mod) (1,838, MIT, Oct 27).
  - **AI:** Assist can use Claude as a conversation agent that controls exposed devices. ([HA Anthropic](https://www.home-assistant.io/integrations/anthropic/))
- **How it compares:**
  - It is free with a huge card ecosystem, and HomePad already embeds these dashboards.
  - It is a web UI. It has no per-face profiles, no HomeKit of its own and no iMessage, and it takes assembly.
  - It works only in the foreground, and Guided Access is still needed, the same limit HomePad has.
  - Photo screensaver and person-detection wake are only proposed for the app itself. ([discussion #2403](https://github.com/orgs/home-assistant/discussions/2403))
- **Spotify:**
  - HA's Spotify integration uses the Web API with your own client ID and needs Premium.
  - "The Spotify API cannot initiate playback to a device not already known to the Spotify API." ([HA Spotify](https://www.home-assistant.io/integrations/spotify/))
  - Reaching HomePods goes through Music Assistant (section 5).

### 5. Kiosk Satellite (Android, source-available)
- **Link and status:** [GitHub](https://github.com/jxlarrea/kiosk-satellite). 2,493 stars, created July 2026, release 2026.11.6 on November 4. License is CC BY-NC-ND 4.0, free for personal non-commercial use.
- **What it does well:**
  - **Voice:** a Home Assistant Assist satellite with wake word, timers and announcements.
  - **Music:** synchronized Music Assistant audio through Sendspin. It is also an AirPlay receiver, and Now Playing shows lyrics and the queue.
  - **Screensavers and wake:** Immich photos, clocks, a weather mood and a night sky. On-device motion and face detection wakes it.
  - **Household:** intercom between kiosks, alarms with a sunrise that brightens the screen, and a family calendar with a color per person.
  - **Device control:** finger-count gestures that run actions, browser remote admin with live screenshots and fleet profiles, and an ESPHome connection that gives HA the screen controls and sensors. ([README](https://github.com/jxlarrea/kiosk-satellite), [Sendspin docs](https://kiosksatellite.com/docs/sendspin/))
- **How it compares:**
  - It has the closest feature set outside Apple and Amazon.
  - It runs on Android only and on Home Assistant only. It detects faces but does not recognize who they are, and it has no per-person screens.
  - It is ahead of HomePad on HA integration (a voice satellite, entities for its sensors) and on fleet admin.
- **Spotify:**
  - Through Music Assistant's Spotify provider, or by following a Spotify Connect receiver app on the same device. ([docs](https://kiosksatellite.com/docs/sendspin/))
  - It does not send to AirPlay speakers.

### 6. Dashboard: Smart Home & RTSP, by Jan Sindelar (App Store)
- **Link and status:** [App Store](https://apps.apple.com/us/app/dashboard-for-your-home/id6787462589). Free, Premium is $14.99 a year or $69.99 once, version 4.1 released yesterday. Covered by [9to5Mac](https://9to5mac.com/2026/08/14/dashboard-for-your-home/).
- **What it does well:**
  - **Screensaver:** clock, weather, calendar and a camera over photos (Premium).
  - **Wake:** on touch, front camera, a motion sensor or a doorbell ring.
  - **Cameras:** RTSP and ONVIF, plus HomeKit cameras with talk.
  - **Music:** Apple Music and podcasts on the panel or "through AirPlay to a HomePod".
  - **Alarm and lock:** a red alarm screen, and a code that locks settings.
- **How it compares:** It is a HomeKit-first wall panel with strong camera support. It has no Home Assistant beyond web tiles, no profiles, no AI and no Spotify.

### 7. Controller for HomeKit (App Store)
- **Link and status:** [App Store](https://apps.apple.com/us/app/controller-for-homekit/id1198176727). Free with subscriptions ($4.99 to $8.99 a month, or $179.99 lifetime), version 10.1.0 this week.
- **What it does well:**
  - [Dashboards](https://controllerforhomekit.com/features/dashboards) from 25+ tile types, chosen per home, per person and per device.
  - [Controller AI](https://controllerforhomekit.com/features/controller-ai) builds scenes, automations and dashboards from text.
  - [Controller Hub](https://controllerforhomekit.com/features/controller-hub) runs an iPad as an always-on automation host with a screensaver.
- **How it compares:** It is the most complete HomeKit power tool. It has no Home Assistant, no music, no face recognition and no named kiosk mode. Per-person dashboards rely on HomeKit users, not on faces.
- **Spotify:** none found.

### 8. Wallflower for HomeKit 3 (App Store)
- **Link and status:** [App Store](https://apps.apple.com/us/app/id1406806705). Free, Premium is $44.99, version 3.2.1 about October 31. Version 3 was a rewrite. ([ifun.de](https://www.ifun.de/wallflower-3-homekit-dashboard-blendet-unwichtiges-aus-289011/))
- **What it does well:**
  - A "Dynamic Dashboard" that shows only what is relevant now.
  - Cameras that appear on motion.
  - Optional approach detection, a wall clock and a family calendar.
  - "Lock a wall panel to its dashboard" (3.2).
- **How it compares:** It has the closest idea to HomePad's context-aware faces among HomeKit apps. It has no music, profiles, AI or Spotify.

### 9. iPad kiosk browsers for Home Assistant: DashPad, HA Dash, DimDash, UltraKiosk
- **DashPad:**
  - [App Store](https://apps.apple.com/us/app/id6766830819) at $3.99, with source on [GitHub](https://github.com/rafapages/DashPad) (43 stars, PolyForm Noncommercial, Oct 30).
  - Vision-based presence (body or face detection), with an idle screen of eight clock faces, photos or a web page.
- **HA Dash:** [App Store](https://apps.apple.com/app/id6759347912). Renders HA dashboards natively with kiosk mode and can publish the iPad camera as RTSP.
- **DimDash:** [App Store](https://apps.apple.com/us/app/dimdash/id6768683806). A dim overlay with proximity wake.
- **UltraKiosk:** [GitHub](https://github.com/mirkosertic/UltraKiosk), 11 stars, no license, August 2026. Open source, with face-detection wake, a Porcupine wake word, and an Assist voice satellite.
- **How they compare:** These are thin shells around the HA web UI. They are useful as references for presence wake on older iPads. None has Spotify.

### 10. MagicMirror² and Home Screens (open-source smart display software)
- **MagicMirror²:**
  - [GitHub](https://github.com/MagicMirrorOrg/MagicMirror): 24,181 stars, MIT, v2.38.0 on October 1, develop branch active today. It is the largest community.
  - It is a modular display for a Raspberry Pi with clock, calendar, weather and news modules, and thousands of third-party modules.
  - Face-recognition profile modules exist but are stale: [MMM-Face-Reco-DNN](https://github.com/nischi/MMM-Face-Reco-DNN), last commit November 2024, and [MMM-Face-Recognition-SMAI](https://github.com/EbenKouao/MMM-Face-Recognition-SMAI), June 2020.
- **Home Screens:**
  - [GitHub](https://github.com/home-screens/home-screens): 100 stars, MIT, last commit today.
  - A drag-and-drop editor, 46 modules and a hub Pi that drives several displays.
  - Modules can show or hide based on live values (weather, calendar, an HA sensor).
  - Kids' visual routines and timers, chores and rewards, a meal planner, and a phone remote.
- **How they compare:**
  - These are ambient boards more than hub controllers.
  - MagicMirror is mostly non-touch.
  - Neither does HomeKit, music playback or per-person screens out of the box.
- **Spotify:** [MMM-NowPlayingOnSpotify](https://github.com/raywo/MMM-NowPlayingOnSpotify) (212 stars) only displays what is playing, through the Web API, and needs a Premium developer app.

### 11. Family calendar displays: Skylight, Hearth, DAKboard (hardware)
- **Skylight:**
  - [Calendar 2](https://www.bestbuy.com/product/skylight-calendar-2-15-inch-touchscreen-smart-calendar-and-chore-chart-white/J3R845QLVJ) (15-inch, $299.99) and Cal Max (27-inch, $579.99).
  - Sidekick AI turns emails, flyers and handwritten recipes into events and plans meals with grocery lists. ([Skylight](https://myskylight.com/lp/sidekick/))
  - No music and no smart home. ([compare](https://myskylight.com/en-au/compare-calendars))
- **Hearth Display:** 27-inch, $699 plus a $9 a month membership. Routines, meal planning and recipes. ([Hearth](https://hearthdisplay.com/products/hearth-display))
- **DAKboard:**
  - Touch 22 is $599.95 and Touch 27 is $799.95. ([shop](https://shop.dakboard.com/collections/all-products))
  - Its Spotify block is Now Playing only. Controls need Premium, and the APIs "do not allow us to play your Music through a DAKboard Display". ([FAQ](https://dakboard.freshdesk.com/support/solutions/articles/35000227791-sonos-and-spotify-faq))
- **How they compare:** They are stronger than HomePad on family organizing: chores, meal plans, and AI intake of flyers. They have no smart home or music.

### 12. Projects inspired by HomeView (all created after October 13, 2026)
- **[HomeViewPad](https://github.com/kuscholar/HomeViewPad):**
  - 12 stars, MIT, Oct 24.
  - A native SwiftUI iPad dashboard for Apple Home, photos and a clock (iPadOS 17 or later, "early preview").
  - Its README says it "does not provide Siri, household recognition, integrated FaceTime, or Intercom". It is the nearest open-source analogue in Swift, but far smaller in scope.
- **[homeview](https://github.com/mcconnellj-Dev/homeview) (mcconnellj-Dev):**
  - 31 stars, MIT, Oct 14.
  - A Python server plus browser pages for cheap Android photo frames, with Standby faces, a night clock, a 7-day meal plan whose ingredients merge into one shopping list, and Sonos.
  - Spotify uses the Web API with Connect (Premium, your own keys). A QR code lets a phone on the Wi-Fi send a Spotify link to a room.
- **[NotHomeView](https://github.com/gamergodggpwnd/NotHomeView):**
  - 15 stars, MIT, Nov 2.
  - 22 HomeView-styled Home Assistant cards, glass and light themes, a Home Screen card and an Assistant popup. It needs WallPanel, card-mod and browser_mod.

### Also checked, in brief
- **[SmartHome Dashboard - HomeView](https://apps.apple.com/us/app/homeview-smarthome-dashboard/id6785599711)** (Remco Uitdenboogaart):
  - Version 3.1 this week. HomeKit plus Home Assistant (since 3.0), an Ambient mode, a doorbell popup and Sonos controls. It has no Spotify.
  - It shares the HomeView name.
- **[Panel - wall mounted widgets](https://apps.apple.com/us/app/id6761287923):** an iPad-only HomeKit wall app that lists "Apple Music and Spotify support built in". How it connects to Spotify is not stated. ([vendor](https://pitbullint.com/panel/))
- **[HomeDash](https://apps.apple.com/us/app/homedash/id1003033186):** an iPad HomeKit dashboard. 6.4.0 adds Apple Music to AirPlay speakers.
- **Google Nest Hub (2nd gen, 2021):** Google's only current display. Gemini for Home replaces Assistant. ([Google](https://blog.google/products-and-platforms/devices/google-nest/gemini-for-home-launch/)) The Pixel Tablet was discontinued in September 2026. ([9to5Google](https://9to5google.com/2026/09/09/google-pixel-tablet-discontinued/)) A "Google Home Display" is still only a name in app code. ([9to5Google](https://9to5google.com/2026/10/13/hey-google-where-is-the-next-nest-hub/)) Spotify works by Cast, and there is no AirPlay.
- **Android HA kiosks:**
  - [Dashie](https://github.com/jwlerch78/dashie-android-app): 182 stars, AGPL-3.0, a free Fully Kiosk alternative with voice and Music Assistant audio.
  - [Ava Pro](https://github.com/knoop7/Ava-Pro): 593 stars. It has local voiceprint recognition that tells family members apart, echo cancellation so the wake word works during music, and Pixel Shift.
  - [View Assist](https://github.com/dinki/View-Assist): 554 stars, Oct 27.
- **Other dashboards and tools:**
  - [Navet](https://github.com/navet-app/navet) (375 stars, AGPL-3.0): one room-first UI over Home Assistant, Homey or openHAB.
  - [NeonPlan 3D](https://github.com/Mastershort/neonplan3d) (1,047 stars, MIT, created Sept 2026): a drawn 3D floor plan for HA.
  - [Homey Dashboards](https://homey.app/dashboards/): tablet kiosk mode with media widgets.
  - The [openHAB app](https://apps.apple.com/us/app/openhab/id6505005945): gained a wall screensaver in 3.1.0.
  - Control4's new T5 panel wakes on approach and has a 4-mic intercom. ([Security Today](https://securitytoday.com/articles/2026/05/07/adi-launches-control4-t5-in-wall-touchscreen.aspx))

## 2. Feature comparison

Sources for each cell are the links in section 1. "Not found" means the product's pages do not mention it.

| Area | HomePad (yours) | Apple HomeView | Echo Show 8/11 | HomePad (Van Eylen) | HA app kiosk + Lovelace | Kiosk Satellite | Dashboard: Smart Home & RTSP |
|---|---|---|---|---|---|---|---|
| Platform and cost | iPad app, built from source, re-signed yearly | $299 device, ships Nov 13, not in EU | $179.99 or $219.99 device, Alexa+ free with Prime | iPad and iPhone app, $8.99 | iPad app, free | Android app, free for personal use | iPad and iPhone app, free plus Premium |
| Always-on faces with widgets | yes, 15 faces, widgets on any face | yes | yes, ambient screen with widgets | yes, faces with complications | partial, clock or dim screensaver, WallPanel adds photos | yes, photo, clock and weather screensavers | yes, Premium screensaver over photos |
| Burn-in drift | yes | not needed, LCD | not found | not found | partial, Blank mode for OLED | not found | not found |
| Red night mode | yes | yes, red tint below a light threshold | not found | not found | no | not found | not found |
| Layout changes as someone walks up | yes | yes (The Verge disputes it) | partial, visuals adapt to proximity | no | no, motion wake only | no, wake only | no, wake only |
| Per-person Home Screens | yes, up to 6 | yes, up to 6 | partial, personal content via Visual ID | no | partial, per HA login | partial, per-person calendar colors | no |
| On-device face recognition | yes, with depth liveness | yes, plus paired iPhone check | yes, Visual ID | no, Face ID only to confirm actions | no | no, detection only | no |
| Home Assistant | yes, plus HA dashboards | no, only via HA's HomeKit Bridge | no native support | yes | yes | yes | partial, web page tiles |
| HomeKit | yes | yes | no | yes | no | no | yes |
| Cameras and doorbell | yes, 9 feeds, doorbell screen | yes, 9 feeds | yes, dashboard cameras | yes, 4 feeds, WebRTC, doorbell popup | yes, camera popup command | yes | yes, RTSP, ONVIF, HomeKit talk |
| Apple Music | yes | yes | yes (retail listings) | yes | no | no | yes |
| AirPlay to HomePods | yes, through the system picker | yes, multiroom | no | yes, AirPlay 2 multiroom | partial, through Music Assistant | no, it is an AirPlay receiver | yes |
| Music Assistant | yes | no | no | not found | yes | yes, Sendspin | no |
| Spotify | partial, Web API plus Connect, no direct HomePod route | partial, mirrored from a nearby iPhone | yes, built in, Free allowed | yes, needs the Spotify app installed | partial, HA Spotify integration or Music Assistant | partial, through Music Assistant | no |
| iMessage | yes, through a Mac | yes | no | no | no | no | no |
| Calendar and reminders | yes | yes | yes | partial, calendar and lists | partial, HA calendars | partial, calendar | partial, calendar |
| Timers | yes | yes | yes (reviews) | yes | not built in | yes, voice timers and alarms | partial, device auto-off timers |
| Recipes and cooking mode | yes | partial, Start Cooking from Safari | partial, recipes "coming" | no | no | not found | no |
| Intercom | yes, push to talk | yes | yes, Drop In | no | partial, two-way audio in Labs | yes | no |
| LLM assistant | yes, any provider with fallback | Siri AI only, beta | Alexa+ only | no | partial, Assist with Claude and others | partial, as an Assist satellite | no |
| Control Center | yes | yes | not found | not found | no | not found | no |
| Phone, Watch and Mac companions | yes | partial, iPhone required, Siri chats sync | not checked | partial, same app on iPhone and Mac | yes, HA app on iPhone, Watch and Mac | partial, browser remote admin | partial, iPhone app with iCloud sync |
| Kiosk lock | partial, Guided Access or Single App Mode | yes, dedicated device | yes, dedicated device | not found | partial, Guided Access still needed | yes, PIN kiosk and home launcher | partial, code locks settings |

## 3. Where HomePad is ahead, and where it is behind

### Ahead
- **Per-person Home Screens chosen by face on an iPad.** No App Store app or open-source project found does this. Only HomeView and the Echo Show do it, on their own hardware. HomePad also needs no paired iPhone, unlike HomeView, which needs an Apple Intelligence iPhone per person.
- **Recognition in the dark.** Presence and recognition use the TrueDepth infrared camera, with a depth liveness check. The kiosk apps and Kiosk Satellite only detect faces or motion, which wakes the screen but does not identify anyone.
- **HomeKit and Home Assistant in one native UI, with HA dashboards embedded.** Only Van Eylen's HomePad and Remco's HomeView app also combine both natively. Wallflower reaches HA only through bridges.
- **Any LLM, with screen awareness, tool use and fallback.** HomeView is Siri-only, Echo is Alexa+-only and Controller AI is only for building automations. HA Assist can use Claude but runs inside the HA web UI.
- **iMessage as each person's own Apple ID.** Only HomeView has this.
- **Spotify and Music Assistant in the same Music app.** Echo has Spotify but no AirPlay. Van Eylen has Spotify but no Music Assistant. Kiosk Satellite has Music Assistant but no Apple Music.
- **Back-camera tools nothing else has:** a LiDAR floor plan, a recipe and grocery scanner, and the iPad as a security camera for HA. The closest relatives are NeonPlan 3D (a drawn plan, not a scan) and HomePad Guard (camera and siren as a HomeKit accessory).
- **No new hardware and works in the EU,** where HomeView is not sold.

### Behind, or missing things others have
- **Distribution.** HomePad is dev-signed and has to be rebuilt yearly. The name is already taken on the App Store by Van Eylen's app, and "HomeView" is in another app's name.
- **No FaceTime or calls.** HomeView has FaceTime with Center Stage, and Echo has calls and Drop In.
- **No video or podcast apps.** HomeView runs CarPlay audio and video apps from the iPhone. Sindelar's Dashboard plays podcasts. HomePad only reaches podcasts or audiobooks through Music Assistant.
- **Not part of Home Assistant itself.**
  - Kiosk Satellite (ESPHome entities, Assist satellite), the HA app (`kiosk_*` commands, kiosk sensors), Dashie and Ava Pro all give HA the screen as a device. HA can then dim it, wake it, read its sensors and speak through it.
  - HomePad publishes only its camera stream and a webhook.
- **No fleet admin.** Kiosk Satellite shows live screenshots and logs and pushes config profiles to every kiosk. HomePad has nothing like it for managing several HomePads.
- **Not a home hub.** Apple's home hub page lists only HomePod and Apple TV ([Apple](https://support.apple.com/en-us/102557)), so HomeKit automations still need one. HomeView itself has Thread.
- **No Spotify path to HomePods inside the app** (section 5).
- **Camera transport.** Van Eylen's app now uses WebRTC for HA cameras, Ring included, with audio. HomePad's faces use snapshots refreshed every few seconds.
- **Family organizing.** HomePad has no chores, rewards, kids' routines or weekly meal plan (Home Screens, Skylight, Hearth). It cannot turn a flyer or email into events (Skylight Sidekick).

## 4. Ideas worth borrowing

1. **Make HomePods into Spotify Connect devices so HomePad's existing Web API path reaches them.** Source: [Music Assistant Spotify Connect plugin](https://www.music-assistant.io/plugins/spotify-connect/), or [SpotConnect](https://github.com/philippe44/SpotConnect). Details and caveats are in section 5.
2. **Be a Home Assistant device, not only a client.**
   - Publish presence, distance, room light, sound alerts, the current face and brightness as HA entities.
   - Accept commands to show a camera, change brightness, sleep or wake.
   - Source: Kiosk Satellite's [ESPHome connection](https://kiosksatellite.com/docs/esphome/) and the HA app's [kiosk commands](https://companion.home-assistant.io/docs/integrations/ios-kiosk-mode).
3. **Act as a Home Assistant Assist satellite** so HA's own voice pipelines, timers and announcements target the iPad. Source: [Kiosk Satellite](https://github.com/jxlarrea/kiosk-satellite), [UltraKiosk](https://github.com/mirkosertic/UltraKiosk), [Voice Satellite card](https://github.com/jxlarrea/voice-satellite-card-integration) (917 stars).
4. **Join Music Assistant as a Sendspin player.** The iPad could then play in sync with other rooms instead of only controlling them. Source: [Kiosk Satellite Sendspin](https://kiosksatellite.com/docs/sendspin/), [Dashie](https://github.com/jwlerch78/dashie-android-app).
5. **Remote admin for several HomePads:** live screenshot, logs, settings backup and shared profiles from a browser or the Mac companion. Source: [Kiosk Satellite](https://github.com/jxlarrea/kiosk-satellite).
6. **Recognize who is speaking.** A voiceprint picks the person when the face is out of view, and echo cancellation keeps "Hey HomePad" working while music plays. Source: [Ava Pro](https://github.com/knoop7/Ava-Pro). HomeView also matches voices to people per [Wired](https://www.wired.com/story/apple-homeview-smart-display/).
7. **Sunrise alarm.** The screen brightens before the alarm rings, and the alarm shows on the clock face with Snooze and Stop. Source: [Kiosk Satellite](https://github.com/jxlarrea/kiosk-satellite).
8. **More hand gestures.** Holding up one to five fingers runs a chosen HA action or opens a camera. This extends HomePad's open palm. Source: [Kiosk Satellite gestures](https://kiosksatellite.com/docs/gestures/#show-fingers).
9. **Widgets with conditions.** Show or hide a widget by live data ("rain map only when rain is forecast", "only when busy") and by schedule. Source: [Home Screens](https://github.com/home-screens/home-screens). Wallflower 3's "Dynamic Dashboard" is the HomeKit version. ([ifun.de](https://www.ifun.de/wallflower-3-homekit-dashboard-blendet-unwichtiges-aus-289011/))
10. **A weekly meal plan that merges every planned recipe's ingredients into Groceries.** Source: [homeview by mcconnellj-Dev](https://github.com/mcconnellj-Dev/homeview), [Skylight Sidekick](https://myskylight.com/lp/sidekick/).
11. **Point the back camera at a flyer, invitation or school letter and get calendar events.** This extends the existing recipe scanner. Source: [Skylight Sidekick](https://myskylight.com/lp/sidekick/).
12. **A QR code for guests.** A phone on the Wi-Fi can send a song, link or photo to this room without pairing. Source: [homeview by mcconnellj-Dev](https://github.com/mcconnellj-Dev/homeview).
13. **WebRTC live view for Home Assistant cameras, with audio,** Ring included. Source: [HomePad by Van Eylen 4.2.2](https://apps.apple.com/us/app/id6749515480).
14. **Check how "HomePad Guard" exposes an iPad camera, mic and siren as a HomeKit accessory.** It contradicts the Camera Lab note that this is impossible. Source: [HomePad by Van Eylen](https://apps.apple.com/us/app/id6749515480).
15. **Immich as a photo source for the Photos face.** Source: [WallPanel](https://github.com/j-a-n/lovelace-wallpanel), [Kiosk Satellite](https://github.com/jxlarrea/kiosk-satellite).
16. **Kids' visual routines and a chore chart with rewards,** which take over the screen step by step with a celebration at the end. Source: [Home Screens](https://github.com/home-screens/home-screens).
17. **Camera event summaries and footage search by the assistant.** Source: Alexa+ with Ring ([aboutamazon](https://www.aboutamazon.com/news/devices/getting-started-echo-show-8-11-alexa-plus-features)). HomePad's Camera Lab already keeps a ring buffer of motion snapshots the LLM could summarize.

## 5. Spotify: how each approach works

| Approach | Who uses it | Browse, search, Now Playing | Reaches HomePods? | Limits |
|---|---|---|---|---|
| Web API with Spotify Connect | HomePad, [HA Spotify](https://www.home-assistant.io/integrations/spotify/), [homeview (mcconnellj)](https://github.com/mcconnellj-Dev/homeview), [MMM-NowPlayingOnSpotify](https://github.com/raywo/MMM-NowPlayingOnSpotify) (display only), [DAKboard](https://dakboard.freshdesk.com/support/solutions/articles/35000227791-sonos-and-spotify-faq) (display only) | Your own UI from Web API data. Now Playing comes from polling `/me/player`. | Only if something makes the HomePod a Connect device (below) | Premium for the app owner and for player calls. Five users per new Client ID. Search capped at 10. Browse categories, new releases and artist top tracks removed. Playlist items only for owned or collaborative playlists. ([migration guide](https://developer.spotify.com/documentation/web-api/tutorials/february-2026-migration-guide)) Refresh tokens end after six months. |
| Drive the installed Spotify app | HomePad by Van Eylen (needs the Spotify app, method not stated), the [Spotify iOS SDK](https://github.com/spotify/ios-sdk) (v5.0.1, August 2025, last commit June 2026) | Van Eylen claims catalogue, playlists and recommendations "with the same player as Apple Music" | The audio plays on the iPad, so only by the person picking AirPlay in Spotify or Control Center. Not automatic. | Spotify app installed and running, Premium for on-demand playback, closed binary |
| Web Playback SDK in a web view | No hub app found | Your own UI, and the iPad becomes a Connect device | Possibly. The audio is the app's own, so the system route picker could send it to a HomePod. Inference, untested. | Lists iOS as supported, needs Premium, and on iOS "playback does not start automatically after transfering playback" ([docs](https://developer.spotify.com/documentation/web-playback-sdk)) |
| Server streams Spotify to speakers | [Music Assistant Spotify provider](https://www.music-assistant.io/music-providers/spotify/) (HomePad already uses it through HA), Kiosk Satellite, Dashie, [OwnTone](https://owntone.github.io/owntone-server/integrations/spotify/) | Music Assistant's library and search, shown in the client's UI | Yes, through Music Assistant's [AirPlay provider](https://www.music-assistant.io/player-support/airplay/), which supports HomePods after PIN pairing | Premium. The librespot engine is "intended for Premium accounts created before December 2024". Soloist needs a personal API key, and "Spotify's terms do not clearly allow using Soloist this way". OwnTone's Spotify does not work for accounts made after about November 2025. Music Assistant's AirPlay 2 "has not yet been extensively tested", and PTP timing is unsupported. |
| Bridge that makes AirPlay speakers Connect devices | [Music Assistant Spotify Connect plugin](https://www.music-assistant.io/plugins/spotify-connect/), [SpotConnect spotraop](https://github.com/philippe44/SpotConnect) (158 stars, 0.20.11 on Oct 3) | The Spotify app's own device list, or any Web API client once the device is registered | Yes, by design | **Music Assistant plugin:** "any MA player (or group of players) appears in the Spotify app's device list". Its page does not say whether these devices appear in the Web API device list. **SpotConnect:** in ZeroConf mode its devices do not appear to Web API apps until reusable credentials are stored with `-J`. Issue [#71](https://github.com/philippe44/SpotConnect/issues/71), "No sound via Apple HomePods", has been open since August 2026. |
| Official headless client on a computer | [Spotify Soloist](https://developer.spotify.com/blog/2026-08-13-introducing-spotify-soloist), released August 13, 2026, desktop builds in October | Shows "in the Spotify app like any other device". It has a local WebSocket API for status and control. | Indirectly. On a Mac it plays to Core Audio's default output, which can be a HomePod. One output at a time, with no device option on macOS. ([overview](https://developer.spotify.com/documentation/soloist/concepts/overview)) | Premium to set up, then Free or Premium can connect. Whether it appears in the Web API device list is not documented. |
| Device with its own Spotify client or Cast | Echo Show and Echo Hub, Nest Hub, Pixel Tablet (discontinued), Control4, Savant, Crestron, Loxone | The device's own UI. Echo's is "cut down". | No | Echo allows Free. Google says Cast needs a subscription. ([Google](https://support.google.com/googlenest/answer/7181830?hl=en)) |
| App mirrored from the iPhone | Apple HomeView ([MacRumors](https://macrumors.com/2026/11/02/spotify-on-apple-homeview/)) | Probably Spotify's CarPlay interface. Unconfirmed. ([Macworld](https://macworld.com/article/3261804/homeview-and-third-party-apps-what-works-what-doesnt-and-what-we-dont-know.html)) | Not documented | Needs a nearby paired iPhone |
| Spotify on the HomePod itself | Nobody | n/a | No. HomePod still has no native Spotify. ([Spotify Community](https://community.spotify.com/t5/Live-Ideas/iOS-Implement-Native-HomePod-Support/idi-p/4985214)) | n/a |

### What gets Spotify onto HomePods from an iPad app
1. **Music Assistant's Spotify provider, already in HomePad.** Playing a Spotify item through `music_assistant.play_media` on a HomePod player works today. It needs Premium. A Spotify account made after December 2024 needs the Soloist engine, whose terms are unclear.
2. **Bridge each HomePod into a Connect device, then use HomePad's own Spotify screens.**
   - Music Assistant's Spotify Connect plugin is the better-maintained option.
   - SpotConnect's spotraop also runs on macOS arm64, so it could live on the Messages Mac hub. Its HomePod no-sound issue is open, though.
   - Test first whether the bridged devices show up in `GET /me/player/devices`. SpotConnect says they do only after credentials are stored. Music Assistant does not document it.
3. **The Mac hub as the speaker.** Run Spotify Soloist or the Spotify desktop app on the Mac, which shows up as a Connect device. Set the Mac's sound output to the HomePod or stereo pair. This gives one AirPlay target, with no multiroom.
4. **The iPad as the player.** Use the Spotify app (Open Spotify Here) or the Web Playback SDK, then route the iPad's audio with the system AirPlay picker. This needs a tap each time, since iOS will not switch speakers silently.
- **Apple TV route (not recommended):** Spotify's redesigned Apple TV app supports Connect ([Engadget, Oct 2025](https://www.engadget.com/entertainment/music/spotifys-redesigned-tvos-app-brings-podcast-and-music-videos-to-apple-tv-143512134.html)). Users report silence when the Apple TV's audio output is a HomePod. ([Spotify Community](https://community.spotify.com/t5/Other-Podcasts-Partners-etc/No-audio-on-Apple-TV-4K-with-HomePod-s-Connected/td-p/5070146))
- **Not affected:** the February 2026 change removed `product` from `GET /me`. HomePad's "needs Premium" state comes from the 403 `PREMIUM_REQUIRED` reason, so it still works.

## 6. Ruled out

| Project | Reason |
|---|---|
| TileBoard | Original repo returns 404, and its [ioBroker adapter](https://github.com/ioBroker/ioBroker.tileboard) is archived |
| [ha-fusion](https://github.com/matt8707/ha-fusion) (3,021 stars) | README says "no longer actively maintained". The fork [knowald/ha-fusion](https://github.com/knowald/ha-fusion) has 82 stars. |
| WallPanel for Android | [TheTimeWalker fork](https://github.com/TheTimeWalker/wallpanel-android) archived May 2025. The original's last commit was 2021. Android only. |
| [WallPanel for iOS](https://github.com/WallPanel-Project/wallpanel-ios) | Last push 2018 |
| [maykar/kiosk-mode](https://github.com/maykar/kiosk-mode) | Archived 2022, replaced by NemesisRE/kiosk-mode |
| [Fully Kiosk Browser](https://www.fully-kiosk.com/) | Android only |
| Kiosk Pro Plus | A general retail kiosk browser, last updated March 2025 ([App Store](https://apps.apple.com/us/app/kiosk-pro-plus/id445701154)) |
| Kiosk for Home Assistant (Bruno Goncalves) | Removed from the US store ([AppGoblin](https://appgoblin.info/apps/6758617177)) |
| The Home Remote, HomeDeck | App Store listing returned 404 or could not be found. Not verified. |
| [HomeView Pro](https://apps.apple.com/us/app/-/id1174308047) (Frank Zhang) | IP camera viewer, last updated 2017 |
| StandBy Hub, StandBy Clock | iPhone StandBy widget apps, not hubs |
| Home+ 6, Eve, HomeWatch | Controllers with no wall or kiosk mode ([Home+](https://apps.apple.com/us/app/home-6/id995994352), [Eve](https://apps.apple.com/us/app/eve-for-matter-homekit/id917695792), [HomeWatch](https://apps.apple.com/us/app/homewatch/id1622801480)) |
| Cozi, FamilyWall, Skylight and Hearth companion apps | Organizers or companions to hardware, no display mode |
| AppDaemon HADashboard, openHAB HABPanel, ioBroker VIS 2 | Still alive ([AppDaemon](https://github.com/AppDaemon/appdaemon), [HABPanel docs](https://www.openhab.org/docs/ui/habpanel/habpanel.html), [VIS 2](https://github.com/ioBroker/ioBroker.vis-2)) but dated web dashboards for their own platforms, surpassed by the options above |
| MagicMirror face-recognition modules | Stale: last commits 2020 and 2024 |
| [MirrorMate](https://github.com/orangekame3/mirrormate) | A voice-first AI mirror, not a hub. Last commit January 2026. |
| E-ink boards ([TRMNL](https://github.com/usetrmnl/trmnl-firmware), [timeframe](https://github.com/timeframe/ha-addon), [Kindle screensaver](https://github.com/sibbl/hass-lovelace-kindle-screensaver)) | Not interactive |
| ESP32 panels ([openHASP](https://github.com/HASwitchPlate/openHASP), [NSPanel Lovelace UI](https://github.com/joBr99/nspanel-lovelace-ui), [HomeTiles](https://github.com/GalusPeres/HomeTiles)) | Small microcontroller screens for controls only |
| Firmware that repurposes old displays ([techo5](https://github.com/HuskerMinion/techo5) for Echo Show 5, [LANovo](https://github.com/ygelfand/LANovo) for Lenovo, [portal-launcher](https://github.com/iblur01/portal-launcher) for Meta Portal) | Hardware hacks for HA, not app-level competitors |
| Native HA iPhone apps ([IntelliNest](https://github.com/TobiasLaross/IntelliNest), [Hassonic](https://github.com/JeffSteinbok/Hassonic-iOS)) | Personal iPhone apps, no wall mode |
| Family web apps ([HomeHub](https://github.com/surajverma/homehub), [Prism](https://github.com/sandydargoport/prism), DinkyDash, Beacon) | Organizers. HomeHub has 1,252 stars but no display or smart-home role. Prism has wall layouts but no hub control. |
| Meta Portal | Consumer line discontinued 2022 ([Engadget](https://www.engadget.com/meta-discontinuing-portal-devices-consumers-050424665.html)) |
| Lenovo Smart Displays | Google ended updates in 2023 ([Android Authority](https://www.androidauthority.com/google-software-support-third-party-smart-displays-3310975)) |
| Pixel Tablet, Nest Hub Max | Pixel Tablet discontinued September 2026. Nest Hub Max reportedly no longer sold by Google (not confirmed on the Google Store). |
| Samsung, Nabu Casa, Ubiquiti | No home display product ([HA hardware](https://www.home-assistant.io/hardware/)). UniFi Connect Display is signage. |
| Aqara Panel Hub S1 Plus, SwitchBot Hub 3 | In-wall controllers with no music, profiles or assistant ([T3](https://www.t3.com/home-living/smart-home/aqara-panel-hub-s1-plus-review-premium-smart-control-for-the-aqara-ecosystem), [SwitchBot](https://www.switch-bot.com/products/switchbot-hub-3)) |
| Control4, Savant, Josh.ai, Crestron, Loxone, Brilliant | Dealer-installed whole-home systems with their own audio, a different market. Brilliant went under in 2024 and returned as Brilliant NextGen for builders ([CE Pro](https://www.cepro.com/news/brilliant-is-back-from-the-dead-with-a-new-focus-on-professional-builders-mdu-management/141327)). |
| Homelab dashboards (for example [homelab-hub](https://github.com/RaidOwl/homelab-hub)) | Server dashboards, not home hubs |

## Could not verify
- How Van Eylen's HomePad plays Spotify (App Remote is a guess), and how Panel connects to Spotify.
- How HomeView's Spotify screens look, whether Siri can start Spotify on HomeView, and whether HomeView can send it on to HomePods.
- Whether devices from Music Assistant's Spotify Connect plugin or from Spotify Soloist appear in the Web API device list.
- How many people Echo Show Visual ID supports, Echo Show's red or night mode, and its companion features.
- Whether the Web Playback SDK in a WKWebView can be routed to a HomePod with the system picker.
