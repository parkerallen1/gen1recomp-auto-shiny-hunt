# Changelog

Format: [keep a changelog](https://keepachangelog.com/en/1.1.0/).
Version headings match `manifest.json`'s `version`.

## 0.4.0

### Added

- `SPEED CAP`: a hard ceiling on GAME SPEED while `AUTO HUNT` is on, 4X by
  default and 4X at the most -- the option can only pick a tighter cap
  (3X/2X/1X), never a looser one. The GAME SPEED row, the `1` hotkey and the
  shoulder buttons all still work, they just cannot leave the value above the
  cap. A `--speed` / `POKEPORT_SPEED` run argument is held down with it and
  handed back untouched when hunting stops.
- The HUD resizes: tap the `+` / `-` chips it draws for itself to go between
  a one-line pill, the corner panel, and a full-screen readout that takes the
  window over and shrinks the game into a picture-in-picture corner, so a
  shiny battle stays on screen (and keeps its pulsing border) at every size.
  Tapping the PiP itself is the quick way back to the full-size game.

### Changed

- The HUD now ranks what it shows at every size: the clock is the biggest
  thing on it, the encounter total next, the per-species breakdown last. The
  full-screen size fits as many species rows as the window has room for,
  in columns, instead of the corner panel's eight.
- Species with equal counts no longer swap places between frames.

## 0.3.0

### Fixed

- The walk-shuffle could repeat the same direction twice in a row when an
  encounter interrupted a step mid-hold (the flip that step earned was
  getting dropped), drifting the player off the original two tiles over
  time. Pending steps are now confirmed even while blocked, so every
  completed step reliably flips direction exactly once.

### Added

- `SHOW HUD` toggle (on by default, independent of `AUTO HUNT`): an
  on-screen readout of real wall-clock elapsed time (not game time --
  unaffected by GAME SPEED), total wild encounters, and a per-species
  encounter count.

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
