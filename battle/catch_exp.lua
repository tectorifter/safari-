return function(mod)
  local SP = mod.exports.safariPlus
  if not SP then return end
  local paidFor = nil
  local pendingMsg = nil
  local function alive(mon)
    return type(mon) == "table" and not mon.isEgg
      and (tonumber(mon.hp) or 0) > 0
      and (tonumber(mon.level) or 1) < 100
  end
  local function battleMod()
    local ok, B = pcall(require, "src.core.game3.battle")
    if ok and type(B) == "table" then return B end
    return nil
  end
  local function liveState()
    local B = battleMod()
    if B and type(B.getState) == "function" then
      local ok, st = pcall(B.getState)
      if ok and type(st) == "table" then return st end
    end
    return nil
  end
  local function expMod()
    local ok, E = pcall(require, "src.core.game3.battle.experience")
    if ok and type(E) == "table" and type(E.awardFoe) == "function" then
      return E
    end
    return nil
  end
  local function eligible(party)
    local idx = {}
    if type(party) ~= "table" then return idx end
    for i = 1, 6 do
      if alive(party[i]) then idx[#idx + 1] = i end
    end
    return idx
  end
  local function isTutorial(st)
    if st.oldManTutorial or st.pokedude then return true end
    local okW, Wally = pcall(require, "src.core.game3.battle.tutorial_wally")
    if okW and Wally and type(Wally.active) == "function" then
      local ok, v = pcall(Wally.active, st)
      if ok and v then return true end
    end
    return false
  end
  local function ours(st)
    if not SP.on() then return false end
    if type(st) ~= "table" or not st.safari then return false end
    if type(st.enemy) ~= "table" then return false end
    if isTutorial(st) then return false end
    return true
  end
  local function baseShare(E, st, idx)
    local enemy = st.enemy
    local fmon = enemy.mon
    if type(fmon) ~= "table" then fmon = enemy end
    local species = enemy.species or fmon.species or fmon.speciesId
    if species == nil then return nil end
    local level = math.max(1, tonumber(fmon.level)
      or tonumber(enemy.level) or 1)
    if type(E.expYield) ~= "function" then return nil end
    local okY, y = pcall(E.expYield, species)
    if not (okY and tonumber(y)) then return nil end
    local calc = math.floor(tonumber(y) * level / 7)
    if calc < 1 then return nil end
    return math.max(1, math.floor(calc / #idx))
  end
  local okC, Catching = pcall(require, "src.core.game3.battle.catching")
  if okC and Catching and type(Catching.storeCaught) == "function"
      and not Catching.__spCatchExpWrapped then
    Catching.__spCatchExpWrapped = true
    local nativeStore = Catching.storeCaught
    Catching.storeCaught = function(session, foe, ballId, opts, ...)
      local res = nativeStore(session, foe, ballId, opts, ...)
      pcall(function()
        if not (type(res) == "table" and res.success) then return end
        local st = liveState()
        if not ours(st) then return end
        if paidFor == st then return end
        local E = expMod()
        if not E then return end
        local idx = eligible(st.playerParty)
        if #idx == 0 then return end
        E.awardFoe(st, st.enemy, { trainer = false, partyIndices = idx })
        paidFor = st
        local base = baseShare(E, st, idx)
        if base then
          local pct = 50
          pcall(function() pct = SP.yieldPct() end)
          pendingMsg = { st = st, base = math.max(0, math.floor(base * pct / 100)) }
        end
      end)
      return res
    end
  end
  if mod.hooks and type(mod.hooks.wrap) == "function" then
    pcall(function()
      mod.hooks:wrap("exp.gain", function(nextFn, ctx)
        local amt = nextFn(ctx)
        if not SP.on() then return amt end
        local b = type(ctx) == "table" and ctx.battle or nil
        if not ours(b) then return amt end
        local pct = 50
        pcall(function() pct = SP.yieldPct() end)
        return math.max(0, math.floor((tonumber(amt) or 0) * pct / 100))
      end)
    end)
  end
  local okU, Ui = pcall(require, "src.core.game3.battle.ui")
  if okU and Ui and type(Ui.push) == "function"
      and not Ui.__spCatchExpWrapped then
    Ui.__spCatchExpWrapped = true
    local nativePush = Ui.push
    Ui.push = function(text, ...)
      local r = nativePush(text, ...)
      pcall(function()
        if not pendingMsg then return end
        local st = liveState()
        local pm = pendingMsg
        pendingMsg = nil
        if st and st == pm.st then
          nativePush("All your POKéMON gained " .. tostring(pm.base)
            .. " EXP. Points!")
        end
      end)
      return r
    end
  end
  if mod.events and type(mod.events.on) == "function" then
    mod.events:on("battle.started", function()
      paidFor = nil
      pendingMsg = nil
    end)
    mod.events:on("battle.ended", function(ev)
      pcall(function()
        pendingMsg = nil
        if not SP.on() then return end
        if type(ev) ~= "table" then return end
        local b = ev.battle
        if b == nil or b == paidFor then return end
        if not ours(b) then return end
        local E = expMod()
        if not E then return end
        local s = SP.session()
        local party = s and s.party
        local idx = eligible(party)
        if #idx == 0 then return end
        local keep = b.playerParty
        b.playerParty = party
        local okA = pcall(E.awardFoe, b, b.enemy,
          { trainer = false, partyIndices = idx })
        b.playerParty = keep
        if okA then paidFor = b end
      end)
    end)
  end
  mod.log:info("safari-plus: catch exp installed (custom message)")
end
