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

-- how long to hold a direction before giving up on it landing a step and
-- flipping anyway -- a real step lands well under this, so it only fires
-- when the way is blocked
local MAX_HOLD_SECONDS = 0.9

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
  })

  local state = {
    dir = nil, token = nil, holdFor = 0, lastPos = nil,
    -- how many non-overworld screens are currently stacked above the
    -- overworld (menus, dialogs, battle, ...): only the TOPMOST screen
    -- ever reads input, so walking must stay silent whenever this is > 0
    -- -- that's the whole options-menu-scrolling-itself bug.
    blockingLayers = 0,
    fleeing = false, autoRunArmed = false, shinyUp = false,
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
      stopWalking()
    end
  end)

  mod.events:on("screen.popped", function(ev)
    if isBlocking(ev.state) then
      state.blockingLayers = math.max(0, state.blockingLayers - 1)
    end
  end)

  mod.events:on("battle.started", function(ev)
    state.shinyUp = false
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
      local t = (love.timer and love.timer.getTime and love.timer.getTime()) or 0
      local pulse = 0.5 + 0.5 * math.sin(t * 6)
      love.graphics.setColor(1, 1, 0, 0.35 * pulse)
      love.graphics.rectangle("line", 2, 2, 156, 140)
      love.graphics.setColor(1, 1, 1, 1)
    end
  end)

  mod.hooks:wrap("input.step", function(next, game, dt)
    if mod.options:get("enabled") and state.fleeing then
      -- one fresh wasPressed edge per tick -- mashing, not holding, since
      -- each text box needs its own edge to advance
      mod.input:tap(game, "a")
    end

    if not mod.options:get("enabled") or state.blockingLayers > 0 then
      stopWalking()
      return next(game, dt)
    end

    if mod.options:get("keep_awake") and love.window
       and love.window.setDisplaySleepEnabled then
      love.window.setDisplaySleepEnabled(false)
    end
    local cur = mod.world:current()
    if not cur then
      stopWalking()
      return next(game, dt)
    end
    if not state.dir then state.dir = mod.options:get("dir_a") end
    if not state.token then
      state.token = mod.input:press(game, state.dir)
      state.lastPos = { x = cur.x, y = cur.y }
      state.holdFor = 0
    else
      state.holdFor = state.holdFor + dt
      local moved = state.lastPos
        and (cur.x ~= state.lastPos.x or cur.y ~= state.lastPos.y)
      if moved or state.holdFor > MAX_HOLD_SECONDS then
        mod.input:release(state.token)
        state.token = nil
        local a, b = mod.options:get("dir_a"), mod.options:get("dir_b")
        state.dir = (state.dir == a) and b or a
      end
    end
    return next(game, dt)
  end)
end
