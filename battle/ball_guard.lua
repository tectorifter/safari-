return function(mod)
  local SP = mod.exports.safariPlus
  if not SP then return end
  local function isTutorial(st)
    if st.oldManTutorial or st.pokedude then return true end
    if st.kinds and st.kinds.tutorial == "wally" then return true end
    return false
  end
  local function isZero(st)
    if not SP.on() then return false end
    if type(st) ~= "table" then return false end
    if not st.safari then return false end
    if type(st.safariState) ~= "table" then return false end
    if isTutorial(st) then return false end
    if st.over then return false end
    return (tonumber(st.safariState.balls) or 0) <= 0
  end
  local function battleMod()
    local okB, B = pcall(require, "src.core.game3.battle")
    if okB and type(B) == "table" then return B end
    return nil
  end
  local function currentState(B)
    if type(B) == "table" and type(B.getState) == "function" then
      local ok, st = pcall(B.getState)
      if ok and type(st) == "table" then return st end
    end
    local okU, Ui = pcall(require, "src.core.game3.battle.ui")
    if okU and type(Ui) == "table" and type(Ui._st) == "table" then
      return Ui._st
    end
    return nil
  end
  local function doFlee(B, st)
    if type(B) ~= "table" or type(st) ~= "table" then return false end
    local okU, Ui = pcall(require, "src.core.game3.battle.ui")
    local okT, BT = pcall(require, "src.core.game3.battle.battle_text")
    if okT and type(BT) == "table" and type(BT.get) == "function"
        and okU and type(Ui) == "table" and type(Ui.push) == "function" then
      pcall(function() Ui.push(BT.get("STRINGID_OUTOFSAFARIBALLS")) end)
    end
    B._actions = {}
    st.over = true
    st.result = "no_safari_balls"
    st.endReason = "no_safari_balls"
    B._pendingEnd = "no_safari_balls"
    B._phase = "ending"
    if okU and type(Ui) == "table" then
      pcall(function()
        Ui._pendingCommand = nil
        Ui._selCmd = nil
        Ui._mode = "none"
      end)
    end
    return true
  end
  local function wrapCatch()
    local okC, Catching = pcall(require, "src.core.game3.battle.catching")
    if not (okC and Catching and type(Catching.tryCatch) == "function") then
      return false
    end
    if Catching.__spBallGuardWrapped then return true end
    Catching.__spBallGuardWrapped = true
    local native = Catching.tryCatch
    Catching.tryCatch = function(itemId, foe, st, session, rng, ...)
      local blocked = false
      pcall(function()
        if not SP.on() then return end
        if type(st) ~= "table" or not st.safari then return end
        if type(st.safariState) ~= "table" then return end
        if isTutorial(st) then return end
        if (tonumber(st.safariState.balls) or 0) <= 0 then blocked = true end
      end)
      if blocked then return false, 0 end
      return native(itemId, foe, st, session, rng, ...)
    end
    return true
  end
  local function wrapSync()
    local B = battleMod()
    if not (B and type(B.safariSyncBalls) == "function") then
      return false
    end
    if B.__spBallGuardSyncWrapped then return true end
    B.__spBallGuardSyncWrapped = true
    local native = B.safariSyncBalls
    B.safariSyncBalls = function(st, ...)
      local r = native(st, ...)
      pcall(function()
        if not SP.on() then return end
        if type(st) ~= "table" or not st.safari then return end
        if type(st.safariState) ~= "table" then return end
        SP.setStock(math.max(0,
          math.floor(tonumber(st.safariState.balls) or 0)))
      end)
      return r
    end
    return true
  end
  local function wrapMenu()
    local okU, Ui = pcall(require, "src.core.game3.battle.ui")
    if not (okU and Ui and type(Ui.openMenu) == "function") then
      return false
    end
    if Ui.__spZeroMenuWrapped then return true end
    Ui.__spZeroMenuWrapped = true
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
    local okU, Ui = pcall(require, "src.core.game3.battle.ui")
    if not (okU and Ui and type(Ui.takeCommand) == "function") then
      return false
    end
    if Ui.__spZeroTakeWrapped then return true end
    Ui.__spZeroTakeWrapped = true
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
  local function wrapUpdate()
    local B = battleMod()
    if not (B and type(B.update) == "function") then
      return false
    end
    if B.__spZeroUpdateWrapped then return true end
    B.__spZeroUpdateWrapped = true
    local native = B.update
    B.update = function(...)
      pcall(function()
        if B._phase == "command" and isZero(currentState(B)) then
          doFlee(B, currentState(B))
        end
      end)
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
      pcall(wrapCatch)
      pcall(wrapSync)
      pcall(wrapMenu)
      pcall(wrapTake)
      pcall(wrapUpdate)
    end)
  end
  mod.log:info("safari-plus: ball guard installed")
end
