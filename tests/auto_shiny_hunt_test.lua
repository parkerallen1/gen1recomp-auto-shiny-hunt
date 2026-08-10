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
  ok(cap and cap.default == "10", "SPEED CAP defaults to 10X")
  local highest = 0
  for _, choice in ipairs(cap.choices) do
    highest = math.max(highest, tonumber(choice[2]) or 0)
  end
  ok(highest == 10, "no rung above 10X is offered (highest = " .. highest .. ")")
  -- every rung has to be a real engine GameSpeed level or the engine's clamp
  -- would round our cap to something else the moment it read it
  local LEVELS = { [1] = true, [2] = true, [3] = true, [4] = true, [10] = true,
                   [20] = true, [30] = true, [50] = true, [75] = true,
                   [100] = true, [200] = true }
  local bad
  for _, choice in ipairs(cap.choices) do
    if not LEVELS[tonumber(choice[2])] then bad = choice[1] end
  end
  ok(not bad, "every rung is a real GameSpeed level" .. (bad and (" -- " .. bad) or ""))
end

-- ----------------------------------------------------------- speed cap --

section("speed cap")
do
  local t = H.load()
  t.options.enabled = true

  local g = H.game(200)
  t.step(g)
  ok(g.save.options.speed == 10, "200X is pinned back to 10X while hunting")
  ok(g.writes == 1, "the clamped value is written back")
  t.step(g)
  ok(g.writes == 1, "an already-capped speed is not rewritten every tick")

  -- the cap lasts exactly as long as the hunt: what the player had set has
  -- to come back, or the mod has quietly kept a setting it lowered
  t.options.enabled = false
  t.step(g)
  ok(g.save.options.speed == 200, "hunting off restores the player's GAME SPEED")
  t.options.enabled = true

  g = H.game(4)
  t.step(g)
  ok(g.save.options.speed == 4, "a speed under the cap is left alone")
  t.options.enabled = false
  t.step(g)
  ok(g.save.options.speed == 4, "a speed never capped is not touched on release")
  t.options.enabled = true

  -- the last speed they actually asked for is what comes back
  g = H.game(200)
  t.step(g)
  g.save.options.speed = 100
  t.step(g)
  ok(g.save.options.speed == 10, "a fresh climb is clamped again")
  t.options.enabled = false
  t.step(g)
  ok(g.save.options.speed == 100, "the most recent choice is what is restored")
  t.options.enabled = true

  -- but a value somebody else moved while we held it down wins over ours
  g = H.game(200)
  t.step(g)
  g.save.options.speed = 3
  t.options.enabled = false
  t.step(g)
  ok(g.save.options.speed == 3, "a speed changed by someone else is not stomped")
  t.options.enabled = true

  t.options.speed_cap = "2"
  g = H.game(4)
  t.step(g)
  ok(g.save.options.speed == 2, "a tighter cap is honoured")
  t.options.speed_cap = "10"

  -- the --speed / POKEPORT_SPEED run argument wins over the saved option in
  -- Game:logicSpeed, so the cap has to reach it too -- and give it back
  g = H.game(1, 100)
  t.step(g)
  ok(g.speedOverride == 10, "the run-argument override is capped as well")
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

-- ---------------------------------------------------------------- clock --

section("clock only runs while the hunt does")
do
  local t = H.load()
  local g = H.game(1)
  local function elapsed()
    return t.state.elapsedBase
      + (t.state.resumedAt and (rec.clock - t.state.resumedAt) or 0)
  end
  local function tick(seconds)
    rec.clock = rec.clock + (seconds or 1)
    t.step(g)
  end

  rec.clock = 1000
  t.options.enabled = false
  tick(10)
  ok(elapsed() == 0, "with AUTO HUNT off the clock does not start")

  -- switched on, but the overworld has not been reached yet: this is the boot
  -- and the loading screen, and it must not count
  t.options.enabled = true
  t.cell = nil
  tick(30)
  ok(elapsed() == 0, "the clock does not run before the hunt can walk")

  -- on the overworld and walking. The first tick takes the hold; the clock
  -- starts on the next one, once there is a hold to see.
  t.cell = { x = 3, y = 4 }
  tick(1)
  tick(1)
  local walking = elapsed()
  tick(20)
  ok(elapsed() >= walking + 20, "the clock runs while the shuffle is walking")

  -- a menu on top: not hunting, so it parks
  t.emit("screen.pushed", { state = { isOverworld = false } })
  tick(1)
  local parked = elapsed()
  tick(600)
  ok(elapsed() == parked, "ten minutes in a menu do not reach the clock")
  t.emit("screen.popped", { state = { isOverworld = false } })

  -- our own flee is part of the cycle, so a battle we are resolving counts
  t.cell = { x = 3, y = 5 }
  tick(1); tick(1)
  t.emit("screen.pushed", { state = { isOverworld = false } })
  t.emit("battle.started", H.wildEvent(H.COMMON_DVS, 2))
  local fleeing = elapsed()
  tick(3)
  ok(elapsed() > fleeing, "the clock keeps running through our own flee")
  t.emit("battle.ended", {})
  t.emit("screen.popped", { state = { isOverworld = false } })

  -- a battle counts however long it stays up, shiny included: the fight is
  -- part of the hunt, and a shiny left on screen is its result being held out
  t.cell = { x = 3, y = 6 }
  tick(1); tick(1)
  t.emit("screen.pushed", { state = { isOverworld = false } })
  t.emit("battle.started", H.wildEvent(H.SHINY_DVS, 3))
  tick(1)
  local found = elapsed()
  tick(3600)
  ok(elapsed() >= found + 3600, "the clock keeps running while a shiny sits")

  -- even with a menu stacked over the battle (the party menu, the bag)
  t.emit("screen.pushed", { state = { isOverworld = false } })
  local inMenu = elapsed()
  tick(30)
  ok(elapsed() >= inMenu + 30, "a menu opened inside a battle does not park it")
  t.emit("screen.popped", { state = { isOverworld = false } })

  -- the HUD still calls the shiny out, clock running or not
  t.state.hudMode = "normal"
  rec.reset()
  t.hud(H.viewport(800, 600))
  local tag
  for _, p in ipairs(rec.prints) do
    if p.text:match("^SHINY") or p.text:match("^HUNT") then tag = tag or p.text end
  end
  ok(tag == "SHINY!", "the HUD tag calls out the shiny (got " .. tostring(tag) .. ")")

  -- A battle that ended without its battle.ended must not leave the clock
  -- running forever. Returning to no layers over the overworld clears the
  -- flag; the walk resuming is why the clock legitimately keeps going there,
  -- so prove the flag itself, then park it by taking the walk away.
  t.emit("screen.popped", { state = { isOverworld = false } })
  ok(t.state.inBattle == false,
     "back on the overworld the battle flag clears with no end event")
  t.cell = nil
  t.step(g, 1.0) -- let any pending step confirmation time out
  tick(1)
  local stranded = elapsed()
  tick(60)
  ok(elapsed() == stranded, "with the flag cleared and nowhere to walk it parks")

  -- and a plain menu on the overworld reads as IDLE
  t.emit("battle.ended", {})
  rec.reset()
  t.emit("screen.pushed", { state = { isOverworld = false } })
  tick(2)
  t.hud(H.viewport(800, 600))
  tag = nil
  for _, p in ipairs(rec.prints) do
    if p.text:match("^HUNT") then tag = tag or p.text end
  end
  ok(tag == "HUNT IDLE", "a parked clock reads as IDLE (got " .. tostring(tag) .. ")")
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

-- ------------------------------------------------------------- FOCUS --

section("FOCUS timer options")
do
  local t = H.load()
  local minutes
  for _, row in ipairs(t.schema) do if row.key == "focus_minutes" then minutes = row end end
  ok(minutes and minutes.type == "number", "FOCUS LENGTH is a number option")
  ok(minutes and minutes.default == 25, "FOCUS LENGTH defaults to 25")
  ok(minutes and minutes.min == 5 and minutes.max == 60 and minutes.step == 5,
    "FOCUS LENGTH runs 5 to 60 in steps of 5")
  ok(minutes and (minutes.max - minutes.min) % minutes.step == 0,
    "the range divides evenly by the step")
  ok(minutes and minutes.choices == nil, "FOCUS LENGTH has no choices -- it is a number widget")

  local chipOpt
  for _, row in ipairs(t.schema) do if row.key == "focus_chip" then chipOpt = row end end
  ok(chipOpt and chipOpt.type == "toggle" and chipOpt.default == false,
    "FOCUS TIMER chip is off by default")
end

section("FOCUS countdown is wall-clock")
do
  local t = H.load()
  t.options.enabled = true
  rec.clock = 2000
  t.cell = { x = 1, y = 1 }
  t.state.focus.active = true
  t.state.focus.startedAt = rec.clock
  t.state.focus.lengthSec = 1500 -- 25 minutes

  -- park the hunt clock the ordinary way -- a menu over the overworld,
  -- nothing walking, no battle -- and prove the countdown does not care
  t.emit("screen.pushed", { state = { isOverworld = false } })
  local elapsedBefore = t.state.elapsedBase

  rec.clock = rec.clock + 600
  t.step(H.game(1))

  rec.reset()
  t.hud(H.viewport(800, 600))
  local timer
  for _, p in ipairs(rec.prints) do
    if p.text:match("^%d+:%d%d$") then timer = p.text end
  end
  ok(timer == "15:00", "the countdown fell by the full 600s parked (got " .. tostring(timer) .. ")")
  ok(t.state.elapsedBase == elapsedBefore,
    "the count-up clock stayed parked the whole time -- the two clocks are independent")

  -- run it out entirely while still parked
  rec.clock = rec.clock + 900
  t.step(H.game(1))
  ok(not t.state.focus.active, "the session ends at zero even while parked")
  t.emit("screen.popped", { state = { isOverworld = false } })
end

section("FOCUS hides the screen")
do
  local t = H.load()
  t.state.focus.active = true
  t.state.focus.startedAt = rec.clock or 1000
  t.state.focus.lengthSec = 1500

  for _, wh in ipairs(SIZES) do
    rec.reset()
    local blits = 0
    local took = t.compose(H.composeCtx(wh[1], wh[2]),
      { blitCanvas = function() blits = blits + 1 end })
    ok(took == true, ("FOCUS takes the composite at %dx%d"):format(wh[1], wh[2]))
    ok(rec.draws == 0 and blits == 0,
      ("no game pixel is drawn or blitted at %dx%d"):format(wh[1], wh[2]))
  end

  t.options.show_hud = false
  ok(t.compose(H.composeCtx(800, 600)) == true, "SHOW HUD off still covers the screen")
  t.options.show_hud = true

  t.state.hudMode = "full"
  ok(t.compose(H.composeCtx(800, 600)) == true, "full HUD mode does not leak the PiP either")
end

section("FOCUS mutes music and suppresses the shiny pulse")
do
  local t = H.load()
  t.options.enabled = true
  t.options.flash = true

  ok(t.music(7, {}) == 7, "music plays at its normal volume with no session running")

  t.state.focus.active = true
  t.state.focus.startedAt = rec.clock or 1000
  t.state.focus.lengthSec = 1500
  ok(t.music(7, {}) == 0, "music is muted while a session is live")

  t.state.shinyUp = true
  rec.reset()
  t.overlay({})
  ok(#rec.rects == 0, "the shiny pulse is suppressed while a session is live")

  t.state.focus.active = false
  ok(t.music(7, {}) == 7, "music returns to normal the moment the session ends")
  rec.reset()
  t.overlay({})
  ok(#rec.rects == 1, "the pulse resumes on its own once the session is over")
end

section("FOCUS result blackout")
do
  -- the important one: drive the same scripted timeline twice, once with a
  -- shiny and once with a common, and prove every observable is identical
  local function runTimeline(dvs)
    local t = H.load()
    t.options.enabled = true
    rec.clock = 5000
    t.cell = { x = 2, y = 2 }
    t.state.focus.active = true
    t.state.focus.startedAt = rec.clock
    t.state.focus.lengthSec = 300
    t.step(H.game(1)); t.step(H.game(1)) -- let the shuffle actually start walking

    rec.clock = rec.clock + 30
    t.emit("screen.pushed", { state = { isOverworld = false } })
    t.emit("battle.started", H.wildEvent(dvs, 7))
    t.step(H.game(1))

    rec.reset()
    t.hud(H.viewport(800, 600))
    local transcript = {}
    for _, p in ipairs(rec.prints) do transcript[#transcript + 1] = p.text end

    -- the peek must add nothing that depends on the find either
    t.tap("focus_peek")
    rec.reset()
    t.hud(H.viewport(800, 600))
    for _, p in ipairs(rec.prints) do transcript[#transcript + 1] = "PEEK:" .. p.text end

    return transcript
  end

  rec.vibrates = 0
  local shinyLines = runTimeline(H.SHINY_DVS)
  local shinyVibes = rec.vibrates
  rec.vibrates = 0
  local commonLines = runTimeline(H.COMMON_DVS)
  local commonVibes = rec.vibrates

  ok(#shinyLines == #commonLines and #shinyLines > 0,
    "both runs draw the same number of lines")
  local diff
  for i = 1, math.max(#shinyLines, #commonLines) do
    if shinyLines[i] ~= commonLines[i] then diff = diff or i end
  end
  ok(not diff, "a found shiny and a common draw byte-identical HUD text" ..
    (diff and (' -- line %d: "%s" vs "%s"'):format(
      diff, tostring(shinyLines[diff]), tostring(commonLines[diff])) or ""))

  ok(shinyVibes == 0, "no vibrate reaches the device while a found session is still live")
  ok(commonVibes == 0, "(and obviously not for a common either)")

  -- the literal status tag, not just the substring -- "TARGETS: ANY SHINY"
  -- on the static session card also contains "SHINY" and is not a leak
  local shinyTag, commonTag
  for _, l in ipairs(shinyLines) do if l == "SHINY!" or l == "PEEK:SHINY!" then shinyTag = true end end
  for _, l in ipairs(commonLines) do if l == "SHINY!" or l == "PEEK:SHINY!" then commonTag = true end end
  ok(not shinyTag and not commonTag, "the SHINY! tag never reaches the screen mid-session")
end

section("FOCUS early exit")
do
  local function driveToConfirm(withShiny)
    local t = H.load()
    t.options.enabled = true
    t.state.focus.active = true
    t.state.focus.startedAt = rec.clock or 1000
    t.state.focus.lengthSec = 1500
    local fled = false
    if withShiny then
      t.emit("battle.started", { kind = "wild",
        battle = { enemy = { mon = { species = 3, dvs = H.SHINY_DVS } },
                   tryRun = function() fled = true end } })
    end
    t.hud(H.viewport(800, 600))
    t.tap("focus_end")
    rec.reset()
    t.hud(H.viewport(800, 600))
    local lines = {}
    for _, p in ipairs(rec.prints) do lines[#lines + 1] = p.text end
    return t, lines, function() return fled end
  end

  local _, withLines = driveToConfirm(true)
  local _, withoutLines = driveToConfirm(false)
  ok(#withLines == #withoutLines and #withLines > 0,
    "the confirm panel draws the same number of lines either way")
  local diff
  for i = 1, math.max(#withLines, #withoutLines) do
    if withLines[i] ~= withoutLines[i] then diff = diff or i end
  end
  ok(not diff, "the END warning text is identical whether or not a shiny is waiting")

  local t, _, wasFled = driveToConfirm(true)
  ok(not wasFled(), "nothing runs from the battle on the first tap")
  ok(t.tap("confirm_cancel"), "STAY is reachable")
  ok(t.state.focus.confirm == nil, "STAY dismisses the confirm")
  ok(t.state.focus.active, "STAY leaves the session running")
  ok(not wasFled(), "STAY still has not touched the battle")

  t.hud(H.viewport(800, 600))
  ok(t.tap("focus_end"), "END is reachable again after STAY")
  t.hud(H.viewport(800, 600))
  ok(t.tap("confirm_ok"), "END NOW is reachable")
  ok(wasFled(), "END NOW runs from the open battle")
  ok(not t.state.focus.active, "END NOW ends the session")
  ok(t.state.focus.summary and t.state.focus.summary.reason == "early",
    "the summary records an early ending")

  -- a trainer/Safari battle must never be run from -- exactly the rule
  -- every other flee path in this file already follows
  local t2 = H.load()
  t2.options.enabled = true
  t2.state.focus.active = true
  t2.state.focus.startedAt = rec.clock or 1000
  t2.state.focus.lengthSec = 1500
  local trainerFled = false
  t2.emit("battle.started", { kind = "trainer",
    battle = { enemy = { mon = { species = 3 } },
               tryRun = function() trainerFled = true end } })
  t2.hud(H.viewport(800, 600))
  t2.tap("focus_end")
  t2.hud(H.viewport(800, 600))
  t2.tap("confirm_ok")
  ok(not trainerFled, "END NOW never runs from a trainer battle")
  ok(not t2.state.focus.active, "the session still ends even though nothing was fled")
end

section("FOCUS covers input, not just video")
do
  local t = H.load()
  t.state.focus.active = true
  t.state.focus.startedAt = rec.clock or 1000
  t.state.focus.lengthSec = 1500

  local function probe(id)
    local reached = false
    t.bus:call("input.pointer", function() reached = true; return false end,
      {}, { phase = "pressed", id = id, x = 5, y = 5 })
    return reached
  end

  -- during the END confirm, only the two buttons are registered -- most of
  -- the screen has no target at all, and a miss there must still be
  -- swallowed rather than fall through to the hidden battle underneath
  t.state.focus.confirm = "end"
  t.hud(H.viewport(800, 600))
  ok(not probe("p1"), "a miss during the end-confirm never reaches the game")
  t.state.focus.confirm = nil

  -- likewise the ~4s peek window only registers the END chip
  t.state.focus.peekUntil = (rec.clock or 1000) + 100
  t.hud(H.viewport(800, 600))
  ok(not probe("p2"), "a miss during the peek window never reaches the game")
  t.state.focus.peekUntil = 0

  -- but the game is genuinely visible during the offer/summary states, so
  -- a miss there behaves exactly like a miss on the ordinary HUD: it passes
  -- through, since there is nothing underneath left to protect
  t.state.focus.active = false
  t.state.focus.confirm = "offer"
  t.hud(H.viewport(800, 600))
  ok(probe("p3"), "a miss while only the offer panel is up still reaches the game")
end

section("FOCUS targets")
do
  local t = H.load()
  t.options.enabled = true

  -- empty target set: any shiny is held, matching the pre-targeting behaviour
  local fled = false
  t.emit("battle.started", { kind = "wild",
    battle = { enemy = { mon = { species = 4, dvs = H.SHINY_DVS } },
               tryRun = function() fled = true end } })
  ok(not fled and t.state.shinyUp, "an empty target set still holds any shiny")
  t.emit("battle.ended", {})

  -- a target set that does not include the species: fled, not caught
  t.saved.focus_targets = { "9" }
  t.state.targets = nil -- force isTarget to reload from mod.save
  fled = false
  t.emit("battle.started", { kind = "wild",
    battle = { enemy = { mon = { species = 4, dvs = H.SHINY_DVS } },
               tryRun = function() fled = true end } })
  ok(fled and not t.state.shinyUp, "a shiny outside the target set is fled")
  t.emit("battle.ended", {})

  -- during a session an off-target shiny is also counted as skipped
  t.state.focus.active = true
  t.state.focus.skipped = 0
  fled = false
  t.emit("battle.started", { kind = "wild",
    battle = { enemy = { mon = { species = 4, dvs = H.SHINY_DVS } },
               tryRun = function() fled = true end } })
  ok(fled and t.state.focus.skipped == 1,
    "an off-target shiny during a session is counted as skipped")
  t.emit("battle.ended", {})
  t.state.focus.active = false

  -- with the species in the target set, it is held
  t.saved.focus_targets = { "4" }
  t.state.targets = nil
  fled = false
  t.emit("battle.started", { kind = "wild",
    battle = { enemy = { mon = { species = 4, dvs = H.SHINY_DVS } },
               tryRun = function() fled = true end } })
  ok(not fled and t.state.shinyUp, "a targeted shiny is held")
  t.emit("battle.ended", {})

  -- the picker itself: pushed via mod.ui, toggled in place with no re-push
  -- (onChoose does not pop the screen), and persisted through mod.save
  t.state.targets = nil
  t.saved.focus_targets = nil
  t.options.focus_chip = true

  t.hud(H.viewport(800, 600))
  ok(t.tap("focus_offer"), "the FOCUS chip opens the offer panel")
  ok(t.state.focus.confirm == "offer", "tapping FOCUS offers a session, does not start one")

  t.hud(H.viewport(800, 600))
  ok(t.tap("focus_targets_btn"), "TARGETS is reachable from the offer panel")
  local push = t.pushes[#t.pushes]
  ok(push and push.id == "ListMenu", "opening TARGETS pushes the ListMenu screen by module name")

  local rows, opts = push.args[2], push.args[3]
  local onChoose = opts.onChoose
  local target
  for _, row in ipairs(rows) do if row.id == "4" then target = row end end
  ok(target and target.right == "", "an unpicked species starts unchecked")

  onChoose(target, { items = rows })
  ok(target.right == "X", "picking it checks it in place, no re-push")
  ok(t.saved.focus_targets and #t.saved.focus_targets == 1
     and t.saved.focus_targets[1] == "4",
     "picking a species persists it through mod.save immediately")

  onChoose(target, { items = rows })
  ok(target.right == "", "picking it again unchecks it")
  ok(#t.saved.focus_targets == 0, "unpicking it removes it from the saved list")

  onChoose(target, { items = rows }) -- pick it again before testing CLEAR ALL
  onChoose(rows[2], { items = rows }) -- rows[2] is "-- CLEAR ALL --"
  ok(target.right == "", "CLEAR ALL blanks every row's checkmark in place")
  ok(#t.saved.focus_targets == 0, "CLEAR ALL empties the saved list")
end

section("FOCUS reveal")
do
  local t = H.load()
  t.options.enabled = true
  t.state.hudMode = "normal"
  rec.clock = 9000
  t.state.focus.active = true
  t.state.focus.startedAt = rec.clock
  t.state.focus.lengthSec = 60
  t.state.totalEncounters = 5
  t.state.focus.encAt0 = 5

  t.emit("battle.started", H.wildEvent(H.SHINY_DVS, 6))
  ok(t.state.focus.heldShiny, "the shiny is held going into the reveal")
  t.emit("battle.ended", {})

  ok(t.compose(H.composeCtx(800, 600)) == true, "still covered right up to zero")
  rec.vibrates = 0
  rec.clock = rec.clock + 61
  t.step(H.game(1))

  ok(not t.state.focus.active, "the session has ended")
  ok(t.compose(H.composeCtx(800, 600)) ~= true, "the game is back on screen at zero")
  ok(rec.vibrates == 1, "exactly the one owed alert fires, and only now")

  local summary = t.state.focus.summary
  ok(summary and summary.reason == "done", "the summary records a completed session")
  ok(summary and summary.shiny == true, "the summary reports the find")
  ok(summary and summary.encounters == 1,
    "the summary reports the encounter delta, not the lifetime total")
  ok(t.state.hudMode == "normal", "the HUD mode from before the session is unchanged")

  rec.reset()
  t.hud(H.viewport(800, 600))
  local sawTitle
  for _, p in ipairs(rec.prints) do
    if p.text:match("^FOCUS COMPLETE") then sawTitle = true end
  end
  ok(sawTitle, "the summary panel draws its title")

  ok(t.tap("focus_dismiss"), "OK dismisses the summary")
  ok(t.state.focus.summary == nil, "dismissing clears the summary")
end

section("FOCUS keeps the screen awake while parked")
do
  local original = love.window.setDisplaySleepEnabled
  local calls = 0
  love.window.setDisplaySleepEnabled = function(v) if v == false then calls = calls + 1 end end

  local t = H.load()
  -- AUTO HUNT off: the ordinary KEEP SCREEN AWAKE apply's own early return
  -- never even runs, so a call here can only have come from focusTick
  t.options.enabled = false
  t.state.focus.active = true
  t.state.focus.startedAt = rec.clock or 1000
  t.state.focus.lengthSec = 1500
  t.step(H.game(1))
  ok(calls >= 1, "the device is kept awake during a session even with AUTO HUNT off")

  love.window.setDisplaySleepEnabled = original
end

section("FOCUS HUD draws at every size, on screen")
do
  local t = H.load()
  t.options.enabled = true
  t.state.focus.active = true
  t.state.focus.startedAt = rec.clock or 1000
  t.state.focus.lengthSec = 1500

  local function checkOnScreen(label, W, Ht)
    local off
    for _, p in ipairs(rec.prints) do
      if p.x < 0 or p.y < 0 or p.x + p.w > W + 1 or p.y + p.h > Ht + 1 then
        off = off or ("%q at %d,%d"):format(p.text, p.x, p.y)
      end
    end
    ok(not off, ("%s at %dx%d keeps every line on screen%s")
      :format(label, W, Ht, off and (" -- " .. off) or ""))
  end

  for _, wh in ipairs(SIZES) do
    local W, Ht = wh[1], wh[2]
    rec.reset()
    run(("FOCUS countdown draws at %dx%d"):format(W, Ht), function()
      t.compose(H.composeCtx(W, Ht))
      t.hud(H.viewport(W, Ht))
    end)
    checkOnScreen("FOCUS countdown", W, Ht)
  end

  t.state.focus.confirm = "end"
  for _, wh in ipairs(SIZES) do
    local W, Ht = wh[1], wh[2]
    rec.reset()
    run(("FOCUS end-confirm draws at %dx%d"):format(W, Ht), function() t.hud(H.viewport(W, Ht)) end)
    checkOnScreen("FOCUS end-confirm", W, Ht)
  end
  t.state.focus.confirm = nil

  t.state.focus.active = false
  t.state.focus.confirm = "offer"
  for _, wh in ipairs(SIZES) do
    local W, Ht = wh[1], wh[2]
    rec.reset()
    run(("FOCUS offer draws at %dx%d"):format(W, Ht), function() t.hud(H.viewport(W, Ht)) end)
    checkOnScreen("FOCUS offer", W, Ht)
  end
  t.state.focus.confirm = nil

  t.state.focus.summary =
    { reason = "early", seconds = 42, encounters = 9, shiny = false, skipped = 2 }
  for _, wh in ipairs(SIZES) do
    local W, Ht = wh[1], wh[2]
    rec.reset()
    run(("FOCUS summary draws at %dx%d"):format(W, Ht), function() t.hud(H.viewport(W, Ht)) end)
    checkOnScreen("FOCUS summary", W, Ht)
  end
end

print(("\n%d checks, %s"):format(checks,
  failures == 0 and "all good" or (failures .. " FAILED")))
os.exit(failures == 0 and 0 or 1)
