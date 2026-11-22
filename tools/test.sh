#!/bin/zsh
# Runs the test suites the fast way.
# Usage: tools/test.sh [unit|ui|all] [extra xcodebuild args, e.g. -only-testing:AirplaneModeGamesUITests/SnakeUITests]
#   unit  GameLogic tests on macOS, optimized (the Sudoku/Chess generators are ~8x faster than debug).
#   ui    UI tests only, spread across parallel simulator clones.
#   all   both (default).
# Env: DEVICE=<simulator name> (default "iPhone 17 Pro"), WORKERS=<n> parallel simulators (default 4).
set -euo pipefail
MODE="${1:-all}"
(( $# )) && shift
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEVICE="${DEVICE:-iPhone 17 Pro}"
WORKERS="${WORKERS:-4}"

run_unit() {
  echo "▸ GameLogic unit tests (release)"
  swift test -c release -Xswiftc -enable-testing --package-path "$ROOT/Packages/GameLogic" 2>&1 | tail -1
}

run_ui() {
  echo "▸ UI tests on $WORKERS × $DEVICE"
  local result="$ROOT/build/Logs/ui-tests.xcresult"
  rm -rf "$result"
  # GameLogic tests are covered by run_unit; skip their slow debug-build copy here.
  xcodebuild test -project "$ROOT/AirplaneModeGames.xcodeproj" -scheme AirplaneModeGames \
    -destination "platform=iOS Simulator,name=$DEVICE" -derivedDataPath "$ROOT/build" \
    -only-testing:AirplaneModeGamesUITests \
    -parallel-testing-enabled YES -parallel-testing-worker-count "$WORKERS" \
    -resultBundlePath "$result" "$@" 2>&1 \
    | grep -E "error:|Test [Cc]ase .*(passed|failed)|TEST (SUCCEEDED|FAILED)|Testing failed" || true
  [[ "$(xcrun xcresulttool get test-results summary --path "$result" 2>/dev/null \
        | python3 -c 'import json,sys; print(json.load(sys.stdin)["result"])')" == "Passed" ]]
}

case "$MODE" in
  unit) run_unit ;;
  ui)   run_ui "$@" ;;
  all)  run_unit && run_ui "$@" ;;
  *)    echo "usage: $0 [unit|ui|all] [xcodebuild args]" >&2; exit 2 ;;
esac
