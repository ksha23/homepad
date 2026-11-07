#!/bin/zsh
# Builds the hub, signs it with a stable identity, swaps it into ~/.homepad-hub on the hub Mac and restarts the agent.
# A stable signature keeps the Full Disk Access grant across rebuilds (an ad-hoc signature does not).
# HUB_HOST is the hub Mac's ssh name and HUB_SIGN_IDENTITY a Developer ID Application identity.
# Set them in the environment, or in Hub/deploy.local (not tracked), which this script reads first.
set -euo pipefail
here=${0:A:h}
[[ -f "$here/deploy.local" ]] && source "$here/deploy.local"
host=${HUB_HOST:?Set HUB_HOST to the hub Mac, here or in Hub/deploy.local}
identity=${HUB_SIGN_IDENTITY:?Set HUB_SIGN_IDENTITY to a Developer ID Application identity, here or in Hub/deploy.local}

cd "$here"
swift build -c release 2>&1 | tail -1
cp .build/release/homepad-hub .build/homepad-hub.signed
codesign --force --options runtime --identifier com.homepad.hub -s "$identity" .build/homepad-hub.signed
scp -q .build/homepad-hub.signed "$host:.homepad-hub/homepad-hub.new"
# scp does not keep the execute bit, and without it launchd fails to start the hub (exit 78).
# Renamed over the old binary, never copied onto it: launchd kills a running process whose binary changes in place.
ssh "$host" 'chmod 755 ~/.homepad-hub/homepad-hub.new && mv -f ~/.homepad-hub/homepad-hub.new ~/.homepad-hub/homepad-hub && launchctl kickstart -k "gui/$(id -u)/com.homepad.hub"'
echo "deployed to $host"
