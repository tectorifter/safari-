return function(mod)
  local SP = mod.exports.safariPlus
  if not SP then return end
  local CD = assert(SP.candyData)
  local function wrapInfo(refresh)
    local ItemsData = SP.require("src.core.game3.items_data")
    if type(ItemsData) ~= "table" or type(ItemsData.info) ~= "function" then
      return false
    end
    if not SP.claim(ItemsData, "__spCandyInfoWrapped") then return true end
    local native = ItemsData.info
    ItemsData.info = function(id, ...)
      if type(refresh) == "function" then refresh() end
      local def = SP.candyDef(id)
      if def then
        return {
          id = def.id,
          name = def.name,
          pocket = "ITEMS",
          fieldUse = "exp_candy",
          price = def.xp,
          description = "Gives " .. tostring(def.xp) .. " Exp. Points.",
        }
      end
      return native(id, ...)
    end
    return true
  end
  local function battleMod()
    local B = SP.require("src.core.game3.battle")
    if type(B) == "table" then return B end
    return nil
  end
  local function liveCatchRes()
    local CS = SP.require("src.core.game3.battle.catch_seq")
    if type(CS) == "table" and type(CS.catchResult) == "function" then
      local okR, res = pcall(CS.catchResult)
      if okR then return res end
    end
    return nil
  end
  local function wrapUi(convertRes, refresh)
    local Ui = SP.require("src.core.game3.battle.ui")
    if type(Ui) ~= "table" or type(Ui.askYesNo) ~= "function" then return false end
    if not SP.claim(Ui, "__spCandyAskWrapped") then return true end
    local nativeAsk = Ui.askYesNo
    Ui.askYesNo = function(a, b)
      if type(refresh) == "function" then refresh() end
      local cb = (type(a) == "function") and a or b
      local prompt = (type(a) == "string") and a or nil
      local divert = false
      local B, st, res = nil, nil, nil
      if SP.on() and type(prompt) == "string" and type(cb) == "function" then
        B = battleMod()
        if B ~= nil and not B._headless and B._phase == "catch_nickname_prompt" then
          st = B._st
          if type(st) == "table" and not SP.isTutorial(st) then
            res = liveCatchRes()
            if type(res) == "table" and res.success and not res.firstTimeCaught
                and not res.spCandyAsked and type(res.mon) == "table"
                and not SP.isShiny(res.mon) then
              local LearnMove = SP.require("src.core.game3.battle.learn_move")
              local busy = false
              if LearnMove and type(LearnMove.busy) == "function" then
                local okB, v = pcall(LearnMove.busy)
                busy = okB and v or false
              end
              divert = not busy
            end
          end
        end
      end
      if not divert then
        return nativeAsk(a, b)
      end
      res.spCandyAsked = true
      local caughtState = st
      local mon = res.mon
      local species = mon.species or mon.speciesId
      local rewards = CD.rewardsFor(species, SP.cleanName(mon, species),
        tonumber(mon.level) or 1, SP.isLegendary(species))
      nativeAsk("You already have a copy of this POKéMON.\nExchange it for an EXP CANDY?",
        function(yes)
          if not B._active or B._st ~= caughtState
              or B._phase ~= "catch_nickname_prompt" then
            return
          end
          if not yes then
            nativeAsk(prompt, cb)
            return
          end
          local _, done = SP.try(convertRes, B, Ui, res, mon, rewards)
          if not done then
            nativeAsk(prompt, cb)
          end
        end)
      return
    end
    return true
  end
  SP.candyDialog = {
    wrapInfo = wrapInfo,
    wrapUi = wrapUi,
  }
  mod.log:info("safari-plus: candy dialogue installed")
end
