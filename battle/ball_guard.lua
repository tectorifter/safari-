return function(mod)
  local SP = mod.exports.safariPlus
  if not SP then return end
  -- Zero-ball guard: with no balls left the safari menu, a queued BALL
  -- command, and the per-frame update all end the battle through the
  -- run-away pipeline instead of letting a throw happen, and tryCatch
  -- refuses the roll outright.
  local function isZero(st, ignoreOver)
    if not SP.on() then return false end
    if type(st) ~= "table" then return false end
    if not st.safari then return false end
    if type(st.safariState) ~= "table" then return false end
    if not ignoreOver and st.over then return false end
    if (tonumber(st.safariState.balls) or 0) > 0 then return false end
    if SP.isTutorial(st) then return false end
    return true
  end
  local function battleMod()
    local B = SP.require("src.core.game3.battle")
    if type(B) == "table" then return B end
    return nil
  end
  local function currentState(B)
    if type(B) == "table" and type(B.getState) == "function" then
      local ok, st = pcall(B.getState)
      if ok and type(st) == "table" then return st end
    end
    local Ui = SP.require("src.core.game3.battle.ui")
    if Ui and type(Ui._st) == "table" then
      return Ui._st
    end
    return nil
  end
  local function doFlee(B, st)
    if type(B) ~= "table" or type(st) ~= "table" then return false end
    local Ui = SP.require("src.core.game3.battle.ui")
    local BT = SP.require("src.core.game3.battle.battle_text")
    if BT and type(BT.get) == "function"
        and Ui and type(Ui.push) == "function" then
      local _, text = SP.try(BT.get, "STRINGID_OUTOFSAFARIBALLS")
      if text ~= nil then SP.try(Ui.push, text) end
    end
    B._actions = {}
    st.over = true
    st.result = "no_safari_balls"
    st.endReason = "no_safari_balls"
    B._pendingEnd = "no_safari_balls"
    B._phase = "ending"
    if type(Ui) == "table" then
      Ui._pendingCommand = nil
      Ui._selCmd = nil
      Ui._mode = "none"
    end
    return true
  end
  local function wrapCatch()
    local Catching = SP.require("src.core.game3.battle.catching")
    if not (Catching and type(Catching.tryCatch) == "function") then
      return false
    end
    if not SP.claim(Catching, "__spBallGuardWrapped") then return true end
    local native = Catching.tryCatch
    Catching.tryCatch = function(itemId, foe, st, session, rng, ...)
      if isZero(st, true) then return false, 0 end
      return native(itemId, foe, st, session, rng, ...)
    end
    return true
  end
  local function wrapSync()
    local B = battleMod()
    if not (B and type(B.safariSyncBalls) == "function") then
      return false
    end
    if not SP.claim(B, "__spBallGuardSyncWrapped") then return true end
    local native = B.safariSyncBalls
    B.safariSyncBalls = function(st, ...)
      local r = native(st, ...)
      if SP.on() and type(st) == "table" and st.safari
          and type(st.safariState) == "table" then
        SP.setStock(math.max(0,
          math.floor(tonumber(st.safariState.balls) or 0)))
      end
      return r
    end
    return true
  end
  local function wrapMenu()
    local Ui = SP.require("src.core.game3.battle.ui")
    if not (Ui and type(Ui.openMenu) == "function") then return false end
    if not SP.claim(Ui, "__spZeroMenuWrapped") then return true end
    local native = Ui.openMenu
    Ui.openMenu = function(...)
      local st = currentState(battleMod())
      if isZero(st) then
        local B = battleMod()
        if B then doFlee(B, st) end
        return
      end
      return native(...)
    end
    return true
  end
  local function wrapTake()
    local Ui = SP.require("src.core.game3.battle.ui")
    if not (Ui and type(Ui.takeCommand) == "function") then return false end
    if not SP.claim(Ui, "__spZeroTakeWrapped") then return true end
    local native = Ui.takeCommand
    Ui.takeCommand = function(...)
      local cmd = native(...)
      if type(cmd) == "table" and cmd.kind == "safari" then
        local B = battleMod()
        local st = currentState(B)
        if B and isZero(st) then
          doFlee(B, st)
          return nil
        end
      end
      return cmd
    end
    return true
  end
  local function checkZero(B)
    if B._phase == "command" then
      local st = currentState(B)
      if isZero(st) then doFlee(B, st) end
    end
  end
  local function wrapUpdate()
    local B = battleMod()
    if not (B and type(B.update) == "function") then
      return false
    end
    if not SP.claim(B, "__spZeroUpdateWrapped") then return true end
    local native = B.update
    B.update = function(...)
      checkZero(B)
      return native(...)
    end
    return true
  end
  wrapCatch()
  wrapSync()
  wrapMenu()
  wrapTake()
  wrapUpdate()
  if mod.events and type(mod.events.on) == "function" then
    mod.events:on("battle.started", function()
      wrapCatch()
      wrapSync()
      wrapMenu()
      wrapTake()
      wrapUpdate()
    end)
  end
  mod.log:info("safari-plus: ball guard installed")
end
