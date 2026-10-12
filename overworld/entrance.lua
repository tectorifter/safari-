return function(mod)
  local SP = mod.exports.safariPlus
  if not SP then return end
  -- The exit-door guard on the zone south map is parked out of the way
  -- while the mod is on (and restored on leaving/switching off), the
  -- timed zone game can't start, and the entrance-desk scripts are
  -- swallowed with the field unlocked: walk past with no fee.
  local function normMap(m)
    return tostring(m or ""):upper():gsub("-", "_")
  end
  local function isSouthMap(m)
    return normMap(m):match("SAFARI_ZONE_SOUTH$") ~= nil
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
    local Objects = SP.require("src.core.game3.objects")
    if type(Objects) ~= "table" then return false end
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
    local fresh = (rec == nil)
    if rec == nil then
      rec = { ox = ex, oy = ey, nx = ex - SHIFT, ny = ey - LIFT }
      movedGuards[lid] = rec
    end
    if ex == rec.nx and ey == rec.ny then return true end
    local done = placeOne(lid, rec.nx, rec.ny)
    if done and fresh then
      mod.log:info("safari-plus: parked door guard %s sk=%s",
        tostring(lid), tostring(eo.scriptKey))
    end
    return done
  end
  local function restoreGuards(map)
    if next(movedGuards) == nil then return end
    local m = map
    if m == nil then
      local s = SP.session()
      m = s and s.map
    end
    if isSouthMap(m) then
      for lid, rec in pairs(movedGuards) do
        placeOne(lid, rec.ox, rec.oy)
      end
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
      local Objects = SP.require("src.core.game3.objects")
      if type(Objects) ~= "table" then return end
      if not (type(Objects.listActive) == "function"
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
    local Objects = SP.require("src.core.game3.objects")
    if type(Objects) ~= "table" then return false end
    if type(Objects.loadMap) == "function"
        and SP.claim(Objects, "__spLoadWrapped") then
      local native = Objects.loadMap
      Objects.loadMap = function(game, mapId, mapDef, ...)
        local a, b, c = native(game, mapId, mapDef, ...)
        if SP.on() then clearDoorGuards(mapId) end
        return a, b, c
      end
    end
    if type(Objects.spawnFromDefs) == "function"
        and SP.claim(Objects, "__spSpawnWrapped") then
      local native = Objects.spawnFromDefs
      Objects.spawnFromDefs = function(defs, mapDef, mapId, ...)
        local a, b, c = native(defs, mapDef, mapId, ...)
        if SP.on() then clearDoorGuards(mapId) end
        return a, b, c
      end
    end
    if type(Objects.adoptPool) == "function"
        and SP.claim(Objects, "__spAdoptWrapped") then
      local native = Objects.adoptPool
      Objects.adoptPool = function(pool, ...)
        local a, b, c = native(pool, ...)
        if SP.on() then clearDoorGuards() end
        return a, b, c
      end
    end
    return true
  end
  local function wrapZone()
    local Safari = SP.require("src.core.game3.safari")
    if type(Safari) ~= "table" then return false end
    if type(Safari.enter) == "function" and SP.claim(Safari, "__spEnterWrapped") then
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
    local Space = SP.require("src.core.game3.scripting.space")
    if type(Space) == "table" and type(Space.scriptKey) == "function" then
      for _, label in ipairs(SCRIPT_LABELS) do
        local ok, k = pcall(Space.scriptKey, label)
        if ok and k ~= nil then out[k] = true end
      end
    end
    return out
  end
  local function unlockField()
    local Field = package.loaded["src.core.game3.field"]
    if type(Field) == "table" then
      if type(Field.unlock) == "function" then pcall(Field.unlock) end
      Field.locked = false
    end
  end
  local function wrapScripts()
    local Space = SP.require("src.core.game3.scripting.space")
    if type(Space) ~= "table" then return false end
    local function gate(key)
      if not SP.on() then return nil end
      if scriptTargets()[key] then
        unlockField()
        return false
      end
      return nil
    end
    if type(Space.startScript) == "function"
        and SP.claim(Space, "__spScriptWrapped") then
      local native = Space.startScript
      Space.startScript = function(key, ...)
        local hit = gate(key)
        if hit ~= nil then return hit end
        return native(key, ...)
      end
    end
    if type(Space.runImmediately) == "function"
        and SP.claim(Space, "__spRunWrapped") then
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
    wrapZone()
    wrapScripts()
    wrapObjects()
    clearDoorGuards()
  end
  rearm()
  if mod.events and type(mod.events.on) == "function" then
    mod.events:on("save.loaded", rearm)
    mod.events:on("game.ready", rearm)
    mod.events:on("mods.loaded", rearm)
    mod.events:on("map.entered", function(ev)
      if type(ev) == "table" and ev.mapId ~= nil then
        clearDoorGuards(ev.mapId)
      else
        clearDoorGuards()
      end
    end)
    mod.events:on("mod.options_changed", function()
      clearDoorGuards()
    end)
  end
  mod.log:info("safari-plus: exit-door guard relocated")
end
