#!/bin/zsh
# Profiles the Faces app in a simulator: runs the UI test tour
# (FacesPerfUITests.testFacesAppTour) with Instruments attached to the app,
# then keeps the trace, the frame rates the app wrote and the test's log.
#
#   scripts/profile-faces.sh <simulator UDID> <new output folder>
#
# Build first, optimized and with the debug launch options the tour uses:
#   scripts/build-slot.sh xcodebuild -project HomePad.xcodeproj -scheme HomePad -configuration Release \
#     -destination 'platform=iOS Simulator,id=<UDID>' -derivedDataPath .build/DerivedData-Profile \
#     SWIFT_ACTIVE_COMPILATION_CONDITIONS=DEBUG -quiet build-for-testing
# Then read the trace with scripts/trace_hotspots.py (see the Faces README's Performance section).
set -u
sim=$1
out=$2
bundle=com.ksha23.homepad
# Seconds the app waits on the Home Screen before Faces opens, for Instruments to attach.
delay=15

mkdir "$out" || exit 1
xcrun simctl terminate "$sim" "$bundle" 2>/dev/null
container=$(xcrun simctl get_app_container "$sim" "$bundle" data 2>/dev/null)
# Frame rates are appended to this file, so note where this run's lines start.
before=0
if [ -n "$container" ] && [ -f "$container/Documents/fps-trace.txt" ]; then
  before=$(wc -l < "$container/Documents/fps-trace.txt")
fi

TEST_RUNNER_FACES_TOUR_DELAY=$delay xcodebuild test-without-building -project HomePad.xcodeproj -scheme HomePad \
  -configuration Release -destination "platform=iOS Simulator,id=$sim" -derivedDataPath .build/DerivedData-Profile \
  -resultBundlePath "$out/tour.xcresult" -only-testing:HomePadUITests/FacesPerfUITests/testFacesAppTour \
  > "$out/test.log" 2>&1 &
test_pid=$!

# The app's process, once the test has launched it.
pid=""
for _ in $(seq 1 240); do
  pid=$(xcrun simctl spawn "$sim" launchctl list 2>/dev/null | awk -v b="$bundle" '$3 ~ "UIKitApplication:" b "\\[" && $1 != "-" { print $1 }')
  [ -n "$pid" ] && break
  sleep 0.5
done
if [ -z "$pid" ]; then
  echo "the app never started, see $out/test.log"
  wait $test_pid
  exit 1
fi
echo "attaching to $pid"
# Hitches and Animation Hitches need a device. FPSMonitor's lines stand in for them here.
xcrun xctrace record --template 'Time Profiler' --instrument 'Points of Interest' \
  --device "$sim" --attach "$pid" --time-limit 300s --no-prompt --output "$out/faces.trace" > "$out/xctrace.log" 2>&1 &
trace_pid=$!

wait $test_pid
test_status=$?
# The recording ends with the app.
xcrun simctl terminate "$sim" "$bundle" 2>/dev/null
wait $trace_pid

container=$(xcrun simctl get_app_container "$sim" "$bundle" data)
tail -n +$((before + 1)) "$container/Documents/fps-trace.txt" > "$out/fps-trace.txt"
grep -E 'Test Case|error|passed|failed' "$out/test.log" | tail -5
echo "test exit $test_status, trace in $out/faces.trace, frame rates in $out/fps-trace.txt"
exit $test_status
