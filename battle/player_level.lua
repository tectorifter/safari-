return function(mod)
  local SP = mod.exports.safariPlus
  if not SP then return end
  local DATA = SP.playerLevelData
  if type(DATA) ~= "table" then return end
  local TH = DATA.THRESHOLDS
  if type(TH) ~= "table" or tonumber(TH[80]) == nil then return end
  local MAXLV = #TH
  if MAXLV < 1 then return end
  local MAXXP = math.floor(tonumber(TH[MAXLV]) or 0)
  local AWARD = DATA.AWARD
  if type(AWARD) ~= "table" then AWARD = {} end
  local UNLOCK = DATA.UNLOCK
  if type(UNLOCK) ~= "table" then UNLOCK = {} end
  local function awardOf(key, dflt)
    local n = tonumber(AWARD[key])
    if n == nil or n < 0 or n ~= n then return dflt end
    return math.floor(n)
  end
  local function on()
    return SP.opt("player_level", true) ~= false
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
  local function scrub(raw)
    local n = math.floor(tonumber(raw) or 0)
    if n < 0 or n ~= n then n = 0 end
    if n > MAXXP then n = MAXXP end
    return n
  end
  local function store()
    local s = SP.session()
    if not s then return nil end
    if type(s.playerXp) ~= "number" then s.playerXp = nil end
    return s
  end
  local function persist()
    local s = store()
    if not s then return end
    saveSet("playerXp", scrub(s.playerXp))
  end
  local function levelFor(xp)
    local lv = 1
    for i = 2, MAXLV do
      if xp >= (tonumber(TH[i]) or math.huge) then lv = i else break end
    end
    return lv
  end
  function SP.playerLevelOn()
    return on()
  end
  function SP.playerXp()
    local s = store()
    local n = s and tonumber(s.playerXp) or 0
    if n == nil or n < 0 or n ~= n then return 0 end
    return math.min(MAXXP, math.floor(n))
  end
  function SP.playerLevel()
    return levelFor(SP.playerXp())
  end
  function SP.playerToNext()
    local total = SP.playerXp()
    local lv = levelFor(total)
    if lv >= MAXLV then return { have = 0, need = 0 } end
    local floor = math.floor(tonumber(TH[lv]) or 0)
    local need = math.floor(tonumber(TH[lv + 1]) or 0) - floor
    if need < 1 then need = 1 end
    local have = total - floor
    if have < 0 then have = 0 end
    if have > need then have = need end
    return { have = have, need = need }
  end
  local pendingUps = 0
  function SP.playerTakePendingUps()
    local n = pendingUps
    pendingUps = 0
    return n
  end
  function SP.playerAddXp(amount)
    local res = { gained = 0, ups = 0 }
    if not on() then return res end
    local n = math.floor(tonumber(amount) or 0)
    if n <= 0 then return res end
    local s = store()
    if not s then return res end
    local old = SP.playerXp()
    if old >= MAXXP then return res end
    local now = old + n
    if now > MAXXP then now = MAXXP end
    if now <= old then return res end
    s.playerXp = now
    persist()
    res.gained = now - old
    local ups = levelFor(now) - levelFor(old)
    if ups < 0 then ups = 0 end
    res.ups = ups
    pendingUps = pendingUps + ups
    return res
  end
  function SP.playerNoteCatch(species, firstTime)
    if not on() then return 0 end
    local total = awardOf("catch", 400)
    if firstTime == true then total = total + awardOf("newMon", 1000) end
    if SP.isLegendary(species) then
      total = total + awardOf("legendary", 1500)
    end
    SP.playerAddXp(total)
    return total
  end
  local function inSet(set, id)
    if type(set) ~= "table" then return false end
    return set[math.floor(tonumber(id) or 0)] == true
  end
  function SP.playerBattleWin(trainerId, result, wild, caught)
    if not on() then return 0 end
    local r = type(result) == "string" and result:lower() or ""
    if r ~= "win" and r ~= "won" and r ~= "victory"
        and r ~= "winner" then
      return 0
    end
    local tid = math.floor(tonumber(trainerId) or 0)
    local n = 0
    if tid > 0 then
      if inSet(DATA.E4, tid) then n = awardOf("e4", 2000)
      elseif inSet(DATA.CHAMP, tid) then n = awardOf("champ", 2000)
      elseif inSet(DATA.GYM, tid) then n = awardOf("gym", 1000)
      elseif inSet(DATA.RIVAL, tid) then n = awardOf("rival", 1000)
      else n = awardOf("trainer", 500) end
    elseif wild == true then
      if caught == true then return 0 end
      n = awardOf("wildBeaten", 400)
    else
      return 0
    end
    if n > 0 then SP.playerAddXp(n) end
    return n
  end
  function SP.playerNoteEvolve(mon)
    if not on() then return 0 end
    if type(mon) ~= "table" then return 0 end
    local n = awardOf("evolve", 1000)
    pcall(function()
      local s = SP.session()
      local party = type(s) == "table" and s.party or nil
      if type(party) ~= "table" then return end
      for _, m in ipairs(party) do
        if m == mon then return end
      end
      n = 0
    end)
    if n > 0 then SP.playerAddXp(n) end
    return n
  end
  function SP.playerNoteHatch()
    if not on() then return 0 end
    local n = awardOf("hatch", 1000)
    SP.playerAddXp(n)
    return n
  end
  function SP.playerNotePokestop()
    if not on() then return 0 end
    local n = awardOf("pokestop", 350)
    SP.playerAddXp(n)
    return n
  end
  function SP.playerNoteDenWin()
    if not on() then return 0 end
    local n = awardOf("den", 6000)
    SP.playerAddXp(n)
    return n
  end
  local lastDenGrant = -1e9
  local function ensureDenHook()
    local h = nil
    pcall(function()
      if mod.find ~= nil then h = mod.find("max_raids") end
    end)
    local raid = type(h) == "table" and h.exports
      and h.exports.raid or nil
    if type(raid) ~= "table"
        or type(raid.startCatch) ~= "function" then
      return false
    end
    if not SP.claim(raid, "__spDenWrapped") then return true end
    local nativeStart = raid.startCatch
    raid.startCatch = function(...)
      pcall(function()
        local now = SP.now()
        if now - lastDenGrant > 60 then
          lastDenGrant = now
          SP.playerNoteDenWin()
        end
      end)
      return nativeStart(...)
    end
    return true
  end
  SP.ensureDenHook = ensureDenHook
  function SP.playerDropLocked(kind, ref)
    if not on() then return false end
    local lv = SP.playerLevel()
    local need = 1
    if kind == "ball" then
      if ref == "ITEM_GREAT_BALL" then need = UNLOCK.great or 14
      elseif ref == "ITEM_ULTRA_BALL" then need = UNLOCK.ultra or 20 end
    elseif kind == "berry" then
      if ref == "pinap" then need = UNLOCK.pinap or 18
      elseif ref == "spinap" then need = UNLOCK.spinap or 22
      elseif ref == "grazz" then need = UNLOCK.grazz or 25 end
    elseif kind == "evo" then
      need = UNLOCK.evo or 16
    end
    return lv < (tonumber(need) or 1)
  end
  local curTid, curWild, caughtBattle = nil, false, false
  local Catching = SP.require("src.core.game3.battle.catching")
  if type(Catching) == "table"
      and type(Catching.storeCaught) == "function"
      and SP.claim(Catching, "__spPlayerCaughtWrapped") then
    local nativeStore = Catching.storeCaught
    Catching.storeCaught = function(session, foe, ballId, opts, ...)
      local res = nativeStore(session, foe, ballId, opts, ...)
      pcall(function()
        if type(res) == "table" and res.success then
          caughtBattle = true
        end
      end)
      return res
    end
  end
  if mod.events and type(mod.events.on) == "function" then
    mod.events:on("battle.started", function(ev)
      pcall(function()
        curTid = type(ev) == "table" and ev.trainerId or nil
        curWild = curTid == nil
        caughtBattle = false
      end)
    end)
    mod.events:on("battle.ended", function(ev)
      pcall(function()
        if not on() then return end
        local b = type(ev) == "table" and ev.battle or nil
        if type(b) == "table" then
          if b.safari then return end
          if SP.isTutorial(b) then return end
        end
        local res = type(ev) == "table" and ev.result or nil
        SP.playerBattleWin(curTid, res, curWild, caughtBattle)
        curTid, curWild, caughtBattle = nil, false, false
      end)
    end)
    mod.events:on("pokemon.evolved", function(ev)
      pcall(function()
        local mon = type(ev) == "table" and ev.mon or nil
        SP.playerNoteEvolve(mon)
      end)
    end)
    mod.events:on("egg.hatched", function()
      pcall(function() SP.playerNoteHatch() end)
    end)
    mod.events:on("save.loaded", function()
      pcall(function()
        local s = store()
        if s then s.playerXp = scrub(saveGet("playerXp", 0)) end
        ensureDenHook()
      end)
    end)
    mod.events:on("map.entered", function()
      pcall(ensureDenHook)
    end)
    mod.events:on("save.writing", function()
      pcall(persist)
    end)
  end
  local s0 = store()
  if s0 then s0.playerXp = scrub(saveGet("playerXp",
    s0.playerXp)) end
  pcall(ensureDenHook)
  mod.log:info("safari-plus: player level installed")
end
