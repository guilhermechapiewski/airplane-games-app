import SwiftUI

enum GameCategory: String, CaseIterable {
    case numbers = "Numbers"
    case logic = "Logic"
    case cards = "Cards & Tiles"
    case board = "Board"
    case words = "Words"
    case arcade = "Arcade"
}

/// The catalog of games. Order here is the order on the home screen.
enum GameID: String, CaseIterable, Identifiable, Codable, Sendable {
    case twentyFortyEight
    case sudoku
    case solitaire
    case blocks
    case tileMatch
    case waterSort
    case minesweeper
    case chess
    case dotsAndBoxes
    case wordGuess
    case wordWheel
    case nonograms
    case wordSearch
    case snake
    case hangman

    var id: String { rawValue }

    var title: String {
        switch self {
        case .twentyFortyEight: "2048"
        case .sudoku: "Sudoku"
        case .solitaire: "Solitaire"
        case .blocks: "Block Puzzle"
        case .tileMatch: "Tile Match"
        case .waterSort: "Water Sort"
        case .dotsAndBoxes: "Dots and Boxes"
        case .wordWheel: "Word Wheel"
        case .minesweeper: "Minesweeper"
        case .chess: "Chess"
        case .wordGuess: "Word Guess"
        case .nonograms: "Nonograms"
        case .wordSearch: "Word Search"
        case .snake: "Snake"
        case .hangman: "Hangman"
        }
    }

    var tagline: String {
        switch self {
        case .twentyFortyEight: "Slide and merge to 2048"
        case .sudoku: "Classic 9×9 number logic"
        case .solitaire: "Klondike patience"
        case .blocks: "Fit blocks, clear lines"
        case .tileMatch: "Match pairs of free tiles"
        case .waterSort: "Pour until each tube is one color"
        case .dotsAndBoxes: "Close boxes, claim the board"
        case .wordWheel: "Spell words around the center"
        case .minesweeper: "Clear the field safely"
        case .chess: "Vs. computer or a friend"
        case .wordGuess: "Find the word in 6 tries"
        case .nonograms: "Reveal the hidden picture"
        case .wordSearch: "Hunt for hidden words"
        case .snake: "Grow without crashing"
        case .hangman: "Guess letter by letter"
        }
    }

    var symbol: String {
        switch self {
        case .twentyFortyEight: "square.grid.2x2.fill"
        case .sudoku: "number.square.fill"
        case .solitaire: "suit.spade.fill"
        case .blocks: "square.stack.3d.up.fill"
        case .tileMatch: "rectangle.stack.fill"
        case .waterSort: "testtube.2"
        case .dotsAndBoxes: "circle.grid.3x3.fill"
        case .wordWheel: "circle.hexagonpath.fill"
        case .minesweeper: "flag.fill"
        case .chess: "crown.fill"
        case .wordGuess: "character.textbox"
        case .nonograms: "squareshape.split.3x3"
        case .wordSearch: "magnifyingglass"
        case .snake: "scribble.variable"
        case .hangman: "textformat.abc"
        }
    }

    var category: GameCategory {
        switch self {
        case .twentyFortyEight: .numbers
        case .sudoku, .minesweeper, .nonograms, .waterSort: .logic
        case .solitaire, .tileMatch: .cards
        case .chess, .dotsAndBoxes: .board
        case .wordGuess, .wordSearch, .hangman, .wordWheel: .words
        case .blocks, .snake: .arcade
        }
    }

    /// Two-stop gradient used for the game's card and accents.
    var colors: [Color] {
        switch self {
        case .twentyFortyEight: [Color(hex: 0xFFB547), Color(hex: 0xFF7A45)]
        case .sudoku: [Color(hex: 0x5B8CFF), Color(hex: 0x3A5BDB)]
        case .solitaire: [Color(hex: 0x2FBF71), Color(hex: 0x14845A)]
        case .blocks: [Color(hex: 0xA77BFF), Color(hex: 0x6A4BE0)]
        case .tileMatch: [Color(hex: 0xFF8FA3), Color(hex: 0xE0527A)]
        case .waterSort: [Color(hex: 0x4FD8E8), Color(hex: 0x1A9FB8)]
        case .dotsAndBoxes: [Color(hex: 0xD47BEA), Color(hex: 0xA044C2)]
        case .wordWheel: [Color(hex: 0x7C86F0), Color(hex: 0x4A4CC4)]
        case .minesweeper: [Color(hex: 0x8A9BB5), Color(hex: 0x56657E)]
        case .chess: [Color(hex: 0xC69B6D), Color(hex: 0x8B5E3C)]
        case .wordGuess: [Color(hex: 0x44C9C1), Color(hex: 0x1E9690)]
        case .nonograms: [Color(hex: 0xFF6F61), Color(hex: 0xD6453A)]
        case .wordSearch: [Color(hex: 0xFFD25A), Color(hex: 0xF0A500)]
        case .snake: [Color(hex: 0x7BD957), Color(hex: 0x3FA33A)]
        case .hangman: [Color(hex: 0x6EC6FF), Color(hex: 0x2F8FD8)]
        }
    }

    var accent: Color { colors[1] }

    /// The `GameStore` key holding an in-progress game, if any.
    var saveKey: String { "game.\(rawValue)" }
}
