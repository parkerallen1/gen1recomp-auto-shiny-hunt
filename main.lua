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

  mod.events:on("battle.started", function(ev)
    -- set before any of the early returns below: the clock counts every
    -- battle, including the trainer and Safari ones this mod stays out of
    state.inBattle = true
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
    state.inBattle = false
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

  local function elapsedRealSeconds()
    local total = state.elapsedBase
    if state.resumedAt then total = total + (nowReal() - state.resumedAt) end
    return total
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
  -- caller so input.pointer can find it
  local function chip(areas, id, mode, label, x, y, size)
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
    areas[#areas + 1] = { id = id, mode = mode, x = x, y = y, w = size, h = size }
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

    local function widthOf(font, text) return font and font:getWidth(text) or 0 end
    local topW = widthOf(tagFont, tag) + pad + chipSize * 2 + pad
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

  mod.hooks:wrap("render.hud", function(next, game, viewport)
    next(game, viewport)
    state.hitAreas = nil
    if not mod.options:get("show_hud") then return end
    if not (love and love.graphics) then return end

    local vp = {
      width = (viewport and viewport.width) or love.graphics.getWidth(),
      height = (viewport and viewport.height) or love.graphics.getHeight(),
    }
    if not (vp.width and vp.height and vp.width > 0 and vp.height > 0) then return end

    local prevFont = love.graphics.getFont()
    local areas = {}
    if state.hudMode == "mini" then
      drawMini(vp, areas)
    elseif state.hudMode == "full" then
      drawFull(vp, areas)
    else
      drawNormal(vp, areas)
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
    if not (ev and mod.options:get("show_hud")) then return next(game, ev) end

    if state.grabbedId ~= nil and ev.id == state.grabbedId then
      if ev.phase == "released" then
        local area = areaAt(ev.x, ev.y)
        if area and area.id == state.grabbedArea then
          state.hudMode = area.mode
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
