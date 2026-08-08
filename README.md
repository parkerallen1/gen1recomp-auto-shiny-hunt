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
4. Leave the phone. Every wild battle either resolves itself in a second
   or two (non-shiny) or stops and sits there (shiny) until you pick the
   phone back up.
5. Turn AUTO HUNT off before you want to play normally again -- it forces
   every one of its own flee attempts to succeed while it's on, but never
   touches a manual RUN you press yourself.

## Notes

- Only triggers on wild encounters (`battle.kind == "wild"`); trainer and
  Safari battles are left alone.
- If something else (an NPC, a menu) interrupts the shuffle, the mod caps
  each held direction at under a second before giving up and flipping, so
  it can't get stuck holding a button into an unrelated screen for long.
  Pick a quiet spot away from trainers/NPCs for a cleaner run.
- Compatible with Wilds of Kanto (its "Random Enc" setting keeps the
  classic step-based rolls this mod needs -- leave it on) and with any
  sprite-replacement mod (sprites are a separate layer from battle logic).
- If you're also running the "Overworld Wild Encounters" (Gamecorner_033)
  mod alongside Wilds of Kanto: those two mods implement the same visible-
  overworld-Pokemon idea independently and can double-spawn on the same
  tiles. Not this mod's issue, but worth disabling one of them before a
  long hunting session.

## Layout

- `manifest.json` - identity, version range, load order
- `main.lua` - the entry chunk; receives the `mod` object

## Dev loop

1. `POKEPORT_DEV=1 love .` once, leave it running
2. edit, press F5 to hot-reload, backtick for the dev console
3. `python3 tools/modkit.py validate auto_shiny_hunt` before sharing
4. `python3 tools/modkit.py pack mods/auto_shiny_hunt` to ship
