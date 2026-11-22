# Airplane Mode Games — Design

A collection of polished, fully offline games for long flights.
No ads, no accounts, no analytics, no network code. Everything is local.

## Principles

1. **Offline by construction.** The app never imports networking APIs. No third-party
   dependencies. All content (word lists, puzzles) is bundled or generated on device.
2. **Quality over quantity.** Every game ships with: auto-save/resume, undo where it
   makes sense, difficulty levels, stats, haptics, synthesized sound effects (mutable),
   a "How to play" sheet, dark mode, Dynamic Type and VoiceOver support.
3. **Testable logic.** All game rules, generators, solvers and AI live in the
   `GameLogic` Swift package, free of UIKit/SwiftUI, and are unit-tested with
   `swift test` (runs on macOS in seconds).
4. **Deterministic where possible.** Generators take a seedable RNG so tests are
   reproducible.
5. **Original presentation.** We implement well-known genres and public-domain game
   mechanics with our own names, visuals and content.

## Platform

- iOS / iPadOS 17.0+, SwiftUI, Swift 6, `@Observable`.
- Bundle ID: `com.gchapiewski.airplanemodegames`.

## Repository layout

```
AirplaneModeGames.xcodeproj
AirplaneModeGames/            App target (SwiftUI)
  App/                        Entry point, root navigation
  DesignSystem/               Colors, typography, reusable components
  Services/                   Persistence, settings, stats, haptics, sound
  Home/                       Game catalog
  Games/<Game>/               One folder per game (views + view model)
AirplaneModeGamesUITests/     UI smoke tests
Packages/GameLogic/           Swift package: pure game logic + tests
  Sources/GameLogic/Core/     RNG, grid helpers, shared protocols
  Sources/GameLogic/<Game>/   One folder per game
  Tests/GameLogicTests/       Unit tests
docs/                         Design notes
```

## Game catalog (v1)

| Game | Id | Pass & play |
|------|----|-------------|
| 2048 | `twentyFortyEight` | — |
| Sudoku | `sudoku` | — |
| Solitaire (Klondike) | `solitaire` | — |
| Block Puzzle | `blocks` | — |
| Tile Match (Mahjong solitaire) | `tileMatch` | — |
| Minesweeper | `minesweeper` | — |
| Chess | `chess` | ✅ vs. computer (levels) or vs. human on same device |
| Word Guess | `wordGuess` | ✅ computer or a friend picks the secret word |
| Nonograms | `nonograms` | — |
| Word Search | `wordSearch` | — |
| Snake | `snake` | — |
| Hangman | `hangman` | ✅ computer or a friend picks the secret word |

**Opponent rule:** any game with an opponent offers both *vs. computer* and
*pass & play vs. a human* on the same device.

## Conventions

- Each game's logic is namespaced under a caseless `enum` (e.g. `Sudoku.Board`).
- Game state types are value types, `Codable`, `Equatable`, `Sendable`.
- View models are `@MainActor @Observable` classes in the app target. They own the
  logic state, persist it through `GameStore`, and trigger haptics/sound.
- Persistence: one JSON file per game in Application Support (`GameStore`).
- Stats: games played/won, best score/time, streaks (`StatsStore`).
- Sounds are synthesized at runtime with `AVAudioEngine` — no audio assets.
  Audio session uses `.ambient` so the silent switch and other audio are respected.

## Word lists

English only for v1. Word lists are derived from public-domain sources and filtered
for offensive words.
