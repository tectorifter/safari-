return function(mod)
  local SP = mod.exports.safariPlus
  if not SP then return end
  local function normMap(m)
    return tostring(m or ""):upper():gsub("-", "_")
  end
  local function isEntranceMap(m)
    local s = normMap(m)
    if s == "EM_ROUTE121_SAFARI_ZONE_ENTRANCE" then return true end
    if s == "EM_ROUTE121_SAFARI_ZONE_ENTRACE" then return true end
    return false
  end
  local function mentionsSafari(v, depth)
    if depth > 2 then return false end
    if type(v) == "string" then
      return v:upper():find("SAFARI", 1, true) ~= nil
    end
    if type(v) == "table" then
      for _, sub in pairs(v) do
        if mentionsSafari(sub, depth + 1) then return true end
      end
    end
    return false
  end
  local function entranceRelated(eo)
    if type(eo) ~= "table" then return false end
    if mentionsSafari(eo.scriptKey, 0) then return true end
    if mentionsSafari(eo.def, 0) then return true end
    return false
  end
  local function findEo(...)
    for i = 1, select("#", ...) do
      local a = select(i, ...)
      if type(a) == "table" and (a.def or a.scriptKey or a.localId) then
        return a
      end
    end
    return nil
  end
  if mod.hooks and type(mod.hooks.wrap) == "function" then
    pcall(function()
      mod.hooks:wrap("world.talk", function(nextFn, ...)
        if type(nextFn) ~= "function" then return end
        if not SP.on() then return nextFn(...) end
        local s = SP.session()
        if not isEntranceMap(s and s.map) then return nextFn(...) end
        if not entranceRelated(findEo(...)) then return nextFn(...) end
        return nil
      end)
    end)
  end
  mod.log:info("safari-plus: safari entrance desk disabled")
end
