# HomePadPresence

The sensing layer that makes an always-on iPad feel aware of the room. It notices people, measures how far away they are, recognizes household members, reads hand and AirPods head gestures, listens for alarms, and provides the Mirror app.

It installs `LivePresenceService` into `services.presence`, registers the assistant tool `presence_status` (who is near, how far, looking or not, room light) and posts these events:

| Event | When |
| --- | --- |
| `.presenceChanged(snapshot)` | Someone arrives or leaves, or the proximity bucket changes |
| `.memberRecognized(id)` | A face signed a household member in (see [Who is signed in](#who-is-signed-in)) |
| `.gesture(.openPalm)` | A deliberately held open palm, when hand gestures are on |
| `.headGesture(.nod / .shake)` | AirPods head gestures while listening |
| `.motionDetected(source: "camera" or "depth")` | Frame differencing saw movement (at most every 5 s) |
| `.soundDetected(label:confidence:)` | A debounced sound alert, labels in `SoundEventLabel` |

The snapshot (`services.presence.snapshot`) carries presence, people count, proximity, smoothed distance, gaze, recognized member, ambient light, source and last activity. It is only republished when something meaningful changes, so it does not redraw the app every frame. `services.presence.isCameraSensing` says whether a camera is looking right now (the duty cycle's camera modes), so the shell reads nobody present as someone walking away only when a camera could have seen them.

## How sensing works

Sensing runs only on a HomePad (`AppRole` in HomePadCore). On the iPhone or Mac companion `start()` does nothing, so the camera and the sound classifier never run there.

### Sensing paths

| Path | Used when | What it gives |
| --- | --- | --- |
| TrueDepth face tracking (ARKit `ARFaceTrackingConfiguration`) | Someone is present on a Face ID iPad | Faces with gaze from `lookAtPoint`, up to `supportedNumberOfTrackedFaces` of them, the ARKit light estimate, and TrueDepth depth on about half the frames, which measures the distance, follows the person while ARKit loses their face, and checks liveness. Works in the dark (infrared). |
| TrueDepth depth scan (AVCapture `AVCaptureDepthDataOutput` at about 2 fps) | Nobody around and the room is dark or dim | People walking by without a visible face, from depth changes. Works in the dark. |
| Front camera (AVCapture plus Vision face and human rectangles) | Nobody around in a lit room, or iPads without TrueDepth | Faces, people, distance from face size and field of view, gaze from head pose. |
| Microphone level | Cameras are unavailable | Activity only, shown as presence at an unknown distance. |
| Simulated | `-HomePadSimulatePresence` | A scripted visitor, for the simulator. |

Why this split: ARKit face tracking runs the camera and face mesh at 30 or 60 fps no matter what, which is too costly around the clock. It therefore only runs while someone is present. The idle scan uses AVCapture at about 2 fps, picking the plain RGB stream when the room is lit and the infrared depth stream when it is dark (RGB sees nothing then). When the light level changes while scanning, the scan switches between the two. The choice lives in `BackendSelector` and is unit tested.

### Duty cycle

`DutyCyclePolicy` is a pure state machine with these modes: off, microphone only, scanning (low rate) and active (full rate).

- Active at 10 fps while anyone was seen in the last 20 seconds, scanning at 2 fps otherwise.
- `ProcessInfo.thermalState` throttles rates: fair 60 percent, serious 30 percent, critical stops the camera.
- The camera stops when `CoreSettings.cameraEnabled` is off, when another feature holds a `services.capture` claim, when the cameras are disabled, without permission, or when the app has been inactive for 3 seconds. Presence then falls back to microphone activity if the microphone is allowed.
- Analysis work scales too. Hand pose only runs with someone within 2.5 m and gestures on. Recognition embeddings only run with enrolled members, someone within 1.6 m and the face in view not decided yet (then every 30 seconds to check it is still the same member, and every 2 seconds while learning from use).

### Presence in the dark: following the person through depth

In a dark room ARKit loses a tracked face on almost half the frames, often for seconds, while the person stands still in front of the iPad and the TrueDepth depth map still shows their head. Presence, distance and the face's look therefore follow the person through the depth map too (`DepthPersonTracker`, run by `DepthSensing` in the analyzer).

- Every ARKit depth map, about 15 a second, is read into a coarse map of about 48 columns (a few thousand reads, no copy of the whole map). This costs no extra camera frames: ARKit delivers the depth anyway.
- A person is picked up only from a seed: a face ARKit tracks, projected into the image (`ARCamera.projectPoint`) and then into the depth map (`DepthRegistration`: exact from the depth's own calibration when it has one, else the image is the centered crop of the depth map, so ARKit's 16:9 image is the middle band of a 4:3 depth map), or, in the dark scan, the nearest cell of a patch of depth that moved. The seed is the nearest surface within a head's radius (12 cm). A face seed whose surface is more than 0.8 m from ARKit's own distance did not land on the face and is ignored.
- From then on the head is looked for in each map near where it was, at about the same depth. While most of the head's disk is still at the head's depth, it stays put, so it does not creep onto the body of someone standing still. A head that moved is looked for within how far a person can move between two maps (1.5 m a second, 15 to 60 cm).
- The room never starts a person, so the walls and furniture a wall-mounted iPad always sees do not count. A person standing still stays followed, since nothing has to move.
- Something right behind a person, such as a chair back within 15 cm of their head, can take their place when they leave. So a person is let go 30 s after a face on their head, or 20 cm of their own movement, last confirmed them. A face on another head (20 cm away or more) is another person.
- A face found in the depth map itself confirms them too (see [Depth identity](#depth-identity)). In a dark room ARKit finds no face, and nothing else would confirm someone sitting still.
- The followed head's depth holds presence (it never starts it, a face or movement does) and is the distance presence reports, ahead of ARKit's face anchor, because ARKit also misjudges how far a face is in the dark. It is depth along the camera axis to the face.
- Cost: while depth still follows someone who turned away, face tracking keeps running at the active rate, up to 30 s plus the duty cycle's 20 s cooldown.

#### Faces only Vision finds

Sitting with the head turned 60 to 85 degrees, a member got no ARKit face anchor at all, while Vision found their face on every sample and matched it at 0.85 to 0.92. Those faces used to count for nothing: the look ended on the next frame, and in windows of 150 samples with 126 to 147 matches the votes never got past one (11-inch traces). A face Vision finds on a frame where ARKit tracks none now counts like an ARKit face (`FaceFollower`):

- It is a face for presence and for the look.
- It seeds or confirms the depth person exactly like an ARKit face: its center goes from the upright image back to the native image, through `DepthRegistration` into the depth map, and the depth there gives its distance.
- On that depth person it starts a face track, or continues the one they have. The track then holds through the frames where Vision does not run and through ARKit's dropouts, as an ARKit face track does, so the votes add up. ARKit finding the face again, under any anchor, continues it on the same person.
- A different person still starts a new look: a face on another depth person, two faces, or a face off the followed head where the depth shows no one.
- While ARKit tracks no face, Vision looks for one at least once a second, in the same pass as the people count, not only when recognition samples. So a recognized person sitting still with their head turned keeps confirming the depth person, which used to let them go after 30 s (and the session went to Guest 30 s later). This is one face request a second, only while ARKit tracks no face.

The trace logs `face track XXXX started from a face only Vision found`.

`ARCamera.projectPoint` in landscape right should put a face where it is in the captured image. In case it is the other way round for one of the iPads' front cameras, a face that misses itself in the depth map is also tried mirrored across, mirrored up and down, and turned half way round, and a flip that alone finds the face on five depth maps in a row is used from then on (`FaceFlip`). The trace then logs `faces were found in the depth map only mirrored across, 5 maps in a row: using that from now on`, which is worth knowing: the projection would then need fixing.

The trace logs `depth person XXXX started at 0.6m from a face`, `depth person XXXX lost at 1.2m`, `depth person XXXX let go: no face or movement for 30 s` and `depth seed missed: surface 2.4m, face 0.6m`, and each frame line carries `depth person 0.6m`. A face only Vision found starts the person `from a face` too.

### Distance, proximity and light

- Depth: the depth of the head `DepthPersonTracker` follows, when it has someone. It comes first.
- ARKit: distance is the length of the face anchor's position relative to the camera.
- RGB: `distance = 0.16 m * focalLengthPixels / faceWidthPixels`, with the focal length from `activeFormat.videoFieldOfView`.
- `ProximityLevel.from(distanceMeters:)` gives the bucket, with 0.15 m hysteresis and distance smoothing so the UI does not flicker at a boundary.
- Ambient light comes from the EXIF BrightnessValue (Bv) on each frame, or the ARKit light estimate, bucketed as dark below 5 lux, dim below 50, normal below 1000 and bright above, with hysteresis. Each frame's own reading sets the bucket at once. Only the lux value is smoothed, for brightness.
- Lux from Bv: an incident light meter reads lux = 2.5 * 2^EV, with EV at ISO 100, and APEX defines EV = Bv + Sv with Sv = 5 at ISO 100. So lux = 2.5 * 2^(Bv + 5), about 80 * 2^Bv. It used to be 2.5 * 2^Bv, Bv read as if it were EV, which made every room 32 times darker than it was. In weeks of traces the 11-inch read 1.24 million face tracking frames dark, 209,000 dim and 9 normal, the M4 never read normal, neither ever used the RGB scan (which runs only in a lit room), and a room Kyle called bright read dark. With the right scale a lit room reads normal: night mode stays off in it during the schedule, auto-brightness follows the real room, and the idle scan uses the cheaper RGB camera there, as designed. The frame lines of the trace carry each frame's own reading as `lux 160`.

### Face recognition

- Up to six members (`Household.maxMembers`). Enrollment (`EnrollmentStep`, `EnrollmentSampleFilter`) takes seven steps and 24 samples in about half a minute, with a segmented progress ring and live hints: straight, each side from 15 to 45 degrees, chin up and down with some yaw for the diagonals, then sitting back where the person usually sits (0.7 to 1.1 m by TrueDepth depth, or by face size without depth), straight and turning. A sample needs one face, the step's distance and pose, and a live face on TrueDepth iPads. Quality rules skip blur (turning faster than 30 degrees a second), dark or blown out faces, and near copies of a kept sample in pose or embedding. They drop for a step after 6 s in a valid pose without a sample, so setup never stalls on them.
- Embeddings are `VNGenerateImageFeaturePrintRequest` (revision 2) feature prints of aligned face crops: square, rotated by the detected roll so the eyes are level, scaled to 192 px.
- Matching uses cosine similarity with an absolute threshold and a margin over the runner-up, then temporal voting (for example 4 of the last 7 decisions, within 4 seconds). The Relaxed, Standard and Strict presets change both.
- Sampling (`RecognitionCadence`): every 0.2 s for the first 3 s of a look and while a member's votes are building, so Standard's 4 votes take about 0.6 s. A face that keeps not matching drops to every 0.5 s. Strict always samples every 0.5 s, so its 6 votes still cover at least 2.5 s. Sampling stops once the face in view is recognized, except to learn (below) and to check it again every 30 s. A new look starts it again (see [Who is signed in](#who-is-signed-in)).
- On TrueDepth iPads every sample must pass a depth liveness check. A plane is fitted to the face's own surface in a 9 by 9 depth grid over the middle 70 percent of the face, and a real face must show at least 1.2 cm of relief. Photos and screens are flat even when tilted. A check that cannot tell, on a turned face, too little depth or no one surface, skips the sample: it neither matches nor counts as a spoof (see below). Depth comes on only some frames, so a due sample waits up to 0.5 s for a frame with depth (`RecognitionSampleGate`), and a passed check covers samples without depth for 3 s until a flat face is seen. The 1.2 cm cutoff comes from real traces: no sample under 12 mm matched, samples at 12 to 13 mm matched only 5 percent of the time, and a lower cutoff would mainly let a bent photo pass. Where the grid goes is below.
#### Liveness: where the face is in the depth map

Vision finds the face in the upright image. `DepthLiveness.evaluate(faceBox:in:depth:)` turns the box back into the camera's native buffer (`SensorFrame.nativeRect`, which undoes the rotation, whichever edge the camera is on), then into the depth map (`DepthRegistration`):

- With ARKit, from both pinhole models: the image's from `ARCamera.intrinsics`, the depth's from its own `cameraCalibrationData` when it has some. Without calibration, the image is the centered crop of the depth map with the image's aspect ratio. ARKit's face tracking image is 1280x720 on both iPads, so over a 4:3 depth map it is the middle three quarters of the height.
- AVCapture depth (enrollment, the dark scan) matches its video, so it is read one to one when the aspect ratios match.

The grid used to be read at the image's normalized coordinates, right only when image and depth cover the same view. Night traces showed it was not on the face. On the M4, 956 of 2,198 samples with depth failed the check, 78 percent in the dark and 39 percent in dim light. The failing samples had depth on a median of 33 percent of the grid (332 had almost none) against 100 percent for passing ones, so the grid was mostly beside the face, on a dark room with no depth. The failures followed the side the face was turned to: 70 to 82 percent of samples with Vision yaw from -50 to -80 degrees failed, and 0 to 2 percent from 0 to +40. On the 11-inch, profile samples passed with reliefs of 0.5 to 1.8 m, the face and the wall behind it together. A grid reading a bent photo and the wall behind it would have passed the same way.

#### Liveness: relief on the face's own surface

The grid reads more than the face. In an 11-inch iPad's traces, faces facing the iPad (Vision yaw under 30 degrees) at under 0.9 m read a median relief of 89 mm and 1,245 mm at the 75th percentile: the wall behind the face, and that passed as live. A photo held in front of a farther wall would have passed the same way. Faces turned 45 degrees or more read 9.1, 12.0 and 14.6 mm at the 10th, 50th and 75th percentiles (16,317 samples), a coin flip against the 12 mm cutoff, so half of Kyle's samples as he sat voted spoof. The flat share rose with the turn: 1.5 percent at 0 to 14 degrees, 8 at 15 to 29, 25 at 30 to 44, 46 to 49 at 45 to 89 and 98 past 90. The side of a turned head is close to flat.

So `DepthLiveness` now measures relief only on the face's own surface: the nearest run of the grid's depths, taken in depth order, with no step of more than 4 cm, that covers at least 40 percent of the grid. A face's depths run on without such a step, and the wall behind it does not, so it is left out. A smaller nearer run, such as a hand, is passed over. A photo, its own surface, is flat whatever is behind it: in front of a far wall, the photo or the wall is the surface, and both are flat. The verdict is one of three:

- live: the face's surface shows 12 mm of relief or more.
- flat: it shows less, on a face facing the iPad (under 30 degrees). That is a spoof vote, as before.
- unsure: too little depth (under half the grid), no one surface covering 40 percent, or flat on a face turned 30 degrees or more. The sample is skipped: no match vote, no spoof vote. It also ends the cover a passed check gives samples without depth, as a flat face does. Skipping is safe, since an unsure sample can never make a match.

30 degrees, not 45: the flat share triples from the 15 to 29 band to the 30 to 44 band. The old check let a photo pass whenever its grid also caught the wall behind it, and that is closed. What 9 by 9 samples cannot tell from a nose is a step of under 4 cm: a photo cut to the outline of the face and held 1 to 4 cm in front of a wall, with the grid crossing its edge, could still read relief. A grid inside the photo reads flat.

The trace shows where the grid read: each sample line says `live relief 22mm valid 1.00 face 0.95 at 0.58m`, with `face` the share of the grid on the face's own surface and `at` its median depth, to compare with `depth person 0.6m` on the frame lines. A skipped one reads `sample skipped: unsure (turned 72 degrees) relief 8mm valid 1.00 face 1.00 at 0.65m pose yaw -72 pitch -19`. The alignment is logged when it changes, each time face tracking starts and every hour, so a trace that keeps only its newest part still has it: `depth map 640x480 for image 1280x720, calibration no, x 1.00+0.00 y 0.75+0.13, focal 520 px`. A sample that fails, other than a turned face reading flat, is followed by `liveness grid check: registered valid 0.33 relief 5mm at 2.10m, one to one valid ..., mirrored across ..., mirrored up-down ..., face 0.60m`, the same grid read through the old and two mirrored mappings. If failures remain on a face, the mapping that reads valid near 1.00 at the face's distance is the right one.

- Models load at launch on a queue of their own with requests of their own (`FrameAnalyzer.warmUpModels`), while frames go on. Face, people and hand detection start on the CPU (`VisionDetectors.runOnCPU`), because after a cold boot the Neural Engine took 41 s to load face detection on the 11-inch (0.35 s on later launches), and the CPU does not wait for it. The warm-up loads the feature print first (under 2 s even after a cold boot), and recognition starts then (`recognition ready` in the trace). Then it loads hand pose, and face and people detection for the Neural Engine, and the analyzer moves its detectors there, which uses less power for an always-on display (`vision warm-up took` gives each model's time). Until the feature print has loaded, samples and hand pose wait (`recognition waits for its models`), `PresenceService.isRecognitionStarting` is true, and the people button and a face's profile dot show a turning ring, with a note in the People menu that HomePad shows guest content until then. Before this, the whole load ran on the analysis queue, and after a cold boot the camera's first frame waited 73 s for it, with no presence, distance or recognition.
- Templates are JSON files in `Application Support/HomePadPresence/FaceTemplates`, written with complete file protection, in a folder excluded from backups. They never go to iCloud. They are deleted when a member is removed from the household or from the settings pane. Learned samples live in `FaceTemplates/Learned/<member>.json` and depth templates in `FaceTemplates/Depth/<member>.json`, with the same protection.

#### Depth identity

The camera and depth recognize together: until one of them names the face in view, both vote, and whichever is sure first names it. In a dark room the camera can tell no one apart, and depth, the dot projector, needs no light. ARKit finds no face in the dark either (none in 478 frames with the owner looking at the iPad from 0.5 m in 3 lux), so depth works from the depth map alone.

The pipeline, per TrueDepth frame while a person is followed (`DepthFaceSampler`):

1. **Where the face is** (`DepthFaceDetector`): the depth map is drawn as a lit surface, a grayscale picture of its shape lit from the camera and a little from above, and Vision's face detector runs on it. The face is looked for only in the box it finds, or in its last box for a second while it misses a map.
2. **The face** (`DepthFaceFinder`): in the box, the face's own surface is what connects to a point near the box's center, at the depth of its middle third, through neighbors 2 pixels apart with no depth step over 2.5 cm, so a hand in front of the face or the wall behind it is not part of it. The nose tip is the nearest few millimeters of that surface, and the face is the surface within 9 cm of it, up to 2,000 points, the nose tip at the origin, turned upright (see [Which way is up](#which-way-is-up)). It must fall away behind the nose by 1.2 to 6 cm at the median and cover half of the disc within 5 cm of it, seen from the camera. A photo, a wall or a chair back does not.
3. **Merging** (`DepthFaceFusion`): iOS does not smooth this depth (`isDepthDataFiltered` is false); a face at half a meter falls on a few thousand of the dot projector's dots, each measured with some noise. So a signature merges the faces found in the last 3 s, 3 to 4 of them, lined up with the newest, on a 3 mm grid. Face tracking gives about 4 depth maps a second in the dark and about 6 in light.
4. **Comparing** (`DepthSignature`, `DepthAlignment`): one face's points are lined up with another's surface, nose tips together first, then each round matches every point to the surface straight behind or in front of it and solves for the small turn and shift that bring the closest 70 percent nearer the surface's tangent planes. The distance is the root mean square of the closest 85 percent, in millimeters: it keeps more than the alignment uses, so the nose, which sets faces apart most, stays in. Faces that overlap less than 60 percent, or had to turn more than 30 degrees, do not compare.

Each depth face found also confirms the followed person, so someone sitting still in the dark stays present.

- **Templates** (`DepthIdentityEvaluator`): a member's own signatures, kept while the camera has named them on the look and the room is not dark: up to 3 per face track, 10 s apart, 20 per member, the oldest rolling out. Depth's own naming never keeps one, so depth cannot teach itself. They are face data, stored like the face templates in `FaceTemplates/Depth/<member>.json`, deleted and moved with the member, and cleared by setting the face up again and by Reset Learned Looks. Templates of another signature version do not load.
- **Setting a face up** ends with a depth step on TrueDepth iPads (`EnrollmentSession.learnDepth`): with setup's camera released, face tracking recognizes the member and keeps a template every second, up to 6 on the look, until there are 3 or 45 s have passed (Skip finishes at once). Setup's own camera reports a focal length several percent apart from face tracking's on some iPads, the 11-inch 3rd generation among them (ZEISS, arXiv 2201.10865), so its depth is not used.
- **A limit per member** (`DepthCalibration`), from 3 templates or more. With templates from several sittings (more than 10 minutes apart), each is compared with the other sittings' and the limit is 1.25 times the 95th percentile of those distances. With one sitting it is twice the largest distance among its templates, at least 1 mm. It is never more than 1.5 mm.
- **Voting** (`DepthVoter`): while no one is named, a signature comes with every face found, and each votes for the member it came under the limit of, with every other member at least 1.25 times farther, or for no one. 3 of the last 4 name the member, as recognized, not verified, so Face ID is still needed for anything sensitive. A camera stranger verdict on the look stops depth's votes. Votes go with the look, and a score worked out for a face that has since left is dropped.
- **The look in the dark**: when it is too dark for the camera (the room reads dark, or a camera sample was too dark to tell in the last 5 s), the look belongs to the person depth follows, whichever of the camera or the depth map saw the face, and a depth face found on them stays in view for 10 s.
- **Angles**: templates from one sitting tend to share one angle, and faces at other angles read farther from them. More sittings, sitting in more ways, give more to match.
- **Not known yet**: how close another person's face comes. With one enrolled member there are no `others`, so only visits by other people show it. Until then the limit rests on the member's own faces and the 1.5 mm ceiling.

##### Reading the trace

```
depth face at 0.58m, 694 points, relief 2.5 cm, coverage 0.95
depth face not found: no face in the lit depth
depth face searches in 10 s: 31 found, 4 with no face box, 2 with no face in the box
depth identity unnamed face, light dark, expression -: others 1.10mm nearest of 20 (Kyle)
depth identity Kyle, light normal, expression 0.14: own 0.90mm nearest of 5, no others
depth template added for Kyle, 6 of 20
depth calibration 841E: 6 templates from 1 visit, match under 1.50 mm
depth vote: Kyle 1.00 mm, under the 1.50 mm limit
recognized Kyle by depth: 3 of the last 3 depth signatures under its limit
```

`own` is how far a face is from the member's nearest template from another visit, `others` from the nearest template of anyone else. Smaller is more alike. Nothing of a signature or a template is ever written to a trace or a log.

#### Which way is up

Frames are turned upright by the rotation coordinator's angle, which is for AVCapture's native buffer, and ARKit's image does not always share that layout: on the 11-inch on a stand in landscape the coordinator said 180, and Vision found faces in the turned frames at a roll of -122 to -170 degrees. So faces decide (`UprightCalibration`): the last 5 rolls of faces Vision found are averaged as angles, and when they agree and the average rounds to a quarter turn other than none, that turn is added for the backend and orientation, kept in the settings and logged (`depth of faceTracking turned 2 more quarter turns to stand upright`). The camera's image and the depth map learn apart, the image from faces in the image and the depth map from faces in the lit depth, since face tracking's depth map is not laid out like its image. It works for any iPad, wherever its camera sits.

#### Seeing what the sensors see

Settings, Presence & Privacy, Show What the Sensors See puts a panel on the face screen: the camera's picture with the faces ARKit or Vision found, the depth map (near in red, far in blue) with the followed head, the nose tip the depth face was found at and its 9 cm reach, the depth face itself at full resolution, colored from its nose tip to 8 cm behind it (what the depth signature compares: the room picture spreads its colors over 2.2 m, so a face's few centimeters of shape barely show there), and a line per stage: the backend and light, the camera's faces, the depth person, the depth face, the last recognition sample (with its crop's brightness), the last depth identity score, and the session. It is drawn four times a second while on, takes no touches, and lives in memory only: nothing of it is saved, traced or sent anywhere.

#### Each HomePad learns each person itself

Paired HomePads share the household's people, with the same IDs, so a person's Home Screen and faces follow them (see "The household's setup" in the Connect README). Face data never does: templates, embeddings, learned looks and enrollment samples stay on the iPad that made them and are never sent over the peer link or anywhere else.

- Whether a person is set up here is this iPad's own (`HouseholdMember.hasFaceEnrollment`, kept when people arrive from another HomePad, and set from this iPad's templates by `reconcile(with:)`).
- Someone added on another HomePad shows "Not set up on this HomePad yet" with Set Up in Face Recognition, "Face recognition not set up on this HomePad" in People, and Settings > Devices & Sharing names everyone still to set up here.
- Someone removed on any HomePad is removed on every one, and each deletes its own face data for them.
- When this HomePad joins a household that already has a person under another ID (matched by name), their face data here moves to that ID before the person changes (`FaceRecognitionService.moveMember`, `FaceTemplateStore.move`, from `Household.onMemberIDChange`). The files are rewritten under the new ID in the same protected folder and the old ones deleted, so recognition keeps working for them and nothing is cleaned up as a removed person's. Templates are unreadable while the iPad is locked, so a join then cannot move them, and the pane says to set up that face again.

#### Learning from use

Like Face ID, recognition keeps learning how each member looks (`FaceRecognitionService+Learning`). It covers looks enrollment cannot, such as sitting at an angle or 0.7 to 0.9 m away in a dark room, where scores otherwise sit just under Standard's 0.82.

- It learns only on one unbroken face track (`FaceTrackContinuity`) that began with a confirmed recognition (`FaceLearningSession`). A track is exactly one face, an ARKit face anchor or a face only Vision found on a depth person, checked on every ARKit frame. In a dark room ARKit drops the face on about half the frames while the TrueDepth sensor still sees the head, so a dropout keeps the track in two cases: the same anchor back within 0.5 s and within 15 cm of where it was lost, or, for up to 30 s, the depth person tracker following the same person without a break and the face coming back on their head, under any anchor. Anything else ends it: a longer dropout, a face back somewhere else, a second face, or a different anchor without a dropout. Learning then waits for the next confirmed recognition, whose votes must all come from the new track. A track on which two members matched is never learned from. The RGB path never learns.
- A sample is kept (`FaceLearningPolicy`) when Vision sees exactly one face, it passed its own depth check with face shaped relief (12 to 40 mm, at least 90 percent of the face with depth), it scores at least 0.70 against the member's enrolled embeddings, below 0.90 against everything stored for them, and beats every other member by the matcher's margin. The floor uses enrolled embeddings only, so learning cannot drift one small step at a time.
- At most one sample every 6 s, 5 per track and 5 minutes of sampling per track. 20 per member, the oldest roll out. Samples taken only to learn never vote.
- Matching uses enrolled and learned embeddings together with the same threshold, margin and votes.
- Re-enrolling, Delete Face Data and Reset Learned Looks in Settings clear them, and the depth templates too. The enrolled template file is never rewritten by learning.
- The trace logs `learning started for NAME`, `learned sample for NAME score S relief R, N learned`, why a sample was skipped, and `learning stopped: the face track ended`.
- `CoreSettings.faceRecognitionEnabled` turns the whole feature off.

**Accuracy, honestly.** iOS has no public face identity API. Vision feature prints describe whole images, not identities. They will separate most household members in good light at arm's length, but they are sensitive to lighting, glasses, hair and expression, and can confuse siblings or a parent and child. Expect false rejections that need a second look, and occasional false accepts between similar-looking people. Do not use face recognition for anything sensitive: keep locks, payments and admin settings behind Face ID. The thresholds were chosen from synthetic tests and must be tuned on the real iPads with the Live Status section.

**Open-source models considered.** A bundled open-source face embedding model is welcome if it is clearly better and its license allows it. InsightFace's code is MIT, but its README states its pretrained models are for non-commercial research only. EdgeFace's repository is BSD 3-Clause, but its weights come from training on research-only face datasets, and converting it to Core ML needs coremltools, which this build machine does not have. Nothing cleared both bars, so the module uses Vision feature prints. The embedder sits behind one type (`FaceEmbedder`), so a Core ML model can replace it later without touching matching, voting or storage.

### Gestures

- Hand gestures (`CoreSettings.handGesturesEnabled`): Vision hand pose, and the open palm is the only hand gesture. The palm must be deliberate (`HandGestureRecognizer`): at least three fingers visible and every visible one straight, pointing up within about 45 degrees (up is learned from open hands, since one iPad delivers its image upside down), a wrist to fingertip span of at least 12 percent of the image, and held still (drifting under 6 percent) in at least 75 percent of the frames of a 0.8 s hold. It fires once per hold, with a 1 s cooldown. Hand pose only runs with someone within 2.5 m. Presence only posts `.gesture(.openPalm)`. The shell and Kitchen decide what it does: stop a ringing timer, else pause or resume the music when `CoreSettings.palmControlsMusic` is on (off by default, Palm Plays and Pauses Music in Settings) and the assistant is idle. The palm never stops the assistant: a hand resting near the face fired every few seconds and closed answers half said. A tap or saying "stop" does that.
- AirPods head gestures (`CMHeadphoneMotionManager`): connection status is watched all the time. Motion runs only while listening, which starts when the assistant is speaking or when another module posts `HomePadEvent.listenForHeadGestures(seconds:)`. A nod is two pitch reversals of at least 9 degrees within 1.5 s, a shake is three yaw reversals of at least 12 degrees, and the other axis must stay comparatively still.

### Sound alerts

- Apple's built-in classifier (`SNClassifySoundRequest(classifierIdentifier: .version1)`), fed from the shared `services.microphone` tap on a private queue.
- Label mapping, checked against the SDK's 303 `knownClassifications`:

| Alert | SDK labels | Posted label |
| --- | --- | --- |
| Smoke or CO alarm | `smoke_detector` | `smoke_alarm` |
| Doorbell | `door_bell` | `doorbell` |
| Knocking | `knock` | `knock` |
| Dog barking | `dog_bark`, `dog_bow_wow` | `dog_bark` |
| Baby crying | `baby_crying` | `baby_crying` |
| Glass breaking | `glass_breaking` | `glass_breaking` |
| Siren | `siren`, `ambulance_siren`, `police_siren`, `fire_engine_siren`, `civil_defense_siren` | `siren` |

- There is no carbon monoxide label and no fire alarm label in the SDK (`fire` means crackling flames). CO alarms will register as `smoke_detector` at best.
- Debouncing: sustained sounds need two hits within 3 s, sharp sounds one. Each kind then stays quiet for its cooldown (60 s for alarms).
- Smoke alarms raise a full-screen red alert with a Dismiss button and post `.wake`. Other sounds show a short glass banner.
- Gated on `CoreSettings.soundAlertsEnabled`, `CoreSettings.microphoneEnabled` and microphone permission.

### Mirror app

App id `mirror`. The front camera full screen with an edge ring light (Off, Low, Medium, High in Warm, Neutral or Cool) and a close-up or full-body view, like HomeView's Mirror. It raises screen brightness while the light is on, claims the camera through `services.capture` (so the presence sensor yields) and releases it on close.

- Where the front camera has Center Stage (a format with `isCenterStageSupported`, moving to one if the current format lacks it), a Close-Up and Full Body switch sits bottom left, one glass capsule as tall as the round ring light button. Close-Up turns Center Stage on so it keeps the person framed as they move, and Full Body turns it off for the camera's whole view.
- The Mirror runs Center Stage in cooperative mode (`AVCaptureDevice.centerStageControlMode = .cooperative`), so the Center Stage toggle in Control Center still works, and the switch follows it. On close it turns Center Stage off under the app's control (`.app`), because presence sensing judges distance from a face's size in a fixed view.
- Without Center Stage, as in the simulator, the switch is hidden and a 2× or 1× zoom button stands in. Both use the same setting, `presence.mirror.framing`.
- Mirror looks the same in Light and Dark, like the Camera app: the camera on black, with dark glass controls. So does the full-screen alarm, white on red. The Presence & Privacy pane and face setup follow the Appearance setting.

## Who is signed in

One state machine decides whose profile shows: `MemberSession` in HomePadCore, a pure reducer with injected time that `Household` owns. Recognition tells it what the camera sees (`household.noteCamera`), the kiosk reports touches (`noteActivity`) and ticks it once a second (`expireIfNeeded`), the People menu picks people (`select`, `signOut`), and Face ID and personal devices verify them (`recognize`). Nothing else keeps a timer for the session. Every module still reads only `activeMember` and `isPersonalContentUnlocked`.

### States

| State | Home Screen | Personal content | Starts with |
| --- | --- | --- | --- |
| Guest | Guest's | Hidden | Launch, a timeout, a confident stranger, Guest in the People menu |
| Picked | The member's | Locked | A pick in the People menu |
| Recognized | The member's | Unlocked | The camera recognizing the member |
| Verified | The member's | Unlocked | Face ID, or approval on the member's personal device |

Every session but a plain Guest has an owner, the person the camera should see. For Recognized and Verified that is the member. For a pick, or Guest chosen by hand, it is whoever chose: the face the camera named at that moment, or that face once the camera names it.

### What the camera reports

`CameraView` is one of: not watching (camera off or paused, face recognition off, or nobody set up), nobody, no face (someone is there but no face is in view), or a face, with its look and what recognition decided about it: undecided, a member, or a stranger.

A look is one unbroken view of one face (`FaceLookTracker`). With ARKit face tracking it is one face track (`FaceTrackContinuity`), which holds through a dropout of up to 0.5 s with the face back in place, and through one of up to 30 s while the depth shows the same person is still there (see [Presence in the dark](#presence-in-the-dark-following-the-person-through-depth)). So in a dark room recognition's votes keep building, and a recognized person stays recognized while ARKit loses and finds their face. During such a dropout the camera still reports their face, so their profile does not time out. Anything else starts a new look: a longer dropout, a second face, or a new anchor without the depth to vouch for it. A face only Vision finds, with ARKit tracking none, is a face track of its own on the depth person it lies on (see [Faces only Vision finds](#faces-only-vision-finds)). The trace logs `face back after 4.2 s, on the same depth person: the look goes on`. With several faces in view, or on the RGB path, a look lasts while some face stays in view. Recognition decides about every look from scratch, with fresh votes, its own stranger run and its own liveness carry, at the fast rate of a first look. Once it has decided, it checks again every 30 s, in case the face tracker kept one track across two people.

### Rules

| Event | What happens |
| --- | --- |
| The owner's face is recognized | The owner is detected. Nothing else changes. |
| Another member's face is recognized | That member is signed in at once (Recognized). The member whose Home Screen was picked by hand is upgraded the same way. |
| A face is confidently a stranger | Guest at once, unless the owner is a stranger too (a guest who picked by hand). |
| A face is undecided | Nothing moves. The owner is not detected, so the timeout runs, and touches do not count. A blurry frame, a bad angle or a dark room can only delay a decision, never sign anyone out. |
| No face in view, or nobody | The timeout runs. Touches count. |
| The camera is not watching | Touches decide alone. |
| A touch | Counts as detecting the owner while no face is in view, the camera is not watching, or the face in view is the owner's. With any other face in view it counts for nothing. |
| A member picked in the People menu | Picked, owned by the chooser. The chooser looking away and back keeps it. Picking yourself while the camera knows you signs you in (Recognized). Picking the member already shown changes nothing. |
| Guest picked in the People menu | Guest, owned by the chooser, so their own face does not sign them back in until they have been gone for the timeout. Anyone else confidently seen ends that hold. |
| Face ID or a personal device | Verified. The face in view then, or the next face within 10 s if none was, counts as the member for as long as that look lasts, whatever recognition says about it. |
| Timeout | The owner has not been detected for Switch to Guest After: plain Guest. |
| The member leaves the household | Plain Guest, if the session was theirs. |

Picks and Face ID follow the same timeout as faces. Of the debug launches, screens pinned by navigation arguments (`-HomePadShowHome` and the like) never time out, and `-HomePadRecognize` sets 24 hours.

### Several faces

The session follows the nearest face, the largest one, which is the face recognition samples. With two or more faces in view there is no single face track, so they are one look while they stay. Another member winning the votes on the nearest face takes over. A stranger verdict needs exactly one face in view, so a guest standing beside a member never signs the member out.

### What counts as confident

- **Another member:** the existing voter on this look, for example Standard's 4 of the last 7 samples within 4 s, at least twice any rival. A face that steps in front takes over about 0.6 s after its first sample, as fast as a first recognition.
- **A stranger** (`StrangerVerdict`): 4 clean samples in a row, each scoring under 0.55 against every enrolled and learned embedding of every member, within 6 s. Clean is the bar learning from use already sets: exactly one face in view, and the sample's own depth check passed with face shaped relief (12 to 40 mm) over at least 90 percent of the face. Unclean samples are skipped without breaking the run. A match, a flat face or any score of 0.55 or more starts it over. On the RGB path no sample has depth, so no sample is clean, and only another member or the timeout ends a session there.
- **Why these numbers.** Feature prints score a household member low too. A member's own samples went as low as 0.49, and up to 17 in a row under 0.60, mostly in the dark at 0.7 to 1 m. Of the 10,331 samples with face shaped relief from visits where the member was recognized, none was under 0.50, seven were under 0.55 and never two in a row. Four in a row leaves a wide margin.
- **Honest limit.** The traces hold no real strangers. A stranger may well score above 0.55 against a member, and then their face stays undecided: it cannot keep the member's profile alive (their touches do not count), and the profile ends one timeout after the member was last seen. Each sample line in the trace ends with `stranger k of 4` while a run builds, so the cutoff can be tuned from a test with a visitor.

### The timeout

Settings > Presence & Privacy > Profiles > Switch to Guest After: 10 s, 30 s (the default), 1 min, 2 min or 5 min (`CoreSettings.signOutAfter`). It counts from the moment the owner was last detected, which is when their face left view, not when presence ends.

Why 30 s: in the traces of an 11-inch iPad in daily use, recognizing a face took 0.60 s at the median, 2.0 s at the 90th percentile and at most 12.7 s (233 recognitions). Looking away and back starts a new look, which is identified just as fast, so 30 s rides out the slowest one more than twice. 10 s would sign him out during about 1 in 100 of them. Longer choices suit a kitchen, where a face is often out of view.

### Why it used to take so long

From the presence and kiosk traces of an 11-inch iPad in daily use (about 160 launches and 460 visits) and the code before this change:

- The profile never timed out. `Household.expireIfNeeded` only relocked personal content, and the Home Screen stayed the member's until someone else was recognized or picked by hand.
- Personal content relocked 120 s after the last recognition refresh or touch. The refresh ran every 30 s while the face kept matching, so content stayed unlocked 90 to 120 s after the person left, and any touch, by anyone, restarted the 120 s.
- A different face never ended anything. Once a member was confirmed, sampling stopped except for the 30 s refresh and learning, the end of presence did not touch the household, and a stranger's refresh samples simply failed to confirm anyone.
- Presence outlived the face. It ended a median 4.6 s after the last face, but 15.6 s at the 75th percentile and 52 s at the 90th, since bodies and depth hold it. The timeout now starts when the face leaves.

The kiosk trace (`-HomePadPresenceTrace YES`) logs each change of session, owner and camera view, and the presence trace logs `camera view ..., session ...` each time recognition reports.

## Settings

Settings > Presence & Privacy (pane id `presence`) is a grouped Form:

- Permission callouts that explain camera and microphone use before the system prompt, or link to Settings after a denial.
- Presence Sensing: Camera, Use Face ID Camera, Sensitivity (Low, Medium, High), Share Motion With Faces.
- Gestures: Hand Gestures, AirPods Head Gestures with connection status.
- Face Recognition: on or off, Match (Relaxed, Standard, Strict), per-member Set Up, Set Up Again, Reset Learned Looks (with the count of learned looks) and Delete Face Data. A person not set up yet reads "Not set up on this HomePad yet", since people come from the household's other HomePads but face data does not.
- Profiles: Switch to Guest After (10 s, 30 s, 1 min, 2 min, 5 min), how long a person's profile stays once they are no longer detected (`CoreSettings.signOutAfter`).
- Sound Alerts: on or off, Sensitivity, which sounds alert, and a test button.
- Live Status: duty cycle, sensor, source, distance, proximity, gaze, people, ambient light, recognized member, last match score, frame rate, thermal state, last gesture and last sound.

Module keys are `presence.*` in `PresenceSettings`. Shared switches stay in `CoreSettings`.

## Simulator and debug launch arguments

```
-HomePadSimulatePresence                 cycle nobody, far, mid, near and back (8 s each)
-HomePadSimulatePresence near            hold one level: nobody, far, mid or near
-HomePadSimulateSound smoke_alarm        fire a sound alert 3 s after launch (any posted label)
-HomePadSettingsPane presence            (shell) open Settings on Presence & Privacy
-HomePadPresencePane status              with it, scroll the pane to Live Status
-HomePadPresencePane enroll              with it, run enrollment for the first member (adds a demo member if none)
-HomePadPresenceTrace YES                write Documents/presence-trace.txt: frames, samples, backend switches,
                                         and the recognition timeline (first face, first sample, recognized after).
                                         Hand lines come once a second at most. The file keeps its newest
                                         32 MB once it passes 64 MB (DebugTrace in HomePadCore)
-HomePadOpenApp mirror                   (shell) open the Mirror app
-PresenceMirrorCenterStage YES           show the Close-Up and Full Body switch in the simulator (debug builds)
```

In simulated mode, enrollment uses a scripted face with synthetic embeddings, and the simulated visitor matches the first enrolled member, so recognition, voting and `.memberRecognized` run end to end. Verified in the simulator: the cycling visitor drives the shell's proximity, enrollment completes, Live Status shows the member recognized with a match score, the smoke alarm takeover and the proximity-aware banners render, and the Mirror shows its ring light with a placeholder preview.

## Structure

```
PresenceModule.swift      Registration: service, Mirror app, settings pane, alert overlay, assistant tool
Settings/                 Setting keys and curated choices (sensitivity, strictness, ring light)
Sensing/                  Pure logic: duty cycle, backend selection, fusion, proximity, light, gaze
Analysis/                 Per-frame pipeline: Vision detectors, motion, depth maps and their registration
                          to the image, the depth person tracker, face track continuity, frame analyzer
Camera/                   Shared AVCaptureSession wrapper and orientation tracking
Backends/                 Face tracking (ARKit), capture (RGB or depth), simulated
Service/                  LivePresenceService, conditions, coordinator, diagnostics, mic fallback, tools
Recognition/              Embedder, matcher, voter, liveness and its grid, template store, looks, stranger
                          verdict, depth identity evaluation, recognition service
Enrollment/               Enrollment steps, session and capture sources
Gestures/                 Hand and head gesture recognizers, AirPods service
Sound/                    Sound kinds, debouncer, classifier, sound alert service
Simulation/               Launch options, scripted visitor, synthetic embeddings
Views/                    Mirror, settings pane, enrollment, alert overlay (shared pieces such as
                          CameraPreview, GlassBanner, PermissionPrompt and SegmentedProgressRing
                          come from HomePadUI)
```

Tests (Swift Testing) cover distance and proximity math, fusion, depth registration, the liveness grid landing on a synthetic face in a 4:3 depth map under a 16:9 image in all four buffer orientations (and the old one to one reading missing it), relief on the face's own surface (a photo before a far wall, a profile face, a frontal face with the wall beside it, a turned face that reads flat), faces only Vision finds keeping one look and the depth person, following a person through synthetic depth maps (standing still, walking closer, leaving, a static object let go, a second face), face tracks held by depth, the duty-cycle state machine, backend selection, matching, voting, liveness, the recognition cadence and depth wait, face track continuity, learning from use (start rule, floors, cap, other members, persistence and reset), the stranger verdict and handing the session to a new face, depth signatures, their scores and the template policy, depth templates stored, deleted and moved with the member and kept out of backups, the enrollment steps and sample filter, nod and shake traces, hand gestures, sound debouncing, motion differencing, launch arguments, and a person's face data moving to the household's ID for them.

## Core additions

`HomePadCore/Extensions/Presence/PresenceEventVocabulary.swift` adds `SoundEventLabel` (posted sound labels) and `PresenceRequest` with `HomePadEvent.listenForHeadGestures(seconds:)` and `HomePadEvent.requestPresencePermissions`, so other modules can talk to Presence without importing it.

## Needs real-device verification

- ARKit face tracking: distance accuracy, gaze (`lookAtPoint` cast onto the screen plane, 0.3 m radius), the number of tracked faces, and that the slowest video format is chosen.
- `AVCaptureDevice.RotationCoordinator` orientation for Vision on both iPad Pro sizes (landscape front camera), including face crops and which way is up for the open palm.
- TrueDepth depth scan: frame rate floor of the depth formats, depth range for people walking past, false motion from depth holes, power draw at 2 fps over a day.
- The liveness grid on the face on both iPads, in the dark and in light, from the `depth map ... for image ...` line, `at 0.58m` against the face's distance, and how often `flat` still appears (it should be rare on a real face, as on the 11-inch).
- Following a person through depth in the dark on both iPads: that `ARCamera.projectPoint` in landscape right lands the face on the face in the depth map (`depth seed missed` lines say it did not), that a person standing still stays followed, and that someone leaving is lost rather than replaced by the wall or chair behind them.
- The RGB distance constant (0.16 m face width) against a tape measure.
- EXIF BrightnessValue to lux mapping, and the ARKit intensity fallback, against a lux meter or the iPad's auto-brightness.
- Depth identity: whether the depth map's face separates household members and strangers at all (the evaluation above), in the dark as in light, and whether the finder's nose tip lands on the nose when the head is turned or a hand is near the face.
- Face recognition thresholds for the household, liveness relief against printed photos and a phone screen, and template protection while the iPad is locked.
- Hand gesture reliability at 1 to 2.5 m, and head gesture axes on real AirPods (pitch for nodding, yaw for shaking).
- Sound classification of the actual smoke and CO alarms and doorbell in the home.
- Thermal behavior and battery or heat over 24 hours on the stand.
- Mirror ring light brightness and zoom levels on the ultra wide front camera, Close-Up and Full Body with Center Stage (which format it picks, how tight Close-Up frames from across the room), the Control Center toggle, and that presence distance is unchanged after closing Mirror.

## Known gaps

- Recognition uses general image feature prints, not a face identity model (see Accuracy).
- Gaze on the RGB path is head pose only (face turned toward the screen), not eye gaze.
- Presence pauses while the app is inactive. iOS does not allow camera capture in the background.
- Template files are unreadable while the iPad is locked (complete protection). They are reloaded when protected data becomes available again.
