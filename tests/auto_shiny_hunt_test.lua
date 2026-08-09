-- What this mod promises, asserted against a stand-in engine (tests/harness).
-- Runs in about a second under plain Lua, so it is the check to make before
-- every release -- and the thing that says an engine or peer-mod update
-- broke something before a player finds out.

package.path = "./tests/?.lua;./?.lua;" .. package.path
local H = require("harness")

local failures, checks = 0, 0
local function ok(cond, what)
  checks = checks + 1
  if cond then
    print("  ok   " .. what)
  else
    failures = failures + 1
    print("  FAIL " .. what)
  end
  return cond
end
local function run(what, fn)
  local good, err = pcall(fn)
  return ok(good, what .. (good and "" or (" -- " .. tostring(err))))
end
local function section(name) print("\n" .. name) end

local rec = H.installLove()
local SIZES = { { 480, 432 }, { 800, 600 }, { 1080, 2340 }, { 2340, 1080 }, { 320, 240 } }

-- ------------------------------------------------------------ manifest --

section("manifest")
do
  local manifest = assert(io.open("manifest.json")):read("a")
  local range = manifest:match('"game_version"%s*:%s*"([^"]+)"')
  -- input.pointer landed in engine v0.1.69 (it is absent in v0.1.68) and the
  -- HUD's tap chips are unreachable without it. The dev placeholder has to be
  -- spelled out because a semver range never matches a prerelease on its own,
  -- and the ceiling has to clear 1.0 or the mod stops loading the day the
  -- engine ships it.
  ok(range and range:find("0%.1%.69", 1) and range:find("0%.0%.0%-dev", 1)
     and range:find("<%s*2%.0%.0"),
     "game_version floors at 0.1.69, allows -dev, and does not stop at 1.0")
end

section("options")
do
  local t = H.load()
  local cap
  for _, row in ipairs(t.schema) do if row.key == "speed_cap" then cap = row end end
  ok(cap and cap.default == "4", "SPEED CAP defaults to 4X")
  local highest = 0
  for _, choice in ipairs(cap.choices) do
    highest = math.max(highest, tonumber(choice[2]) or 0)
  end
  ok(highest == 4, "no rung above 4X is offered (highest = " .. highest .. ")")
end

-- ----------------------------------------------------------- speed cap --

section("speed cap")
do
  local t = H.load()
  t.options.enabled = true

  local g = H.game(200)
  t.step(g)
  ok(g.save.options.speed == 4, "200X is pinned back to 4X while hunting")
  ok(g.writes == 1, "the clamped value is written back")
  t.step(g)
  ok(g.writes == 1, "an already-capped speed is not rewritten every tick")

  g = H.game(2)
  t.step(g)
  ok(g.save.options.speed == 2, "a speed under the cap is left alone")

  t.options.speed_cap = "2"
  g = H.game(4)
  t.step(g)
  ok(g.save.options.speed == 2, "a tighter cap is honoured")
  t.options.speed_cap = "4"

  -- the --speed / POKEPORT_SPEED run argument wins over the saved option in
  -- Game:logicSpeed, so the cap has to reach it too -- and give it back
  g = H.game(1, 100)
  t.step(g)
  ok(g.speedOverride == 4, "the run-argument override is capped as well")
  t.options.enabled = false
  t.step(g)
  ok(g.speedOverride == 100, "hunting off hands the player's override back")

  t.options.enabled = true
  g = H.game(1, 100)
  t.step(g)
  g.speedOverride = 7
  t.options.enabled = false
  t.step(g)
  ok(g.speedOverride == 7, "an override changed by someone else is not stomped")

  g = H.game(50)
  t.step(g)
  ok(g.save.options.speed == 50, "with hunting off GAME SPEED is untouched")

  run("a game with no save yet survives the step", function()
    t.step({ input = {} })
  end)
end

-- ------------------------------------------------------------- shinies --

section("shiny detection and fleeing")
do
  local t = H.load()
  t.options.enabled = true

  local function started(dvs, species, extra)
    local fled = false
    local ev = H.wildEvent(dvs, species, extra)
    ev.battle.tryRun = function() fled = true end
    t.emit("battle.started", ev)
    return fled
  end

  ok(started(H.COMMON_DVS, 4), "a common wild is fled")
  t.emit("battle.ended", {})
  ok(not started(H.SHINY_DVS, 5), "a shiny wild is left alone")
  t.emit("battle.ended", {})

  -- Dramatic Shape 1.8.1 and the standalone Shiny Pokemon mod both write
  -- their verdict INTO the DVs (forceShiny / applyShinyToMon) and keep
  -- mon.shiny only as a cache, so both have to read correctly here.
  for _, case in ipairs({
    { name = "the DV pattern alone", shiny = true, dvs = H.SHINY_DVS },
    { name = "DVs plus the mon.shiny cache", shiny = true,
      dvs = H.SHINY_DVS, extra = { shiny = true } },
    { name = "the top attack DV in the set", shiny = true,
      dvs = { attack = 15, defense = 10, speed = 10, special = 10 } },
    { name = "forceCommon's one-point nudge on Special", shiny = false,
      dvs = { attack = 2, defense = 10, speed = 10, special = 9 } },
    { name = "an attack DV outside the set", shiny = false,
      dvs = { attack = 5, defense = 10, speed = 10, special = 10 } },
    { name = "no DVs at all", shiny = false, dvs = nil },
  }) do
    local fled = started(case.dvs, 6, case.extra)
    t.emit("battle.ended", {})
    ok(fled ~= case.shiny, ("%s reads as %s"):format(case.name,
      case.shiny and "shiny" or "common"))
  end

  -- only the flee this mod fires is forced; a manual RUN keeps Gen 1's odds
  started(H.COMMON_DVS, 7)
  ok(t.run({}) == true, "our own flee is forced to succeed")
  ok(t.run({}) == "vanilla", "the force is spent after one RUN")
  t.emit("battle.ended", {})
  ok(t.run({}) == "vanilla", "a RUN outside our flee is never forced")

  local touched = false
  t.emit("battle.started", { kind = "trainer",
    battle = { enemy = { mon = { species = 9, dvs = H.SHINY_DVS } },
               tryRun = function() touched = true end } })
  ok(not touched, "a trainer battle is left entirely alone")
  t.emit("battle.ended", {})

  -- with hunting paused the HUD still counts, but nothing is fled
  t.options.enabled = false
  ok(not started(H.COMMON_DVS, 4), "paused, a wild battle is not fled")
  t.emit("battle.ended", {})
end

-- ----------------------------------------------------------------- HUD --

section("HUD draws at every size")
do
  local t = H.load({ speciesName = "NIDORANFEMALE" })
  t.options.enabled = true
  for i = 1, 400 do
    t.emit("battle.started", H.wildEvent(H.COMMON_DVS, i % 37))
    t.emit("battle.ended", {})
  end

  for _, mode in ipairs({ "mini", "normal", "full" }) do
    for _, wh in ipairs(SIZES) do
      run(("%s draws at %dx%d"):format(mode, wh[1], wh[2]), function()
        t.state.hudMode = mode
        t.compose(H.composeCtx(wh[1], wh[2]))
        t.hud(H.viewport(wh[1], wh[2]))
      end)
    end
  end
end

section("HUD layout")
do
  local t = H.load()
  t.options.enabled = true
  for i = 1, 40 do
    t.emit("battle.started", H.wildEvent(H.COMMON_DVS, i % 9))
    t.emit("battle.ended", {})
  end

  -- the clock is the biggest thing on it, the total next, species last
  for _, mode in ipairs({ "normal", "full" }) do
    t.state.hudMode = mode
    rec.reset()
    t.compose(H.composeCtx(1080, 2340))
    t.hud(H.viewport(1080, 2340))
    local clock, total, species = 0, 0, 0
    for _, p in ipairs(rec.prints) do
      if p.text:match("^%d+:%d%d") then clock = math.max(clock, p.px) end
      if p.text:match("^ENCOUNTERS") or p.text:match("^%d+$") then
        total = math.max(total, p.px)
      end
      if p.text:match("^MON%d") then species = math.max(species, p.px) end
    end
    ok(clock > total and total > species,
      ("%s ranks clock(%d) > total(%d) > species(%d)")
        :format(mode, clock, total, species))
  end

  -- nothing off screen, and in full size nothing over the game's PiP
  for _, wh in ipairs(SIZES) do
    for _, mode in ipairs({ "mini", "normal", "full" }) do
      local W, Ht = wh[1], wh[2]
      t.state.hudMode = mode
      rec.reset()
      t.compose(H.composeCtx(W, Ht))
      -- render.compose paints the backdrop and then the PiP: the second fill
      local pip = mode == "full" and rec.rects[2] or nil
      local composeRects = #rec.rects
      t.hud(H.viewport(W, Ht))
      local off, over
      for _, p in ipairs(rec.prints) do
        if p.x < 0 or p.y < 0 or p.x + p.w > W + 1 or p.y + p.h > Ht + 1 then
          off = off or ("%q at %d,%d"):format(p.text, p.x, p.y)
        end
        if pip and p.x < pip.x + pip.w and p.x + p.w > pip.x
           and p.y < pip.y + pip.h and p.y + p.h > pip.y then
          over = over or ("%q"):format(p.text)
        end
      end
      ok(not off, ("%s at %dx%d keeps every line on screen%s")
        :format(mode, W, Ht, off and (" -- " .. off) or ""))
      if pip then
        ok(not over, ("full at %dx%d keeps text clear of the PiP%s")
          :format(W, Ht, over and (" -- " .. over) or ""))
        ok(composeRects >= 2, ("full at %dx%d paints a backdrop and a PiP")
          :format(W, Ht))
      end
    end
  end
end

section("HUD composite")
do
  local t = H.load()

  t.state.hudMode = "normal"
  local vanilla = false
  t.compose(H.composeCtx(800, 600), { blitCanvas = function() end })
  ok(t.compose(H.composeCtx(800, 600)) ~= true,
     "at corner size the engine's own composite is left alone")

  t.state.hudMode = "full"
  local blits = 0
  local ctx = H.composeCtx(1080, 2340, {
    worldActive = true, worldZones = {}, worldCanvas = H.canvas(176, 160),
    dpiX = 2, dpiY = 2,
  })
  local took = t.compose(ctx, { blitCanvas = function() blits = blits + 1 end })
  ok(took == true, "at full size the mod takes the window over")
  ok(blits == 2, "the world and UI canvases are both blitted into the PiP")

  -- a render pipeline (the voxel mod's diorama) hands over one window-sized
  -- image instead of the world canvas; it has to reach the PiP too
  rec.reset()
  ctx = H.composeCtx(800, 600, { worldActive = true, worldOverride = H.canvas(800, 600) })
  ok(t.compose(ctx) == true and rec.draws == 1,
     "a pipeline's whole-window image is drawn into the PiP")

  -- and with the HUD switched off the mod stands down entirely
  t.options.show_hud = false
  ok(t.compose(H.composeCtx(800, 600)) ~= true,
     "with SHOW HUD off the composite is never taken over")
  local passed = false
  t.hud(H.viewport(800, 600))
  t.pointer({ phase = "pressed", id = "x", x = 10, y = 10 })
  ok(t.state.hitAreas == nil, "with SHOW HUD off no tap targets are published")
  local _ = passed
  t.options.show_hud = true
end

section("HUD taps")
do
  local t = H.load()
  t.options.enabled = true
  local vp = H.viewport(800, 600)

  t.hud(vp)
  ok(t.area("grow") and t.area("shrink"), "the corner panel publishes both chips")
  ok(t.tap("grow"), "the + chip takes the tap")
  ok(t.state.hudMode == "full", "+ expands the HUD to full screen")

  t.compose(H.composeCtx(800, 600)); t.hud(vp)
  ok(t.tap("shrink") and t.state.hudMode == "normal", "- brings it back to the corner")

  t.hud(vp)
  ok(t.tap("shrink") and t.state.hudMode == "mini", "- again shrinks it to the pill")

  t.hud(vp)
  ok(t.tap("pill") and t.state.hudMode == "normal", "tapping the pill restores it")

  -- the game itself is the other way out of full size
  t.state.hudMode = "full"
  t.compose(H.composeCtx(800, 600)); t.hud(vp)
  ok(t.tap("pip") and t.state.hudMode == "normal", "tapping the PiP returns to the game")

  -- a press that wanders off its target must not resize anything
  t.hud(vp)
  local chip = t.area("grow")
  t.pointer({ phase = "pressed", id = "d", x = chip.x + 2, y = chip.y + 2 })
  t.pointer({ phase = "released", id = "d", x = 700, y = 560 })
  ok(t.state.hudMode == "normal", "dragging off a chip cancels it")

  -- and a cancelled pointer (focus loss) leaves nothing latched
  t.pointer({ phase = "pressed", id = "e", x = chip.x + 2, y = chip.y + 2 })
  t.pointer({ phase = "cancelled", id = "e", x = chip.x + 2, y = chip.y + 2 })
  ok(t.state.hudMode == "normal", "a cancelled press changes nothing")
  ok(t.pointer({ phase = "pressed", id = "z", x = 780, y = 560 }) ~= true,
     "a tap that misses the HUD reaches the game")
end

-- ------------------------------------------------------------ peer mod --

section("peer mod on the same hooks")
do
  -- Gen1 Modern UI wraps render.compose, render.hud and input.pointer at
  -- priority 100 -- ahead of ours -- and calls next in each. This is that
  -- shape: if a future version of it (or anything like it) stops deferring,
  -- these are the assertions that go red.
  local t = H.load()
  t.options.enabled = true
  local peer = { composeSawHandled = nil, hudDrewAfterUs = false, pointerForwarded = 0 }

  t.bus:wrap("render.compose", function(next, renderer, ctx)
    local handled = next(renderer, ctx)
    peer.composeSawHandled = handled
    return handled
  end, 100, "peer")

  t.bus:wrap("render.hud", function(next, game, viewport)
    next(game, viewport)
    peer.hudDrewAfterUs = true
  end, 100, "peer")

  t.bus:wrap("input.pointer", function(next, game, ev)
    peer.pointerForwarded = peer.pointerForwarded + 1
    return next(game, ev)
  end, 100, "peer")

  t.state.hudMode = "full"
  local took = t.compose(H.composeCtx(800, 600))
  ok(took == true and peer.composeSawHandled == true,
     "our takeover reaches an outer compose wrapper as handled = true")

  t.hud(H.viewport(800, 600))
  ok(peer.hudDrewAfterUs, "an outer HUD wrapper still draws over ours")
  ok(t.area("shrink") ~= nil, "our tap targets survive the outer wrappers")

  ok(t.tap("shrink") and t.state.hudMode == "normal",
     "a tap forwarded by a peer still works the chip")
  ok(peer.pointerForwarded >= 2, "the peer saw the pointer events first")

  -- a peer that claims the window (its own takeover) must not make us throw
  t.state.hudMode = "full"
  t.bus:wrap("render.compose", function() return true end, 200, "greedy-peer")
  run("a peer taking the window over first is survivable", function()
    t.compose(H.composeCtx(800, 600))
    t.hud(H.viewport(800, 600))
  end)
end

-- --------------------------------------------------------------- walk --

section("walk shuffle")
do
  local t = H.load()
  t.options.enabled = true
  local g = H.game(1)

  t.step(g)
  ok(t.holds == 1, "hunting holds a direction")

  -- a step that lands flips the direction exactly once
  t.cell = { x = 3, y = 5 }
  t.step(g)
  t.step(g)
  ok(t.holds == 1, "after a completed step it holds the other direction")

  -- a menu on top must stop the walking (the options-menu-scrolls-itself bug)
  t.emit("screen.pushed", { state = { isOverworld = false } })
  t.step(g)
  ok(t.holds == 0, "a menu on top releases the held direction")
  -- Closing it does NOT press again immediately: the interrupted hold is
  -- still owed an answer about whether its step landed, and crediting that
  -- step is what stops the shuffle repeating a direction and drifting off
  -- its two tiles (the v0.3.0 fix). The step did land here, so the next
  -- tick credits it and the one after presses the other way.
  t.emit("screen.popped", { state = { isOverworld = false } })
  t.step(g)
  ok(t.holds == 0, "an interrupted step is confirmed before pressing again")
  t.cell = { x = 3, y = 6 }
  t.step(g)
  t.step(g)
  ok(t.holds == 1, "once the step is credited the walk resumes")

  -- and a hold that genuinely cannot move gives up under a second
  local blockedAt = { x = t.cell.x, y = t.cell.y }
  t.cell = blockedAt
  t.step(g, 1.0)
  t.step(g)
  ok(t.holds == 1, "a hold that never lands times out and flips anyway")

  -- fleeing mashes A rather than holding it
  local before = #t.taps
  t.emit("battle.started", H.wildEvent(H.COMMON_DVS, 1))
  t.step(g); t.step(g)
  ok(#t.taps >= before + 2, "each tick of a flee queues its own A press")
  t.emit("battle.ended", {})
end

print(("\n%d checks, %s"):format(checks,
  failures == 0 and "all good" or (failures .. " FAILED")))
os.exit(failures == 0 and 0 or 1)
