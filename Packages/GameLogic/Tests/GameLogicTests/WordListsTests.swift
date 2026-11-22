import Foundation
import Testing
@testable import GameLogic

@Suite("Word lists")
struct WordListsTests {
    private func isLowercaseLetters(_ word: String) -> Bool {
        !word.isEmpty && word.unicodeScalars.allSatisfy { $0.value >= 97 && $0.value <= 122 }
    }

    @Test func listsLoadWithExpectedSizes() {
        #expect(WordLists.validGuesses.count > 8_000)
        #expect((1_500...2_500).contains(WordLists.answers.count))
        #expect(WordLists.blocklist.count > 50)
    }

    @Test func guessesAreFiveLowercaseLetters() {
        for word in WordLists.validGuesses {
            #expect(word.count == 5 && isLowercaseLetters(word), "bad guess entry \(word)")
        }
    }

    @Test func answersAreValidCleanAndUnique() {
        let answers = WordLists.answers
        #expect(Set(answers).count == answers.count)
        for word in answers {
            #expect(word.count == 5 && isLowercaseLetters(word), "bad answer \(word)")
            #expect(WordLists.validGuesses.contains(word), "\(word) is not a valid guess")
            #expect(!WordLists.blocklist.contains(word), "\(word) is blocklisted")
        }
    }

    @Test func includesPluralsAndCommonWords() {
        for word in ["cats", "dogs"] { #expect(!WordLists.isValidGuess(word)) }
        for word in ["cakes", "plane", "PLANE", "crane", "shirt", "email"] where word.count == 5 {
            #expect(WordLists.isValidGuess(word), "\(word) should be valid")
        }
        #expect(!WordLists.isValidGuess("zzzzz"))
        #expect(!WordLists.isValidGuess("abcde"))
    }

    @Test func randomAnswerIsDeterministicWithSeed() {
        var a = SeededRandom(seed: 7), b = SeededRandom(seed: 7)
        let first = (0..<10).map { _ in WordLists.randomAnswer(using: &a) }
        let second = (0..<10).map { _ in WordLists.randomAnswer(using: &b) }
        #expect(first == second)
        #expect(first.allSatisfy { WordLists.answers.contains($0) })
    }

    @Test func cleanCheckSplitsPhrases() {
        #expect(WordLists.isClean("ice cream"))
        #expect(WordLists.isClean("hello shell"))
        #expect(!WordLists.isClean("shit"))
        #expect(!WordLists.isClean("Holy Shit"))
        #expect(!WordLists.isClean("bull-shit"))
    }

    @Test func listsAreSafeToLoadConcurrently() async {
        await withTaskGroup(of: Int.self) { group in
            for _ in 0..<8 { group.addTask { WordLists.validGuesses.count + WordLists.answers.count } }
            var results = Set<Int>()
            for await r in group { results.insert(r) }
            #expect(results.count == 1)
        }
    }

    // MARK: Categories

    @Test func categoriesHaveEnoughCleanEntries() {
        #expect(WordCategory.all.count >= 13)
        #expect(Set(WordCategory.all.map(\.id)).count == WordCategory.all.count)
        for category in WordCategory.all {
            #expect((30...80).contains(category.entries.count), "\(category.id) has \(category.entries.count)")
            #expect(Set(category.entries).count == category.entries.count, "\(category.id) has duplicates")
            #expect(category.singleWords(maxLength: 8).count >= 15, "\(category.id) lacks short words")
            for entry in category.entries {
                #expect(WordLists.isClean(entry), "\(entry) is not clean")
                #expect(entry.contains { $0.isLetter })
                #expect(entry.allSatisfy { ("a"..."z").contains($0) || " -'".contains($0) }, "bad entry \(entry)")
                #expect(entry == entry.trimmingCharacters(in: .whitespaces) && !entry.contains("  "))
            }
        }
    }

    @Test func singleWordsFilterByLengthAndLetters() {
        let animals = WordCategory.named("animals")!
        let singles = animals.singleWords(minLength: 4, maxLength: 6)
        #expect(singles.contains("tiger"))
        #expect(!singles.contains("fox"))
        #expect(!singles.contains("polar bear"))
        #expect(!singles.contains("elephant"))
    }
}
