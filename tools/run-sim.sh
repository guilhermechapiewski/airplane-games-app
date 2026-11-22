#!/bin/zsh
# Builds, installs and launches the app on a simulator, then saves a screenshot.
# Usage: tools/run-sim.sh [device-name-or-UDID] [screenshot-path] [extra launch args...]
# Env:   DERIVED_DATA=<path> to override the DerivedData directory.
# When several simulators share a name, the one on the newest iOS runtime is used.
set -euo pipefail
DEVICE="${1:-iPhone 17}"
SHOT="${2:-}"
shift $(( $# > 2 ? 2 : $# ))
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

if [[ "$DEVICE" =~ ^[0-9A-F-]{36}$ ]]; then
  UDID="$DEVICE"
else
  UDID=$(xcrun simctl list devices available | grep -F "    $DEVICE (" | tail -1 | grep -oE '[0-9A-F-]{36}')
  [[ -n "$UDID" ]] || { echo "No simulator named '$DEVICE'" >&2; exit 1; }
fi

DD="${DERIVED_DATA:-$ROOT/build/DerivedData-$UDID}"
xcodebuild -project "$ROOT/AirplaneModeGames.xcodeproj" -scheme AirplaneModeGames \
  -destination "platform=iOS Simulator,id=$UDID" -derivedDataPath "$DD" build -quiet
xcrun simctl boot "$UDID" 2>/dev/null || true
APP="$DD/Build/Products/Debug-iphonesimulator/AirplaneModeGames.app"
xcrun simctl install "$UDID" "$APP"
xcrun simctl terminate "$UDID" com.gchapiewski.airplanemodegames 2>/dev/null || true
xcrun simctl launch "$UDID" com.gchapiewski.airplanemodegames "$@" >/dev/null
if [[ -n "$SHOT" ]]; then
  sleep 3
  xcrun simctl io "$UDID" screenshot "$SHOT" >/dev/null 2>&1
  echo "screenshot: $SHOT"
fi
