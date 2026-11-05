return function(mod)
  local SP = mod.exports.safariPlus
  if not SP then return end
-- Overworld catch: while the OVERWORLD toggle is on, tapping one of
-- Untamed's visible wild mons throws the equipped ball as a projectile
-- at that tile (predicted 3 tiles ahead max).
  -- The ball rocks on the ground (shakes from the real catch roll),
  -- goes still + fades on a catch, parked at the landing tile.
  -- The mon hides inside the ball until a break-out reveals it. Screen mapping comes from Untamed's own
  -- per-actor draw records (no sprite/player geometry assumed), and
  -- the tap hitbox covers the mon's whole VISIBLE sprite: Untamed
  -- draws each sprite feet-anchored (bottom at the tile bottom, top
  -- at tile bottom minus frame height), so for the usual 16x32 mon
  -- the tappable head is a full tile above the occupied tile — a
  -- tile-only hitbox misses every tap aimed at the creature itself.
  -- NOTHING is spawned here: the foe is the tapped actor itself
  -- (species/level/personality/moves), IVs roll at throw time exactly
  -- like bumping into it would, and a catch despawns that actor
  -- through Untamed's own Owe.remove. Break-outs leave it wandering.
  -- Rewards reuse the real pipeline: storeCaught (mastery +
  -- safari-XP wrappers fire; the cap award is flattened to +4 while
  -- our overworld flag is up), manual party EXP/EVs,
  -- SP.awardOverworldCandy for stat/species candy, and EXP-candy
  -- auto-conversion for unguarded duplicates. Results are HUD toasts
  -- only — no modal UI. One active sequence + a 1s wall-clock
  -- cooldown between throws. Requires Untamed-Advanced with OW
  -- encounters on; without it the toggle warns and idles.
  local BALL_ID = 5
  local THROW_COOLDOWN = 1
  local SHAKE_DUR = 0.5
  local STILL_DUR = 0.4
  local FADE_DUR = 0.5
  local function owOn()
    return SP.opt("overworld", false) == true
  end
  local function hudHidden()
    local s = SP.session()
    local v = s ~= nil and s.spOwHudHidden or nil
    if v == nil and type(SP.saveGet) == "function" then
      local ok, sv = pcall(SP.saveGet, "owHudHidden", false)
      if ok then v = sv end
    end
    return v == true
  end
  local function setHudHidden(hide)
    local v = hide == true
    pcall(function()
      local s = SP.session()
      if type(s) == "table" then s.spOwHudHidden = v end
    end)
    pcall(function()
      if type(SP.saveSet) == "function" then SP.saveSet("owHudHidden", v) end
    end)
  end
  local function gameClock()
    local hh, mm = nil, nil
    pcall(function()
      local Rtc = require("src.core.game3.rtc")
      local s = SP.session()
      if type(Rtc) == "table" and type(Rtc.enabled) == "function"
          and Rtc.enabled(s) and type(Rtc.calcLocalTime) == "function" then
        local t = Rtc.calcLocalTime(s)
        if type(t) == "table" then
          hh = tonumber(t.hours)
          mm = tonumber(t.minutes)
        end
      end
    end)
    if hh == nil or mm == nil then
      pcall(function()
        if type(os) == "table" and type(os.date) == "function" then
          local d = os.date("*t")
          if type(d) == "table" then
            hh = tonumber(d.hour)
            mm = tonumber(d.min)
          end
        end
      end)
    end
    if hh == nil then hh = 8 end
    if mm == nil then mm = 0 end
    return string.format("%02d:%02d", math.floor(hh) % 24, math.floor(mm) % 60)
  end
  local function speedup()
    return SP.opt("speedup", true) ~= false
  end
  local seq = nil
  local lastThrow = -10
  local lastMap = nil
  local toasts = {}
  local hudBox = nil
  local hudBerryBoxes = nil
  local hudEyeBox = nil
  local equippedId
  local equippedCount
  local throwBallName
  local firstOwnedBall
  local animT = 0
  local fontCache = nil
  local viewportCache = nil
  local oweVel = setmetatable({}, { __mode = "k" })
  local spawnSeen = setmetatable({}, { __mode = "k" })
  local WOH_AVAILABLE = "available"
  local WOH_STARTING = "encounter_starting"
  local wohHandle = nil
  local wohLogged = false
  local wohHiddenId = nil
  local wohSerial = 0
  local ownField = { vw = nil, vh = nil, camX = nil, camY = nil }
  local ueHandle = nil
  local ueLogged = false
  local warnedMap = nil
  local function toast(text, dur)
    if type(text) ~= "string" or text == "" then return end
    toasts[#toasts + 1] = { text = text, t = tonumber(dur) or 2.4 }
    while #toasts > 4 do table.remove(toasts, 1) end
  end
  local function skillOrder()
    if type(SP.ORDER) == "table" then return SP.ORDER end
    return { "catch", "like", "regen", "cap" }
  end
  local function skillLevels()
    local lv = {}
    if type(SP.count) ~= "function" then return lv end
    for _, skill in ipairs(skillOrder()) do
      lv[skill] = SP.count(skill)
    end
    return lv
  end
  local function toastLevelUps(before, beforeP)
    if type(before) ~= "table" then return end
    if type(SP.count) == "function" then
      for _, skill in ipairs(skillOrder()) do
        local now = SP.count(skill)
        if now > (tonumber(before[skill]) or 0) then
          toast("Safari " .. skill .. " up! Lv " .. now)
        end
      end
    end
    if type(SP.playerLevel) == "function" then
      local okP, nowP = pcall(SP.playerLevel)
      if okP and math.floor(tonumber(nowP) or 0)
          > math.floor(tonumber(beforeP) or 0) then
        toast("Player up! Lv " .. math.floor(nowP))
      end
    end
    if type(SP.playerTakePendingUps) == "function" then
      pcall(SP.playerTakePendingUps)
    end
  end
  local function toastAward(award)
    if type(award) ~= "table" or not award.ok then return end
    if type(award.texts) == "table" and #award.texts > 0 then
      for _, line in ipairs(award.texts) do
        if type(line) == "string" and line ~= "" then toast(line) end
      end
    elseif type(award.text) == "string" then
      toast(award.text)
    end
  end
  local function se(name)
    pcall(function()
      local SE = SP.require("src.core.game3.se_ids")
      local Audio = SP.require("src.core.game3.audio")
      if type(SE) == "table" and type(Audio) == "table"
          and type(Audio.playSe) == "function"
          and tonumber(SE[name]) ~= nil then
        Audio.playSe(SE[name])
      end
    end)
  end
  local function cry(species)
    pcall(function()
      local Audio = SP.require("src.core.game3.audio")
      if type(Audio) == "table"
          and type(Audio.playCry) == "function" then
        Audio.playCry(species)
      end
    end)
  end
  -- Untamed handle: resolved lazily (load order is not guaranteed),
  -- re-resolved while missing so a later load is picked up.
  local function untamedE()
    if type(ueHandle) == "table" and type(ueHandle.engine) == "table" then
      return ueHandle.engine
    end
    ueHandle = nil
    local ok, h = pcall(function() return mod.find("untamed_advanced") end)
    if not ok or type(h) ~= "table" then return nil end
    local ex = h.exports
    if type(ex) ~= "table" or type(ex.engine) ~= "table" then
      return nil
    end
    ueHandle = ex
    if not ueLogged then
      ueLogged = true
      mod.log:info("safari-plus: overworld catch linked Untamed %s",
        tostring(h.version))
    end
    return ex.engine
  end
  -- Wilds of Hoenn handle: same lazy pattern (it replaces
  -- Untamed's actor list with its own spawnManager entities).
  local function wohM()
    if type(wohHandle) == "table" and type(wohHandle.exports) == "table" then
      return wohHandle
    end
    wohHandle = nil
    local ok, h = pcall(function() return mod.find("wilds_of_hoenn") end)
    if not ok or type(h) ~= "table" then return nil end
    local ex = h.exports
    if type(ex) ~= "table" or ex.engineReady ~= true then
      return nil
    end
    wohHandle = h
    if not wohLogged then
      wohLogged = true
      mod.log:info("safari-plus: overworld catch linked Wilds of Hoenn %s",
        tostring(h.version))
    end
    return h
  end
  local function wohSM()
    local m = wohM()
    local sm = type(m) == "table" and type(m.exports) == "table"
      and m.exports.spawnManager or nil
    if type(sm) ~= "table" or type(sm.get) ~= "function" then return nil end
    return sm
  end
  -- active visible-mon provider: Untamed wins when both answer,
  -- Wilds of Hoenn otherwise. Nil means nothing to tap.
  local function provider()
    if untamedE() ~= nil then return "untamed" end
    if wohSM() ~= nil then return "woh" end
    return nil
  end
  -- Wilds of Hoenn entities carry species/level/personality/ivs
  -- where Untamed actors carry engineSpecies; slot marks Untamed.
  local function isWohEntity(a)
    return type(a) == "table" and tonumber(a.engineSpecies) == nil
      and tonumber(a.species) ~= nil
      and type(a.cellX) == "number" and a.slot == nil
  end
  local function untamedSuppress()
    local E = untamedE()
    if type(E) ~= "table" or type(E.C) ~= "table" then return false end
    return E.C.WE_OW_ENCOUNTERS == true
      and not E.C.WE_VANILLA_RANDOM
  end
  local function isTarget(a, isOWE)
    if type(a) ~= "table" then return false end
    if isWohEntity(a) then
      if a.state ~= WOH_AVAILABLE then return false end
      if a.defeated or a.runAway then return false end
      local fx = a.fx
      if type(fx) == "table"
          and (fx.under or fx.mode == "swoop" or fx.mode == "swim") then
        return false
      end
      if tonumber(a.species) == nil then return false end
      if tonumber(a.level) == nil then return false end
      if tonumber(a.px) == nil or tonumber(a.py) == nil then return false end
      return true
    end
    if (tonumber(a.slot) or 0) <= 1 then return false end
    if a.oweType ~= "generated" then return false end
    -- the engine only draws actors with visible set (its forDraw
    -- gate is active+visible+draw): anything else is an invisible
    -- wanderer and must never be tappable.
    if not a.visible then return false end
    if tonumber(a.engineSpecies) == nil then return false end
    if tonumber(a.level) == nil then return false end
    if type(isOWE) == "function" then return isOWE(a) == true end
    return a.active == true and a.uadv == true
  end
  local function engineTargets()
    local E = untamedE()
    return type(E) == "table" and type(E.actors) == "table"
      and type(E.Owe) == "table"
      and type(E.Owe.isOWE) == "function"
  end
  local function eachTarget(fn)
    if engineTargets() then
      local E = untamedE()
      local isOWE = E.Owe.isOWE
      for i = 1, #E.actors do
        local a = E.actors[i]
        if isTarget(a, isOWE) then fn(a) end
      end
      return
    end
    local sm = wohSM()
    if sm == nil or type(sm.order) ~= "table"
        or type(sm.entities) ~= "table" then
      return
    end
    for _, id in ipairs(sm.order) do
      local e = sm.entities[id]
      if isTarget(e) then fn(e) end
    end
  end
  -- removal through the provider itself when available
  -- (despawn FX, roamer bookkeeping, pending clear); otherwise the
  -- same slot clearing Untamed's own RemoveObjectEvent path performs.
  local function oweRemove(a)
    if isWohEntity(a) then
      if wohHiddenId == a.id then wohHiddenId = nil end
      pcall(function()
        local sm = wohSM()
        if sm ~= nil and type(sm.despawn) == "function" then
          sm:despawn(a.id)
        end
      end)
      return
    end
    local E = untamedE()
    if type(E) == "table" and type(E.Owe) == "table"
        and type(E.Owe.remove) == "function" then
      local ok = pcall(E.Owe.remove, a)
      if ok then return end
    end
    pcall(function()
      a.active, a.moving, a.oweType = false, false, nil
      a.species, a.engineSpecies, a.level, a.age, a.category =
        nil, nil, 0, 0, nil
      a.noDespawn, a.offScreen = false, false
    end)
  end
  local function rngInt(n)
    n = math.max(1, math.floor(tonumber(n) or 1))
    local Rng = SP.require("src.core.game3.rng")
    if type(Rng) == "table" and type(Rng.Random) == "function" then
      local ok, v = pcall(Rng.Random)
      if ok and tonumber(v) ~= nil then
        return math.floor(tonumber(v)) % n
      end
    end
    return math.floor(math.random() * n)
  end
  local function rngFn(lo, hi)
    lo = math.floor(tonumber(lo) or 0)
    hi = math.floor(tonumber(hi) or 255)
    if hi < lo then lo, hi = hi, lo end
    return lo + rngInt(hi - lo + 1)
  end
  local function playerPos()
    local P = SP.require("src.core.game3.player")
    if type(P) == "table" then
      local px, py = tonumber(P.px), tonumber(P.py)
      if px ~= nil and py ~= nil then
        return px, py, math.floor(px / 16), math.floor(py / 16),
          P.moving == true, P.surfing == true
      end
      local cx, cy = tonumber(P.cellX), tonumber(P.cellY)
      if cx ~= nil and cy ~= nil then
        return cx * 16, cy * 16, cx, cy, P.moving == true,
          P.surfing == true
      end
    end
    return nil
  end
  local function curMap()
    local M = SP.require("src.core.game3.map")
    if type(M) == "table" and type(M.current) == "string" then
      return M.current
    end
    local s = SP.session()
    if type(s) == "table" and type(s.map) == "string" then
      return s.map
    end
    return nil
  end
  -- draw gate: the field is settled (same checks as worldBusy, but
  -- walking is fine — the ball stays visible while moving, hidden in
  -- menus, scripts, battles and warps).
  local function fieldClear()
    local Field = SP.require("src.core.game3.field")
    if type(Field) ~= "table" or not Field.running then return false end
    if Field.locked then return false end
    local R = SP.require("src.core.game3.runtime")
    if type(R) == "table" and type(R.uiBusy) == "function" then
      local ok, busy = pcall(R.uiBusy)
      if ok and busy then return false end
    end
    local Sp = SP.require("src.core.game3.scripting.space")
    if type(Sp) == "table" then
      local vm = Sp.vm
      if type(vm) == "table" and type(vm.isRunning) == "function" then
        local ok, running = pcall(vm.isRunning, vm)
        if ok and running then return false end
      end
    end
    local B = SP.require("src.core.game3.battle.init")
      or SP.require("src.core.game3.battle")
    if type(B) == "table" and type(B.isActive) == "function" then
      local ok, active = pcall(B.isActive)
      if ok and active then return false end
    end
    local W = SP.require("src.core.game3.warp")
    if type(W) == "table" and type(W.isBusy) == "function" then
      local ok, busy = pcall(W.isBusy)
      if ok and busy then return false end
    end
    return true
  end
  -- EXACT screen mapping, no sprite/player assumptions: Untamed
  -- records every drawn OWE actor's origin (lastSx/lastSy =
  -- px-camX, py-camY) during the field draw, so camX = px-lastSx
  -- straight from a live actor. Freshest draw serial only —
  -- despawned actors keep stale values. Falls back to the player
  -- tile (exact while standing still) and then the old pixel
  -- formula; the fallback almost never matters (no drawn actor
  -- means nothing tappable and no live sequence).
  local function exactCam()
    local fresh, serial = nil, nil
    local function consider(a)
      if type(a) ~= "table" or not a.active then return end
      -- slot 1 is the follower (odd visibility rules); the camera
      -- must come from real OWE actors.
      if (tonumber(a.slot) or 0) <= 1 then return end
      local px, py = tonumber(a.px), tonumber(a.py)
      local sx, sy = tonumber(a.lastSx), tonumber(a.lastSy)
      local s = math.floor(tonumber(a.drawnAt) or -1)
      if px == nil or py == nil or sx == nil or sy == nil
          or s < 0 then
        return
      end
      if serial == nil or s > serial then
        serial = s
        fresh = { a }
      elseif s == serial then
        fresh[#fresh + 1] = a
      end
    end
    local E = untamedE()
    if type(E) == "table" and type(E.actors) == "table" then
      for i = 1, #E.actors do consider(E.actors[i]) end
    end
    if fresh ~= nil then
      -- consensus (median): live actors agree on the camera
      -- exactly; stale records are outliers and lose the vote.
      local cxs, cys = {}, {}
      for _, a in ipairs(fresh) do
        cxs[#cxs + 1] = a.px - a.lastSx
        cys[#cys + 1] = a.py - a.lastSy
      end
      table.sort(cxs)
      table.sort(cys)
      local mid = math.floor(#cxs / 2) + 1
      return cxs[mid], cys[mid]
    end
    if type(E) == "table"
        and type(E.playerCur) == "function" then
      local ok, cx, cy = pcall(E.playerCur)
      cx, cy = tonumber(cx), tonumber(cy)
      if cx ~= nil and cy ~= nil then
        return cx * 16 + 8 - 120, cy * 16 + 8 - 80
      end
    end
    local px, py, cx, cy, moving = playerPos()
    if px == nil then return nil end
    if not moving and cx ~= nil and cy ~= nil then
      return cx * 16 + 8 - 120, cy * 16 + 8 - 80
    end
    return math.floor(px + 8 - 120), math.floor(py + 8 - 80)
  end
  -- world-view correction (portrait): Untamed's draw records live in
  -- the WORLD canvas's pixels (FieldView.draw sizes camX/camY from
  -- the world view: cam = player+8-view/2), while taps arrive in
  -- the 240x160 UI canvas's pixels (hud viewport). When both match
  -- (landscape / flat present path) the correction measures ~0 and
  -- changes nothing; when portrait grows the world view (letterbox
  -- voids become more map), records sit (view-UI)/2 off — x stays
  -- right, taps land high. Measured live: the camera always
  -- centers the player, so view = 2*(player+8-cam). Returns
  -- cx, cy (UI px to add to a tap / subtract from a record) plus
  -- the measured vw, vh (nil when unobservable — callers fall back
  -- to the UI canvas, which is exactly right on the flat path).
  local function viewInfo()
    local camX, camY = exactCam()
    local px, py = playerPos()
    if camX == nil or camY == nil or px == nil or py == nil then
      return 0, 0, nil, nil
    end
    local vw = 2 * ((px + 8) - camX)
    local vh = 2 * ((py + 8) - camY)
    if vw < 80 or vw > 2000 or vh < 80 or vh > 2000 then
      return 0, 0, nil, nil
    end
    local cx, cy = (vw - 240) / 2, (vh - 160) / 2
    -- a real canvas growth is single-digit tiles; anything bigger
    -- is a bad sample (camera pan/transition), not a canvas.
    if math.abs(cx) > 80 then cx = 0 end
    if math.abs(cy) > 80 then cy = 0 end
    return cx, cy, vw, vh
  end
  -- the mon's occupied tile (actors are top-left anchored:
  -- cell*16 at rest). The ball lands on the tile; the tap hitbox is
  -- the tile plus the sprite body above it (see tryThrow).
  local function captureField()
    local FV = SP.require("src.core.game3.field_view")
    if type(FV) ~= "table" or type(FV.draw) ~= "function" then return end
    if FV.__spOwOwned then return end
    FV.__spOwOwned = true
    local raw = FV.draw
    FV.draw = function(game, canvasW, canvasH, opts)
      pcall(function()
        local vw = math.floor(tonumber(canvasW) or 0)
        local vh = math.floor(tonumber(canvasH) or 0)
        if vw > 0 and vh > 0 then
          ownField.vw, ownField.vh = vw, vh
          local px, py = playerPos()
          if px ~= nil and py ~= nil then
            local cx = math.floor(px + 8 - vw / 2)
            local cy = math.floor(py + 8 - vh / 2)
            if type(FV.cameraPanX) == "number" then cx = cx + FV.cameraPanX end
            if type(FV.cameraPanY) == "number" then cy = cy + FV.cameraPanY end
            ownField.camX, ownField.camY = cx, cy
          end
        end
      end)
      return raw(game, canvasW, canvasH, opts)
    end
  end
  local function worldCam()
    if ownField.camX ~= nil and ownField.vw ~= nil then
      return ownField.camX, ownField.camY, ownField.vw, ownField.vh
    end
    local cx, cy = exactCam()
    if cx == nil then return nil end
    return cx, cy, nil, nil
  end
  local function worldBlit()
    local R = SP.require("src.render.Renderer")
    if type(R) ~= "table" then return nil end
    local okF, fr = pcall(R.frameRects, R)
    if not okF or type(fr) ~= "table" then return nil end
    local vx = tonumber(fr.vx) or 0
    local vy = tonumber(fr.vy) or 0
    local pw = tonumber(fr.pw)
    local ph = tonumber(fr.ph)
    local dpiX = tonumber(fr.dpiX) or 1
    local dpiY = tonumber(fr.dpiY) or 1
    if dpiX <= 0 then dpiX = 1 end
    if dpiY <= 0 then dpiY = 1 end
    local Sp = tonumber(fr.Sp)
    if Sp == nil and type(R.fitScale) == "function" then
      local okS, v = pcall(R.fitScale, R)
      if okS then Sp = tonumber(v) end
    end
    if Sp == nil or Sp <= 0 then return nil end
    local sp = Sp
    local Z = SP.require("src.render.Zoom")
    if type(Z) == "table" and type(Z.scale) == "function" then
      local okZ, v = pcall(Z.scale, Sp)
      if okZ and tonumber(v) and tonumber(v) > 0 then sp = tonumber(v) end
    end
    local wvw, wvh = nil, nil
    local wc = R.worldCanvas
    if wc ~= nil then
      local okW, a, b = pcall(function() return wc:getWidth(), wc:getHeight() end)
      if okW then wvw, wvh = tonumber(a), tonumber(b) end
    end
    if wvw == nil and ownField.vw ~= nil then wvw, wvh = ownField.vw, ownField.vh end
    if wvw == nil or wvh == nil or pw == nil or ph == nil then return nil end
    local sx, sy = sp / dpiX, sp / dpiY
    local lift = tonumber(fr.lift) or 0
    local wox = (vx + math.floor((pw - wvw * sp) / 2)) / dpiX
    local woy = (vy + math.floor((ph - wvh * sp) / 2) - lift) / dpiY
    return wox, woy, sx, sy
  end
  local function hookOweRemove()
    local E = untamedE()
    if type(E) ~= "table" or type(E.Owe) ~= "table" then return end
    if type(E.Owe.remove) ~= "function" or E.Owe.__spOwVelHook then return end
    E.Owe.__spOwVelHook = true
    local raw = E.Owe.remove
    E.Owe.remove = function(a)
      oweVel[a] = nil
      spawnSeen[a] = nil
      return raw(a)
    end
  end
  local function hookWohCollect()
    local sm = wohSM()
    if sm == nil or type(sm.collectActors) ~= "function" then return end
    if sm.__spOwHideHook then return end
    sm.__spOwHideHook = true
    local raw = sm.collectActors
    sm.collectActors = function(self, actors, camX, camY)
      local n = 0
      if type(actors) == "table" then n = #actors end
      raw(self, actors, camX, camY)
      local h = wohHiddenId
      if h == nil or type(actors) ~= "table" then return end
      for i = #actors, n + 1, -1 do
        if type(actors[i]) == "table" and actors[i].i == h then
          table.remove(actors, i)
        end
      end
    end
  end
  local function monTile(a)
    local px, py = tonumber(a.px), tonumber(a.py)
    if px == nil or py == nil then return nil end
    return math.floor(px / 16), math.floor(py / 16)
  end
  -- per-actor screen anchor: the actor's own draw record maps its
  -- world point to its screen point with no camera involved, so a
  -- tap (or the ball) measured against the actor itself stays
  -- correct even if the global camera notion is off.
  local function actorScreen(a)
    if type(a) ~= "table" then return nil end
    local px, py = tonumber(a.px), tonumber(a.py)
    local sx, sy = tonumber(a.lastSx), tonumber(a.lastSy)
    local s = math.floor(tonumber(a.drawnAt) or -1)
    if px == nil or py == nil or sx == nil or sy == nil
        or s < 0 then
      return nil
    end
    return sx, sy, s, px, py
  end
  -- freshest draw serial seen on any live actor (nil when neither
  -- provider recorded one). Records older than this are despawns.
  local function freshSerial()
    local m = nil
    local function ck(a)
      if type(a) ~= "table" then return end
      if not isWohEntity(a) then
        if not a.active then return end
        if (tonumber(a.slot) or 0) <= 1 then return end
      end
      local s = math.floor(tonumber(a.drawnAt) or -1)
      if s >= 0 and (m == nil or s > m) then m = s end
    end
    local E = untamedE()
    if type(E) == "table" and type(E.actors) == "table" then
      for i = 1, #E.actors do ck(E.actors[i]) end
    else
      local sm = wohSM()
      if sm ~= nil and type(sm.order) == "table"
          and type(sm.entities) == "table" then
        for _, id in ipairs(sm.order) do ck(sm.entities[id]) end
      end
    end
    return m
  end
  -- visible sprite size of an actor: Untamed draws the frame
  -- feet-anchored (bottom at tile bottom, top at tile bottom minus
  -- frame height), read from the same atlas table Untamed itself
  -- uses (sheets[(sheet-1)*6+3/4] = frame w/h). Cached per sheet;
  -- nil when unresolvable (callers fall back to the 16x32 standard).
  local sheetSizeCache = {}
  local function spriteSize(a)
    if isWohEntity(a) then
      local fw, fh = nil, nil
      pcall(function()
        local r = a.renderer
        if type(r) ~= "table" then return end
        if type(r.visualHeight) == "function" then
          fh = tonumber(r:visualHeight())
        elseif type(r.headLift) == "function" then
          fh = tonumber(r:headLift())
        else
          fh = tonumber(r.frameHeight or r.height)
        end
        fw = tonumber(r.frameWidth or r.width) or 16
      end)
      if fh == nil or fh < 8 or fh > 128 then fh = 32 end
      if fw == nil or fw < 8 or fw > 64 then fw = 16 end
      return fw, fh
    end
    local sheet = math.floor(tonumber(a.sheet) or 0)
    if sheet < 1 then return nil end
    local hit = sheetSizeCache[sheet]
    if hit ~= nil then
      if type(hit) == "table" then return hit[1], hit[2] end
      return nil
    end
    local fw, fh = nil, nil
    pcall(function()
      local E = untamedE()
      local A = type(E) == "table" and E.Data
        and E.Data.ATLAS
      local sheets = type(A) == "table" and A.sheets
      if type(sheets) ~= "table" then return end
      if sheet < 1 or (sheet - 1) * 6 + 4 > #sheets then return end
      fw = tonumber(sheets[(sheet - 1) * 6 + 3])
      fh = tonumber(sheets[(sheet - 1) * 6 + 4])
    end)
    if fw == nil or fh == nil or fw < 8 or fw > 64
        or fh < 8 or fh > 64 then
      sheetSizeCache[sheet] = false
      return nil
    end
    sheetSizeCache[sheet] = { fw, fh }
    return fw, fh
  end
  -- per-axis presentation scales: the engine letterboxes per axis
  -- (Display.fit: scaleX = k/dpiX, scaleY = k/dpiY) and Game3._drawHud
  -- publishes only scaleX as viewport.scale, with gameHeight already
  -- carrying scaleY (gameHeight = 160*scaleY). Uniform-dpi landscape
  -- hides this (both scales equal, which is why landscape works);
  -- portrait phone dpi splits them, so every window<->game
  -- conversion below MUST use scy for y or taps land high/low.
  local function scalesOf(v)
    local scx = tonumber(v.scale) or 1
    if scx <= 0 then scx = 1 end
    local scy = scx
    local gh = tonumber(v.gameHeight)
    if gh ~= nil and gh > 0 then scy = gh / 160 end
    if scy <= 0 then scy = scx end
    return scx, scy
  end
  -- live canvas size in game px, from the cached hud viewport
  -- (game rect in window px divided by the per-axis scales). Nil
  -- when unknown.
  local function canvasSize()
    local v = viewportCache
    if type(v) ~= "table" then return nil end
    local scx, scy = scalesOf(v)
    local gw = tonumber(v.gameWidth)
    local gh = tonumber(v.gameHeight)
    if gw == nil or gh == nil
        or gw <= 0 or gh <= 0 then
      return nil
    end
    local cw, ch = gw / scx, gh / scy
    -- sanity: a field canvas is never smaller than the GBA screen.
    -- If the units ever misread, stay permissive, not blind.
    if cw < 200 or ch < 140 then return nil end
    return cw, ch
  end
  -- is the actor's drawn sprite (feet-anchored, same geometry as
  -- the hitbox) inside the visible canvas at all? Runtime-drawn
  -- records exist for clipped off-screen actors too (the engine
  -- does not cull the main list), so freshness alone does not
  -- prove the player can see the mon.
  local function spriteOnScreen(a, sx, sy, cw, ch)
    if cw == nil or ch == nil then return true end
    local fw, fh = spriteSize(a)
    fw = fw or 16
    fh = fh or 32
    local x0 = sx + 8 - fw / 2
    local y0 = sy + 16 - fh
    return x0 + fw > 0 and x0 < cw and y0 + fh > 0 and y0 < ch
  end
  -- the tapped actor as a foe: Untamed's own battle shape
  -- (species, level, personality, moves), mon built from confirmed
  -- engine seams only: Pokemon.learnset for the wild moveset (last 4
  -- at or below level, like the engine's own wild mon), moveName/movePp
  -- for validation/PP, applyStats (or the stats-table formula) for
  -- stats, natureId/gender guarded. NOTHING here hard-fails on a
  -- missing helper: an unresolvable piece degrades instead of
  -- refusing the throw (a refused throw is silent on the field).
  local moveIdCache = {}
  local function moveNameOf(Pokemon, id)
    if type(Pokemon) == "table"
        and type(Pokemon.moveName) == "function" then
      local ok, nm = pcall(Pokemon.moveName, id)
      if ok and type(nm) == "string" and nm ~= "" then return nm end
    end
    return nil
  end
  local function moveIdByName(Pokemon, name)
    if type(name) ~= "string" or name == "" then return nil end
    if type(Pokemon) ~= "table"
        or type(Pokemon.moveName) ~= "function" then
      return nil
    end
    local key = string.upper(name)
    if moveIdCache[key] ~= nil then return moveIdCache[key] or nil end
    local found = nil
    for n = 1, 600 do
      local ok, mname = pcall(Pokemon.moveName, n)
      if ok and type(mname) == "string"
          and string.upper(mname) == key then
        found = n
        break
      end
    end
    moveIdCache[key] = found or false
    return found
  end
  local learnPoolCache = {}
  local function learnPool(Pokemon, species)
    local cached = learnPoolCache[species]
    if cached ~= nil then return cached end
    local pool = {}
    if type(Pokemon) == "table"
        and type(Pokemon.learnset) == "function" then
      local ok, set = pcall(Pokemon.learnset, species)
      if ok and type(set) == "table" then
        for _, e in ipairs(set) do
          local lv, mv = nil, nil
          if type(e) == "table" then
            lv = tonumber(e[1] or e.level)
            mv = e[2] or e.move
          else
            mv = e
          end
          local id = tonumber(mv)
          if id == nil then id = moveIdByName(Pokemon, mv) end
          if id ~= nil and id >= 1 and moveNameOf(Pokemon, id) ~= nil then
            pool[#pool + 1] = { lv = lv or 0, id = id }
          elseif id ~= nil and id >= 1
              and not (type(Pokemon.moveName) == "function") then
            -- no name table to validate against: trust the numeric id.
            pool[#pool + 1] = { lv = lv or 0, id = id }
          end
        end
      end
    end
    if #pool == 0 then
      -- registry fallback: same learnset/level1Moves the content
      -- records carry (catch-em-all reads these live the same way).
      pcall(function()
        local rec = mod.content.pokemon:get(species)
        if type(rec) ~= "table" then return end
        local function pushList(list, defLv)
          if type(list) ~= "table" then return end
          for _, e in ipairs(list) do
            local lv, mv = defLv, nil
            if type(e) == "table" then
              lv = tonumber(e.level or e[1]) or defLv
              mv = e.move or e[2]
            else
              mv = e
            end
            local id = tonumber(mv)
            if id == nil then id = moveIdByName(Pokemon, mv) end
            if id ~= nil and id >= 1 then
              pool[#pool + 1] = { lv = lv or 0, id = id }
            end
          end
        end
        pushList(rec.level1Moves, 1)
        pushList(rec.learnset, nil)
      end)
    end
    learnPoolCache[species] = pool
    return pool
  end
  local function wildMovesFor(Pokemon, species, lvl, actorMoves)
    local ids = {}
    if type(actorMoves) == "table" then
      for i = 1, #actorMoves do
        local id = tonumber(actorMoves[i])
        if id ~= nil and id >= 1 then ids[#ids + 1] = id end
      end
    end
    if #ids == 0 then
      local pool = learnPool(Pokemon, species)
      local seen, rev = {}, {}
      for i = #pool, 1, -1 do
        local e = pool[i]
        if (e.lv or 0) <= lvl and not seen[e.id] then
          seen[e.id] = true
          rev[#rev + 1] = e.id
          if #rev >= 4 then break end
        end
      end
      for i = #rev, 1, -1 do ids[#ids + 1] = rev[i] end
    end
    return ids
  end
  local function foeMonFromActor(a)
    local Pokemon = SP.require("src.core.game3.pokemon")
    if type(Pokemon) ~= "table" then return nil end
    local species = math.floor(tonumber(a.engineSpecies or a.species) or 0)
    if species < 1 then return nil end
    local lvl = math.max(1, math.min(100, math.floor(
      tonumber(a.level) or 1)))
    local Rng = SP.require("src.core.game3.rng")
    local personality = tonumber(a.personality)
    if personality == nil then
      if type(Rng) == "table"
          and type(Rng.Random32) == "function" then
        local ok, v = pcall(Rng.Random32)
        if ok and tonumber(v) ~= nil then
          personality = math.floor(tonumber(v))
        end
      end
    end
    if personality == nil then
      personality = math.floor(math.random() * 4294967296)
    end
    local r16 = function()
      if type(Rng) == "table" and type(Rng.Random) == "function" then
        local ok, v = pcall(Rng.Random)
        if ok and tonumber(v) ~= nil then
          return math.floor(tonumber(v)) % 65536
        end
      end
      return math.floor(math.random() * 65536)
    end
    local iv1, iv2 = r16(), r16()
    local ivs = {
      hp = iv1 % 32,
      atk = math.floor(iv1 / 32) % 32,
      def = math.floor(iv1 / 1024) % 32,
      spe = iv2 % 32,
      spa = math.floor(iv2 / 32) % 32,
      spd = math.floor(iv2 / 1024) % 32,
    }
    if type(a.ivs) == "table" then
      local got = {}
      local valid = true
      for _, k in ipairs({ "hp", "atk", "def", "spe", "spa", "spd" }) do
        local v = math.floor(tonumber(a.ivs[k]) or -1)
        if v < 0 or v > 31 then
          valid = false
          break
        end
        got[k] = v
      end
      if valid then ivs = got end
    end
    -- same tiers a bumped battle would grant through Bridge.start.
    if type(SP.masteryCount) == "function"
        and type(SP.masteryTierFor) == "function" then
      local count = tonumber(SP.masteryCount(species)) or 0
      if count >= 5 then
        local guaranteed, bonus = SP.masteryTierFor(count)
        guaranteed = math.floor(tonumber(guaranteed) or 0)
        bonus = math.floor(tonumber(bonus) or 0)
        if guaranteed > 0 or bonus > 0 then
          local keys = { "hp", "atk", "def", "spe", "spa", "spd" }
          local avail = {}
          for i = 1, 6 do
            if (tonumber(ivs[keys[i]]) or 0) < 31 then
              avail[#avail + 1] = i
            end
          end
          for _ = 1, guaranteed do
            if #avail == 0 then break end
            local idx = rngInt(#avail) + 1
            ivs[keys[avail[idx]]] = 31
            avail[idx] = avail[#avail]
            avail[#avail] = nil
          end
          for _ = 1, bonus do
            if #avail == 0 then break end
            if rngInt(2) == 0 then
              local idx = rngInt(#avail) + 1
              ivs[keys[avail[idx]]] = 31
              avail[idx] = avail[#avail]
              avail[#avail] = nil
            end
          end
        end
      end
    end
    local gender = "U"
    if type(Pokemon.gender) == "function" then
      local ok, g = pcall(Pokemon.gender, species, personality)
      if ok and (g == "M" or g == "F" or g == "U") then gender = g end
    end
    local nature = 0
    if type(Pokemon.natureId) == "function" then
      local ok, v = pcall(Pokemon.natureId, personality)
      if ok and tonumber(v) ~= nil then nature = math.floor(v) end
    end
    local moves = wildMovesFor(Pokemon, species, lvl, a.moves)
    -- even a moveless mon still throws: the catch roll never reads
    -- moves (eggs are stored moveless too), and the wild-moveset
    -- sources above resolve in practice.
    local pp, maxPp = {}, {}
    for i = 1, #moves do
      local mpp = 10
      if type(Pokemon.movePp) == "function" then
        local ok, v = pcall(Pokemon.movePp, moves[i])
        if ok and tonumber(v) ~= nil then mpp = math.floor(v) end
      end
      pp[i] = mpp
      maxPp[i] = mpp
    end
    local mon = {
      species = species,
      speciesId = species,
      level = lvl,
      moves = moves,
      pp = pp,
      maxPp = maxPp,
      gender = gender,
      ivs = ivs,
      personality = personality,
      nature = nature,
    }
    if type(Pokemon.applyStats) == "function" then
      pcall(Pokemon.applyStats, mon)
    end
    if tonumber(mon.maxHp) == nil then
      -- applyStats unavailable: same gen-3 formula partner.lua uses,
      -- from the confirmed stats table (neutral nature).
      pcall(function()
        local base = Pokemon.stats(species)
        if type(base) ~= "table" then return end
        local function bv(k)
          return math.max(0, math.floor(tonumber(base[k]) or 0))
        end
        local function iv(k)
          local v = math.floor(tonumber(ivs[k]) or 0)
          if v < 0 then return 0 end
          if v > 31 then return 31 end
          return v
        end
        mon.maxHp = math.floor(
          ((2 * bv("hp") + iv("hp")) * lvl) / 100) + lvl + 10
        for _, k in ipairs({ "atk", "def", "spe", "spa", "spd" }) do
          mon[k] = math.floor(((2 * bv(k) + iv(k)) * lvl) / 100) + 5
        end
      end)
    end
    local maxHp = tonumber(mon.maxHp) or 1
    if maxHp < 1 then maxHp = 1 end
    mon.maxHp = maxHp
    mon.hp = maxHp
    pcall(function()
      local Experience = SP.require("src.core.game3.battle.experience")
      if type(Experience) == "table"
          and type(Experience.syncExpToLevel) == "function" then
        Experience.syncExpToLevel(mon)
      end
    end)
    mon.hp = tonumber(mon.maxHp) or maxHp
    return mon
  end
  local function monName(mon)
    local Pokemon = SP.require("src.core.game3.pokemon")
    if type(Pokemon) == "table"
        and type(Pokemon.displayMonName) == "function" then
      local ok, nm = pcall(Pokemon.displayMonName, mon)
      if ok and type(nm) == "string" and nm ~= "" then return nm end
    end
    return "POKéMON"
  end
  local function actorName(a)
    local Pokemon = SP.require("src.core.game3.pokemon")
    if type(Pokemon) == "table"
        and type(Pokemon.name) == "function" then
      local ok, nm = pcall(Pokemon.name, tonumber(a.engineSpecies or a.species))
      if ok and type(nm) == "string" and nm ~= ""
          and nm ~= "??????????" then
        return nm
      end
    end
    return "POKéMON"
  end
  local function countPerfect(mon)
    local ivs = type(mon) == "table" and mon.ivs
    if type(ivs) ~= "table" then return 0 end
    local n = 0
    for _, k in ipairs({ "hp", "atk", "def", "spe", "spa", "spd" }) do
      if math.floor(tonumber(ivs[k]) or 0) >= 31 then n = n + 1 end
    end
    return n
  end
  -- real catch roll at throw time: full-HP mon + synthetic
  -- safariState, so meta catch rate + SP.catchBonus() apply exactly
  -- like an in-battle fresh throw.
  local function rollCatch(mon, species, extra, ballId, rctx)
    local custom = tonumber(ballId) ~= BALL_ID
      and type(SP.customCatch) == "function"
    if custom then
      local okC, caught, shakes = pcall(SP.customCatch, species,
        extra and extra.level or 1, ballId, rctx,
        function() return rngFn(0, 9999) / 10000 end)
      if okC and caught ~= nil then
        shakes = math.max(0, math.min(4, math.floor(tonumber(shakes) or 0)))
        if caught and shakes < 4 then shakes = 4 end
        return caught == true, shakes
      end
      custom = false
    end
    local ball = BALL_ID
    if not custom and tonumber(ballId) ~= BALL_ID then
      local n = math.floor(tonumber(ballId) or 0)
      if n >= 1 and n <= 12 then ball = n end
    end
    local Catching = SP.require("src.core.game3.battle.catching")
    local Rules = SP.require("src.core.game3.battle.rules")
    local Pokemon = SP.require("src.core.game3.pokemon")
    local session = SP.session()
    if type(Catching) ~= "table"
        or type(Catching.tryCatch) ~= "function"
        or type(session) ~= "table" then
      return false, 0
    end
    local rate = 45
    if type(Pokemon) == "table"
        and type(Pokemon.speciesMeta) == "function" then
      local ok, meta = pcall(Pokemon.speciesMeta, species)
      if ok and type(meta) == "table" then
        rate = math.max(1, math.min(255,
          math.floor(tonumber(meta.catchRate) or 45)))
      end
    end
    local st = nil
    if ball == BALL_ID and type(Rules) == "table"
        and type(Rules.safari) == "table"
        and type(Rules.safari.newState) == "function" then
      local ok, s = pcall(Rules.safari.newState, rate, 0)
      if ok and type(s) == "table" then st = { safariState = s } end
    end
    local foe = { species = species, mon = mon }
    if type(extra) == "table" then
      -- bridge-foe fields too (level/personality/moves/ivs): the same
      -- table Untamed hands startWild, so native code reading either
      -- the battled-mon shape or the bridge shape finds real data.
      for k, v in pairs(extra) do
        if foe[k] == nil then foe[k] = v end
      end
    end
    local ok, caught, shakes =
      pcall(Catching.tryCatch, ball, foe, st, session, rngFn)
    if not ok then return false, 0 end
    shakes = math.max(0, math.min(4, math.floor(tonumber(shakes) or 0)))
    if caught and shakes < 4 then shakes = 4 end
    return caught == true, shakes
  end
  local function flightDur()
    if speedup() then return 0.15 end
    return 0.45
  end
  local function gulpDur()
    if speedup() then return 0.12 end
    return 0.35
  end
  local function rockOf(u)
    return math.tanh(2.2 * math.sin(u * math.pi * 2)) / 0.9757
  end
  local function actorGone(a)
    if type(a) ~= "table" then return true end
    if isWohEntity(a) then
      local sm = wohSM()
      if sm == nil or type(sm.get) ~= "function" then return true end
      local ok, e = pcall(sm.get, sm, a.id)
      if not ok or e ~= a then return true end
      return a.state ~= WOH_AVAILABLE and a.state ~= WOH_STARTING
    end
    return not a.active
      or a.oweType == nil
  end
  local lastWhiffToast = -10
  local lastStillToast = -10
  -- recent taps for the TAP DEBUG overlay (game-space point + expiry).
  local tapMarks = {}
  local function tapDebug()
    return SP.opt("tap_debug", false) == true
  end
  local function launchThrow(best)
    local px, py, pcx, pcy, moving, surfing = playerPos()
    if px == nil then return false end
    if moving then
      if SP.now() - lastStillToast > 3 then
        lastStillToast = SP.now()
        toast("Stand still to throw!")
      end
      return false
    end
    local mon = foeMonFromActor(best)
    if mon == nil then return false end
   SP.tick()
    local thrownId = equippedId()
    if thrownId == BALL_ID then
      se("SE_FAILURE")
      toast("No BALLS left!")
      return true
    end
    local spent = false
    pcall(function()
      local s = SP.session()
      local bag = type(s) == "table" and s.bag or nil
      local Bag = SP.require("src.core.game3.bag")
      if type(Bag) == "table" and type(Bag.remove) == "function"
          and type(bag) == "table" then
        local ok, res = pcall(Bag.remove, bag, thrownId, 1)
        if ok and res then spent = true end
      end
    end)
    if not spent then
      se("SE_FAILURE")
      toast("No " .. throwBallName() .. " left!")
      return true
    end
    lastThrow = SP.now()
    local v = oweVel[best]
    local vx, vy = 0, 0
    if type(v) == "table" then
      vx, vy = tonumber(v.vx) or 0, tonumber(v.vy) or 0
    end
    local dur = flightDur()
    local bx = tonumber(best.px) or 0
    local by = tonumber(best.py) or 0
    local ctx, cty = math.floor(bx / 16), math.floor(by / 16)
    local ltx = math.floor((bx + 8 + vx * dur) / 16)
    local lty = math.floor((by + 8 + vy * dur) / 16)
    if ltx - ctx > 3 then ltx = ctx + 3 end
    if ltx - ctx < -3 then ltx = ctx - 3 end
    if lty - cty > 3 then lty = cty + 3 end
    if lty - cty < -3 then lty = cty - 3 end
    local lx, ly = ltx * 16 + 8, lty * 16 + 8
    local species = math.floor(tonumber(best.engineSpecies or best.species) or 0)
    local lvl = math.floor(tonumber(best.level) or 1)
    local distTiles = 3
    if pcx ~= nil and pcy ~= nil then
      local dx = math.abs(ctx - pcx)
      local dy = math.abs(cty - pcy)
      distTiles = dx > dy and dx or dy
    end
    local spawnAge = math.max(0, animT - (spawnSeen[best] or animT))
    if spawnAge > 86400 then spawnAge = 86400 end
    local dist = 1.2
    if type(SP.distMult) == "function" then
      local okD, v = pcall(SP.distMult, distTiles)
      if okD and tonumber(v) then dist = tonumber(v) end
    end
    local berry = 1
    if type(SP.berryMult) == "function" then
      local okB, v = pcall(SP.berryMult)
      if okB and tonumber(v) then berry = tonumber(v) end
    end
    local caught, shakes = rollCatch(mon, species, {
      level = lvl,
      personality = mon.personality,
      moves = mon.moves,
      ivs = mon.ivs,
    }, thrownId, {
      level = lvl,
      species = species,
      surfing = surfing == true,
      actor = best,
      ue = untamedE(),
      session = SP.session(),
      dist = dist,
      berry = berry,
      spawnAge = spawnAge,
    })
    seq = {
      actor = best,
      mon = mon,
      ballId = thrownId,
      usedBerry = berry > 1,
      species = species,
      lvl = lvl,
      shiny = best.shiny == true,
      caught = caught,
      shakes = shakes,
      phase = "fly",
      t = 0,
      dur = dur,
      sx = (pcx ~= nil and pcx * 16 + 8) or (px + 8),
      sy = (pcy ~= nil and pcy * 16 + 8) or py,
      lx = lx,
      ly = ly,
      shakeIdx = 0,
      map = curMap(),
    }
    if isWohEntity(best) then
      seq.wohMarked = false
      pcall(function()
        local sm = wohSM()
        if sm ~= nil and type(sm.markEncounterStarting) == "function" then
          sm:markEncounterStarting(best.id)
          seq.wohMarked = true
        end
      end)
    end
    se("SE_BALL_THROW")
    return true
  end
  local function tryThrowExact(ex, ey)
    if not owOn() then return false, true end
    if seq ~= nil then return false, true end
    if SP.now() - lastThrow < THROW_COOLDOWN then return false, true end
    if not fieldClear() then return false, true end
    if provider() == nil then return false, true end
    local camX, camY = worldCam()
    if camX == nil then return nil, false end
    local wox, woy, wsx, wsy = worldBlit()
    if wox == nil then return nil, false end
    local wx, wy = (ex - wox) / wsx, (ey - woy) / wsy
    local vw, vh = ownField.vw, ownField.vh
    local fs = freshSerial()
    local best, bestD, seen = nil, nil, 0
    local extBest, extD = nil, nil
    eachTarget(function(a)
      local tx, ty = monTile(a)
      if tx == nil then return end
      seen = seen + 1
      local sx, sy, s, px0, py0 = actorScreen(a)
      if sx == nil or fs == nil or s ~= fs then return end
      local ax = tonumber(a.px)
      local ay = tonumber(a.py)
      if ax == nil or ay == nil then return end
      if vw ~= nil and vh ~= nil then
        local fw0, fh0 = spriteSize(a)
        fw0 = fw0 or 16
        fh0 = fh0 or 32
        local rx0 = ax - camX + 8 - fw0 / 2
        local ry0 = ay - camY + 16 - fh0
        if rx0 + fw0 <= 0 or rx0 >= vw or ry0 + fh0 <= 0 or ry0 >= vh then return end
      end
      local tax, tay = wx + camX, wy + camY
      local fw, fh = spriteSize(a)
      fh = fh or 32
      fw = fw or 16
      local x0, x1 = tx * 16, tx * 16 + 16
      local over = math.max(0, (fw - 16) / 2)
      local y0 = ty * 16 - math.max(0, fh - 16) - 4
      local dx = tax - (tx * 16 + 8)
      local dy = tay - (ty * 16 + 16 - fh / 2)
      local d = dx * dx + dy * dy
      if tax >= x0 and tax < x1
          and tay >= ty * 16 and tay < ty * 16 + 16 then
        if best == nil or d < bestD then
          best, bestD = a, d
        end
      elseif tax >= x0 - over and tax < x1 + over
          and tay >= y0 and tay < ty * 16 + 16 then
        if extBest == nil or d < extD then
          extBest, extD = a, d
        end
      end
    end)
    if best == nil then best = extBest end
    if best == nil then
      if seen > 0 and SP.now() - lastWhiffToast > 3 then
        lastWhiffToast = SP.now()
        toast("Missed! Tap a wild POKéMON directly.")
      end
      return false, true
    end
    return launchThrow(best), true
  end
  local drawBall
  local drawShadow
  local ballFrame
  local function actorTileCenter(a)
    local tx, ty = monTile(a)
    if tx == nil then return nil end
    return tx * 16 + 8, ty * 16 + 8
  end
  local function drawBallExact(s)
    local camX, camY = worldCam()
    if camX == nil then return false end
    local wox, woy, wsx, wsy = worldBlit()
    if wox == nil then return false end
    local bx, by = s.lx, s.ly
    local rot = 0
    if s.phase == "fly" then
      local e = s.dur > 0 and math.min(1, s.t / s.dur) or 1
      bx = s.sx + (s.lx - s.sx) * e
      by = s.sy + (s.ly - s.sy) * e - 24 * math.sin(math.pi * e)
    elseif s.phase == "shake" then
      local u = (s.t % SHAKE_DUR) / SHAKE_DUR
      local rock = rockOf(u)
      bx = bx + rock * 2.5
      rot = rock * 0.32
    end
    local alpha = 1
    if s.phase == "fade" then
      alpha = math.max(0, 1 - s.t / FADE_DUR)
    end
    local shAlpha = 0.32 * alpha
    drawShadow(wox + (s.lx - camX) * wsx, woy + (s.ly + 7 - camY) * wsy,
      6 * wsx, 2.5 * wsy, shAlpha)
    drawBall(wox + (bx - camX) * wsx, woy + (by - camY) * wsy,
      wsx, wsy, alpha, rot, ballFrame(s))
    return true
  end
  local function tryThrow(gx, gy)
    if not owOn() then return false end
    if seq ~= nil then return false end
    if SP.now() - lastThrow < THROW_COOLDOWN then return false end
    if not fieldClear() then return false end
    if provider() == nil then return false end
    local px, py, pcx, pcy, moving = playerPos()
    if px == nil then return false end
    -- strict runtime targeting: the tap must hit a mon Untamed
    -- drew in the latest field draw (fresh draw record) whose
    -- sprite is actually on the visible canvas. No global-camera
    -- fallback here — a fallback can map the tap onto a live but
    -- undrawn wanderer, i.e. an invisible mon. Two tiers: a tap
    -- inside an occupied TILE always belongs to that tile's mon
    -- (nearest on the rare shared tile); only a tap that hits no
    -- tile falls to the sprite-extension boxes (nearest there).
    -- One tier would let a stacked upper mon snatch taps aimed at
    -- the lower mon's head and throw the ball a tile too high.
    local fs = freshSerial()
    local cw, ch = canvasSize()
    -- portrait world-view growth: records are world-canvas px, taps
    -- are UI-canvas px (see viewInfo). Measure it once per tap.
    local ccx, ccy, vw, vh = viewInfo()
    if vw ~= nil and vh ~= nil then cw, ch = vw, vh end
    local best, bestD, seen = nil, nil, 0
    local extBest, extD = nil, nil
    eachTarget(function(a)
      local tx, ty = monTile(a)
      if tx == nil then return end
      seen = seen + 1
      local sx, sy, s, px0, py0 = actorScreen(a)
      if sx == nil or fs == nil or s ~= fs then return end
      if not spriteOnScreen(a, sx, sy, cw, ch) then return end
      local Wx, Wy = px0 + (gx - sx) + ccx, py0 + (gy - sy) + ccy
      local fw, fh = spriteSize(a)
      fh = fh or 32
      fw = fw or 16
      local x0, x1 = tx * 16, tx * 16 + 16
      local over = math.max(0, (fw - 16) / 2)
      local y0 = ty * 16 - math.max(0, fh - 16) - 4
      local dx = Wx - (tx * 16 + 8)
      local dy = Wy - (ty * 16 + 16 - fh / 2)
      local d = dx * dx + dy * dy
      if Wx >= x0 and Wx < x1
          and Wy >= ty * 16 and Wy < ty * 16 + 16 then
        if best == nil or d < bestD then
          best, bestD = a, d
        end
      elseif Wx >= x0 - over and Wx < x1 + over
          and Wy >= y0 and Wy < ty * 16 + 16 then
        if extBest == nil or d < extD then
          extBest, extD = a, d
        end
      end
    end)
    if best == nil then best = extBest end
    if best == nil then
      -- a tap that reaches us but hits nothing: say so only when a
      -- tappable mon is actually on screen (otherwise every stray
      -- field tap would nag).
      if seen > 0 and SP.now() - lastWhiffToast > 3 then
        lastWhiffToast = SP.now()
        toast("Missed! Tap a wild POKéMON directly.")
      end
      return false
    end
    -- stand still to throw; mons keep moving so prediction matters.
    return launchThrow(best)
  end
  local function alive(mon)
    return type(mon) == "table" and not mon.isEgg
      and (tonumber(mon.hp) or 0) > 0
      and (tonumber(mon.level) or 1) < 100
  end
  -- vanilla /7 split across eligible party mons (caught mon excluded:
  -- it didn't fight), scaled by EXP YIELD; EVs via native gainEVs
  -- (skipped at 0%); level-up moves auto-teach on free slots, toast
  -- otherwise. Evolution waits for a later battle (v1 limit).
  local function payExp(session, species, lvl, caughtMon)
    local pct = SP.yieldPct()
    if pct <= 0 then return end
    local party = type(session) == "table" and session.party or nil
    if type(party) ~= "table" then return end
    local Pokemon = SP.require("src.core.game3.pokemon")
    local Experience = SP.require("src.core.game3.battle.experience")
    if type(Pokemon) ~= "table" or type(Experience) ~= "table"
        or type(Experience.apply) ~= "function" then
      return
    end
    local yield = 0
    if type(Pokemon.expYield) == "function" then
      local ok, v = pcall(Pokemon.expYield, species)
      if ok then yield = math.floor(tonumber(v) or 0) end
    elseif type(Experience.expYield) == "function" then
      local ok, v = pcall(Experience.expYield, species)
      if ok then yield = math.floor(tonumber(v) or 0) end
    end
    if yield <= 0 then
      -- content fallback: the merged pokemon record carries baseExp
      -- (catch-em-all reads these records live the same way).
      pcall(function()
        local rec = mod.content.pokemon:get(species)
        if type(rec) == "table" then
          yield = math.floor(
            tonumber(rec.baseExp or rec.expYield) or 0)
        end
      end)
    end
    if yield <= 0 then return end
    local idx = {}
    for i = 1, 6 do
      local m = party[i]
      if m ~= nil and m ~= caughtMon and alive(m) then
        idx[#idx + 1] = i
      end
    end
    if #idx == 0 then return end
    local total = math.floor(yield * lvl / 7)
    local each = math.max(1, math.floor(total / #idx))
    local scaled = math.max(0, math.floor(each * pct / 100))
    if scaled <= 0 then return end
    local sum = 0
    for _, pi in ipairs(idx) do
      local m = party[pi]
      if type(Pokemon.gainEVs) == "function" then
        pcall(Pokemon.gainEVs, m, species)
      end
      local ok, r = pcall(Experience.apply, m, scaled)
      if ok and type(r) == "table" then
        sum = sum + (tonumber(r.gained) or scaled)
        if type(r.levels) == "table" and #r.levels > 0
            and type(Pokemon.movesLearnedAt) == "function" then
          local sid = m.species or m.speciesId
          for _, lv in ipairs(r.levels) do
            local okL, learned =
              pcall(Pokemon.movesLearnedAt, sid, lv)
            if okL and type(learned) == "table" then
              for _, mv in ipairs(learned) do
                if type(Pokemon.knowsMove) == "function"
                    and not Pokemon.knowsMove(m, mv) then
                  local taught = false
                  if type(Pokemon.teachMove) == "function" then
                    local okT, v =
                      pcall(Pokemon.teachMove, m, mv)
                    taught = okT and v == true
                  end
                  local mvName = "a move"
                  if type(Pokemon.moveName) == "function" then
                    local okN, nm = pcall(Pokemon.moveName, mv)
                    if okN and type(nm) == "string" and nm ~= "" then
                      mvName = nm
                    end
                  end
                  if taught then
                    toast(monName(m) .. " learned " .. mvName .. "!")
                  else
                    toast(monName(m) .. " wants to learn "
                      .. mvName .. "!")
                  end
                end
              end
            end
          end
        end
      else
        sum = sum + scaled
      end
    end
    toast("Your party gained " .. math.floor(sum / #idx)
      .. " EXP. Points!")
  end
  local function releaseMon(session, res, mon)
    pcall(function()
      if type(res) == "table" and res.pending then
        res.pending = nil
        return
      end
      if type(res) == "table" and res.location == "pc"
          and res.box ~= nil and res.slot ~= nil then
        local Storage = SP.require("src.core.game3.storage")
        if type(Storage) == "table"
            and type(Storage.releaseMon) == "function" then
          pcall(Storage.releaseMon, session, res.box, res.slot)
        end
        return
      end
      local party = type(session) == "table" and session.party or nil
      if type(party) == "table" then
        for i = #party, 1, -1 do
          if party[i] == mon then
            table.remove(party, i)
            break
          end
        end
      end
    end)
  end
  local showActor
  local hideActor
  local dropSeq
  local settleBall
  settleBall = function(s)
    local bid = math.floor(tonumber(type(s) == "table" and s.ballId) or 0)
    if bid ~= 0 and bid ~= BALL_ID then
      local n = 0
      pcall(function()
        local sess = SP.session()
        local bag = type(sess) == "table" and sess.bag or nil
        local Bag = SP.require("src.core.game3.bag")
        if type(Bag) == "table" and type(Bag.get) == "function"
            and type(bag) == "table" then
          local ok, q = pcall(Bag.get, bag, bid)
          if ok then n = math.floor(tonumber(q) or 0) end
        end
      end)
      if n <= 0 and type(SP.setEquippedBall) == "function" then
        pcall(SP.setEquippedBall, firstOwnedBall() or BALL_ID)
      end
    end
  end
  local function eatBerry(s)
    if type(s) == "table" and s.usedBerry == true
        and type(SP.clearBerry) == "function" then
      pcall(SP.clearBerry)
    end
  end
  local function resolveCatch()
    local s = seq
    seq = nil
    if s == nil then return end
    settleBall(s)
    if actorGone(s.actor) then eatBerry(s) return end
    local before = skillLevels()
    local beforeP = 0
    if type(SP.playerLevel) == "function" then
      local okP, lv = pcall(SP.playerLevel)
      if okP then beforeP = math.floor(tonumber(lv) or 0) end
    end
    local session = SP.session()
    if type(session) ~= "table" then showActor(s) eatBerry(s) return end
    local Catching = SP.require("src.core.game3.battle.catching")
    if type(Catching) ~= "table"
        or type(Catching.storeCaught) ~= "function" then
      showActor(s)
      eatBerry(s)
      return
    end
    local foe = { species = s.species, mon = s.mon,
      level = s.lvl, personality = s.mon.personality,
      moves = s.mon.moves, ivs = s.mon.ivs }
    local res = nil
    SP.owFlatCap = true
    local bid = math.floor(tonumber(s.ballId) or 0)
    if bid < 1 or bid > 12 then bid = BALL_ID end
    local ok, r = pcall(Catching.storeCaught, session, foe, bid,
      {})
    SP.owFlatCap = nil
    if ok and type(r) == "table" then res = r end
    if type(res) ~= "table" or not res.success then
      se("SE_FAILURE")
      toast("The PC BOX is full!")
      showActor(s)
      eatBerry(s)
      return
    end
    pcall(function()
      if type(SP.addXp) ~= "function" then return end
      local g = tonumber(type(SP.GAIN) == "table"
        and SP.GAIN.regenOwCatch)
      if g == nil or g < 0 then g = 3 end
      SP.addXp("regen", math.floor(g))
    end)
    -- the tapped actor is the catch: despawn it through the provider.
    oweRemove(s.actor)
    local mon = res.mon
    local dup = res.firstTimeCaught == false
    local keep = not dup
    if dup then
      local need = math.floor(tonumber(SP.opt("iv_guard", 3)) or 3)
      if countPerfect(mon) >= need or s.shiny
          or SP.isShiny(mon) then
        keep = true
      end
    end
    if keep then
      local award = nil
      if type(SP.awardOverworldCandy) == "function" then
        local okA, v = pcall(SP.awardOverworldCandy, session, mon,
          s.lvl, res.firstTimeCaught, nil, false)
        if okA then award = v end
      end
      payExp(session, s.species, s.lvl, mon)
      se("SE_SUCCESS")
      cry(s.species)
      toast("Gotcha! " .. monName(mon) .. " was caught!")
      toastAward(award)
      toastLevelUps(before, beforeP)
    else
      local rewards = nil
      if SP.opt("exp_candy", true) ~= false then
        local CD = SP.candyData
        if type(CD) == "table"
            and type(CD.rewardsFor) == "function" then
          local okR, v = pcall(CD.rewardsFor, s.species,
            SP.cleanName(mon, s.species), s.lvl,
            SP.isLegendary(s.species))
          if okR and type(v) == "table" then rewards = v end
        end
      end
      local award = nil
      if type(SP.awardOverworldCandy) == "function" then
        local okA, v = pcall(SP.awardOverworldCandy, session, mon,
          s.lvl, res.firstTimeCaught, rewards, true)
        if okA then award = v end
      end
      if type(award) ~= "table" or not award.ok then
        -- bag full: the actor is already gone, so the mon is kept.
        payExp(session, s.species, s.lvl, mon)
        se("SE_SUCCESS")
        cry(s.species)
        toast("Gotcha! " .. monName(mon) .. " was caught!")
        toast("The BAG is full!")
        toastLevelUps(before, beforeP)
        eatBerry(s)
        return
      end
      releaseMon(session, res, mon)
      payExp(session, s.species, s.lvl, mon)
      se("SE_SUCCESS")
      cry(s.species)
      if type(rewards) == "table" and #rewards > 0 then
        local CD = SP.candyData
        local parts = nil
        if type(CD) == "table"
            and type(CD.rewardLines) == "function" then
          local okL, v = pcall(CD.rewardLines, rewards)
          if okL and type(v) == "table" and #v > 0 then parts = v end
        end
        if type(parts) ~= "table" then
          local line = "EXP CANDY"
          if type(CD) == "table"
              and type(CD.rewardText) == "function" then
            line = CD.rewardText(rewards)
          end
          parts = { line }
        end
        toast("You found:")
        for _, part in ipairs(parts) do
          if type(part) == "string" and part ~= "" then
            toast(part .. "!")
          end
        end
      else
        toast("Released " .. monName(mon) .. "!")
      end
      toastAward(award)
      toastLevelUps(before, beforeP)
    end
    eatBerry(s)
  end
  showActor = function(s)
    if type(s) ~= "table" or not s.hidden then return end
    s.hidden = false
    local a = s.actor
    if isWohEntity(a) then
      if wohHiddenId == a.id then wohHiddenId = nil end
      if s.wohMarked then
        s.wohMarked = false
        pcall(function()
          local sm = wohSM()
          local e = sm ~= nil and type(sm.get) == "function"
            and sm:get(a.id) or nil
          if e == a then a.state = WOH_AVAILABLE end
        end)
      end
      return
    end
    if type(a) == "table" then pcall(function() a.visible = true end) end
  end
  hideActor = function(s)
    local a = type(s) == "table" and s.actor
    if type(a) ~= "table" then return end
    if s.hidden then return end
    s.hidden = true
    if isWohEntity(a) then
      if not s.wohMarked then
        s.wohMarked = false
        pcall(function()
          local sm = wohSM()
          if sm ~= nil and type(sm.markEncounterStarting) == "function" then
            sm:markEncounterStarting(a.id)
            s.wohMarked = true
          end
        end)
      end
      wohHiddenId = a.id
      return
    end
    pcall(function() a.visible = false end)
  end
  dropSeq = function()
    local s = seq
    seq = nil
    settleBall(s)
    showActor(s)
  end
  local function breakOut()
    local s = seq
    dropSeq()
    eatBerry(s)
    se("SE_FAILURE")
    toast("Oh no! The POKéMON broke free!")
    local before = skillLevels()
    local beforeP = 0
    if type(SP.playerLevel) == "function" then
      local okP, lv = pcall(SP.playerLevel)
      if okP then beforeP = math.floor(tonumber(lv) or 0) end
    end
    pcall(function()
      if type(SP.addXp) ~= "function" then return end
      local g = tonumber(type(SP.GAIN) == "table" and SP.GAIN.likeFail)
      if g == nil or g < 0 then g = 2 end
      SP.addXp("like", math.floor(g))
      local r = tonumber(type(SP.GAIN) == "table"
        and SP.GAIN.regenOwFail)
      if r == nil or r < 0 then r = 1 end
      SP.addXp("regen", math.floor(r))
    end)
    toastLevelUps(before, beforeP)
  end
  local function seqTick(dt)
    local s = seq
    if s == nil then return end
    if actorGone(s.actor) then
      dropSeq()
      return
    end
    s.t = s.t + dt
    if s.phase == "fly" then
      if s.t >= s.dur then
        s.phase = "gulp"
        s.t = 0
        s.shakeIdx = 1
        local ax, ay = actorTileCenter(s.actor)
        if ax ~= nil then s.lx, s.ly = ax, ay end
        hideActor(s)
        se("SE_BALL_BOUNCE_1")
      else
        return
      end
    end
    if s.phase == "gulp" then
      if s.t >= gulpDur() then
        s.phase = "shake"
        s.t = 0
      end
      return
    end
    if s.phase == "shake" then
      local total = s.shakes
      if s.caught and total < 4 then total = 4 end
      if total <= 0 then
        breakOut()
        return
      end
      local idx = math.floor(s.t / SHAKE_DUR)
      while s.shakeIdx <= idx and s.shakeIdx < total do
        s.shakeIdx = s.shakeIdx + 1
        se("SE_BALL_BOUNCE_" .. ((s.shakeIdx - 1) % 3 + 1))
      end
      if s.t >= total * SHAKE_DUR then
        if s.caught then
          s.phase = "still"
          s.t = 0
        else
          breakOut()
        end
      end
      return
    end
    if s.phase == "still" then
      if s.t >= STILL_DUR then
        s.phase = "fade"
        s.t = 0
      end
      return
    end
    if s.phase == "fade" then
      if s.t >= FADE_DUR then resolveCatch() end
      return
    end
  end
  local function stepTick(dt)
    if dt == nil or dt <= 0 then return end
    if dt > 0.1 then dt = 0.1 end
    animT = animT + dt
    local mapId = curMap()
    pcall(captureField)
    pcall(hookOweRemove)
    pcall(hookWohCollect)
    if mapId == nil then return end
    if not fieldClear() then return end
    if provider() == nil then
      if warnedMap ~= mapId then
        warnedMap = mapId
        mod.log:warn("safari-plus: OVERWORLD needs Untamed or Wilds of Hoenn")
        toast("OVERWORLD needs Untamed or Wilds of Hoenn!")
      end
      return
    end
    if untamedE() == nil then
      local cx, cy = exactCam()
      if cx ~= nil and cy ~= nil then
        wohSerial = wohSerial + 1
        eachTarget(function(a)
          if type(a.px) == "number" and type(a.py) == "number" then
            a.lastSx, a.lastSy, a.drawnAt = a.px - cx, a.py - cy, wohSerial
          end
        end)
      end
    end
    -- sample live actor positions for landing prediction.
    eachTarget(function(a)
      if spawnSeen[a] == nil then spawnSeen[a] = animT end
      local ax = tonumber(a.px)
      local ay = tonumber(a.py)
      if ax == nil or ay == nil then return end
      local v = oweVel[a]
      if type(v) ~= "table" then
        v = { x = ax, y = ay, t = animT, vx = 0, vy = 0 }
        oweVel[a] = v
        return
      end
      if animT > v.t then
        local step = animT - v.t
        local dx, dy = ax - v.x, ay - v.y
        if math.abs(dx) > 24 or math.abs(dy) > 24 then
          -- slot recycled (despawn+spawn reuses the table: a
          -- teleport, not motion) — forget it instead of faking a
          -- sprint that throws the landing tiles off.
          v.vx, v.vy = 0, 0
        else
          local nvx, nvy = dx / step, dy / step
          -- frame hitches attribute several frames of movement to one
          -- clamped dt and would fake a sprint (ball landing tiles off,
          -- unpredictably); cap at the engine's fastest step rate.
          local sp = math.sqrt(nvx * nvx + nvy * nvy)
          if sp > 300 then
            nvx, nvy = nvx * 300 / sp, nvy * 300 / sp
          end
          v.vx, v.vy = nvx, nvy
        end
        v.x, v.y, v.t = ax, ay, animT
      end
    end)
    seqTick(dt)
    for i = #toasts, 1, -1 do
      toasts[i].t = toasts[i].t - dt
      if toasts[i].t <= 0 then table.remove(toasts, i) end
    end
  end
  -- the safari-battle ball sprite (battle ball sheet, safari id).
  local ballSheetCache = nil
  local ballQuadCache = {}
  local function ballSheet()
    if ballSheetCache ~= nil then return ballSheetCache or nil end
    pcall(function()
      local BallOpen = SP.require("src.core.game3.battle.ball_open")
      if type(BallOpen) ~= "table"
          or type(BallOpen.data) ~= "function" then
        return
      end
      local d = BallOpen.data()
      if type(d) ~= "table" or type(d.ballSheet) ~= "string" then return end
      if type(d.ballSheetW) ~= "number"
          or type(d.ballSheetH) ~= "number" then
        return
      end
      local lv = love
      if type(lv) ~= "table" or type(lv.image) ~= "table"
          or type(lv.graphics) ~= "table" then
        return
      end
      local root = "data/generated/gba/pokemon/battle/ball_open"
      pcall(function()
        local Extract = SP.require("src.import.gba.extract_island1")
        if type(Extract) == "table"
            and type(Extract.CACHE_ROOT) == "string" then
          root = Extract.CACHE_ROOT .. "/pokemon/battle/ball_open"
        end
      end)
      local rgba = nil
      pcall(function()
        local Dataset = SP.require("src.core.game3.dataset")
        local c = type(Dataset) == "table" and Dataset.cache
          and Dataset.cache()
        if c ~= nil and type(c.read) == "function" then
          rgba = c:read(root .. "/" .. d.ballSheet)
        end
      end)
      if type(rgba) ~= "string" then return end
      if #rgba < d.ballSheetW * d.ballSheetH * 4 then return end
      local ok, id = pcall(lv.image.newImageData,
        d.ballSheetW, d.ballSheetH, "rgba8", rgba)
      if not ok or id == nil then return end
      local okI, img = pcall(lv.graphics.newImage, id)
      if not okI or img == nil then return end
      pcall(function() img:setFilter("nearest", "nearest") end)
      ballSheetCache = img
    end)
    if ballSheetCache == nil then ballSheetCache = false end
    return ballSheetCache or nil
  end
  firstOwnedBall = function()
    local found = nil
    pcall(function()
      local s = SP.session()
      local bag = type(s) == "table" and s.bag or nil
      local Bag = SP.require("src.core.game3.bag")
      if type(Bag) ~= "table" or type(Bag.get) ~= "function"
          or type(bag) ~= "table" then
        return
      end
      for id = 1, 12 do
        if id ~= BALL_ID then
          local ok, q = pcall(Bag.get, bag, id)
          if ok and math.floor(tonumber(q) or 0) > 0 then
            found = id
            return
          end
        end
      end
    end)
    return found
  end
  equippedId = function()
    if type(seq) == "table" then
      local b = math.floor(tonumber(seq.ballId) or 0)
      if b >= 1 and b <= 12 then return b end
    end
    if type(SP.equippedBall) == "function" then
      local v = math.floor(tonumber(SP.equippedBall()) or 5)
      if v >= 1 and v <= 12 then
        if v ~= BALL_ID then return v end
        return firstOwnedBall() or BALL_ID
      end
    end
    return firstOwnedBall() or BALL_ID
  end
  equippedCount = function()
    local bid = equippedId()    if bid == BALL_ID then
      return 0
    end
    local n = 0
    pcall(function()
      local s = SP.session()
      local bag = type(s) == "table" and s.bag or nil
      local Bag = SP.require("src.core.game3.bag")
      if type(Bag) == "table" and type(Bag.get) == "function"
          and type(bag) == "table" then
        local ok, q = pcall(Bag.get, bag, bid)
        if ok then n = math.floor(tonumber(q) or 0) end
      end
    end)
    if n < 0 then n = 0 end
    return n
  end
  throwBallName = function()
    local name = nil
    pcall(function()
      local ItemsData = SP.require("src.core.game3.items_data")
      if type(ItemsData) == "table"
          and type(ItemsData.displayName) == "function" then
        local ok, v = pcall(ItemsData.displayName, equippedId())
        if ok and type(v) == "string" and v ~= "" then name = v end
      end
    end)
    return name or "BALL"
  end
  local function safariBallId()
    local id = 2
    pcall(function()
      local BallOpen = SP.require("src.core.game3.battle.ball_open")
      if type(BallOpen) == "table"
          and type(BallOpen.ballIdForItem) == "function" then
        local ok, v = pcall(BallOpen.ballIdForItem, equippedId())
        if ok and tonumber(v) ~= nil then id = math.floor(v) end
      end
    end)
    if id < 0 or id > 11 then id = 2 end
    return id
  end
  local function ballQuad(frame)
    local img = ballSheet()
    if img == nil then return nil end
    local id = safariBallId()
    frame = math.max(0, math.min(2, math.floor(tonumber(frame) or 0)))
    local key = id * 3 + frame
    local q = ballQuadCache[key]
    if q == nil then
      local quad = nil
      pcall(function()
        local iw, ih = img:getDimensions()
        quad = love.graphics.newQuad(id * 16, frame * 16,
          16, 16, iw, ih)
      end)
      if quad == nil then return nil end
      ballQuadCache[key] = quad
      q = quad
    end
    return img, q
  end
  ballFrame = function(s)
    if s.phase == "gulp" then
      return math.floor((tonumber(s.t) or 0) / 0.083) % 2 + 1
    end
    return 0
  end
  drawBall = function(wx, wy, scx, scy, alpha, rot, frame)
    local img, q = ballQuad(frame or 0)
    if img == nil or q == nil then return end
    pcall(function()
      local lv = love
      if type(lv) ~= "table" or type(lv.graphics) ~= "table" then
        return
      end
      lv.graphics.setColor(1, 1, 1, alpha)
      lv.graphics.draw(img, q, wx, wy, rot or 0, scx, scy, 8, 8)
      lv.graphics.setColor(1, 1, 1, 1)
    end)
  end
  drawShadow = function(wx, wy, rx, ry, alpha)
    pcall(function()
      local lv = love
      if type(lv) ~= "table" or type(lv.graphics) ~= "table" then
        return
      end
      if type(lv.graphics.ellipse) ~= "function" then return end
      lv.graphics.setColor(0, 0, 0, alpha)
      lv.graphics.ellipse("fill", wx, wy, rx, ry)
      lv.graphics.setColor(1, 1, 1, 1)
    end)
  end
  local function useFont()
    local lv = love
    if type(lv) ~= "table" or type(lv.graphics) ~= "table" then
      return nil
    end
    if fontCache ~= nil then
      local ok, set = pcall(lv.graphics.setFont, fontCache)
      if ok and set ~= false then return fontCache end
    end
    if type(lv.graphics.newFont) == "function" then
      local ok, f = pcall(lv.graphics.newFont, 14)
      if ok and f ~= nil then
        fontCache = f
        pcall(lv.graphics.setFont, f)
        return f
      end
    end
    return nil
  end
  local function outlinePrint(s, x, y)
    local lv = love
    if type(lv) ~= "table" or type(lv.graphics) ~= "table" then return end
    if type(lv.graphics.print) ~= "function" then return end
    lv.graphics.setColor(0, 0, 0, 1)
    lv.graphics.print(s, x - 1, y)
    lv.graphics.print(s, x + 1, y)
    lv.graphics.print(s, x, y - 1)
    lv.graphics.print(s, x, y + 1)
    lv.graphics.setColor(1, 1, 1, 1)
    lv.graphics.print(s, x, y)
    lv.graphics.setColor(1, 1, 1, 1)
  end
  local function drawToasts(v)
    if #toasts == 0 then return end
    pcall(function()
      local lv = love
      if type(lv) ~= "table" or type(lv.graphics) ~= "table" then
        return
      end
      local font = useFont()
      local scx, scy = scalesOf(v)
      local gx = tonumber(v.gameX) or 0
      local gy = tonumber(v.gameY) or 0
      -- gameWidth is already window px (240*scaleX); the old
      -- code multiplied by scale a second time and pushed toasts
      -- right (the earlier off-right-edge screenshot).
      local gw = tonumber(v.gameWidth) or 240 * scx
      for i, t in ipairs(toasts) do
        local y = gy + (160 - 22 - (i - 1) * 18) * scy
        local alpha = 1
        if t.t < 0.5 then alpha = math.max(0, t.t / 0.5) end
        local text = tostring(t.text)
        local w = gw * 0.9
        if font ~= nil and type(font.getWidth) == "function" then
          local ok, fw = pcall(font.getWidth, font, text)
          if ok and tonumber(fw) ~= nil then w = fw end
        end
        -- never run off-screen (hidpi fonts can measure wider than
        -- the fallback estimate): center when it fits, else pad left.
        local x = gx + (gw - w) / 2
        if w > gw - 8 then x = gx + 4 end
        if x < gx then x = gx + 4 end
        lv.graphics.setColor(0, 0, 0, 0.1 * alpha)
        if type(lv.graphics.rectangle) == "function" then
          local rx, rw = x - 4, w + 8
          if rw > gw then rx, rw = gx, gw end
          lv.graphics.rectangle("fill", rx, y - 2, rw, 18)
        end
        lv.graphics.setColor(1, 1, 1, alpha)
        lv.graphics.print(text, x, y)
        lv.graphics.setColor(1, 1, 1, 1)
      end
    end)
  end
  -- TAP DEBUG overlay: red crosses where taps registered, green
  -- boxes where the mod thinks each visible mon's occupied tile is
  -- (through that mon's own draw record). Cross off the finger =
  -- taps misregister; box off its mon = record mapping is off.
  local function drawTapMarks(v)
    pcall(function()
      local lv = love
      if type(lv) ~= "table" or type(lv.graphics) ~= "table" then
        return
      end
      local scx, scy = scalesOf(v)
      local gx = tonumber(v.gameX) or 0
      local gy = tonumber(v.gameY) or 0
      local now = SP.now()
      if type(lv.graphics.line) == "function" then
        lv.graphics.setColor(1, 0.15, 0.15, 1)
        for i = #tapMarks, 1, -1 do
          local m = tapMarks[i]
            if type(m) ~= "table" or (tonumber(m.untilT) or 0) < now then
              table.remove(tapMarks, i)
            else
            local mx, my = tonumber(m.x), tonumber(m.y)
            local cx, cy = nil, nil
            if mx ~= nil and my ~= nil then
              cx, cy = mx, my
            else
              cx = gx + (tonumber(m.gx) or 0) * scx
              cy = gy + (tonumber(m.gy) or 0) * scy
            end
              local rx, ry = 6 * scx, 6 * scy
            lv.graphics.line(cx - rx, cy, cx + rx, cy)
            lv.graphics.line(cx, cy - ry, cx, cy + ry)
          end
        end
      end
      local boxed = false
      pcall(function()
        if type(lv.graphics.rectangle) ~= "function" then return end
        local exCamX, exCamY = worldCam()
        if exCamX == nil then return end
        local exWox, exWoy, exWsx, exWsy = worldBlit()
        if exWox == nil then return end
        if ownField.vw == nil then return end
        local exFs = freshSerial()
        if exFs == nil then return end
        boxed = true
        eachTarget(function(a)
          local tx, ty = monTile(a)
          if tx == nil then return end
          local asx, asy, ast, apx0, apy0 = actorScreen(a)
          if asx == nil or ast ~= exFs then return end
          local ex0 = exWox + (tx * 16 - exCamX) * exWsx
          local ey0 = exWoy + (ty * 16 - exCamY) * exWsy
          lv.graphics.setColor(0.2, 1, 0.2, 1)
          lv.graphics.rectangle("line", ex0, ey0, 16 * exWsx, 16 * exWsy)
        end)
      end)
      if type(lv.graphics.rectangle) == "function" then
        local fs = freshSerial()
        local ccx, ccy = viewInfo()
        if not boxed and fs ~= nil then
          lv.graphics.setColor(0.2, 1, 0.2, 1)
          eachTarget(function(a)
            local tx, ty = monTile(a)
            if tx == nil then return end
            local sx, sy, s, px0, py0 = actorScreen(a)
            if sx == nil or s ~= fs then return end
            local scx0 = gx + (sx + (tx * 16 - px0) - ccx) * scx
            local scy0 = gy + (sy + (ty * 16 - py0) - ccy) * scy
            lv.graphics.rectangle("line", scx0, scy0,
              16 * scx, 16 * scy)
          end)
        end
      end
      lv.graphics.setColor(1, 1, 1, 1)
    end)
  end
  local function berryCount(id)
    local n = 0
    pcall(function()
      local s = SP.session()
      local bag = type(s) == "table" and s.bag or nil
      local Bag = SP.require("src.core.game3.bag")
      if type(Bag) == "table" and type(Bag.get) == "function"
          and type(bag) == "table" then
        local ok, q = pcall(Bag.get, bag, id)
        if ok then n = math.floor(tonumber(q) or 0) end
      end
    end)
    if n < 0 then n = 0 end
    return n
  end
  local function berryName(kind, id)
    local name = nil
    pcall(function()
      if type(SP.berryDef) == "function" then
        local ok, def = pcall(SP.berryDef, kind)
        if ok and type(def) == "table" and type(def.name) == "string"
            and def.name ~= "" then
          name = def.name
        end
      end
    end)
    if name == nil then
      pcall(function()
        local ItemsData = SP.require("src.core.game3.items_data")
        if type(ItemsData) == "table"
            and type(ItemsData.displayName) == "function" then
          local ok, v = pcall(ItemsData.displayName, id)
          if ok and type(v) == "string" and v ~= "" then name = v end
        end
      end)
    end
    return name or "BERRY"
  end
  local function useBerryCell(kind)
    if type(SP.tryUseBerry) ~= "function" then return false end
    local ok, err = SP.tryUseBerry(kind)
    if ok then return true end
    if err == "active" then
      toast("Another berry is in effect!")
    else
      local def = nil
      if type(SP.berryDef) == "function" then
        local okD, d = pcall(SP.berryDef, kind)
        if okD and type(d) == "table" then def = d end
      end
      toast("No " .. berryName(kind, def ~= nil and def.id or 0) .. " left!")
    end
    return true
  end
  local function drawClock(v, gx, gy, scx, scy)
    local lv = love
    if type(lv) ~= "table" or type(lv.graphics) ~= "table" then return end
    if type(hudEyeBox) ~= "table" then return end
    local font = useFont()
    local label = gameClock()
    local tw = 40
    if font ~= nil and type(font.getWidth) == "function" then
      local ok, a = pcall(font.getWidth, font, label)
      if ok and tonumber(a) ~= nil then tw = a end
    end
    local fh = 16
    if font ~= nil and type(font.getHeight) == "function" then
      local ok, h = pcall(font.getHeight, font)
      if ok and tonumber(h) ~= nil then fh = h end
    end
    local ex0 = tonumber(hudEyeBox.x0) or 0
    local ey0 = tonumber(hudEyeBox.y0) or 0
    local ew = tonumber(hudEyeBox.w) or 0
    local eh = tonumber(hudEyeBox.h) or 0
    local cw = tw + 8
    local chh = 16 * scy + 8
    local x0 = ex0 + ew - cw
    local y0 = ey0 + eh + 4
    outlinePrint(label, x0 + 4, y0 + 4 + (chh - fh) / 2)
  end
  local function drawEye(v, gx, gy, scx, scy, hidden)
    local lv = love
    if type(lv) ~= "table" or type(lv.graphics) ~= "table" then return end
    local gw = tonumber(v.gameWidth) or 240 * scx
    local pad = 4
    local boxH = 16 * scy + 8
    local boxW = 16 * scx + 8
    local x0, y0 = gx + gw - boxW - pad, gy + pad
    hudEyeBox = { x0 = x0, y0 = y0, w = boxW, h = boxH }
    if type(lv.graphics.rectangle) == "function" then
      lv.graphics.setColor(0, 0, 0, 0.1)
      lv.graphics.rectangle("fill", x0, y0, boxW, boxH)
    end
    local cx, cy = x0 + boxW / 2, y0 + boxH / 2
    local rx = math.min(boxW, boxH) * 0.30
    local ry = rx * 0.62
    if type(lv.graphics.ellipse) == "function" then
      lv.graphics.setColor(0, 0, 0, 1)
      lv.graphics.ellipse("line", cx, cy, rx + 1, ry + 1)
      lv.graphics.setColor(1, 1, 1, 1)
      lv.graphics.ellipse("line", cx, cy, rx, ry)
    end
    if type(lv.graphics.circle) == "function" then
      lv.graphics.setColor(0, 0, 0, 1)
      lv.graphics.circle("fill", cx, cy, math.max(1, rx * 0.35) + 1)
      lv.graphics.setColor(1, 1, 1, 1)
      lv.graphics.circle("fill", cx, cy, math.max(1, rx * 0.35))
    end
    if hidden and type(lv.graphics.line) == "function" then
      lv.graphics.setColor(0, 0, 0, 1)
      lv.graphics.line(x0 + 3, y0 + 4, x0 + boxW - 4, y0 + boxH - 4)
      lv.graphics.line(x0 + 5, y0 + 4, x0 + boxW - 4, y0 + boxH - 4)
      lv.graphics.line(x0 + 4, y0 + 3, x0 + boxW - 4, y0 + boxH - 4)
      lv.graphics.line(x0 + 4, y0 + 5, x0 + boxW - 4, y0 + boxH - 4)
      lv.graphics.setColor(1, 0.2, 0.2, 1)
      lv.graphics.line(x0 + 4, y0 + 4, x0 + boxW - 4, y0 + boxH - 4)
    end
    lv.graphics.setColor(1, 1, 1, 1)
  end
  local function drawStockHud(v)
    pcall(function()
      local lv = love
      if type(lv) ~= "table" or type(lv.graphics) ~= "table" then
        return
      end
      SP.tick()
      local scx, scy = scalesOf(v)
      local gx = tonumber(v.gameX) or 0
      local gy = tonumber(v.gameY) or 0
      local hidden = hudHidden()
      pcall(drawEye, v, gx, gy, scx, scy, hidden)
      pcall(drawClock, v, gx, gy, scx, scy)
      if hidden then
        hudBox = nil
        hudBerryBoxes = nil
        return
      end
      local stock = equippedCount()
      local font = useFont()
      local line1 = "x " .. stock
      local fh = 16
      if font ~= nil and type(font.getHeight) == "function" then
        local ok, h = pcall(font.getHeight, font)
        if ok and tonumber(h) ~= nil then fh = h end
      end
      local w1 = 40
      if font ~= nil and type(font.getWidth) == "function" then
        local ok, a = pcall(font.getWidth, font, line1)
        if ok and tonumber(a) ~= nil then w1 = a end
      end
      local pad = 4
      local bw, bh = 16 * scx, 16 * scy
      local x0, y0 = gx + pad, gy + pad
      local boxW = bw + 6 + w1 + 8
      local boxH = bh + 8
      hudBox = { x0 = x0, y0 = y0, w = boxW, h = boxH }
      if type(lv.graphics.rectangle) == "function" then
        lv.graphics.setColor(0, 0, 0, 0.1)
        lv.graphics.rectangle("fill", x0, y0, boxW, boxH)
      end
      local img, q = ballQuad(0)
      if img ~= nil and q ~= nil then
        lv.graphics.setColor(1, 1, 1, 1)
        lv.graphics.draw(img, q, x0 + 4, y0 + 4, 0, scx, scy)
      end
      outlinePrint(line1, x0 + 4 + bw + 6, y0 + 4 + (bh - fh) / 2)
      local berryRows = { { "razz", "pinap" }, { "grazz", "spinap" } }
      local boxes = {}
      local brow = y0 + boxH + 4
      local activeKind = nil
      if type(SP.berryKind) == "function" then
        local okK, k = pcall(SP.berryKind)
        if okK and type(k) == "string" then activeKind = k end
      end
      for _, row in ipairs(berryRows) do
        local bx = x0
        for _, kind in ipairs(row) do
          local bid = 0
          if type(SP.berryDef) == "function" then
            local okD, def = pcall(SP.berryDef, kind)
            if okD and type(def) == "table" then
              bid = math.floor(tonumber(def.id) or 0)
            end
          end
          local line = "x " .. berryCount(bid)
          local tw = 40
          if font ~= nil and type(font.getWidth) == "function" then
            local okW, a = pcall(font.getWidth, font, line)
            if okW and tonumber(a) ~= nil then tw = a end
          end
          local iw, ih = 16 * scx, 16 * scy
          local cw, chh = iw + 6 + tw + 8, ih + 8
          if type(lv.graphics.rectangle) == "function" then
            lv.graphics.setColor(0, 0, 0, 0.1)
            lv.graphics.rectangle("fill", bx, brow, cw, chh)
          end
          local bimg = nil
          if type(SP.berryImage) == "function" then
            local okI, v = pcall(SP.berryImage, kind)
            if okI then bimg = v end
          end
          if bimg ~= nil then
            lv.graphics.setColor(1, 1, 1, 1)
            pcall(function()
              lv.graphics.draw(bimg, bx + 4, brow + 4, 0, iw / 24, ih / 24)
            end)
          end
          outlinePrint(line, bx + 4 + iw + 6, brow + 4 + (ih - fh) / 2)
          if activeKind == kind
              and type(lv.graphics.rectangle) == "function" then
            lv.graphics.setColor(0.2, 1, 0.2, 1)
            lv.graphics.rectangle("line", bx, brow, cw, chh)
            lv.graphics.setColor(1, 1, 1, 1)
          end
          boxes[#boxes + 1] = { kind = kind, x0 = bx, y0 = brow,
            w = cw, h = chh }
          bx = bx + cw + 4
        end
        brow = brow + (16 * scy + 8) + 4
      end
      hudBerryBoxes = boxes
    end)
  end
  local function hudDraw(viewport)
    local v = viewport
    if type(v) ~= "table" then return end
    local scx, scy = scalesOf(v)
    local gx = tonumber(v.gameX) or 0
    local gy = tonumber(v.gameY) or 0
    local camX, camY = exactCam()
    -- record space is world-canvas px, screen space is UI-canvas px
    -- (see viewInfo): subtract the growth back off when placing.
    local ccx, ccy = viewInfo()
    local s = seq
    if s ~= nil and not actorGone(s.actor) and not drawBallExact(s) then
      local bx, by = s.lx, s.ly
      local rot = 0
      if s.phase == "fly" then
        local e = s.dur > 0 and math.min(1, s.t / s.dur) or 1
        bx = s.sx + (s.lx - s.sx) * e
        by = s.sy + (s.ly - s.sy) * e - 24 * math.sin(math.pi * e)
      elseif s.phase == "shake" then
        local rock = rockOf((s.t % SHAKE_DUR) / SHAKE_DUR)
        bx = bx + rock * 2.5
        rot = rock * 0.32
      end
      -- world→screen through the actor's own draw record (camera
      -- cancels out); global camera only for actors without one.
      -- Records older than the freshest draw are despawns-in-waiting
      -- and must not place the ball.
      local asx, asy, ss, px0, py0 = actorScreen(s.actor)
      local fs = freshSerial()
      local useRec = asx ~= nil and (fs == nil or ss == fs)
      local function toScreen(wx, wy)
        local qx, qy
        if useRec then
          qx, qy = asx + (wx - px0), asy + (wy - py0)
        elseif camX ~= nil then
          qx, qy = wx - camX, wy - camY
        else
          return nil
        end
        return gx + (qx - ccx) * scx, gy + (qy - ccy) * scy
      end
      local alpha = 1
      if s.phase == "fade" then
        alpha = math.max(0, 1 - s.t / FADE_DUR)
      end
      local shx, shy = toScreen(s.lx, s.ly + 7)
      if shx ~= nil then
        drawShadow(shx, shy, 6 * scx, 2.5 * scy, 0.32 * alpha)
      end
      local ox, oy = toScreen(bx, by)
      if ox ~= nil then
        drawBall(ox, oy, scx, scy, alpha, rot, ballFrame(s))
      end
    end
    if tapDebug() then drawTapMarks(v) end
    drawStockHud(v)
    drawToasts(v)
  end
  if mod.hooks and type(mod.hooks.wrap) == "function" then
    mod.hooks:wrap("encounter.roll", function(next, encDef, ctx)
      if owOn() and untamedSuppress() then return nil end
      return next(encDef, ctx)
    end)
    mod.hooks:wrap("input.step", function(next, game, dt)
      next(game, dt)
      pcall(function()
        if not owOn() then return end
        local mapId = curMap()
        if mapId ~= lastMap then
          dropSeq()
          toasts = {}
          lastMap = mapId
        end
        stepTick(dt)
      end)
    end)
    mod.hooks:wrap("input.pointer", function(next, game, ev)
      if type(ev) == "table" and ev.phase == "pressed" and owOn() then
        local v = viewportCache
        if type(v) == "table" and tonumber(v.gameX) ~= nil
            and tonumber(v.gameY) ~= nil then
          local scx, scy = scalesOf(v)
          local ex, ey = tonumber(ev.x), tonumber(ev.y)
          if scx > 0 and scy > 0 and ex ~= nil and ey ~= nil then
            local gx = (ex - tonumber(v.gameX)) / scx
            local gy = (ey - tonumber(v.gameY)) / scy
            if tapDebug() then
              tapMarks[#tapMarks + 1] =
                { gx = gx, gy = gy, x = ex, y = ey, untilT = SP.now() + 4 }
              while #tapMarks > 8 do table.remove(tapMarks, 1) end
            end
            if type(hudEyeBox) == "table" then
              local ex0 = tonumber(hudEyeBox.x0) or 0
              local ey0 = tonumber(hudEyeBox.y0) or 0
              local ew = tonumber(hudEyeBox.w) or 0
              local eh = tonumber(hudEyeBox.h) or 0
              if ex >= ex0 and ex <= ex0 + ew
                  and ey >= ey0 and ey <= ey0 + eh then
                pcall(setHudHidden, not hudHidden())
                return true
              end
            end
            if seq == nil and type(hudBox) == "table"
                and type(SP.openBallsBag) == "function" then
              local bx = tonumber(hudBox.x0) or 0
              local by = tonumber(hudBox.y0) or 0
              local bw = tonumber(hudBox.w) or 0
              local bh = tonumber(hudBox.h) or 0
              if ex >= bx and ex <= bx + bw
                  and ey >= by and ey <= by + bh then
                local okB, opened = pcall(SP.openBallsBag)
                if okB and opened then return true end
              end
            end
            if seq == nil and type(hudBerryBoxes) == "table" then
              for _, cell in ipairs(hudBerryBoxes) do
                local cx0 = tonumber(cell.x0) or 0
                local cy0 = tonumber(cell.y0) or 0
                local cw = tonumber(cell.w) or 0
                local chh = tonumber(cell.h) or 0
                if ex >= cx0 and ex <= cx0 + cw
                    and ey >= cy0 and ey <= cy0 + chh then
                  local okU, used = pcall(useBerryCell, cell.kind)
                  if okU and used then return true end
                end
              end
            end
            local okE, usedE, exactE = pcall(tryThrowExact, ex, ey)
            if okE and exactE then
              if usedE then return true end
            else
              local ok, consumed = pcall(tryThrow, gx, gy)
              if ok and consumed then return true end
            end
          end
        end
      end
      return next(game, ev)
    end)
    mod.hooks:wrap("render.hud", function(next, game, viewport)
      next(game, viewport)
      pcall(function()
        if type(viewport) == "table" then viewportCache = viewport end
        if not owOn() then hudBox = nil hudBerryBoxes = nil hudEyeBox = nil return end
        if not fieldClear() then hudBox = nil hudBerryBoxes = nil hudEyeBox = nil return end
        hudDraw(viewport)
      end)
    end)
  else
    mod.log:warn("safari-plus: overworld catch not installed (no hooks)")
    return
  end
  if mod.events and type(mod.events.on) == "function" then
    mod.events:on("map.entered", function()
      dropSeq()
      toasts = {}
      lastMap = curMap()
    end)
    mod.events:on("battle.started", function()
      dropSeq()
    end)
  end
  pcall(captureField)
  mod.log:info("safari-plus: overworld catch installed")
end
