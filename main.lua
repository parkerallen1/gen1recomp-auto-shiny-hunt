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

-- how long a *confirmed-uninterrupted* hold can run before giving up on
-- it landing a step and flipping anyway -- a real step lands well under
-- this, so it only fires when the way is genuinely blocked
local MAX_HOLD_SECONDS = 0.9

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

local MAX_HUD_SPECIES_ROWS = 8

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
        .. "to deal with a shiny." },
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
    -- battle reaction
    fleeing = false, autoRunArmed = false, shinyUp = false,
    -- stats: elapsed is real (wall-clock) time, deliberately not tied to
    -- GAME SPEED or fixed-step dt -- love.timer.getTime() is a real clock
    wasHunting = false, elapsedBase = 0, resumedAt = nil,
    totalEncounters = 0, speciesCounts = {}, speciesOrder = {},
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
  end)

  local function speciesLabel(species)
    local ok, def = pcall(function() return mod.content.pokemon:get(species) end)
    if ok and def and def.name then return def.name end
    return tostring(species or "?")
  end

  mod.events:on("battle.started", function(ev)
    state.shinyUp = false
    if ev.kind == "wild" then
      local species = ev.battle and ev.battle.enemy and ev.battle.enemy.mon
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
      state.shinyUp = true
      if mod.options:get("vibrate") and love.system and love.system.vibrate then
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
    if state.shinyUp and mod.options:get("flash") then
      local t = nowReal()
      local pulse = 0.5 + 0.5 * math.sin(t * 6)
      love.graphics.setColor(1, 1, 0, 0.35 * pulse)
      love.graphics.rectangle("line", 2, 2, 156, 140)
      love.graphics.setColor(1, 1, 1, 1)
    end
  end)

  local hudFont
  local function elapsedRealSeconds()
    local total = state.elapsedBase
    if state.resumedAt then total = total + (nowReal() - state.resumedAt) end
    return total
  end

  mod.hooks:wrap("render.hud", function(next, game, viewport)
    next(game, viewport)
    if not mod.options:get("show_hud") then return end
    if not (love and love.graphics) then return end

    if not hudFont then
      local ok, font = pcall(love.graphics.newFont, 14)
      hudFont = ok and font or false
    end

    local lines = {
      ("HUNT %s: %s"):format(
        mod.options:get("enabled") and "ON" or "PAUSED",
        formatElapsed(elapsedRealSeconds())),
      ("ENCOUNTERS: %d"):format(state.totalEncounters),
    }
    local rows = {}
    for _, species in ipairs(state.speciesOrder) do
      rows[#rows + 1] = { species = species, count = state.speciesCounts[species] }
    end
    table.sort(rows, function(a, b) return a.count > b.count end)
    for i = 1, math.min(#rows, MAX_HUD_SPECIES_ROWS) do
      lines[#lines + 1] = ("  %s x%d"):format(speciesLabel(rows[i].species), rows[i].count)
    end
    if #rows > MAX_HUD_SPECIES_ROWS then
      lines[#lines + 1] = ("  ...+%d more"):format(#rows - MAX_HUD_SPECIES_ROWS)
    end

    local prevFont = love.graphics.getFont()
    if hudFont then love.graphics.setFont(hudFont) end
    local lineH = love.graphics.getFont():getHeight() + 2
    local w = 0
    for _, line in ipairs(lines) do
      w = math.max(w, love.graphics.getFont():getWidth(line))
    end
    local x, y = 6, 6
    love.graphics.setColor(0, 0, 0, 0.55)
    love.graphics.rectangle("fill", x - 4, y - 4, w + 8, #lines * lineH + 4)
    love.graphics.setColor(1, 1, 1, 1)
    for i, line in ipairs(lines) do
      love.graphics.print(line, x, y + (i - 1) * lineH)
    end
    love.graphics.setColor(1, 1, 1, 1)
    if prevFont then love.graphics.setFont(prevFont) end
  end)

  mod.hooks:wrap("input.step", function(next, game, dt)
    local hunting = mod.options:get("enabled")

    if hunting and not state.wasHunting then
      state.resumedAt = nowReal()
    elseif not hunting and state.wasHunting then
      state.elapsedBase = state.elapsedBase + (nowReal() - (state.resumedAt or nowReal()))
      state.resumedAt = nil
    end
    state.wasHunting = hunting

    if hunting and state.fleeing then
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
