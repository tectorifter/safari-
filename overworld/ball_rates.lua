return function(mod)
  local SP = mod.exports.safariPlus
  if not SP then return end
  local BALL_SAFARI = 5
  local WATER = 11
  local BUG = 7
  local CPM_LO = 0.5940
  local CPM_HI = 0.8950
  local LVL_LO = 1
  local LVL_HI = 70
  local TIMER_BASE = 0.1
  local TIMER_TOP = 4
  local TIMER_DEFAULT_MAX = 16
  local BALL_STATIC = { [2] = 2, [3] = 1.5, [4] = 1, [11] = 1, [12] = 1 }
  function SP.cpmForLevel(lvl)
    local l = math.floor(tonumber(lvl) or LVL_LO)
    if l < LVL_LO then l = LVL_LO end
    if l > LVL_HI then l = LVL_HI end
    return CPM_LO + (CPM_HI - CPM_LO) * (l - LVL_LO) / (LVL_HI - LVL_LO)
  end
  function SP.distMult(d)
    local n = math.floor(tonumber(d) or 3)
    if n <= 1 then return 2 end
    if n == 2 then return 1.5 end
    return 1.2
  end
  function SP.setBerryMult(mult, ttlSec)
    local m = tonumber(mult)
    if m == nil or not (m > 0) then return SP.clearBerry() end
    local exp = nil
    local ttl = tonumber(ttlSec)
    if ttl ~= nil and ttl > 0 then exp = SP.now() + ttl end
    pcall(function()
      local s = SP.session()
      if type(s) == "table" then s.safariBerry = { m = m, exp = exp } end
    end)
    return m
  end
  function SP.berryMult()
    local s = SP.session()
    local b = type(s) == "table" and s.safariBerry or nil
    local m = type(b) == "table" and tonumber(b.m) or nil
    if m == nil or not (m > 0) then return 1 end
    local exp = type(b) == "table" and tonumber(b.exp) or nil
    if exp ~= nil and SP.now() > exp then
      pcall(function() s.safariBerry = nil end)
      return 1
    end
    return m
  end
  function SP.clearBerry()
    pcall(function()
      local s = SP.session()
      if type(s) == "table" then s.safariBerry = nil end
    end)
    return 1
  end
  local function numField(t, keys)
    if type(t) ~= "table" then return nil end
    for _, k in ipairs(keys) do
      local v = tonumber(t[k])
      if v ~= nil and v == v and v > 0 and v <= 86400 then return v end
    end
    return nil
  end
  function SP.timerSpan(actor, ue)
    local span = nil
    if type(actor) == "table" then
      span = numField(actor, { "maxAge", "maxage", "ttl", "ttlSec",
        "life", "lifetime", "lifespan", "despawnIn", "expireIn",
        "removeIn" })
    end
    if span == nil then
      local c = type(ue) == "table" and ue.C or nil
      span = numField(c, { "OWE_MAX_AGE", "MAX_AGE", "OWE_LIFESPAN",
        "LIFESPAN", "OWE_TTL", "TTL", "DESPAWN", "OWE_DESPAWN" })
    end
    if span == nil or span <= 0.5 then span = TIMER_DEFAULT_MAX end
    return span
  end
  local function speciesTypes(species)
    local t1, t2 = 0, 0
    pcall(function()
      local Pokemon = SP.require("src.core.game3.pokemon")
      if type(Pokemon) == "table"
          and type(Pokemon.types) == "function" then
        local ok, v = pcall(Pokemon.types, species)
        if ok and type(v) == "table" then
          t1 = tonumber(v[1]) or 0
          t2 = tonumber(v[2]) or 0
        end
      end
    end)
    return t1, t2
  end
  local function dexCaught(ctx)
    local hit = false
    pcall(function()
      local Dex = SP.require("src.core.game3.dex")
      local s = ctx.session or SP.session()
      local dex = type(s) == "table" and s.dex or nil
      if type(Dex) == "table" and type(Dex.isCaught) == "function"
          and dex ~= nil then
        local ok, v = pcall(Dex.isCaught, dex, ctx.species)
        if ok and v then hit = true end
      end
    end)
    return hit
  end
  function SP.ballValue(ballId, ctx)
    local bid = math.floor(tonumber(ballId) or 0)
    if bid == 1 then return "auto" end
    local v = BALL_STATIC[bid]
    if v ~= nil then return v end
    ctx = type(ctx) == "table" and ctx or {}
    if bid == 6 then
      local t1, t2 = speciesTypes(ctx.species)
      if t1 == WATER or t2 == WATER or t1 == BUG or t2 == BUG then
        return 3
      end
      return 1
    end
    if bid == 7 then
      if ctx.surfing then return 3.5 end
      return 1
    end
    if bid == 8 then
      local lvl = math.floor(tonumber(ctx.level) or 1)
      if lvl < 40 then return math.max(1, (40 - lvl) / 10) end
      return 1
    end
    if bid == 9 then
      if dexCaught(ctx) then return 3 end
      return 1
    end
    if bid == 10 then
      local age = math.max(0, tonumber(ctx.spawnAge) or 0)
      local span = SP.timerSpan(ctx.actor, ctx.ue)
      local frac = age / math.max(0.5, span - 0.5)
      if frac > 1 then frac = 1 end
      if frac < 0 then frac = 0 end
      return TIMER_BASE + (TIMER_TOP - TIMER_BASE) * frac
    end
    return 1
  end
  function SP.baseCaptureRate(species, session)
    local rate = nil
    pcall(function()
      local Pokemon = SP.require("src.core.game3.pokemon")
      if type(Pokemon) == "table"
          and type(Pokemon.speciesMeta) == "function" then
        local ok, meta = pcall(Pokemon.speciesMeta, species)
        if ok and type(meta) == "table" then
          rate = tonumber(meta.catchRate)
        end
      end
    end)
    if rate == nil or rate < 0 then rate = 45 end
    if rate > 255 then rate = 255 end
    local a = math.floor(rate / 3)
    pcall(function()
      local Catching = SP.require("src.core.game3.battle.catching")
      if type(Catching) == "table"
          and type(Catching.catchOdds) == "function" then
        local foe = { species = species, mon = { hp = 1, maxHp = 1 } }
        local ok, v = pcall(Catching.catchOdds, 4, foe, nil, session)
        if ok then a = math.max(1, math.min(255,
          math.floor(tonumber(v) or a))) end
      end
    end)
    if a < 1 then a = 1 end
    if a > 255 then a = 255 end
    local b = math.floor(1048560 / math.sqrt(math.sqrt(16711680 / a)))
    local p = b / 65535
    return p * p * p
  end
  function SP.customCatch(species, level, ballId, ctx, roll)
    ctx = type(ctx) == "table" and ctx or {}
    local value = SP.ballValue(ballId, ctx)
    if value == "auto" then return true, 4, 1 end
    if ballId == BALL_SAFARI then return false, 0, 0 end
    local cpm = SP.cpmForLevel(level)
    local base = SP.baseCaptureRate(species, ctx.session)
    local x = base / (2 * cpm)
    if x > 1 then x = 1 end
    if x < 0 then x = 0 end
    local modifier = (tonumber(value) or 1)
      * (tonumber(ctx.berry) or SP.berryMult())
      * (tonumber(ctx.dist) or 1)
    if not (modifier > 0) then modifier = 1 end
    local prob = 1 - (1 - x) ^ modifier
    if prob > 1 then prob = 1 end
    if prob < 0 then prob = 0 end
    local doRoll = roll
    if type(doRoll) ~= "function" then
      doRoll = function() return math.random() end
    end
    local s = prob ^ 0.25
    local shakes = 0
    for _ = 1, 4 do
      if doRoll() < s then
        shakes = shakes + 1
      else
        return false, shakes, prob
      end
    end
    return true, 4, prob
  end
  mod.log:info("safari-plus: ball rates installed")
end
