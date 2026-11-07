#!/usr/bin/env python3
"""Captures README screenshots in the simulator and composes them into docs/images.

    make readme-images                                # capture and compose everything
    python3 scripts/readme_images.py --compose-only   # compose from the last capture
    python3 scripts/readme_images.py --only audio     # one README image
    python3 scripts/readme_images.py --shots board    # recapture one shot, recompose its images
    python3 scripts/readme_images.py --shots up-next  # the same for a sheet

Each shot launches HomePad with debug launch arguments (see the package READMEs),
so the images are reproducible. Shots are framed as rounded iPad screens and laid
on a dark banner, one image per README section or two for a long one.

Sheets are captured differently. `-HomePadForceLandscape` turns the app but not
its sheets, its full-screen presentations (Now Playing) or the keyboard, so the
shots in SHEETS come from ReadmeShotsUITests
(in UITests/), which turns the simulator itself. The script runs those tests in
the same simulator after the other shots, exports their screenshots from the
result bundle, and takes the shots with the keyboard up itself while each test
holds the screen. Rerunning a sheet is the same command as any other shot.

Needs Pillow (`pip install pillow`) and a built simulator app (`make build`). The
UI tests build into .build/DerivedData-UITests on their first run.
HOMEPAD_SIM picks the simulator (`make readme-images SIM=<name>` sets it). HOMEPAD_SHOT_DELAY sets the seconds to wait
after launch for shots without their own delay in DELAYS.
"""
import argparse
import json
import os
import re
import subprocess
import sys
import tempfile

from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RAW = os.path.join(ROOT, ".build", "readme-shots")
OUT = os.path.join(ROOT, "docs", "images")
SIM = os.environ.get("HOMEPAD_SIM", "iPad Pro 13-inch (M5)")
BUNDLE_ID = "com.ksha23.homepad"
# Capture in landscape (how a HomePad usually sits). The simulator cannot rotate,
# so the shell lays itself out sideways and the capture is rotated back upright.
LANDSCAPE = os.environ.get("HOMEPAD_README_PORTRAIT") is None

# Demo household with Alex (an admin) recognized, so personal items and admin panes show.
MEMBER = ["-HomePadMember", "Alex", "-HomePadRecognized", "YES"]
DAY = ["-HomePadCondition", "active", "-HomePadDemoContent", "YES", *MEMBER]
FACE = ["-HomePadCondition", "ambient", "-HomePadDemoContent", "YES", *MEMBER]
# Demo music with generated covers, playing on This iPad.
MUSIC = ["-HomePadAudioDemo", "YES"]

# Widgets on faces, as `id:size@column,row` on the 6 by 4 landscape grid.
# Modular takes them in its two trailing columns, Photos in its bottom row.
MODULAR_WIDGETS = "personal.weather:medium@4,0;personal.upnext:medium@4,1;smarthome.favorites:large@4,2"
PHOTOS_WIDGETS = "personal.weather:medium@0,3;kitchen.timers:small@2,3;personal.upnext:medium@4,3"
# The editor shot leaves a cell free, so Add Widget is on, and holds the weather lifted on its way down.
EDITOR_WIDGETS = "personal.weather:medium@4,0;smarthome.favorites:large@4,2"

# name: launch arguments
SHOTS = {
    # Faces
    "face-modular": ["-HomePadShowFace", "faces.modular", *FACE],
    "face-modular-widgets": ["-HomePadShowFace", "faces.modular", "-HomePadFacesWidgets", MODULAR_WIDGETS, *FACE],
    "face-photos": ["-HomePadShowFace", "faces.photos", "-HomePadProximity", "far", *FACE],
    "face-photos-widgets": ["-HomePadShowFace", "faces.photos", "-HomePadProximity", "far",
                            "-HomePadFacesWidgets", PHOTOS_WIDGETS, *FACE],
    "face-now-playing": ["-HomePadShowFace", "faces.modular", *MUSIC, *FACE],
    "face-home": ["-HomePadShowFace", "faces.homeModular", *FACE],
    "face-weather": ["-HomePadShowFace", "faces.weather", *FACE],
    "face-flow": ["-HomePadShowFace", "faces.flow", *FACE],
    "face-critters": ["-HomePadShowFace", "faces.critters", *FACE],
    "face-numerals": ["-HomePadShowFace", "faces.numerals", *FACE],
    "face-cameras": ["-HomePadShowFace", "faces.cameras", "-HomePadProximity", "near", *FACE],
    "face-fade": ["-HomePadShowFace", "faces.fade", *FACE],
    "face-night": ["-HomePadShowFace", "faces.modular", "-HomePadCondition", "night", "-HomePadDemoContent", "YES"],
    "faces-app": ["-HomePadOpenApp", "faces", *DAY],
    "faces-edit-widgets": ["-HomePadOpenApp", "faces", "-HomePadFacesEdit", "faces.modular", "-HomePadFacesEditWidgets", "YES",
                           "-HomePadFacesWidgets", EDITOR_WIDGETS, "-HomePadFacesWidgetDrag", "0@-30,150", *DAY],
    # Distance and night
    "weather-far": ["-HomePadOpenApp", "weather", "-HomePadProximity", "far", *DAY],
    "weather-near": ["-HomePadOpenApp", "weather", "-HomePadProximity", "near", *DAY],
    "home-night": ["-HomePadShowHome", "YES", "-HomePadCondition", "night", "-HomePadDemoContent", "YES"],
    # Home Screen, people, Control Center and kiosk
    "home-screen": ["-HomePadShowHome", "YES", *MUSIC, *DAY],
    "home-edit": ["-HomePadShowHome", "YES", "-HomePadEditHomeScreen", "YES", *DAY],
    "people": ["-HomePadShowHome", "YES", "-HomePadShowPanel", "people", *DAY],
    "gate": ["-HomePadShowGate", "assistant", *DAY],
    "control-center": ["-HomePadShowPanel", "controlCenter", *MUSIC, *DAY],
    "control-edit": ["-HomePadShowPanel", "controlCenter", "-HomePadEditControlCenter", "YES", *DAY],
    "kiosk-settings": ["-HomePadSettingsPane", "kiosk", *DAY],
    "onboarding": ["-HomePadShowOnboarding", "YES", "-HomePadOnboardingStep", "0", *DAY],
    # Assistant
    "assistant-answer": ["-HomePadShowHome", "YES", "-HomePadAssistantDemo", "answer", *DAY],
    "assistant-confirm": ["-HomePadShowHome", "YES", "-HomePadAssistantDemo", "confirm", *DAY],
    "assistant-calendar": ["-HomePadShowHome", "YES", "-HomePadAssistantDemo", "calendar", *DAY],
    # The sample conversation is a guest's, so nobody is recognized here.
    "assistant-chat": ["-HomePadOpenApp", "assistant", "-HomePadAssistantDemo", "chat", "-HomePadCondition", "active",
                       "-HomePadDemoContent", "YES"],
    # Smart home
    "home-app": ["-HomePadOpenApp", "home", *DAY],
    "accessory-controls": ["-HomePadOpenApp", "home", "-HomePadSmartHomeAccessory", "demo:light.kitchen", *DAY],
    "cameras-app": ["-HomePadOpenApp", "cameras", *DAY],
    "doorbell": ["-HomePadShowHome", "YES", "-HomePadRingDoorbell", "demo:camera.front", *DAY],
    # Music (Now Playing is a full-screen presentation, so it comes from ReadmeShotsUITests)
    "music":["-HomePadOpenApp", "music", "-HomePadMusicSection", "listenNow", *MUSIC, *DAY],
    "music-library": ["-HomePadOpenApp", "music", "-HomePadMusicSection", "library", "-HomePadMusicLibrary", "albums",
                      *MUSIC, *DAY],
    "music-album": ["-HomePadOpenApp", "music", "-HomePadMusicSection", "library", "-HomePadMusicPage", "Night Signals",
                    *MUSIC, *DAY],
    # Presence
    "presence-status": ["-HomePadSettingsPane", "presence", "-HomePadPresencePane", "status", "-HomePadSimulatePresence", "near", *DAY],
    "mirror": ["-HomePadOpenApp", "mirror", *DAY],
    # Kitchen
    "recipes": ["-HomePadOpenApp", "recipes", *DAY],
    "recipe-card": ["-HomePadOpenApp", "recipes", "-KitchenDemo", "card", "-KitchenDemoNoAlarms", "YES", *DAY],
    "cooking": ["-HomePadOpenApp", "recipes", "-KitchenDemo", "cooking", "-KitchenDemoStep", "2", "-KitchenDemoNoAlarms", "YES", *DAY],
    "timers": ["-HomePadOpenApp", "timers", "-KitchenDemo", "timers", "-KitchenDemoNoAlarms", "YES", *DAY],
    # Personal
    "calendar": ["-HomePadOpenApp", "calendar", *DAY],
    "reminders": ["-HomePadOpenApp", "reminders", *DAY],
    "worldclock": ["-HomePadOpenApp", "worldclock", *DAY],
    "findmy": ["-HomePadOpenApp", "findmy", *DAY],
    "findmy-card": ["-HomePadOpenApp", "findmy", "-HomePadFindMyDevice", "Sam's iPhone", *DAY],
    "photos-album": ["-HomePadOpenApp", "photos", "-HomePadPhotosAlbum", "library", *DAY],
    "photos-viewer": ["-HomePadOpenApp", "photos", "-HomePadPhotosAlbum", "library", "-HomePadPhotosViewer", "13", *DAY],
    # Camera Lab
    "cameralab": ["-HomePadOpenApp", "cameralab", *DAY],
    "security-camera": ["-HomePadOpenApp", "cameralab", "-CameraLabTool", "security", "-CameraLabSecurity", "on", *DAY],
    "floor-plan": ["-HomePadOpenApp", "floorplan", *DAY],
    "ask-about-this": ["-HomePadOpenApp", "cameralab", "-CameraLabTool", "ask", *DAY],
    # Messages, from a stand-in hub with made-up conversations
    "messages": ["-HomePadOpenApp", "messages", "-HomePadCommsDemo", "YES", "-HomePadMessagesOpen", "demo.sam", *DAY],
    "messages-group": ["-HomePadOpenApp", "messages", "-HomePadCommsDemo", "YES", "-HomePadMessagesOpen", "demo.family", *DAY],
    "messages-settings": ["-HomePadSettingsPane", "comms", "-HomePadCommsDemo", "YES", *DAY],
    # Connect
    "intercom":["-HomePadOpenApp", "intercom", "-ConnectDemoData", "YES", *DAY],
    "board": ["-HomePadOpenApp", "board", "-ConnectDemoData", "YES", "-ConnectDemoNotes", "9", *DAY],
    "board-widget": ["-HomePadShowHome", "YES", "-HomePadHomeWidgets", "connect.board:large", "-ConnectDemoData", "YES", *DAY],
    "connect-settings": ["-HomePadSettingsPane", "connect", *DAY],
}

# Seconds to wait after launch where the default does not fit: maps load
# their tiles, photos draw their scenes and subject masks, recipe pictures
# come from TheMealDB, the doorbell rings two seconds after launch, and the
# timers tick on whole seconds after launch, so their shot falls between ticks.
DELAYS = {
    "findmy": 10,
    "findmy-card": 10,
    "photos-album": 6,
    "photos-viewer": 6,
    "recipes": 10,
    "doorbell": 6,
    "timers": 5,
}
# Faces wait until the system home indicator has faded out.
DELAYS.update({name: 8 for name in SHOTS if name.startswith("face-")})

# Sheets and full-screen presentations, from ReadmeShotsUITests: shot name, then its test. The tests hold
# the launch arguments, since most of them tap to open their sheet.
SHEETS = {
    "face-gallery": "testFaceGallery",
    "face-widget-gallery": "testFaceWidgetGallery",
    "home-widget-gallery": "testHomeWidgetGallery",
    "home-add-app": "testHomeAddApp",
    "home-wallpaper": "testHomeWallpaper",
    "person-editor": "testPersonEditor",
    "assistant-provider": "testAssistantProvider",
    "presence-enroll": "testEnrollment",
    "now-playing": "testNowPlaying",
    "up-next": "testUpNext",
    "recipe-preview": "testRecipePreview",
    "ingredients": "testIngredients",
    "worldclock-add-city": "testAddCity",
    "weather-location": "testWeatherLocation",
    # With the keyboard up, so the script takes these itself.
    "board-composer": "testBoardComposer",
    "board-editor": "testBoardEditor",
}
# The log line a keyboard shot's test writes while it holds the screen.
HOLD_LINE = re.compile(r"\bt = .*README screen (\S+)\s*$")

# README image: shots, left to right and top to bottom
GROUPS = {
    "hero": ["face-photos", "home-screen", "assistant-answer", "face-home"],
    "faces": ["face-modular", "face-weather", "face-flow", "face-critters"],
    "faces-more": ["face-numerals", "face-cameras", "faces-app", "face-gallery", "face-fade"],
    "faces-widgets": ["face-modular-widgets", "face-photos-widgets", "faces-edit-widgets", "face-widget-gallery",
                      "face-now-playing"],
    "proximity-night": ["weather-far", "weather-near", "face-night", "home-night"],
    "home-screen": ["home-screen", "people", "person-editor", "gate"],
    "home-screen-edit": ["home-edit", "home-widget-gallery", "home-add-app", "home-wallpaper"],
    "control-kiosk": ["control-center", "control-edit", "kiosk-settings", "onboarding"],
    "assistant": ["assistant-answer", "assistant-calendar", "assistant-confirm", "assistant-chat", "assistant-provider"],
    "smart-home": ["home-app", "accessory-controls", "cameras-app", "doorbell"],
    "audio": ["now-playing", "up-next", "music", "music-library", "music-album"],
    "presence": ["presence-status", "presence-enroll", "gate", "mirror"],
    "kitchen": ["recipes", "recipe-preview", "recipe-card", "ingredients", "cooking", "timers"],
    "personal": ["calendar", "reminders", "weather-near", "weather-location", "worldclock", "worldclock-add-city"],
    "findmy-photos": ["findmy", "findmy-card", "photos-album", "photos-viewer"],
    "camera-lab": ["cameralab", "ask-about-this", "security-camera", "floor-plan"],
    "connect": ["intercom", "board", "board-composer", "board-editor", "board-widget", "connect-settings"],
    "messages": ["messages", "messages-group", "messages-settings"],
}

BANNER_TOP = (26, 26, 30)
BANNER_BOTTOM = (12, 12, 14)
SCREEN_HEIGHT = 900      # each framed shot is scaled to this height (portrait)
SCREEN_WIDTH = 1100      # each framed shot is scaled to this width (landscape)
GAP = 48
MARGIN = 56


def capture(names):
    os.makedirs(RAW, exist_ok=True)
    extra = ["-HomePadForceLandscape", "YES"] if LANDSCAPE else []
    for name in [n for n in names if n in SHOTS]:
        out = os.path.join(RAW, f"{name}.png")
        env = dict(os.environ)
        if name in DELAYS:
            env["HOMEPAD_SHOT_DELAY"] = str(DELAYS[name])
        # A fresh install per shot, so state from one shot (a timer still
        # running, a finished alarm) never shows up in the next.
        subprocess.run(["xcrun", "simctl", "uninstall", SIM, BUNDLE_ID], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        subprocess.run([os.path.join(ROOT, "scripts", "screenshot.sh"), SIM, out, *SHOTS[name], *extra],
                       check=True, stdout=subprocess.DEVNULL, env=env)
        if LANDSCAPE:
            Image.open(out).rotate(-90, expand=True).save(out)
        print("captured", name)
    sheets = [n for n in names if n in SHEETS]
    if sheets:
        capture_sheets(sheets)


def capture_sheets(names):
    """Runs the README tests for these sheets and saves their screenshots.

    A fresh install first, as for every other shot. Then the tests run in
    order in one app, each launching it again.
    """
    subprocess.run(["xcrun", "simctl", "uninstall", SIM, BUNDLE_ID], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    env = dict(os.environ, TEST_RUNNER_HOMEPAD_README_SHOTS="YES")
    if not LANDSCAPE:
        env["TEST_RUNNER_HOMEPAD_README_PORTRAIT"] = "YES"
    with tempfile.TemporaryDirectory() as work:
        result = os.path.join(work, "shots.xcresult")
        # HOMEPAD_SIM is a simulator's name or its identifier. Two simulators can share a name.
        destination = f"id={SIM}" if re.fullmatch(r"[0-9A-F]{8}(-[0-9A-F]{4}){3}-[0-9A-F]{12}", SIM) else f"name={SIM}"
        command = [os.path.join(ROOT, "scripts", "build-slot.sh"), "xcodebuild", "-project", "HomePad.xcodeproj",
                   "-scheme", "HomePad", "-destination", f"platform=iOS Simulator,{destination}",
                   "-derivedDataPath", os.path.join(".build", "DerivedData-UITests"), "-resultBundlePath", result,
                   *[f"-only-testing:HomePadUITests/ReadmeShotsUITests/{SHEETS[n]}" for n in names], "test"]
        log = []
        captured = set()
        with subprocess.Popen(command, cwd=ROOT, env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True) as tests:
            for line in tests.stdout:
                log.append(line)
                held = HOLD_LINE.search(line)
                if held and held[1] in names:
                    # simctl's screenshot shows the keyboard, upright in either orientation.
                    subprocess.run(["xcrun", "simctl", "io", SIM, "screenshot", os.path.join(RAW, f"{held[1]}.png")],
                                   check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                    captured.add(held[1])
                    print("captured", held[1])
        if tests.returncode != 0:
            sys.stdout.writelines(log[-60:])
            sys.exit("ReadmeShotsUITests failed, see above")
        attachments = os.path.join(work, "attachments")
        subprocess.run(["xcrun", "xcresulttool", "export", "attachments", "--path", result, "--output-path", attachments],
                       check=True, stdout=subprocess.DEVNULL)
        with open(os.path.join(attachments, "manifest.json")) as manifest:
            tests_run = json.load(manifest)
        shots = {test: name for name, test in SHEETS.items()}
        for test in tests_run:
            name = shots[test["testIdentifier"].split("/")[-1].removesuffix("()")]
            for attachment in test["attachments"]:
                shot = Image.open(os.path.join(attachments, attachment["exportedFileName"]))
                # An XCTest screenshot in landscape has the top of the screen on the right.
                (shot.rotate(90, expand=True) if LANDSCAPE else shot).save(os.path.join(RAW, f"{name}.png"))
                captured.add(name)
                print("captured", name)
    missing = [n for n in names if n not in captured]
    if missing:
        sys.exit("no screenshot for " + " ".join(missing))


def framed(path):
    """A screenshot scaled down, with rounded corners, a thin bezel and a soft shadow."""
    shot = Image.open(path).convert("RGB")
    scale = SCREEN_WIDTH / shot.width if shot.width > shot.height else SCREEN_HEIGHT / shot.height
    shot = shot.resize((round(shot.width * scale), round(shot.height * scale)), Image.LANCZOS)
    w, h = shot.size
    bezel = 14
    radius = 42
    frame = Image.new("RGBA", (w + 2 * bezel, h + 2 * bezel), (0, 0, 0, 0))
    ImageDraw.Draw(frame).rounded_rectangle([0, 0, frame.width - 1, frame.height - 1], radius=radius + bezel, fill=(44, 44, 48, 255))
    mask = Image.new("L", shot.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, w - 1, h - 1], radius=radius, fill=255)
    frame.paste(shot, (bezel, bezel), mask)
    pad = 40
    shadow = Image.new("RGBA", (frame.width + 2 * pad, frame.height + 2 * pad), (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle([pad, pad + 10, pad + frame.width, pad + frame.height + 10],
                                             radius=radius + bezel, fill=(0, 0, 0, 150))
    shadow = shadow.filter(ImageFilter.GaussianBlur(18))
    shadow.alpha_composite(frame, (pad, pad))
    return shadow


def compose(group, names):
    tiles = [framed(os.path.join(RAW, f"{n}.png")) for n in names]
    # Landscape shots go two to a row, so every shot is as large as in a
    # 2 by 2 grid, and a last odd one is centered. Portrait shots go in one row.
    columns = 2 if tiles[0].width > tiles[0].height else len(tiles)
    rows = [tiles[i:i + columns] for i in range(0, len(tiles), columns)]
    tile_w = max(t.width for t in tiles)
    tile_h = max(t.height for t in tiles)
    width = columns * tile_w + GAP * (columns - 1) + 2 * MARGIN
    height = len(rows) * tile_h + GAP * (len(rows) - 1) + 2 * MARGIN
    banner = Image.new("RGBA", (width, height))
    draw = ImageDraw.Draw(banner)
    for y in range(height):
        t = y / max(height - 1, 1)
        color = tuple(round(a + (b - a) * t) for a, b in zip(BANNER_TOP, BANNER_BOTTOM))
        draw.line([(0, y), (width, y)], fill=(*color, 255))
    for r, row in enumerate(rows):
        indent = (columns - len(row)) * (tile_w + GAP) // 2
        for c, tile in enumerate(row):
            x = MARGIN + indent + c * (tile_w + GAP) + (tile_w - tile.width) // 2
            y = MARGIN + r * (tile_h + GAP) + (tile_h - tile.height) // 2
            banner.alpha_composite(tile, (x, y))
    image = banner.convert("RGB")
    target_width = 1800
    if image.width > target_width:
        image = image.resize((target_width, round(image.height * target_width / image.width)), Image.LANCZOS)
    os.makedirs(OUT, exist_ok=True)
    out = os.path.join(OUT, f"{group}.jpg")
    image.save(out, quality=84, optimize=True, progressive=True)
    print("composed", out, f"{os.path.getsize(out) // 1024} KB")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--compose-only", action="store_true")
    parser.add_argument("--only", nargs="*", help="limit to these groups")
    parser.add_argument("--shots", nargs="*", help="recapture only these shots, then compose the groups that use them")
    args = parser.parse_args()
    groups = {g: n for g, n in GROUPS.items() if not args.only or g in args.only}
    if args.shots:
        unknown = [n for n in args.shots if n not in SHOTS and n not in SHEETS]
        if unknown:
            parser.error("unknown shots: " + " ".join(unknown))
        groups = {g: n for g, n in groups.items() if set(n) & set(args.shots)}
    if not args.compose_only:
        capture(sorted(args.shots or {n for names in groups.values() for n in names}))
    for group, names in groups.items():
        compose(group, names)


if __name__ == "__main__":
    sys.exit(main())
