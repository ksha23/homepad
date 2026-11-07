# App zoom

How an app opens out of its Home Screen icon and closes back into it.

## The reference

The numbers come from 60 fps recordings of the iPadOS simulator's own Home Screen opening Calendar from the dock and closing an app into its icon, measured frame by frame.

- The window keeps the screen's shape (0.74 to 0.75 width over height) and stays fully opaque the whole way. Its corners are rounded at about 37 to 45 points on screen, easing off only as an opening app comes to rest.
- The home indicator is part of the window and shrinks and moves with it.
- The window turns into the icon only at the very end. From about twice the icon's size, in about four frames, its shape becomes the icon's square and the icon's picture cross-dissolves in. From there it is the icon's picture shrinking onto the icon, and nothing fades out afterwards.
- An open reaches 96 percent in about 0.27 seconds and settles by about 0.5. Scale and position move together on one spring, which reads as the screen zooming into the icon.
- During a swipe up the window's bottom edge stays under the finger and the window shrinks the higher it goes. Letting go carries the finger's speed into the spring.

## What is built

The zoom animates a picture of the app, not the live app, the way iPadOS does.

- `ZoomAnimator` draws in `ZoomOverlay`, a UIKit layer above the open app. A pose is only a window size and place, a rounded clip with continuous corners, the picture's scale and the icon picture's square and opacity, and Core Animation draws that. Nothing in the app is drawn again for the zoom.
- Closing takes a picture of the screen exactly as shown (`snapshotView(afterScreenUpdates: false)`), so the window that shrinks is the app with its margin and home bar. The live app goes away at once and the picture lands in the icon.
- A swipe up takes the picture on its first move and hides the live app. The finger sets the window's pose (`AppZoomGeometry.dragPose`). Letting go springs it into the icon or back to full screen, and back at full screen the live app shows again under it.
- Opening grows the picture the app had when it was last closed, or a plain page in the app's own color the first time, like an iPadOS launch screen. A suspended app rejoins the window as the open starts, hidden under the zoom, so it is live the moment the window lands, and the picture goes a frame later. An app built from nothing waits until the window is full screen, since building it takes the main thread for a moment and behind a still picture the moment shows nothing. Its picture goes three frames after it has drawn.
- Apps stay suspended after they close, like iPadOS apps. The last few apps opened each live in a UIKit host of their own (`SuspendableHost`), and only the one on screen is in the window. A closed app's view leaves the window, so everything in it is told it disappeared and stops its cameras, audio and polling, while its state stays in the host. Reopened, it joins the window again as it was left, under the picture of it the close kept. The suspended apps and their pictures are dropped when another person takes over the screen. Each host is compared by what it shows (`SuspendableHost`, with `.equatable()`), so a screen change hands an app's content to its host again only when the app joins or leaves the window or the environment changes.
- The live app is hidden, or not yet built, only while the picture stands in for it. Whenever the picture goes, by whichever path, the app shows again (`ZoomAnimator.onEnd`). A swipe Home once left it hidden, so the next app opened invisible over a Home Screen that took no touches.
- A swipe the system takes over (its own Home gesture) never reaches the drag's end. The home bar notices the drag stop and springs a window still held by the finger back to full screen.
- A spring is SwiftUI's `Spring` worked out up front at 120 poses a second and handed to the overlay as Core Animation keyframes, so the render server moves the window at the screen's rate whatever the main thread is doing. It ends once the window stays within half a point of its target. A spring that takes over another starts from the pose and speed the old one had at that moment. A finger sets the pose directly.
- An app grows out of what was touched to open it and closes back into it: an icon on the Home Screen or in the app grid, a widget on the Home Screen or a face, or a timer or Now Playing pill. Each of these reports where it is and its shape (HomePadUI's `zoomSource(_:shape:)`, a `ZoomSource`). When an app opens, the navigator takes the smallest source under the touch that went down a moment before (`zoomOrigin(opening:as:)`), so it does not matter whether a button, an event a module posted or a redirect opened the app. With no touch (VoiceOver, Siri, a link) it is the app's icon. Apps close to the Home Screen, wherever they were opened from, and it stays laid out behind an open app, so the source is found again where it is now, even after the iPad turns. An app opened from the face has no source on the Home Screen unless it was a pill, which the header has too, so it lands on its own icon when the page shows it. With nothing to land on, the window shrinks into a stand-in at the screen's center and fades. Faces, opened by holding the face, grows from the stand-in and closes back to the face onto it, since the whole face was held, not a part of it.
- Only the face at rest reports sources (`FacePager`). The faces on either side of it are laid out too and can be the same face with the same widgets, whose sources then landed a page to the side under the same IDs, so nothing on the face was ever under the touch.
- Holding the face opens its editor with a fade, not the zoom (`fadingAppID`): the whole face was held, so there is nothing to grow out of. The app fades in over the face and fades out back to it, kept in the window until its fade ends.
- An icon's window turns into the icon's picture. A widget's or a pill's window takes its shape and corners (a pill's are half its height) over its flight and melts into it, since it stays in view.
- The icon is hidden while its app is in flight, from the first move of a swipe on, since the window is it. When a close lands, the icon shows first and the picture over it, which looks the same, goes a frame later. A swipe that springs back shows the icon again. Each icon reads a flag of its own (`ZoomHiddenIcons`), so hiding it and showing it again updates that icon alone, not every tile on the Home Screen.
- While an app is open the whole Home Screen is blurred and dimmed, and its icons and widgets sit back to 95 percent. As an app closes it comes into focus. All three are plain states that change with the screen change, so the Home Screen is drawn once for them, and Core Animation plays all three, so none of them needs the main thread on any frame.
- The sit back is a Core Animation scale of the icons' and widgets' own UIKit view (`HomeScreenHost`), as iPadOS scales its Home Screen. Their layout never sees it. The wallpaper stays put.
- The blur is a plain backdrop blur over the Home Screen (`BackdropBlurView`), its radius sprung by Core Animation with the screen change's timing. A blur over it rather than of it, because the Face wallpaper is itself a blur of the face behind the Home Screen.
- The dim is a black view over the blur (`HomeDimView`), its opacity sprung by Core Animation on the same spring. As a SwiftUI animation it took the main thread on every frame of the screen change.
- The Home Screen lays itself out from the screen's edges with its own margins and takes no safe area.
- With no icon on screen (closing to the face, another Home Screen page, a folder), the window zooms into an icon-sized stand-in at the screen's center and fades.
- Reduce Motion skips the zoom and cross fades.

All of the shapes and poses are pure functions in `AppZoomGeometry`, under unit tests.

## The main thread during a zoom

Everything that moves in a zoom (the window, the blur, the dim, the sit back) is played by Core Animation. The main thread still has the screen change to do: SwiftUI updates the shell for it as the zoom starts, a suspended app rejoins or leaves the window, and the icon hides and shows again. A stall there holds only what SwiftUI animates itself, such as the top pills coming and going, but `FPSMonitor` counts it.

- Each zoom is marked in Instruments' Points of Interest (`ZoomSignposts`): an open, a close, a swipe, a spring back and the window landing. A Time Profiler trace attached to the app shows what the main thread does around each one.
- `FPSMonitor` records the main thread's frame rate through each open and close (`AppZoom.open <id>`, `AppZoom.close <id>`) in Documents/fps-trace.txt.
- In the simulator, UI tests turn accessibility on and the simulator's keyboard turns on UIKit's focus engine, which together add about a third to the main thread's work at a zoom. An iPad with no keyboard attached and no assistive feature on should do neither, which has not been measured on the iPad.

## Why the earlier versions looked wrong

- Scaling the live SwiftUI app drops whatever it draws outside its own layout frame. The shell adds a screen margin to the safe area (`ScreenMarginInstaller`), and an app's page color in that margin is drawn outside its frame. With the app scaled, the margin vanished and the window showed as the inset content with square corners, while its rounded mask fell outside it. That was the border arriving late. No mask, measurement or timing change could fix it, which is why the zoom now animates a picture.
- A full-app offscreen pass every frame, the Home Screen redrawn every frame through an animated environment value, and an SF Symbol drawn at a new size every frame made the zoom drop to a few frames per second.
- Icons were measured from the safe area's corner while the zoom worked from the screen's, so the window landed about 40 points left of and 44 above its icon. Home Screen icons are now measured in their host's own space, which is the window's, whatever the sit back.
- The sit back was first a SwiftUI scale effect, and SwiftUI lets a scale reach layout. A scaled view gets no safe area, so the grid was laid out 52 points shorter while an app was open and stretched back after. With that fixed, the paging scroll view still worked its page position out again on every frame of the scale (logged: page 2 at 1354.5 to 1376 points instead of a steady 1376), and the icons shifted sideways and back as an app closed, while the header did not. In its own host, scaled by Core Animation, the position holds at 1376 throughout.
- A SwiftUI blur of the Home Screen grouped it on its own, and the Face wallpaper, a blur of the face behind, drew black.

## Sources

Nathan Gitter's `fluid-interfaces` (Apache 2.0, from Apple's WWDC18 talk "Designing Fluid Interfaces") for the ideas of describing a spring by response and damping and of carrying the finger's velocity into it. No code was copied, so the dependency table in docs/ARCHITECTURE.md has no entry.
