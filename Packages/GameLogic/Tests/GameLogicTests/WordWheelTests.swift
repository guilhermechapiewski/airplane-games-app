import Foundation
import Testing
@testable import GameLogic

@Suite("Word Wheel")
struct WordWheelTests {
    typealias W = WordWheel

    /// A small hand-made wheel: center A, ring E I N P R T.
    private let puzzle = W.Puzzle(center: "a", outer: Array("tnreip"),
                                  answers: ["painter", "paint", "pant", "rant", "train", "tear", "parent"])
    private let extras: Set<String> = ["pertain", "repaint", "tarp", "nape", "pine"]
    private func valid(_ w: String) -> Bool { puzzle.answers.contains(w) || extras.contains(w) }

    private func enter(_ word: String, into state: inout W.State) -> Result<W.Accepted, W.Rejection> {
        for ch in word { state.type(ch) }
        return state.submit(isValidWord: valid)
    }

    // MARK: Scoring

    @Test func scoring() {
        #expect(W.points(for: "pant", isPangram: false) == 1)
        #expect(W.points(for: "paint", isPangram: false) == 5)
        #expect(W.points(for: "parent", isPangram: false) == 6)
        #expect(W.points(for: "painter", isPangram: true) == 14)
        #expect(W.points(for: "pertaining", isPangram: true) == 17)
    }

    @Test func pangramDetection() {
        #expect(puzzle.isPangram("painter"))
        #expect(puzzle.isPangram("pertain"))
        #expect(puzzle.isPangram("paintier"))
        #expect(!puzzle.isPangram("parent"))
        #expect(puzzle.pangrams == ["painter"])
        #expect(puzzle.maxPoints == 14 + 5 + 1 + 1 + 5 + 1 + 6)
    }

    @Test func puzzleNormalizesLetters() {
        #expect(puzzle.center == "a")
        #expect(puzzle.outer == ["e", "i", "n", "p", "r", "t"])
        #expect(puzzle.answers == puzzle.answers.sorted())
        #expect(puzzle.letters == Set("aeinprt"))
    }

    // MARK: Validation

    @Test func rejectsWithTheRightReason() {
        var s = W.State(puzzle: puzzle)
        do { let r = enter("pan", into: &s); #expect(r == .failure(.tooShort)) }
        do { let r = enter("tern", into: &s); #expect(r == .failure(.missingCenter)) }
        do { let r = enter("tarn", into: &s); #expect(r == .failure(.notInList)) }
        do { let r = s.enter("plant", isValidWord: valid); #expect(r == .failure(.badLetters)) }
        #expect(s.score == 0 && s.found.isEmpty)
        do { let r = enter("paint", into: &s); #expect(r.isSuccess) }
        do { let r = enter("paint", into: &s); #expect(r == .failure(.alreadyFound)) }
        #expect(s.score == 5)
    }

    @Test func acceptsAnswersBonusWordsAndPangrams() throws {
        var s = W.State(puzzle: puzzle)
        let pant = try enter("pant", into: &s).get()
        #expect(pant.points == 1 && pant.isAnswer && !pant.isPangram)
        let tarp = try enter("tarp", into: &s).get()
        #expect(!tarp.isAnswer && tarp.points == 1)
        let bonusPangram = try enter("pertain", into: &s).get()
        #expect(bonusPangram.isPangram && !bonusPangram.isAnswer && bonusPangram.points == 14)
        let painter = try enter("painter", into: &s).get()
        #expect(painter.isPangram && painter.isAnswer)
        #expect(s.found == ["pant", "tarp", "pertain", "painter"])
        #expect(s.foundAnswers == ["pant", "painter"])
        #expect(s.bonusWords == ["tarp", "pertain"])
        #expect(s.missedAnswers == ["paint", "parent", "rant", "tear", "train"])
        #expect(s.score == 1 + 1 + 14 + 14)
    }

    @Test func typingOnlyTakesWheelLetters() {
        var s = W.State(puzzle: puzzle)
        do { let r = s.type("P"); #expect(r) }
        do { let r = s.type("z"); #expect(!r) }
        do { let r = s.type("1"); #expect(!r) }
        do { let r = s.type("a"); #expect(r) }
        #expect(s.input == "pa")
        do { let r = s.deleteLetter(); #expect(r) }
        #expect(s.input == "p")
        s.clearInput()
        do { let r = s.deleteLetter(); #expect(!r) }
        for _ in 0..<40 { s.type("a") }
        #expect(s.input.count == W.maxInputLength)
        _ = s.submit(isValidWord: valid)
        #expect(s.input.isEmpty)
    }

    @Test func finishedWheelTakesNoInput() {
        var s = W.State(puzzle: puzzle)
        s.type("p")
        s.finish()
        #expect(s.isFinished && s.input.isEmpty)
        do { let r = s.type("a"); #expect(!r) }
        do { let r = s.enter("paint", isValidWord: valid); #expect(r.isFailure) }
        #expect(s.missedAnswers.count == puzzle.answers.count)
    }

    @Test func shuffleAlwaysMovesSomething() {
        var s = W.State(puzzle: puzzle)
        var rng = SeededRandom(seed: 1)
        for _ in 0..<50 {
            let before = s.ring
            s.shuffle(using: &rng)
            #expect(s.ring != before)
            #expect(s.ring.sorted() == puzzle.outer)
        }
        s.setRing(["z", "y", "x", "w", "v", "u"])
        #expect(s.ring.sorted() == puzzle.outer)
        s.setRing(["t", "r", "p", "n", "i", "e"])
        #expect(s.ring == ["t", "r", "p", "n", "i", "e"])
    }

    // MARK: Ranks

    @Test func rankThresholds() {
        typealias R = W.Rank
        #expect(R.allCases.map(\.title) == ["Starter", "Good", "Great", "Amazing", "Genius"])
        #expect(R.allCases.map { $0.threshold(maxPoints: 200) } == [0, 20, 50, 100, 140])
        #expect(R.great.threshold(maxPoints: 101) == 26)   // rounds up
        #expect(R.rank(points: 0, maxPoints: 200) == .starter)
        #expect(R.rank(points: 19, maxPoints: 200) == .starter)
        #expect(R.rank(points: 20, maxPoints: 200) == .good)
        #expect(R.rank(points: 49, maxPoints: 200) == .good)
        #expect(R.rank(points: 50, maxPoints: 200) == .great)
        #expect(R.rank(points: 139, maxPoints: 200) == .amazing)
        #expect(R.rank(points: 999, maxPoints: 200) == .genius)
        #expect(R.solved == .great)
        #expect(R.starter.next == .good && R.genius.next == nil)
    }

    @Test func rankUpIsReported() throws {
        var s = W.State(puzzle: puzzle)   // max 33: good at 4, great at 9
        let first = try enter("pant", into: &s).get()
        #expect(!first.rankedUp)
        let second = try enter("paint", into: &s).get()
        #expect(second.rankedUp && second.rankAfter == .good)
        let third = try enter("parent", into: &s).get()
        #expect(third.rankAfter == .great && s.rank == .great)
    }

    // MARK: Persistence

    @Test func codableRoundTrip() throws {
        var s = W.State(puzzle: puzzle)
        var rng = SeededRandom(seed: 9)
        s.shuffle(using: &rng)
        _ = enter("paint", into: &s)
        _ = enter("tarp", into: &s)
        s.type("r")
        let data = try JSONEncoder().encode(s)
        let back = try JSONDecoder().decode(W.State.self, from: data)
        #expect(back == s)
        #expect(back.input == "r" && back.score == 6 && back.ring == s.ring)
    }

    // MARK: Dictionary

    @Test func dictionaryFiltersAndMasks() {
        let d = W.Dictionary(answers: ["Paint", "pain", "pan", "sand", "painter", "fuck", "paint"],
                             extras: ["tarp", "paint", "abcdefgh", "pants"])
        #expect(d.answers == ["pain", "paint", "painter"])
        #expect(d.isValid("tarp") && d.isValid("paint") && !d.isAnswer("tarp"))
        #expect(!d.isValid("pants") && !d.isValid("abcdefgh") && !d.isValid("fuck"))
        #expect(d.pangramMasks == [W.mask("painter")])
        #expect(d.answers(letters: W.mask("painter"), center: "t") == ["paint", "painter"])
    }

    @Test func bundledListsAreClean() {
        let d = W.Dictionary.bundled
        #expect(d.answers.count > 10_000)
        #expect(d.extras.count > 20_000)
        #expect(d.pangramMasks.count > 1_000)
        let blocked = WordLists.blocklist
        for w in d.answers {
            #expect(!blocked.contains(w), "\(w)")
            #expect(W.Dictionary.isEligible(w), "\(w)")
        }
        #expect(d.isValid("planet") && d.isAnswer("planet"))
    }

    // MARK: Generator

    private func checkGenerated(_ p: W.Puzzle, dictionary: W.Dictionary) {
        #expect(!p.pangrams.isEmpty, "no pangram: \(p.center) \(p.outer)")
        #expect(W.answerRange.contains(p.answers.count), "\(p.answers.count) answers")
        #expect(W.maxPointsRange.contains(p.maxPoints), "\(p.maxPoints) points")
        #expect(p.outer.count == 6 && p.letters.count == 7 && !p.letters.contains("s"))
        let blocked = WordLists.blocklist
        for w in p.answers {
            #expect(w.contains(p.centerLetter) && w.count >= 4 && w.allSatisfy(p.letters.contains), "\(w)")
            #expect(!blocked.contains(w) && WordLists.isClean(w), "\(w)")
            #expect(dictionary.isAnswer(w))
        }
        // The answers are exactly the dictionary's fitting familiar words.
        #expect(p.answers == dictionary.answers(letters: W.mask(p.outer.joined() + p.center), center: p.centerLetter))
    }

    @Test func generatorIsDeterministic() {
        var a = SeededRandom(seed: 42)
        var b = SeededRandom(seed: 42)
        #expect(W.generate(using: &a) == W.generate(using: &b))
        var c = SeededRandom(seed: 43)
        var d = SeededRandom(seed: 42)
        #expect(W.generate(using: &c) != W.generate(using: &d))
    }

    @Test func generatedWheelsAreGood() {
        let dictionary = W.Dictionary.bundled
        var seen = Set<W.Puzzle>()
        for seed in UInt64(0)..<200 {
            var rng = SeededRandom(seed: seed)
            let p = W.generate(using: &rng, dictionary: dictionary)
            checkGenerated(p, dictionary: dictionary)
            seen.insert(p)
        }
        #expect(seen.count > 180)
    }

    @Test func generationIsFast() {
        let dictionary = W.Dictionary.bundled
        let start = threadCPUTime()
        for seed in UInt64(0)..<50 {
            var rng = SeededRandom(seed: seed)
            _ = W.generate(using: &rng, dictionary: dictionary)
        }
        #expect((threadCPUTime() - start) / 50 < 0.1)
    }
}

private extension Result {
    var isSuccess: Bool { if case .success = self { true } else { false } }
    var isFailure: Bool { !isSuccess }
}
