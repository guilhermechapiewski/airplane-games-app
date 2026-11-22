#!/bin/zsh
# Builds, installs and launches the app on a simulator, then saves a screenshot.
# Usage: tools/run-sim.sh [device-name] [screenshot-path] [extra launch args...]
set -euo pipefail
DEVICE="${1:-iPhone 17}"
SHOT="${2:-}"
shift $(( $# > 2 ? 2 : $# ))
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DD="$ROOT/build/DerivedData-${DEVICE// /_}"
xcodebuild -project "$ROOT/AirplaneModeGames.xcodeproj" -scheme AirplaneModeGames \
  -destination "platform=iOS Simulator,name=$DEVICE" -derivedDataPath "$DD" build -quiet
xcrun simctl boot "$DEVICE" 2>/dev/null || true
APP="$DD/Build/Products/Debug-iphonesimulator/AirplaneModeGames.app"
xcrun simctl install "$DEVICE" "$APP"
xcrun simctl terminate "$DEVICE" com.gchapiewski.airplanemodegames 2>/dev/null || true
xcrun simctl launch "$DEVICE" com.gchapiewski.airplanemodegames "$@" >/dev/null
if [[ -n "$SHOT" ]]; then
  sleep 3
  xcrun simctl io "$DEVICE" screenshot "$SHOT" >/dev/null 2>&1
  echo "screenshot: $SHOT"
fi
