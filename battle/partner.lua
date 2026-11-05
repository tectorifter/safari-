return function(mod)
  local SP = mod.exports.safariPlus
  if not SP then return end
  local BONUS = { hp = 10, atk = 25, def = 10, spa = 25, spd = 10, spe = 30 }
  local ORDER = { "hp", "atk", "def", "spa", "spd", "spe" }
  local LINE = {
    TORCHIC = true, COMBUSKEN = true, BLAZIKEN = true,
    TREECKO = true, GROVYLE = true, SCEPTILE = true,
    MUDKIP = true, MARSHTOMP = true, SWAMPERT = true,
  }
  local NATURE_DELTA = {
    [0] = { 0, 0, 0, 0, 0 },
    [1] = { 1, -1, 0, 0, 0 },
    [2] = { 1, 0, -1, 0, 0 },
    [3] = { 1, 0, 0, -1, 0 },
    [4] = { 1, 0, 0, 0, -1 },
    [5] = { -1, 1, 0, 0, 0 },
    [6] = { 0, 0, 0, 0, 0 },
    [7] = { 0, 1, -1, 0, 0 },
    [8] = { 0, 1, 0, -1, 0 },
    [9] = { 0, 1, 0, 0, -1 },
    [10] = { -1, 0, 1, 0, 0 },
    [11] = { 0, -1, 1, 0, 0 },
    [12] = { 0, 0, 0, 0, 0 },
    [13] = { 0, 0, 1, -1, 0 },
    [14] = { 0, 0, 1, 0, -1 },
    [15] = { -1, 0, 0, 1, 0 },
    [16] = { 0, -1, 0, 1, 0 },
    [17] = { 0, 0, -1, 1, 0 },
    [18] = { 0, 0, 0, 0, 0 },
    [19] = { 0, 0, 0, 1, -1 },
    [20] = { -1, 0, 0, 0, 1 },
    [21] = { 0, -1, 0, 0, 1 },
    [22] = { 0, 0, -1, 0, 1 },
    [23] = { 0, 0, 0, -1, 1 },
    [24] = { 0, 0, 0, 0, 0 },
  }
  local function partnerOn()
    return SP.opt("partner", true) ~= false
  end
  local function normName(raw)
    if type(raw) ~= "string" then return nil end
    local s = raw:upper():gsub("[^A-Z0-9]", "")
    if s == "" then return nil end
    return s
  end
  local function speciesNorm(species)
    if type(species) == "string" then
      local n = normName(species)
      if n ~= nil and LINE[n] then return n end
      local id = tonumber(species)
      if id == nil then return nil end
      species = id
    end
    local id = math.floor(tonumber(species) or 0)
    if id < 1 then return nil end
    local Pokemon = SP.require("src.core.game3.pokemon")
    if Pokemon and type(Pokemon.name) == "function" then
      local ok, nm = pcall(Pokemon.name, id)
      if ok then
        local n = normName(nm)
        if n ~= nil and LINE[n] then return n end
      end
    end
    return nil
  end
  local function monSpecies(mon)
    if type(mon) ~= "table" then return nil end
    local Pokemon = SP.require("src.core.game3.pokemon")
    if Pokemon and type(Pokemon.displayMonName) == "function" then
      local ok, nm = pcall(Pokemon.displayMonName, mon)
      if ok then
        local n = normName(nm)
        if n ~= nil and LINE[n] then return n end
      end
    end
    if mon.species ~= nil then
      local n = speciesNorm(mon.species)
      if n ~= nil then return n end
    end
    if mon.speciesId ~= nil then
      local n = speciesNorm(mon.speciesId)
      if n ~= nil then return n end
    end
    return nil
  end
  local function isPartner(mon)
    return type(mon) == "table" and mon.spPartner == true
  end
  SP.isPartnerMon = isPartner
  SP.partnerLine = monSpecies
  local function natureMul(nature, idx)
    local d = NATURE_DELTA[(math.floor(tonumber(nature) or 0)) % 25]
    if type(d) ~= "table" then return 1 end
    local v = tonumber(d[idx]) or 0
    if v > 0 then return 1.1 end
    if v < 0 then return 0.9 end
    return 1
  end
  local function boostedStats(mon, sid)
    local Pokemon = SP.require("src.core.game3.pokemon")
    if Pokemon == nil or type(Pokemon.stats) ~= "function" then
      return nil
    end
    local okB, base = pcall(Pokemon.stats, sid)
    if not okB or type(base) ~= "table" then return nil end
    local level = math.floor(tonumber(mon.level) or 1)
    if level < 1 then level = 1 end
    if level > 100 then level = 100 end
    local ivs = mon.ivs
    if type(ivs) ~= "table" then ivs = {} end
    local evs = mon.evs
    if type(evs) ~= "table" then evs = {} end
    local nature = (tonumber(mon.personality) or 0) % 25
    if type(Pokemon.natureId) == "function" then
      local okN, v = pcall(Pokemon.natureId, mon.personality)
      if okN and tonumber(v) ~= nil then nature = tonumber(v) end
    end
    local function iv(k)
      local v = math.floor(tonumber(ivs[k]) or 0)
      if v < 0 then return 0 end
      if v > 31 then return 31 end
      return v
    end
    local function evq(k)
      local v = math.floor(tonumber(evs[k]) or 0)
      if v < 0 then return 0 end
      if v > 252 then return 252 end
      return v
    end
    local b = {}
    for _, k in ipairs(ORDER) do
      b[k] = (tonumber(base[k]) or 0) + (BONUS[k] or 0)
    end
    local out = {}
    out.maxHp = math.floor(((2 * b.hp + iv("hp")
      + math.floor(evq("hp") / 4)) * level) / 100) + level + 10
    local idx = { atk = 1, def = 2, spe = 3, spa = 4, spd = 5 }
    for _, k in ipairs({ "atk", "def", "spe", "spa", "spd" }) do
      local n = math.floor(((2 * b[k] + iv(k)
        + math.floor(evq(k) / 4)) * level) / 100) + 5
      out[k] = math.floor(n * natureMul(nature, idx[k]))
    end
    return out
  end
  local function recalc(mon)
    if type(mon) ~= "table" or mon.isEgg then return end
    local Pokemon = SP.require("src.core.game3.pokemon")
    if type(Pokemon) == "table"
        and type(Pokemon.applyStats) == "function" then
      SP.try(Pokemon.applyStats, mon)
    end
  end
  SP.partnerRecalc = recalc
  local function wrapApply()
    local Pokemon = SP.require("src.core.game3.pokemon")
    if type(Pokemon) ~= "table"
        or type(Pokemon.applyStats) ~= "function" then
      return false
    end
    if not SP.claim(Pokemon, "__spPartnerWrapped") then return true end
    local native = Pokemon.applyStats
    Pokemon.applyStats = function(mon, ...)
      if type(mon) ~= "table" or mon.isEgg or not isPartner(mon)
          or not partnerOn() then
        return native(mon, ...)
      end
      local sid = math.floor(tonumber(mon.species or mon.speciesId) or 0)
      if sid < 1 or monSpecies(mon) == nil then
        return native(mon, ...)
      end
      local oldMax = tonumber(mon.maxHp)
      local oldHp = tonumber(mon.hp)
      local res = { pcall(native, mon, ...) }
      if res[1] ~= true then error(res[2], 0) end
      local st = boostedStats(mon, sid)
      if type(st) == "table" then
        mon.maxHp = st.maxHp
        mon.attack, mon.defense = st.atk, st.def
        mon.speed, mon.spAtk = st.spe, st.spa
        mon.spDef = st.spd
        mon.atk, mon.def = st.atk, st.def
        mon.spe, mon.spa = st.spe, st.spa
        mon.spd = st.spd
        local newMax = tonumber(st.maxHp)
        if oldHp == nil then
          mon.hp = newMax
        elseif oldMax and newMax and newMax > oldMax and oldHp > 0 then
          local hp = oldHp + (newMax - oldMax)
          if hp > newMax then hp = newMax end
          mon.hp = hp
        end
      end
      return unpack(res, 2)
    end
    return true
  end
  local function assigned()
    return SP.saveGet("partnerAssigned", false) == true
  end
  local function setAssigned()
    SP.saveSet("partnerAssigned", true)
  end
  local pendingGift = false
  local pendingSeen = nil
  local function playerLists(extra, saveParty)
    local lists = {}
    local function push(l)
      if type(l) ~= "table" or #l < 1 then return end
      for _, e in ipairs(lists) do if e == l then return end end
      lists[#lists + 1] = l
    end
    local s = SP.session()
    if type(s) == "table" then push(s.party) end
    if type(saveParty) == "table" then push(saveParty) end
    if type(extra) == "table" then
      push(extra.playerParty)
      push(extra.party)
    end
    return lists
  end
  local function stamp(mon)
    mon.spPartner = true
    setAssigned()
    if partnerOn() and type(SP.partnerSetAbilityFor) == "function" then
      SP.try(SP.partnerSetAbilityFor, mon)
    end
    recalc(mon)
  end
  local function tryAssign(extra, saveParty, backfill)
    if assigned() then
      pendingGift = false
      pendingSeen = nil
      return
    end
    local lists = playerLists(extra, saveParty)
    if pendingGift then
      for _, l in ipairs(lists) do
        for i = 1, #l do
          local m = l[i]
          if type(m) == "table" and not m.isEgg and not isPartner(m)
              and monSpecies(m) ~= nil then
            if pendingSeen == nil or pendingSeen[m] ~= true then
              stamp(m)
              mod.log:info("safari-plus: partner bonded (%s)",
                tostring(monSpecies(m)))
              pendingGift = false
              pendingSeen = nil
              return
            end
          end
        end
      end
      return
    end
    if backfill then
      for _, l in ipairs(lists) do
        for i = 1, #l do
          local m = l[i]
          if type(m) == "table" and not m.isEgg and not isPartner(m)
              and monSpecies(m) ~= nil then
            stamp(m)
            mod.log:info("safari-plus: partner adopted (%s)",
              tostring(monSpecies(m)))
            return
          end
        end
      end
    end
  end
  local function recalcFlagged(extra)
    local seen = {}
    for _, l in ipairs(playerLists(extra, nil)) do
      for i = 1, #l do
        local m = l[i]
        if type(m) == "table" and not seen[m] then
          seen[m] = true
          if isPartner(m) then recalc(m) end
        end
      end
    end
  end
  local RIVAL_KEYS = { "RIVAL", "MAY", "BRENDAN" }
  local function trainerStrings(ev, b)
    local out = {}
    local function grab(t)
      if type(t) ~= "table" then return end
      for _, k in ipairs({ "trainerId", "trainerClass", "oppClass",
          "className", "personalName", "name", "title" }) do
        local v = t[k]
        if type(v) == "string" and v ~= "" then out[#out + 1] = v end
      end
    end
    grab(ev)
    grab(b)
    if type(b) == "table" then grab(b.trainer) end
    return out
  end
  local function battleIsWild(ev, b)
    if type(ev) == "table" and (ev.kind == "wild" or ev.wild == true) then
      return true
    end
    if type(b) == "table" and (b.wild == true or b.isWild == true
        or b.kind == "wild" or b.battleType == "wild"
        or b.type == "wild") then
      return true
    end
    return false
  end
  local function battleIsTrainer(ev, b)
    if type(ev) == "table" and (ev.kind == "trainer"
        or ev.trainerId ~= nil or ev.trainerClass ~= nil) then
      return true
    end
    if type(b) == "table" and (b.kind == "trainer" or b.trainer ~= nil
        or b.trainerId ~= nil or b.trainerClass ~= nil) then
      return true
    end
    return false
  end
  local function rawMon(who)
    if type(who) ~= "table" then return nil end
    if type(who.mon) == "table" then return who.mon end
    return who
  end
  local function stampEnemies(ev, b)
    local seen = {}
    local function consider(who)
      local m = rawMon(who)
      if type(m) ~= "table" or seen[m] or m.isEgg or isPartner(m) then
        return
      end
      seen[m] = true
      if monSpecies(m) == nil then return end
      m.spPartner = true
      if partnerOn() and type(SP.partnerSetAbilityFor) == "function" then
        SP.try(SP.partnerSetAbilityFor, m)
      end
      recalc(m)
    end
    local roots = {}
    if type(b) == "table" then roots[#roots + 1] = b end
    if type(ev) == "table" and type(ev.battle) == "table"
        and ev.battle ~= b then
      roots[#roots + 1] = ev.battle
    end
    for _, r in ipairs(roots) do
      consider(r.enemy)
      consider(r.foe)
      consider(r.opponent)
      consider(r.rival)
      for _, k in ipairs({ "foeParty", "enemyParty" }) do
        local l = r[k]
        if type(l) == "table" then
          for i = 1, #l do consider(l[i]) end
        end
      end
      if type(r.battlers) == "table" then
        for _, bt in pairs(r.battlers) do
          if type(bt) == "table" and (bt.side == "enemy"
              or bt.side == "foe" or bt.isPlayer == false) then
            consider(bt)
          end
        end
      end
    end
  end
  wrapApply()
  if mod.events and type(mod.events.on) == "function" then
    mod.events:on("pokemon.before_give", function(ev)
      pcall(function()
        if type(ev) ~= "table" or assigned() or pendingGift then return end
        if speciesNorm(ev.species) == nil then return end
        pendingGift = true
        pendingSeen = {}
        local ctx = ev.ctx
        local sv = type(ctx) == "table" and ctx.save or nil
        local sp = type(sv) == "table" and sv.party or nil
        for _, l in ipairs(playerLists(nil, sp)) do
          for i = 1, #l do
            local m = l[i]
            if type(m) == "table" then pendingSeen[m] = true end
          end
        end
      end)
    end)
    mod.events:on("battle.started", function(ev)
      pcall(function()
        wrapApply()
        local b = type(ev) == "table" and ev.battle or nil
        if type(b) ~= "table" and type(ev) == "table" then b = ev end
        tryAssign(b, nil, false)
        recalcFlagged(b)
        local wild = battleIsWild(ev, b)
        local trainer = battleIsTrainer(ev, b)
        if wild and not trainer then return end
        if not trainer then return end
        local rival = false
        for _, s in ipairs(trainerStrings(ev, b)) do
          local u = s:upper()
          for _, k in ipairs(RIVAL_KEYS) do
            if u:find(k, 1, true) then
              rival = true
              break
            end
          end
          if rival then break end
        end
        if rival then stampEnemies(ev, b) end
      end)
    end)
    mod.events:on("map.entered", function()
      pcall(function()
        tryAssign(nil, nil, false)
      end)
    end)
    mod.events:on("save.loaded", function(ev)
      pcall(function()
        wrapApply()
        local sv = type(ev) == "table" and ev.save or nil
        local sp = type(sv) == "table" and sv.party or nil
        tryAssign(nil, sp, true)
        recalcFlagged(nil)
      end)
    end)
    mod.events:on("pokemon.evolved", function(ev)
      pcall(function()
        if type(ev) == "table" and isPartner(ev.mon) then recalc(ev.mon) end
      end)
    end)
    mod.events:on("mod.options_changed", function(ev)
      pcall(function()
        if type(ev) == "table" and ev.key == "partner" then
          local on = partnerOn()
          local seen = {}
          for _, l in ipairs(playerLists(nil, nil)) do
            for i = 1, #l do
              local m = l[i]
              if type(m) == "table" and not seen[m] then
                seen[m] = true
                if isPartner(m) and not m.isEgg then
                  if on then
                    if type(SP.partnerSetAbilityFor) == "function" then
                      SP.try(SP.partnerSetAbilityFor, m)
                    end
                  else
                    if type(SP.partnerRestoreAbilityFor) == "function" then
                      SP.try(SP.partnerRestoreAbilityFor, m)
                    end
                  end
                  recalc(m)
                end
              end
            end
          end
        end
      end)
    end)
  end
  if mod.hooks and type(mod.hooks.wrap) == "function" then
    pcall(function()
      mod.hooks:wrap("ui.party.submenu", function(next, game, items, mon,
          ctx)
        local res = next(game, items, mon, ctx)
        if partnerOn() and type(res) == "table" and type(mon) == "table"
            and isPartner(mon) then
          local out = {}
          for i = 1, #res do
            local it = res[i]
            local lab = nil
            if type(it) == "table" then
              lab = it.label
              if type(lab) ~= "string" then lab = it[1] end
            elseif type(it) == "string" then
              lab = it
            end
            if type(lab) == "string"
                and lab:upper():find("RELEASE", 1, true) then
            else
              out[#out + 1] = it
            end
          end
          return out
        end
        return res
      end)
    end)
  end
  mod.log:info("safari-plus: partner installed")
end
