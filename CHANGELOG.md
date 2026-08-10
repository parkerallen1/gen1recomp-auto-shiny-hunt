# Changelog

Format: [keep a changelog](https://keepachangelog.com/en/1.1.0/).
Version headings match `manifest.json`'s `version`.

## 0.7.3

### Changed

- **The focus timer is findable now.** It was behind two gates at once: its
  `FOCUS TIMER` option shipped **off**, and even switched on the `F` chip
  drew at one HUD size out of three -- so the way in was a setting you had
  to already know existed. `FOCUS TIMER` now defaults **on**, and `F` draws
  at the normal *and* full sizes. Switching the option off still removes the
  chip entirely, and an explicit `off` already saved is untouched.
- `F` is deliberately **not** on the mini pill, which is the HUD's placement
  rule made explicit: a control you might need *urgently* is on every size
  (that is `II`, because a hunt you cannot stop is a trap), and a feature
  you go looking for is where there is room for it. Mini exists to be out of
  the way, and its pill is already one tap back to the panel.

## 0.7.2

### Fixed

- **A saved target list silently fled shinies during ordinary hunting.**
  Targeting was documented as a FOCUS-session feature, but the target test
  ran on every wild battle -- only the "how many were skipped" counter was
  session-scoped. Since the list is saved, one left behind after a session
  kept running from every off-target shiny forever after, with no vibrate,
  no border, no tag and nothing counting it. That is this mod's headline
  promise broken in the most expensive way available. The list now binds
  only while a session is running; outside one it is ignored entirely and
  every shiny is held, whatever is on it.
- **A game text box could draw on top of a FOCUS session's cover.**
  `render.compose` refusing to blit the game's canvases settles the engine's
  own composite and nothing else: a peer mod that wraps `render.hud` at a
  higher priority than this mod's (Gen1 Modern UI is at 100; `mod.hooks:wrap`
  defaults to 0) runs first and draws in window space, landing on top of the
  cover. A fishing verdict box (`Oh! It's a bite!`) was caught doing exactly
  that over a running countdown. The cover is now three layers: every screen
  is taken off the draw list for the duration (`screen.render_visible`), the
  composite is still refused, and `render.hud` paints its own opaque
  full-window ground before drawing the countdown -- so anything drawn by an
  outer link is covered rather than merely un-composited.

## 0.7.1

### Fixed

- **A running hunt could not be stopped from inside itself.** The shuffle
  re-presses its direction in the same tick the previous step lands, so the
  player is permanently mid-step -- and `OverworldState:handleInput` drops A
  and START entirely while `player.moving`. The only control was `AUTO HUNT`
  in OPTIONS -> MOD SETTINGS, behind exactly the menu a running hunt makes
  hard to open, which left a hunt you had to wait out. There are now two
  ways to stop one that do not need the menu:
  - a `II` / `>` chip on the HUD, at **all three sizes** (a pointer press
    reaches the mod regardless of what is holding a button down), and
  - **holding SELECT for a second**, which needs no HUD at all, so it still
    works with `SHOW HUD` off or on a device with no touchscreen. SELECT
    alone only: the engine reads SELECT + shoulder as a display chord, so
    the gesture ignores SELECT with A, B or START held.

  Pausing releases the held direction, stops the auto-flee's A mash
  mid-battle, stops casting in FISH mode, hands `GAME SPEED` back (a 10X
  hunt is otherwise unplayable while you try to escape it), and parks the
  clock. Counts, the clock and the species list keep their totals. A pause
  is deliberately not persisted -- after a restart the title screen has no
  overworld, so nothing is held and the settings are reachable normally.

### Changed

- The tag for `AUTO HUNT` being off now reads `HUNT OFF` rather than
  `HUNT PAUSED`, so it cannot be confused with the new `PAUSED`. They are
  different states with different remedies: `PAUSED` is one tap from
  running again, `HUNT OFF` is the player's saved setting.
- Starting a FOCUS session lifts a pause, since starting one is an explicit
  "hunt now". Neither pause control does anything during a session -- the
  cover owns the screen and `END` is the documented way out.

## 0.7.0

### Added

- **Fishing**: a new `HUNT MODE` option picks between `WALK` (the shuffle,
  unchanged and still the default) and `FISH`. In `FISH` mode the mod never
  moves the player: it casts a rod at the water the character is already
  facing, mashes through the engine's own `. . .` and verdict boxes, and
  casts again -- for as long as the hunt runs. A hooked encounter arrives as
  an ordinary wild battle, so every shiny check, flee, encounter count,
  FOCUS target and blackout rule applies to it with nothing added. `ROD`
  chooses which rod to cast; `BEST OWNED` (the default) takes the highest
  tier actually in the bag, and a rod that is not in the bag is never used.
  Because it does not need the classic step-based roll, this also works on a
  setup where that roll is switched off -- Wilds of Kanto with `RANDOM ENC`
  off included.
- The HUD tag names why a rod is not casting -- `FACE WATER`, `NO ROD`,
  `SURFING` -- instead of the bare `HUNT IDLE` the shuffle shows, since
  every one of those is fixable from where the player is standing. The
  FOCUS offer panel says the same thing before a session starts, rather
  than covering the screen for 25 minutes over a rod that cannot cast.

### Changed

- The hunting clock counts a cast's own text boxes as hunting -- they are
  the hunt's screen, not a menu interrupting it. A menu the mod did not put
  up still parks the clock exactly as before.
- `KEEP SCREEN AWAKE` now applies whenever `AUTO HUNT` is on, rather than
  only on the ticks the hunt was unblocked. `FISH` mode spends most of its
  cycle behind a text box, which sat on the blocked side of that check.

## 0.6.0

### Added

- **Focus timer**: a fixed-length hunting session (5-60 minutes, `FOCUS
  LENGTH`) for hunting while doing something else. `FOCUS TIMER` adds an
  `F` chip to the corner HUD; starting a session covers the screen
  entirely and shows nothing but a countdown until it reaches zero --
  no vibrate, no pulsing border, no `SHINY!` tag, and the clock itself is a
  raw wall-clock timer rather than the hunting clock, so a found shiny
  parking the shuffle can never be inferred from a stalled number. Tapping
  the screen peeks a static card (session length, targets) that never
  shows encounter counts, since a parked count would itself leak a find.
  Music is muted for the session (no hook exists for battle SFX, so that
  residual leak is documented rather than hidden). Ending a session early
  requires a confirmation worded identically whether or not anything is
  waiting, and then runs from whatever wild battle is open -- a held shiny
  included, so ending early costs you the find. At zero the screen returns,
  every suppressed alert fires, and a summary reports what happened until
  dismissed.
- **Targets**: pick one or more species (or none, for "any shiny") from a
  full scrollable species list via the engine's own list screen, persisted
  in the savefile. During a session, a shiny that is not one of the current
  targets is fled rather than held -- irreversible, so the summary always
  reports how many were skipped this way.

### Fixed

- `KEEP SCREEN AWAKE` stopped applying the moment a found shiny parked the
  hunt (its own apply sat behind the hunting-blocked early return in the
  same tick), which would have let a Focus session's device sleep on
  exactly the runs it most needed to stay lit. A session now holds the
  screen awake unconditionally, independent of AUTO HUNT.
- The README's Setup section still said `SPEED CAP` was 4X by default; it
  has been 10X since 0.5.0.
- The README pointed at `docs/launcher.md`, an engine-repo path that does
  not exist in this repo.

## 0.5.1

### Changed

- The hunting clock was too strict in 0.5.0: it parked for any battle this
  mod wasn't itself fleeing from, and for a shiny sitting on screen. Battles
  now count -- every kind, however long they stay up -- because the fight is
  part of the hunt's cycle and a shiny left on screen is the hunt holding
  its result out for you. A menu opened inside a battle (party, bag) counts
  too. What still parks it is what was actually meant: a menu or dialog over
  the overworld, the title screen, a load, or anywhere else the shuffle
  cannot walk.
- Returning to the overworld now clears the mod's in-battle flag as well as
  `battle.ended` does, so a missed end event can't leave the clock running
  forever.

## 0.5.0

### Changed

- `SPEED CAP` now tops out at **10X** (the engine's next ladder rung above
  4X) and defaults to it. The tighter rungs -- 4X, 3X, 2X, 1X -- are still
  there; there is still no way to set it looser than the ceiling.
- The cap now lasts exactly as long as `AUTO HUNT` does. It already only
  *applied* while hunting, but it left GAME SPEED where it had pushed it:
  turning the hunt off now hands back the speed you had set, the same way a
  `--speed` / `POKEPORT_SPEED` launch argument was already handed back. If
  you climb the ladder again mid-hunt it is the most recent choice that
  comes back, and a value something else changed while the cap held it down
  is left alone.
- The HUD clock now counts **time spent hunting** rather than time since
  AUTO HUNT was switched on. It parks while a menu, a dialog, the title
  screen or a load is up, before the shuffle has started walking (so a boot
  straight into a hunting save no longer counts the loading screen), and
  while a shiny is sitting on screen -- so the number you pick the phone up
  to is how long the hunt actually took. The mod's own flees still count;
  they are part of the cycle.
- The HUD's status tag says which of those it is: `HUNT ON`, `HUNT IDLE`
  (on, but the clock is parked), `HUNT PAUSED` or `SHINY!`, so a clock that
  is not moving explains itself.

### Compatibility

- Verified against the `artyrambles/DRAMALESS_SHAPE` fork (v1.6.4), which is
  where the voxel mod has moved: no shared hooks, and because it forked
  before upstream's shiny work it has no shiny feature and never touches
  `Pokemon.new` -- so the standalone Shiny Pokemon mod is the shiny source
  alongside it, with nothing to turn off. The README's shiny-source and
  camera-rung notes now cover both it and the upstream mod, whose repo
  stopped resolving on 2026-08-10.

## 0.4.1

### Fixed

- `game_version` was `>=0.0.0-dev <1.0.0`, so the mod would have refused to
  load the day the engine shipped 1.0. It is now
  `0.0.0-dev || >=0.1.69 <2.0.0`: 0.1.69 is where `input.pointer` landed
  (it is absent in 0.1.68), and without it the HUD's tap chips cannot be
  reached at all.

### Added

- `tests/` -- a stand-in engine (hook bus with the real priority/`next`
  chaining, a recording `love.graphics`) and the mod's own checks, run with
  `./tests/run.sh` and no LOVE install. Covers the speed cap, shiny
  detection through both DVs and the `mon.shiny` cache, the walk shuffle's
  interrupt handling, HUD layout at five window sizes, the tap targets, and
  a peer mod wrapping the same three HUD hooks at a higher priority.
- `compat/upstream.json` and a weekly `upstream-watch` workflow: it compares
  the engine and the four peer mods against the versions this mod has been
  read against, and opens a single issue when one of them releases.
- A Compatibility section in the README: which versions were checked, why
  Wilds of Kanto's RANDOM ENC has to stay on, why Dramatic Shape's
  first/third-person camera rungs are the wrong place to hunt, and what to
  do now that both Dramatic Shape 1.8.1 and the Shiny Pokemon mod roll
  shinies.

### Changed

- The packed release `.zip` no longer carries `tests/` or `compat/`.

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
