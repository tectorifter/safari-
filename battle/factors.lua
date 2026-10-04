return function(mod)
  local SP = mod.exports.safariPlus
  if not SP then return end
  local okR, Rules = pcall(require, "src.core.game3.battle.rules")
  if not (okR and Rules and type(Rules.safari) == "table") then
    mod.log:warn("safari-plus: factors not installed -- no safari rules")
    return
  end
  local RS = Rules.safari
  local function stockOr(fallback)
    local s = SP.session()
    local b = s and s.safari and tonumber(s.safari.balls)
    if b ~= nil then return math.max(0, math.floor(b)) end
    return fallback
  end
  if type(RS.newStateRse) == "function" and not RS.__spRseWrapped then
    RS.__spRseWrapped = true
    local native = RS.newStateRse
    RS.newStateRse = function(catchRate, cfg, ...)
      local st = native(catchRate, cfg, ...)
      if type(st) == "table" then
        st.balls = stockOr(tonumber(cfg and cfg.balls) or SP.BALL_START)
      end
      return st
    end
  end
  if type(RS.newState) == "function" and not RS.__spNewWrapped then
    RS.__spNewWrapped = true
    local native = RS.newState
    RS.newState = function(catchRate, fleeRate, ...)
      local st = native(catchRate, fleeRate, ...)
      if type(st) == "table" then
        st.balls = stockOr(RS.BALLS or SP.BALL_START)
      end
      return st
    end
  end
  if type(RS.ballCatchRate) == "function" and not RS.__spRateWrapped then
    RS.__spRateWrapped = true
    local native = RS.ballCatchRate
    RS.ballCatchRate = function(sf, ...)
      local base = tonumber(native(sf, ...)) or 0
      if SP.on() then base = base + SP.catchBonus() end
      return base
    end
  end
  local function speciesBST()
    local bst = nil
    pcall(function()
      local B = require("src.core.game3.battle")
      local st = B and type(B.getState) == "function" and B.getState() or nil
      local foe = type(st) == "table" and st.enemy or nil
      if type(foe) ~= "table" then return end
      local mon = foe.mon
      local sid = tonumber(foe.species
        or (type(mon) == "table" and (mon.species or mon.speciesId))
        or foe.speciesId)
      if sid == nil then return end
      local Pokemon = require("src.core.game3.pokemon")
      local tab = Pokemon and type(Pokemon.stats) == "function"
        and Pokemon.stats(sid) or nil
      if type(tab) ~= "table" then return end
      local total = (tonumber(tab.hp) or 0) + (tonumber(tab.atk) or 0)
        + (tonumber(tab.def) or 0) + (tonumber(tab.spe) or 0)
        + (tonumber(tab.spa) or 0) + (tonumber(tab.spd) or 0)
      if total > 0 then bst = total end
    end)
    return bst
  end
  if type(RS.fleeRate) == "function" and not RS.__spFleeWrapped then
    RS.__spFleeWrapped = true
    local native = RS.fleeRate
    RS.fleeRate = function(sf, ...)
      if SP.on() then
        local bst = speciesBST()
        if bst ~= nil then
          local like = tonumber(SP.likeValue()) or 1
          if not (like > 0) then like = 1 end
          return ((bst / 100) / like) * 5
        end
        if type(sf) == "table" and sf.rse then
          local eff = math.max(0.1,
            (tonumber(sf.escapeFactor) or 0) - SP.likeCut())
          return eff * 5
        end
      end
      local base = tonumber(native(sf, ...)) or 0
      if SP.on() then base = math.max(0.5, base - SP.likeCut() * 5) end
      return base
    end
  end
  mod.log:info("safari-plus: catch/escape factors installed")
end
