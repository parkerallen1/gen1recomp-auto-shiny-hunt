# Changelog

Format: [keep a changelog](https://keepachangelog.com/en/1.1.0/).
Version headings match `manifest.json`'s `version`.

## 0.2.0

### Fixed

- Non-shiny wild encounters no longer stall on "Wild X appeared!" waiting
  for a manual A press -- the mod now mashes A itself for the duration of
  its own auto-flee.
- The walk-shuffle no longer presses directions while any menu, dialog, or
  other non-overworld screen is on top of the stack (was making the
  Options menu unusable while AUTO HUNT was on).

## 0.1.0

### Added

- `AUTO HUNT` toggle: shuffles the player between two configurable
  directions to keep triggering classic step-based wild encounters.
- Auto-flees any non-shiny wild encounter (never touches trainer/Safari
  battles, never affects a manually-pressed RUN).
- Detects Gen 1's real virtual-shiny DV pattern directly off the wild
  Pokemon's own DVs, so it stays correct alongside any other mod that
  rerolls DVs for its own shiny rate.
- Vibrate + pulsing battle-screen border alert on a shiny.
- Keeps the display awake while hunting (the app pauses if Android sleeps
  the screen).
