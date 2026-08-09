# Auto Shiny Hunt

Unattended shiny hunting. When AUTO HUNT is on, this mod shuffles the
player between two directions to keep triggering classic step-based wild
encounters, flees anything that isn't shiny, and leaves a shiny battle on
screen (with a vibrate + pulsing border) so it's obvious at a glance.

"Shiny" is Gen 1's real virtual-shiny DV pattern (the one that makes the
one special Red Gyarados possible): DEF/SPD/SPC DVs = 10 and ATK DV in
{2,3,6,7,10,11,14,15}. Natural odds are 1/8192 per wild encounter -- that
can be a long unattended hunt on its own. If you also install the
community "Shiny Pokemon" mod (masterwebx) and raise its rate, this mod
still detects it correctly with no extra setup: it only reads the DVs a
wild Pokemon actually ends up with, however they got there.

## Setup

1. Install this mod (see `docs/launcher.md` / the in-game mod importer for
   how to load a mod `.zip` on your device -- no rebuild needed).
2. Walk your character to a spot with an open tile on two opposite sides
   (e.g. grass to the north, a path tile to the south). Face either
   direction.
3. OPTIONS -> MOD SETTINGS -> AUTO SHINY HUNT:
   - Turn on **AUTO HUNT**.
   - Set **WALK DIR A** / **WALK DIR B** to the axis that's actually open
     where you're standing (defaults to UP/DOWN).
   - Leave **KEEP SCREEN AWAKE** on so the app doesn't get paused by the
     device sleeping. Plug the phone in -- this runs indefinitely.
   - **SPEED CAP** is 4X unless you pick a tighter one; see below.
4. Leave the phone. Every wild battle either resolves itself in a second
   or two (non-shiny) or stops and sits there (shiny) until you pick the
   phone back up.
5. Turn AUTO HUNT off before you want to play normally again -- it forces
   every one of its own flee attempts to succeed while it's on, but never
   touches a manual RUN you press yourself.

## Speed cap

**SPEED CAP** holds GAME SPEED down while AUTO HUNT is on. It defaults to
**4X**, which is also the highest it goes -- the option only offers
*tighter* caps (3X, 2X, 1X), never a looser one. Past 4X an unattended hunt
stops being the game running fast and turns into a counter being spun.

Nothing is taken away: the GAME SPEED options row, the `1` hotkey and the
shoulder buttons all still cycle, they just can't leave the value above the
cap for longer than a tick. Turn AUTO HUNT off and the game is yours again
at whatever speed you like -- and if you launched with `--speed` /
`POKEPORT_SPEED`, that exact value is handed back untouched.

## HUD

**SHOW HUD** (on by default, independent of AUTO HUNT) draws real
wall-clock elapsed time (not game time -- unaffected by the GAME SPEED
setting), the total wild encounter count, and a per-species count sorted
highest first. It keeps counting through a pause (e.g. while AUTO HUNT is
off so you can catch a shiny) and only resets when the game restarts or the
mod reloads.

It comes in three sizes, and the chips it draws on itself switch between
them with a tap (or a mouse click on desktop):

| size | what it is |
| --- | --- |
| **mini** | a one-line pill: clock and total, out of the way |
| **normal** | the corner panel -- clock, total, top species |
| **full** | the HUD owns the screen; the game shrinks to a corner PiP |

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
  Safari battles are left alone.
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
- Compatible with Wilds of Kanto (its "Random Enc" setting keeps the
  classic step-based rolls this mod needs -- leave it on) and with any
  sprite-replacement mod (sprites are a separate layer from battle logic).
- If you're also running the "Overworld Wild Encounters" (Gamecorner_033)
  mod alongside Wilds of Kanto: those two mods implement the same visible-
  overworld-Pokemon idea independently and can double-spawn on the same
  tiles. Not this mod's issue, but worth disabling one of them before a
  long hunting session -- also saves the battery it costs to run two of
  them at once.

## Compatibility

This mod depends on nobody. It reads the engine's own virtual-shiny DV
formula and the public hooks, never `require`s another mod, and never reads
another mod's state -- which is why a shiny from *any* source is detected
with no setup. What it has actually been read against:

| project | version | notes |
| --- | --- | --- |
| Gen1Recomp (engine) | v0.1.75 | `input.pointer` needs >= v0.1.69 -- that's the manifest floor |
| Dramatic Shape Voxel Mod | v1.8.1 | no shared hooks; its shinies are detected (see below) |
| Shiny Pokemon (masterwebx) | v1.0.8 | its shinies are detected; see the note on running both |
| Wilds of Kanto | v1.11.1 | **leave RANDOM ENC on** (see below) |
| Gen1 Modern UI | v0.8.3 | wraps the same three HUD hooks at priority 100 and defers correctly |

`compat/upstream.json` is the machine-readable copy of that table;
`.github/workflows/upstream-watch.yml` checks it weekly and opens an issue
when one of them releases something new.

### Shiny sources

Since **Dramatic Shape v1.8.1** the voxel mod rolls its own shinies, and the
standalone **Shiny Pokemon** mod has always done the same. Both write the
verdict into the Pokemon's DVs, which is exactly what this mod reads -- so
one, the other, both or neither all work here without a setting.

Running **both** at once is the thing to avoid: they each wrap
`Pokemon.new`, and Dramatic Shape's miss branch actively *un-shinies* a mon,
so one mod can cancel the other's shiny and the real rate is neither dial.
Pick one:

- Turn **Shiny Pokemon** off, or
- keep it for its overworld sprite colouring (Dramatic Shape's shiny art is
  battle-side only) and set its **SHINY RATE** to **OFF**, which leaves it
  reading DVs and colouring without rolling anything of its own.

### Wilds of Kanto

Leave its **RANDOM ENC** setting **on**. With it off, Wilds of Kanto returns
`nil` from `encounter.roll` for grass, which switches the classic step-based
roll off entirely -- and the classic roll is the only thing this mod's
shuffle can trigger. The hunt would walk in place for hours and never find a
single encounter.

### Dramatic Shape camera rungs

Hunt on the orbit/diorama rungs (or in 2D), not the **1ST**/**3RD** person
ones. Those replace grid walking with continuous movement rotated by the
camera's yaw, so a held UP is "forward from where you happen to be looking"
rather than one tile north -- the shuffle can slide off its two tiles, and
turning the camera changes what the walk directions mean mid-hunt.

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
