#!/bin/zsh
# Installs the device build (Release unless DEVICE_CONFIG=Debug) on a connected iPad and launches it.
#   scripts/install-device.sh            # lists devices
#   scripts/install-device.sh "Kyle's iPad Pro"
set -euo pipefail
root=${0:A:h:h}
app="$root/.build/DerivedData/Build/Products/${DEVICE_CONFIG:-Release}-iphoneos/HomePad.app"
if [ -z "${1:-}" ]; then
  xcrun devicectl list devices
  echo "Pass a device name or identifier from the list above."
  exit 1
fi
xcrun devicectl device install app --device "$1" "$app"
xcrun devicectl device process launch --device "$1" com.ksha23.homepad
