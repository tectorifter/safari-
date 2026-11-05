return function(mod)
  local SP = mod.exports.safariPlus
  if not SP then return end
  local NATIVES = SP.itemBallNatives
  if type(NATIVES) ~= "table" then return end
  local DROPS = SP.evoDrops
  if type(DROPS) ~= "table" or type(DROPS.DROPS) ~= "table" then return end
  local RECHARGE = math.floor(tonumber(DROPS.RECHARGE) or 300)
  if RECHARGE < 1 then RECHARGE = 300 end
  local ROLLS = math.floor(tonumber(DROPS.ROLLS) or 6)
  if ROLLS < 1 then ROLLS = 6 end
  local BALL_MAX = math.floor(tonumber(DROPS.BALL_MAX) or 4)
  local BERRY_MAX = math.floor(tonumber(DROPS.BERRY_MAX) or 4)
  local _unpack = table.unpack or unpack
  local function lidOf(eo)
    if type(eo) ~= "table" then return 0 end
    return eo.localId
      or (eo.def and (eo.def.localId or eo.def.index)) or 0
  end
  local function scriptOf(eo)
    if type(eo) ~= "table" then return nil end
    if type(eo.scriptKey) == "string" then return eo.scriptKey end
    if type(eo.script) == "string" then return eo.script end
    if type(eo.def) == "table" then
      if type(eo.def.scriptKey) == "string" then return eo.def.scriptKey end
      if type(eo.def.script) == "string" then return eo.def.script end
    end
    return nil
  end
  local builtFor = nil
  local byRuntime = {}
  local function natFor(label)
    if type(label) ~= "string" then return nil end
    local direct = NATIVES[label]
    if direct ~= nil then return direct end
    local Sp = SP.require("src.core.game3.scripting.space")
    local b = (type(Sp) == "table") and Sp.bundle or nil
    if type(Sp) == "table" and type(Sp.scriptKey) == "function"
        and type(b) == "table" then
      if builtFor ~= b then
        builtFor = b
        byRuntime = {}
        for key, entry in pairs(NATIVES) do
          local ok, rk = pcall(Sp.scriptKey, key)
          if ok and type(rk) == "string" then byRuntime[rk] = entry end
        end
      end
    end
    return byRuntime[label]
  end
  local function curMap()
    local s = SP.session()
    if type(s) == "table" and s.map ~= nil then
      return tostring(s.map)
    end
    return nil
  end
  local function numIdBoth(ref)
    local n = SP.numId(ref)
    if math.floor(tonumber(n) or 0) > 0 then return n end
    if type(ref) == "string" then
      local short = ref:gsub("^ITEM_", "")
      if short ~= ref then
        n = SP.numId(short)
        if math.floor(tonumber(n) or 0) > 0 then return n end
      end
    end
    return nil
  end
  local function bagQty(bag, id)
    local Bag = SP.require("src.core.game3.bag")
    if type(Bag) ~= "table" or type(Bag.get) ~= "function" then
      return 0
    end
    local ok, q = SP.try(Bag.get, bag, id)
    if not ok then return 0 end
    return math.floor(tonumber(q) or 0)
  end
  local function bagAdd(bag, id, n)
    local Bag = SP.require("src.core.game3.bag")
    if type(Bag) ~= "table" or type(Bag.add) ~= "function" then
      return 0
    end
    local before = bagQty(bag, id)
    SP.try(Bag.add, bag, id, n)
    local after = bagQty(bag, id)
    local got = after - before
    if got < 0 then got = 0 end
    return got
  end
  local function itemName(id)
    local ItemsData = SP.require("src.core.game3.items_data")
    if type(ItemsData) == "table"
        and type(ItemsData.displayName) == "function" then
      local ok, nm = pcall(ItemsData.displayName, id)
      if ok and type(nm) == "string" and nm ~= "" then return nm end
    end
    return tostring(id)
  end
  local function berryId(kind)
    if type(SP.berryDef) == "function" then
      local ok, def = pcall(SP.berryDef, kind)
      if ok and type(def) == "table" then
        return math.floor(tonumber(def.id) or 0)
      end
    end
    return nil
  end
  local eggPool = nil
  local function buildEggPool()
    if eggPool ~= nil then return eggPool end
    eggPool = {}
    pcall(function()
      local Pokemon = SP.require("src.core.game3.pokemon")
      if type(Pokemon) ~= "table"
          or type(Pokemon.name) ~= "function" then
        return
      end
      for id = 1, 2048 do
        local okN, nm = pcall(Pokemon.name, id)
        if okN and type(nm) == "string" and nm ~= ""
            and nm ~= "??????????" then
          local bad = false
          if type(SP.isLegendary) == "function" then
            local okL, leg = pcall(SP.isLegendary, id)
            if okL and leg then bad = true end
          end
          if not bad then eggPool[#eggPool + 1] = id end
        end
      end
    end)
    return eggPool
  end
  local function pickEggSpecies()
    local pool = buildEggPool()
    if #pool > 0 then
      return pool[math.random(1, #pool)]
    end
    for _ = 1, 40 do
      local s = math.random(1, 386)
      local bad = false
      pcall(function()
        if type(SP.isLegendary) == "function"
            and SP.isLegendary(s) then
          bad = true
        end
      end)
      if not bad then return s end
    end
    return nil
  end
  local function evoId(ref)
    if type(SP.evoUse) == "table"
        and type(SP.evoUse.numOf) == "function" then
      local ok, n = pcall(SP.evoUse.numOf, ref)
      if ok and math.floor(tonumber(n) or 0) > 0 then return n end
    end
    return numIdBoth(ref)
  end
  local function rollDrop(pool, totalW)
    if totalW <= 0 then return nil end
    local r = math.random() * totalW
    for _, d in ipairs(pool) do
      r = r - (tonumber(d.w) or 0)
      if r <= 0 then return d end
    end
    return nil
  end
  local function rollBundle(session, bag)
    local pool, totalW = {}, 0
    for _, d in ipairs(DROPS.DROPS) do
      local locked = false
      if type(SP.playerDropLocked) == "function" then
        local ok, v = pcall(SP.playerDropLocked, d.kind, d.ref)
        if ok and v then locked = true end
      end
      if not locked then
        pool[#pool + 1] = d
        totalW = totalW + (tonumber(d.w) or 0)
      end
    end
    local lines = {}
    local balls, berries = 0, 0
    local evoSeen, eggSeen = {}, false
    for _ = 1, ROLLS do
      local d = rollDrop(pool, totalW)
      if type(d) == "table" then
        if d.kind == "ball" then
          if balls < BALL_MAX then
            local id = numIdBoth(d.ref)
            if id ~= nil and bagAdd(bag, id, 1) > 0 then
              balls = balls + 1
              lines[#lines + 1] = "Received 1 " .. itemName(id) .. "!"
            end
          end
        elseif d.kind == "berry" then
          if berries < BERRY_MAX then
            local id = berryId(d.ref)
            if id ~= nil and id > 0 and bagAdd(bag, id, 1) > 0 then
              berries = berries + 1
              lines[#lines + 1] = "Received 1 " .. itemName(id) .. "!"
            end
          end
        elseif d.kind == "evo" then
          if not evoSeen[d.ref] then
            local id = evoId(d.ref)
            if id ~= nil and bagAdd(bag, id, 1) > 0 then
              evoSeen[d.ref] = true
              lines[#lines + 1] = "Received 1 " .. itemName(id) .. "!"
            end
          end
        elseif d.kind == "egg" then
          if not eggSeen then
            local species = pickEggSpecies()
            local okE = false
            if species ~= nil then
              pcall(function()
                local Party = SP.require("src.core.game3.party")
                if type(Party) == "table"
                    and type(Party.giveEggToPlayer) == "function" then
                  Party.giveEggToPlayer(session, species)
                  okE = true
                end
              end)
            end
            if okE then
              eggSeen = true
              lines[#lines + 1] = "Received a POKéMON EGG!"
            end
          end
        end
      end
    end
    return lines
  end
  local function getState()
    local st = nil
    pcall(function()
      if mod.save and type(mod.save.get) == "function" then
        st = mod.save:get("itemBalls", nil)
      end
    end)
    if type(st) ~= "table" then st = {} end
    return st
  end
  local function setState(st)
    pcall(function()
      if mod.save and type(mod.save.set) == "function" then
        mod.save:set("itemBalls", st)
      end
    end)
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
  local function unfreezeLid(lid)
    pcall(function()
      local Objects = SP.require("src.core.game3.objects")
      if type(Objects) == "table"
          and type(Objects.unfreeze) == "function" then
        Objects.unfreeze(lid)
      end
    end)
  end
  local function showLines(lid, lines)
    local Message = SP.require("src.ui.game3.message")
    if type(Message) ~= "table"
        or type(Message.show) ~= "function" then
      unfreezeLid(lid)
      return
    end
    local ok = pcall(Message.show, table.concat(lines, "\n"), function()
      unfreezeLid(lid)
    end)
    if not ok then unfreezeLid(lid) end
  end
  local function freezeFace(lid, game)
    pcall(function()
      local Objects = SP.require("src.core.game3.objects")
      if type(Objects) ~= "table" then return end
      if type(Objects.freeze) == "function" then
        Objects.freeze(lid)
      end
      if type(Objects.facePlayer) == "function" then
        Objects.facePlayer(lid, game)
      end
    end)
  end
  local markCool, rebuildCool, wrapOw
  if mod.hooks and type(mod.hooks.wrap) == "function" then
    mod.hooks:wrap("world.talk", function(nextFn, ...)
      local args = { ... }
      local narg = select("#", ...)
      local game = args[1]
      local eo = nil
      for i = 1, narg do
        local a = args[i]
        if type(a) == "table"
            and (a.def or a.scriptKey or a.localId) then
          eo = a
          break
        end
      end
      if type(nextFn) ~= "function" then return end
      local label = scriptOf(eo)
      local nat = natFor(label)
      if nat == nil then return nextFn(...) end
      local map = curMap() or nat.map
      if map == nil then return nextFn(...) end
      local lid = lidOf(eo)
      local key = tostring(map) .. "#" .. tostring(lid)
      pcall(wrapOw)
      local gid = nil
      if type(eo) == "table" then
        gid = eo.graphicsId
        if gid == nil and type(eo.def) == "table" then
          gid = eo.def.graphicsId or eo.def.graphics
        end
      end
      local ok = pcall(function()
        local st = getState()
        local entry = st[key]
        if type(entry) ~= "table" then entry = {} end
        local now = SP.now()
        local deadline = tonumber(entry.c) or 0
        if entry.t == true and now < deadline
            and (deadline - now) <= RECHARGE then
          freezeFace(lid, game)
          showLines(lid, { "It's empty..." })
          return
        end
        local first = entry.t ~= true
        local session = SP.session()
        local bag = (type(session) == "table") and session.bag or nil
        local lines = {}
        local granted = false
        if type(session) == "table" and type(bag) == "table" then
          local beforeP = 0
          if type(SP.playerLevel) == "function" then
            local okP, lv = pcall(SP.playerLevel)
            if okP then beforeP = math.floor(tonumber(lv) or 0) end
          end
          if first then
            local nid = numIdBoth(nat.item)
            if nid ~= nil and bagAdd(bag, nid, 1) > 0 then
              granted = true
              lines[#lines + 1] = "You found " .. itemName(nid) .. "!"
            end
          end
          local bundle = rollBundle(session, bag)
          for _, line in ipairs(bundle) do
            granted = true
            lines[#lines + 1] = line
          end
          if granted and type(SP.playerNotePokestop) == "function" then
            pcall(SP.playerNotePokestop)
          end
          if type(SP.playerLevel) == "function" then
            local okP, lv = pcall(SP.playerLevel)
            if okP and math.floor(tonumber(lv) or 0) > beforeP then
              lines[#lines + 1] = "Player level up! Lv " .. math.floor(lv)
            end
          end
          if type(SP.playerTakePendingUps) == "function" then
            pcall(SP.playerTakePendingUps)
          end
        end
        if #lines == 0 then
          if first then
            lines[#lines + 1] = "Your bag is full!"
          else
            lines[#lines + 1] = "It's empty..."
          end
        else
          se("SE_BALL_CLICK")
        end
        freezeFace(lid, game)
        st[key] = { t = true, c = SP.now() + RECHARGE, map = map,
          x = nat.x, y = nat.y, g = gid }
        setState(st)
        markCool(map, nat.x, nat.y, gid, SP.now() + RECHARGE)
        showLines(lid, lines)
      end)
      if not ok then
        pcall(function()
          mod.log:warn("safari-plus: item ball kept after error")
        end)
        local st = getState()
        st[key] = { t = true, c = SP.now() + RECHARGE, map = map,
          x = nat.x, y = nat.y, g = gid }
        setState(st)
        markCool(map, nat.x, nat.y, gid, SP.now() + RECHARGE)
        unfreezeLid(lid)
        showLines(lid, { "It's empty..." })
      end
      return true
    end)
  end
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
  local cool = {}
  local function coolKey(map, x, y)
    return tostring(map) .. "\0" .. tostring(x) .. "\0" .. tostring(y)
  end
  markCool = function(map, x, y, gid, deadline)
    local tx = math.floor(tonumber(x) or -1)
    local ty = math.floor(tonumber(y) or -1)
    if map == nil or tx < 0 or ty < 0 then return end
    cool[coolKey(map, tx, ty)] = { t = true, c = deadline, map = map,
      x = tx, y = ty, g = gid }
  end
  rebuildCool = function()
    local fresh = {}
    local st = getState()
    if type(st) == "table" then
      for _, entry in pairs(st) do
        if type(entry) == "table" and entry.t == true
            and entry.map ~= nil then
          local tx = math.floor(tonumber(entry.x) or -1)
          local ty = math.floor(tonumber(entry.y) or -1)
          if tx >= 0 and ty >= 0 then
            fresh[coolKey(entry.map, tx, ty)] = entry
          end
        end
      end
    end
    cool = fresh
  end
  wrapOw = function()
    local Ow = SP.require("src.core.game3.ow_sprites")
    if type(Ow) ~= "table" or type(Ow.draw) ~= "function" then return end
    if Ow.__spIbGrayWrapped then return end
    Ow.__spIbGrayWrapped = true
    local raw = Ow.draw
    Ow.draw = function(gid, px, py, camX, camY, facing, walkPhase,
        stepFlip, opts)
      local drew = raw(gid, px, py, camX, camY, facing, walkPhase,
        stepFlip, opts)
      pcall(function()
        if drew ~= true then return end
        if next(cool) == nil then return end
        local tx = math.floor((tonumber(px) or -1) / 16)
        local ty = math.floor((tonumber(py) or -1) / 16)
        if tx < 0 or ty < 0 then return end
        local map = curMap()
        if map == nil then return end
        local entry = cool[coolKey(map, tx, ty)]
        if type(entry) ~= "table" then return end
        local now = SP.now()
        local deadline = tonumber(entry.c) or 0
        if entry.t ~= true or now >= deadline
            or (deadline - now) > RECHARGE then
          cool[coolKey(map, tx, ty)] = nil
          return
        end
        if not fieldClear() then return end
        if entry.g ~= nil and tonumber(gid) ~= tonumber(entry.g) then
          return
        end
        local spr = nil
        if type(Ow.getDraw) == "function" then
          local okG, g = pcall(Ow.getDraw, gid)
          if okG then spr = g end
        end
        if type(spr) ~= "table" or spr.image == nil
            or type(spr.quads) ~= "table" then
          return
        end
        local frame, flip = 0, false
        if type(Ow.pose) == "function" then
          local okP, f, fl = pcall(Ow.pose, spr, facing, walkPhase,
            stepFlip, opts)
          if okP and tonumber(f) ~= nil then
            frame, flip = f, fl
          end
        end
        local q = spr.quads[frame]
        local w = math.floor(tonumber(spr.width) or 0)
        local h = math.floor(tonumber(spr.height) or 0)
        if q == nil or w < 1 or h < 1 then return end
        local lv = love
        if type(lv) ~= "table" or type(lv.graphics) ~= "table" then
          return
        end
        local sx = px - camX + (16 - w) / 2
        local sy = py - camY + 16 - h
        local alpha = 0.85
        if type(opts) == "table" and tonumber(opts.alpha) ~= nil then
          alpha = 0.85 * tonumber(opts.alpha)
        end
        lv.graphics.setColor(0.55, 0.55, 0.58, alpha)
        if flip then
          lv.graphics.draw(spr.image, q, sx + w, sy, 0, -1, 1)
        else
          lv.graphics.draw(spr.image, q, sx, sy)
        end
        lv.graphics.setColor(1, 1, 1, 1)
      end)
      return drew
    end
  end
  rebuildCool()
  wrapOw()
  if mod.events and type(mod.events.on) == "function" then
    mod.events:on("map.entered", function()
      pcall(rebuildCool)
      pcall(wrapOw)
    end)
    mod.events:on("save.loaded", function()
      pcall(rebuildCool)
      pcall(wrapOw)
    end)
  end
  mod.log:info("safari-plus: item balls installed")
end
