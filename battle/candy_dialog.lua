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
      local POUCH = CD.POUCH
      if POUCH ~= nil and tonumber(id) == math.floor(tonumber(POUCH.id) or 0) then
        return {
          id = POUCH.id,
          name = POUCH.name or "CANDY POUCH",
          pocket = "ITEMS",
          fieldUse = "pouch",
          price = 0,
          description = "Holds all your candies. Use to open it.",
        }
      end
      local def = SP.candyDef(id)
      if def then
        if def.kind == "species" then
          return {
            id = def.id,
            name = def.name,
            pocket = "ITEMS",
            fieldUse = "species_candy",
            price = def.price or 500,
            description = "A candy of the "
              .. tostring(def.lineName or "same")
              .. " line. Raises the lowest IV: 1 candy at 1-10,"
              .. " 3 at 11-20, 5 at 21-30, 10 for 30-31.",
          }
        end
        if def.evStat ~= nil then
          local label = (CD.STAT_LABEL
            and CD.STAT_LABEL[def.evStat]) or def.evStat:upper()
          local win = type(def.size) == "string" and CD.STAT_WINDOW
            and CD.STAT_WINDOW[def.size] or nil
          local desc = "Gives +4 " .. tostring(label) .. " EVs."
          if type(win) == "table" then
            desc = desc .. " Works at "
              .. tostring(math.floor(tonumber(win.lo) or 0)) .. "-"
              .. tostring(math.floor(tonumber(win.hi) or 0)) .. " EVs."
          end
          return {
            id = def.id,
            name = def.name,
            pocket = "ITEMS",
            fieldUse = "stat_candy",
            price = def.price or def.ev,
            description = desc,
          }
        end
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
      -- The IV guard's own keep question passes through this (inner)
      -- ask on its way out: show it untouched. Without this the
      -- phase + catch-result check below hijacks it into a candy
      -- exchange, consuming spCandyAsked before the guard resolves.
      if SP.ivGuardAsking == true then
        return nativeAsk(a, b)
      end
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
      local expOn = SP.opt("exp_candy", true) ~= false
      local rewards = {}
      if expOn then
        rewards = CD.rewardsFor(species, SP.cleanName(mon, species),
          tonumber(mon.level) or 1, SP.isLegendary(species))
      end
      local prompt = "You already have a copy of this POKéMON.\nRelease it?"
      if expOn then
        prompt = "You already have a copy of this POKéMON.\nExchange it for an EXP CANDY?"
      end
      nativeAsk(prompt,
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
