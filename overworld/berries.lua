return function(mod)
  local SP = mod.exports.safariPlus
  if not SP then return end
  local DEFS = {
    razz = { id = 148, name = "RAZZ BERRY", catch = 1.5, candy = 1 },
    pinap = { id = 152, name = "PINAP BERRY", catch = 1.2, candy = 2 },
    grazz = { id = 9401, name = "GOLDEN RAZZ", catch = 2.5, candy = 1 },
    spinap = { id = 9402, name = "SILVER PINAP", catch = 1.8, candy = 3 },
  }
  local ORDER = { "razz", "pinap", "grazz", "spinap" }
  local BY_ID = {}
  for _, k in ipairs(ORDER) do BY_ID[DEFS[k].id] = k end
  local function defOf(kind)
    if type(kind) == "string" and DEFS[kind] ~= nil then
      return DEFS[kind], kind
    end
    local n = math.floor(tonumber(SP.numId(kind)) or 0)
    if BY_ID[n] ~= nil then return DEFS[BY_ID[n]], BY_ID[n] end
    return nil
  end
  local function isCustomId(id)
    local _, k = defOf(id)
    return k == "grazz" or k == "spinap"
  end
  function SP.berryDef(kind)
    local def = defOf(kind)
    return def
  end
  function SP.berryKind()
    local s = SP.session()
    local b = type(s) == "table" and s.safariBerry or nil
    local k = type(b) == "table" and b.kind or nil
    if type(k) == "string" and DEFS[k] ~= nil then return k end
    return nil
  end
  function SP.armBerry(kind)
    local def, k = defOf(kind)
    if def == nil then return false end
    local s = SP.session()
    if type(s) ~= "table" then return false end
    s.safariBerry = { m = def.catch, kind = k }
    return true
  end
  function SP.berryCandyMult()
    local k = SP.berryKind()
    if k == nil then return 1 end
    return tonumber(DEFS[k].candy) or 1
  end
  local function bagCount(id)
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
  function SP.tryUseBerry(kind)
    local def, k = defOf(kind)
    if def == nil then return false, "bad" end
    if SP.berryKind() ~= nil then return false, "active" end
    if bagCount(def.id) <= 0 then return false, "empty" end
    local before = bagCount(def.id)
    pcall(function()
      local s = SP.session()
      local bag = type(s) == "table" and s.bag or nil
      local Bag = SP.require("src.core.game3.bag")
      if type(Bag) == "table" and type(Bag.remove) == "function"
          and type(bag) == "table" then
        pcall(Bag.remove, bag, def.id, 1)
      end
    end)
    if bagCount(def.id) >= before then return false, "empty" end
    if not SP.armBerry(k) then return false, "empty" end
    return true
  end
  local imgCache = {}
  local TINT = {
    grazz = { base = 148, r = 1.0, g = 0.82, b = 0.35 },
    spinap = { base = 152, r = 0.78, g = 0.8, b = 0.88 },
  }
  local rseAtlas = nil
  local function rseCrop(id)
    local n = math.floor(tonumber(SP.numId(id)) or 0)
    if n < 0 then return nil end
    if rseAtlas == nil then
      pcall(function()
        local BC = SP.require("src.ui.game3.rse.bag_chrome")
        local Kit = SP.require("src.ui.game3.rse.scene_kit")
        local lv = love
        if type(BC) ~= "table" or type(Kit) ~= "table" then return end
        if type(BC.manifest) ~= "function" then return end
        if type(Kit.rgbaImage) ~= "function" then return end
        if type(lv) ~= "table" or type(lv.graphics) ~= "table" then return end
        local m = BC.manifest()
        local icons = type(m) == "table" and m.icons or nil
        if type(icons) ~= "table" then return end
        local count = math.floor(tonumber(icons.count) or 0)
        local w = math.floor(tonumber(icons.w) or 0)
        local h = math.floor(tonumber(icons.h) or 0)
        if count < 1 or w < 1 or h < 1 then return end
        if type(icons.rgba) ~= "string" then return end
        local img = Kit.rgbaImage(icons.rgba, icons.w, icons.h)
        if img == nil then return end
        rseAtlas = { img = img, count = count, w = w, h = h }
      end)
    end
    local A = rseAtlas
    if type(A) ~= "table" then return nil end
    if n >= A.count then n = A.count - 1 end
    local out = nil
    pcall(function()
      local lv = love
      local cv = lv.graphics.newCanvas(24, 24)
      if cv == nil then return end
      local q = lv.graphics.newQuad(0, n * 24, 24, 24, A.w, A.h)
      if q == nil then return end
      lv.graphics.push()
      lv.graphics.setCanvas(cv)
      lv.graphics.clear(0, 0, 0, 0)
      lv.graphics.setColor(1, 1, 1, 1)
      lv.graphics.draw(A.img, q, 0, 0)
      lv.graphics.setCanvas()
      lv.graphics.pop()
      lv.graphics.setColor(1, 1, 1, 1)
      pcall(function() cv:setFilter("nearest", "nearest") end)
      out = cv
    end)
    return out
  end
  local function nativeIcon(id)
    local img = nil
    pcall(function()
      if type(SP.berryNativeIcon) == "function" then
        img = SP.berryNativeIcon(id)
      end
    end)
    local ok = false
    pcall(function()
      if img ~= nil and type(img.getDimensions) == "function" then
        local w = img:getDimensions()
        if math.floor(tonumber(w) or 0) > 0 then ok = true end
      end
    end)
    if ok then return img end
    return rseCrop(id)
  end
  local function bakeTint(img, r, g, b)
    local lv = love
    if type(lv) ~= "table" or type(lv.graphics) ~= "table" then
      return nil
    end
    local out = nil
    pcall(function()
      local w, h = img:getDimensions()
      w = math.floor(tonumber(w) or 0)
      h = math.floor(tonumber(h) or 0)
      if w < 1 or h < 1 then return end
      local cv = lv.graphics.newCanvas(w, h)
      if cv == nil then return end
      lv.graphics.push()
      lv.graphics.setCanvas(cv)
      lv.graphics.clear(0, 0, 0, 0)
      lv.graphics.setColor(r, g, b, 1)
      lv.graphics.draw(img, 0, 0)
      lv.graphics.setCanvas()
      lv.graphics.pop()
      lv.graphics.setColor(1, 1, 1, 1)
      pcall(function() cv:setFilter("nearest", "nearest") end)
      out = cv
    end)
    return out
  end
  function SP.berryImage(kind)
    local _, k = defOf(kind)
    if k == nil then return nil end
    if imgCache[k] ~= nil then return imgCache[k] or nil end
    local img = nil
    pcall(function()
      local baseId = nil
      local tint = nil
      if k == "razz" then baseId = 148
      elseif k == "pinap" then baseId = 152
      elseif TINT[k] ~= nil then
        baseId = TINT[k].base
        tint = TINT[k]
      end
      if baseId == nil then return end
      img = nativeIcon(baseId)
      if img == nil then return end
      if tint ~= nil then
        img = bakeTint(img, tint.r, tint.g, tint.b) or img
      end
    end)
    if img ~= nil then imgCache[k] = img end
    return img
  end
  local function wrapName()
    local ItemsData = SP.require("src.core.game3.items_data")
    if type(ItemsData) ~= "table"
        or type(ItemsData.displayName) ~= "function" then
      return false
    end
    if not SP.claim(ItemsData, "__spBerryName") then return true end
    local native = ItemsData.displayName
    ItemsData.displayName = function(id, ...)
      if isCustomId(id) then
        local def = defOf(id)
        if def ~= nil then return def.name end
      end
      return native(id, ...)
    end
    return true
  end
  local function wrapPocket()
    local ItemsData = SP.require("src.core.game3.items_data")
    if type(ItemsData) ~= "table"
        or type(ItemsData.pocketOf) ~= "function" then
      return false
    end
    if not SP.claim(ItemsData, "__spBerryPocket") then return true end
    local native = ItemsData.pocketOf
    ItemsData.pocketOf = function(id, ...)
      if isCustomId(id) then return "BERRY_POUCH" end
      return native(id, ...)
    end
    return true
  end
  local function wrapInfo()
    local ItemsData = SP.require("src.core.game3.items_data")
    if type(ItemsData) ~= "table"
        or type(ItemsData.info) ~= "function" then
      return false
    end
    if not SP.claim(ItemsData, "__spBerryInfo") then return true end
    local native = ItemsData.info
    ItemsData.info = function(id, ...)
      if isCustomId(id) then
        local def = defOf(id)
        if def ~= nil then
          local n = math.floor(tonumber(SP.numId(id)) or 0)
          return { id = n, name = def.name, pocket = "BERRY_POUCH",
            fieldUse = "none", price = 1 }
        end
      end
      return native(id, ...)
    end
    return true
  end
  local function bumpCap(ItemsData)
    local cap = type(ItemsData) == "table" and ItemsData.CAPACITY or nil
    if type(cap) ~= "table" then return false end
    local cur = math.floor(tonumber(cap.BERRY_POUCH) or 0)
    if cur < 45 then cap.BERRY_POUCH = 45 end
    return true
  end
  local function wrapCap()
    local ItemsData = SP.require("src.core.game3.items_data")
    if type(ItemsData) ~= "table" then return false end
    if type(ItemsData.applyProfile) == "function"
        and SP.claim(ItemsData, "__spBerryCapApplied") then
      local native = ItemsData.applyProfile
      ItemsData.applyProfile = function(...)
        local out = native(...)
        pcall(bumpCap, ItemsData)
        return out
      end
    end
    local ok = false
    pcall(function() ok = bumpCap(ItemsData) == true end)
    return ok
  end
  local function berryImgFor(id)
    local _, k = defOf(id)
    if k ~= "grazz" and k ~= "spinap" then return nil end
    if type(SP.berryImage) ~= "function" then return nil end
    local img = nil
    pcall(function() img = SP.berryImage(k) end)
    return img
  end
  local function wrapBagIcons()
    local BC = SP.require("src.ui.game3.bag_chrome")
    if type(BC) ~= "table" then return false end
    local okI, okD = false, false
    if type(BC.iconImage) == "function"
        and SP.claim(BC, "__spBerryIconWrapped") then
      local native = BC.iconImage
      SP.berryNativeIcon = SP.berryNativeIcon or native
      BC.iconImage = function(itemId)
        local img = nil
        pcall(function() img = berryImgFor(itemId) end)
        if img ~= nil then return img end
        return native(itemId)
      end
      okI = true
    end
    if type(BC.drawItemIcon) == "function"
        and SP.claim(BC, "__spBerryDrawWrapped") then
      local native = BC.drawItemIcon
      BC.drawItemIcon = function(itemId, px, py, scale)
        local img = nil
        pcall(function() img = berryImgFor(itemId) end)
        local lv = love
        if img ~= nil and type(lv) == "table"
            and type(lv.graphics) == "table" then
          local s = tonumber(scale) or 1
          lv.graphics.setColor(1, 1, 1, 1)
          lv.graphics.draw(img, px or 0, py or 0, 0, s, s)
          return true
        end
        return native(itemId, px, py, scale)
      end
      okD = true
    end
    return okI and okD
  end
  local function wrapRse()
    local BC = SP.require("src.ui.game3.rse.bag_chrome")
    if type(BC) ~= "table"
        or type(BC.drawItemIcon) ~= "function" then
      return false
    end
    if not SP.claim(BC, "__spBerryRseWrapped") then return true end
    local native = BC.drawItemIcon
    BC.drawItemIcon = function(index, x, y, rotation, ox, oy)
      local img = nil
      pcall(function() img = berryImgFor(index) end)
      local lv = love
      if img ~= nil and type(lv) == "table"
          and type(lv.graphics) == "table" then
        lv.graphics.setColor(1, 1, 1, 1)
        lv.graphics.draw(img, x or 0, y or 0)
        return
      end
      return native(index, x, y, rotation, ox, oy)
    end
    return true
  end
  local function blockedSoilId(id)
    local n = math.floor(tonumber(SP.numId(id)) or 0)
    return n == DEFS.grazz.id or n == DEFS.spinap.id
  end
  local function wrapSoil()
    local RB = SP.require("src.ui.game3.rse.bag_menu")
    if type(RB) ~= "table"
        or type(RB.chooseBerry) ~= "function" then
      return false
    end
    if not SP.claim(RB, "__spBerrySoilWrapped") then return true end
    local native = RB.chooseBerry
    RB.chooseBerry = function(ctx, done, location)
      local guarded
      guarded = function(item)
        if blockedSoilId(item) then
          local okMsg = false
          pcall(function()
            local Message = SP.require("src.ui.game3.message")
            if type(Message) == "table"
                and type(Message.show) == "function" then
              okMsg = true
              Message.show("This berry can't be sown!", function()
                pcall(native, ctx, guarded, location)
              end)
            end
          end)
          if not okMsg then pcall(native, ctx, guarded, location) end
          return
        end
        if type(done) == "function" then pcall(done, item) end
      end
      return native(ctx, guarded, location)
    end
    return true
  end
  local wrapsDone = false
  local function ensure()
    if not wrapsDone then
      local a, b, c, d, e, f, g = false, false, false, false, false, false, false
      pcall(function() a = wrapName() == true end)
      pcall(function() b = wrapPocket() == true end)
      pcall(function() c = wrapInfo() == true end)
      pcall(function() d = wrapCap() == true end)
      pcall(function() e = wrapBagIcons() == true end)
      pcall(function() f = wrapRse() == true end)
      pcall(function() g = wrapSoil() == true end)
      wrapsDone = a and b and c and d and e and f and g
    end
    return wrapsDone
  end
  ensure()
  if mod.events and type(mod.events.on) == "function" then
    mod.events:on("battle.started", function()
      pcall(ensure)
    end)
  end
  mod.log:info("safari-plus: berries installed")
end
