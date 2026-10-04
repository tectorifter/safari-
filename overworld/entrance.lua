return function(mod)
  local SP = mod.exports.safariPlus
  if not SP then return end
  local function normMap(m)
    return tostring(m or ""):upper():gsub("-", "_")
  end
  local function isSouthMap(m)
    return normMap(m):find("SAFARI_ZONE_SOUTH", 1, true) ~= nil
  end
  local function mentions(v, words, depth)
    if depth > 2 then return false end
    if type(v) == "string" then
      local s = v:upper()
      for _, w in ipairs(words) do
        if s:find(w, 1, true) ~= nil then return true end
      end
      return false
    end
    if type(v) == "table" then
      for _, sub in pairs(v) do
        if mentions(sub, words, depth + 1) then return true end
      end
    end
    return false
  end
  local function isGuardEo(eo)
    if type(eo) ~= "table" then return false end
    return mentions(eo.scriptKey, { "SAFARI" }, 0)
      or mentions(eo.def, { "SAFARI" }, 0)
      or mentions(eo.scriptKey, { "EXIT", "RETIRE", "TIMESUP",
        "TIMES_UP", "OUTOFBALL", "OUT_OF_BALL" }, 0)
      or mentions(eo.def, { "EXIT", "RETIRE", "TIMESUP",
        "TIMES_UP", "OUTOFBALL", "OUT_OF_BALL" }, 0)
  end
  local DOOR_X, DOOR_Y = 32, 33
  local DOOR_R = 2
  local LIFT = 6
  local SHIFT = 1
  local function doorDist(eo)
    local ex = tonumber(eo.cellX) or tonumber(eo.x)
    local ey = tonumber(eo.cellY) or tonumber(eo.y)
    if not (ex and ey) then return nil end
    return math.max(math.abs(ex - DOOR_X), math.abs(ey - DOOR_Y))
  end
  local function placeOne(lid, nx, ny)
    lid = tonumber(lid) or lid
    if lid == nil then return false end
    local ok, Objects = pcall(require, "src.core.game3.objects")
    if not (ok and Objects) then return false end
    local done = false
    pcall(function()
      if type(Objects.setObjectXY) == "function" then
        Objects.setObjectXY(lid, nx, ny)
        done = true
      else
        local eo = type(Objects.find) == "function"
          and Objects.find(lid) or nil
        if type(eo) == "table" then
          eo.cellX, eo.cellY = nx, ny
          eo.homeX, eo.homeY = nx, ny
          if eo.def then eo.def.x, eo.def.y = nx, ny end
          done = true
        end
      end
    end)
    return done
  end
  local movedGuards = {}
  local function moveOne(lid, eo)
    lid = tonumber(lid) or lid
    if lid == nil or type(eo) ~= "table" then return false end
    local ex = tonumber(eo.cellX) or tonumber(eo.x)
    local ey = tonumber(eo.cellY) or tonumber(eo.y)
    if not (ex and ey) then return false end
    local rec = movedGuards[lid]
    if rec == nil then
      rec = { ox = ex, oy = ey, nx = ex - SHIFT, ny = ey - LIFT }
      movedGuards[lid] = rec
    end
    if ex == rec.nx and ey == rec.ny then return true end
    return placeOne(lid, rec.nx, rec.ny)
  end
  local function restoreGuards(map)
    if next(movedGuards) == nil then return end
    local m = map
    if m == nil then
      local s = SP.session()
      m = s and s.map
    end
    if isSouthMap(m) then
      pcall(function()
        for lid, rec in pairs(movedGuards) do
          pcall(placeOne, lid, rec.ox, rec.oy)
        end
      end)
    end
    movedGuards = {}
  end
  local function clearDoorGuards(forceMap)
    if not SP.on() then restoreGuards() return end
    local s = SP.session()
    local m = forceMap or (s and s.map)
    if m == nil then return end
    if not isSouthMap(m) then restoreGuards(m) return end
    pcall(function()
      local Objects = require("src.core.game3.objects")
      if not (Objects and type(Objects.listActive) == "function"
          and type(Objects.find) == "function") then return end
      local pid = Objects.PLAYER_LOCAL_ID or 0xFF
      for _, lid in ipairs(Objects.listActive()) do
        lid = tonumber(lid) or lid
        if lid ~= pid then
          local eo = Objects.find(lid)
          if type(eo) == "table" then
            local rec = movedGuards[lid]
            if rec ~= nil then
              local ex = tonumber(eo.cellX) or tonumber(eo.x)
              local ey = tonumber(eo.cellY) or tonumber(eo.y)
              rec.nx, rec.ny = rec.ox - SHIFT, rec.oy - LIFT
              if ex == rec.ox and ey ~= rec.ny then
                placeOne(lid, rec.nx, rec.ny)
              end
            elseif isGuardEo(eo) then
              moveOne(lid, eo)
            else
              local dd = doorDist(eo)
              if dd ~= nil and dd <= DOOR_R then
                moveOne(lid, eo)
              end
            end
          end
        end
      end
    end)
  end
  local function wrapObjects()
    local okO, Objects = pcall(require, "src.core.game3.objects")
    if not (okO and Objects) then return false end
    if type(Objects.loadMap) == "function"
        and not Objects.__spLoadWrapped then
      Objects.__spLoadWrapped = true
      local native = Objects.loadMap
      Objects.loadMap = function(game, mapId, mapDef, ...)
        local a, b, c = native(game, mapId, mapDef, ...)
        if SP.on() then pcall(clearDoorGuards, mapId) end
        return a, b, c
      end
    end
    if type(Objects.spawnFromDefs) == "function"
        and not Objects.__spSpawnWrapped then
      Objects.__spSpawnWrapped = true
      local native = Objects.spawnFromDefs
      Objects.spawnFromDefs = function(defs, mapDef, mapId, ...)
        local a, b, c = native(defs, mapDef, mapId, ...)
        if SP.on() then pcall(clearDoorGuards, mapId) end
        return a, b, c
      end
    end
    if type(Objects.adoptPool) == "function"
        and not Objects.__spAdoptWrapped then
      Objects.__spAdoptWrapped = true
      local native = Objects.adoptPool
      Objects.adoptPool = function(pool, ...)
        local a, b, c = native(pool, ...)
        if SP.on() then pcall(clearDoorGuards) end
        return a, b, c
      end
    end
    return true
  end
  local function wrapZone()
    local okS, Safari = pcall(require, "src.core.game3.safari")
    if not (okS and Safari) then return false end
    if type(Safari.enter) == "function" and not Safari.__spEnterWrapped then
      Safari.__spEnterWrapped = true
      local native = Safari.enter
      Safari.enter = function(session, ...)
        if SP.on() then return false end
        return native(session, ...)
      end
    end
    return true
  end
  local SCRIPT_LABELS = {
    "Route121_SafariZoneEntrance_EventScript_EntranceCounterTrigger",
    "Route121_SafariZoneEntrance_EventScript_TryEnterSafariZone",
    "Route121_SafariZoneEntrance_EventScript_NoPokeblockCase",
    "Route121_SafariZoneEntrance_EventScript_ExitSafariZone",
  }
  local function scriptTargets()
    local out = {}
    pcall(function()
      local Space = require("src.core.game3.scripting.space")
      if not (Space and type(Space.scriptKey) == "function") then return end
      for _, label in ipairs(SCRIPT_LABELS) do
        local ok, k = pcall(Space.scriptKey, label)
        if ok and k ~= nil then out[k] = true end
      end
    end)
    return out
  end
  local function unlockField()
    pcall(function()
      local Field = package.loaded["src.core.game3.field"]
      if Field then
        if type(Field.unlock) == "function" then Field.unlock() end
        Field.locked = false
      end
    end)
  end
  local function wrapScripts()
    local okS, Space = pcall(require, "src.core.game3.scripting.space")
    if not (okS and Space) then return false end
    local function gate(key)
      if not SP.on() then return nil end
      if scriptTargets()[key] then
        unlockField()
        return false
      end
      return nil
    end
    if type(Space.startScript) == "function"
        and not Space.__spScriptWrapped then
      Space.__spScriptWrapped = true
      local native = Space.startScript
      Space.startScript = function(key, ...)
        local hit = gate(key)
        if hit ~= nil then return hit end
        return native(key, ...)
      end
    end
    if type(Space.runImmediately) == "function"
        and not Space.__spRunWrapped then
      Space.__spRunWrapped = true
      local native = Space.runImmediately
      Space.runImmediately = function(script, ...)
        local hit = gate(script)
        if hit ~= nil then return hit end
        return native(script, ...)
      end
    end
    return true
  end
  local function rearm()
    pcall(wrapZone)
    pcall(wrapScripts)
    pcall(wrapObjects)
    pcall(clearDoorGuards)
  end
  rearm()
  if mod.events and type(mod.events.on) == "function" then
    mod.events:on("save.loaded", rearm)
    mod.events:on("game.ready", rearm)
    mod.events:on("mods.loaded", rearm)
    mod.events:on("map.entered", function(ev)
      if type(ev) == "table" and ev.mapId ~= nil then
        pcall(clearDoorGuards, ev.mapId)
      else
        pcall(clearDoorGuards)
      end
    end)
    mod.events:on("mod.options_changed", function()
      pcall(clearDoorGuards)
    end)
  end
  mod.log:info("safari-plus: exit-door guard relocated")
end
