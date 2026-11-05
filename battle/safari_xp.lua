return function(mod)
  local SP = mod.exports.safariPlus
  if not SP then return end
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
  local function scrub(raw)
    local out = {}
    for _, skill in ipairs(SP.SKILLS) do
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
    saveSet("xp", scrub(store()))
  end
  local function gainOf(key, dflt)
    local n = tonumber(type(SP.GAIN) == "table" and SP.GAIN[key])
    if n == nil or n < 0 or n ~= n then return dflt end
    return math.floor(n)
  end
  local function seedFromLegacy()
    local g = saveGet("upg", nil)
    if type(g) ~= "table" then
      local s = SP.session()
      g = s and s.safariUpg
    end
    if type(g) ~= "table" then return end
    local t = store()
    if not t then return end
    for _, skill in ipairs(SP.SKILLS) do
      local lv = math.floor(tonumber(g[skill]) or 0)
      if lv < 0 or lv ~= lv then lv = 0 end
      local mx = SP.maxOf(skill)
      if lv > mx then lv = mx end
      local tab = type(SP.XP_TABLE) == "table" and SP.XP_TABLE[skill]
      local seeded = tonumber(type(tab) == "table" and tab[lv + 1]) or 0
      if (tonumber(t[skill]) or 0) < seeded then t[skill] = seeded end
    end
    persist()
  end
  local function pull()
    local g = saveGet("xp", nil)
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
    saveSet("xp", clean)
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
    for _, k in ipairs(SP.SKILLS) do
      if k == skill then valid = true break end
    end
    if not valid then return 0 end
    local t = store()
    if not t then return 0 end
    t[skill] = SP.xp(skill) + n
    persist()
    pcall(function()
      if type(SP.playerAddXp) == "function" then
        local pay = n * 100
        local lv = 40
        pcall(function()
          if type(SP.playerLevel) == "function" then
            lv = SP.playerLevel()
          end
        end)
        if math.floor(tonumber(lv) or 0) < 40 then
          pay = math.floor(pay / 2)
        end
        SP.playerAddXp(pay)
      end
    end)
    return n
  end
  local function liveState()
    local okB, B = pcall(require, "src.core.game3.battle")
    if okB and B and type(B.getState) == "function" then
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
    pcall(function()
      local Pokemon = require("src.core.game3.pokemon")
      if Pokemon and type(Pokemon.speciesMeta) == "function" then
        local meta = Pokemon.speciesMeta(tonumber(species) or species)
        rate = meta and tonumber(meta.catchRate)
      end
    end)
    if rate == nil or rate < 0 then return 45 end
    if rate > 255 then return 255 end
    return math.floor(rate)
  end
  local function awardCatch(species, firstTime)
    local rate = catchRateOf(species)
    local xp = 20 + math.floor((255 - rate) / 2)
    if SP.isLegendary(species) then
      if firstTime then
        xp = xp * 30
      else
        xp = xp * 5
      end
    end
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
  local okC, Catching = pcall(require, "src.core.game3.battle.catching")
  if okC and Catching and type(Catching.storeCaught) == "function"
      and not Catching.__spSafariXpWrapped then
    Catching.__spSafariXpWrapped = true
    local nativeStore = Catching.storeCaught
    Catching.storeCaught = function(session, foe, ballId, opts, ...)
      local res = nativeStore(session, foe, ballId, opts, ...)
      pcall(function()
        if not (type(res) == "table" and res.success) then return end
        local st = liveState()
        if st and SP.isTutorial(st) then return end
        local mon = res.mon
        local species = type(mon) == "table"
          and (mon.species or mon.speciesId) or nil
        if species == nil and type(foe) == "table" then
          species = foe.species or foe.speciesId
        end
        if species == nil then return end
        awardCatch(species, res.firstTimeCaught == true)
        if type(SP.playerNoteCatch) == "function" then
          pcall(SP.playerNoteCatch, species, res.firstTimeCaught == true)
        end
        if SP.owFlatCap == true then
          SP.addXp("cap", gainOf("capOwCatch", 4))
        else
          capAward()
          if res.firstTimeCaught == true then
            SP.addXp("cap", gainOf("capNew", 8))
          end
        end
      end)
      return res
    end
  end
  if okC and Catching and type(Catching.tryCatch) == "function"
      and not Catching.__spXpThrowWrapped then
    Catching.__spXpThrowWrapped = true
    local nativeTry = Catching.tryCatch
    Catching.tryCatch = function(ballId, enemy, st, session, rng, ...)
      local caught, shakes = nativeTry(ballId, enemy, st, session, rng, ...)
      pcall(function()
        if caught then return end
        if tonumber(ballId) ~= 5 then return end
        if not SP.on() then return end
        local live = liveState()
        if not ours(live) then return end
        if SP.isTutorial(live) then return end
        ballFails = ballFails + 1
      end)
      return caught, shakes
    end
  end
  local function ensureRules()
    local okR, Rules = pcall(require, "src.core.game3.battle.rules")
    if not (okR and Rules and type(Rules.safari) == "table") then return end
    local RS = Rules.safari
    if type(RS.watchStep) == "function" and not RS.__spXpWatchWrapped then
      RS.__spXpWatchWrapped = true
      local nativeWatch = RS.watchStep
      RS.watchStep = function(sf, ...)
        local reaction = nativeWatch(sf, ...)
        if reaction == "watching" then
          pcall(function()
            if not SP.on() then return end
            local st = liveState()
            if not ours(st) then return end
            if SP.isTutorial(st) then return end
            SP.addXp("like", gainOf("likeWatch", 6))
          end)
        end
        return reaction
      end
    end
    if type(RS.throwPokeblock) == "function" and not RS.__spXpBlockWrapped then
      RS.__spXpBlockWrapped = true
      local nativeBlock = RS.throwPokeblock
      RS.throwPokeblock = function(sf, tables, gain, ...)
        local result = nativeBlock(sf, tables, gain, ...)
        pcall(function()
          if not SP.on() then return end
          local st = liveState()
          if not ours(st) then return end
          if SP.isTutorial(st) then return end
          SP.addXp("like", gainOf("likeBlock", 8))
        end)
        return result
      end
    end
  end
  ensureRules()
  pull()
  if mod.events and type(mod.events.on) == "function" then
    mod.events:on("battle.started", function()
      ballFails = 0
      pcall(ensureRules)
    end)
    mod.events:on("battle.ended", function(ev)
      pcall(function()
        ballFails = 0
        if not SP.on() then return end
        local b = type(ev) == "table" and ev.battle or nil
        if not ours(b) then return end
        if SP.isTutorial(b) then return end
        SP.addXp("regen", gainOf("regenEnd", 10))
      end)
    end)
    mod.events:on("world.stepped", function()
      pcall(function()
        if not SP.on() then return end
        if SP.inBattle() then return end
        if SP.stock() >= SP.cap() then return end
        SP.addXp("regen", gainOf("regenStep", 1))
      end)
    end)
    mod.events:on("save.loaded", function()
      pcall(pull)
    end)
    mod.events:on("save.writing", function()
      pcall(persist)
    end)
  end
  mod.log:info("safari-plus: safari xp installed")
end
