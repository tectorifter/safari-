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
  local function clearZoneFlag()
    if not SP.on() then return end
    local s = SP.session()
    if not s then return end
    pcall(function()
      local BP = require("src.core.game3.battle.profile")
      local p = BP.get(s)
      local cfg = p and p.safari
      local Rse = require("src.core.game3.rse.init")
      local id = (cfg and Rse.flagId(cfg.flag, s)) or 0x800
      local Space = require("src.core.game3.scripting.space")
      local Flags = require("src.core.game3.scripting.flags")
      local st = Space.store
      local ctx = Space.vm and Space.vm.ctx
      Flags.setFlag(st, ctx, id, false)
      if type(s.flags) == "table" then s.flags[id] = nil end
    end)
  end
  local movedGuards = {}
  local restoring = false
  local function isSouthMap(m)
    return normMap(m):find("SAFARI_ZONE_SOUTH", 1, true) ~= nil
  end
  local function mentionsExit(v, depth)
    if depth > 2 then return false end
    if type(v) == "string" then
      local s = v:upper()
      return s:find("EXIT", 1, true) ~= nil
        or s:find("RETIRE", 1, true) ~= nil
        or s:find("TIMESUP", 1, true) ~= nil
        or s:find("TIMES_UP", 1, true) ~= nil
        or s:find("OUTOFBALL", 1, true) ~= nil
        or s:find("OUT_OF_BALL", 1, true) ~= nil
    end
    if type(v) == "table" then
      for _, sub in pairs(v) do
        if mentionsExit(sub, depth + 1) then return true end
      end
    end
    return false
  end
  local function isGuardEo(eo)
    if type(eo) ~= "table" then return false end
    return mentionsSafari(eo.scriptKey, 0)
      or mentionsSafari(eo.def, 0)
      or mentionsExit(eo.scriptKey, 0)
      or mentionsExit(eo.def, 0)
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
  local function restoreGuards()
    if next(movedGuards) == nil then return end
    restoring = true
    pcall(function()
      for lid, rec in pairs(movedGuards) do
        pcall(placeOne, lid, rec.ox, rec.oy)
      end
    end)
    restoring = false
    movedGuards = {}
  end
  local function clearDoorGuards(forceMap)
    if not SP.on() then restoreGuards() return end
    local s = SP.session()
    local m = forceMap or (s and s.map)
    if m == nil then return end
    if not isSouthMap(m) then restoreGuards() return end
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
    if type(Objects.forDraw) == "function"
        and not Objects.__spDrawWrapped then
      Objects.__spDrawWrapped = true
      local native = Objects.forDraw
      Objects.forDraw = function(...)
        if SP.on() and not restoring then
          pcall(clearDoorGuards)
        end
        return native(...)
      end
    end
    return true
  end
  local function eoLid(eo)
    if type(eo) ~= "table" then return nil end
    local l = eo.localId or (eo.def and (eo.def.localId or eo.def.index))
    return tonumber(l)
  end
  local function eoDist(eo)
    local ok, d = pcall(function()
      local Objects = require("src.core.game3.objects")
      local pid = Objects.PLAYER_LOCAL_ID or 0xFF
      local pe = Objects.find(pid)
      local ex = tonumber(eo.cellX) or tonumber(eo.x)
      local ey = tonumber(eo.cellY) or tonumber(eo.y)
      local px = tonumber(pe.cellX) or tonumber(pe.x)
      local py = tonumber(pe.cellY) or tonumber(pe.y)
      if not (ex and ey and px and py) then return nil end
      return math.max(math.abs(ex - px), math.abs(ey - py))
    end)
    if ok then return d end
    return nil
  end
  local function wrapZone()    local okS, Safari = pcall(require, "src.core.game3.safari")
    if not (okS and Safari) then return false end
    if type(Safari.enter) == "function" and not Safari.__spEnterWrapped then
      Safari.__spEnterWrapped = true
      local native = Safari.enter
      Safari.enter = function(session, ...)
        if SP.on() then return false end
        return native(session, ...)
      end
    end
    if type(Safari.exit) == "function" and not Safari.__spExitWrapped then
      Safari.__spExitWrapped = true
      local native = Safari.exit
      Safari.exit = function(session, ...)
        if SP.on() then return true end
        return native(session, ...)
      end
    end
    if type(Safari.exitToEntrance) == "function"
        and not Safari.__spExitToWrapped then
      Safari.__spExitToWrapped = true
      local native = Safari.exitToEntrance
      Safari.exitToEntrance = function(session, game, ...)
        if SP.on() then return true end
        return native(session, game, ...)
      end
    end
    if type(Safari.timesUp) == "function" and not Safari.__spTimesUpWrapped then
      Safari.__spTimesUpWrapped = true
      local native = Safari.timesUp
      Safari.timesUp = function(session, game, ...)
        if SP.on() then return true end
        return native(session, game, ...)
      end
    end
    if type(Safari.outOfBalls) == "function"
        and not Safari.__spOutOfBallsWrapped then
      Safari.__spOutOfBallsWrapped = true
      local native = Safari.outOfBalls
      Safari.outOfBalls = function(session, game, ...)
        if SP.on() then return true end
        return native(session, game, ...)
      end
    end
    if type(Safari.retirePrompt) == "function"
        and not Safari.__spRetireWrapped then
      Safari.__spRetireWrapped = true
      local native = Safari.retirePrompt
      Safari.retirePrompt = function(session, game, ...)
        if SP.on() then return true end
        return native(session, game, ...)
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
        if ok and k ~= nil then out[k] = "gate" end
      end
      local s = SP.session()
      if s then
        local okB, BP = pcall(require, "src.core.game3.battle.profile")
        local p = okB and BP and BP.get(s)
        local cfg = p and p.safari
        if type(cfg) == "table" then
          for _, f in ipairs({ "outOfBallsMidBattle", "outOfBalls",
              "retire", "timesUp" }) do
            if cfg[f] ~= nil then out[cfg[f]] = "zone" end
          end
        end
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
  local function intercept(key)
    if not SP.on() then return nil end
    local mode = scriptTargets()[key]
    if mode == nil then return nil end
    if mode == "gate" then
      local s = SP.session()
      if not isEntranceMap(s and s.map) then return nil end
    end
    unlockField()
    return false
  end
  local function wrapScripts()
    local okS, Space = pcall(require, "src.core.game3.scripting.space")
    if not (okS and Space) then return false end
    if type(Space.startScript) == "function"
        and not Space.__spScriptWrapped then
      Space.__spScriptWrapped = true
      local native = Space.startScript
      Space.startScript = function(key, ...)
        local hit = intercept(key)
        if hit ~= nil then return hit end
        return native(key, ...)
      end
    end
    if type(Space.runImmediately) == "function"
        and not Space.__spRunWrapped then
      Space.__spRunWrapped = true
      local native = Space.runImmediately
      Space.runImmediately = function(script, ...)
        local hit = intercept(script)
        if hit ~= nil then return hit end
        return native(script, ...)
      end
    end
    return true
  end
  wrapZone()
  pcall(wrapScripts)
  pcall(wrapObjects)
  pcall(clearDoorGuards)
  if mod.hooks and type(mod.hooks.wrap) == "function" then
    pcall(function()
      mod.hooks:wrap("world.talk", function(nextFn, ...)
        if type(nextFn) ~= "function" then return end
        if not SP.on() then return nextFn(...) end
        local s = SP.session()
        local m = s and s.map
        local eo = findEo(...)
        if isEntranceMap(m) then
          if entranceRelated(eo) then return nil end
          return nextFn(...)
        end
        if isSouthMap(m) and type(eo) == "table" then
          local lid = eoLid(eo)
          if lid and movedGuards[lid] then return nil end
          if isGuardEo(eo) then return nil end
          local d = eoDist(eo)
          if d ~= nil and d <= 1 then return nil end
        end
        return nextFn(...)
      end)
    end)
  end
  if mod.events and type(mod.events.on) == "function" then
    mod.events:on("save.loaded", function()
      pcall(wrapZone)
      pcall(wrapScripts)
      pcall(wrapObjects)
      pcall(clearZoneFlag)
      pcall(clearDoorGuards)
    end)
    mod.events:on("game.ready", function()
      pcall(wrapZone)
      pcall(wrapScripts)
      pcall(wrapObjects)
      pcall(clearDoorGuards)
    end)
    mod.events:on("map.entered", function(ev)
      if type(ev) == "table" and ev.mapId ~= nil then
        pcall(clearDoorGuards, ev.mapId)
      else
        pcall(clearDoorGuards)
      end
    end)
    mod.events:on("world.npc_spawned", function(ev)
      if not SP.on() then return end
      if type(ev) ~= "table" then pcall(clearDoorGuards) return end
      local mid = ev.mapId or ev.map
      if mid ~= nil and not isSouthMap(mid) then
        local s = SP.session()
        mid = s and s.map
      end
      if not isSouthMap(mid) then return end
      pcall(clearDoorGuards, mid)
    end)
    mod.events:on("mods.loaded", function()
      pcall(wrapZone)
      pcall(wrapScripts)
      pcall(wrapObjects)
      pcall(clearDoorGuards)
    end)
    mod.events:on("battle.started", function()
      pcall(wrapZone)
      pcall(wrapScripts)
      pcall(wrapObjects)
    end)
    mod.events:on("battle.ended", function()
      pcall(clearDoorGuards)
    end)
    mod.events:on("mod.options_changed", function()
      pcall(clearDoorGuards)
    end)
  end
  mod.log:info("safari-plus: safari entrance desk disabled")
end
