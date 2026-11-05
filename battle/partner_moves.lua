return function(mod)
  local SP = mod.exports.safariPlus
  if not SP then return end
  local DATA = SP.partnerMoveData
  if type(DATA) ~= "table" then return end
  local TYPE_NUM = {
    NORMAL = 0, FIGHTING = 1, FLYING = 2, POISON = 3, GROUND = 4,
    ROCK = 5, BUG = 6, GHOST = 7, STEEL = 8, MYSTERY = 9,
    FIRE = 10, WATER = 11, GRASS = 12, ELECTRIC = 13,
    PSYCHIC = 14, ICE = 15, DRAGON = 16, DARK = 17,
  }
  local BY_NUM = {}
  local function rebuildByNum()
    for k in pairs(BY_NUM) do BY_NUM[k] = nil end
    for _, def in ipairs(DATA.MOVES) do BY_NUM[def.num] = def end
  end
  rebuildByNum()
  local HOME_BASE = 355
  local MOVE_COUNT = #DATA.MOVES
  local baseApplied = nil
  local function foreignTop()
    local top = 354
    pcall(function()
      local Moves = SP.require("src.core.game3.battle.moves")
      if type(Moves) ~= "table" then return end
      if type(Moves.BY_NUM) == "table" then
        for k, v in pairs(Moves.BY_NUM) do
          local n = math.floor(tonumber(k) or 0)
          if n >= HOME_BASE then
            local ours = type(v) == "string" and v:sub(1, 3) == "SP_"
            if not ours and n > top then top = n end
          end
        end
      end
      local rows = nil
      if type(Moves.romRows) == "function" then
        local ok, r = pcall(Moves.romRows)
        if ok and type(r) == "table" then rows = r end
      end
      if type(rows) ~= "table" then rows = Moves._rom end
      if type(rows) == "table" then
        for k, v in pairs(rows) do
          local n = math.floor(tonumber(k) or 0)
          if n >= HOME_BASE then
            local ours = type(v) == "table" and v.spPartner == true
            if not ours and n > top then top = n end
          end
        end
      end
    end)
    return top
  end
  local function dexPresent()
    local found = false
    pcall(function()
      found = mod.find ~= nil and mod.find("national_dex_gen3") ~= nil
    end)
    return found
  end
  local function computeBase()
    local top = foreignTop()
    if dexPresent() or top >= HOME_BASE then
      if top < 900 then top = 899 end
      return top + 1
    end
    return HOME_BASE
  end
  local function applyBase(base)
    if baseApplied == base then return end
    baseApplied = base
    for i, def in ipairs(DATA.MOVES) do def.num = base + i - 1 end
    for _, entry in pairs(DATA.LINES) do
      if type(entry) == "table" then entry.nums = {} end
    end
    for _, def in ipairs(DATA.MOVES) do
      local entry = DATA.LINES[def.line]
      if type(entry) == "table" then
        entry.nums[#entry.nums + 1] = def.num
      end
    end
    DATA.RETURN_SET = {}
    DATA.ALWAYS_SET = {}
    DATA.SUCKER_NUM = nil
    DATA.HYDRO_NUM = nil
    for _, def in ipairs(DATA.MOVES) do
      if def.returnPower then DATA.RETURN_SET[def.num] = true end
      if def.alwaysHit then DATA.ALWAYS_SET[def.num] = true end
      if def.sucker then DATA.SUCKER_NUM = def.num end
      if def.primary then DATA.HYDRO_NUM = def.num end
    end
    rebuildByNum()
  end
  local function remapMon(oldBase, newBase, mon)
    if type(mon) ~= "table" then return false end
    local changed = false
    for _, key in ipairs({ "moves", "moveIds" }) do
      local t = mon[key]
      if type(t) == "table" then
        for i = 1, 4 do
          local v = math.floor(tonumber(t[i]) or 0)
          if v >= oldBase and v < oldBase + MOVE_COUNT then
            t[i] = newBase + (v - oldBase)
            changed = true
          end
        end
      end
    end
    return changed
  end
  local function migrateMoves(oldBase, newBase)
    if oldBase == newBase then return end
    local sess = SP.session()
    local party = type(sess) == "table" and sess.party or nil
    if type(party) == "table" then
      for _, mon in ipairs(party) do pcall(remapMon, oldBase, newBase, mon) end
    end
    pcall(function()
      local Storage = SP.require("src.core.game3.storage")
      if type(Storage) ~= "table" then return end
      local seen = {}
      local function walk(t, depth)
        if type(t) ~= "table" or depth > 4 or seen[t] then return end
        seen[t] = true
        if type(t.moves) == "table" then pcall(remapMon, oldBase, newBase, t) end
        for _, v in pairs(t) do
          if type(v) == "table" then walk(v, depth + 1) end
        end
      end
      for _, key in ipairs({ "pc", "boxes", "storage", "box" }) do
        if type(sess) == "table" and type(sess[key]) == "table" then
          walk(sess[key], 0)
        end
      end
      for _, key in ipairs({ "boxes", "listBoxes", "eachBox", "pc", "list" }) do
        local fn = Storage[key]
        if type(fn) == "function" then
          local ok, out = pcall(fn, sess or Storage)
          if ok and type(out) == "table" then walk(out, 0) end
        end
      end
    end)
  end
  local function partnerOn()
    return SP.opt("partner", true) ~= false
  end
  local function lineOf(mon)
    if type(SP.partnerLine) ~= "function" then return nil end
    local ok, nm = pcall(SP.partnerLine, mon)
    if not ok or type(nm) ~= "string" then return nil end
    return DATA.EVO_LINE[nm]
  end
  local function abilityNum(name, fallback)
    local Ab = SP.require("src.core.game3.battle.abilities")
    if type(Ab) == "table" and type(Ab.id) == "function" then
      local ok, v = pcall(Ab.id, name)
      if ok and tonumber(v) then return math.floor(tonumber(v)) end
    end
    return fallback
  end
  local function setAbility(mon, line)
    if type(mon) ~= "table" then return end
    if line == "MUDKIP" then
      mon.ability, mon.abilityId = "MUD_FORCE", "MUD_FORCE"
      mon.spMudForce = true
    elseif line == "TORCHIC" then
      local id = abilityNum("INTIMIDATE", 22)
      mon.ability, mon.abilityId = id, id
      mon.spMudForce = nil
    elseif line == "TREECKO" then
      local id = abilityNum("LIGHTNING_ROD", 31)
      mon.ability, mon.abilityId = id, id
      mon.spMudForce = nil
    end
  end
 SP.partnerSetAbility = setAbility
 SP.partnerSetAbilityFor = function(mon)
   if type(mon) ~= "table" then return end
   local line = lineOf(mon)
   if line ~= nil then setAbility(mon, line) end
 end
  local function restoreAbility(mon)
    if type(mon) ~= "table" then return end
    local sid = math.floor(tonumber(mon.species or mon.speciesId) or 0)
    if sid < 1 then return end
    local Pokemon = SP.require("src.core.game3.pokemon")
    if type(Pokemon) ~= "table"
        or type(Pokemon.abilityId) ~= "function" then
      return
    end
    local ok, id = pcall(Pokemon.abilityId, sid, mon.personality)
    if not ok or tonumber(id) == nil then return end
    id = math.floor(tonumber(id))
    mon.ability, mon.abilityId = id, id
    mon.spMudForce = nil
  end
  SP.partnerRestoreAbility = restoreAbility
  SP.partnerRestoreAbilityFor = function(mon)
    if type(mon) ~= "table" then return end
    if lineOf(mon) ~= nil then restoreAbility(mon) end
  end
  local function allowedFor(badges)
    local n = 0
    for i, th in ipairs(DATA.UNLOCK) do
      if (math.floor(tonumber(badges) or 0)) >= th then n = i end
    end
    return n
  end
  local function moveNumOf(v)
    local n = tonumber(v)
    if n then return n end
    if type(v) ~= "string" or v == "" then return nil end
    local Moves = SP.require("src.core.game3.battle.moves")
    if type(Moves) == "table" and type(Moves.numForName) == "function" then
      local ok, num = pcall(Moves.numForName, v)
      if ok and tonumber(num) then return math.floor(tonumber(num)) end
    end
    return nil
  end
  local function returnPower(aMon)
    local fr = 70
    if type(aMon) == "table" then
      fr = tonumber(aMon.friendship or aMon.happiness) or 70
    end
    local p = math.floor(10 * fr / 25)
    if p < 1 then p = 1 end
    return p
  end
  local function runBlindpoint(ctx)
    ctx.changeStage(ctx.target, "attack", -1)
    ctx.changeStage(ctx.target, "special", -1)
    return {}
  end
  local function screenTurns()
    local Cap = SP.require("src.core.game3.battle.capabilities")
    if type(Cap) == "table" and tonumber(Cap.screenDefaultTurns) then
      local t = math.floor(tonumber(Cap.screenDefaultTurns))
      if t >= 1 then return t end
    end
    return 5
  end
  local function runAvalanche(ctx)
    local st = ctx.battle
    if type(st) ~= "table" then return {} end
    local side = nil
    if type(ctx.user) == "table" and ctx.user.side == "player" then
      side = st.playerSide
    else
      side = st.enemySide
    end
    if type(side) ~= "table" then return {} end
    if (tonumber(side.expReflectTurns) or 0) > 0 then
      return { "But it failed!" }
    end
    side.expReflectTurns = screenTurns()
    return { ctx.displayName(ctx.user) .. " raised its side's DEFENSE!" }
  end
  local function runEmber(ctx)
    ctx.changeStage(ctx.user, "speed", 1)
    return {}
  end
  local function runDragon(ctx)
    local u = ctx.user
    local mon = (type(u) == "table") and u.mon or nil
    if type(mon) ~= "table" then return {} end
    local maxHp = math.floor(tonumber(mon.maxHp) or 0)
    local hp = math.floor(tonumber(mon.hp) or 0)
    if maxHp < 1 or hp >= maxHp then return {} end
    local gain = math.floor(maxHp * 15 / 100)
    if gain < 1 then gain = 1 end
    local v = hp + gain
    if v > maxHp then v = maxHp end
    mon.hp = v
    return { ctx.displayName(u) .. " restored its HP!" }
  end
  local function runTerra(ctx)
    local t = ctx.target
    if type(t) ~= "table" then return {} end
    if (tonumber(t.substituteHP) or 0) > 0 then
      return { "But it failed!" }
    end
    if t.expSeeded then return { "But it failed!" } end
    if t.type1 == 12 or t.type2 == 12 then
      return { "It doesn't affect " .. ctx.displayName(t) .. "..." }
    end
    t.expSeeded = true
    t.leechSeed = true
    t.expSeedSource = ctx.user
    return { ctx.displayName(t) .. " was seeded!" }
  end
  local function runHydro(ctx)
    local user = ctx.user
    if type(user) ~= "table" then return { failed = true } end
    local last = user.expLastResulting and moveNumOf(user.expLastResulting)
      or nil
    if last ~= DATA.HYDRO_NUM and not DATA.PROTECT_NUMS[last] then
      user.expProtectStreak = 0
    end
    local streak = math.floor(tonumber(user.expProtectStreak) or 0)
    if streak < 0 then streak = 0 end
    local st = ctx.battle
    local want = ((type(st) == "table" and st.double) and 4 or 2)
    local ok = user.expTurnOrder ~= want
    if ok and streak > 0 then
      local denom = 2 ^ math.min(streak, 3)
      local roll = 1
      if type(ctx.rng) == "function" then
        local okR, v = pcall(ctx.rng, 0, denom - 1)
        if okR and tonumber(v) then roll = math.floor(tonumber(v)) end
      end
      ok = (roll == 0)
    end
    if not ok then
      user.expProtectStreak = 0
      return { failed = true, "But it failed!" }
    end
    user.expProtectStreak = streak + 1
    user.expProtected = true
    user.expHydroUp = true
    return { ctx.displayName(user) .. " protected itself!" }
  end
  local EFFECT_RUN = {
    SP_BLINDPOINT_STRIKE = { kind = "secondary", run = runBlindpoint },
    SP_AVALANCHE_STOMP = { kind = "secondary", run = runAvalanche },
    SP_EMBER_PULSE = { kind = "secondary", run = runEmber },
    SP_DRAGON_ROAR = { kind = "secondary", run = runDragon },
    SP_TERRA_SHOT = { kind = "secondary", run = runTerra },
    SP_HYDRO_SHIELD = { kind = "primary", run = runHydro },
  }
  local function installAll()
    local Moves = SP.require("src.core.game3.battle.moves")
    if type(Moves) ~= "table" then return false end
    if type(Moves.romReady) == "function" then SP.try(Moves.romReady) end
    local rows = nil
    if type(Moves.romRows) == "function" then
      local ok, r = pcall(Moves.romRows)
      if ok and type(r) == "table" then rows = r end
    end
    if type(rows) ~= "table" then rows = Moves._rom end
    if type(rows) ~= "table" then return false end
    local Types = SP.require("src.core.game3.battle.types")
    for _, def in ipairs(DATA.MOVES) do
      local t = TYPE_NUM[def.type]
      if type(Types) == "table" and type(Types.ID) == "table"
          and tonumber(Types.ID[def.type]) then
        t = math.floor(tonumber(Types.ID[def.type]))
      end
      rows[def.num] = {
        power = def.power, type = t, accuracy = def.accuracy,
        pp = def.pp, effect = def.effect,
        secondaryChance = def.chance, target = def.target,
        priority = def.priority, flags = def.flags,
        _modEffectId = def.modEffect, spPartner = true,
      }
    end
    local Pokemon = SP.require("src.core.game3.pokemon")
    if type(Pokemon) == "table" then
      for _, key in ipairs({ "_moveNames", "_romMoveNames" }) do
        if type(Pokemon[key]) == "table" then
          for _, def in ipairs(DATA.MOVES) do
            Pokemon[key][def.num] = def.name
          end
        end
      end
    end
    if type(Moves.BY_NUM) == "table" then
      for _, def in ipairs(DATA.MOVES) do Moves.BY_NUM[def.num] = def.id end
    end
    if type(Moves._numByName) == "table" then
      for _, def in ipairs(DATA.MOVES) do
        Moves._numByName[def.id] = def.num
      end
    end
    return true
  end
  local function installEffects()
    local ModBattle = SP.require("src.core.game3.battle.mod_registries")
    if type(ModBattle) ~= "table"
        or type(ModBattle.data) ~= "function" then
      return false
    end
    local ok, d = pcall(ModBattle.data)
    if not ok or type(d) ~= "table" then return false end
    local reg = d.gen3MoveEffects
    if type(reg) ~= "table" then
      reg = {}
      d.gen3MoveEffects = reg
    end
    for id, rec in pairs(EFFECT_RUN) do reg[id] = rec end
    return true
  end
  local function ensure()
    local base = computeBase()
    applyBase(base)
    local saved = HOME_BASE
    pcall(function()
      if type(SP.saveGet) == "function" then
        saved = math.floor(tonumber(SP.saveGet("pmBase", HOME_BASE)) or HOME_BASE)
      end
    end)
    if saved ~= base then
      pcall(migrateMoves, saved, base)
      pcall(function()
        if type(SP.saveSet) == "function" then SP.saveSet("pmBase", base) end
      end)
    end
    local ok = installAll()
    installEffects()
    return ok
  end
  local function wrapDamage()
    local Damage = SP.require("src.core.game3.battle.damage")
    if type(Damage) ~= "table"
        or type(Damage.calc) ~= "function" then
      return false
    end
    if not SP.claim(Damage, "__spPartnerMovesWrapped") then return true end
    local native = Damage.calc
    local Rules = SP.require("src.core.game3.battle.rules")
    local Moves = SP.require("src.core.game3.battle.moves")
    Damage.calc = function(attacker, defender, moveId, opts)
      opts = opts or {}
      local num = nil
      if type(moveId) == "table" then
        num = tonumber(moveId.numId)
      else
        num = tonumber(moveId)
        if not num and type(moveId) == "string" and type(Moves) == "table"
            and type(Moves.numForName) == "function" then
          local ok, n = pcall(Moves.numForName, moveId)
          if ok then num = tonumber(n) end
        end
      end
      if num ~= nil then
        if DATA.RETURN_SET[num] and opts.power == nil then
          local aMon = (type(attacker) == "table")
            and (attacker.mon or attacker) or {}
          local o2 = {}
          for k, v in pairs(opts) do o2[k] = v end
          o2.power = returnPower(aMon)
          opts = o2
        end
        local aMon = (type(attacker) == "table")
          and (attacker.mon or attacker) or nil
        if partnerOn() and type(aMon) == "table" and aMon.spMudForce then
          local w = opts.weatherKind
          if w == nil and type(Rules) == "table"
              and type(Rules.weather) == "table" then
            if (opts.st ~= nil or opts.adapter ~= nil)
                and type(Rules.weather.effective) == "function" then
              local okW, kind = pcall(Rules.weather.effective,
                opts.st, opts.adapter)
              if okW then w = kind end
            elseif opts.weather ~= nil
                and type(Rules.weather.kind) == "function" then
              local okW, kind = pcall(Rules.weather.kind, opts.weather)
              if okW then w = kind end
            end
          end
          if w == "RAIN" then
            local atk = tonumber(aMon.attack or aMon.atk) or 0
            if atk > 0 then
              local boosted = math.floor(atk * 130 / 100)
              local m2 = {}
              for k, v in pairs(aMon) do m2[k] = v end
              m2.attack, m2.atk = boosted, boosted
              if type(attacker) == "table" then
                local a2 = {}
                for k, v in pairs(attacker) do a2[k] = v end
                a2.mon = m2
                attacker = a2
              end
            end
          end
        end
      end
      return native(attacker, defender, moveId, opts)
    end
    return true
  end
  local function suckerBlocked(c)
    local st = c.battle
    local target = c.target
    if type(st) ~= "table" or type(target) ~= "table" then return true end
    local rows = st.turnActions
    if type(rows) ~= "table" then return true end
    local me = nil
    for _, row in pairs(rows) do
      if type(row) == "table" and row.user == target then
        me = row
        break
      end
    end
    if me == nil then
      local State = SP.require("src.core.game3.battle.state")
      if type(State) == "table" and type(State.idOf) == "function" then
        local okT, tid = pcall(State.idOf, target)
        if okT and tid ~= nil then
          for _, row in pairs(rows) do
            if type(row) == "table" and type(row.user) == "table" then
              local okR, rid = pcall(State.idOf, row.user)
              if okR and rid == tid then
                me = row
                break
              end
            end
          end
        end
      end
    end
    if me == nil or me.kind ~= "move" then return true end
    local Moves = SP.require("src.core.game3.battle.moves")
    if type(Moves) ~= "table" or type(Moves.get) ~= "function" then
      return true
    end
    local ok, mv = pcall(Moves.get, me.move)
    if not ok or type(mv) ~= "table" then return true end
    return (tonumber(mv.power) or 0) <= 0
  end
  local function clearHydroStatus(tb, adapter)
    tb.status = nil
    tb.toxicCounter = nil
    tb.sleepTurns = nil
    if type(tb.mon) == "table" then
      tb.mon.status = nil
      tb.mon.toxicCounter = nil
      tb.mon.sleepTurns = nil
    end
    if type(adapter) == "table" and type(adapter.say) == "function" then
      local nm = "POKéMON"
      local Pokemon = SP.require("src.core.game3.pokemon")
      if type(Pokemon) == "table"
          and type(Pokemon.displayMonName) == "function" then
        local okN, v = pcall(Pokemon.displayMonName, tb.mon or tb)
        if okN and type(v) == "string" and v ~= "" then nm = v end
      end
      SP.try(adapter.say, adapter, nm .. " was cured of its status!")
    end
  end
  local function wrapResolve()
    local Engine = SP.require("src.core.game3.battle.engine")
    if type(Engine) ~= "table"
        or type(Engine.resolveMove) ~= "function" then
      return false
    end
    if not SP.claim(Engine, "__spPartnerMovesResolveWrapped") then
      return true
    end
    local native = Engine.resolveMove
    local State = SP.require("src.core.game3.battle.state")
    local Moves = SP.require("src.core.game3.battle.moves")
    Engine.resolveMove = function(user, target, moveId, slot, adapter, st,
        out, opts)
      local watched = nil
      if type(st) == "table" and st.double ~= true
          and type(State) == "table"
          and type(State.occupant) == "function"
          and (opts == nil or not opts.called) then
        local okO, tb = pcall(State.occupant, st, target)
        local okU, ub = pcall(State.occupant, st, user)
        if okO and type(tb) == "table" and tb.expHydroUp
            and tb.expProtected and okU and type(ub) == "table"
            and ub.side ~= tb.side then
          local mv = nil
          if type(Moves) == "table"
              and type(Moves.get) == "function" then
            local okM, m = pcall(Moves.get, moveId)
            if okM and type(m) == "table" then mv = m end
          end
          local tt = (mv ~= nil) and tonumber(mv.target) or nil
          if tt ~= nil and tt ~= 16 then
            watched = {
              tb = tb,
              hp = tonumber(tb.mon and tb.mon.hp),
              status = tb.status or (tb.mon and tb.mon.status),
            }
          end
        end
      end
      local res = { pcall(native, user, target, moveId, slot, adapter, st,
        out, opts) }
      if res[1] ~= true then error(res[2], 0) end
      if watched ~= nil then
        local tb = watched.tb
        tb.expHydroUp = nil
        local hp = tonumber(tb.mon and tb.mon.hp)
        local status = tb.status or (tb.mon and tb.mon.status)
        if hp == watched.hp and status == watched.status then
          clearHydroStatus(tb, adapter)
        end
      end
      return unpack(res, 2)
    end
    return true
  end
  local function countBadges()
    local session = SP.session()
    local base = 0x820
    local BP = SP.require("src.core.game3.battle.profile")
    if type(BP) == "table" and type(BP.get) == "function" then
      local ok, p = pcall(BP.get, session)
      if ok and type(p) == "table" and type(p.badgeFlags) == "table"
          and tonumber(p.badgeFlags[1]) then
        base = math.floor(tonumber(p.badgeFlags[1]))
      end
    end
    local Flags = SP.require("src.core.game3.scripting.flags")
    local Space = SP.require("src.core.game3.scripting.space")
    local store = (type(Space) == "table") and Space.store or nil
    local n = 0
    for i = 0, 7 do
      if type(Flags) == "table" and type(Flags.getFlag) == "function"
          and store ~= nil then
        local ok, v = pcall(Flags.getFlag, store, nil, base + i)
        if ok and v == true then n = n + 1 end
      end
    end
    return n
  end
  local function rowLine(row)
    if type(row) ~= "table" then return nil end
    local Pokemon = SP.require("src.core.game3.pokemon")
    if type(Pokemon) ~= "table" then return nil end
    local id = nil
    local sp = row.species
    if type(sp) == "string" and not tonumber(sp)
        and type(Pokemon.speciesFromName) == "function" then
      local ok, v = pcall(Pokemon.speciesFromName, sp)
      if ok and tonumber(v) then id = math.floor(tonumber(v)) end
    end
    if id == nil then id = math.floor(tonumber(sp) or 0) end
    if (id or 0) < 1 then
      id = math.floor(tonumber(row.speciesId) or 0)
    end
    if id < 1 or type(Pokemon.name) ~= "function" then return nil end
    local ok, nm = pcall(Pokemon.name, id)
    if not ok or type(nm) ~= "string" then return nil end
    return DATA.EVO_LINE[nm:upper():gsub("[^A-Z0-9]", "")]
  end
  local function applyPartnerRow(row, line, n)
    if type(row) ~= "table" or line == nil then return end
    local entry = DATA.LINES[line]
    if type(entry) ~= "table" then return end
    row.moves = (type(row.moves) == "table") and row.moves or {}
    row.pp = (type(row.pp) == "table") and row.pp or {}
    row.maxPp = (type(row.maxPp) == "table") and row.maxPp or {}
    for s = 1, math.min(n, 4) do
      local num = entry.nums[s]
      local def = BY_NUM[num]
      if num ~= nil and def ~= nil then
        row.moves[s] = num
        row.pp[s] = def.pp
        row.maxPp[s] = def.pp
      end
    end
    row.moveIds = (type(row.moveIds) == "table") and row.moveIds or {}
    for s = 1, 4 do
      if row.moves[s] ~= nil then
        row.moveIds[s] = tonumber(row.moves[s])
      end
    end
    local ab = entry.ability
    row.ability, row.abilityId = ab, ab
    if line == "MUDKIP" then row.spMudForce = true end
  end
  local function trainerKind(class, tid)
    local id = tonumber(tid)
    if id ~= nil then
      if DATA.WALLY_IDS[id] then return "wally" end
      if DATA.RIVAL_IDS[id] then return "rival" end
    end
    if type(class) == "string" then
      local u = class:upper()
      for _, k in ipairs(DATA.WALLY_KEYS) do
        if u:find(k, 1, true) then return "wally" end
      end
      for _, k in ipairs(DATA.RIVAL_KEYS) do
        if u:find(k, 1, true) then return "rival" end
      end
    end
    return nil
  end
  local function playerLine()
    local session = SP.session()
    local party = (type(session) == "table") and session.party or nil
    if type(party) == "table" then
      for _, mon in ipairs(party) do
        if type(mon) == "table" and mon.spPartner and not mon.isEgg then
          local line = lineOf(mon)
          if line ~= nil then return line end
        end
      end
      for _, mon in ipairs(party) do
        if type(mon) == "table" and not mon.isEgg then
          local line = lineOf(mon)
          if line ~= nil then return line end
        end
      end
    end
    return nil
  end
  local function rewriteTrainerParty(class, tid, party)
    if not partnerOn() then return party end
    if type(party) ~= "table" then return party end
    local kind = trainerKind(class, tid)
    if kind == nil then return party end
    local n = allowedFor(countBadges())
    for _, row in ipairs(party) do
      local line = rowLine(row)
      if line ~= nil then applyPartnerRow(row, line, n) end
    end
    if kind == "wally" then
      local lastLine = nil
      for i, row in ipairs(party) do
        if rowLine(row) ~= nil then lastLine = i end
      end
      if lastLine == nil then
        local mine = playerLine()
        if mine ~= nil then
          local rival = DATA.ADVANTAGE[mine]
          local want = nil
          for _, cand in ipairs({ "TORCHIC", "TREECKO", "MUDKIP" }) do
            if cand ~= mine and cand ~= rival then want = cand end
          end
          if want ~= nil then
            local lv = 5
            for _, row in ipairs(party) do
              local l = math.floor(tonumber(row.level) or 0)
              if l > lv then lv = l end
            end
            local row = {
              species = want, level = lv, moves = {},
              personality = math.random(0, 999999),
              ivs = {
                hp = math.random(10, 20), atk = math.random(10, 20),
                def = math.random(10, 20), spe = math.random(10, 20),
                spa = math.random(10, 20), spd = math.random(10, 20),
              },
            }
            applyPartnerRow(row, want, n)
            party[#party + 1] = row
          end
        end
      elseif lastLine ~= #party then
        local row = table.remove(party, lastLine)
        party[#party + 1] = row
      end
    end
    return party
  end
  local PM = {
    allowedFor = allowedFor,
    costFor = function(i) return DATA.COSTS[i] end,
    ensure = ensure,
    lineOf = lineOf,
    moveDef = function(num) return BY_NUM[tonumber(num)] end,
    applyPartnerRow = applyPartnerRow,
    trainerKind = trainerKind,
    rowLine = rowLine,
  }
  SP.partnerMoves = PM
  wrapDamage()
  wrapResolve()
  if mod.hooks and type(mod.hooks.wrap) == "function" then
    pcall(function()
      mod.hooks:wrap("battle.accuracy", function(next, c)
        local num = tonumber(c.moveNum) or moveNumOf(c.moveId)
        if num == nil then return next(c) end
        if DATA.ALWAYS_SET[num] then return true end
        if num == DATA.SUCKER_NUM then
          if suckerBlocked(c) then return false end
          return next(c)
        end
        return next(c)
      end)
    end)
    pcall(function()
      mod.hooks:wrap("trainer.party", function(next, class, tid, party)
        local ok, res = pcall(rewriteTrainerParty, class, tid, party)
        if ok and type(res) == "table" then
          return next(class, tid, res)
        end
        return next(class, tid, party)
      end)
    end)
  end
  if mod.events and type(mod.events.on) == "function" then
    mod.events:on("battle.started", function(ev)
      pcall(function()
        ensure()
        wrapDamage()
        wrapResolve()
        local b = type(ev) == "table" and ev.battle or nil
        if type(b) ~= "table" and type(ev) == "table" then b = ev end
        if type(b) ~= "table" then return end
        local State = SP.require("src.core.game3.battle.state")
        if type(State) ~= "table"
            or type(State.present) ~= "function" then
          return
        end
        local okP, list = pcall(State.present, b)
        if not okP or type(list) ~= "table" then return end
        for _, bt in pairs(list) do
          if type(bt) == "table" and type(bt.mon) == "table"
              and bt.mon.spPartner then
            if partnerOn() then
              local line = lineOf(bt.mon)
              if line ~= nil then
                setAbility(bt.mon, line)
                bt.ability = bt.mon.ability
              end
            else
              restoreAbility(bt.mon)
              bt.ability = bt.mon.ability
            end
          end
        end
      end)
    end)
    mod.events:on("save.loaded", function()
      pcall(function()
        ensure()
        local session = SP.session()
        local party = (type(session) == "table") and session.party or nil
        if type(party) ~= "table" then return end
        for _, mon in ipairs(party) do
          if type(mon) == "table" and mon.spPartner and not mon.isEgg then
            if partnerOn() then
              local line = lineOf(mon)
              if line ~= nil then setAbility(mon, line) end
            else
              restoreAbility(mon)
            end
          end
        end
      end)
    end)
    mod.events:on("map.entered", function()
      pcall(function()
        ensure()
        local session = SP.session()
        local party = (type(session) == "table") and session.party or nil
        if type(party) ~= "table" then return end
        for _, mon in ipairs(party) do
          if type(mon) == "table" and mon.spPartner and not mon.isEgg then
            if partnerOn() then
              local line = lineOf(mon)
              if line ~= nil and mon.ability == nil then
                setAbility(mon, line)
              end
            else
              restoreAbility(mon)
            end
          end
        end
      end)
    end)
    mod.events:on("pokemon.evolved", function(ev)
      pcall(function()
        if type(ev) == "table" and type(ev.mon) == "table"
            and ev.mon.spPartner and partnerOn() then
          local line = lineOf(ev.mon)
          if line ~= nil then setAbility(ev.mon, line) end
        end
      end)
    end)
  end
  mod.log:info("safari-plus: partner moves installed")
end
