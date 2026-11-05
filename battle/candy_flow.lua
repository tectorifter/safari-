return function(mod)
  local SP = mod.exports.safariPlus
  if not SP then return end
  local CD = assert(SP.candyData)
  local pendingLearn = nil
  local converted = false
  local function checkCandyEvolution(PM, mon, session, bag, done)
    local finish = SP.once(done)
    local target = nil
    local Evolution = SP.require("src.core.game3.evolution")
    if Evolution and type(Evolution.levelTarget) == "function" then
      local ok, v = pcall(Evolution.levelTarget, mon, session)
      if ok then target = v end
    end
    if target == nil then return finish() end
    local Scene = SP.require("src.ui.game3.evolution_scene")
    if Scene and type(Scene.start) == "function" then
      local Audio = SP.require("src.core.game3.audio")
      local song = Audio and Audio._mapSong or nil
      local ok, started = pcall(Scene.start, mon, target, {
        session = session,
        bag = bag,
        canStop = true,
        savedSong = song,
        via = "item",
        onDone = SP.once(function()
          if PM and type(PM.reloadSprites) == "function" then
            pcall(PM.reloadSprites)
          end
          finish()
        end),
      })
      if ok and started then return end
      return finish()
    end
    if Evolution and type(Evolution.apply) == "function" then
      pcall(Evolution.apply, mon, target, session, bag, "item")
    end
    return finish()
  end
  local function startLearnQueue(PM, mon, levels, session, bag, done)
    local finish = function()
      checkCandyEvolution(PM, mon, session, bag, done)
    end
    local LearnMove = SP.require("src.core.game3.battle.learn_move")
    if not (LearnMove and type(LearnMove.beginQueue) == "function") then
      finish()
      return
    end
    local monName = nil
    local Pokemon = SP.require("src.core.game3.pokemon")
    if Pokemon and type(Pokemon.displayMonName) == "function" then
      local ok, v = pcall(Pokemon.displayMonName, mon)
      if ok then monName = v end
    end
    local ok, started = pcall(LearnMove.beginQueue, mon, levels, {
      displayName = monName,
      pushMsg = function(t, cb) PM.showMessage(t, cb) end,
      askYesNo = function(a, b)
        local cb = (type(a) == "function") and a or b
        local prompt = (type(a) == "string") and a or PM._messageText or ""
        PM.showYesNo(prompt, function(yes)
          if cb then cb(yes == true) end
        end)
      end,
      askForget = function(moves, cb)
        PM.showForgetPrompt("", moves, function(idx)
          if cb then cb(idx) end
        end)
      end,
      onDone = finish,
    })
    if not ok then
      finish()
    end
  end
  local function wrapPartyMsg()
    local PM = SP.require("src.ui.game3.party_menu")
    if type(PM) ~= "table" or type(PM.showMessage) ~= "function"
        or type(PM.showYesNo) ~= "function"
        or type(PM.showForgetPrompt) ~= "function" then
      return false
    end
    if not SP.claim(PM, "__spCandyMsgWrapped") then return true end
    local native = PM.showMessage
    PM.showMessage = function(text, cb, ...)
      local pend = pendingLearn
      if pend ~= nil and type(text) == "string" and text == pend.msg then
        pendingLearn = nil
        local mon, levels, sess, pBag = pend.mon, pend.levels, pend.sess, pend.bag
        return native(text, function()
          startLearnQueue(PM, mon, levels, sess, pBag, cb)
        end, ...)
      end
      return native(text, cb, ...)
    end
    return true
  end
  local function useCandy(session, bag, def, item, slot, onArmed)
    if type(def) == "table" and def.kind == "species"
        and type(SP.speciesCandyUse) == "function" then
      local _, iout = SP.try(SP.speciesCandyUse, session, bag, def,
        item, slot)
      if type(iout) == "table" then return iout end
    end
    if type(def) == "table" and def.evStat ~= nil
        and type(SP.statCandyUse) == "function" then
      local _, sout = SP.try(SP.statCandyUse, session, bag, def, item,
        slot)
      if type(sout) == "table" then return sout end
    end
    if type(session) ~= "table" then
      session = SP.session()
    end
    local party = type(session) == "table" and session.party or nil
    local idx = math.floor(tonumber(slot) or 0)
    local mon = type(party) == "table" and party[idx] or nil
    if type(mon) ~= "table" or mon.isEgg then
      return { false, "no_effect", "It won't have any effect." }
    end
    local lvl = math.floor(tonumber(mon.level) or 1)
    if lvl >= 100 or (tonumber(mon.hp) or 0) <= 0 then
      return { false, "no_effect", "It won't have any effect." }
    end
    local targetBag = bag or (type(session) == "table" and session.bag) or nil
    local Bag = SP.require("src.core.game3.bag")
    if type(Bag) ~= "table" or type(Bag.remove) ~= "function" then
      return { false, "no_effect", "It won't have any effect." }
    end
    local has = select(2, SP.try(Bag.has, targetBag, item, 1))
    if has ~= true then
      return { false, "no_effect", "It won't have any effect." }
    end
    local removed = select(2, SP.try(Bag.remove, targetBag, item, 1))
    if removed ~= true then
      return { false, "no_effect", "It won't have any effect." }
    end
    local Exp = SP.require("src.core.game3.battle.experience")
    if not (Exp and type(Exp.apply) == "function") then
      SP.try(Bag.add, targetBag, item, 1)
      return { false, "no_effect", "It won't have any effect." }
    end
    local okA, res = SP.try(Exp.apply, mon, def.xp)
    if not (okA and type(res) == "table") then
      SP.try(Bag.add, targetBag, item, 1)
      return { false, "no_effect", "It won't have any effect." }
    end
    local monName = mon.name or "POKéMON"
    local Pokemon = SP.require("src.core.game3.pokemon")
    if Pokemon and type(Pokemon.displayMonName) == "function" then
      local ok, nm = pcall(Pokemon.displayMonName, mon)
      if ok and type(nm) == "string" and nm ~= "" then monName = nm end
    end
    local msg = tostring(monName) .. " gained " .. tostring(def.xp)
      .. " EXP. Points!"
    if tonumber(res.toLevel) and tonumber(res.fromLevel)
        and res.toLevel > res.fromLevel then
      msg = msg .. " Grew to Lv " .. tostring(res.toLevel) .. "!"
    end
    if type(res.levels) == "table" and #res.levels > 0 then
      local lvls = {}
      for _, lv in ipairs(res.levels) do lvls[#lvls + 1] = lv end
      pendingLearn = { mon = mon, levels = lvls, msg = msg,
        sess = session, bag = targetBag }
      if type(onArmed) == "function" then onArmed() end
    end
    return { true, "exp", msg }
  end
  local function wrapUse(onArmed)
    local ItemUse = SP.require("src.core.game3.item_use")
    if type(ItemUse) ~= "table" or type(ItemUse.useField) ~= "function" then
      return false
    end
    if not SP.claim(ItemUse, "__spCandyUseWrapped") then return true end
    local native = ItemUse.useField
    ItemUse.useField = function(session, bag, item, slot, moveSlot, ...)
      local def = SP.candyDef(item)
      if def == nil then
        return native(session, bag, item, slot, moveSlot, ...)
      end
      local _, out = SP.try(useCandy, session, bag, def, item, slot, onArmed)
      if type(out) == "table" then
        return out[1], out[2], out[3]
      end
      return native(session, bag, item, slot, moveSlot, ...)
    end
    return true
  end
  local function wrapTarget()
    local ItemUse = SP.require("src.core.game3.item_use")
    if type(ItemUse) ~= "table" or type(ItemUse.needsPartyTarget) ~= "function" then
      return false
    end
    if not SP.claim(ItemUse, "__spCandyTargetWrapped") then return true end
    local native = ItemUse.needsPartyTarget
    ItemUse.needsPartyTarget = function(id, ...)
      if SP.candyDef(id) ~= nil then return true end
      return native(id, ...)
    end
    return true
  end
  local function convertRes(B, Ui, res, mon, rewards)
    if SP.opt("partner", true) ~= false
        and type(SP.isPartnerMon) == "function"
        and SP.isPartnerMon(mon) then
      local monName = (type(mon) == "table" and mon.name) or "POKéMON"
      local Pokemon = SP.require("src.core.game3.pokemon")
      if type(Pokemon) == "table"
          and type(Pokemon.displayMonName) == "function" then
        local ok, nm = pcall(Pokemon.displayMonName, mon)
        if ok and type(nm) == "string" and nm ~= "" then monName = nm end
      end
      Ui.push(tostring(monName) .. " won't leave your side!")
      return false
    end
    local session = SP.session()
    if type(session) ~= "table" then return false end
    local Bag = SP.require("src.core.game3.bag")
    if type(Bag) ~= "table" or type(Bag.add) ~= "function"
        or type(Bag.canAdd) ~= "function" then
      return false
    end
    local bag = session.bag
    if type(SP.takeSpeciesConvert) == "function" then
      local _, extra = SP.try(SP.takeSpeciesConvert, mon)
      if type(extra) == "table" and tonumber(extra.id) ~= nil then
        rewards[#rewards + 1] = { id = extra.id,
          qty = math.max(1, math.floor(tonumber(extra.qty) or 1)) }
      end
    end
    for _, r in ipairs(rewards) do
      local _, fits = SP.try(Bag.canAdd, bag, r.id, r.qty)
      if fits ~= true then return false end
    end
    if #rewards == 0 then
      if res.pending then
        res.pending = nil
      else
        local party = session.party
        if type(party) == "table" then
          for i = #party, 1, -1 do
            if party[i] == mon then
              table.remove(party, i)
              break
            end
          end
        end
      end
      local monName = (type(mon) == "table" and mon.name) or "POKéMON"
      local Pokemon = SP.require("src.core.game3.pokemon")
      if type(Pokemon) == "table"
          and type(Pokemon.displayMonName) == "function" then
        local ok, nm = pcall(Pokemon.displayMonName, mon)
        if ok and type(nm) == "string" and nm ~= "" then monName = nm end
      end
      res.location = "party"
      Ui.push("Released " .. tostring(monName) .. "!")
      B._phase = "catch_pc_msg"
      converted = true
      return true
    end
    local droppedPending = false
    local droppedIndex = nil
    if res.pending then
      res.pending = nil
      droppedPending = true
    else
      local party = session.party
      if type(party) == "table" then
        for i = #party, 1, -1 do
          if party[i] == mon then
            table.remove(party, i)
            droppedIndex = i
            break
          end
        end
      end
    end
    local granted = true
    for _, r in ipairs(rewards) do
      local _, added = SP.try(Bag.add, bag, r.id, r.qty)
      if added ~= true then granted = false end
    end
    if not granted then
      if droppedPending then
        res.pending = true
      elseif droppedIndex ~= nil and type(session.party) == "table" then
        table.insert(session.party, math.min(droppedIndex, #session.party + 1), mon)
      end
      return false
    end
    res.location = "party"
    Ui.push("You found " .. CD.rewardText(rewards) .. "!")
    B._phase = "catch_pc_msg"
    converted = true
    return true
  end
  local function reset()
    pendingLearn = nil
  end
  local function resetConvert()
    converted = false
  end
  local function releasable(mon)
    if type(mon) ~= "table" or mon.isEgg then return false end
    if type(SP.isPartnerMon) == "function" then
      local okP, p = pcall(SP.isPartnerMon, mon)
      if okP and p then return false end
    end
    return true
  end
  local function releaseBundle(mon)
    local extra = nil
    if SP.opt("exp_candy", true) ~= false
        and type(CD.rewardsFor) == "function"
        and type(SP.cleanName) == "function"
        and type(SP.isLegendary) == "function" then
      local species = mon.species or mon.speciesId
      local lvl = math.max(1, math.min(100,
        math.floor(tonumber(mon.level) or 1)))
      local okR, v = pcall(CD.rewardsFor, species,
        SP.cleanName(mon, species), lvl, SP.isLegendary(species))
      if okR and type(v) == "table" then extra = v end
    end
    return extra
  end
  local function wrapRelease()
    local RS = SP.require("src.ui.game3.release_seq")
    if type(RS) ~= "table" or type(RS.start) ~= "function" then
      return false
    end
    if not SP.claim(RS, "__spReleaseCandyWrapped") then return true end
    local native = RS.start
    RS.start = function(opts)
      if type(opts) == "table"
          and type(opts.onComplete) == "function" then
        local mon = opts.mon
        local sess = opts.session
        local cb = opts.onComplete
        opts.onComplete = function(released)
          pcall(function()
            if released == true and releasable(mon)
                and type(SP.awardOverworldCandy) == "function" then
              pcall(SP.awardOverworldCandy,
                type(sess) == "table" and sess or SP.session(),
                mon, math.floor(tonumber(mon.level) or 1),
                false, releaseBundle(mon), true)
            end
          end)
          return cb(released)
        end
      end
      return native(opts)
    end
    return true
  end
  local function wasConverted()
    return converted
  end
  SP.candyFlow = {
    useCandy = useCandy,
    convertRes = convertRes,
    wasConverted = wasConverted,
    resetConvert = resetConvert,
    wrapUse = wrapUse,
    wrapTarget = wrapTarget,
    wrapPartyMsg = wrapPartyMsg,
    wrapRelease = wrapRelease,
    reset = reset,
  }
  mod.log:info("safari-plus: candy flow installed")
end
