-- Enough of the engine to run this mod's hooks under plain Lua: a hook bus
-- with the real chaining semantics, a stand-in love.graphics that records
-- what was drawn, and the mod facade the loader hands an entry chunk.
--
-- The bus is the part that matters. src/mods/Hooks.lua sorts a chain by
-- priority (highest first) and hands each link a `next` it may decline to
-- call -- which is exactly how a peer mod like Gen1 Modern UI (priority 100
-- on render.compose, render.hud and input.pointer) ends up wrapped around
-- ours. Reimplementing that here is what lets a test assert we still behave
-- with somebody else's wrapper on the outside; a table of one callback per
-- hook could not.

-- Some Lua 5.1 interpreters (certain LuaJIT builds without 5.2 compat
-- enabled) lack table.pack/table.unpack. Polyfilled only when missing, so
-- anything that already has them -- 5.2+, or a 5.2-compat LuaJIT -- is
-- untouched.
if not table.pack then
  table.pack = function(...) return { n = select("#", ...), ... } end
end
if not table.unpack then
  table.unpack = unpack
end

local H = {}

-- ---------------------------------------------------------------- bus --

local Bus = {}
Bus.__index = Bus

function H.newBus()
  return setmetatable({ chains = {} }, Bus)
end

function Bus:wrap(name, callback, priority, owner)
  local chain = self.chains[name] or {}
  self.chains[name] = chain
  chain[#chain + 1] =
    { callback = callback, priority = priority or 0, owner = owner, seq = #chain }
  -- highest priority first; insertion order breaks ties, so a chain is
  -- deterministic the way the engine's sort is in practice
  table.sort(chain, function(a, b)
    if a.priority ~= b.priority then return a.priority > b.priority end
    return a.seq < b.seq
  end)
  return function()
    for i, entry in ipairs(chain) do
      if entry.callback == callback then table.remove(chain, i) break end
    end
  end
end

function Bus:call(name, vanilla, ...)
  local chain = self.chains[name]
  if not chain or #chain == 0 then return vanilla(...) end
  local args = table.pack(...)
  local function run(index, a)
    if index > #chain then return vanilla(table.unpack(a, 1, a.n)) end
    local function nextFn(...)
      local passed = table.pack(...)
      if passed.n == 0 then passed = a end
      return run(index + 1, passed)
    end
    return chain[index].callback(nextFn, table.unpack(a, 1, a.n))
  end
  return run(1, args)
end

-- ------------------------------------------------------------- love --

local function fakeFont(px)
  return {
    px = px,
    getHeight = function(self) return math.floor(self.px * 1.25) end,
    -- a monospace stand-in: width scales with size the way the real font's
    -- advance does, which is the property fitFont solves against
    getWidth = function(self, s) return math.floor(#tostring(s) * self.px * 0.55) end,
  }
end
H.fakeFont = fakeFont

-- Records every draw so a test can assert on layout: what was printed,
-- where, and at what font size.
function H.installLove()
  -- `seq` is a frame-wide draw counter stamped on every recorded print and
  -- rect, so a test can assert one thing was drawn OVER another -- which is
  -- the whole question when a cover has to hide a peer mod's drawing.
  local rec = { prints = {}, rects = {}, draws = 0, fonts = 0, vibrates = 0, seq = 0 }
  local current = fakeFont(12)
  local function num(v, what)
    assert(type(v) == "number" and v == v, ("%s is not a number: %s"):format(what, tostring(v)))
    return v
  end
  _G.love = {
    timer = { getTime = function() return rec.clock or 1000 end },
    system = { getOS = function() return "Android" end,
      vibrate = function() rec.vibrates = rec.vibrates + 1 end },
    window = { setDisplaySleepEnabled = function() end },
    getVersion = function() return 11, 4, 0, "Mysterious Mysteries" end,
    graphics = {
      newFont = function(px)
        assert(type(px) == "number" and px >= 1, "bad font size " .. tostring(px))
        rec.fonts = rec.fonts + 1
        return fakeFont(px)
      end,
      getFont = function() return current end,
      setFont = function(f) current = f or current end,
      setColor = function() end,
      setLineWidth = function() end,
      setScissor = function() end,
      setShader = function() end,
      getWidth = function() return 800 end,
      getHeight = function() return 600 end,
      print = function(text, x, y)
        assert(type(text) == "string", "print got " .. type(text))
        rec.seq = rec.seq + 1
        rec.prints[#rec.prints + 1] = {
          text = text, x = num(x, "print x"), y = num(y, "print y"),
          px = current.px, w = current:getWidth(text), h = current:getHeight(),
          seq = rec.seq,
        }
      end,
      rectangle = function(mode, x, y, w, h)
        rec.seq = rec.seq + 1
        rec.rects[#rec.rects + 1] = { mode = mode, x = num(x, "rect x"),
          y = num(y, "rect y"), w = num(w, "rect w"), h = num(h, "rect h"),
          seq = rec.seq }
      end,
      draw = function() rec.draws = rec.draws + 1 end,
    },
  }
  rec.reset = function()
    rec.prints, rec.rects, rec.draws, rec.vibrates, rec.seq = {}, {}, 0, 0, 0
  end
  return rec
end

-- -------------------------------------------------------------- mod --

-- Load main.lua against a fresh mod facade. Returns the handle every test
-- drives the mod through.
function H.load(opts)
  opts = opts or {}
  local bus = H.newBus()
  local t = {
    bus = bus, options = {}, schema = {}, events = {}, taps = {}, holds = 0,
    saved = {}, pushes = {},
  }

  local mod = {
    id = "auto_shiny_hunt",
    options = {
      define = function(_, schema)
        t.schema = schema
        for _, row in ipairs(schema) do
          if t.options[row.key] == nil then t.options[row.key] = row.default end
        end
      end,
      get = function(_, key) return t.options[key] end,
    },
    hooks = {
      wrap = function(_, name, callback, priority)
        return bus:wrap(name, callback, priority, "auto_shiny_hunt")
      end,
    },
    events = {
      on = function(_, name, callback) t.events[name] = callback end,
    },
    input = {
      tap = function(_, _, btn) t.taps[#t.taps + 1] = btn end,
      press = function(_, _, btn)
        t.holds = t.holds + 1
        return { btn = btn }
      end,
      release = function(_, token)
        if token then t.holds = t.holds - 1 end
      end,
    },
    -- mod.world. `current` is the player cell the walk shuffle watches;
    -- `overworld` and `mapOverview` are what FISH mode reads -- a live
    -- OverworldState stand-in whose goFishing records the cast the way the
    -- real one starts it, and the read-only water map the real
    -- WorldAPI:mapOverview returns.
    world = {
      current = function() return t.cell end,
      overworld = function()
        if t.overworldError then error("no overworld", 0) end
        return t.ow
      end,
      mapOverview = function()
        if not t.mapView then return nil, "no overworld" end
        return t.mapView
      end,
    },
    content = { pokemon = {
      get = function(_, id)
        return { name = (opts.speciesName or "MON") .. tostring(id) }
      end,
      -- a small fixed species list, string-or-number ids and all, so a
      -- test can build a picker off it without needing 151 real entries.
      -- `opts.species` overrides it entirely when a test wants specific ids.
      each = function()
        local list = opts.species or {
          { id = 1, name = "MON1", dex = 1 }, { id = 2, name = "MON2", dex = 2 },
          { id = 3, name = "MON3", dex = 3 }, { id = 4, name = "MON4", dex = 4 },
          { id = 5, name = "MON5", dex = 5 }, { id = 6, name = "MON6", dex = 6 },
          { id = 7, name = "MON7", dex = 7 }, { id = 8, name = "MON8", dex = 8 },
          { id = 9, name = "MON9", dex = 9 },
        }
        local i = 0
        return function()
          i = i + 1
          local s = list[i]
          if not s then return nil end
          return s.id, { name = s.name, dex = s.dex }
        end
      end,
    } },
    -- per-mod savefile storage; a test reads t.saved directly to check
    -- round-tripping, or seeds it before H.load to simulate a prior session
    save = {
      get = function(_, key, default)
        local v = t.saved[key]
        if v == nil then return default end
        return v
      end,
      set = function(_, key, value) t.saved[key] = value end,
    },
    -- the engine's screen-push facade. Recorded rather than simulated: this
    -- mod's picker degrades cleanly with no push at all, so a test only
    -- needs to see that push was attempted with a sane id and item list.
    ui = {
      push = function(game, id, ...)
        t.pushes[#t.pushes + 1] = { id = id, game = game, args = table.pack(...) }
      end,
    },
  }

  t.cell = { x = 3, y = 4 }

  -- A screen pushed or popped by identity, the way the engine delivers one.
  -- The identity is the point: a text box pops itself *before* the onDone
  -- that pushes its successor, so a cast's own boxes and a menu the player
  -- opened are told apart by which table came back, never by how deep the
  -- stack got.
  function t.pushScreen(over)
    local screen = over or {}
    t.emit("screen.pushed", { state = screen })
    return screen
  end
  function t.popScreen(screen)
    t.emit("screen.popped", { state = screen })
  end

  -- The fishing spot: a 5x4 map with water along the top row, and the player
  -- standing on land. A fishing test sets t.cell's facing to aim the cast.
  t.casts = {}
  t.ow = {
    isOverworld = true,
    player = { surfing = false },
    -- OverworldState:goFishing pushes its ". . ." box from inside the call,
    -- so a stand-in that returned quietly would hand the mod a stack the
    -- engine would never have shown it. t.box is that box, for the test to
    -- pop when it wants the cast to reach its verdict.
    goFishing = function(_, rod)
      t.casts[#t.casts + 1] = rod
      t.box = t.pushScreen()
      if t.onCast then t.onCast(rod) end
    end,
  }
  t.mapView = {
    mapId = "ROUTE_1", width = 5, height = 4,
    rows = { "~~~~~", ".....", ".....", "....." },
  }

  local chunk = assert(loadfile(opts.entry or "main.lua"))
  chunk()(mod)
  t.mod = mod

  -- The mod keeps its state table private, as it should. A test that wants
  -- the HUD at a given size without first simulating the taps that get there
  -- reaches it through the hook closures; the tap path itself is asserted
  -- separately, against the hit areas the HUD publishes.
  local function findState(fn, seen)
    seen = seen or {}
    if seen[fn] then return nil end
    seen[fn] = true
    for i = 1, 80 do
      local name, value = debug.getupvalue(fn, i)
      if not name then break end
      if type(value) == "table" and value.hudMode ~= nil then return value end
      if type(value) == "function" then
        local found = findState(value, seen)
        if found then return found end
      end
    end
  end
  for _, chain in pairs(bus.chains) do
    for _, entry in ipairs(chain) do
      t.state = t.state or findState(entry.callback)
    end
  end
  assert(t.state, "could not reach the mod's state table")

  -- the tap target the HUD published under `id` on its last drawn frame
  function t.area(id)
    for _, area in ipairs(t.state.hitAreas or {}) do
      if area.id == id then return area end
    end
  end

  -- a full press/release on that target, the way a finger delivers it
  function t.tap(id, pointerId)
    local area = assert(t.area(id), "no tap target named " .. tostring(id))
    local x, y = area.x + area.w / 2, area.y + area.h / 2
    local pressed = t.pointer({ phase = "pressed", id = pointerId or "f1", x = x, y = y })
    local released = t.pointer({ phase = "released", id = pointerId or "f1", x = x, y = y })
    return pressed == true and released == true
  end

  -- ---- the engine-side call sites, named as the engine names them
  function t.step(game, dt)
    return bus:call("input.step", function() end, game, dt or 1 / 60)
  end
  function t.hud(viewport, game)
    return bus:call("render.hud", function() end, game or {}, viewport)
  end
  function t.compose(ctx, renderer)
    return bus:call("render.compose", function() return false end,
      renderer or { blitCanvas = function() end }, ctx)
  end
  function t.pointer(ev, game)
    return bus:call("input.pointer", function() return false end, game or {}, ev)
  end
  function t.overlay(battle)
    return bus:call("battle.overlay", function() end, battle or {})
  end
  -- the engine asks this per state, per frame, before it draws anything
  function t.renderVisible(screen)
    return bus:call("screen.render_visible", function() return true end, screen or {})
  end
  -- render.hud with a peer mod inside our link: whatever it draws lands
  -- between the engine's composite and our own drawing, which is where the
  -- leaked text box came from. `label` is what it prints.
  -- `priority` places the peer outside our link (higher than our 100, the
  -- Gen1 Modern UI case: it draws, then calls next into us) or inside it
  -- (lower: it only draws if we hand the chain on).
  function t.hudWithPeer(viewport, label, priority)
    local drew = false
    local remove = bus:wrap("render.hud", function(nextFn, game, vp)
      drew = true
      love.graphics.print(label or "PEER", 10, 10)
      return nextFn(game, vp)
    end, priority or 200, "peer")
    bus:call("render.hud", function() end, {}, viewport)
    remove()
    return drew
  end
  function t.run(ctx)
    return bus:call("battle.run", function() return "vanilla" end, ctx or {})
  end
  function t.music(vol, ctx)
    return bus:call("music.volume", function(v) return v end, vol, ctx)
  end
  function t.emit(name, payload)
    local handler = t.events[name]
    assert(handler, "no listener for " .. name)
    return handler(payload)
  end

  return t
end

-- ------------------------------------------------------------ fixtures --

H.SHINY_DVS = { attack = 2, defense = 10, speed = 10, special = 10 }
H.COMMON_DVS = { attack = 5, defense = 3, speed = 1, special = 9 }

function H.wildEvent(dvs, species, extra)
  local mon = { species = species or 1, dvs = dvs }
  if extra then for k, v in pairs(extra) do mon[k] = v end end
  return {
    kind = "wild",
    battle = { enemy = { mon = mon }, tryRun = function() end },
  }
end

function H.viewport(w, h)
  return { width = w, height = h, gameX = 0, gameY = 0,
           gameWidth = w, gameHeight = h, scale = 3, dpiX = 1, dpiY = 1 }
end

function H.canvas(w, h)
  return { getWidth = function() return w end, getHeight = function() return h end }
end

function H.composeCtx(w, h, over)
  local ctx = {
    ww = w, wh = h, uiw = 160, uih = 144, dpiX = 1, dpiY = 1,
    zones = {}, worldActive = false, uiCanvas = H.canvas(160, 144),
  }
  if over then for k, v in pairs(over) do ctx[k] = v end end
  return ctx
end

-- `bag` is save.inventory: item id -> count, the shape Bag.add writes and
-- the only part of it FISH mode reads (does the player own this rod).
function H.game(speed, override, bag)
  local g = {
    save = { options = { speed = speed }, inventory = bag or {} },
    speedOverride = override, writes = 0,
  }
  -- game.input, as much of Game.input as the PAUSE gesture reads: which
  -- buttons are physically down. g.hold/g.release drive it the way a player
  -- holding the button would; the mod's own presses never come through here,
  -- which is exactly the asymmetry the gesture relies on.
  local held = {}
  g.input = { isDown = function(_, btn) return held[btn] == true end }
  function g.hold(btn) held[btn] = true end
  function g.release(btn) held[btn] = nil end
  g.writeOptions = function(self) self.writes = self.writes + 1 end
  return g
end

return H
