return function(mod)
  local SP = mod.exports.safariPlus
  if not SP then return end
  local okB, Bridge = pcall(require, "src.core.game3.battle_bridge")
  if okB and Bridge and type(Bridge.start) == "function"
      and not Bridge.__spSafariWrapped then
    Bridge.__spSafariWrapped = true
    local nativeStart = Bridge.start
    Bridge.start = function(mArg, game, foe, opts)
      local useOpts = opts
      pcall(function()
        if SP.on() and type(opts) == "table" and opts.wild and not opts.link then
          local skip = opts.tutorial == true
          if not skip and type(foe) == "table" then
            skip = (foe.oldMan or foe.pokedude or foe.tutorial) and true or false
            if not skip and type(foe.party) == "table" then skip = true end
          end
          if not skip and (opts.trainerId ~= nil
              or (type(foe) == "table" and foe.trainerId ~= nil)) then
            skip = true
          end
          if not skip then
            local copy = {}
            for k, v in pairs(opts) do copy[k] = v end
            copy.safari = true
            useOpts = copy
            SP.tick()
            SP.ensureStock()
          end
        end
      end)
      return nativeStart(mArg, game, foe, useOpts)
    end
  end
  if mod.events and type(mod.events.on) == "function" then
    mod.events:on("battle.started", function()
      pcall(SP.tick)
      pcall(SP.freeze)
    end)
    mod.events:on("battle.ended", function(ev)
      pcall(SP.thaw)
      pcall(function()
        if not SP.on() then return end
        local b = type(ev) == "table" and ev.battle or nil
        local sf = type(b) == "table" and b.safariState or nil
        if not (type(b) == "table" and b.safari and type(sf) == "table") then return end
        local s = SP.session()
        if not s then return end
        s.safari = type(s.safari) == "table" and s.safari or {}
        local left = tonumber(sf.balls)
        if left ~= nil then
          s.safari.balls = math.max(0, math.min(SP.cap(), math.floor(left)))
        end
        SP.persist()
      end)
    end)
  end
  local okS, Safari = pcall(require, "src.core.game3.safari")
  if okS and Safari and type(Safari.takeStep) == "function"
      and not Safari.__spTakeStepWrapped then
    Safari.__spTakeStepWrapped = true
    local nativeStep = Safari.takeStep
    Safari.takeStep = function(session, game, ...)
      pcall(SP.tick)
      if SP.on() then return false end
      return nativeStep(session, game, ...)
    end
  end
  mod.log:info("safari-plus: wild encounters diverted to safari scene")
end
