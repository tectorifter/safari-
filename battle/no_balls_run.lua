return function(mod)
  local SP = mod.exports.safariPlus
  if not SP then return end
  local converted = nil
  local noBalls = false
  local function battleState()
    local okB, B = pcall(require, "src.core.game3.battle")
    if okB and B and type(B.getState) == "function" then
      local ok, st = pcall(B.getState)
      if ok and type(st) == "table" then return st end
    end
    return nil
  end
  local function seFlee()
    pcall(function()
      local Audio = require("src.core.game3.audio")
      local SE = require("src.core.game3.se_ids")
      if Audio and Audio.playSe and SE and SE.SE_FLEE then
        Audio.playSe(SE.SE_FLEE)
      end
    end)
  end
  local function wrapSafari()
    local okS, Safari = pcall(require, "src.core.game3.safari")
    if not (okS and Safari) then return false end
    if type(Safari.endBattleRse) == "function" and not Safari.__spRunWrapped then
      Safari.__spRunWrapped = true
      local nativeEnd = Safari.endBattleRse
      Safari.endBattleRse = function(session, st, ...)
        if SP.on() and type(st) == "table" and st.safari then
          return false
        end
        return nativeEnd(session, st, ...)
      end
    end
    if type(Safari.outOfBallsMidBattle) == "function"
        and not Safari.__spMidWrapped then
      Safari.__spMidWrapped = true
      local nativeMid = Safari.outOfBallsMidBattle
      Safari.outOfBallsMidBattle = function(session, game, ...)
        if SP.on() and (noBalls or converted ~= nil) then
          converted = nil
          noBalls = false
          return true
        end
        return nativeMid(session, game, ...)
      end
    end
    return true
  end
  wrapSafari()
  local okT, BT = pcall(require, "src.core.game3.battle.battle_text")
  if okT and BT and type(BT.get) == "function" and not BT.__spRunWrapped then
    BT.__spRunWrapped = true
    local nativeGet = BT.get
    BT.get = function(id, fill, ...)
      if SP.on() and id == "STRINGID_OUTOFSAFARIBALLS" then
        local st = battleState()
        if st and st.safari then
          local ok, text = pcall(nativeGet, "STRINGID_GOTAWAYSAFELY", fill)
          if ok and type(text) == "string" and text ~= "" then
            if converted ~= st then
              converted = st
              seFlee()
            end
            noBalls = true
            return text
          end
        end
      end
      return nativeGet(id, fill, ...)
    end
  end
  if mod.events and type(mod.events.on) == "function" then
    mod.events:on("battle.started", function()
      converted = nil
      noBalls = false
      pcall(wrapSafari)
    end)
  end
  mod.log:info("safari-plus: out-of-balls runs away")
end
