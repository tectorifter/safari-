return function(mod)
  local DATA = mod.exports.spSkillData
  assert(type(DATA) == "table", "safari-plus: data/skills.lua missing")
  local M = {}
  M.BALL_START = DATA.BALL_START
  M.BALL_HARD = DATA.BALL_HARD
  M.BALL_STEP = DATA.BALL_STEP
  M.SKILL_DEF = DATA.SKILL_DEF
  M.SKILL_ORDER = DATA.SKILL_ORDER
  M.XP_TABLE = DATA.XP_TABLE
  M.GAIN = DATA.GAIN
  M.LEGENDS = DATA.LEGENDS
  function M.require(path)
    local ok, v = pcall(require, path)
    if ok then return v end
    return nil
  end
  function M.claim(tbl, flag)
    assert(type(tbl) == "table", "safari-plus: claim on missing module")
    if tbl[flag] then return false end
    tbl[flag] = true
    return true
  end
  function M.numId(id)
    local ItemsData = M.require("src.core.game3.items_data")
    if type(ItemsData) == "table" and type(ItemsData.toNumericId) == "function" then
      local ok, n = pcall(ItemsData.toNumericId, id)
      if ok and n ~= nil then return tonumber(n) end
    end
    return tonumber(id)
  end
  function M.candyDef(id)
    local CD = M.candyData
    if type(CD) ~= "table" then return nil end
    return CD.BY_ID[M.numId(id)]
  end
  function M.once(fn)
    local ran = false
    return function(...)
      if ran then return end
      ran = true
      if type(fn) == "function" then return fn(...) end
    end
  end
  function M.try(fn, ...)
    if type(fn) ~= "function" then return false, nil end
    local ok, v = pcall(fn, ...)
    if ok then return true, v end
    return false, nil
  end
  function M.opt(key, dflt)
    local o = mod.options
    if type(o) == "table" and type(o.get) == "function" then
      local ok, v = pcall(o.get, o, key)
      if ok and v ~= nil then return v end
    end
    return dflt
  end
  function M.speciesId(species)
    local sid = tonumber(species)
    if sid ~= nil then return sid end
    if type(species) ~= "string" then return nil end
    local Pokemon = M.require("src.core.game3.pokemon")
    if Pokemon and type(Pokemon.speciesFromName) == "function" then
      local ok, id = pcall(Pokemon.speciesFromName, species)
      if ok then return tonumber(id) end
    end
    return nil
  end
  function M.isLegendary(species)
    local sid = M.speciesId(species)
    if sid ~= nil and M.LEGENDS[sid] then return true end
    if sid == nil then return false end
    local nm = nil
    local Pokemon = M.require("src.core.game3.pokemon")
    if Pokemon and type(Pokemon.name) == "function" then
      local ok, v = pcall(Pokemon.name, sid)
      if ok then nm = v end
    end
    if type(nm) == "string" and nm ~= "" then
      return M.LEGENDS[nm:upper():gsub("[^A-Z0-9]", "")] == true
    end
    return false
  end
  function M.isShiny(mon)
    if type(mon) ~= "table" then return false end
    local Pokemon = M.require("src.core.game3.pokemon")
    if Pokemon and type(Pokemon.isShiny) == "function" then
      local ok, v = pcall(Pokemon.isShiny, mon)
      if ok then return v == true end
    end
    return mon.isShiny == true
  end
  function M.chainResult(result)
    if result == "catch" or result == "caught" then return "win" end
    if result == "run" then
      local B = M.require("src.core.game3.battle")
      if B and type(B.getState) == "function" then
        local ok, st = pcall(B.getState)
        if ok and type(st) == "table" and st.endReason == "enemy_fled" then
          return "win"
        end
      end
    end
    return result
  end
  function M.cleanName(mon, species)
    local nm = nil
    local Pokemon = M.require("src.core.game3.pokemon")
    if Pokemon and type(Pokemon.name) == "function" and species ~= nil then
      local ok, v = pcall(Pokemon.name, species)
      if ok then nm = v end
    end
    if type(nm) ~= "string" or nm == "" then
      nm = type(mon) == "table" and mon.name or nil
    end
    if type(nm) ~= "string" then return "" end
    return nm:upper():gsub("[^A-Z0-9]", "")
  end
  function M.on()
    return M.opt("safari", true) == true
  end
  function M.session()
    local R = M.require("src.core.game3.runtime")
    if R and type(R.getSession) == "function" then
      local okS, s = pcall(R.getSession)
      if okS and type(s) == "table" then return s end
    end
    return nil
  end
  function M.saveGet(k, d)
    local sv = mod.save
    if sv and type(sv.get) == "function" then
      local ok, v = pcall(sv.get, sv, k, d)
      if ok then return v end
    end
    return d
  end
  function M.saveSet(k, v)
    local sv = mod.save
    if sv and type(sv.set) == "function" then
      pcall(sv.set, sv, k, v)
    end
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
    local d = M.SKILL_DEF[key]
    return d and d.max or 0
  end
  function M.now()
    local lv = love
    if type(lv) == "table" and type(lv.timer) == "table"
        and type(lv.timer.getTime) == "function" then
      local okT, t = pcall(lv.timer.getTime)
      t = okT and tonumber(t) or nil
      if t ~= nil then return t end
    end
    return os.time()
  end
  function M.scrubState(u, balls, regenAt)
    local c = {}
    for _, key in ipairs(M.SKILL_ORDER) do
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
    local n = math.floor(tonumber(M.opt("exp_yield", 50)) or 50)
    if n < 0 then return 0 end
    if n > 500 then return 500 end
    return n
  end
  local function sync(fromSave)
    local s = M.session()
    local u, b, ra
    if fromSave then
      local gu = M.saveGet("upg", nil)
      local gb = M.saveGet("balls", nil)
      local gra = M.saveGet("regenAt", nil)
      if gu ~= nil or gb ~= nil or gra ~= nil then
        u, b, ra = gu, gb, gra
      else
        u = s and s.safariUpg
        b = s and s.safari and s.safari.balls
        ra = s and s.safariRegenAt
      end
    else
      u = s and s.safariUpg
      b = s and s.safari and s.safari.balls
      ra = s and s.safariRegenAt
    end
    local c, cb, cra = M.scrubState(u, b, ra)
    if s then
      s.safariUpg = c
      s.safari = type(s.safari) == "table" and s.safari or {}
      s.safari.balls = cb
      s.safariRegenAt = cra
    end
    M.saveSet("balls", cb)
    M.saveSet("regenAt", cra)
  end
  function M.persist()
    sync(false)
  end
  function M.pull()
    sync(true)
  end
  function M.level(skill)
    local x = 0
    if type(M.xp) == "function" then x = M.xp(skill) or 0 end
    x = tonumber(x) or 0
    local t = M.XP_TABLE[skill]
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
  function M.inBattle()
    local B = M.require("src.core.game3.battle")
    if B and type(B.isActive) == "function" then
      local ok, active = pcall(B.isActive)
      if ok and active then return true end
    end
    return false
  end
  function M.isTutorial(st)
    if type(st) ~= "table" then return false end
    if st.oldManTutorial or st.pokedude then return true end
    if st.kinds and st.kinds.tutorial == "wally" then return true end
    local Wally = M.require("src.core.game3.battle.tutorial_wally")
    if Wally and type(Wally.active) == "function" then
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
      if type(M.addXp) == "function" then
        M.addXp("regen", grants * M.GAIN.regenTick)
      end
      M.persist()
    end
  end
  M.pull()
  if mod.events and type(mod.events.on) == "function" then
    mod.events:on("save.loaded", function()
      M.pull()
    end)
    mod.events:on("save.writing", function()
      M.persist()
    end)
  end
  if mod.migrations and type(mod.migrations.add) == "function" then
    mod.migrations:add("0.5.0", function(save)
      local id = mod.id or "safari-plus"
      local md = type(save) == "table" and save.modData
      local b = md and md[id]
      if type(b) ~= "table" then return end
      local c, cb, cra = M.scrubState(b.upg, b.balls, b.regenAt)
      b.upg, b.balls, b.regenAt = c, cb, cra
    end)
  end
  mod.exports.safariPlus = M
end
