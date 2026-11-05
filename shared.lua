return function(mod)
  local M = {}
  M.BALL_START = 10
  M.BALL_HARD = 70
  M.BALL_STEP = 2
  M.UPG = {
    catch = { name = "SAFARI UPG", max = 60 },
    like = { name = "LIKEABLE", max = 30 },
    regen = { name = "BALL RECOVERY", max = 70 },
    cap = { name = "BALL CAP", max = 30 },
  }
  M.XP_TABLE = {
    catch = {
      0, 100, 293, 549, 857, 1212, 1607, 2041, 2511, 3014,
      3548, 4113, 4707, 5329, 5977, 6652, 7352, 8076, 8824, 9596,
      10390, 11206, 12044, 12903, 13782, 14683, 15603, 16543, 17502, 18481,
      19478, 20493, 21527, 22579, 23648, 24735, 25839, 26960, 28097, 29252,
      30422, 31609, 32812, 34031, 35266, 36516, 37781, 39062, 40357, 41668,
      42994, 44334, 45688, 47057, 48441, 49838, 51250, 52675, 54114, 55567,
      57034,
    },
    like = {
      0, 100, 273, 492, 746, 1032, 1344, 1680, 2039, 2419,
      2818, 3236, 3671, 4123, 4591, 5074, 5572, 6083, 6609, 7148,
      7700, 8265, 8841, 9430, 10030, 10642, 11264, 11898, 12542, 13197,
      13862,
    },
    regen = {
      0, 75, 227, 435, 689, 985, 1319, 1687, 2089, 2523,
      2986, 3478, 3997, 4543, 5115, 5712, 6334, 6979, 7647, 8338,
      9051, 9786, 10542, 11319, 12117, 12935, 13773, 14630, 15507, 16402,
      17316, 18249, 19200, 20169, 21156, 22160, 23182, 24221, 25276, 26349,
      27438, 28544, 29666, 30804, 31958, 33128, 34314, 35515, 36732, 37964,
      39211, 40474, 41751, 43043, 44350, 45671, 47007, 48357, 49722, 51100,
      52493, 53900, 55321, 56755, 58204, 59665, 61141, 62630, 64132, 65648,
      67177,
    },
    cap = {
      0, 100, 273, 492, 746, 1032, 1344, 1680, 2039, 2419,
      2818, 3236, 3671, 4123, 4591, 5074, 5572, 6083, 6609, 7148,
      7700, 8265, 8841, 9430, 10030, 10642, 11264, 11898, 12542, 13197,
      13862,
    },
  }
  M.GAIN = {
    likeWatch = 6,
    likeBlock = 8,
    regenStep = 1,
    regenEnd = 10,
    regenOwFail = 1,
    regenOwCatch = 3,
    capFirst = 8,
    capFail = 1,
    capMin = 4,
    capNew = 8,
    capOwCatch = 4,
  }
  M.ORDER = { "catch", "like", "regen", "cap" }
  M.SKILLS = { "catch", "like", "regen", "cap" }
  M.LEGEND_IDS = {
    [144] = true, [145] = true, [146] = true, [150] = true, [151] = true,
    [243] = true, [244] = true, [245] = true, [249] = true, [250] = true,
    [251] = true, [377] = true, [378] = true, [379] = true, [380] = true,
    [381] = true, [382] = true, [383] = true, [384] = true, [385] = true,
    [386] = true,
  }
  M.LEGEND_NAMES = {
    ARTICUNO = true, ZAPDOS = true, MOLTRES = true, MEWTWO = true, MEW = true,
    RAIKOU = true, ENTEI = true, SUICUNE = true, LUGIA = true, HOOH = true,
    CELEBI = true, REGIROCK = true, REGICE = true, REGISTEEL = true,
    LATIAS = true, LATIOS = true, KYOGRE = true, GROUDON = true,
    RAYQUAZA = true, JIRACHI = true, DEOXYS = true,
  }
  local dexLegends = nil
  local dexLegendsCount = -1
  local function dexList()
    local out = nil
    pcall(function()
      local h = mod.find ~= nil and mod.find("national_dex_gen3") or nil
      local xp = type(h) == "table" and h.exports or nil
      if type(xp) == "table" and type(xp.listSpecies) == "function" then
        out = xp.listSpecies()
      end
    end)
    return out
  end
  function M.dexLegends()
    local list = dexList()
    local n = 0
    if type(list) == "table" then n = #list end
    if dexLegends ~= nil and n == dexLegendsCount then return dexLegends end
    dexLegendsCount = n
    dexLegends = { ids = {}, names = {}, nats = {} }
    if type(list) == "table" then
      for _, r in ipairs(list) do
        if type(r) == "table" and (r.legendary or r.mythical) then
          local slot = math.floor(tonumber(r.slot) or 0)
          if slot > 0 then dexLegends.ids[slot] = true end
          if type(r.name) == "string" and r.name ~= "" then
            dexLegends.names[r.name:upper():gsub("[^A-Z0-9]", "")] = true
          end
          local nat = math.floor(tonumber(r.dex) or 0)
          if nat > 0 then dexLegends.nats[nat] = true end
        end
      end
    end
    return dexLegends
  end
  function M.isLegendary(species)
    local sid = tonumber(species)
    if sid == nil and type(species) == "string" then
      pcall(function()
        local Pokemon = require("src.core.game3.pokemon")
        if Pokemon and type(Pokemon.speciesFromName) == "function" then
          sid = Pokemon.speciesFromName(species)
        end
      end)
      sid = tonumber(sid)
    end
    if sid ~= nil and M.LEGEND_IDS[sid] then return true end
    local dx = M.dexLegends()
    if sid ~= nil and dx.ids[sid] then return true end
    if sid ~= nil then
      local nat = nil
      pcall(function()
        local Pokemon = require("src.core.game3.pokemon")
        if Pokemon and type(Pokemon.national) == "function" then
          nat = Pokemon.national(sid)
        end
      end)
      nat = math.floor(tonumber(nat) or 0)
      if nat > 0 and (M.LEGEND_IDS[nat] or dx.nats[nat]) then return true end
    end
    local nm = nil
    pcall(function()
      local Pokemon = require("src.core.game3.pokemon")
      if Pokemon and type(Pokemon.name) == "function" and sid ~= nil then
        nm = Pokemon.name(sid)
      end
    end)
    if type(nm) == "string" and nm ~= "" then
      local key = nm:upper():gsub("[^A-Z0-9]", "")
      return M.LEGEND_NAMES[key] == true or dx.names[key] == true
    end
    return false
  end
  function M.on()
    local ok, v = pcall(function() return mod.options:get("safari") end)
    if not ok or v == nil then return true end
    return v == true
  end
  function M.session()
    local okR, R = pcall(require, "src.core.game3.runtime")
    if okR and R and type(R.getSession) == "function" then
      local okS, s = pcall(R.getSession)
      if okS and type(s) == "table" then return s end
    end
    return nil
  end
  local function saveGet(k, d)
    local v = d
    pcall(function()
      local sv = mod.save
      if sv and type(sv.get) == "function" then v = sv:get(k, d) end
    end)
    return v
  end
  local function saveSet(k, v)
    pcall(function()
      local sv = mod.save
      if sv and type(sv.set) == "function" then sv:set(k, v) end
    end)
  end
  local function cleanNum(v, lo, hi, dflt)
    local n = tonumber(v)
    if n == nil or n ~= n or n == math.huge or n == -math.huge then
      return dflt
    end
    n = math.floor(n)
    if n < lo then return lo end
    if n > hi then return hi end
    return n
  end
  function M.maxOf(key)
    local d = M.UPG[key]
    return d and d.max or 0
  end
  function M.now()
    local t = nil
    pcall(function()
      local lv = love
      if type(lv) == "table" and type(lv.timer) == "table"
          and type(lv.timer.getTime) == "function" then
        t = lv.timer.getTime()
      end
    end)
    t = tonumber(t)
    if t ~= nil then return t end
    return os.time()
  end
  function M.scrubState(u, balls, regenAt)
    local c = {}
    for _, key in ipairs(M.ORDER) do
      c[key] = cleanNum(type(u) == "table" and u[key], 0, M.maxOf(key), 0)
    end
    local cap = math.min(M.BALL_HARD, M.BALL_START + M.BALL_STEP * (c.cap or 0))
    local now = M.now()
    local ra = tonumber(regenAt)
    if ra == nil or ra ~= ra or ra == math.huge or ra == -math.huge then
      ra = now
    end
    if ra < 0 or ra > now + 120 then ra = now end
    return c, cleanNum(balls, 0, cap, M.BALL_START), ra
  end
  function M.cap()
    return math.min(M.BALL_HARD, M.BALL_START + M.BALL_STEP * M.count("cap"))
  end
  function M.yieldPct()
    local v = nil
    pcall(function()
      if mod.options and type(mod.options.get) == "function" then
        v = mod.options:get("exp_yield")
      end
    end)
    local n = tonumber(v)
    if n == nil then return 50 end
    n = math.floor(n)
    if n < 0 then return 0 end
    if n > 500 then return 500 end
    return n
  end
  function M.evTotalCap()
    if M.opt("ev_1512", false) == true then return 1512 end
    return 510
  end
  function M.persist()
    local s = M.session()
    local u = s and s.safariUpg
    local b = s and s.safari and s.safari.balls
    local c, cb, cra = M.scrubState(u, b, s and s.safariRegenAt)
    if s then
      s.safariUpg = c
      s.safari = type(s.safari) == "table" and s.safari or {}
      s.safari.balls = cb
      s.safariRegenAt = cra
    end
    saveSet("balls", cb)
    saveSet("regenAt", cra)
  end
  function M.pull()
    local s = M.session()
    local gu = saveGet("upg", nil)
    local gb = saveGet("balls", nil)
    local gra = saveGet("regenAt", nil)
    local c, cb, cra
    if gu ~= nil or gb ~= nil or gra ~= nil then
      c, cb, cra = M.scrubState(gu, gb, gra)
    else
      c, cb, cra = M.scrubState(s and s.safariUpg,
        s and s.safari and s.safari.balls, s and s.safariRegenAt)
    end
    if s then
      s.safariUpg = c
      s.safari = type(s.safari) == "table" and s.safari or {}
      s.safari.balls = cb
      s.safariRegenAt = cra
    end
    saveSet("balls", cb)
    saveSet("regenAt", cra)
  end
  function M.level(skill)
    local x = 0
    if type(M.xp) == "function" then x = M.xp(skill) or 0 end
    x = tonumber(x) or 0
    local t = type(M.XP_TABLE) == "table" and M.XP_TABLE[skill]
    local lv = 0
    if type(t) == "table" then
      for i = 1, #t do
        if x >= (tonumber(t[i]) or math.huge) then lv = i - 1 else break end
      end
    end
    if lv < 0 or lv ~= lv then return 0 end
    local mx = M.maxOf(skill)
    if lv > mx then return mx end
    return lv
  end
  function M.count(key)
    if type(M.xp) == "function" then return M.level(key) end
    local s = M.session()
    local u = s and s.safariUpg
    return cleanNum(type(u) == "table" and u[key], 0, M.maxOf(key), 0)
  end
  function M.regenInterval()
    return math.max(5, 12 - 0.1 * M.count("regen"))
  end
  function M.catchBonus()
    return 0.35 * M.count("catch")
  end
  function M.likeCut()
    return 0.1 * M.count("like")
  end
  function M.likeValue()
    return math.min(4, 1 + 0.1 * M.count("like"))
  end
  function M.ensureStock()
    local s = M.session()
    if not s then return end
    s.safari = type(s.safari) == "table" and s.safari or {}
    if tonumber(s.safari.balls) == nil then s.safari.balls = M.BALL_START end
    M.persist()
  end
  function M.stock()
    local s = M.session()
    if not s then return M.BALL_START end
    local b = s.safari and s.safari.balls
    return cleanNum(b, 0, M.cap(), M.BALL_START)
  end
  function M.setStock(n)
    local s = M.session()
    local v = cleanNum(n, 0, M.cap(), 0)
    if s then
      s.safari = type(s.safari) == "table" and s.safari or {}
      s.safari.balls = v
    end
    M.persist()
    return v
  end
  M.BALL_DEFAULT = 5
  function M.equippedBall()
    local s = M.session()
    local v = math.floor(tonumber(s and s.safariBall)
      or tonumber(M.saveGet("equippedBall", 5)) or 5)
    if v < 1 or v > 12 then v = 5 end
    if v ~= 5 then
      local has = false
      pcall(function()
        local Bag = M.require("src.core.game3.bag")
        local bag = s ~= nil and s.bag or nil
        if type(Bag) == "table" and type(Bag.get) == "function"
            and type(bag) == "table" then
          local ok, q = pcall(Bag.get, bag, v)
          if ok and math.floor(tonumber(q) or 0) > 0 then has = true end
        end
      end)
      if not has then v = 5 end
    end
    return v
  end
  function M.setEquippedBall(id)
    local v = math.floor(tonumber(id) or 5)
    if v < 1 or v > 12 then v = 5 end
    local s = M.session()
    if s ~= nil then s.safariBall = v end
    M.saveSet("equippedBall", v)
    return v
  end
  function M.inBattle()
    local okB, B = pcall(require, "src.core.game3.battle")
    if okB and B and type(B.isActive) == "function" then
      local ok, active = pcall(B.isActive)
      if ok and active then return true end
    end
    return false
  end
  function M.isTutorial(st)
    if type(st) ~= "table" then return false end
    if st.oldManTutorial or st.pokedude then return true end
    if st.kinds and st.kinds.tutorial == "wally" then return true end
    local okW, Wally = pcall(require, "src.core.game3.battle.tutorial_wally")
    if okW and Wally and type(Wally.active) == "function" then
      local ok, v = pcall(Wally.active, st)
      if ok and v then return true end
    end
    return false
  end
  function M.freeze()
    local s = M.session()
    if not s then return end
    if s.safariFrozenAt == nil then s.safariFrozenAt = M.now() end
  end
  function M.thaw()
    local s = M.session()
    if not s then return end
    local f = tonumber(s.safariFrozenAt)
    s.safariFrozenAt = nil
    if not f then return end
    local now = M.now()
    local last = tonumber(s.safariRegenAt)
    if last == nil then
      s.safariRegenAt = now
      M.persist()
      return
    end
    s.safariRegenAt = math.min(now, last + math.max(0, now - f))
    M.persist()
  end
  function M.tick()
    if M.inBattle() then return end
    local s = M.session()
    if not s then return end
    s.safari = type(s.safari) == "table" and s.safari or {}
    local now = M.now()
    local cap = M.cap()
    if cleanNum(s.safari.balls, 0, cap, 0) >= cap then
      s.safariRegenAt = now
      return
    end
    local last = tonumber(s.safariRegenAt) or now
    if now <= last then
      s.safariRegenAt = now
      M.persist()
      return
    end
    local grants = math.floor((now - last) / M.regenInterval())
    if grants > 0 then
      grants = math.min(grants, cap)
      s.safari.balls = math.min(cap,
        cleanNum(s.safari.balls, 0, cap, 0) + grants)
      s.safariRegenAt = last + grants * M.regenInterval()
      M.persist()
    end
  end
  function M.require(name)
    if type(name) ~= "string" then return nil end
    local ok, v = pcall(require, name)
    if not ok then return nil end
    return v
  end
  function M.try(fn, ...)
    if type(fn) ~= "function" then return false end
    return pcall(fn, ...)
  end
  function M.claim(tbl, key)
    if type(tbl) ~= "table" or type(key) ~= "string" then return false end
    if tbl[key] == true then return false end
    tbl[key] = true
    return true
  end
  function M.once(fn)
    local ran = false
    return function(...)
      if ran then return end
      ran = true
      if type(fn) == "function" then return fn(...) end
    end
  end
  function M.opt(key, dflt)
    local v = nil
    local ok = pcall(function()
      if mod.options and type(mod.options.get) == "function" then
        v = mod.options:get(key)
      end
    end)
    if not ok or v == nil then return dflt end
    return v
  end
  function M.numId(id)
    if type(id) == "table" then id = id.id end
    local ItemsData = M.require("src.core.game3.items_data")
    if type(ItemsData) == "table"
        and type(ItemsData.toNumericId) == "function" then
      local ok, n = pcall(ItemsData.toNumericId, id)
      if ok and n ~= nil then return tonumber(n) end
    end
    return tonumber(id)
  end
  M.saveGet = saveGet
  M.saveSet = saveSet
  function M.candyDef(id)
    local n = M.numId(id)
    if n == nil then return nil end
    local CD = M.candyData
    if type(CD) == "table" and type(CD.BY_ID) == "table" then
      local def = CD.BY_ID[n]
      if def ~= nil then return def end
    end
    if type(M.speciesDef) == "function" then
      local ok, def = pcall(M.speciesDef, n - 9500)
      if ok and type(def) == "table" then return def end
    end
    return nil
  end
  function M.cleanName(mon, species)
    local nm = nil
    local Pokemon = M.require("src.core.game3.pokemon")
    if Pokemon and type(Pokemon.name) == "function" and species ~= nil then
      local ok, v = pcall(Pokemon.name, species)
      if ok and type(v) == "string" and v ~= "" then nm = v end
    end
    if type(nm) ~= "string" or nm == "" then
      nm = type(mon) == "table" and mon.name or nil
    end
    if type(nm) ~= "string" then return "" end
    return nm:upper():gsub("[^A-Z0-9]", "")
  end
  function M.isShiny(mon)
    if type(mon) ~= "table" then return false end
    if mon.shiny == true or mon.isShiny == true then return true end
    local sv = mon.shininess
    if sv == true or tonumber(sv) == 1 then return true end
    if mon.dvs ~= nil then
      local ok, Stats = pcall(require, "src.pokemon.Stats")
      if ok and type(Stats) == "table"
          and type(Stats.isShiny) == "function" then
        local okS, v = pcall(Stats.isShiny, mon.dvs)
        if okS and v then return true end
      end
    end
    return false
  end
  -- Encounter-chain reasons: the wild mon fleeing keeps the chain
  -- (mapped to a win in chainResult), while the player's own run,
  -- forced out-of-balls end and losses still break it. Reason strings
  -- are engine-defined (decomp-outcome naming, same family as the
  -- mod's own "no_safari_balls"), matched case-insensitively.
  M.FLEE_REASONS = {
    mon_fled = true, fled = true, flee = true,
    enemy_fled = true, foe_fled = true, wild_fled = true,
    escaped = true, escape = true,
  }
  M.CHAIN_QUIET = {
    win = true, won = true, victory = true, winner = true,
    caught = true, catch = true,
    run = true, ran = true,
    lose = true, lost = true, defeat = true,
    no_safari_balls = true,
  }
  M.chainFled = false
  function M.isFleeReason(reason)
    if type(reason) ~= "string" then return false end
    return M.FLEE_REASONS[reason:lower()] == true
  end
  function M.isChainQuiet(reason)
    if type(reason) ~= "string" then return true end
    if M.FLEE_REASONS[reason:lower()] == true then return true end
    return M.CHAIN_QUIET[reason:lower()] == true
  end
  -- Live endReason read for chainResult: done may run before
  -- battle.ended, while the battle state is still up.
  function M.liveEndReason()
    local B = M.require("src.core.game3.battle")
    if type(B) == "table" and type(B.getState) == "function" then
      local ok, st = pcall(B.getState)
      if ok and type(st) == "table"
          and type(st.endReason) == "string" then
        return st.endReason
      end
    end
    return nil
  end
  function M.chainResult(result)
    -- A duplicate catch exchanged for candy still counts as winning
    -- the wild battle: the conversion rebuilds the catch result (the
    -- mon leaves the party for candy), so the native result reaching
    -- the encounter chain is no longer a win and the chain breaks.
    -- Likewise a fled wild mon keeps the chain: the flee endReason
    -- (snapshot at battle.ended, or read live here when done runs
    -- first) maps to a win too. Player runs, forced out-of-balls
    -- ends and losses pass through untouched and still break it.
    -- This is the funnel safari_force's battle_bridge done-wrapper
    -- passes every outgoing safari-battle result through, so mapping
    -- here covers scripts (check_battle_result "win") and any other
    -- done-consumer. Non-converted, non-fled battles pass through
    -- untouched.
    if result ~= "win" then
      local CF = M.candyFlow
      if type(CF) == "table"
          and type(CF.wasConverted) == "function" then
        local ok, conv = pcall(CF.wasConverted)
        if ok and conv == true then return "win" end
      end
      if M.isFleeReason(M.liveEndReason()) or M.chainFled then
        return "win"
      end
    end
    return result
  end
  function M.isUpgId(id)
    return false
  end
  function M.keyOf(id)
    return nil
  end
  function M.addLevels(key, n)
    return 0
  end
  function M.price(key)
    return 0
  end
  function M.refreshMeta(key)
  end
  M.pull()
  if mod.events and type(mod.events.on) == "function" then
    mod.events:on("save.loaded", function()
      pcall(M.pull)
    end)
    mod.events:on("save.writing", function()
      pcall(M.persist)
    end)
  end
  if mod.migrations and type(mod.migrations.add) == "function" then
    pcall(function()
      mod.migrations:add("0.5.0", function(save)
        local id = mod.id or "safari-plus"
        local md = type(save) == "table" and save.modData
        local b = md and md[id]
        if type(b) ~= "table" then return end
        local c, cb, cra = M.scrubState(b.upg, b.balls, b.regenAt)
        b.upg, b.balls, b.regenAt = c, cb, cra
      end)
    end)
  end
  mod.exports.safariPlus = M
end
