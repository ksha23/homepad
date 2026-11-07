#!/bin/zsh
# Boots the simulator, installs the built app and launches it.
set -euo pipefail
sim=${1:-iPad Pro 13-inch (M5)}
root=${0:A:h:h}
app="$root/.build/DerivedData/Build/Products/Debug-iphonesimulator/HomePad.app"
xcrun simctl boot "$sim" 2>/dev/null || true
# Xcode 27 shows simulators in DeviceHub and no longer ships Simulator.app.
open -a Simulator 2>/dev/null || open -b com.apple.dt.Devices
xcrun simctl install "$sim" "$app"
xcrun simctl launch "$sim" com.ksha23.homepad
