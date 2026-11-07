#!/bin/zsh
# Launches HomePad in a simulator with launch arguments and saves a screenshot.
#   scripts/screenshot.sh <simulator> <out.png> [launch args...]
# Example: scripts/screenshot.sh HP-lead /tmp/home.png -HomePadShowHome YES -HomePadDemoContent YES
set -euo pipefail
sim=$1; out=$2; shift 2
root=${0:A:h:h}
app="$root/.build/DerivedData/Build/Products/Debug-iphonesimulator/HomePad.app"
xcrun simctl boot "$sim" 2>/dev/null || true
xcrun simctl install "$sim" "$app"
xcrun simctl launch --terminate-running-process "$sim" com.ksha23.homepad "$@" >/dev/null
sleep ${HOMEPAD_SHOT_DELAY:-4}
xcrun simctl io "$sim" screenshot "$out" >/dev/null 2>&1
echo "$out"
