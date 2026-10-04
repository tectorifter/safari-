return function(mod)
  local SP = mod.exports.safariPlus
  if not SP then return end
  local paidFor = nil
  local pendingSt = nil
  local gainedSum = 0
  local gainedCount = 0
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
  local function ours(st)
    if not SP.on() then return false end
    if type(st) ~= "table" or not st.safari then return false end
    if type(st.enemy) ~= "table" then return false end
    if SP.isTutorial(st) then return false end
    return true
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
        gainedSum, gainedCount, pendingSt = 0, 0, st
        E.awardFoe(st, st.enemy, { trainer = false, partyIndices = idx })
        paidFor = st
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
        local scaled = math.max(0, math.floor((tonumber(amt) or 0) * pct / 100))
        if pendingSt ~= nil and b == pendingSt then
          gainedSum = gainedSum + scaled
          gainedCount = gainedCount + 1
        end
        return scaled
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
        if pendingSt == nil then return end
        local st = liveState()
        local pst = pendingSt
        pendingSt = nil
        if st and st == pst and gainedCount > 0 and gainedSum > 0 then
          nativePush("All your POKéMON gained "
            .. tostring(math.floor(gainedSum / gainedCount))
            .. " EXP. Points!")
        end
        gainedSum, gainedCount = 0, 0
      end)
      return r
    end
  end
  if mod.events and type(mod.events.on) == "function" then
    mod.events:on("battle.started", function()
      paidFor = nil
      pendingSt = nil
      gainedSum, gainedCount = 0, 0
    end)
  end
  mod.log:info("safari-plus: catch exp installed (custom message)")
end
