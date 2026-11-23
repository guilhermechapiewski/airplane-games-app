# Airplane Games ✈️

*On the App Store as **Airplane Games: Offline Fun**.*

A collection of beautifully crafted, **fully offline** games for long flights.
No ads. No accounts. No tracking. No internet connection — ever.

## Games

| Game | Highlights |
|------|-----------|
| **2048** | Smooth slide & merge animations, undo, best score |
| **Sudoku** | 4 levels graded by solving technique, unique solutions, notes, explained hints |
| **Solitaire** | Klondike draw 1 / draw 3, solver-checked winnable deals, auto-complete |
| **Block Puzzle** | Drag pieces onto an 8×8 board, row & column clears, combos and streaks |
| **Tile Match** | Mahjong-style tile matching, 6 original layouts, always-solvable deals |
| **Minesweeper** | No-guess boards (always solvable by logic), safe first tap, chording, flag mode, pinch to zoom |
| **Chess** | vs. computer (5 levels) or pass & play, full rules, move list |
| **Word Guess** | 5-letter word in 6 tries, hard mode, high-contrast colors, pass & play |
| **Nonograms** | 44 original picture puzzles, all solvable by logic alone, explained hints |
| **Word Search** | 15 themes, 3 sizes, drag selection that snaps to 8 directions |
| **Snake** | Fluid motion, 3 speeds, walls or wrap-around, swipe or D-pad |
| **Hangman** | Friendly hot-air balloon illustration, categories, pass & play |

Sudoku, Word Guess, Solitaire, Minesweeper, Word Search and Tile Match have a **daily puzzle**,
generated from the date (the same for everyone that day, no network) with day streaks.
Every game auto-saves and resumes, keeps local statistics, supports light & dark mode,
iPhone & iPad, VoiceOver, and has sound effects and haptics that can be turned off.
Games with an opponent can be played against the computer **or** a friend on the same device.

## Requirements

- Xcode 16 or newer
- iOS / iPadOS 17.0+

## Building

Open `AirplaneModeGames.xcodeproj` in Xcode and run the `AirplaneModeGames` scheme.

## Testing

```sh
tools/test.sh          # everything
tools/test.sh unit     # GameLogic tests on macOS, optimized build (~5 s warm)
tools/test.sh ui       # UI tests across 4 parallel simulator clones (~5 min)
tools/test.sh ui -only-testing:AirplaneModeGamesUITests/SnakeUITests
```

`DEVICE=<simulator name>` and `WORKERS=<n>` override the simulator and the number of clones.
Under UI tests (`-uiTesting`) the app behaves as if Reduce Motion were on, so looping SwiftUI
animations can't keep XCUITest waiting for the app to go idle; views read `\.reduceMotion`
rather than `\.accessibilityReduceMotion` for this reason.

## Architecture

- `Packages/GameLogic` — pure Swift package with all rules, generators, solvers and AI.
  No UI code; fully unit-tested (270+ tests).
- `AirplaneModeGames/` — SwiftUI app: shared design system and services, one folder per game.
- `docs/DESIGN.md` — principles and layout; `docs/GAME_GUIDE.md` — how to add a game.
- `tools/` — app icon renderer, simulator launcher (`run-sim.sh`), screenshot contact sheets.

## Privacy

The app collects no data and contains no networking code. See `docs/DESIGN.md`.

## License

MIT — see [LICENSE](LICENSE).
