# Changelog

All notable changes to this project will be documented in this file.

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
