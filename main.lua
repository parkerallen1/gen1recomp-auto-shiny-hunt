-- Auto Shiny Hunt: shuffles the player between two directions to keep
-- rolling classic step-based wild encounters, then reacts to whatever
-- shows up -- flees anything that isn't shiny, leaves a shiny battle
-- alone and flags it (vibrate + a pulsing border) so it's obvious on a
-- glance.  Turn AUTO HUNT on from OPTIONS -> MOD SETTINGS -> AUTO SHINY
-- HUNT before parking the phone in a patch of grass.
--
-- "Shiny" is Gen 1's real virtual-shiny DV pattern (the one Red Gyarados
-- uses): DEF/SPD/SPC DVs = 10 and ATK DV in the even-high set. This is
-- deliberately the bare formula off mon.dvs, not a private require of
-- src.pokemon.Stats -- any other installed mod that rerolls a wild's DVs
-- for its own shiny rate (e.g. Shiny Pokemon) still lands on DVs that
-- satisfy this same formula, so this mod sees it correctly either way
-- with no dependency on that mod being present.
local SHINY_ATK = {
  [2] = true, [3] = true, [6] = true, [7] = true,
  [10] = true, [11] = true, [14] = true, [15] = true,
}

local function isShinyDVs(dvs)
  if type(dvs) ~= "table" then return false end
  return (dvs.defense or 0) == 10 and (dvs.speed or 0) == 10
     and (dvs.special or 0) == 10 and SHINY_ATK[dvs.attack or 0] == true
end

local function isShinyMon(mon)
  return mon ~= nil and (mon.shiny == true or isShinyDVs(mon.dvs))
end

local DIR_CHOICES = {
  { "UP", "up" }, { "DOWN", "down" }, { "LEFT", "left" }, { "RIGHT", "right" },
}

-- GAME SPEED ceiling while hunting.  The engine's ladder
-- (src/core/GameSpeed.lua) is 1, 2, 3, 4, 10, 20, 30, ... -- 10X is the last
-- rung the engine describes as a rate rather than a ceiling (past it vsync
-- caps how much a frame can do anyway), so that is the highest this mod
-- will let it sit.  The option can only pick a *tighter* cap; there is no
-- way to raise it past MAX_SPEED_CAP.
local MAX_SPEED_CAP = 10
local SPEED_CAP_CHOICES = {
  { "10X", "10" }, { "4X", "4" }, { "3X", "3" }, { "2X", "2" }, { "1X", "1" },
}

-- how long a *confirmed-uninterrupted* hold can run before giving up on
-- it landing a step and flipping anyway -- a real step lands well under
-- this, so it only fires when the way is genuinely blocked
local MAX_HOLD_SECONDS = 0.9

-- how long a FOCUS peek panel, or the end-early confirm, stays up before it
-- dismisses itself
local FOCUS_PEEK_SECONDS = 4
local FOCUS_CONFIRM_SECONDS = 10

-- Deliberately unconditional and deliberately dull. A warning that read
-- differently depending on whether something was waiting would announce the
-- find, which is the one thing a FOCUS session exists to prevent -- so this
-- mentions running from an open battle every single time, including the
-- (usual) times there is nothing to run from.
local FOCUS_END_WARNING = {
  "END THIS SESSION EARLY?",
  "THE SESSION IS DISCARDED AND ANY WILD",
  "BATTLE STILL OPEN WILL BE RUN FROM.",
}

local function nowReal()
  if love and love.timer and love.timer.getTime then return love.timer.getTime() end
  return os.clock()
end

local function formatElapsed(seconds)
  seconds = math.max(0, math.floor(seconds or 0))
  local h = math.floor(seconds / 3600)
  local m = math.floor((seconds % 3600) / 60)
  local s = seconds % 60
  if h > 0 then return ("%d:%02d:%02d"):format(h, m, s) end
  return ("%02d:%02d"):format(m, s)
end

-- species rows the corner-sized HUD lists; the full-screen one fits as many
-- as the window has room for
local MAX_HUD_SPECIES_ROWS = 8

-- the Game Boy screen's aspect, the PiP's shape until render.compose hands
-- over the real UI canvas size
local GB_ASPECT = 160 / 144

return function(mod)
  mod.options:define({
    { key = "enabled", type = "toggle", label = "AUTO HUNT", default = false,
      help = "Flee non-shiny wild encounters and shuffle in place to "
        .. "trigger them. Stand in grass (or wherever you want encounters) "
        .. "with an open tile on each side of the chosen axis first." },
    { key = "dir_a", type = "choice", label = "WALK DIR A", default = "up",
      choices = DIR_CHOICES,
      help = "The two directions to shuffle between. Pick whichever axis "
        .. "is actually open where you're standing." },
    { key = "dir_b", type = "choice", label = "WALK DIR B", default = "down",
      choices = DIR_CHOICES },
    { key = "keep_awake", type = "toggle", label = "KEEP SCREEN AWAKE", default = true,
      help = "Stops the device from sleeping while hunting -- the app "
        .. "pauses if the screen turns off." },
    { key = "vibrate", type = "toggle", label = "VIBRATE ON SHINY", default = true },
    { key = "flash", type = "toggle", label = "FLASH ON SHINY", default = true,
      help = "Pulsing border around the battle screen while a shiny is up." },
    { key = "show_hud", type = "toggle", label = "SHOW HUD", default = true,
      help = "On-screen real-time elapsed clock and a per-species "
        .. "encounter count. Stays visible even if you pause AUTO HUNT "
        .. "to deal with a shiny. Tap the + / - chips on it to blow it up "
        .. "full screen or shrink it back down." },
    { key = "speed_cap", type = "choice", label = "SPEED CAP", default = "10",
      choices = SPEED_CAP_CHOICES,
      help = "Ceiling on GAME SPEED while AUTO HUNT is on, and only while "
        .. "it is on -- 10X at the most. Whatever you had set comes back "
        .. "the moment you turn AUTO HUNT off." },
    { key = "focus_minutes", type = "number", label = "FOCUS LENGTH", default = 25,
      min = 5, max = 60, step = 5,
      help = "How long a FOCUS session runs. The screen is covered for the "
        .. "whole length and nothing about what it found is shown until it "
        .. "ends -- including if it ends in the first minute." },
    { key = "focus_chip", type = "toggle", label = "FOCUS TIMER", default = false,
      help = "Adds a FOCUS chip to the corner HUD. Tap it to start a "
        .. "fixed-length session: the screen is covered, a countdown "
        .. "replaces the clock, and the result is held back until zero." },
  })

  local state = {
    -- movement shuffle
    dir = nil, token = nil, holdFor = 0, lastPos = nil,
    awaitingConfirm = false,
    -- how many non-overworld screens are currently stacked above the
    -- overworld (menus, dialogs, battle, ...): only the TOPMOST screen
    -- ever reads input, so walking must stay silent whenever this is > 0
    -- -- that's the options-menu-scrolling-itself bug.
    blockingLayers = 0,
    -- battle reaction.  inBattle is any battle at all, tracked separately
    -- from fleeing because the clock counts a fight (and a shiny sitting in
    -- one) as hunting, whether this mod is running from it or not.
    fleeing = false, autoRunArmed = false, shinyUp = false, inBattle = false,
    -- stats: elapsed is real (wall-clock) time, deliberately not tied to
    -- GAME SPEED or fixed-step dt -- love.timer.getTime() is a real clock.
    -- It only advances while the hunt is actually running (see huntIsRunning):
    -- a menu, the title screen or a load parks it, so the number stays "time
    -- spent hunting" rather than "time since you switched it on".
    wasRunning = false, elapsedBase = 0, resumedAt = nil,
    totalEncounters = 0, speciesCounts = {}, speciesOrder = {},
    -- HUD: size, the tap targets the last drawn frame published, and which
    -- pointer (if any) is currently down on one of them
    hudMode = "normal", hitAreas = nil, grabbedId = nil, grabbedArea = nil,
    pipAspect = GB_ASPECT,
    -- what GAME SPEED (and the --speed / POKEPORT_SPEED run argument) were
    -- before the cap pushed them down, kept so hunting off hands the
    -- player's own values back
    optionStash = nil, optionCapped = nil,
    overrideStash = nil, overrideCapped = nil,
    -- the battle currently on screen, kept only so a FOCUS session's early
    -- exit can run from one it never opened itself. battleKind travels
    -- with it so that exit can refuse a trainer/Safari battle exactly like
    -- every other flee path in this file already does.
    battleRef = nil, battleKind = nil,
    -- FOCUS target species: lazily loaded from mod.save. nil = not loaded
    -- yet; an empty table means "any shiny", the pre-FOCUS behaviour
    targets = nil, speciesIndex = nil,
    -- a fixed-length hunting session that covers the screen and holds back
    -- everything it finds until the countdown reaches zero
    focus = {
      active = false, startedAt = nil, lengthSec = 0,
      -- totalEncounters at session start, so the summary can report the
      -- delta rather than the lifetime total
      encAt0 = 0,
      -- a target shiny found during the session. Sticky: survives
      -- battle.ended so the summary is honest even if the battle ends on
      -- its own. NEVER read by anything that draws while active is true.
      heldShiny = false, shinySpecies = nil,
      -- non-target shinies fled during the session
      skipped = 0,
      -- an alert (vibrate) that was suppressed and is owed at reveal
      pendingVibrate = false,
      peekUntil = 0, confirm = nil, confirmUntil = 0, summary = nil,
    },
  }

  local function stopWalking()
    if state.token then
      mod.input:release(state.token)
      state.token = nil
    end
  end

  local function isBlocking(scr)
    return not (scr and scr.isOverworld)
  end

  mod.events:on("screen.pushed", function(ev)
    if isBlocking(ev.state) then
      state.blockingLayers = state.blockingLayers + 1
    end
  end)

  mod.events:on("screen.popped", function(ev)
    if isBlocking(ev.state) then
      state.blockingLayers = math.max(0, state.blockingLayers - 1)
    end
    -- A battle is always at least one layer over the overworld, so back at
    -- zero there cannot be one on screen.  Belt and braces for the clock: if
    -- a battle.ended ever went missing, inBattle would otherwise hold the
    -- clock running forever.
    if state.blockingLayers == 0 then state.inBattle = false end
  end)

  local function speciesLabel(species)
    local ok, def = pcall(function() return mod.content.pokemon:get(species) end)
    if ok and def and def.name then return def.name end
    return tostring(species or "?")
  end

  -- ------------------------------------------------------- FOCUS targets --
  -- Which species a FOCUS session is hunting. Persisted with mod.save (the
  -- savefile), since a target list is a property of this playthrough, not a
  -- global setting -- and mod.options has no write path for the mod anyway.
  local function targets()
    if state.targets then return state.targets end
    local set = {}
    local ok, saved = pcall(function() return mod.save:get("focus_targets", nil) end)
    if ok and type(saved) == "table" then
      for _, id in ipairs(saved) do set[tostring(id)] = true end
    end
    state.targets = set
    return set
  end

  local function saveTargets()
    local list = {}
    for id in pairs(state.targets or {}) do list[#list + 1] = id end
    table.sort(list)
    pcall(function() mod.save:set("focus_targets", list) end)
  end

  -- an empty set means "any shiny" -- the mod's behaviour before targeting
  -- existed, and what a FOCUS session with nothing picked still gets
  local function isTarget(species)
    local set = targets()
    if next(set) == nil then return true end
    return set[tostring(species)] == true
  end

  -- every known species, sorted by dex number, built once and cached. Never
  -- hardcodes a species count -- mod-added species and a patched dexSize
  -- both come along for free through :each().
  local function speciesIndex()
    if state.speciesIndex then return state.speciesIndex end
    local list = {}
    pcall(function()
      for id, def in mod.content.pokemon:each() do
        list[#list + 1] = { id = id, name = (def and def.name) or tostring(id),
          dex = tonumber(def and def.dex) or math.huge }
      end
    end)
    table.sort(list, function(a, b)
      if a.dex ~= b.dex then return a.dex < b.dex end
      return tostring(a.id) < tostring(b.id)
    end)
    state.speciesIndex = list
    return list
  end

  mod.events:on("battle.started", function(ev)
    -- set before any of the early returns below: the clock counts every
    -- battle, including the trainer and Safari ones this mod stays out of
    state.inBattle = true
    state.battleRef = ev.battle
    state.battleKind = ev.kind
    state.shinyUp = false
    local species
    if ev.kind == "wild" then
      species = ev.battle and ev.battle.enemy and ev.battle.enemy.mon
        and ev.battle.enemy.mon.species
      if species then
        state.totalEncounters = state.totalEncounters + 1
        if not state.speciesCounts[species] then
          state.speciesOrder[#state.speciesOrder + 1] = species
        end
        state.speciesCounts[species] = (state.speciesCounts[species] or 0) + 1
      end
    end

    if not mod.options:get("enabled") then return end
    if ev.kind ~= "wild" then return end
    local mon = ev.battle and ev.battle.enemy and ev.battle.enemy.mon
    if isShinyMon(mon) then
      -- a shiny that is not one of the current targets is treated exactly
      -- like a common: fled, and counted so the summary can own up to it.
      if not isTarget(species) then
        if state.focus.active then state.focus.skipped = state.focus.skipped + 1 end
        state.fleeing = true
        state.autoRunArmed = true
        ev.battle:tryRun()
        return
      end
      state.shinyUp = true
      if state.focus.active then
        -- Result blackout: the find is recorded and nothing else happens.
        -- No vibrate, no tag reaching the screen, no pulse -- the alert is
        -- owed and paid when the session reveals.
        state.focus.heldShiny = true
        state.focus.shinySpecies = state.focus.shinySpecies or species
        state.focus.pendingVibrate = true
      elseif mod.options:get("vibrate") and love.system and love.system.vibrate then
        pcall(love.system.vibrate, 1.0)
      end
      return
    end
    -- mash past "Wild X appeared!" and "Got away safely!" ourselves --
    -- those are real text boxes waiting on a button press, not something
    -- that clears on its own
    state.fleeing = true
    state.autoRunArmed = true
    ev.battle:tryRun()
  end)

  mod.events:on("battle.ended", function()
    state.fleeing = false
    state.autoRunArmed = false
    state.shinyUp = false
    state.inBattle = false
    state.battleRef = nil
    state.battleKind = nil
    -- state.focus.heldShiny is deliberately NOT cleared here: it is sticky
    -- so the end-of-session summary still reports a find whose battle
    -- somehow ended on its own.
  end)

  -- only forces success for the flee *this mod* triggers above -- a
  -- manual RUN press (hunting off, or a trainer edge case) still rolls
  -- the normal Gen 1 speed-based odds
  mod.hooks:wrap("battle.run", function(next, ctx)
    if state.autoRunArmed then
      state.autoRunArmed = false
      return true
    end
    return next(ctx)
  end)

  mod.hooks:wrap("battle.overlay", function(next, battle)
    next(battle)
    -- suppressed during a FOCUS session -- this would otherwise reach the
    -- screen through the compose takeover's own PiP/UI canvas blits, which
    -- this mod's cover never draws, so it is currently unreachable in
    -- practice too. Kept explicit for a peer mod that composites the game
    -- some other way.
    if state.shinyUp and mod.options:get("flash") and not state.focus.active then
      local t = nowReal()
      local pulse = 0.5 + 0.5 * math.sin(t * 6)
      love.graphics.setColor(1, 1, 0, 0.35 * pulse)
      love.graphics.rectangle("line", 2, 2, 156, 140)
      love.graphics.setColor(1, 1, 1, 1)
    end
  end)

  -- Muting music during a session closes an audio leak: a parked shiny
  -- loops the battle theme forever, audibly different from a session that
  -- cycles overworld music normally. music.volume is re-applied every frame
  -- while any mod wraps it, so returning 0 here is enough on its own -- and
  -- muting is exactly what a focus block wants anyway. There is no
  -- equivalent hook for battle SFX; that residual leak is documented, not
  -- hidden.
  mod.hooks:wrap("music.volume", function(next, vol, ctx)
    if state.focus.active then return 0 end
    return next(vol, ctx)
  end)

  local function elapsedRealSeconds()
    local total = state.elapsedBase
    if state.resumedAt then total = total + (nowReal() - state.resumedAt) end
    return total
  end

  -- -------------------------------------------------------------- FOCUS --
  -- A fixed-length hunting session that covers the screen and holds back
  -- everything it finds until the countdown reaches zero. See the option
  -- rows above and drawFocus/drawOffer/drawSummary below for the HUD side.
  local function focusMinutes()
    local n = tonumber(mod.options:get("focus_minutes")) or 25
    return math.max(5, math.min(60, n))
  end

  -- Deliberately NOT elapsedRealSeconds(): that one is gated on
  -- huntIsRunning, and a parked hunt is exactly what a found shiny causes.
  -- A countdown that froze the moment something was found would announce
  -- the find louder than a vibrate. This is raw wall-clock time from the
  -- moment START was tapped, and nothing -- a menu, a battle, a shiny
  -- sitting open, AUTO HUNT being switched off -- can slow it down.
  local function focusRemaining()
    local f = state.focus
    if not f.active or not f.startedAt then return 0 end
    return math.max(0, f.lengthSec - (nowReal() - f.startedAt))
  end

  local function startFocus()
    local f = state.focus
    f.active = true
    f.startedAt = nowReal()
    f.lengthSec = focusMinutes() * 60
    f.encAt0 = state.totalEncounters
    f.heldShiny, f.shinySpecies, f.skipped = false, nil, 0
    f.pendingVibrate = false
    f.peekUntil, f.confirm, f.confirmUntil, f.summary = 0, nil, 0, nil
  end

  local function endFocus(reason) -- "done" | "early"
    local f = state.focus
    f.summary = {
      reason = reason,
      seconds = nowReal() - (f.startedAt or nowReal()),
      encounters = state.totalEncounters - f.encAt0,
      species = f.shinySpecies,
      shiny = f.heldShiny,
      skipped = f.skipped,
    }
    -- set first: the very next render.compose falls through and the game
    -- is back on screen
    f.active = false
    f.confirm, f.peekUntil = nil, 0
    -- the alert that was owed the whole session, paid only if it actually
    -- ran to completion -- an early exit already flees the find itself
    if reason == "done" and f.pendingVibrate
       and mod.options:get("vibrate") and love.system and love.system.vibrate then
      pcall(love.system.vibrate, 1.0)
    end
    f.pendingVibrate = false
  end

  -- the forced exit behind ending a session early: whatever is on screen
  -- gets run from, exactly like a common the mod fled on its own. Gated to
  -- wild the same way every other flee in this file is (main.lua:285) --
  -- without it, ending early during a trainer/Safari battle would arm a
  -- run that tryRun() refuses outright, leaving state.fleeing stuck and the
  -- A-mash below firing into the player's own battle indefinitely.
  local function fleeHeld()
    if not (state.inBattle and state.battleRef and state.battleKind == "wild") then return end
    state.fleeing = true
    state.autoRunArmed = true
    pcall(function() state.battleRef:tryRun() end)
  end

  local function focusTick(game)
    local f = state.focus
    if f.confirm == "end" and nowReal() > f.confirmUntil then f.confirm = nil end
    if not f.active then return end
    -- keep the device awake unconditionally during a session. The ordinary
    -- KEEP SCREEN AWAKE apply, further down in the input.step wrap, sits
    -- behind the hunting-blocked early return in that same wrap -- so a
    -- parked find would otherwise let the screen sleep, an obvious physical
    -- tell that something was found.
    if mod.options:get("keep_awake") and love.window
       and love.window.setDisplaySleepEnabled then
      love.window.setDisplaySleepEnabled(false)
    end
    if focusRemaining() <= 0 then endFocus("done") end
  end

  -- push the engine's own scrollable list screen for target species. Fully
  -- optional: if mod.ui or the screen id is not available, this pcalls out
  -- quietly and the feature degrades to "empty set = any shiny".
  local function openPicker(game)
    local rows = {
      { label = "-- DONE --", id = "__done" },
      { label = "-- CLEAR ALL --", id = "__clear" },
    }
    for _, s in ipairs(speciesIndex()) do
      rows[#rows + 1] = {
        label = s.name, right = targets()[tostring(s.id)] and "X" or "",
        id = tostring(s.id),
      }
    end
    local function onChoose(item, menu)
      if item.id == "__done" then
        if menu.close then menu:close() end
        return
      end
      if item.id == "__clear" then
        state.targets = {}
        saveTargets()
        for _, row in ipairs(menu.items or {}) do
          if row.id ~= "__done" and row.id ~= "__clear" then row.right = "" end
        end
        return
      end
      local set = targets()
      set[item.id] = (not set[item.id]) or nil
      saveTargets()
      -- onChoose does not pop the screen, so mutate the row in place --
      -- menu.items holds the exact tables these rows are, no re-push needed
      item.right = set[item.id] and "X" or ""
    end
    pcall(function()
      mod.ui.push(game, "ListMenu", "FOCUS TARGETS", rows, {
        onChoose = onChoose, wrap = true, pageJump = true, keyRepeat = true,
        footer = "A SHINY THAT ISN'T PICKED IS FLED, NOT CAUGHT",
      })
    end)
  end

  local function targetsSummaryText()
    local set = targets()
    local n = 0
    for _ in pairs(set) do n = n + 1 end
    if n == 0 then return "TARGETS: ANY SHINY" end
    return ("TARGETS: %d SPECIES"):format(n)
  end

  local FOCUS_ACTIONS = {
    offer = function() state.focus.confirm = "offer" end,
    start = function() startFocus() end,
    cancel = function() state.focus.confirm = nil end,
    peek = function() state.focus.peekUntil = nowReal() + FOCUS_PEEK_SECONDS end,
    endask = function()
      state.focus.confirm = "end"
      state.focus.confirmUntil = nowReal() + FOCUS_CONFIRM_SECONDS
    end,
    endnow = function()
      fleeHeld()
      endFocus("early")
    end,
    dismiss = function() state.focus.summary = nil end,
    targets = function(game) openPicker(game) end,
  }

  local function focusAction(name, game)
    local fn = FOCUS_ACTIONS[name]
    if fn then fn(game) end
  end

  -- ---------------------------------------------------------------- HUD --
  -- Three sizes, cycled by tapping the chips the HUD draws for itself:
  --   mini   one line -- clock and total, out of the way
  --   normal the corner panel
  --   full   the HUD owns the window and the game shrinks into a corner PiP
  -- Every size ranks the same way: the clock is the biggest thing on it, the
  -- encounter total next, the per-species breakdown last.

  -- one font object per pixel size, since a size is asked for every frame.
  -- The whole cache is dropped rather than grown without bound if a window
  -- gets dragged through enough sizes to fill it.
  local fontCache, fontCacheN = {}, 0
  local function fontAt(px)
    px = math.max(8, math.floor(px or 12))
    local cached = fontCache[px]
    if cached ~= nil then return cached or nil end
    if fontCacheN >= 24 then fontCache, fontCacheN = {}, 0 end
    local ok, font = pcall(love.graphics.newFont, px)
    fontCache[px] = ok and font or false
    fontCacheN = fontCacheN + 1
    return ok and font or nil
  end

  -- Largest font that fits `text` inside maxW x maxH.  The default font's
  -- advance scales linearly with its size, so measuring one small probe is
  -- enough to solve for the width -- and measuring the probe rather than the
  -- height budget means a 500px glyph atlas never gets built just to be
  -- thrown away on a tall screen.
  local PROBE_PX = 32
  local function fitFont(text, maxW, maxH)
    local probe = fontAt(PROBE_PX)
    if not probe then return nil end
    local w = probe:getWidth(text)
    local byWidth = (w > 0) and (PROBE_PX * maxW / w) or (maxH or 12)
    return fontAt(math.min(byWidth, (maxH or 12) / 1.3))
  end

  local function panel(x, y, w, h, alpha)
    love.graphics.setColor(0, 0, 0, alpha or 0.62)
    love.graphics.rectangle("fill", x, y, w, h, 4, 4)
    love.graphics.setColor(1, 1, 1, 0.16)
    love.graphics.rectangle("line", x, y, w, h, 4, 4)
    love.graphics.setColor(1, 1, 1, 1)
  end

  local function printAt(text, font, x, y, alpha, r, g, b)
    font = font or love.graphics.getFont()
    love.graphics.setFont(font)
    love.graphics.setColor(r or 1, g or 1, b or 1, alpha or 1)
    love.graphics.print(text, math.floor(x), math.floor(y))
    love.graphics.setColor(1, 1, 1, 1)
    return font:getHeight()
  end

  -- a square tap target with a label, published to state.hitAreas by the
  -- caller so input.pointer can find it. `mode` is a HUD size to switch to
  -- on tap (the pre-FOCUS behaviour); `action` is a FOCUS_ACTIONS name --
  -- every existing call site passes only `mode`, so this stays untouched.
  local function chip(areas, id, mode, label, x, y, size, action)
    love.graphics.setColor(0, 0, 0, 0.7)
    love.graphics.rectangle("fill", x, y, size, size, 4, 4)
    love.graphics.setColor(1, 1, 1, 0.5)
    love.graphics.rectangle("line", x, y, size, size, 4, 4)
    local font = fontAt(size * 0.6)
    if font then
      love.graphics.setFont(font)
      love.graphics.setColor(1, 1, 1, 0.95)
      love.graphics.print(label,
        math.floor(x + (size - font:getWidth(label)) / 2),
        math.floor(y + (size - font:getHeight()) / 2))
    end
    love.graphics.setColor(1, 1, 1, 1)
    areas[#areas + 1] = { id = id, mode = mode, action = action, x = x, y = y, w = size, h = size }
  end

  -- a rectangular tap target with a label -- like chip(), but not
  -- constrained to a square, for FOCUS's wider buttons (START, CANCEL, ...)
  local function button(areas, id, label, x, y, w, h, action)
    love.graphics.setColor(0, 0, 0, 0.7)
    love.graphics.rectangle("fill", x, y, w, h, 4, 4)
    love.graphics.setColor(1, 1, 1, 0.5)
    love.graphics.rectangle("line", x, y, w, h, 4, 4)
    local font = fontAt(h * 0.55)
    if font then
      printAt(label, font, x + (w - font:getWidth(label)) / 2,
        y + (h - font:getHeight()) / 2, 0.95)
    end
    areas[#areas + 1] = { id = id, action = action, x = x, y = y, w = w, h = h }
  end

  -- x offset that centers `text` (at `font`'s width) inside a span of `width`
  local function centeredX(font, text, width)
    local w = font and font:getWidth(text) or 0
    return math.floor((width - w) / 2)
  end

  local function speciesRows()
    local rows = {}
    for _, species in ipairs(state.speciesOrder) do
      rows[#rows + 1] = { species = species, count = state.speciesCounts[species] }
    end
    -- ties broken by name so the list does not reshuffle under itself every
    -- time two species draw level
    table.sort(rows, function(a, b)
      if a.count ~= b.count then return a.count > b.count end
      return tostring(a.species) < tostring(b.species)
    end)
    return rows
  end

  -- The tag doubles as the answer to "why isn't the clock moving?": IDLE is
  -- AUTO HUNT on but the hunt not running -- a menu is up, the game is
  -- loading, or it cannot walk -- which is exactly when the clock parks.
  local function statusText()
    if state.shinyUp then return "SHINY!" end
    if not mod.options:get("enabled") then return "HUNT PAUSED" end
    return state.wasRunning and "HUNT ON" or "HUNT IDLE"
  end

  -- Where the game sits once the HUD owns the window.  Pure geometry off the
  -- window size, so render.compose (which paints the game into it) and
  -- render.hud (which frames it and lays text out around it) agree without
  -- either having to run first.
  local function pipRect(width, height)
    local ref = math.min(width, height)
    local m = math.max(8, math.floor(ref * 0.035))
    local aspect = state.pipAspect
    if not (aspect and aspect > 0) then aspect = GB_ASPECT end
    local w = math.floor(math.min(width * 0.34, height * 0.38 * aspect))
    w = math.max(64, math.min(w, width - m * 2))
    local h = math.floor(w / aspect)
    return { x = math.floor(width - m - w), y = m, w = w, h = h, m = m }
  end

  local function drawMini(vp, areas)
    local ref = math.min(vp.width, vp.height)
    local pad = math.max(5, math.floor(ref * 0.014))
    local font = fontAt(math.max(12, ref * 0.040))
    local text = ("%s   x%d"):format(
      formatElapsed(elapsedRealSeconds()), state.totalEncounters)
    local w = (font and font:getWidth(text) or 90) + pad * 2
    local h = (font and font:getHeight() or 16) + pad * 2
    local x, y = pad, pad
    panel(x, y, w, h)
    printAt(text, font, x + pad, y + pad, state.shinyUp and 1 or 0.95,
      1, 1, state.shinyUp and 0.25 or 1)
    -- the pill is its own tap target: there is no room on it for chips
    areas[#areas + 1] = { id = "pill", mode = "normal", x = x, y = y, w = w, h = h }
  end

  local function drawNormal(vp, areas)
    local ref = math.min(vp.width, vp.height)
    local pad = math.max(5, math.floor(ref * 0.016))
    local chipSize = math.max(26, math.floor(ref * 0.062))
    local tagFont = fontAt(math.max(10, ref * 0.026))
    local timerFont = fontAt(math.max(16, ref * 0.058))
    local countFont = fontAt(math.max(12, ref * 0.036))
    local rowFont = fontAt(math.max(10, ref * 0.026))

    local timer = formatElapsed(elapsedRealSeconds())
    local count = ("ENCOUNTERS  %d"):format(state.totalEncounters)
    local tag = statusText()
    local rows = speciesRows()
    local shown = math.min(#rows, MAX_HUD_SPECIES_ROWS)
    local rowText = {}
    for i = 1, shown do
      rowText[i] = ("%s x%d"):format(speciesLabel(rows[i].species), rows[i].count)
    end
    if #rows > shown then
      rowText[#rowText + 1] = ("+%d more"):format(#rows - shown)
    end

    -- the FOCUS entry chip only shows up when the option is on and there is
    -- no session/offer/summary already occupying the screen -- one way in,
    -- and never a second target stacked under something else
    local showFocusChip = mod.options:get("focus_chip") and not state.focus.active
      and not state.focus.summary and not state.focus.confirm

    local function widthOf(font, text) return font and font:getWidth(text) or 0 end
    local topW = widthOf(tagFont, tag) + pad
      + chipSize * (showFocusChip and 3 or 2) + pad
    local bodyW = math.max(widthOf(timerFont, timer), widthOf(countFont, count))
    for _, text in ipairs(rowText) do
      bodyW = math.max(bodyW, widthOf(rowFont, text))
    end

    local rowH = (rowFont and rowFont:getHeight() or 12) + 2
    local w = math.max(topW, bodyW) + pad * 2
    local h = pad * 2 + chipSize
      + (timerFont and timerFont:getHeight() or 20) + math.floor(pad * 0.4)
      + (countFont and countFont:getHeight() or 14) + math.floor(pad * 0.4)
      + rowH * #rowText

    local x, y = math.max(4, math.floor(ref * 0.012)), math.max(4, math.floor(ref * 0.012))
    -- a mod with very long species names must not push the panel off screen
    w = math.min(w, vp.width - x * 2)
    panel(x, y, w, h)

    local cy = y + pad
    printAt(tag, tagFont,
      x + pad, cy + (chipSize - (tagFont and tagFont:getHeight() or 10)) / 2,
      0.8, 1, 1, state.shinyUp and 0.25 or 1)
    if showFocusChip then
      chip(areas, "focus_offer", nil, "F",
        x + w - pad - chipSize * 3 - 8, cy, chipSize, "offer")
    end
    chip(areas, "shrink", "mini", "-", x + w - pad - chipSize * 2 - 4, cy, chipSize)
    chip(areas, "grow", "full", "+", x + w - pad - chipSize, cy, chipSize)
    cy = cy + chipSize

    cy = cy + printAt(timer, timerFont, x + pad, cy) + math.floor(pad * 0.4)
    cy = cy + printAt(count, countFont, x + pad, cy, 0.9) + math.floor(pad * 0.4)
    for i, text in ipairs(rowText) do
      printAt(text, rowFont, x + pad, cy + (i - 1) * rowH, 0.85)
    end
  end

  local function drawFull(vp, areas)
    local ref = math.min(vp.width, vp.height)
    local pip = pipRect(vp.width, vp.height)
    local m = pip.m
    local chipSize = math.max(28, math.floor(ref * 0.075))

    -- render.compose already painted the game into this rect underneath us;
    -- the frame (and the shiny pulse) go on top of it
    love.graphics.setColor(1, 1, 1, 0.3)
    love.graphics.rectangle("line", pip.x - 1, pip.y - 1, pip.w + 2, pip.h + 2)
    if state.shinyUp and mod.options:get("flash") then
      local pulse = 0.5 + 0.5 * math.sin(nowReal() * 6)
      love.graphics.setLineWidth(3)
      love.graphics.setColor(1, 1, 0, 0.9 * pulse)
      love.graphics.rectangle("line", pip.x - 3, pip.y - 3, pip.w + 6, pip.h + 6)
      love.graphics.setLineWidth(1)
    end
    love.graphics.setColor(1, 1, 1, 1)
    -- the game itself is the other way back down, so a shiny is one tap from
    -- the full-size screen
    areas[#areas + 1] =
      { id = "pip", mode = "normal", x = pip.x, y = pip.y, w = pip.w, h = pip.h }
    chip(areas, "shrink", "normal", "-",
      pip.x + pip.w - chipSize, pip.y + pip.h + math.floor(m * 0.4), chipSize)

    -- text column beside the PiP, or under it when the window is too narrow
    -- for the two to sit side by side
    local colX, colY = m, m
    local colW = pip.x - m * 2
    if colW < vp.width * 0.42 then
      colX = m
      colY = pip.y + pip.h + chipSize + m
      colW = vp.width - m * 2
    end
    -- leave the bottom strip alone: that is where the on-screen d-pad and
    -- A/B live on a phone
    local bottom = vp.height - math.floor(vp.height * 0.16)
    local avail = math.max(60, bottom - colY)

    local y = colY
    local tagFont = fontAt(math.max(12, ref * 0.032))
    y = y + printAt(statusText(), tagFont, colX, y, 0.75,
      1, 1, state.shinyUp and 0.25 or 1) + math.floor(m * 0.2)

    local timer = formatElapsed(elapsedRealSeconds())
    local timerFont = fitFont(timer, colW, math.min(avail * 0.36, vp.height * 0.28))
    local timerH = timerFont and timerFont:getHeight() or 40
    y = y + printAt(timer, timerFont, colX, y) + math.floor(m * 0.35)

    local labelFont = fontAt(math.max(11, timerH * 0.2))
    y = y + printAt("ENCOUNTERS", labelFont, colX, y, 0.7)
    local count = tostring(state.totalEncounters)
    y = y + printAt(count, fitFont(count, colW, timerH * 0.58), colX, y)
      + math.floor(m * 0.5)

    local rows = speciesRows()
    if not rows[1] then return end
    local rowFont = fontAt(math.max(11, timerH * 0.26))
    local rowH = (rowFont and rowFont:getHeight() or 14) + 2
    local perCol = math.max(1, math.floor(math.max(0, bottom - y) / rowH))
    local text, cellW = {}, 0
    for i, row in ipairs(rows) do
      text[i] = ("%s  x%d"):format(speciesLabel(row.species), row.count)
      cellW = math.max(cellW, rowFont and rowFont:getWidth(text[i]) or 0)
    end
    local gap = math.floor(m * 0.8)
    local cols = 1
    if cellW > 0 then
      cols = math.max(1, math.min(3, math.floor((colW + gap) / (cellW + gap))))
    end
    local slots = perCol * cols
    -- the last slot goes to the "+N more" tally when the list overflows
    local shown = #text <= slots and #text or math.max(0, slots - 1)
    for i = 1, shown do
      printAt(text[i], rowFont,
        colX + math.floor((i - 1) / perCol) * (cellW + gap),
        y + ((i - 1) % perCol) * rowH, 0.88)
    end
    if #text > shown then
      printAt(("+%d more"):format(#text - shown), rowFont,
        colX + math.floor(shown / perCol) * (cellW + gap),
        y + (shown % perCol) * rowH, 0.55)
    end
  end

  -- ------------------------------------------------------------- FOCUS UI --
  -- The offer panel (before a session starts), the countdown itself, and a
  -- generic two-button confirm, all layered as overlays over whatever the
  -- normal HUD is already drawing -- reusing panel/printAt/chip/button
  -- rather than a parallel draw stack.

  -- a centered "are you sure" prompt: `lines` of text, then two buttons.
  -- Reused by FOCUS's END confirm; deliberately takes no branch on content,
  -- so a caller that always passes the same `lines` (as the END warning
  -- does) draws a byte-identical panel every time.
  local function drawConfirmPanel(vp, areas, lines, okLabel, okAction, cancelLabel, cancelAction)
    local ref = math.min(vp.width, vp.height)
    local font = fontAt(math.max(12, ref * 0.032))
    local pad = math.max(8, math.floor(ref * 0.02))
    local lineH = (font and font:getHeight() or 16) + 4
    local btnH = math.floor(ref * 0.075)
    local w = math.min(vp.width - pad * 2, math.floor(vp.width * 0.86))
    local h = pad * 2 + lineH * #lines + math.floor(pad * 0.8) + btnH
    local x = math.floor((vp.width - w) / 2)
    local y = math.floor((vp.height - h) / 2)
    panel(x, y, w, h, 0.88)
    local cy = y + pad
    for _, line in ipairs(lines) do
      printAt(line, font, x + centeredX(font, line, w), cy, 0.95)
      cy = cy + lineH
    end
    cy = cy + math.floor(pad * 0.8)
    local half = math.floor((w - pad * 3) / 2)
    button(areas, "confirm_ok", okLabel, x + pad, cy, half, btnH, okAction)
    button(areas, "confirm_cancel", cancelLabel, x + pad * 2 + half, cy, half, btnH, cancelAction)
  end

  local function drawOffer(vp, areas)
    local ref = math.min(vp.width, vp.height)
    local titleFont = fontAt(math.max(14, ref * 0.04))
    local lineFont = fontAt(math.max(11, ref * 0.028))
    local pad = math.max(8, math.floor(ref * 0.02))

    local title = "FOCUS TIMER"
    local lines = { ("FOCUS: %d MIN"):format(focusMinutes()), targetsSummaryText() }
    if not mod.options:get("enabled") then
      lines[#lines + 1] = "AUTO HUNT IS OFF -- NOTHING WILL BE HUNTED"
    end

    local lineH = (lineFont and lineFont:getHeight() or 14) + 4
    local titleH = titleFont and titleFont:getHeight() or 18
    local btnH = math.floor(ref * 0.075)
    local w = math.min(vp.width - pad * 2, math.floor(vp.width * 0.86))
    local h = pad * 2 + titleH + math.floor(pad * 0.6) + lineH * #lines
      + math.floor(pad * 0.8) + btnH * 2 + math.floor(pad * 0.4)

    local x = math.floor((vp.width - w) / 2)
    local y = math.floor((vp.height - h) / 2)
    panel(x, y, w, h, 0.85)

    local cy = y + pad
    printAt(title, titleFont, x + centeredX(titleFont, title, w), cy, 1)
    cy = cy + titleH + math.floor(pad * 0.6)
    for _, line in ipairs(lines) do
      printAt(line, lineFont, x + pad, cy, 0.9)
      cy = cy + lineH
    end
    cy = cy + math.floor(pad * 0.8)

    button(areas, "focus_targets_btn", "TARGETS", x + pad, cy, w - pad * 2, btnH, "targets")
    cy = cy + btnH + math.floor(pad * 0.4)
    local half = math.floor((w - pad * 3) / 2)
    button(areas, "focus_start", "START", x + pad, cy, half, btnH, "start")
    button(areas, "focus_cancel", "CANCEL", x + pad * 2 + half, cy, half, btnH, "cancel")
  end

  -- The countdown screen itself. Nothing here reads state.shinyUp, and that
  -- is the whole point: statusText()/drawMini/drawNormal/drawFull, the only
  -- places SHINY! or the pulse can reach the screen, are simply never
  -- called while a session is active -- this function is dispatched to
  -- instead, so the guarantee comes from render.hud's dispatch order, not a
  -- conditional buried in here.
  local function drawFocus(vp, areas)
    local f = state.focus
    if f.confirm == "end" then
      drawConfirmPanel(vp, areas, FOCUS_END_WARNING, "END NOW", "endnow", "STAY", "cancel")
      return
    end

    local ref = math.min(vp.width, vp.height)
    -- leave the bottom strip alone: the on-screen d-pad and A/B live there
    local bottom = vp.height - math.floor(vp.height * 0.16)
    local labelFont = fontAt(math.max(12, ref * 0.032))
    local timer = formatElapsed(focusRemaining())
    local timerFont = fitFont(timer, vp.width * 0.86, math.min(bottom * 0.34, vp.height * 0.3))

    local y = math.floor(bottom * 0.22)
    printAt("FOCUS", labelFont, centeredX(labelFont, "FOCUS", vp.width), y, 0.6)
    y = y + (labelFont and labelFont:getHeight() or 16) + math.floor(ref * 0.02)
    printAt(timer, timerFont, centeredX(timerFont, timer, vp.width), y, 1)

    local m = math.max(8, math.floor(ref * 0.02))
    local chipSize = math.max(28, math.floor(ref * 0.07))
    chip(areas, "focus_end", nil, "END", vp.width - chipSize - m, m, chipSize, "endask")

    if nowReal() < f.peekUntil then
      -- the static session card: length and targets, never anything that
      -- moves in response to a find (see targetsSummaryText/session length)
      local lineFont = fontAt(math.max(11, ref * 0.026))
      local lines = {
        ("SESSION  %s / %s"):format(
          formatElapsed(nowReal() - (f.startedAt or nowReal())), formatElapsed(f.lengthSec)),
        targetsSummaryText(),
      }
      local pad = math.max(8, math.floor(ref * 0.02))
      local lineH = (lineFont and lineFont:getHeight() or 14) + 4
      local w = math.min(vp.width - pad * 2, math.floor(vp.width * 0.8))
      local h = pad * 2 + lineH * #lines
      local px = math.floor((vp.width - w) / 2)
      local py = bottom - h - m
      panel(px, py, w, h, 0.75)
      local cy = py + pad
      for _, line in ipairs(lines) do
        printAt(line, lineFont, px + centeredX(lineFont, line, w), cy, 0.85)
        cy = cy + lineH
      end
    else
      -- one big invisible target: tapping anywhere above the d-pad strip
      -- (that isn't the END chip, pushed first above) peeks the session card
      areas[#areas + 1] =
        { id = "focus_peek", action = "peek", x = 0, y = 0, w = vp.width, h = bottom }
    end
  end

  local function drawSummary(vp, areas)
    local f = state.focus
    local s = f.summary
    if not s then return end
    local ref = math.min(vp.width, vp.height)
    local titleFont = fontAt(math.max(14, ref * 0.036))
    local lineFont = fontAt(math.max(11, ref * 0.028))
    local pad = math.max(8, math.floor(ref * 0.02))

    local title = s.reason == "early" and "FOCUS ENDED EARLY" or "FOCUS COMPLETE"
    local lines = {
      ("%s   ENCOUNTERS %d"):format(formatElapsed(s.seconds), s.encounters),
      s.shiny and ("SHINY: %s"):format(speciesLabel(s.species)) or "NO SHINY",
    }
    if s.skipped and s.skipped > 0 then
      lines[#lines + 1] = ("%d non-target shiny(s) fled"):format(s.skipped)
    end

    local lineH = (lineFont and lineFont:getHeight() or 14) + 4
    local titleH = titleFont and titleFont:getHeight() or 18
    local btnH = math.floor(ref * 0.075)
    local w = math.min(vp.width - pad * 2, math.floor(vp.width * 0.86))
    local h = pad * 2 + titleH + math.floor(pad * 0.6) + lineH * #lines
      + math.floor(pad * 0.8) + btnH + pad

    local x = math.floor((vp.width - w) / 2)
    local y = math.floor((vp.height - h) / 2)
    panel(x, y, w, h, 0.9)

    local cy = y + pad
    printAt(title, titleFont, x + centeredX(titleFont, title, w), cy, 1)
    cy = cy + titleH + math.floor(pad * 0.6)
    for _, line in ipairs(lines) do
      printAt(line, lineFont, x + pad, cy, 0.9)
      cy = cy + lineH
    end
    cy = cy + math.floor(pad * 0.8)
    button(areas, "focus_dismiss", "OK", x + pad, cy, w - pad * 2, btnH, "dismiss")
  end

  mod.hooks:wrap("render.hud", function(next, game, viewport)
    next(game, viewport)
    state.hitAreas = nil
    if not (love and love.graphics) then return end

    local vp = {
      width = (viewport and viewport.width) or love.graphics.getWidth(),
      height = (viewport and viewport.height) or love.graphics.getHeight(),
    }
    if not (vp.width and vp.height and vp.width > 0 and vp.height > 0) then return end

    -- viewport calc is hoisted above the SHOW HUD gate: a FOCUS session or
    -- its summary draws regardless of that setting -- a covered screen
    -- with no countdown, or a result nobody can dismiss, would be a soft
    -- lock. Anything else falls through to the existing SHOW HUD-gated path
    -- unchanged.
    local prevFont = love.graphics.getFont()
    local areas = {}
    local function drawUnderlyingHud()
      if not mod.options:get("show_hud") then return end
      if state.hudMode == "mini" then
        drawMini(vp, areas)
      elseif state.hudMode == "full" then
        drawFull(vp, areas)
      else
        drawNormal(vp, areas)
      end
    end

    if state.focus.active then
      drawFocus(vp, areas)
    elseif state.focus.confirm == "offer" then
      drawUnderlyingHud()
      drawOffer(vp, areas)
    elseif state.focus.summary then
      drawUnderlyingHud()
      drawSummary(vp, areas)
    elseif mod.options:get("show_hud") then
      drawUnderlyingHud()
    else
      return
    end
    state.hitAreas = areas
    love.graphics.setColor(1, 1, 1, 1)
    if prevFont then love.graphics.setFont(prevFont) end
  end)

  -- Full-size HUD: take the window over and re-composite the finished game
  -- frame into the PiP ourselves, so the battle is still on screen -- just
  -- small -- while the clock and the counters get the rest of it.  Any other
  -- size falls straight through to the engine's normal composite.
  mod.hooks:wrap("render.compose", function(next, renderer, ctx)
    -- A FOCUS session owns the window outright: the game's canvases are
    -- never blitted, so nothing about what is behind the cover -- a shiny
    -- battle included -- can reach the screen. Returning true without
    -- calling next is what consumes the composite entirely. This ignores
    -- SHOW HUD on purpose: turning the HUD off mid-session must not
    -- uncover the screen, or leave the countdown with nothing to draw over.
    if state.focus.active and love and love.graphics and ctx then
      local uiw, uih = ctx.uiw or 160, ctx.uih or 144
      if uiw > 0 and uih > 0 then state.pipAspect = uiw / uih end
      love.graphics.setColor(0, 0, 0, 1)
      love.graphics.rectangle("fill", 0, 0, ctx.ww or 0, ctx.wh or 0)
      love.graphics.setColor(1, 1, 1, 1)
      return true
    end

    if state.hudMode ~= "full" or not mod.options:get("show_hud")
       or not (love and love.graphics and ctx and renderer.blitCanvas) then
      return next(renderer, ctx)
    end

    local uiw = ctx.uiw or 160
    local uih = ctx.uih or 144
    if uiw <= 0 or uih <= 0 then return next(renderer, ctx) end
    state.pipAspect = uiw / uih
    local pip = pipRect(ctx.ww, ctx.wh)

    love.graphics.setColor(0.05, 0.06, 0.09, 1)
    love.graphics.rectangle("fill", 0, 0, ctx.ww, ctx.wh)
    love.graphics.setColor(0, 0, 0, 1)
    love.graphics.rectangle("fill", pip.x, pip.y, pip.w, pip.h)
    love.graphics.setColor(1, 1, 1, 1)

    local scale = math.min(pip.w / uiw, pip.h / uih)
    if ctx.worldOverride then
      -- a render pipeline already produced the whole window as one image, so
      -- it goes in as a single scaled draw (the iOS/LOVE 12 flip is the same
      -- one the engine's own composite does for this canvas)
      local img = ctx.worldOverride
      local iw = img:getWidth() / (ctx.dpiX or 1)
      local ih = img:getHeight() / (ctx.dpiY or 1)
      local s = math.min(pip.w / iw, pip.h / ih)
      local dx = pip.x + (pip.w - iw * s) / 2
      local dy = pip.y + (pip.h - ih * s) / 2
      local flipped = love.system and love.system.getOS
        and love.system.getOS() == "iOS" and select(1, love.getVersion()) >= 12
      love.graphics.setScissor(pip.x, pip.y, pip.w, pip.h)
      if flipped then
        love.graphics.draw(img, dx, dy + ih * s, 0,
          s / (ctx.dpiX or 1), -s / (ctx.dpiY or 1))
      else
        love.graphics.draw(img, dx, dy, 0, s / (ctx.dpiX or 1), s / (ctx.dpiY or 1))
      end
      love.graphics.setScissor()
    elseif ctx.worldActive and ctx.worldCanvas then
      local wvw = ctx.worldCanvas:getWidth()
      local wvh = ctx.worldCanvas:getHeight()
      renderer:blitCanvas(ctx.worldCanvas, scale, scale,
        ctx.worldZones or ctx.zones, scale, scale,
        pip.x + (pip.w - wvw * scale) / 2, pip.y + (pip.h - wvh * scale) / 2,
        pip.x, pip.y, pip.w, pip.h, ctx.dpiX, ctx.dpiY)
    end
    if ctx.uiCanvas then
      renderer:blitCanvas(ctx.uiCanvas, scale, scale, ctx.zones, scale, scale,
        pip.x + (pip.w - uiw * scale) / 2, pip.y + (pip.h - uih * scale) / 2,
        pip.x, pip.y, pip.w, pip.h, ctx.dpiX, ctx.dpiY)
    end
    love.graphics.setColor(1, 1, 1, 1)
    return true
  end)

  -- Taps on the HUD's own chips resize it.  A press that lands on one is
  -- consumed for that pointer's whole lifecycle so the game never sees half
  -- a touch, and the resize only fires if the release lands on the same
  -- target -- dragging off it cancels, the way a button should.
  local function areaAt(x, y)
    for _, area in ipairs(state.hitAreas or {}) do
      if x >= area.x and x <= area.x + area.w
         and y >= area.y and y <= area.y + area.h then
        return area
      end
    end
    return nil
  end

  mod.hooks:wrap("input.pointer", function(next, game, ev)
    if not ev then return next(game, ev) end

    -- While a session is active the screen is fully covered by
    -- render.compose, so a tap that misses our own chips must NOT reach the
    -- game underneath -- unlike the normal-HUD miss behaviour below, which
    -- deliberately lets a d-pad press under a corner panel through. Falling
    -- through here would let a blind tap (the peek's ~4s window, the END
    -- confirm's own gaps, or just resting a thumb on the glass) drive the
    -- hidden battle: advance a text box, pick a move, even RUN -- exactly
    -- what the cover exists to prevent touching. offer/summary are exempt:
    -- the game is genuinely visible underneath both, so a miss reaching it
    -- is the same harmless behaviour a miss on the normal HUD already has.
    local coveredMustSwallow = state.focus.active

    if not (mod.options:get("show_hud") or coveredMustSwallow or state.focus.summary) then
      return next(game, ev)
    end

    if state.grabbedId ~= nil and ev.id == state.grabbedId then
      if ev.phase == "released" then
        local area = areaAt(ev.x, ev.y)
        if area and area.id == state.grabbedArea then
          if area.action then
            focusAction(area.action, game)
          elseif area.mode then
            state.hudMode = area.mode
          end
        end
        state.grabbedId, state.grabbedArea = nil, nil
      elseif ev.phase == "cancelled" then
        state.grabbedId, state.grabbedArea = nil, nil
      end
      return true
    end

    if ev.phase == "pressed" then
      local area = areaAt(ev.x, ev.y)
      if area then
        state.grabbedId, state.grabbedArea = ev.id, area.id
        return true
      end
    end
    if coveredMustSwallow then return true end
    return next(game, ev)
  end)

  -- ---------------------------------------------------------- speed cap --
  -- The engine reads save.options.speed live every frame (Game:logicSpeed),
  -- so holding it down here is all it takes: the GAME SPEED row, the "1"
  -- hotkey and the shoulder buttons all still cycle, they just cannot leave
  -- the value above the cap for longer than a tick.  The --speed /
  -- POKEPORT_SPEED run argument wins over the option, so it is pushed down
  -- with it.
  --
  -- The cap lasts exactly as long as AUTO HUNT does.  Both values are
  -- stashed on the way down and handed back the moment hunting stops, so
  -- turning the hunt off leaves the game at the speed the player chose --
  -- this mod is not allowed to quietly keep a setting it lowered.  The stash
  -- is refreshed on every clamp, so what comes back is the last speed they
  -- actually asked for, and it is only restored if the live value is still
  -- the one we imposed: if anything else moved it in the meantime, that
  -- newer choice wins and we drop ours.
  local function speedCapValue()
    local n = tonumber(mod.options:get("speed_cap"))
    if not n or n < 1 then return MAX_SPEED_CAP end
    return math.min(n, MAX_SPEED_CAP)
  end

  local function applySpeedCap(game, hunting)
    local opts = game and game.save and game.save.options
    if hunting then
      local cap = speedCapValue()
      if opts and (tonumber(opts.speed) or 1) > cap then
        state.optionStash = opts.speed
        state.optionCapped = cap
        opts.speed = cap
        if game.writeOptions then pcall(game.writeOptions, game) end
      end
      local override = tonumber(game and game.speedOverride)
      if override and override > cap then
        state.overrideStash = game.speedOverride
        state.overrideCapped = cap
        game.speedOverride = cap
      end
      return
    end

    if state.optionStash ~= nil then
      if opts and tonumber(opts.speed) == state.optionCapped then
        opts.speed = state.optionStash
        if game.writeOptions then pcall(game.writeOptions, game) end
      end
      state.optionStash, state.optionCapped = nil, nil
    end
    if state.overrideStash ~= nil then
      if game and tonumber(game.speedOverride) == state.overrideCapped then
        game.speedOverride = state.overrideStash
      end
      state.overrideStash, state.overrideCapped = nil, nil
    end
  end

  -- Is the hunt actually running right now?  This is what the clock counts:
  --
  --   * a battle counts, whatever kind and however long it stays up.  The
  --     fight is part of the hunt's own cycle, and a shiny left on screen is
  --     the hunt still holding its result out for you.
  --   * a menu, a dialog, the title screen or a load on top of the overworld
  --     is not hunting, and neither is anything else that stops the shuffle.
  --   * on the overworld it counts once the shuffle is genuinely walking,
  --     rather than merely unblocked -- which is what keeps a boot straight
  --     into a hunting save from counting its loading screen, whatever the
  --     screen stack happened to look like before this mod was listening.
  local function huntIsRunning(hunting)
    if not hunting then return false end
    if state.inBattle then return true end
    if state.blockingLayers > 0 then return false end
    return state.token ~= nil or state.awaitingConfirm
  end

  mod.hooks:wrap("input.step", function(next, game, dt)
    -- unconditional and first: a FOCUS countdown, its keep-awake, and its
    -- own expiry must run whatever AUTO HUNT or the screen stack is doing
    focusTick(game)

    local hunting = mod.options:get("enabled")
    applySpeedCap(game, hunting)

    local running = huntIsRunning(hunting)
    if running and not state.wasRunning then
      state.resumedAt = nowReal()
    elseif not running and state.wasRunning then
      state.elapsedBase = state.elapsedBase + (nowReal() - (state.resumedAt or nowReal()))
      state.resumedAt = nil
    end
    state.wasRunning = running

    -- state.fleeing is only ever set by our own flee (the auto-hunt one, or
    -- a FOCUS session's forced early exit), so it never needed `hunting` on
    -- top of it -- and a focus exit must mash through the text box even
    -- with AUTO HUNT switched off
    if state.fleeing then
      -- one fresh wasPressed edge per tick -- mashing, not holding, since
      -- each text box needs its own edge to advance
      mod.input:tap(game, "a")
    end

    local blocked = state.blockingLayers > 0

    -- Resolve any step we're still waiting to confirm. This has to run
    -- even while blocked (a menu popped up, or the very step we're on
    -- triggered an encounter) -- otherwise the flip that step earned gets
    -- eaten, and the *next* hold repeats the same direction, walking the
    -- axis off its original two tiles instead of alternating in place.
    if state.token or state.awaitingConfirm then
      local cur = mod.world:current()
      local moved = cur and state.lastPos
        and (cur.x ~= state.lastPos.x or cur.y ~= state.lastPos.y)
      if not blocked then state.holdFor = state.holdFor + dt end
      local timedOut = not blocked and state.holdFor > MAX_HOLD_SECONDS
      if moved or timedOut then
        if state.token then mod.input:release(state.token); state.token = nil end
        state.awaitingConfirm = false
        local a, b = mod.options:get("dir_a"), mod.options:get("dir_b")
        state.dir = (state.dir == a) and b or a
      elseif blocked and state.token then
        -- stop physically holding into whatever just came up, but keep
        -- waiting to learn whether that hold's step actually landed
        mod.input:release(state.token)
        state.token = nil
        state.awaitingConfirm = true
      end
    end

    if not hunting or blocked or state.awaitingConfirm then
      if state.token then mod.input:release(state.token); state.token = nil end
      return next(game, dt)
    end

    if mod.options:get("keep_awake") and love.window
       and love.window.setDisplaySleepEnabled then
      love.window.setDisplaySleepEnabled(false)
    end

    local cur = mod.world:current()
    if not cur then return next(game, dt) end

    if not state.dir then state.dir = mod.options:get("dir_a") end
    if not state.token then
      state.token = mod.input:press(game, state.dir)
      state.lastPos = { x = cur.x, y = cur.y }
      state.holdFor = 0
    end

    return next(game, dt)
  end)
end
