# Building a Game — Conventions & Checklist

Read `docs/DESIGN.md` first. **2048 is the reference implementation** — copy its patterns:

- Logic: `Packages/GameLogic/Sources/GameLogic/TwentyFortyEight/TwentyFortyEight.swift`
- Tests: `Packages/GameLogic/Tests/GameLogicTests/TwentyFortyEightTests.swift`
- Model: `AirplaneModeGames/Games/TwentyFortyEight/TwentyFortyEightModel.swift`
- View: `AirplaneModeGames/Games/TwentyFortyEight/TwentyFortyEightView.swift`
- UI test: `AirplaneModeGamesUITests/AppSmokeTests.swift`

## Where things go

| What | Where |
|------|-------|
| Pure rules, generators, solvers, AI | `Packages/GameLogic/Sources/GameLogic/<Game>/` under `public enum <Game> {}` |
| Unit tests (Swift Testing: `import Testing`, `@Suite`, `@Test`, `#expect`) | `Packages/GameLogic/Tests/GameLogicTests/<Game>Tests.swift` |
| `@MainActor @Observable` model + SwiftUI views | `AirplaneModeGames/Games/<Game>/` (a placeholder `<Game>View.swift` already exists and is already wired into `RootView`) |
| UI test | `AirplaneModeGamesUITests/<Game>UITests.swift` |

The Xcode project uses synchronized folders: new files are picked up automatically — **never edit
`project.pbxproj`**.

**Do not modify shared files** (`AirplaneModeGames/DesignSystem`, `Services`, `Home`, `App`,
`Settings`, `docs/`, `Package.swift`, other games' folders). If you truly need a shared change,
put a game-local helper in your own folder instead and mention the need in your final report.
(Exception: the word-games task may add a `resources:` entry to `Package.swift`.)

## Shared building blocks (use them)

- `.gameChrome(game, rules:, stats:, newGame:, onActiveChange:)` — nav title, menu with
  New Game (multiple `NewGameOption`s become a submenu, e.g. difficulties), How to Play, Statistics.
  `onActiveChange(Bool)` drives clocks and saving on background.
- `HowToPlay(summary:sections:)` — rules content, keep it short and friendly.
- `StatsStore.shared.record(game, variant:, won:, score:, time:)` at the end of each game;
  `StatsVariant` / `StatsVariant.difficulties()` describe what the stats sheet shows.
- `GameStore.shared.save/load/remove(key: game.saveKey)` — save after every meaningful change,
  remove when the game ends (the home screen shows "Resume" when a save exists).
- `GameClock` — play time that pauses in background.
- `Feedback.play(.tap/.select/.move/.merge/.place/.pop/.flip/.eat/.clear/.invalid/.win/.lose)` —
  synthesized sound + matching haptic. `Haptics.*` for haptics only.
- UI: `Theme.background/surface/well/hairline`, `game.colors`/`game.accent`, `StatPill`,
  `ToolButton`, `ResultOverlay`, `PrimaryButtonStyle(color:)`, `SecondaryButtonStyle`,
  `PressableStyle`, `GameBadge`, `ConfettiView` (inside ResultOverlay on win).
- `GameLogic`: `SeededRandom`, `GridPoint`, `Direction`, `Difficulty`.

## Quality bar (every game)

- [ ] Correct rules, exhaustively unit-tested logic (edge cases, generators produce valid/solvable
      content, determinism with seeds, `Codable` round-trip of state).
- [ ] Auto-save & resume exactly where the player left off (including timer/undo where sensible).
- [ ] Undo where it makes sense. Difficulty levels where it makes sense.
- [ ] Polished, original visuals with tasteful animations (spring/easeOut, 0.1–0.35s). Respect
      `accessibilityReduceMotion`.
- [ ] Looks great in **light and dark mode**, on small iPhones (iPhone 17e / SE size), large
      iPhones, and **iPad** (center the board, cap its width, use space well).
- [ ] VoiceOver: meaningful labels/values for cells and controls; custom actions where gestures
      are required. Dynamic Type must not break layout (use `minimumScaleFactor` on dense grids).
- [ ] Sound + haptics on meaningful events (not spammy).
- [ ] Win / loss overlay with stats, "Play Again", and a way back.
- [ ] Stats recorded; best scores/times shown where relevant.
- [ ] Heavy work (puzzle generation, AI search) runs off the main actor (`Task.detached` /
      `nonisolated` async) and never blocks UI; show a subtle progress state if it can take >150ms.
- [ ] No networking, no third-party code, no assets copied from other games; original names/look.
- [ ] **Opponent rule:** any game with an opponent offers both vs. computer and pass & play.
- [ ] Swift 6 strict concurrency clean, **zero warnings**.

## Commands

Each parallel task gets its own simulator and DerivedData path — use the ones assigned to you.

```sh
# Logic tests (fast, macOS)
swift test --package-path Packages/GameLogic

# Build the app
xcodebuild -project AirplaneModeGames.xcodeproj -scheme AirplaneModeGames \
  -destination 'platform=iOS Simulator,name=<DEVICE>' -derivedDataPath build/DD-<DEVICE> build -quiet

# Run your UI test only
xcodebuild test -project AirplaneModeGames.xcodeproj -scheme AirplaneModeGames \
  -destination 'platform=iOS Simulator,name=<DEVICE>' -derivedDataPath build/DD-<DEVICE> \
  -only-testing:AirplaneModeGamesUITests/<Game>UITests

# Launch straight into your game and screenshot it (DEBUG `-openGame <GameID rawValue>`)
tools/run-sim.sh "<DEVICE>" /path/to/shot.png -openGame <gameId>
xcrun simctl ui "<DEVICE>" appearance dark   # or light
```

Look at your screenshots (light + dark, and an iPad if assigned) and iterate until it looks great.

## Commits

Small, focused commits on your branch (e.g. logic+tests, then UI, then polish). Message style:

```
Add Sudoku generator with unique-solution guarantee

<optional body>

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
```

Never commit `build/`.
