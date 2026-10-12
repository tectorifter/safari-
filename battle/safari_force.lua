return function(mod)
  local SP = mod.exports.safariPlus
  if not SP then return end
  -- Wild and fated encounters run on the native Safari scene (a copy
  -- of opts, so the caller's table never leaks safari mode into the
  -- next trainer battle). Tutorials, links and trainer parties pass
  -- through untouched.
  local Bridge = SP.require("src.core.game3.battle_bridge")
  if type(Bridge) == "table" and type(Bridge.start) == "function"
      and SP.claim(Bridge, "__spSafariWrapped") then
    local nativeStart = Bridge.start
    Bridge.start = function(mArg, game, foe, opts)
      local useOpts = opts
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
          if type(opts.done) == "function" then
            local origDone = opts.done
            copy.done = function(result) return origDone(SP.chainResult(result)) end
          end
          useOpts = copy
          SP.tick()
          SP.ensureStock()
        end
      end
      return nativeStart(mArg, game, foe, useOpts)
    end
  end
  if mod.events and type(mod.events.on) == "function" then
    mod.events:on("battle.started", function()
      SP.tick()
      SP.freeze()
    end)
    mod.events:on("battle.ended", function(ev)
      SP.thaw()
      if SP.on() then
        local b = type(ev) == "table" and ev.battle or nil
        local sf = type(b) == "table" and b.safariState or nil
        if type(b) == "table" and b.safari and type(sf) == "table" then
          local s = SP.session()
          if s then
            s.safari = type(s.safari) == "table" and s.safari or {}
            local left = tonumber(sf.balls)
            if left ~= nil then
              s.safari.balls = math.max(0, math.min(SP.cap(), math.floor(left)))
            end
            SP.persist()
          end
        end
      end
    end)
  end
  mod.log:info("safari-plus: wild encounters diverted to safari scene")
end
