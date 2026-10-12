return function(mod)
  local SP = mod.exports.safariPlus
  if not SP then return end
  local function scrub(raw)
    local out = {}
    for _, skill in ipairs(SP.SKILL_ORDER) do
      local n = math.floor(tonumber(type(raw) == "table" and raw[skill]) or 0)
      if n < 0 or n ~= n then n = 0 end
      out[skill] = n
    end
    return out
  end
  local function store()
    local s = SP.session()
    if not s then return nil end
    local t = s.safariXp
    if type(t) ~= "table" then t = {} s.safariXp = t end
    return t
  end
  local function persist()
    SP.saveSet("xp", scrub(store()))
  end
  local function gainOf(key, dflt)
    local n = math.floor(tonumber(SP.GAIN[key]) or dflt)
    if n < 0 then return dflt end
    return n
  end
  local function seedFromLegacy()
    local g = SP.saveGet("upg", nil)
    if type(g) ~= "table" then
      local s = SP.session()
      g = s and s.safariUpg
    end
    if type(g) ~= "table" then return end
    local t = store()
    if not t then return end
    for _, skill in ipairs(SP.SKILL_ORDER) do
      local lv = math.floor(tonumber(g[skill]) or 0)
      if lv < 0 or lv ~= lv then lv = 0 end
      local mx = SP.maxOf(skill)
      if lv > mx then lv = mx end
      local tab = SP.XP_TABLE[skill]
      local seeded = tonumber(type(tab) == "table" and tab[lv + 1]) or 0
      if (tonumber(t[skill]) or 0) < seeded then t[skill] = seeded end
    end
    persist()
  end
  local function pull()
    local g = SP.saveGet("xp", nil)
    local clean
    if g ~= nil then
      clean = scrub(g)
    else
      local s = SP.session()
      clean = scrub(s and s.safariXp)
      seedFromLegacy()
      clean = scrub(store())
    end
    local t = store()
    if t then
      for k in pairs(t) do t[k] = nil end
      for k, v in pairs(clean) do t[k] = v end
    end
    SP.saveSet("xp", clean)
  end
  function SP.xp(skill)
    local t = store()
    local n = t and tonumber(t[skill]) or 0
    if n == nil or n < 0 or n ~= n then return 0 end
    return math.floor(n)
  end
  function SP.addXp(skill, amount)
    local n = math.floor(tonumber(amount) or 0)
    if n <= 0 then return 0 end
    local valid = false
    for _, k in ipairs(SP.SKILL_ORDER) do
      if k == skill then valid = true break end
    end
    if not valid then return 0 end
    local t = store()
    if not t then return 0 end
    t[skill] = SP.xp(skill) + n
    persist()
    return n
  end
  local function liveState()
    local B = SP.require("src.core.game3.battle")
    if type(B) == "table" and type(B.getState) == "function" then
      local ok, st = pcall(B.getState)
      if ok and type(st) == "table" then return st end
    end
    return nil
  end
  local function ours(st)
    return type(st) == "table" and st.safari
      and type(st.safariState) == "table"
  end
  local function catchRateOf(species)
    local rate = nil
    local Pokemon = SP.require("src.core.game3.pokemon")
    if Pokemon and type(Pokemon.speciesMeta) == "function" then
      local ok, meta = pcall(Pokemon.speciesMeta, tonumber(species) or species)
      if ok then rate = meta and tonumber(meta.catchRate) end
    end
    if rate == nil or rate < 0 then return 45 end
    if rate > 255 then return 255 end
    return math.floor(rate)
  end
  local function awardCatch(species, firstTime, shiny)
    local rate = catchRateOf(species)
    local xp = 20 + math.floor((255 - rate) / 2)
    if SP.isLegendary(species) then
      if firstTime then
        xp = xp * 30
      else
        xp = xp * 5
      end
    end
    if shiny then xp = xp + gainOf("shinyCatch", 1000) end
    return SP.addXp("catch", xp)
  end
  local ballFails = 0
  local function capAward()
    local first = gainOf("capFirst", 8)
    local step = gainOf("capFail", 1)
    local floorXp = gainOf("capMin", 4)
    local v = first - ballFails * step
    if v < floorXp then v = floorXp end
    if v < 0 then v = 0 end
    return SP.addXp("cap", v)
  end
  local Catching = SP.require("src.core.game3.battle.catching")
  if type(Catching) == "table" and type(Catching.storeCaught) == "function"
      and SP.claim(Catching, "__spSafariXpWrapped") then
    local nativeStore = Catching.storeCaught
    Catching.storeCaught = function(session, foe, ballId, opts, ...)
      local res = nativeStore(session, foe, ballId, opts, ...)
      if type(res) == "table" and res.success then
        local st = liveState()
        if not (st and SP.isTutorial(st)) then
          local mon = res.mon
          local species = type(mon) == "table"
            and (mon.species or mon.speciesId) or nil
          if species == nil and type(foe) == "table" then
            species = foe.species or foe.speciesId
          end
          if species ~= nil then
            local shiny = SP.isShiny(mon)
            if not shiny and type(foe) == "table" then
              shiny = SP.isShiny(foe)
            end
            awardCatch(species, res.firstTimeCaught == true, shiny)
            capAward()
            if res.firstTimeCaught == true then
              SP.addXp("cap", gainOf("capNew", 8))
            end
          end
        end
      end
      return res
    end
  end
  if type(Catching) == "table" and type(Catching.tryCatch) == "function"
      and SP.claim(Catching, "__spXpThrowWrapped") then
    local nativeTry = Catching.tryCatch
    Catching.tryCatch = function(ballId, enemy, st, session, rng, ...)
      local caught, shakes = nativeTry(ballId, enemy, st, session, rng, ...)
      if not caught and tonumber(ballId) == 5 and SP.on() then
        local live = liveState()
        if ours(live) and not SP.isTutorial(live) then
          ballFails = ballFails + 1
        end
      end
      return caught, shakes
    end
  end
  local function ensureRules()
    local Rules = SP.require("src.core.game3.battle.rules")
    if type(Rules) ~= "table" or type(Rules.safari) ~= "table" then return end
    local RS = Rules.safari
    if type(RS.watchStep) == "function" and SP.claim(RS, "__spXpWatchWrapped") then
      local nativeWatch = RS.watchStep
      RS.watchStep = function(sf, ...)
        local reaction = nativeWatch(sf, ...)
        if reaction == "watching" and SP.on() then
          local st = liveState()
          if ours(st) and not SP.isTutorial(st) then
            SP.addXp("like", gainOf("likeWatch", 6))
          end
        end
        return reaction
      end
    end
    if type(RS.throwPokeblock) == "function" and SP.claim(RS, "__spXpBlockWrapped") then
      local nativeBlock = RS.throwPokeblock
      RS.throwPokeblock = function(sf, tables, gain, ...)
        local result = nativeBlock(sf, tables, gain, ...)
        if SP.on() then
          local st = liveState()
          if ours(st) and not SP.isTutorial(st) then
            SP.addXp("like", gainOf("likeBlock", 8))
          end
        end
        return result
      end
    end
  end
  ensureRules()
  pull()
  if mod.events and type(mod.events.on) == "function" then
    mod.events:on("battle.started", function()
      ballFails = 0
      ensureRules()
    end)
    mod.events:on("battle.ended", function(ev)
      ballFails = 0
      if not SP.on() then return end
      local b = type(ev) == "table" and ev.battle or nil
      if not ours(b) then return end
      if SP.isTutorial(b) then return end
      SP.addXp("regen", gainOf("regenEnd", 10))
    end)
    mod.events:on("world.stepped", function()
      if not SP.on() then return end
      if SP.inBattle() then return end
      if SP.stock() >= SP.cap() then return end
      SP.addXp("regen", gainOf("regenStep", 1))
    end)
    mod.events:on("save.loaded", function()
      pull()
    end)
    mod.events:on("save.writing", function()
      persist()
    end)
  end
  mod.log:info("safari-plus: safari xp installed")
end
