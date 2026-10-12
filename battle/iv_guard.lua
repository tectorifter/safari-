return function(mod)
  local SP = mod.exports.safariPlus
  if not SP then return end
  -- Duplicate catches with at least IV GUARD perfect stats ask to keep
  -- first (Yes falls through to the stock nickname prompt, No to the
  -- candy question). Wraps outside the candy wrap so it sees the
  -- nickname prompt first.
  local IV_KEYS = { "hp", "atk", "def", "spe", "spa", "spd" }
  local function guardThreshold()
    local n = math.floor(tonumber(SP.opt("iv_guard", 3)) or 3)
    if n < 1 then return 1 end
    if n > 6 then return 6 end
    return n
  end
  local function perfectCount(mon)
    if type(mon) ~= "table" or type(mon.ivs) ~= "table" then return 0 end
    local n = 0
    for _, k in ipairs(IV_KEYS) do
      if tonumber(mon.ivs[k]) == 31 then n = n + 1 end
    end
    return n
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
  local function monName(mon)
    local nm = nil
    local Pokemon = SP.require("src.core.game3.pokemon")
    if Pokemon and type(Pokemon.displayMonName) == "function" then
      local ok, v = pcall(Pokemon.displayMonName, mon)
      if ok then nm = v end
    end
    if type(nm) == "string" and nm ~= "" then return nm end
    return "This POKéMON"
  end
  local function wrapAsk()
    local Ui = SP.require("src.core.game3.battle.ui")
    if type(Ui) ~= "table" or type(Ui.askYesNo) ~= "function" then return false end
    if not SP.claim(Ui, "__spIvGuardWrapped") then return true end
    local innerAsk = Ui.askYesNo
    Ui.askYesNo = function(a, b)
      local cb = (type(a) == "function") and a or b
      local prompt = (type(a) == "string") and a or nil
      local B, st, res, count = nil, nil, nil, 0
      local protect = false
      if SP.on() and type(prompt) == "string" and type(cb) == "function" then
        B = battleMod()
        if B ~= nil and not B._headless and B._phase == "catch_nickname_prompt" then
          st = B._st
          if type(st) == "table" and not SP.isTutorial(st) then
            res = liveCatchRes()
            if type(res) == "table" and res.success and not res.firstTimeCaught
                and not res.spCandyAsked and type(res.mon) == "table" then
              local LearnMove = SP.require("src.core.game3.battle.learn_move")
              local busy = false
              if type(LearnMove) == "table" and type(LearnMove.busy) == "function" then
                local okB, v = pcall(LearnMove.busy)
                busy = okB and v or false
              end
              if not busy then
                count = perfectCount(res.mon)
                if count >= guardThreshold() then protect = true end
              end
            end
          end
        end
      end
      if not protect then
        return innerAsk(a, b)
      end
      local kept = res
      local mon = res.mon
      local n = count
      innerAsk(monName(mon) .. " has " .. tostring(n)
        .. (n == 1 and " perfect IV!" or " perfect IVs!")
        .. "\nKeep it?", function(yes)
        if not B._active then return end
        if yes then
          kept.spCandyAsked = true
          innerAsk(prompt, cb)
          return
        end
        innerAsk(a, b)
      end)
      return
    end
    return true
  end
  local installed = wrapAsk()
  if mod.events and type(mod.events.on) == "function" then
    mod.events:on("battle.started", function()
      if not installed then
        installed = wrapAsk()
      end
    end)
  end
  mod.log:info("safari-plus: iv guard installed")
end
