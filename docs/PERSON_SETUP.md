# Guided person setup

One flow takes a person from "new" to "ready" on a HomePad: who they are, their face, their screen, their assistant, and their Messages account. It runs from onboarding, from People > Add Person, and from Finish Setup on an existing person. Every step can be skipped and finished later, and a step that is already done shows a check.

## How modules take part

Feature packages never import each other, so the shell cannot call Presence or Messages directly. Each module contributes a step to the registry, the same way it contributes apps and settings panes. The shell hosts the flow and draws the progress.

```swift
public struct PersonSetupStepDescriptor: Identifiable {
    public let id: String
    public let title: String
    public let subtitle: String
    public let systemImage: String
    public let sortOrder: Double
    /// Whether this person has already done the step. Drives the check mark and "Finish Setup".
    public let status: @MainActor (HouseholdMember, AppServices) -> PersonSetupStatus
    /// The step's screen. It calls `context.next()` when finished and `context.skip()` to leave it for later.
    public let makeView: @MainActor (PersonSetupContext) -> AnyView
}
```

`PersonSetupContext` carries the member, `AppServices`, and the `next`, `skip` and `update(member)` actions.

## The steps

| Order | Step | Module | What the person does |
|---|---|---|---|
| 0 | You | Shell | Name, emoji, color. Built in, not skippable. |
| 10 | Your face | Presence | The existing enrollment (five poses at arm's length, two seated), in a guided full-screen layout with the live camera and hints. |
| 20 | Your screen | Faces | Pick the always-on face, from live thumbnails. Stored as `preferences["faceID"]`. |
| 30 | Your assistant | Assistant | Provider, model and personality, from `MemberAssistantPreferences`. |
| 40 | Messages | Comms | Pair with the hub on their Mac by scanning a QR code, then watch a live checklist turn green. |
| 99 | Done | Shell | Summary of what is ready and what was skipped, with a button into their Home Screen. |

## Pairing Messages

The person sets up Messages in two places, and the iPad leads them through both.

On the Mac (shown on the iPad as a numbered checklist, each item ticking itself when the hub reports it):

1. Sign in to Messages with the person's Apple ID, and turn on Messages in iCloud.
2. Run `homepad-hub install --name <person> --port <n>` in that Mac user's session. It copies and signs the hub, creates a token and a LaunchAgent.
3. Give the hub Full Disk Access (read messages) and Automation access to Messages (send).
4. Run `homepad-hub pair`. It prints a QR code, and also saves it as an image and opens it.

On the iPad:

1. The step opens the camera and scans the QR code, which holds the hub address and token (`homepad-hub://pair?u=...&t=...`).
2. The credentials go into the Keychain under that person.
3. The step polls `GET /v1/status` and shows `Reachable`, `Signed in as <Apple ID>`, `Can read messages`, `Can send messages`, each green or with the one thing to fix.
4. Typing the address and token by hand stays available as a fallback.

## What it does not cover

iPadOS shows only the iCloud account signed in on the iPad itself to Calendar, Reminders and Photos, so other people's calendars cannot come through the system. CalDAV with an app-specific password could add Calendar and Reminders per person later. Photos would need a shared-album link.
