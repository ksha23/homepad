#!/bin/zsh
# Runs a command while holding one of N build slots, so parallel agents
# never run more than N xcodebuild processes at once on this Mac.
#   scripts/build-slot.sh xcodebuild ...
# HOMEPAD_BUILD_SLOTS (default 3) sets N.
set -u
slots=${HOMEPAD_BUILD_SLOTS:-3}
lockdir=/tmp/homepad-build-slots
mkdir -p "$lockdir"
while true; do
  for i in $(seq 1 $slots); do
    # lockf -t 0 fails immediately (exit 75) if the slot is taken.
    lockf -t 0 "$lockdir/slot$i" "$@"
    rc=$?
    if [ $rc -ne 75 ]; then exit $rc; fi
  done
  sleep 5
done
