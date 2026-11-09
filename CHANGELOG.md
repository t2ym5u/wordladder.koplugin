# Changelog

All notable changes to this project will be documented in this file.

## [1.4.1] - 2026-11-09

### Fixed
- The game now starts in KOReader's language (French when KOReader is in
  French) instead of always English; a language picked in the game holds
  until KOReader's language changes.

## [1.4.0] - 2026-11-05

### Changed
- The three levels now really differ: the target sits at an exact fewest
  number of steps from the start word -- Easy 2-3, Medium 4-5, Hard 6-9.
  Before, a level only set the length of a random walk, and any ladder of
  2 steps or more was accepted, so Hard (mean 3.6 steps in English) was
  barely longer than Easy (2.5). A word length or language with no such
  ladder from the start words tried gets the closest one. The puzzle a
  seed gives is now the same on every device (the word list is sorted).

### Fixed
- "Lynch" and its forms (LYNCHED, LYNCHING, LYNCHERS...; LYNCHAGE,
  LYNCHER... in French) are added to the family-friendly blocklist, so the
  game never draws or reveals them. They are still accepted when typed.

## [1.3.2] - 2026-11-05

### Fixed
- English puzzles no longer start or end on first names, places, brands,
  abbreviations or foreign words (Aaron, Cairo, Buick, ASAP...): 622 such
  words are gone from the English list, which keeps only dictionary words
  (plus email, login, admin, cyber, spam, manga and tech). They are no
  longer accepted as steps either.

## [1.3.1] - 2026-11-04

### Fixed
- A game no longer crashes when an outdated plugin is installed alongside:
  shared modules left behind by an older plugin are replaced by this
  plugin's own copy instead of being used as they are.

## [1.3.0] - 2026-11-04

### Changed
- Bigger keys in landscape: the keyboard panel beside the ladder takes half
  the screen instead of 36 %, so each key is about 40 % wider. Portrait is
  unchanged.
- Needs game-common 1.13.0.
- Uses less memory: the game loads when you open it, not when KOReader
  starts, so it no longer takes memory or startup time while unplayed.
- Uses less memory: the word lists load when the game opens, only for the
  language played, and are freed when it closes.

## [1.2.0] - 2026-11-04

### Changed
- Faster new puzzles: each word's one-letter neighbours are looked up
  instead of comparing it with every word of the same length, and the word
  list is built once instead of for every puzzle. A 4-letter Hard ladder
  went from up to 0.1 s on a desktop (2 s on a reader) to under 0.01 s.
  Same puzzles as before.

## [1.1.3] - 2026-11-03

### Changed
- Picks up game-common 1.11.0: the shared on-screen keyboard (where used)
  gives every key the same letter size, and the no-repeat history helper.

## [1.1.2] - 2026-11-02

### Changed
- Family-friendly words: the start and target words and the solution path
  behind the hints are never vulgar, sexual, scatological, slur or
  drug-related any more (`blocklist.lua`) -- 42 English and 44 French words.
  They stay in the dictionary.

## [1.1.1] - 2026-11-02

### Changed
- Listed under **Tools → Games**, grouped by category, instead of its own
  entry in the Tools menu (game-common 1.9.1).

## [1.1.0] - 2026-10-30

### Changed
- Redesigned play screen: the ladder fills the room the keyboard leaves,
  every row at the same size, and Hint and Undo moved from the title-bar menu
  to a full-width bar under the keyboard. The keys are finger-sized.
- A long ladder keeps its newest words on screen: the oldest drop off the top
  behind "…" instead of running off the board.
- The title-bar menu follows the order every game uses: New game (was "New
  puzzle"), "Difficulty: …", "Language: …", "Length: …", Rules.
- The status line reads "Medium · Steps: 3" (the board already shows the
  start, target and every word) and wraps in landscape.
- The keyboard follows KOReader's language (AZERTY in French, QWERTZ in
  German) instead of the word list's language.
- Once the ladder is solved, the bar shows "New game" in place of Hint and
  Undo.

### Fixed
- Words were sized from the board height and then scaled again for the
  screen's DPI, so they could overflow the board; they are now measured to
  fit it.

## [1.0.14] - 2026-10-02

### Fixed
- Dropped this plugin's `Hint` override. `package.loaded` is keyed by module
  name alone, so every `require("i18n")` on the device resolves to one module
  and the first plugin loaded wins it. Every plugin's `i18n_fr.lua` merges
  into that one shared table, where plugins silently overwrite each other's
  translations. This one rendered `Hint` as "Indice", overwriting game-
  common's "Astuce" for the whole fleet because it happened to merge last. The
  shared value now stands.

## [1.0.13] - 2026-10-01

### Fixed
- Picks up game-common v1.5.0. Play statistics were recorded under a key no
  tool could match: `ReaderUI`/`FileManager:registerModule()` rewrite a plugin
  instance's `name` to `reader<id>` / `filemanager<id>` right after it is
  built, so this game's sessions were split across two rows and neither
  carried its plugin id. Rows written under the old keys are merged back on
  first read. The same release brings the `stopPlugin()` /
  `deletePluginSettings()` hooks KOReader 2026.07 calls when a plugin is
  deleted from the device (PR #15240).

  No change to this plugin's own code -- it inherits all of it from the
  shared library.

## [1.0.6] - 2026-07-29

### Added
- French word ladders: a new "Language" menu (English/Français) lets
  puzzles be generated from a French dictionary (words_fr.lua) instead
  of English, using the same 3-5 letter, accent-stripped format as the
  English word list. The chosen language is remembered per saved puzzle.

### Changed
- Replaced the small hand-curated English 4-5 letter word list with
  anagram.koplugin's larger frequency-filtered set (Google Books top-N
  intersected with the dwyl dictionary), giving noticeably more puzzle
  variety in English and incidentally removing a duplicate entry
  ("lore" was listed twice) that existed in the old list.
