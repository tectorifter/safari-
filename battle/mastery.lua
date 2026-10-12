return function(mod)
  local SP = mod.exports.safariPlus
  if not SP then return end
  -- Per-species catch counters persist across sessions; wild encounters
  -- of mastered species roll bonus 31 IVs by tier. Species are keyed by
  -- National Dex on the caught form.
  local COUNT_CAP = 300
  local NAT_MAX = 1025
  local STAT_KEYS = { "hp", "atk", "def", "spe", "spa", "spd" }
  local TIERS = {
    { 300, 3, 3 }, { 200, 2, 4 }, { 150, 2, 3 }, { 100, 2, 2 },
    { 75, 2, 1 }, { 50, 1, 2 }, { 30, 1, 1 }, { 15, 0, 2 }, { 5, 0, 1 },
  }
  local function masteryOn()
    return SP.opt("mastery", true) == true
  end
  local function rng(n)
    n = math.max(1, math.floor(tonumber(n) or 1))
    local R = SP.require("src.core.game3.rng")
    if type(R) == "table" and type(R.Random) == "function" then
      local ok, v = pcall(R.Random)
      if ok and tonumber(v) ~= nil then return tonumber(v) % n end
    end
    return math.random(0, n - 1)
  end
  local function natOf(species)
    local id = tonumber(species)
    if id == nil and type(species) == "string" then
      local Pokemon = SP.require("src.core.game3.pokemon")
      if Pokemon and type(Pokemon.speciesFromName) == "function" then
        local ok, v = pcall(Pokemon.speciesFromName, species)
        if ok then id = v end
      end
      id = tonumber(id)
    end
    if id == nil or id < 1 then return nil end
    local nat = nil
    local Pokemon = SP.require("src.core.game3.pokemon")
    if Pokemon and type(Pokemon.national) == "function" then
      local ok, v = pcall(Pokemon.national, id)
      if ok then nat = v end
    end
    nat = math.floor(tonumber(nat) or 0)
    if nat < 1 or nat > NAT_MAX then return nil end
    return nat
  end
  local function scrub(raw)
    local out = {}
    if type(raw) == "table" then
      for k, v in pairs(raw) do
        local nat = math.floor(tonumber(k) or 0)
        local n = math.floor(tonumber(v) or 0)
        if nat >= 1 and nat <= NAT_MAX then
          if n < 0 then n = 0 end
          if n > COUNT_CAP then n = COUNT_CAP end
          if n > 0 then out[nat] = n end
        end
      end
    end
    return out
  end
  local function store()
    local s = SP.session()
    if not s then return nil end
    local t = s.safariMastery
    if type(t) ~= "table" then t = {} s.safariMastery = t end
    return t
  end
  local function pull()
    local g = SP.saveGet("mastery", nil)
    local clean
    if g ~= nil then
      clean = scrub(g)
    else
      local s = SP.session()
      clean = scrub(s and s.safariMastery)
    end
    local t = store()
    if t then
      for k in pairs(t) do t[k] = nil end
      for k, v in pairs(clean) do t[k] = v end
    end
    SP.saveSet("mastery", clean)
  end
  local function persist()
    local t = store()
    SP.saveSet("mastery", scrub(t))
  end
  local function getCount(species)
    local nat = natOf(species)
    if not nat then return 0 end
    local t = store()
    local n = t and tonumber(t[nat]) or 0
    if n == nil or n < 0 then return 0 end
    if n > COUNT_CAP then return COUNT_CAP end
    return math.floor(n)
  end
  local function recordCatch(species)
    local nat = natOf(species)
    if not nat then return end
    local t = store()
    if not t then return end
    local n = math.floor(tonumber(t[nat]) or 0)
    if n >= COUNT_CAP then return end
    t[nat] = n + 1
    persist()
  end
  local function tierFor(count)
    for _, row in ipairs(TIERS) do
      if count >= row[1] then return row[2], row[3] end
    end
    return nil, nil
  end
  local function rollIVs()
    local iv1 = rng(65536)
    local iv2 = rng(65536)
    return {
      hp = iv1 % 32,
      atk = math.floor(iv1 / 32) % 32,
      def = math.floor(iv1 / 1024) % 32,
      spe = iv2 % 32,
      spa = math.floor(iv2 / 32) % 32,
      spd = math.floor(iv2 / 1024) % 32,
    }
  end
  local function applyToFoe(foe)
    local species = nil
    if type(foe) == "table" then
      species = foe.species or foe.speciesId or foe.id
    end
    local count = getCount(species)
    if count < 5 then return end
    local guaranteed, bonus = tierFor(count)
    if not guaranteed or (guaranteed == 0 and bonus == 0) then return end
    local ivs = rollIVs()
    local avail = {}
    for i = 1, 6 do
      if (tonumber(ivs[STAT_KEYS[i]]) or 0) < 31 then avail[#avail + 1] = i end
    end
    if #avail == 0 then return end
    for _ = 1, guaranteed do
      if #avail == 0 then break end
      local idx = rng(#avail) + 1
      ivs[STAT_KEYS[avail[idx]]] = 31
      avail[idx] = avail[#avail]
      avail[#avail] = nil
    end
    for _ = 1, bonus do
      if #avail == 0 then break end
      if rng(2) == 0 then
        local idx = rng(#avail) + 1
        ivs[STAT_KEYS[avail[idx]]] = 31
        avail[idx] = avail[#avail]
        avail[#avail] = nil
      end
    end
    foe.ivs = ivs
  end
  local function liveState()
    local B = SP.require("src.core.game3.battle")
    if type(B) == "table" and type(B.getState) == "function" then
      local ok, st = pcall(B.getState)
      if ok and type(st) == "table" then return st end
    end
    return nil
  end
  local function foeSkipped(foe, opts)
    if type(foe) ~= "table" then return true end
    if foe.oldMan or foe.pokedude or foe.tutorial then return true end
    if type(foe.party) == "table" then return true end
    if opts and opts.trainerId ~= nil then return true end
    if foe.trainerId ~= nil then return true end
    if foe.ivs ~= nil then return true end
    return false
  end
  local Bridge = SP.require("src.core.game3.battle_bridge")
  if type(Bridge) == "table" and type(Bridge.start) == "function"
      and SP.claim(Bridge, "__spMasteryWrapped") then
    local nativeStart = Bridge.start
    Bridge.start = function(mArg, game, foe, opts)
      if masteryOn() and type(opts) == "table" and opts.wild and not opts.link
          and opts.tutorial ~= true and not foeSkipped(foe, opts) then
        local st = liveState()
        if not (st and SP.isTutorial(st)) then
          applyToFoe(foe)
        end
      end
      return nativeStart(mArg, game, foe, opts)
    end
  end
  local Catching = SP.require("src.core.game3.battle.catching")
  if type(Catching) == "table" and type(Catching.storeCaught) == "function"
      and SP.claim(Catching, "__spMasteryWrapped") then
    local nativeStore = Catching.storeCaught
    Catching.storeCaught = function(session, foe, ballId, opts, ...)
      local res = nativeStore(session, foe, ballId, opts, ...)
      if masteryOn() and type(res) == "table" and res.success then
        local st = liveState()
        if not (st and SP.isTutorial(st)) then
          local mon = res.mon
          local species = type(mon) == "table"
            and (mon.species or mon.speciesId) or nil
          if species == nil and type(foe) == "table" then
            species = foe.species or foe.speciesId
          end
          recordCatch(species)
        end
      end
      return res
    end
  end
  pull()
  if mod.events and type(mod.events.on) == "function" then
    mod.events:on("save.loaded", function()
      pull()
    end)
    mod.events:on("save.writing", function()
      persist()
    end)
  end
  mod.log:info("safari-plus: mastery installed")
end
