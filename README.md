# Airplane Mode Games ✈️

A collection of beautifully crafted, **fully offline** games for long flights.
No ads. No accounts. No tracking. No internet connection — ever.

## Games

2048 · Sudoku · Solitaire · Block Puzzle · Tile Match · Minesweeper · Chess ·
Word Guess · Nonograms · Word Search · Snake · Hangman

Chess, Word Guess and Hangman support pass-and-play with a friend on the same device.

## Requirements

- Xcode 16 or newer
- iOS / iPadOS 17.0+

## Building

Open `AirplaneModeGames.xcodeproj` in Xcode and run the `AirplaneModeGames` scheme.

## Testing

Game logic lives in a dependency-free Swift package and can be tested from the command line:

```sh
swift test --package-path Packages/GameLogic
```

UI tests run through Xcode or:

```sh
xcodebuild test -project AirplaneModeGames.xcodeproj -scheme AirplaneModeGames \
  -destination 'platform=iOS Simulator,name=iPhone 17'
```

## Privacy

The app collects no data and contains no networking code. See `docs/DESIGN.md`.

## License

MIT — see [LICENSE](LICENSE).
