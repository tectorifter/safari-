return function(mod)
  local SP = mod.exports.safariPlus
  if not SP then return end
  -- Safari catches pay party EXP through the engine's own awardFoe so
  -- the messages, bars and level-ups play in-scene; move learning and
  -- evolution queue off the summary line while the battle is parked on
  -- an input-routed phase.
  local paidFor = nil
  local pendingSt = nil
  local gainedSum = 0
  local gainedCount = 0
  local pendingBattleLearn = nil
  local function alive(mon)
    return type(mon) == "table" and not mon.isEgg
      and (tonumber(mon.hp) or 0) > 0
      and (tonumber(mon.level) or 1) < 100
  end
  local function battleMod()
    local B = SP.require("src.core.game3.battle")
    if type(B) == "table" then return B end
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
    local E = SP.require("src.core.game3.battle.experience")
    if type(E) == "table" and type(E.awardFoe) == "function" then return E end
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
  local parkedPhase = nil
  -- Native award/learn UI (Choice boxes AND the summary forget picker)
  -- only receives input while the battle sits in an input-routed phase;
  -- "awarding" routes both. It is safe to hold: its update short-circuits
  -- on LearnMove.busy(), which is true for every frame of our queue, so
  -- the stale ExpSeq path can never fire; the phase is restored on drain.
  -- The evolution scene parks on the pump-idle nickname phase instead,
  -- since awarding would run ExpSeq once LearnMove goes idle.
  local function parkPhase(B, want)
    if B == nil or B._headless then return end
    if parkedPhase ~= nil then
      if B._phase ~= want then B._phase = want end
      return
    end
    if B._phase == want then return end
    parkedPhase = B._phase
    B._phase = want
  end
  local function unparkPhase(B)
    if parkedPhase == nil then return end
    if B ~= nil and (B._phase == "awarding" or B._phase == "catch_nickname_prompt") then
      B._phase = parkedPhase
    end
    parkedPhase = nil
  end
  local pendingBattleEvo = nil
  local function clearBattle()
    paidFor = nil
    pendingSt = nil
    pendingBattleLearn = nil
    pendingBattleEvo = nil
    parkedPhase = nil
    gainedSum, gainedCount = 0, 0
  end
  local function runBattleEvo()
    local mon = nil
    if type(pendingBattleEvo) == "table" and #pendingBattleEvo > 0 then
      mon = table.remove(pendingBattleEvo, 1)
      if #pendingBattleEvo == 0 then pendingBattleEvo = nil end
    end
    local B = battleMod()
    if B ~= nil and B._active == false then
      pendingBattleEvo = nil
      unparkPhase(B)
      return
    end
    if mon == nil then
      unparkPhase(B)
      return
    end
    local nextFn = SP.once(function() runBattleEvo() end)
    local st = liveState()
    local session = st and st.session or nil
    if session == nil then
      session = SP.session()
    end
    local bag = (type(session) == "table" and session.bag) or nil
    local target = nil
    local Evolution = SP.require("src.core.game3.evolution")
    if Evolution and type(Evolution.levelTarget) == "function" then
      local okE, v = pcall(Evolution.levelTarget, mon, session)
      if okE then target = v end
    end
    if target == nil then return nextFn() end
    local Scene = SP.require("src.ui.game3.evolution_scene")
    if type(Scene) ~= "table" or type(Scene.start) ~= "function" then
      if Evolution and type(Evolution.apply) == "function" then
        pcall(Evolution.apply, mon, target, session, bag)
      end
      return nextFn()
    end
    parkPhase(B, "catch_nickname_prompt")
    local ok, started = pcall(Scene.start, mon, target, {
      session = session,
      bag = bag,
      canStop = true,
      isBattle = true,
      onDone = nextFn,
    })
    if not (ok and started) then
      return nextFn()
    end
  end
  local function drainBattleLearn(UiMod)
    local item = nil
    if type(pendingBattleLearn) == "table" and #pendingBattleLearn > 0 then
      item = table.remove(pendingBattleLearn, 1)
      if #pendingBattleLearn == 0 then pendingBattleLearn = nil end
    end
    local B = battleMod()
    if B ~= nil and B._active == false then
      pendingBattleLearn = nil
      pendingBattleEvo = nil
      unparkPhase(B)
      return
    end
    if item == nil then
      runBattleEvo()
      return
    end
    parkPhase(B, "awarding")
    local nextFn = function() drainBattleLearn(UiMod) end
    local LearnMove = SP.require("src.core.game3.battle.learn_move")
    if type(LearnMove) ~= "table" or type(LearnMove.beginQueue) ~= "function" then
      return nextFn()
    end
    local ok = pcall(LearnMove.beginQueue, item.mon, item.levels, {
      displayName = item.name,
      pushMsg = function(t, cb) UiMod.push(t, cb) end,
      askYesNo = function(a, b) UiMod.askYesNo(a, b) end,
      askForget = function(labels, cb, ctx) UiMod.askForget(labels, cb, ctx) end,
      headless = B ~= nil and B._headless == true,
      battleText = true,
      onDone = nextFn,
    })
    if not ok then
      nextFn()
    end
  end
  local Catching = SP.require("src.core.game3.battle.catching")
  if type(Catching) == "table" and type(Catching.storeCaught) == "function"
      and SP.claim(Catching, "__spCatchExpWrapped") then
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
        local awards = E.awardFoe(st, st.enemy, { trainer = false, partyIndices = idx })
        if type(awards) == "table" then
          local P = SP.require("src.core.game3.pokemon")
          for _, entry in ipairs(awards) do
            local r = entry and entry.result
            if type(r) == "table" and type(r.levels) == "table"
                and #r.levels > 0 and type(entry.mon) == "table" then
              local lvls = {}
              for _, lv in ipairs(r.levels) do lvls[#lvls + 1] = lv end
              local nm = nil
              if P and type(P.displayMonName) == "function" then
                nm = P.displayMonName(entry.mon)
              end
              pendingBattleLearn = pendingBattleLearn or {}
              pendingBattleLearn[#pendingBattleLearn + 1] =
                { mon = entry.mon, levels = lvls, name = nm }
              pendingBattleEvo = pendingBattleEvo or {}
              pendingBattleEvo[#pendingBattleEvo + 1] = entry.mon
            end
          end
        end
        paidFor = st
      end)
      return res
    end
  end
  if mod.hooks and type(mod.hooks.wrap) == "function" then
    mod.hooks:wrap("exp.gain", function(nextFn, ctx)
        local amt = nextFn(ctx)
        if not SP.on() then return amt end
        local b = type(ctx) == "table" and ctx.battle or nil
        if not ours(b) then return amt end
        local pct = SP.yieldPct()
        local scaled = math.max(0, math.floor((tonumber(amt) or 0) * pct / 100))
        if pendingSt ~= nil and b == pendingSt then
          gainedSum = gainedSum + scaled
          gainedCount = gainedCount + 1
        end
        return scaled
    end)
  end
  local Ui = SP.require("src.core.game3.battle.ui")
  if type(Ui) == "table" and type(Ui.push) == "function"
      and SP.claim(Ui, "__spCatchExpWrapped") then
    local nativePush = Ui.push
    Ui.push = function(text, ...)
      local r = nativePush(text, ...)
      if pendingSt ~= nil then
        local st = liveState()
        local pst = pendingSt
        pendingSt = nil
        if st and st == pst and gainedCount > 0 and gainedSum > 0 then
          nativePush("All your POKéMON gained "
            .. tostring(math.floor(gainedSum / gainedCount))
            .. " EXP. Points!", function()
              drainBattleLearn(Ui)
            end)
        else
          pendingBattleLearn = nil
          pendingBattleEvo = nil
          unparkPhase(battleMod())
        end
        gainedSum, gainedCount = 0, 0
      end
      return r
    end
  end
  if mod.events and type(mod.events.on) == "function" then
    mod.events:on("battle.started", clearBattle)
    mod.events:on("battle.ended", clearBattle)
  end
  mod.log:info("safari-plus: catch exp installed (custom message)")
end
