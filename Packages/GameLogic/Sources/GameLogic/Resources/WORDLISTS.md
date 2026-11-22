# Word lists

All word data bundled with the app is either public domain or original to this project.

| File | Contents | Source | License |
|------|----------|--------|---------|
| `guesses5.txt` | Every accepted 5-letter guess (8,643 words, lowercase a–z) | The ENABLE word list (*Enhanced North American Benchmark Lexicon*, `enable1.txt`), filtered to 5-letter words, plus 7 modern everyday words written for this project (`admin`, `bicep`, `email`, `emoji`, `inbox`, `login`, `ramen`). Downloaded from <https://raw.githubusercontent.com/dolph/dictionary/master/enable1.txt> | Public domain (ENABLE was explicitly placed in the public domain by its author, Alan Beale) |
| `answers5.txt` | ~2,050 familiar 5-letter words the computer may choose | Hand-curated for this project from familiar everyday English (no proper nouns, no plurals of 4-letter words, no obscure words), then checked against `guesses5.txt` and `blocklist.txt` | Original, MIT (this repository) |
| `blocklist.txt` | Offensive words never chosen by the computer | Written for this project | Original, MIT (this repository) |
| `WordCategories.swift` (in `Words/`) | Themed categories for Hangman and Word Search | Written for this project | Original, MIT (this repository) |

## Rules

- Computer-chosen content (Word Guess answers, Hangman words, Word Search words) never contains a
  blocklisted word; unit tests enforce this.
- Words typed by a friend in Pass & Play are only checked for validity (Word Guess) or allowed
  characters (Hangman), never for profanity — players are adults.

## Regenerating

`guesses5.txt` = 5-letter lines of `enable1.txt` ∪ the supplement above ∪ `answers5.txt`, sorted.
