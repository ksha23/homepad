# HomePadAudio

Music, speakers and Now Playing for HomePad. It installs `AudioMediaService` as `services.media`.

HomePad does not build its own music service. It reuses existing ones and lets the person pick:

- **This iPad**: Apple Music through MusicKit and the synced library through MediaPlayer, played by Apple's own players and sent to speakers with the system AirPlay picker.
- **Music Assistant**: Music Assistant inside Home Assistant, reached only through `services.smartHome`. It searches Apple Music, Spotify, radio and the library, and plays on HomePods, Sonos and groups by itself, so the iPad stays free.
- **Spotify** (optional, off by default): the Spotify app on this iPad plays, to the speakers picked in AirPlay, and HomePad browses, searches and controls it through Spotify's Web API. Any Spotify Connect device can play instead. Each person can link their own account. See [Spotify](#spotify).

## Music source

A curated choice of up to three, at the top of the Music app and in Settings > Audio & AirPlay.

- The default is This iPad. Music Assistant or Spotify becomes the source only when the person picks it.
- The choice is remembered for the recognized member (in `HouseholdMember.preferences["audio.musicSource"]`), or for the household when nobody is recognized (`audio.musicSource`).
- When Home Assistant has no running Music Assistant, or Spotify is turned off or has no account for whoever uses HomePad, that choice hides and HomePad plays on this iPad.

## Up Next and each person's queue

- **Up Next** (the list button in Now Playing) shows what plays now, where it came from ("Playing from Night Signals"), shuffle and repeat, and the next 100 songs. On this iPad the songs reorder with their handles, remove with the minus buttons, and Clear empties the list. `UpNextEdit` does the arithmetic on plain arrays (tested), and `AppleMusicPlayer+Queue.swift` applies it to the songs after the current one only, through `ApplicationMusicPlayer.Queue.entries`, so the song that plays is never touched.
- **Play Next and Play Later** are on every album, playlist and song: a tile's touch and hold menu, the More button on song rows, and the More menu of a page. They use `queue.insert(_:position:)` (`.afterCurrentEntry`, `.tail`). With nothing queued they play at once, as in the Music app. Music Assistant items use `play_media`'s `enqueue` (`next`, `add`), and Spotify tracks use `POST /me/player/queue`.
- **Stations.** MusicKit ignores songs queued together with a station (learned on a device), so while a station plays, or the song resumed ahead of one (`stationAfterSong`), Play Next and Play Later are hidden and Up Next says the station chooses its songs.
- **Shuffle and repeat** sit beside the transport in Now Playing and in Up Next. Play on a page plays in order and Shuffle shuffles, like the Music app. They stay in place, dimmed, for radio and stations, so nothing moves between tracks.
- **Per person.** Each member's queue, place, shuffle, repeat and Recently Played are saved on this iPad under `audio.music.member.<member UUID>` (`MemberMusicState`), and guests share `audio.music.member.household`. When HomePad recognizes another person while nothing plays here, that person's queue and place come back, paused (`AppleMusicPlayer.holdSavedPlace`): music never starts on its own. Music that plays keeps playing for whoever started it, and new music started by someone else becomes their queue after the replaced one is saved for its owner. `audio.music.queueOwner` says whose queue the player holds, so a restart files the saved place (`audio.appleMusic.resume`) under the right person. Only Apple Music moves between people. Radio, sleep sounds and the synced library stay as they are.
- **Saving an edited queue.** MusicKit's queue does not outlive HomePad. An album, playlist or station that nobody edited comes back from its ID. Once Up Next was edited, the place is saved as the song list from the current song on (`.songs`, at most 150), and `AppleMusicLookup.songs` finds catalog songs in the catalog and library songs in the library.
- **Recently Played** on Listen Now starts with what the person using HomePad played here (`noteRecent`), then the Apple Music account's history, which everyone on the iPad shares. A recognized member who linked their own Apple Music sees their own account's history instead (see [Each person's own Apple Music](#each-persons-own-apple-music)).

## Library and pages

- **Library** (a Music section) lists playlists, albums, artists and songs, with chips. This iPad reads the Apple Music library of the account signed in on the iPad (`AppleMusicLibrary`, `MusicLibraryRequest`), and falls back to the synced library through MediaPlayer when MusicKit cannot read it. MusicKit has one library per iPad, so a member who has not linked their own Apple Music sees the iPad's. A recognized member who has sees "Kyle's Library" (see [Each person's own Apple Music](#each-persons-own-apple-music)). Music Assistant lists its library by name (`get_library`), and Spotify the saved music of the signed-in account.
- **Pages.** Albums, playlists and artists open a page in the content column, with a back button before the title (`MusicPageStack`, `MusicDetailView`): artwork, Play, Shuffle, a More menu (Play Next, Play Later, Add to Library for catalog items, Show Artist), the track list with durations, and an artist's albums, singles and similar artists. A library artist gets the catalog artist of the same name for its top songs. Search's Artists, Albums and Playlists open pages too, and its Top Result opens on a tap and plays with Play. Listen Now's tiles play on a tap, made for a quick tap from across the room, and offer their page in their menu.
- **Sleep timer** for what this iPad plays is a menu in Now Playing's header, the same timer Sleep Sounds uses.

## Each person's own Apple Music

The iPad plays Apple Music only through its own Apple Account (Settings > Media & Purchases), and no app can sign in another one. What a member can bring is a Music User Token, made by MusicKit on their own iPhone and handed to this HomePad over the encrypted peer link (the Connect README has the handoff). With it the HomePad reads their library, recently played and recommendations from the Apple Music API. Playback stays with the iPad's account.

### What shows

- **Whose music.** On This iPad, while a member is recognized (face, Face ID or Use Personal Device) and their Apple Music is linked, Listen Now and the Library show theirs, under a header with their avatar: "Kyle's Apple Music" on Listen Now and "Kyle's Library" in the Library. Picking someone in People is not enough. With nobody recognized, or a member who has not linked, Music shows the iPad's own, as before (`MemberAppleMusic.shownMember`, tested). Music Assistant and Spotify are not affected.
- **Listen Now**: Recently Played (what they played on HomePad, then their account's own history from any device), up to four of Apple Music's recommendation groups for them ("Made for You", "New Releases for You"), Your Playlists and Recently Added (their library's albums by date added). Radio picks follow, as before.
- **Library**: their playlists, albums, artists and songs, up to 300 of each. Albums and artists open the catalog page they match. Their own playlists open a page of their songs (`MusicPage.memberPlaylist`). A playlist they added from Apple Music opens its catalog page.
- **Search** searches the catalog through the iPad, as before.
- The header says plainly where it comes from and that songs play through this iPad's Apple Music, so they count toward its account.

### What plays

- Every item plays by its catalog ID, looked up again on this iPad (`MemberCatalog`), in the iPad account's country, through the same `ApplicationMusicPlayer` and AirPlay route as everything else. Plays count toward the iPad's account: its history, its recommendations and its play counts, not the member's.
- The playable rule (`MemberMusicItem.unavailableReason`, tested): a song, album or artist needs a catalog match. A song they uploaded (or an album of uploads) has none, so it shows dimmed with "Not in Apple Music" and takes no taps (`View.unavailable`). Their own playlists always open and play the catalog songs in them, in order, as "Playing from Road Trip". The page says how many of its songs cannot play. A personal station ("ra.u-" IDs, such as "Kyle's Station") is made for its owner's account, so it shows dimmed with "Only on its owner's account".
- An item the iPad's country does not have says "isn't available to the Apple Music account on this iPad" under the header.
- Queues, places, shuffle, repeat and HomePad's Recently Played stay per person (`MemberMusicState`), since what plays is catalog music. Their own playlists go in Recently Played as `RecentMusicItem.Source.memberLibrary`, which plays and opens only while they are recognized.
- **The assistant.** "Play my playlist Road Trip", "play my Road Trip playlist" or "the playlist Road Trip" (`play_music`) looks in the recognized member's own playlists first, when the request says "my" or "playlist" (`MemberLibraryMatch`, tested: the same name, then a name starting with it, then one containing it, ignoring case and accents). Anything else searches the catalog as before.

### Reading it

- `AppleMusicAPI` calls `api.music.apple.com` with this HomePad's own developer token (`DefaultMusicTokenProvider.developerToken(options:)`, which MusicKit makes for HomePad's App ID through the MusicKit App Service) in `Authorization: Bearer`, and the member's token in `Music-User-Token`. MusicKit's own requests would add the iPad account's token, so they cannot read anyone else's library.
- Endpoints: `/v1/me/storefront`, `/v1/me/library/{playlists,albums,artists,songs}?include=catalog&limit=100` (following `next`), `/v1/me/recent/played?limit=10&types=albums,library-albums,playlists,library-playlists,stations` (two pages), `/v1/me/recommendations` and `/v1/me/library/playlists/{id}/tracks?include=catalog`. The catalog match comes from the `catalog` relationship, or `playParams.catalogId` for songs and `playParams.globalId` for public playlists.
- A 401 is tried once more with a fresh developer token (`.ignoreCache`). A second 401, or a 403, means the member's token stopped working: their sign-in token ran out, they turned off HomePad's access, or their subscription lapsed. HomePad then tells `services.memberMusic.tokenRejected`, which forgets the token and asks their phone for a new one, and keeps showing the saved library with "needs a new sign-in token" in the header.
- Nothing logs a request, a reply or a token.

### Kept on this iPad

- The token lives in the Connect module's Keychain item, per member (see the Connect README).
- The listings live in each member's encrypted cache (`MemberMusicCache`), the same way Messages keeps conversations: a random 256-bit key per member in this iPad's Keychain (`com.ksha23.homepad.music.cache`, this device only, never iCloud Keychain or a backup restored elsewhere) and one AES-GCM sealed file in `Application Support/HomePadAudio/MemberMusic`. It holds names, artwork addresses, IDs and the songs of the 20 playlists opened last, never the token. Music opens at once from it and refreshes behind it.
- It is deleted, key and file, when the member's Apple Music is unlinked (they turned it off, their phone was unlinked, the token's phone left) or they leave the household. Writes and deletes go through one queue, so no write lands after a delete.
- While the member is not recognized, nothing of theirs is held in memory.

## Spotify

The Spotify app on this iPad plays, and HomePad browses, searches, shows Now Playing and controls it through Spotify's Web API. Spotify's sound follows the iPad's AirPlay, so it reaches the HomePods. Any other Spotify Connect device can be picked instead. The Spotify app has to be installed.

Each household member can link their own Spotify account, and the household can link one for guests. While HomePad recognizes a member, Spotify uses theirs. See [Each person's own account](#each-persons-own-account) and [Where it plays](#where-it-plays).

### Why this path

Neither Spotify nor the Music app can be embedded: iOS has no public API to host another app's interface. Two ways drive the installed Spotify app.

- **The Web API, with the Spotify app here as the Connect device (built).** Authorization Code with PKCE, which needs no client secret, through `ASWebAuthenticationSession` (ephemeral, so no Spotify cookie stays in Safari on a shared iPad). It reads what plays (`GET /me/player`, polled) and the devices, plays a URI on a device (`PUT /me/player/play?device_id=`), moves playback, pauses, skips, seeks, shuffles, repeats and queues. It also gives search, the library and pages. Player calls need Premium. ([code-pkce-flow](https://developer.spotify.com/documentation/web-api/tutorials/code-pkce-flow), [start playback](https://developer.spotify.com/documentation/web-api/reference/start-a-users-playback))
- **Spotify's iOS SDK, App Remote (`SpotifyiOS` v5.0.1, August 13, 2025, not added).** It drives the installed app over a local connection and reports player state without polling. It adds nothing that helps day to day, so HomePad leaves it out:
  - It connects only while the Spotify app runs. Its FAQ says "Music must be playing when you connect with `SPTAppRemote` to ensure the Spotify app is not suspended in the background". That is the same window in which the app is a Connect device for the Web API.
  - The one thing it adds is waking Spotify: `authorizeAndPlayURI` switches to the Spotify app, starts the URI and comes back. Guided Access blocks switching apps, so in the kiosk it wakes nothing the Web API cannot.
  - Its authorization returned `error=unknown_error` and no token in Spotify's own demo app on Spotify 9.1.48 ([issue 474](https://github.com/spotify/ios-sdk/issues/474), June 2026, closed without an answer). The repository has had one commit since August 2025, a change of owner.
  - Its player API has no volume, no devices and no search or library, so the Web API would still be needed.
  - It is a closed binary under Spotify's Developer Terms, with no license file of its own (`Package.swift` is one `binaryTarget`, 326 KB for the device slice, 1.06 MB for the whole xcframework). It would add a URL type to Info.plist and the bundle ID to the dashboard. ([ios-sdk](https://github.com/spotify/ios-sdk))
- **Spotify's Web Playback SDK** in a `WKWebView` could make HomePad itself a Connect device. Spotify lists iOS browsers as supported, but it is untested on iPadOS 26, needs the `streaming` scope and Premium, and would play in WebKit's audio session, which could disturb the microphone claims verified on a device. Not built.
- **Music Assistant's Spotify provider** plays Spotify on HomePods from Home Assistant, with no app on the iPad. See [Music Assistant](#music-assistant-through-home-assistant).

### Each person's own account

- **Accounts.** One for the household, used by guests and anyone without their own, and one per member. All of them sign in to the household's one developer app (Kyle's client ID), so each person's Spotify account must be on that app's User Management list.
- **Which account.** While HomePad recognizes a member (face recognition, Face ID or Use Personal Device, `household.unlockedMember`) who has linked an account, Spotify in Music uses theirs: Listen Now, the Library, search, album, playlist and artist pages, Now Playing, the pill, the Now Playing widget, Control Center, the iPhone remote and the assistant's "play X". Picking someone by hand in People is not enough, as for their messages and photos. Everyone else gets the household's account. With neither, Spotify is not offered as a source (`SpotifyAccountChoice.wanted`, tested).
- **Music that plays keeps its account.** When HomePad recognizes someone else while the account in use plays, that account stays until its music stops, so Now Playing still shows it and anyone can pause it. Listen Now says whose Spotify is playing. Starting new music (a tap, a search played, or the assistant) switches to the recognized person's account first, and pauses what the last account played on this iPad, as Apple Music's queues do (`SpotifyAccountChoice.inUse`, `useSpotifyAccountForNewMusic`, tested).
- **A switch forgets everything.** Listen Now, the Library, search results, Up Next, the devices and Now Playing of the last account are dropped, any answer that arrives after the switch is dropped (`accountEpoch`), and its pages close.
- **Signing in on the person's own iPhone** (the way to do it). In HomePad on their iPhone, the HomePad's remote ends with Unlock With This iPhone, Show My Photos and My Spotify. Sign In to Spotify opens Spotify's own page on the phone, for the household's client ID, which the HomePad tells the phone. It shares Safari's Spotify sign-in, so it is often one tap, and asks which account (`show_dialog`). The phone then hands Spotify's one-time code and PKCE verifier to the HomePad, sealed to it and signed after Face ID, and the HomePad exchanges them for tokens (Connect README, Spotify from each person's iPhone). The password is typed only on the phone, and the refresh token is made on the HomePad and never exists on the phone.
- **Signing in on the iPad** (the fallback). Settings > Audio & AirPlay > Spotify Setup lists the household and each member. A member's Sign In Here appears only while HomePad recognizes that member, so nobody links someone else's account at the wall. The household's signs in at any time. The browser session is ephemeral, so no Spotify cookie stays on a shared iPad.
- **Why not the Spotify app's own login.** Only the iOS SDK's authorization signs in through the Spotify app. It needs the SDK, a URL type and the bundle ID in the dashboard, and it returned `unknown_error` in Spotify's own demo (see [Why this path](#why-this-path)). The phone's web sign-in already offers the login Safari remembers, and iCloud Keychain fills passwords and passkeys.
- **Secrets.** Each account's refresh token is in this iPad's Keychain, under `audio.spotify.refreshToken` for the household (the name it always had, so an existing sign-in stays) and `audio.spotify.refreshToken.<member UUID>` for a member. It is never synced to iCloud Keychain (`SpotifyService.tokenStore`, tested), never logged, and never in settings. Access tokens stay in memory. Each account also has a record in this iPad's settings (`SpotifyAccountRecord`, `audio.spotify.account` and `audio.spotify.account.<member UUID>`): Spotify's user ID and name, where and when they signed in, the device new music plays on, and this iPad's Connect device under that account. Nothing in it is secret. Requests go only to accounts.spotify.com and api.spotify.com.
- **When they go.** Sign Out in Settings or on the person's phone removes the token and the record. A member removed from the household loses both at once, also when they were removed on another HomePad or while HomePad was not running (`audio.spotify.members` lists who has one, tested). A new client ID ends every sign-in. When Spotify ends one (six months), the record stays, so that person's Spotify asks them to sign in again instead of quietly showing the household's.

### Where it plays

- Spotify's Web API controls only the devices signed in to the same Spotify account: `GET /me/player/devices` lists that account's devices, and every player call acts on them. So a member's music plays on This iPad only while the Spotify app on this iPad is signed in as them. The Spotify app holds one account at a time. Otherwise it plays on their own phone, computer or Connect speakers, which their account lists, picked in Play On.
- HomePad learns whose Spotify the app here has: the Spotify user under which it last saw this iPad's device in the list (`audio.spotify.thisIPadUser`). For anyone else's account, This iPad in Play On reads "Signed in to Spotify as Kyle" (the member's name when they linked that account here), and a tap on it says what to do. New music goes to that account's chosen device, else its active one. With none on, Music says whose Spotify the iPad has and asks them to open Spotify on one of their own devices (`SpotifyTarget`, `SpotifyError.thisIPadIsOthers`, tested).
- To make this iPad play their music, a person signs out in the Spotify app here, signs in as themselves and plays any song for a few seconds. HomePad then learns the device under their account, and the iPad becomes theirs until someone else does the same.
- Each account keeps its own device choice and its own Connect device ID for this iPad.

### This iPad as a Connect device

- New Spotify music plays on this iPad unless another Connect device was picked (`audio.spotify.device`, empty for this iPad).
- The Web API names devices and gives their type, nothing more, and iPadOS gives HomePad no name to compare. So HomePad learns which device is the Spotify app here (`SpotifyThisIPad`, tested) and keeps its ID with the account, on this iPad (`SpotifyAccountRecord.thisIPadID`):
  - HomePad opened Spotify here, and a device that was not listed before joins. That is this iPad.
  - Spotify plays on a tablet while another app's audio plays here (`secondaryAudioShouldBeSilencedHint`) and HomePad's own players are quiet. That tablet is this iPad.
  - A remembered device that is still listed is never replaced, so another iPad playing Spotify cannot take its place.
- When new music should play here and the Spotify app here is not in the device list, HomePad opens it (`spotify:`), reads the device list every two seconds for up to two minutes, and plays what was asked once it joins (`wakeSpotifyHere`). The person comes back with the HomePad link at the top left. HomePad also reads Spotify again each time it comes back to the front.
- Listen Now, the Play On panel and the setup page say where the Spotify app here stands: open, not open, or not met yet (`SpotifyService.HereState`).

### Under Guided Access

- iPadOS opens no other app under Guided Access or Single App Mode, so HomePad cannot open Spotify there, and App Remote could not either. HomePad says so with the steps (`SpotifyWake`) instead of a button that does nothing.
- The Spotify app stays a Connect device while it plays, and for a while after it stops. iPadOS then suspends it and it leaves the device list. Spotify Community users report a few minutes. With `-HomePadAudioTrace YES`, audio-session-trace.txt notes it as `spotify here: left the device list, N s after it last played here`, to the resolution of the polling.
- Once it has gone, the person triple-clicks the top button and ends Guided Access, plays again (HomePad opens Spotify and comes back playing), and starts Guided Access again.
- Autonomous Single App Mode could end itself, open Spotify and start again on return, with no passcode. Not built: it needs a supervised iPad, and a failure would leave the kiosk unlocked.

### HomePods and volume

- Spotify on iOS has not adopted AirPlay 2's long-form audio, so its sound follows the iPad's system route: one AirPlay speaker or stereo pair at a time, which suits a stereo pair. ([MacRumors, April 2023](https://www.macrumors.com/2023/04/02/spotify-downplays-homepod-support/))
- With Spotify on this iPad, the speaker button in Music's header and in Now Playing opens the same AirPlay picker as Apple Music (`newMusicUsesAirPlay`, `nowPlayingUsesAirPlay`, tested). Other Spotify devices get the Play On panel, where This iPad is the first row, with an AirPlay button.
- The volume slider moves the HomePods through `spotifyVolume`, a second `MusicAirPlayVolume` that reads the system route's output context (`AVOutputContext.sharedSystemAudioContext`) as the first reads Apple's long-form one. The Web API refuses volume for phones and tablets (403, "Restriction violated"), and the system volume follows HomePad's own session, which stays on the iPad speaker. When the route reads the iPad itself, the slider sets the system volume. When it cannot be read, the AirPlay menu's per-speaker sliders stand in (`NowPlayingVolumeTarget.airPlay`, tested). It keeps no memory and restores nothing.
- Now Playing, the pill, the Now Playing widget and HomePad's Control Center follow Spotify (`Focus.spotify`), with the AirPlay speakers' name as where it plays. The iPad's own Lock Screen and Control Center show Spotify's own Now Playing.

### Setup and status

Settings > Audio & AirPlay > Spotify turns it on, and Spotify Setup is a page of five steps, each checked once done (`SpotifySetupStep`, tested). Its top shows the state and whose account is in use.
1. **Create a Spotify app** at developer.spotify.com/dashboard, signed in with Premium: App Name `HomePad`, App Description `Spotify on my HomePad iPad`, Redirect URI `homepad-spotify-login://callback`, and only the Web API box. Each value has a copy button. Website, Bundle IDs and Android Packages stay empty.
2. **Add who signs in** under User Management: Kyle, each person who links their own account, and the household's account if it is another one. Up to five.
3. **Paste the client ID.** It is kept in the keychain (`audio.spotify.clientID`, `services.keychain`). It is the household's one app, and each member's iPhone gets it from the HomePad.
4. **Sign In Each Person.** The household, then each member, with the account's name, where they signed in and Sign Out (`SpotifyAccountRows`). A member signs in on their own iPhone, or here with Sign In Here while HomePad recognizes them.
5. **Play once in Spotify here**, so HomePad learns which device this iPad is.

Settings and Listen Now show one state each, for the account in use: needs a client ID, not signed in, needs Premium, account not on the user list, sign in again, unknown client ID, no device on, or Spotify not open here.

**What Kyle does once:** steps 1 to 3, the household's sign-in in step 4 if guests should have Spotify, and step 5. For each person who wants their own Spotify, add their Spotify account's name and email under User Management in the dashboard (step 2), and link their iPhone to them on this HomePad (Unlock With This iPhone, Connect README).

**What each member does once:** in HomePad on their iPhone, open this HomePad, link the iPhone to themselves if it is not yet, then under My Spotify choose Sign In to Spotify, sign in to their own account, and confirm with Face ID. To have their music play on this iPad itself, they sign in to the Spotify app here as themselves (see [Where it plays](#where-it-plays)), otherwise it plays on their own devices. Every six months Spotify asks them to sign in again, from the same card.

Polling (`SpotifyService.pollInterval`, tested): every 3 seconds while a Spotify screen shows, every 15 while music plays, every 30 for ten minutes after it stops, then not at all, and never while Spotify is not the source. With this iPad as the target, each poll also reads the device list, to see whether the Spotify app here is still awake.

### Limits

- **For a personal app** (Spotify's development mode): the app owner needs Premium, up to five accounts on the app's User Management list (so the household's account and at most four people's, Kyle's included), search returns at most 10 of each kind, playlist songs are listed only for playlists the person owns or collaborates on, and artist top tracks, recommendations and browse categories are not available to new client IDs. Refresh tokens end six months after sign-in, and Settings then asks to sign in again. ([February 2026 changes](https://developer.spotify.com/documentation/web-api/tutorials/february-2026-migration-guide), [refresh token expiry](https://developer.spotify.com/blog/2026-06-18-refresh-token-expiration))
- **Spotify's design rules**: Spotify content stays on screens of its own (it is a separate source, never mixed into Apple Music shelves), with "Open Spotify" links back.

## Music Assistant through Home Assistant

`MusicAssistantClient` and `MusicAssistantService` use only `services.smartHome`. HomePad never talks to Music Assistant directly.

| What | Home Assistant call | Source |
|---|---|---|
| Is Music Assistant set up, and its `config_entry_id` | WebSocket `config_entries/get` with `domain: music_assistant` | [config_entries.py](https://github.com/home-assistant/core/blob/dev/homeassistant/components/config/config_entries.py) |
| Search every provider | `music_assistant.search` with `config_entry_id`, `name`, `media_type`, `limit`, `library_only` (response: `artists`, `albums`, `tracks`, `playlists`, `radio`, `audiobooks`, `podcasts`) | [docs](https://www.home-assistant.io/actions/music_assistant.search/), [services.py](https://github.com/home-assistant/core/blob/dev/homeassistant/components/music_assistant/services.py) |
| Listen Now shelves | `music_assistant.get_library` with `config_entry_id`, `media_type`, `favorite`, `order_by` (`last_played_desc`, `timestamp_added_desc`), `limit`, `offset` (response: `items`) | [docs](https://www.home-assistant.io/actions/music_assistant.get_library/), [schemas.py](https://github.com/home-assistant/core/blob/dev/homeassistant/components/music_assistant/schemas.py) |
| Play on a speaker | `music_assistant.play_media` on the entity with `media_id` (a URI from search, or a name), `media_type`, `enqueue` | [docs](https://www.home-assistant.io/actions/music_assistant.play_media/), [services.yaml](https://github.com/home-assistant/core/blob/dev/homeassistant/components/music_assistant/services.yaml) |
| Up Next | `music_assistant.get_queue` on the entity (response keyed by entity ID: `current_item`, `next_item`, `items`, `current_index`) | [docs](https://www.home-assistant.io/actions/music_assistant.get_queue/), [media_player.py](https://github.com/home-assistant/core/blob/dev/homeassistant/components/music_assistant/media_player.py) |
| Move music to another speaker | `music_assistant.transfer_queue` on the target with `source_player`, `auto_play` | [docs](https://www.home-assistant.io/actions/music_assistant.transfer_queue/) |
| Multi-room | `media_player.join` (`group_members`) and `media_player.unjoin` | [media_player docs](https://www.home-assistant.io/integrations/media_player/#media-control-actions) |
| Transport and volume | `media_player.media_play`, `media_pause`, `media_next_track`, `media_previous_track`, `media_seek`, `volume_set` | same |

Actions that answer (`search`, `get_library`, `get_queue`) go through `call_service` with `return_response: true` ([WebSocket API](https://contributors.home-assistant.io/core/internals/websocket-api/)).

Players are Home Assistant `media_player` entities whose entity registry `platform` is `music_assistant` (Core's `HomeAccessory.integration`). Music Assistant's dashboard displays (device class `tv`) are left out because they cannot play music. The device model (`HomeAccessory.deviceModel`) picks the HomePod, HomePod mini or Sonos symbol.

**Spotify** also works through Music Assistant's Spotify provider, which can play it on HomePods. HomePad's own Spotify source is described under [Spotify](#spotify).

**Each person's Music Assistant user.** Music Assistant can hold several Spotify accounts, each a source of its own, and since 2.7 has users, each limited to the sources they may use (Music Assistant's Settings > User Management, "Only these sources are used when initiating playback"). Home Assistant's `search`, `get_library` and `play_media` take a `username` for that user (added to `search` in June 2026 and `get_library` in July 2026, so Home Assistant 2026.8 or later). Without it, Music Assistant uses the Home Assistant user of HomePad's token. Settings > Audio & AirPlay > Music Assistant Users sets a Music Assistant user per member (`HouseholdMember.preferences["audio.musicAssistant.user"]`). While HomePad recognizes that member, every search, Listen Now shelf, Library list and play goes as their user, so their own Spotify account plays on the HomePods, and their library shows. Changing who is recognized reloads what Music showed. With no user set, nothing is sent, so an older Home Assistant keeps working (`MusicAssistantAction`, tested). To set it up, add a Music Assistant user per person, add each person's Spotify account as its own Spotify source, limit each user to their own source, and type the user names in HomePad. What Music Assistant does with a library item that more than one Spotify source has is up to Music Assistant.

**Music Assistant's web UI** stays available as a secondary "Open Music Assistant" panel when its address is set, themed with HomePad's colors.

## This iPad

**Apple Music status.** `AppleMusicProbe` runs a one-song catalog search, then checks the subscription, and reports exactly one of: Ready, Needs Apple Music subscription, MusicKit not enabled for HomePad (the developer token request failed), Not allowed, or Offline. The Music app and Settings show it with a short fix, never a blank screen. Every MusicKit failure is logged with `Log.make("Music")` using `String(reflecting:)`, so the exact error can be read in Console.

**Library fallback.** When the catalog does not work, `MediaLibraryBrowser` reads the synced library with `MPMediaQuery` (playlists, recently added albums, artists) and `MediaLibraryPlayer` plays it with `MPMusicPlayerController.applicationQueuePlayer`. Both need only the Media and Apple Music permission, no developer token.

**Which Apple player.** HomePad uses `ApplicationMusicPlayer` (MusicKit) and `applicationQueuePlayer` (MediaPlayer), not `SystemMusicPlayer`. Checked on an iPad with HomePods:
- Apple's player runs its own audio session and its own long-form AirPlay route, apart from HomePad's. It plays to the speakers picked in AirPlay, several HomePods at once, while HomePad keeps the microphone on for the wake word.
- HomePad claims no audio session for it (`AudioMediaService.prepareToPlay`). A claim made HomePad's session one that does not mix, and the player starting then interrupted it, which silenced the microphone for as long as the music played.
- `MusicAirPlayVolume` reads and sets the volume of those speakers through AVFoundation's private `AVOutputContext`, and names them for Now Playing. The system volume slider and the volume buttons follow HomePad's own session, which stays on the iPad speaker.
- Application players keep HomePad's queue separate from the Music app's, give HomePad full control of the queue, and keep Now Playing and remote commands with HomePad.
- `SystemMusicPlayer` would survive HomePad quitting, but HomePad is a kiosk app that stays open, and it would take over the Music app's queue.

**Music volume after a restart.** `MusicAirPlayVolume` remembers the last level the person set for each set of AirPlay speakers Apple's player plays to (by their sorted names, in `audio.music.volumes`, on this iPad only), and `MusicVolumeRestore` decides what each reading means (tested):
- The speakers keep their own volume. Whenever they can be read, HomePad shows what they read and writes nothing.
- Until they can be read, right after launch, the assistant and the iPhone remote use the remembered level. They used the iPad's own volume, often far higher, so "turn it down" could set the HomePods louder.
- The one write HomePad makes on its own: in the first 8 seconds of the first playback to speakers after a launch or a reconnect, speakers that read louder than the person left them get that exact level back, at most twice. It never raises a volume and stops once the person sets one. A pause is not a reconnect.
- While music plays after that, a volume changed elsewhere (the AirPlay menu, the top of a HomePod, the Home app) becomes the remembered level. One raised elsewhere while HomePad was not playing comes back down to HomePad's level at its next first playback.
- A level set while the speakers cannot take it yet is sent once they can, within 10 seconds.
- HomePad never sets the system volume on its own, at launch or around an assistant request.

**Radio and sleep sounds** stay iPad-only, as secondary sections of the Music app. They work without any account. They play in HomePad's own audio session, so Keep Microphone On applies to them: with it on, the wake word keeps working and they reach one AirPlay speaker at a time. With it off, HomePad claims `.longFormPlayback` for AirPlay 2 multi-room and the wake word pauses while they play.

## House-wide Now Playing

`services.media.nowPlaying` drives Music's full-screen player, the shell's pill, Control Center's media tile, the Now Playing widget and the iPhone companion's music remote. The pill and Control Center draw the cover through `registry.register(nowPlayingArtwork:)`, so they show the same artwork as Now Playing (MusicKit or library art, a speaker's picture, or `GeneratedArtwork`). It follows, in order:
1. local audio while it plays (Apple Music, library, radio, sleep sounds),
2. a speaker the person chose to control (`select(outputID:)`),
3. with Music Assistant as the source, the active Music Assistant player: the chosen speaker while it plays, then the most recently active one (persisted), with a group follower counting as its leader,
4. whatever is loaded locally.

Transport, seek and volume go to the same place. With This iPad as the source, Music Assistant speakers that play show under "Elsewhere in the House".

`NowPlayingHold` keeps Now Playing steady through track changes. A gap holds the last item for 1.25 seconds, a paused report right after a track change still shows playing, and the same track keeps its artwork and duration. Now Playing's layout comes only from the space available (`NowPlayingLayout`), never from what plays or from proximity, and artwork and text crossfade.

With Settings > Audio & AirPlay > Artwork Fills the Screen on (`AudioSettings.nowPlayingFullScreenArtwork`, off by default), six seconds after the last touch Now Playing's controls fade and `NowPlayingPoster` takes over, as on HomeView: the cover as tall as the screen (as wide when upright), never cropped, fading into the artwork wash, with the title and artist large at the bottom left. A touch anywhere, seen by `TouchObserver` without taking it from the views underneath, brings the controls back and presses nothing. The controls stay while nothing plays, while the speaker picker or Up Next is open, and while VoiceOver is on. The title in the controls is about 48 points on the 11-inch iPad (`NowPlayingLayout.titleSize`), readable from across the room.

## Apps and surfaces

- `music`: a sidebar (chips when narrow) with Listen Now, Search, Library and Speakers, then Radio and Sleep Sounds under "On This iPad". The header has the source menu beside the title and the speaker button. On This iPad, and with Spotify playing on this iPad, the speaker button opens Apple's AirPlay picker at once. For Music Assistant and other Spotify devices it opens the Play On panel. Album, playlist and artist pages push in the content column.
  - It opens where it was left (`MusicPlace`): the section, the Library's kind and the album, playlist or artist page on top, also after a restart, when the page is looked up again from its source. Scroll positions are not kept.
  - Mini player (`MusicMiniPlayer`): the one place Music shows what plays, as in Apple Music on iPad. A Liquid Glass capsule floats at the bottom of the content column on every section and page, over the content, with the cover (`NowPlayingArtwork`), title, artist and where it plays (when there is room), then previous, play or pause and next. It is sized for someone walking up to the iPad: as tall as `Theme.Size.heroControl` (88 points), a 68 point cover, Title 3 text and `roundControl` buttons. A tap anywhere but its buttons opens the full-screen player over Music. A swipe left on it plays the next song and a swipe right the one before, as in Apple Music and CarPlay, from anywhere on the bar, its buttons too. The cover and title follow the finger a little, fading as they go, and spring back. A release past 64 points or a quick flick skips, a short slow drag does nothing, and a swipe never also opens the player or presses a button (`MiniPlayerSwipe`, on `DirectionalPan(.horizontal)`). Radio cannot skip, so there the swipe only springs back. VoiceOver gets Next Track and Previous Track as actions on the bar. Every section scrolls under it to the bottom of the screen, and its last row stays clear of it. It shows whatever Now Playing has, playing or paused: after a restart, or when HomePad recognizes someone, that is the person's saved place, paused where it stopped, so Play picks up where they left off. With nothing to show it hides, and it scales and fades in and out with the music on `Theme.Motion.settle`, like the shell's pill, which stays hidden inside Music.
  - Listen Now: shelves from the source, led by Recently Played. Speakers are chosen from the header or the Speakers section, so Listen Now has no speakers panel.
  - Search: recent searches, moods and shelves before typing. Results show a top result beside songs, then shelves. Music Assistant search has kind chips.
  - Speakers: This iPad's AirPlay route, every Music Assistant speaker with what it plays and its volume, and other Home Assistant speakers.
  - Play On panel (Music Assistant and Spotify): check one speaker or several for multi-room, with volume per speaker. It moves the queue when the playing speaker is left out. With Spotify, it lists This iPad first, with an AirPlay button, then the Spotify Connect devices.
- Full-screen player (`NowPlayingView`): part of Music, not an app of its own, so the pill opens the app that plays. Music presents it with `fullScreenCover` while `media.isPlayerOpen` (`openPlayer()`, `closePlayer()`), zooming out of the mini player (`navigationTransition(.zoom)` from its `matchedTransitionSource`) and back into it, as Apple Music on iPad does. iPadOS owns the opening, the closing and the drag down, and its own menus (AirPlay) open over the player, which an overlay drawn inside Music covered. The header has the speaker button, Up Next, a sleep timer and a chevron that puts it away, then artwork, title, scrubber, shuffle, transport and repeat, and volume (system volume for this iPad, the AirPlay speakers for Apple Music and for Spotify on this iPad, the speaker's volume for a remote one or a Spotify Connect device). Closing shows Music as it was, on the same page and scroll position. The shell draws its alerts under any presentation, so the player closes for the assistant, the doorbell, a finished timer and an intercom message. It draws the shell's home bar (`coverHomeBar()`), so a tap on the bar or a swipe up from the bottom edge goes Home from the player as from Music: the window, player and all, shrinks into the Music icon, and a short swipe springs back to the player. Once the window has landed the shell dismisses the player, so Music opens again on its page and the mini player brings the player back. Going to the face or to another app closes it the same way. `nowplaying` is an `AppRedirect` to Music that opens the player, so the pill, the Now Playing widget, Control Center and links land in Music with the player up, and Music's back button returns to the app the pill was tapped in. It is dark in every appearance, as Apple Music's is, since its page is a dark wash of the cover, and Up Next stays dark with it. Everything else in Music follows the appearance, and the mini player is light glass with dark text in Light.

- Now Playing widget (`audio.nowplaying`, `NowPlayingWidgetView`), small, medium and large, on the Home Screen and on faces. Every size has play or pause and the volume, and medium and large add back, forward and AirPlay.
  - The volume is an upright bar at the trailing edge, as tall as the widget, like the volume beside Control Center's media tile. It is a `BigSlider` (`VolumeSlider` in its `.bar(.vertical)` style), and a drag anywhere on it moves the level. On the widget's glass it takes the tile's control fill (`controlSurface`) and corners, and it fills with `.primary`, so it reads on dark and light glass and turns red at night with the rest of the widget.
  - It sets the same level as the full-screen player (`NowPlayingVolumeTarget`, `NowPlayingVolumeSlider`): the speaker transport goes to, the Spotify Connect device, the AirPlay speakers Apple's player or the Spotify app on this iPad plays to, or the system volume. Where HomePad cannot read those speakers (`.airPlayMenu`), the bar's place holds an AirPlay button that opens the menu with a slider for each speaker. Remote speakers and Spotify Connect devices get the level when the drag ends, the others as the finger moves.
  - The controls come first. At the default text size they are `Theme.Size.tapTarget` (64) tall: play or pause is a 64 point square with a 38 point symbol, back and forward are 44 wide with 27 point symbols, the bar is 64 wide (44 in small, to leave the title room) and AirPlay is 44. Each size takes the first layout that fits its tile (`ViewThatFits`): larger text drops title and artist lines and the cover shrinks or goes before the controls step down to 48 and then 44 points (`toolbarItem`, `minTapTarget`).
  - Small shows the title over play or pause, with the cover above it in a tall cell. Medium shows a 44 to 64 point cover beside the title and artist, over the transport and AirPlay. Large shows a cover that takes the height left over the title, artist and transport. A tap on the cover or the title opens Now Playing in Music, and in small a tap anywhere but the controls does.
  - The bar's drag starts as the finger lands, and SwiftUI gives a view's own gesture precedence over those around it, as for Control Center's sliders. So dragging the bar moves only the volume: it does not turn the face or Home Screen pages, open Music, or count as the holds that edit the Home Screen or open Faces. Being upright, it also moves across the pages' axis. In Home Screen edit mode the widget takes no touches, so a press lifts it as before.

Shared look: every screen uses HomePadUI (`AppScreen`, `AppHeader`, `GlassTile`, `GlassPanel`, `ShelfRow`, `ArtworkTile`, `ChoiceChips`, `GlassIconButton`, `GlassCapsuleButton`, `GlassBanner`, `EmptyStateView`). Items without artwork get `GeneratedArtwork`, a palette gradient with the name.

Candidates for HomePadUI, in `Views/Components/`: `GeneratedArtwork`.

## Assistant

- `play_music` (Assistant module) calls `services.media.playSearch`. It routes a request that names a speaker ("Taylor Swift in the kitchen") to that Music Assistant speaker, uses the chosen speaker when Music Assistant is the source, Spotify's best match on the chosen device when Spotify is the source, and otherwise plays on this iPad (the recognized member's own playlist for "play my playlist Road Trip", then Apple Music, then the library, then radio).
- `play_on_speaker` searches with `music_assistant.search`, plays the best match by URI, and can set volume and group speakers.
- `list_speakers` reports groups and which speakers are not in Music Assistant.
- `play_radio` plays a station by name, `play_sleep_sounds` starts a sleep sound with an optional timer, and `identify_song` listens with ShazamKit.

## Core API this module relies on

In HomePadCore:
- `SmartHomeService.sendCommand(_:data:)`, a raw command with a JSON result. The default throws `SmartHomeError.unsupported`.
- `SmartHomeCommands.swift`: `callServiceForResponse(domain:service:data:target:)`, `integrationEntries(domain:)` returning `SmartHomeIntegrationEntry`, and `browseMedia(entityID:contentType:contentID:)`.
- `HomeAccessory.integration`, `deviceClass` and `deviceModel`. `AccessoryState.mediaAlbum` and `mediaGroupMemberIDs`.

HomePadSmartHome implements `sendCommand` for Home Assistant with HAKit. The unified service allows action calls (checked by the same security policy as `callService`) and read-only commands only.

## Structure

```
Sources/HomePadAudio/
  AudioModule.swift        registration
  Services/                AudioMediaService (+Focus, +Transport, +NowPlaying, +Playback, +AppleMusic,
                           +Queue, +Members, +MemberAccounts, +Recents, +Spotify, +Routing, +Source, +MusicSources),
                           NowPlayingHold, FocusHold, SpokenMusicRequest, session claimer, Now Playing bridge
  Queue/                   UpNextEdit, QueueEditing, MemberMusicState, MusicQueueOwner
  Browse/                  MusicPage (pages pushed in the Music app), MusicDetail (a page from any source),
                           MusicPlace (where the Music app was left)
  Spotify/                 PKCE sign-in (with Core's SpotifyPKCE), Web API client, items, playback and devices,
                           accounts per person (SpotifyAccounts), where new music goes (SpotifyTarget),
                           this iPad's device and waking it (SpotifyThisIPad), service, pages
  MusicAssistant/          action payloads, client, models (items, search, queue, player), service
  AppleMusic/              MusicKit player (+Covers, +Resume, +Queue), catalog browsing, library, pages,
                           tiles, lookups by ID, live status probe
    Members/               each person's own Apple Music: the API client, items and the playable rule, the
                           encrypted cache, the library while shown, whose shows, playback, tiles and pages
  MediaLibrary/            MPMediaQuery browser and applicationQueuePlayer source
  Playback/                PlaybackSource protocol shared by every local source
  Radio/, Ambient/         internet radio and sleep sounds
  HomeAssistant/           media_player payloads, speaker mapping, remote controller
  Routing/, Recognition/   AirPlay routing and ShazamKit
  Tools/                   assistant tools
  Views/                   Music (+Search, Library, Pages), Speakers, NowPlaying (+Up Next), Overlays, Controls, Settings, Components
  Demo/                    simulator content, including a pretend Music Assistant
  Models/, Settings/       small value types and setting keys
```

## Settings

All keys are `audio.*`, in `Settings/AudioSettings.swift`: `musicSource`, `musicAssistant.player` (where new music plays), `musicAssistant.lastActive`, `musicAssistant.url` (optional web panel), `music.recentSearches`, `music.queueOwner` and `music.member.<owner>` (each person's queue, place and Recently Played, on this iPad only), `spotify.enabled` (off by default), `spotify.account` and `spotify.account.<member UUID>` (each linked account's record, on this iPad only), `spotify.members` (the members with one), `spotify.thisIPadUser` (whose Spotify the app here has), `spotify.device` and `spotify.thisIPad` (read once into the household's record, from before members had accounts), `preferMicrophone`, `preferredSpeaker`, `promptForPreferredSpeaker`, `pauseOnHeadphonesDisconnect`, `sleep.defaultMinutes`, `sleep.presets`, `radio.favorites`, `radio.saved`, `radio.recents`, `appleMusic.resume`, `music.volumes` (the music volume per set of AirPlay speakers, on this iPad only) and `lastLocalSource`.

Each person's own Apple Music adds no settings here. Their listings are in their encrypted cache, with its key in the Keychain (`com.ksha23.homepad.music.cache`, this device only), and their token in the Connect module's Keychain item.

Where the Music app was left is kept by `MusicPlace` (`Browse/MusicPlace.swift`) in three keys of its own, on this iPad only: `audio.music.place.section`, `audio.music.place.libraryKind` and `audio.music.place.page` (the page on top by its source, kind and ID, as Recently Played keeps items). They are all in that one type so they can move to a shared state API in one place.

Settings > Audio & AirPlay has Music Source, Apple Music on This iPad (live status, library status, Connect or Check Again), Music Assistant (status, the speaker it plays on, web panel address), Music Assistant Users (one per member), Spotify (turn on, and Spotify Setup: five steps with the dashboard values, client ID, each person's account, and the Spotify app here), AirPlay From This iPad, AirPlay and Microphone, Sleep Sounds and Favorite Stations.

## Simulator

The simulator has no Home Assistant, no AirPlay speakers and no Apple Music playback. `-HomePadAudioDemo YES` swaps in `DemoMusicAssistantHome`, a `SmartHomeService` that answers `config_entries/get` and the Music Assistant actions in the documented JSON shapes and changes four demo speakers (Living Room HomePods grouped with Kitchen, Office Sonos, Bedroom). It also adds a demo Apple Music queue on the iPad, with Up Next, shuffle and repeat, and demo library pages. Nothing contacts a real Home Assistant.

```
-HomePadOpenApp music|nowplaying   -HomePadAudioDemo YES
-HomePadMusicSource thisIPad|musicAssistant|spotify   (spotify also turns Spotify on, to see its setup state)
-HomePadSettingsPane audio -HomePadSpotifySetup YES   (Settings opened on Spotify Setup)
-HomePadSpotifyAccounts YES        (Spotify Setup scrolled to Sign In Each Person)
-HomePadSpotifyDemoAccounts YES    (debug builds: made-up accounts for the demo people, with -HomePadDemoContent YES.
                                    The household and Sam signed in, Jordan's ended, Alex none. Tokens in memory,
                                    every request answered in the app, nothing reaches Spotify)
-HomePadMusicSection listenNow|search|library|speakers|radio|sleep
-HomePadMusicLibrary playlists|albums|artists|songs
-HomePadMusicPage <demo album, playlist or artist name>   (such as "Night Signals", "Dinner Party" or "Neon Avenue")
                                   (these three win over where Music was left, and a launch with any of them saves nothing)
-HomePadNowPlayingQueue YES        (Now Playing opens with Up Next)
-HomePadMusicSearch <text>         -HomePadMusicSpeakerPicker YES
-HomePadForceLandscape YES         -HomePadCondition active
-HomePadAudioDemoSong YES          (song recognition card)
-HomePadAudioDemoArtwork YES       (large square demo covers)
-HomePadAudioDemoSkipEvery 3       (skip a track every 3 seconds)
-HomePadAudioTrace YES             (on a device: Documents/audio-trace.txt and audio-session-trace.txt)
-HomePadMemberMusicDemo YES        (the recognized member has a made-up Apple Music, answered in the API's own
                                    shapes, with uploads and a personal station dimmed. Recognize someone with
                                    -HomePadDemoContent YES -HomePadMember Alex -HomePadRecognized YES)
```

## Check on the iPad first

1. Settings > Audio & AirPlay > Music Assistant shows the number of speakers. If it says "Not Set Up in Home Assistant", the long-lived token's user may not see the Music Assistant config entry.
2. In Music, pick Music Assistant, open the speaker button, and check that HomePods and Sonos appear with the right names and symbols.
3. Search for an artist. Results should mix Apple Music and any other providers. Play one on a HomePod.
4. Check two speakers in Play On for multi-room. Uncheck the playing one to check `transfer_queue`.
5. Now Playing, the pill, Control Center and the widget should follow that speaker, with artwork, progress and working transport.
6. Ask the assistant "play Taylor Swift in the kitchen".
7. Pick This iPad. Settings > Audio & AirPlay > Apple Music should read Ready once the MusicKit App Service is enabled for `com.ksha23.homepad`. Until then it should read "MusicKit not enabled for HomePad" and the synced library should still play.
8. Skip tracks in Now Playing on both sources and check that nothing jumps.
9. Up Next: play an album, add a song with Play Next and another with Play Later, drag one, remove one, then Clear. The song that plays must not restart. Then quit HomePad and play again: the edited queue comes back.
10. Per person: with music paused, switch people in the People menu (or be recognized). Each person's own song comes back, paused. Switch while music plays: it keeps playing.
11. Shuffle and repeat in Now Playing, and a station (Play Next is hidden, shuffle and repeat dim).
12. Library: playlists, albums, artists and songs, then an album, a playlist and an artist page, and Add to Library on a catalog album.
13. Spotify per person: link the household's account on the iPad, then sign in to your own from HomePad on your iPhone (My Spotify). Be recognized: Listen Now shows your library, and Settings says your account is in use. Step away and let a guest use it: the household's library. Play from your account, then let someone else be recognized: your music stays in Now Playing until it stops. With the Spotify app here signed in as someone else, Play On says so and your music plays on your phone.
14. Spotify: follow Settings > Audio & AirPlay > Spotify Setup, pick Spotify as the source, and play an album with the Spotify app closed. HomePad opens Spotify, and the album plays once you come back. Pick the HomePods with the speaker button (AirPlay), drag the volume in Now Playing and the widget, and check the HomePods follow. Then move to another Connect device in Play On, add a song to the queue, and check Now Playing and the pill follow it.
15. Music's mini player: play an album, scroll a page, tap the bar away from its buttons for Now Playing, then swipe down: the same page at the same place. Swipe the bar left and right from a step back: the next song, then the one before, and the player stays closed. Pause, quit HomePad and open Music again: the bar shows the song paused, and Play continues it. Check it in night mode too.
16. Now Playing's idle look: turn on Artwork Fills the Screen, then leave Now Playing alone for six seconds while music plays. The controls fade to the full-height cover with the title at the bottom left. Touch the cover where the play button was: the controls come back and the music keeps playing. Skip tracks from the iPhone remote while idle: the cover and title crossfade, nothing else moves. Try it upright too.
17. The Now Playing widget, small, medium and large, on the Home Screen and on a face: drag its volume bar up and down, also starting with a sideways move. The volume moves (the HomePods' with Apple Music, the speaker's with Music Assistant) and the pages stay put. Tap the bar and the controls: Music does not open. Hold the bar still for a second: the Home Screen does not enter edit mode and the face does not open Faces. A tap on the title still opens Now Playing.
18. Each person's own Apple Music: on Kyle's iPhone, turn on Use My Apple Music in the HomePad's remote (the Connect README has the steps). Be recognized at the HomePad and open Music: Listen Now reads "Kyle's Apple Music" with Kyle's own recently played and recommendations, and the Library reads "Kyle's Library". Play an album, a song from Songs and one of Kyle's own playlists, then check the HomePods play them and the iPad's account (not Kyle's) gets the plays in its Recently Played. An uploaded song shows dimmed with "Not in Apple Music". Ask "play my playlist" and a playlist name. Walk away until HomePad stops recognizing Kyle: Music shows the iPad's own library again. Pick Kyle in People without being recognized: still the iPad's.

## Needs real-device testing

- Everything above against Kyle's real Music Assistant, including artwork URLs (Music Assistant's image proxy and `entity_picture`) and position updates.
- That `config_entries/get` works with the long-lived token's user (it is not admin-only in current Home Assistant).
- `applicationQueuePlayer` (the synced library) on HomePods picked in AirPlay, as checked for Apple Music, and its Now Playing info next to HomePad's remote commands.
- The MusicKit probe's classification on a device where the App Service is off, then on.
- `MPMediaQuery` speed with a large library (it runs on the main actor, once per launch).
- Radio and sleep sounds on several HomePods with Keep Microphone On turned off, `RoutePickerPresenter`, `SystemVolume.set`, sleep sounds to AirPlay and AirPods, and ShazamKit.
- Each person's own Apple Music, with a second Apple Account on an iPhone: that the iPad's own developer token works with a user token made on the iPhone (both are made for HomePad's App ID), that the library, recently played and recommendations read as the fixtures say, which status an expired or revoked token gives (401 or 403), that catalog lookups on the iPad find what the member's storefront listed, and how a public playlist (`pl.u-`) plays.
- The music volume after a restart: whether a new AirPlay session from Apple's player moves the HomePods' volume by itself. With `-HomePadAudioTrace YES`, audio-session-trace.txt shows it as a `music volume reading` that rises with no `music volume sent` before it, then `music volume restore`.

- Spotify for each person, with real accounts on the household's developer app:
  - the sign-in on a member's iPhone through to their account on the HomePad, the Face ID prompt, and that Safari's existing Spotify sign-in is offered,
  - an account that is not on the User Management list: the phone's card should say so, and the account should work once added,
  - that `GET /me/player/devices` of one account never lists the Spotify app here while it is signed in to another, and that HomePad then reads "Signed in to Spotify as ..." for that account,
  - that the switch waits while one person's music plays and happens when it stops, and that the assistant plays from the recognized person's account,
  - Music Assistant users: that `username` in `search`, `get_library` and `play_media` uses each user's own Spotify source on the HomePods, on Home Assistant 2026.8 or later.
- Spotify on this iPad, with `-HomePadAudioTrace YES`:
  - that HomePad's AirPlay picker moves Spotify's sound (the system route) to the HomePods while HomePad's microphone stays on the iPad,
  - that `spotify route volume reading` names the HomePods and reads `settable true`, so the slider moves them. If it reads the iPad while the HomePods play, Spotify has moved to the long-form route, and the `music volume reading` lines name the HomePods instead,
  - that HomePad learns the Spotify app's device (`spotify here: learned this iPad's device`) after a play in Spotify, and after HomePad opens it,
  - how long the Spotify app stays a Connect device after a pause (`spotify here: left the device list, N s after it last played here`),
  - what Guided Access does to `UIApplication.open` for `spotify:`, and that the notice explains it.

## Known gaps

- Music Assistant players hidden from the Home app's layout are hidden from Music too, because they come from `services.smartHome.accessories`.
- Up Next for Music Assistant shows the current and next items and a count, because `get_queue` returns only those.
- Remote speakers do not appear on the iPad's Lock Screen or system Control Center, because iOS shows only the app that plays audio there. HomePad's own surfaces show them.
- With Guided Access on, Apple's AirPlay picker is hard to close: a tap outside it does not close it.
- `media_player/browse_media` is available in Core but the Music app browses through `get_library` instead, which gives artwork and favorites in one call.
- No lyrics. MusicKit has no public lyrics API (`Song.hasLyrics` only says whether Apple has them).
- No Love or Dislike: MusicKit has no ratings API. Apple Music's web API has one (`/v1/me/ratings`) through `MusicDataRequest`, untested.
- No crossfade setting. `ApplicationMusicPlayer.transition` (iOS 18) offers it, untested with HomePods.
- MusicKit has one library and one account per iPad, so the Library and Apple Music's own history are shared by everyone who has not linked their own Apple Music from their iPhone. Queues, places and HomePad's Recently Played are per person.
- Each person's own Apple Music plays through the iPad's account. Their plays count toward the iPad's history, recommendations and play counts, never theirs, and their Recently Played on other devices does not show what they played here (HomePad's own Recently Played does). Songs they uploaded, personal stations, and anything the iPad's country does not have cannot play here. Play Next and Play Later are not on their own playlists' songs yet, and their library shows at most 300 of each kind.
- Spotify's queue can be added to but not reordered or cleared through the Web API. Albums and playlists cannot be queued on Spotify, only tracks.
- Under Guided Access HomePad cannot wake the Spotify app once iPadOS has suspended it. Ending Guided Access is the only way, since iPadOS opens no other app inside it.
- Spotify on this iPad reaches one AirPlay speaker or stereo pair at a time, because Spotify on iOS plays on the system route, not AirPlay 2's long-form one.
- The Spotify app on this iPad plays one account's music at a time. HomePad cannot sign it in or out, so moving it to another person is done in the Spotify app.
- HomePad knows whose Spotify the app here has only from the last time it saw it in a linked account's device list. Until then, or after the app is signed in to an account nobody linked, it is treated as this account's.
- Development mode allows five accounts on the User Management list, so at most five accounts in all, the household's included.

## Dependencies

None. Apple frameworks (AVFoundation, AVKit, AuthenticationServices, CryptoKit, MediaPlayer, MusicKit, ShazamKit, WebKit), the free Radio Browser web API, Spotify's Web API with `URLSession` (optional, with Kyle's own client ID) and the Spotify app on the iPad, and Home Assistant through `services.smartHome`. Spotify's iOS SDK is not used (see [Why this path](#why-this-path)).
