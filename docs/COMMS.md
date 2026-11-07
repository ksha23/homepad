# Messages

HomePad can message as each household member's own Apple ID. iPadOS does not let one app act as several Apple IDs, so a Mac does the Apple-side work and the iPad is the screen.

```
iPad (HomePad)                         Mac (one macOS user per Apple ID)
  HomePadComms module  --HTTPS+token-->   homepad-hub
  CommsKit (shared models)                  reads  ~/Library/Messages/chat.db
                                            sends  through Messages.app (AppleScript)
                                          Messages.app <--iCloud--> your other devices
```

## Why a Mac

Apple only accepts iMessage registrations from real Apple hardware running Apple's own code. The Mac already holds that registration, signed in to the Apple ID. The hub drives the real Messages app, so it works on any macOS version Apple supports and never touches the protocol. Messages in iCloud keeps read state, history and deletions in step with the person's other devices with no extra work.

### Why not the iPhone

Each person's iPhone already runs the HomePad companion, and it brings their photos to the HomePad (see the Connect README). It cannot do the same for Messages. iOS gives apps no way to read Messages or other apps' notifications, and no way to send an iMessage without the person tapping Send on the phone itself (`MFMessageComposeViewController`). Shortcuts can run on a received message, but each person would have to build that automation by hand, and it can only hand the companion one message at a time. Forwarding notifications to accessories exists from iOS 26.2 only in the EU (Accessory Transport Extension). The Mac stays the way in.

## Who can see what

- The hub serves exactly one Apple ID and accepts one bearer token.
- On the iPad, each member's hub URL and token live in the Keychain under that member's ID.
- The module shows the messages of whoever is picked in People. With Settings > Messages > Require face recognition on, it shows them only while `household.unlockedMember` is that member (face recognized or Face ID), and picking a person by hand shows nothing. Until someone chooses, it is on once the household has more than one person (`CommsRuntime.requiresRecognition`), so nobody reads another person's messages by picking them. One person alone can pick themselves.
- When personal content locks, the module drops its connection, clears its in-memory conversations and stops showing banners.
- Notifications are shown by the module itself from the hub's event stream, only while that member is unlocked. Nothing is sent to the lock screen.
- The Messages icon on the Home Screen and in All Apps carries the total unread count (red, 99+ cap), as HomePad counts it (see Read state). The module supplies it through `AppDescriptor.badgeCount`.
- A new message shows a banner on the Home Screen with the sender and text. On the always-on face the banner shows the sender and "New message" only, because the face is read from across the room. Settings > Messages > Show previews on the face adds the text. It fades after about eight seconds, a tap dismisses it, and opening Messages clears it.
- Only messages from other people raise a banner. Your own messages, messages in the conversation on screen, messages older than two minutes, and events the hub replays after a reconnect (same event id or message id) do not.

## More than one person

Each household member has their own hub address and token, stored under their member ID. The module follows whoever is active: when the active person changes, it drops the old connection and connects with the new person's credentials. Nothing of one person is shown or cached under another.

One hub serves one Apple ID, because Messages.app allows one Apple ID per macOS user. One Mac still serves the whole household, with a macOS user for each person:

1. On the Mac, add a standard user for the person (System Settings > Users & Groups) and turn on Fast User Switching (Control Center > Fast User Switching), so every user stays logged in at once.
2. Log in as that user, sign in to Messages with the person's Apple ID and turn on Messages in iCloud.
3. In that user's session, run `Hub/launchd/install.sh`. Each user gets their own port: 8787 for the Mac's first user, 8788 for the second, and so on (`HUB_PORT` picks another). It prints the address to enter on the iPad.
4. Give that user's `~/.homepad-hub/homepad-hub` Full Disk Access (an admin approves it), and allow it to control Messages when macOS asks.
5. Switch back with Fast User Switching rather than logging out, so the user's Messages and hub keep running.
6. On the iPad, the person picks themselves in People and enters their hub address and token under Settings > Messages.

Only the user on screen has an active session. Messages marks a chat read only in an active, unlocked session (see Read state), so for the people whose users run in the background, a conversation read on HomePad is read on HomePad but is expected to stay unread on their iPhone. Whether Messages sends from a background session is not tried yet either. The options for marking read without the chat on screen are in docs/research/READ-STATE-2026-11.md.

After the Mac restarts, macOS logs in at most one user by itself (none with FileVault on), so each person's user has to be logged in once again, at the Mac or over Screen Sharing. A user who is not logged in has no Messages running, and their Messages on the iPad shows that it cannot reach the Mac.

BlueBubbles, which also reads `chat.db` and sends through Messages.app, documents the same setup for several people on one Mac. HomePad has run it with one Apple ID so far. Two Apple IDs on one Mac at once is not tried yet.

To try the flow without a second Apple ID, `Hub/fixtures/make_fixture.py` builds a synthetic Messages database, and `homepad-hub --database <file>` serves it as a second account.

## Reliable connection

- The hub numbers every event and keeps the last 500. A client that reconnects sends `Last-Event-ID` and gets exactly what it missed. If it is older than the buffer, the stream starts with `event: gap` and the client reloads.
- The hub sends a `: ping` comment every 15 seconds, so a dead link is noticed within the client's 45 second idle timeout.
- The iPad retries every 3 seconds with no action from the person, and keeps showing the last messages while it does.
- Signing is stable (`Hub/deploy.sh`, Developer ID), so the Full Disk Access grant survives rebuilds.

## Read state

Messages on the Mac marks a chat read only while that chat is on screen in an unlocked session. A hub Mac often sits locked, so HomePad keeps its own read state and does not wait for the Mac.

- Each person has a read marker per conversation: the date of the newest message they have had on screen on this iPad (`ReadMarkers`). It is saved in their encrypted cache (see Local cache), on this iPad only, and is never sent to the hub or anywhere else. The 200 most recent are kept.
- Opening a conversation sets its marker at once, and again once its messages have loaded. While a conversation is on screen, each new message in it moves the marker. A message sent from any of the person's devices counts as reading everything before it.
- HomePad's count for a conversation:
  - 0 when the hub says 0, so a chat read on the iPhone or the Mac is read here too.
  - The hub's count when there is no marker.
  - 0 when nothing is newer than the marker, whatever the hub counts.
  - Otherwise the unread messages from other people newer than the marker, counted in the thread HomePad holds, and never more than the hub says. When that thread does not reach back to the marker, the hub's count.
- The store keeps the hub's counts aside and puts HomePad's count in each conversation (`CommsStore.conversations`). The unread dot in the list, the icon badge and the Control Center tile (`unreadTotal`) and the banners all read it there, so they always agree. A Messages widget or an assistant summary, when one is built, reads the same place.
- The iPad still asks the hub to mark the chat read when a conversation opens and when a message arrives in the one on screen. The Mac does it when it can, and Messages in iCloud carries it to the person's other devices.
- Dates travel in whole seconds. A message that arrives in the same second as the marker counts as seen.

### How the hub opens a chat

To mark a chat read, the hub opens it in Messages for about a second, then hides Messages. It picks the URL from chat.db (`ChatAddress`), not from the chat GUID, because from macOS 26 every GUID starts with `any;` whatever the service, and a group's GUID ends in its `chat123...` identifier, which is no address.

| Chat | URL | How sure |
|---|---|---|
| One person, iMessage | `imessage://<number or email>` | As before |
| One person, SMS or RCS | `messages://open?groupid=<group_id>`, or `sms:<number>` when the chat has no group ID | Not yet tried on the hub Mac |
| Group | `messages://open?groupid=<group_id>` | Not yet tried on the hub Mac |
| Group with no group ID | Not opened | |

- `group_id` is chat.db's own ID for the conversation. `messages://open?groupid=` names that one chat, so an SMS chat cannot open as an iMessage chat with the same number.
- Apple does not document it. On macOS 27, Messages' own frameworks build this URL to open a conversation (the Shortcuts conversation entity and Siri action suggestions among them), and the URL parser also reads `chatguid`, `recipient` and `addresses`. Not checked on macOS 15.
- A URL made from a group's participants (`sms://open?addresses=a,b,c`) opens a new message to those people. Messages may then show another group with the same people, so the hub does not use it.
- None of this works while the hub Mac's screen is locked. Keep the screen lock off on the hub Mac.

## Local cache

Each person has an encrypted snapshot of their 25 newest conversations and 40 newest messages each, so Messages opens instantly and shows something offline.

- AES-GCM (CryptoKit), one random 256-bit key per person in this iPad's Keychain (not iCloud Keychain), one file per person in Application Support.
- A copied file is unreadable without that person's key. Forgetting a person (`CommsCache.delete`) removes both.
- The in-memory copy is still wiped when the person locks. The file protects against a lost or imaged device, not against someone using the app while it shows that person.

## Parts

| Part | Where | Job |
|---|---|---|
| CommsKit | `Packages/HomePadComms/CommsKit` | Wire models and routes shared by the hub and the module |
| HomePadComms | `Packages/HomePadComms` | Messages app, settings pane, message banners, Control Center tile |
| homepad-hub | `Hub/` | macOS command line tool, one per Apple ID |

## Debug launch arguments

| Argument | Effect |
|---|---|
| `-HomePadCommsDemo YES` | A stand-in hub inside the app (`CommsDemo`) serves made-up conversations to whoever is at the iPad. Nothing reaches a real hub, nothing is cached and nothing is saved to the Keychain |
| `-HomePadMessagesOpen <id>` | Opens Messages on that conversation, such as `demo.sam` or `demo.family` with the demo |
| `-HomePadCommsURL <url> -HomePadCommsToken <token>` | Saves hub credentials for the person at the iPad |
| `-HomePadCommsSeeds '[{"member":…,"url":…,"token":…}]'` | Saves hub credentials for several people at once |

## Hub API

All routes need `Authorization: Bearer <token>`.

| Route | Meaning |
|---|---|
| `GET /v1/status` | Hub version, account handle, permissions state |
| `GET /v1/conversations?limit=` | Recent conversations, newest first |
| `GET /v1/conversations/{id}/messages?before=&limit=` | One page of messages |
| `POST /v1/conversations/{id}/messages` | Send text |
| `POST /v1/conversations/{id}/attachments` | Send a file: raw body, `Content-Type`, `X-Filename` (percent-encoded), up to 100 MB. The hub writes it to `~/.homepad-hub/outbox`, sends it through Messages.app and deletes it |
| `POST /v1/conversations/{id}/read` | Mark read in Messages.app (syncs through iCloud) by opening the chat for about a second (see Read state). Replies once Messages is asked, and the `read` event reports the change. Does nothing for a group with no group ID |
| `GET /v1/events` | Server-sent events: new messages and read changes |

## Reactions

Tapbacks are rows in `message` that point at the message they react to (`associated_message_type` 2000 to 2006 adds, 3000 to 3006 removes). The hub never returns them as messages. They do not set a conversation's preview, date or unread count. Each message carries a `reactions` array instead, where the latest add or remove per person and tapback wins. A custom emoji reaction (2006, macOS 26 and later) uses `associated_message_emoji`. The iPad draws a round badge on the bubble's top corner away from the screen edge, with a count when several people chose the same one. `reactions` is optional on the wire, so old caches and old hubs decode as none. Reading only: Messages.app has no AppleScript to send a tapback. A new tapback does not yet push an event, so it shows on the next load.

## Mac setup

1. Sign in to Messages with the person's Apple ID. Turn on Messages in iCloud.
2. Give the hub binary, `~/.homepad-hub/homepad-hub`, Full Disk Access (to read `chat.db`), and allow it to control Messages when macOS asks the first time it sends.
3. Run `homepad-hub --token-file <path> --port <n>` as a LaunchAgent in that macOS user.

`Hub/deploy.sh` builds the hub, signs it with your Developer ID and swaps it in on the hub Mac over ssh, then restarts the LaunchAgent. The stable signature keeps the Full Disk Access grant across updates. Set `HUB_HOST` (the hub Mac's ssh name) and `HUB_SIGN_IDENTITY` in the environment or in `Hub/deploy.local`, which is not tracked. The Mac also needs `libswiftCompatibilitySpan.dylib` from Xcode's toolchain next to the binary, since a Mac without Xcode does not have it.

## Photos

- Several photos in one message draw as a pile (2 or 3) or a grid with a "+N" tile (4 or more). Tapping opens a full-screen viewer that pages through them, zooms, and loads the original (thumbnail first, with progress).
- Originals live in memory only (`NSCache`) and are decoded off the main thread at a screen-sized resolution. Nothing of a photo is written to disk on the iPad. Video is written to a temp file only for the moment Photos reads it.
- Save to Photos asks for add-only access. Save to Files uses the system exporter, so it can go to iCloud Drive.
- "Send to..." in the viewer and the long-press menu forwards a photo through `POST /v1/conversations/{id}/attachments`. The composer's photo button uses the same route.
