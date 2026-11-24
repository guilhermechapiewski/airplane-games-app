# Word lists

All word data bundled with the app is either public domain or original to this project.

| File | Contents | Source | License |
|------|----------|--------|---------|
| `guesses5.txt` | Every accepted 5-letter guess (8,643 words, lowercase a–z) | The ENABLE word list (*Enhanced North American Benchmark Lexicon*, `enable1.txt`), filtered to 5-letter words, plus 7 modern everyday words written for this project (`admin`, `bicep`, `email`, `emoji`, `inbox`, `login`, `ramen`). Downloaded from <https://raw.githubusercontent.com/dolph/dictionary/master/enable1.txt> | Public domain (ENABLE was explicitly placed in the public domain by its author, Alan Beale) |
| `answers5.txt` | ~2,050 familiar 5-letter words the computer may choose | Hand-curated for this project from familiar everyday English (no proper nouns, no plurals of 4-letter words, no obscure words), then checked against `guesses5.txt` and `blocklist.txt` | Original, MIT (this repository) |
| `wheelAnswers.txt` | 13,624 familiar words (4+ letters, ≤ 7 distinct letters, no "s") that Word Wheel expects as a wheel's answers | Words in **both** the 12dicts list `3of6game.txt` (words found in 3 of 6 advanced learner's dictionaries; entries marked `$`, `^` or `&` dropped) **and** `enable1.txt`, whose base form (after stripping a simple inflection such as -s, -ed, -ing, -er, -est, -ly, -y) is in the 12dicts core-vocabulary list `3esl.txt`; minus anything whose base form is in `blocklist.txt` or in a short project list of words not to expect (see below). 12dicts 6.0.2 by Alan Beale, downloaded from <http://downloads.sourceforge.net/wordlist/12dicts-6.0.2.zip> (linked from <http://wordlist.aspell.net/12dicts/>) | Public domain (12dicts ReadMe: "The 12dicts lists were compiled by Alan Beale. I explicitly release them to the public domain, but request acknowledgment of their use." Only `2of12inf` and the `2+2+3` lists are excepted, because they depend on AGID; neither is used.) ENABLE: public domain |
| `wheelGuesses.txt` | 30,963 more accepted Word Wheel guesses (scored as bonus words) | Every other `enable1.txt` word with 4+ letters, ≤ 7 distinct letters and no "s" | Public domain (ENABLE) |
| `blocklist.txt` | Offensive words never chosen by the computer | Written for this project | Original, MIT (this repository) |
| `WordCategories.swift` (in `Words/`) | Themed categories for Hangman and Word Search | Written for this project | Original, MIT (this repository) |

## Rules

- Computer-chosen content (Word Guess answers, Hangman words, Word Search words) never contains a
  blocklisted word; unit tests enforce this.
- Word Wheel never expects (or shows as "missed") a blocklisted word; a player may still type any ENABLE word.
- Words typed by a friend in Pass & Play are only checked for validity (Word Guess) or allowed
  characters (Hangman), never for profanity — players are adults.

## Regenerating

`guesses5.txt` = 5-letter lines of `enable1.txt` ∪ the supplement above ∪ `answers5.txt`, sorted.

### Word Wheel (`wheelAnswers.txt`, `wheelGuesses.txt`)

Wheels never use the letter "s" (so plurals can't flood them), so neither list holds words with an "s".
Steps (a ~60-line Python script; inputs: `enable1.txt`, `International/3of6game.txt` and `American/3esl.txt`
from 12dicts 6.0.2, and `blocklist.txt`):

1. ENABLE: lines matching `[a-z]+`. Eligible = length ≥ 4, no "s", at most 7 distinct letters.
2. `3of6game.txt`: drop lines annotated `$` (thinly attested), `^` (close variant) or `&` (alternate
   spelling); strip `+`/`!`; keep lines matching `[a-z]+`. `3esl.txt`: single lowercase words.
3. Base forms of a word: the word itself plus the word with one suffix stripped
   (-ies/-ied/-ier/-iest/-ily → -y; -es, -s, -ed, -d, -ing, -er, -r, -est, -st, -ly, -y, with "e" restored
   for -ed/-ing/-er/-est and doubled consonants undone, e.g. stopped → stop).
4. Answers = eligible words in both `3of6game` and ENABLE that have a base form in `3esl`, and no base form
   in `blocklist.txt` or in this list of words a wheel shouldn't expect: abortion barf boob bondage cocaine
   crotch cripple diarrhea dope fecal floozy genital genitalia goddamn gonorrhea grope harlot heroin idiot
   imbecile junkie lewd lynch midget naked nipple nude pee pimp poop puke rectal rectum tampon teat thong
   urine vomit wanton.
5. `wheelGuesses.txt` = eligible ENABLE words not in the answers. Both files sorted, one word per line.

Source checksums (SHA-256): `enable1.txt` 3f161302…c63b1a89, `12dicts-6.0.2.zip` 64ac1d35…48780e52.
