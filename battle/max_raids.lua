return function(mod)
  local SP = mod.exports.safariPlus
  if not SP then return end
  local function ensure()
    local h = nil
    pcall(function()
      if mod.find ~= nil then h = mod.find("max_raids") end
    end)
    local rw = type(h) == "table" and h.exports
      and h.exports._test and h.exports._test.rewards or nil
    if type(rw) ~= "table"
        or type(rw.chance) ~= "function"
        or type(rw.throw) ~= "function" then
      return false
    end
    if not SP.claim(rw, "__spCatch100Wrapped") then return true end
    rw.chance = function() return 100 end
    return true
  end
  SP.ensureMaxRaids = ensure
  ensure()
  if mod.events and type(mod.events.on) == "function" then
    mod.events:on("save.loaded", function()
      pcall(ensure)
    end)
    mod.events:on("map.entered", function()
      pcall(ensure)
    end)
  end
  mod.log:info("safari-plus: max raids catch installed")
end
