#!/bin/zsh
# Builds one local package for the iOS Simulator, through a build slot.
#   scripts/build-package.sh HomePadSmartHome          # build
#   scripts/build-package.sh HomePadSmartHome test     # run its tests on a simulator
set -euo pipefail
pkg=$1
action=${2:-build}
root=${0:A:h:h}
cd "$root/Packages/$pkg"
derived="$root/.build/DerivedData-$pkg"
if [ "$action" = test ]; then
  dest="platform=iOS Simulator,name=${HOMEPAD_SIM:-iPad Pro 13-inch (M5)}"
else
  dest="generic/platform=iOS Simulator"
fi
exec "$root/scripts/build-slot.sh" xcodebuild -scheme "$pkg" -destination "$dest" \
  -derivedDataPath "$derived" -skipPackagePluginValidation -quiet "$action"
