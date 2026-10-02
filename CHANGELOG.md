# Changelog

All notable changes to this project will be documented in this file.

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
