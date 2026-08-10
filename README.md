# Auto Shiny Hunt

Unattended shiny hunting. When AUTO HUNT is on, this mod keeps wild
encounters coming -- by shuffling the player between two directions in
grass, or by casting a rod at the water in front of them -- flees anything
that isn't shiny, and leaves a shiny battle on screen (with a vibrate +
pulsing border) so it's obvious at a glance.

"Shiny" is Gen 1's real virtual-shiny DV pattern (the one that makes the
one special Red Gyarados possible): DEF/SPD/SPC DVs = 10 and ATK DV in
{2,3,6,7,10,11,14,15}. Natural odds are 1/8192 per wild encounter -- that
can be a long unattended hunt on its own. If you also install the
community "Shiny Pokemon" mod (masterwebx) and raise its rate, this mod
still detects it correctly with no extra setup: it only reads the DVs a
wild Pokemon actually ends up with, however they got there.

## Setup

1. Install this mod (see the in-game mod importer for how to load a mod
   `.zip` on your device -- no rebuild needed).
2. Get into position for the **HUNT MODE** you want:
   - **WALK** -- stand somewhere with an open tile on two opposite sides
     (e.g. grass to the north, a path tile to the south), facing either
     direction.
   - **FISH** -- stand on the shore *facing the water*, with a rod in your
     bag. Nothing moves you in this mode, so where you leave the character
     standing is where it fishes.
3. OPTIONS -> MOD SETTINGS -> AUTO SHINY HUNT:
   - Turn on **AUTO HUNT**.
   - Set **HUNT MODE** (defaults to WALK).
   - WALK only: set **WALK DIR A** / **WALK DIR B** to the axis that's
     actually open where you're standing (defaults to UP/DOWN).
   - FISH only: set **ROD** (defaults to BEST OWNED); see below.
   - Leave **KEEP SCREEN AWAKE** on so the app doesn't get paused by the
     device sleeping. Plug the phone in -- this runs indefinitely.
   - **SPEED CAP** is 10X unless you pick a tighter one; see below.
4. Leave the phone. Every wild battle either resolves itself in a second
   or two (non-shiny) or stops and sits there (shiny) until you pick the
   phone back up.
5. Turn AUTO HUNT off before you want to play normally again -- it forces
   every one of its own flee attempts to succeed while it's on, but never
   touches a manual RUN you press yourself.

## Stopping it

**A running hunt owns the d-pad**, so you cannot simply walk away from it,
and the START menu is awkward to open while it does (the game ignores button
presses that land mid-step, and the shuffle keeps you mid-step). So the stop
button does not live in the menu:

- **Tap the `II` chip on the HUD.** It is on every HUD size, in the same
  place, and a tap works even while the mod is holding a direction down. It
  turns into `>` while paused; tap it again to carry on.
- **Or hold SELECT for a second.** Same toggle, no HUD needed -- this is the
  one that works with SHOW HUD off, or on a device with no touchscreen.
  SELECT on its own, though: the engine reads SELECT + a shoulder button as
  a display chord, so the gesture ignores SELECT with A, B or START held.

Pausing lets go of the held direction, stops the auto-flee mid-battle if one
is running, stops casting in FISH mode, hands **GAME SPEED** back (so a 10X
hunt stops being unplayable), and parks the clock. The HUD tag reads
`PAUSED`. Nothing is lost -- counts, the clock and the species list all keep
their totals.

A pause is "stop right now" and is not saved. Two things worth knowing:

- It is **not** the same as switching AUTO HUNT off, and the HUD says which
  is which: `PAUSED` is one tap from running again, `HUNT OFF` is your
  setting and only the settings screen changes it. If you want the hunt to
  stay off across a restart, switch the setting off.
- The **title screen is always safe**: there is no overworld there, so
  nothing is held and OPTIONS -> MOD SETTINGS is reachable normally. If you
  ever do get wedged, restarting the app and turning AUTO HUNT off from the
  title is the guaranteed way out.

During a FOCUS session neither control does anything -- the session owns the
screen and has its own **END** chip (see Focus timer below).

## Fishing

**HUNT MODE = FISH** casts a rod at the water tile the player is facing,
mashes through the `. . .` and `Not even a nibble!` / `Oh! It's a bite!`
boxes, and casts again -- indefinitely. A bite is an ordinary wild battle,
so everything else in this mod applies to it unchanged: the shiny check,
the auto-flee, the encounter counts, FOCUS targets, the lot.

It refuses exactly what the bag refuses:

| the HUD says | what to do |
| --- | --- |
| `FACE WATER` | you're facing land -- turn to the water |
| `NO ROD` | the rod you picked isn't in your bag |
| `SURFING` | rods don't work on the water; get back on land |

**ROD** picks which one to cast. **BEST OWNED** (the default) takes the
highest tier you actually have; a rod you don't own is never used, and the
mod never hands you one.

| rod | what it hooks | bite odds per cast |
| --- | --- | --- |
| **OLD ROD** | L5 Magikarp, everywhere | every cast |
| **GOOD ROD** | L10 Goldeen / Poliwag, everywhere | 1/3 |
| **SUPER ROD** | the map's own fishing group | up to 1/2 |

Those are the engine's numbers, not this mod's -- it calls the same code the
bag does, so the tables and the odds are wherever they already were. Worth
knowing which one you want: the Old Rod is the *fastest* hunt in encounters
per minute (it hooks every single cast) but it is Magikarp and only
Magikarp, while the Super Rod is the only way to reach anything else.

Fishing does not use the classic step-based encounter roll at all, so unlike
the WALK shuffle it still works on a setup where that roll is switched off
-- including Wilds of Kanto with **RANDOM ENC** off (see Compatibility).

## Speed cap

**SPEED CAP** holds GAME SPEED down **while AUTO HUNT is on, and only while
it is on**. It defaults to **10X**, which is also the highest it goes -- the
option only offers *tighter* caps (4X, 3X, 2X, 1X), never a looser one.

Nothing is taken away: the GAME SPEED options row, the `1` hotkey and the
shoulder buttons all still cycle, they just can't leave the value above the
cap for longer than a tick. Turn AUTO HUNT off and whatever you had set
comes straight back -- including a `--speed` / `POKEPORT_SPEED` launch
argument, handed back untouched. If you climb the ladder again mid-hunt, the
speed that comes back is the last one you asked for; if anything else moves
it while the cap is holding it down, that newer choice wins and the mod
drops its own.

## HUD

**SHOW HUD** (on by default, independent of AUTO HUNT) draws the elapsed
hunting clock, the total wild encounter count, and a per-species count
sorted highest first. The counts keep their totals through a pause (e.g.
while AUTO HUNT is off so you can catch a shiny) and only reset when the
game restarts or the mod reloads.

The clock is real wall-clock time, not game time -- the GAME SPEED setting
does not stretch it -- and it counts **time spent hunting**, not time since
you switched the mod on. It runs while the shuffle is walking and through
any battle, shiny ones included: a fight is part of the hunt's cycle, and a
shiny left on screen is the hunt holding its result out for you. It parks
for the things that aren't hunting at all:

- paused (tag reads `PAUSED`) -- see Stopping it above
- AUTO HUNT off (tag reads `HUNT OFF`)
- a menu or dialog over the overworld, the title screen, a load, or anywhere
  else the shuffle can't walk (tag reads `HUNT IDLE`)

A menu opened *inside* a battle -- the party screen, the bag -- doesn't park
it; that's still the battle. In FISH mode a cast's own `. . .` and verdict
boxes don't park it either, for the same reason: they're the hunt's screen,
not something interrupting it. A menu this mod didn't put up still does.

The tag next to the clock always says which state it's in, so a clock that
isn't moving explains itself -- and in FISH mode it names the specific
reason (`FACE WATER`, `NO ROD`, `SURFING`) rather than a bare `HUNT IDLE`,
since each of those is fixable from where you're standing.

It comes in three sizes, and the chips it draws on itself switch between
them with a tap (or a mouse click on desktop):

| size | what it is |
| --- | --- |
| **mini** | a one-line pill: clock and total, out of the way |
| **normal** | the corner panel -- clock, total, top species |
| **full** | the HUD owns the screen; the game shrinks to a corner PiP |

- `II` pauses the hunt and `>` resumes it, and `F` opens the focus timer.
  The rule: a control you might need *urgently* is on every size (`II`,
  because a hunt you cannot stop is a trap), and a feature you go looking
  for is where there is room for it (`F`, on normal and full). Mini's whole
  job is to be out of the way, and the pill is already one tap back to the
  panel.
- `+` grows the HUD, `-` shrinks it. From the corner panel, `-` goes to the
  pill and tapping the pill brings the panel back.
- At full size the game is still live in the picture-in-picture corner --
  a shiny battle is right there, pulsing border and all -- and tapping the
  PiP is the quick way back to the full-size screen. The full size also
  lists as many species as the window has room for, in columns.
- Whatever the size, the clock is the biggest thing on it, the encounter
  total is next, and the per-species breakdown is last.
- Taps that miss the HUD go to the game as normal, and the on-screen
  controls always get first refusal, so the HUD can never eat a d-pad press.

## Focus timer

A fixed-length hunting session for when you want the phone to hunt while you
do something else, without the temptation to keep checking on it. Tap
the **`F`** chip on the HUD, pick a length from 5 to 60 minutes in
**FOCUS LENGTH**, and tap **START**. `F` is on the normal and full sizes;
turning **FOCUS TIMER** off in the mod's settings removes it entirely.

While a session is running:

- **The screen is covered.** No game, no HUD, nothing but a countdown and an
  **END** chip. Tap anywhere else to peek a static card (session length and
  targets) -- it never shows encounter counts or shiny status, because a
  parked encounter count would itself give a find away.
- **Nothing about a find is shown until the countdown reaches zero** -- not
  a vibrate, not the pulsing border, not the `SHINY!` tag, not even a
  stalled clock. If it finds what you're hunting partway through, the
  session still runs its full length and gives no sign. This is deliberate:
  the point is to know for certain, at the end, without being able to peek
  the result early by any means -- including tapping END, see below.
- **Music is muted** for the duration (there is no equivalent hook for
  battle sound effects, so those are still audible -- see Notes).
- **Ending it early costs you the find.** The **END** chip asks for
  confirmation, worded identically whether or not anything is waiting (a
  warning that only showed up for a real find would itself be the leak),
  and confirming runs from whatever wild battle is open -- a held shiny
  included. Tap **STAY** instead to keep the session running.

At zero the screen returns, every suppressed alert fires at once, and a
summary reports what happened: elapsed time, the encounter count for that
session (not the lifetime total), whether a target was found, and how many
off-target shinies were fled (see Targets below). It stays up until you tap
**OK**.

A session lives only as long as the app does -- it is not saved, and
restarting the app or reloading the mod ends it with nothing to show.

### Targets

This is how you tell it which Pokemon you are actually after. To get there:

1. Tap the **`F`** chip on the HUD, then **TARGETS**. (`F` is on the normal
   and full sizes; from the mini pill, tap the pill to get the panel back.
   If there's no `F` at all, **FOCUS TIMER** has been switched off in the
   mod's settings.)

That opens a scrollable list of every species the game knows, in dex order.
Tap to toggle; picked species show an `X`. `-- CLEAR ALL --` empties the
list, `-- DONE --` closes it. The offer panel then reads `TARGETS: 3
SPECIES` (or `TARGETS: ANY SHINY`) so you can see it took. Picks are written
to your savefile's mod data immediately, but only reach disk on your next
in-game SAVE.

Targets decide **which shiny the session stops for** -- not what appears.
What can show up is set by where you are standing, or which rod you are
casting in FISH mode.

**Inside a session, a shiny that is not one of your targets is fled, not
caught.** That is what makes targeting worth having, but it is irreversible
and it is the one thing in this feature that runs against the mod's own
promise to leave every shiny battle alone. The summary reports how many were
skipped so it is never a total surprise, but there is no undo. Leave the
list empty if you are not sure.

**The list only binds inside a FOCUS session.** During ordinary hunting it
is ignored completely and every shiny is held, whatever is on it -- so a
list left over from an old session cannot quietly cost you anything. (Before
0.7.2 it bound everywhere, which meant exactly that: a saved target list ran
from off-target shinies during normal hunting, silently and uncounted. If
you set targets on 0.6.0 or 0.7.0/0.7.1, that was happening.)

## Battery

An unattended hunt with the screen forced awake for hours is going to use
power regardless. To cut it down:

- Disable graphics-heavy mods you don't need while not watching (a 3D
  voxel-style rendering mod is the biggest one) -- turn them back on when
  you pick the phone up.
- If you're running Wilds of Kanto, turn its **Show Wild Mons** setting
  off but leave **Random Enc** on -- this mod only needs the classic
  step-based roll, not the visible/animated sprites.
- Lower your device's screen brightness; it matters more than anything
  in-game.
- Plug the phone in. KEEP SCREEN AWAKE has to stay on for this mod to run
  at all, so charging isn't optional for a long session.

## Notes

- Only triggers on wild encounters (`battle.kind == "wild"`); trainer and
  Safari battles are left alone. That includes fishing inside the Safari
  Zone, which the engine turns into a Safari battle -- the rod still casts,
  but the mod won't flee it, so the hunt stops there until you deal with it.
  Hunt somewhere else.
- Fishing is the one part of this mod that reaches past the engine's
  supported mod API. There is no public entry point for a rod (`mod.world`
  has none, and `encounter.fishing` only lets a mod redress a cast somebody
  else started), so it calls `OverworldState:goFishing` -- the same method
  the bag's own USE calls, after checking the same two things the bag checks
  first. That keeps the rod tables, the bite odds and the hooked-battle
  intro exactly where they already were, but it is an internal method: if a
  future engine moves it, FISH mode says `CAN'T FISH` on the HUD and casts
  nothing rather than inventing an encounter of its own. WALK mode is
  unaffected either way.
- If an encounter (or a menu, or anything else) interrupts a step mid-hold,
  the mod still credits that step and flips direction correctly once
  things clear -- it doesn't repeat the same direction twice and drift off
  the original two tiles.
- If a held direction genuinely can't move at all (blocked by a wall),
  it gives up and flips after under a second.
- The full-size HUD composites the window itself (`render.compose`), so
  whole-screen display effects -- GBC FX's LCD grid, a CRT-style post-process
  pipeline -- are not drawn over the picture-in-picture while it's up. Shrink
  the HUD back to the corner panel and they're there again; nothing about the
  setting changes.
- A FOCUS session's cover is three layers deep, because refusing to draw the
  game is not the same as nothing being drawn. It takes every screen off the
  draw list (`screen.render_visible`), refuses the composite
  (`render.compose`), and then paints its own opaque full-window ground in
  `render.hud` before the countdown. That last one is the layer that matters:
  a peer mod wrapping `render.hud` at a higher priority than this mod's runs
  *before* it and cannot be stopped, so the only defence against what it drew
  is covering it. Until 0.7.2 the cover relied on the composite alone, and a
  peer redrawing the dialogue box in window space put a live `Oh! It's a
  bite!` text box on top of a running countdown.
- Compatible with Wilds of Kanto (its "Random Enc" setting keeps the
  classic step-based rolls this mod needs -- leave it on) and with any
  sprite-replacement mod (sprites are a separate layer from battle logic).
- If you're also running the "Overworld Wild Encounters" (Gamecorner_033)
  mod alongside Wilds of Kanto: those two mods implement the same visible-
  overworld-Pokemon idea independently and can double-spawn on the same
  tiles. Not this mod's issue, but worth disabling one of them before a
  long hunting session -- also saves the battery it costs to run two of
  them at once.
- Any tap during a session that misses the FOCUS screen's own targets is
  swallowed -- it cannot reach the hidden game underneath. The one exception
  is the on-screen touch controls (d-pad, A/B), which draw over everything
  and get first refusal on a tap before this mod ever sees it (see the HUD
  section above): a press landing exactly on one of those, during a session,
  can still reach a real, hidden battle -- selecting a move, or advancing a
  text box, with no visual feedback that anything happened. This is a real
  gap, not just a cosmetic one, and it is not something a mod hook can
  close. If this worries you, rest your hand off the bottom strip of the
  screen while a session runs.
- FOCUS mutes music but has no hook into battle sound effects, so a held
  shiny's battle sound is still audible if you're close enough to hear it --
  the mod can only close the leaks the engine gives it a hook for.
- A FOCUS session lives in memory only. It is not part of the savefile, so
  quitting the app or reloading mods during one ends it with no summary and
  nothing recorded.

## Compatibility

This mod depends on nobody. It reads the engine's own virtual-shiny DV
formula and the public hooks, never `require`s another mod, and never reads
another mod's state -- which is why a shiny from *any* source is detected
with no setup. The one engine internal it touches is
`OverworldState:goFishing`, and only in FISH mode (see Notes). What it has
actually been read against:

| project | version | notes |
| --- | --- | --- |
| Gen1Recomp (engine) | v0.1.75 | `input.pointer` needs >= v0.1.69 -- that's the manifest floor |
| Dramaless Shape (`artyrambles/DRAMALESS_SHAPE`) | v1.6.4 | no shared hooks; **no shinies of its own** (see below) |
| Dramatic Shape Voxel Mod | v1.8.1 | upstream repo is gone as of 2026-08-10; checked while it was up |
| Shiny Pokemon (masterwebx) | v1.0.8 | its shinies are detected with no setup |
| Wilds of Kanto | v1.11.1 | **leave RANDOM ENC on** (see below) |
| Gen1 Modern UI | v0.8.3 | wraps the same three HUD hooks at priority 100 and defers correctly |

`compat/upstream.json` is the machine-readable copy of that table;
`.github/workflows/upstream-watch.yml` checks it weekly and opens an issue
when one of them releases something new.

### Shiny sources

Whatever makes a wild Pokemon shiny, this mod reads the DVs, so it needs no
setup either way. What matters is that **exactly one** mod is rolling them.

- **Dramaless Shape** (the `artyrambles/DRAMALESS_SHAPE` fork, v1.6.x) has
  **no shiny feature** -- it forked before upstream added one. With this
  fork, the standalone **Shiny Pokemon** mod is your shiny source and should
  stay on. Nothing conflicts: the fork never touches `Pokemon.new`.
- **Dramatic Shape v1.8.1** (upstream, now unavailable) did roll its own.
  If you are running a copy of it, do not also run Shiny Pokemon's roll:
  both wrap `Pokemon.new`, and v1.8.1's miss branch actively *un-shinies* a
  mon, so one can cancel the other and the real rate is neither dial. Turn
  Shiny Pokemon off, or set its **SHINY RATE** to **OFF** and keep
  **SHINY COLORS** on for the overworld colouring v1.8.1 does not do.

Note that Shiny Pokemon's default rate is **1/4096**, not Gen 2's 1/8192 --
set it to `1/8192 (Gen 2)` if you want the classic pace.

### Wilds of Kanto

Leave its **RANDOM ENC** setting **on**. With it off, Wilds of Kanto returns
`nil` from `encounter.roll` for grass, which switches the classic step-based
roll off entirely -- and the classic roll is the only thing this mod's
shuffle can trigger. The hunt would walk in place for hours and never find a
single encounter.

This only applies to **HUNT MODE = WALK**. A rod does not go through
`encounter.roll` at all, so FISH mode hunts normally with **RANDOM ENC**
off -- and is the way to hunt on that setup without changing it.

### Voxel camera rungs

This applies to both the fork and upstream -- they share the code. Hunt on
the orbit/diorama rungs (or in 2D), not the **1ST**/**3RD** person ones.
Those replace grid walking with continuous movement rotated by the camera's
yaw, so a held UP is "forward from where you happen to be looking" rather
than one tile north -- the shuffle can slide off its two tiles, and turning
the camera changes what the walk directions mean mid-hunt.

## Layout

- `manifest.json` - identity, version range, load order
- `main.lua` - the entry chunk; receives the `mod` object
- `tests/` - a stand-in engine and the mod's own checks (`./tests/run.sh`)
- `compat/upstream.json` - what this mod has been verified against

## Dev loop

1. `POKEPORT_DEV=1 love .` once, leave it running
2. edit, press F5 to hot-reload, backtick for the dev console
3. `./tests/run.sh` -- no LOVE needed; it stands in an engine and drives
   every hook this mod installs
4. `python3 tools/modkit.py validate auto_shiny_hunt` before sharing
5. `python3 tools/modkit.py pack mods/auto_shiny_hunt` to ship

Before a release, or when the watcher files an issue: skim each moved
project's changelog for the hooks listed in `compat/upstream.json`, run the
tests, then update that file and the table above.
