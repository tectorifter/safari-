return function(mod)
  local SP = mod.exports.safariPlus
  if not SP then return end
  local DATA = SP.evoDrops
  if type(DATA) ~= "table" then return end
  local CUSTOM = DATA.CUSTOM
  if type(CUSTOM) ~= "table" then return end
  local NATIVE_EVO = DATA.NATIVE_EVO
  if type(NATIVE_EVO) ~= "table" then return end
  local names = {}
  for k, def in pairs(CUSTOM) do
    if type(def) == "table" and math.floor(tonumber(def.id) or 0) > 0 then
      names[#names + 1] = k
    end
  end
  SP.evoCustomCount = #names
  local numCache = {}
  local function numOf(ref)
    if numCache[ref] ~= nil then return numCache[ref] end
    local n = SP.numId(ref)
    if (n == nil or n == 0) and type(CUSTOM[ref]) == "table" then
      n = math.floor(tonumber(CUSTOM[ref].id) or 0)
    end
    if n == nil or n == 0 then n = false end
    numCache[ref] = n
    return n
  end
  local evoSet = {}
  for _, ref in ipairs(NATIVE_EVO) do
    local n = numOf(ref)
    if n then evoSet[n] = true end
  end
  for _, k in ipairs(names) do
    local n = numOf(k)
    if n then evoSet[n] = true end
  end
  local function isEvoId(id)
    local n = SP.numId(id) or math.floor(tonumber(id) or 0)
    if n == nil or n == 0 then return false end
    return evoSet[n] == true
  end
  local EVO_TRADE, EVO_TRADE_ITEM = 5, 6
  pcall(function()
    local E = SP.require("src.core.game3.evolution")
    if type(E) == "table" then
      if tonumber(E.EVO_TRADE) then EVO_TRADE = E.EVO_TRADE end
      if tonumber(E.EVO_TRADE_ITEM) then EVO_TRADE_ITEM = E.EVO_TRADE_ITEM end
    end
  end)
  local everstone = SP.numId("ITEM_EVERSTONE") or 195
  local function fallback(mon, item, session)
    if type(mon) ~= "table" then return nil end
    local n = SP.numId(item) or math.floor(tonumber(item) or 0)
    if n == nil or n == 0 or evoSet[n] ~= true then return nil end
    local held = math.floor(tonumber(mon.item or mon.heldItem) or 0)
    if held == everstone then return nil end
    local Pokemon = SP.require("src.core.game3.pokemon")
    if type(Pokemon) ~= "table" then return nil end
    local species = nil
    pcall(function()
      if type(Pokemon.speciesOf) == "function" then
        species = Pokemon.speciesOf(mon)
      end
    end)
    species = math.floor(tonumber(species or mon.species or mon.speciesId) or 0)
    if species <= 0 then return nil end
    if type(Pokemon.evolutions) ~= "function" then return nil end
    local ok, rows = pcall(Pokemon.evolutions, species)
    if not ok or type(rows) ~= "table" then return nil end
    local linkN = numOf("LINKING_CORD")
    local target = nil
    for _, evo in ipairs(rows) do
      if type(evo) == "table" then
        local m = math.floor(tonumber(evo.method or evo[1]) or 0)
        local param = math.floor(tonumber(evo.param or evo[2]) or 0)
        local tgt = math.floor(tonumber(evo.target or evo[3]) or 0)
        if tgt > 0 then
          if linkN and n == linkN and m == EVO_TRADE then
            target = tgt
            break
          elseif (not linkN or n ~= linkN) and m == EVO_TRADE_ITEM
              and param == n then
            target = tgt
            break
          end
        end
      end
    end
    if target == nil or target <= 0 then return nil end
    local allows = true
    pcall(function()
      local E = SP.require("src.core.game3.evolution")
      if type(E) == "table"
          and type(E.nationalAllows) == "function" then
        allows = E.nationalAllows(target, session) ~= false
      end
    end)
    if not allows then return nil end
    return target
  end
  local function wrapEvo()
    local E = SP.require("src.core.game3.evolution")
    if type(E) ~= "table" then return false end
    local okT, okC = false, false
    if type(E.itemTarget) == "function"
        and SP.claim(E, "__spEvoUseTarget") then
      local native = E.itemTarget
      E.itemTarget = function(mon, item, session)
        local target = nil
        pcall(function() target = native(mon, item, session) end)
        if math.floor(tonumber(target) or 0) > 0 then return target end
        return fallback(mon, item, session)
      end
      okT = true
    end
    if type(E.itemCheck) == "function"
        and SP.claim(E, "__spEvoUseCheck") then
      local native = E.itemCheck
      E.itemCheck = function(mon, item)
        local target = nil
        pcall(function() target = native(mon, item) end)
        if math.floor(tonumber(target) or 0) > 0 then return target end
        return fallback(mon, item, nil)
      end
      okC = true
    end
    return okT and okC
  end
  local function wrapKind()
    local ItemsData = SP.require("src.core.game3.items_data")
    if type(ItemsData) ~= "table"
        or type(ItemsData.fieldUseKind) ~= "function" then
      return false
    end
    if not SP.claim(ItemsData, "__spEvoUseKind") then return true end
    local native = ItemsData.fieldUseKind
    ItemsData.fieldUseKind = function(id, ...)
      if isEvoId(id) then return "evo" end
      return native(id, ...)
    end
    return true
  end
  local function isCustomId(id)
    local n = SP.numId(id) or math.floor(tonumber(id) or 0)
    for _, k in ipairs(names) do
      if numOf(k) == n then return true end
    end
    return false
  end
  local function customDef(id)
    local n = SP.numId(id) or math.floor(tonumber(id) or 0)
    for k, def in pairs(CUSTOM) do
      if numOf(k) == n then return def, k end
    end
    return nil
  end
  local DESC = {
    LINKING_CORD = "A cord that links trade evolutions.",
  }
  local function wrapMeta()
    local ItemsData = SP.require("src.core.game3.items_data")
    if type(ItemsData) ~= "table" then return false end
    local okN, okP, okI, okD = false, false, false, false
    if type(ItemsData.displayName) == "function"
        and SP.claim(ItemsData, "__spEvoUseName") then
      local native = ItemsData.displayName
      ItemsData.displayName = function(id, ...)
        if isCustomId(id) then
          local def = customDef(id)
          if def ~= nil then return def.name end
        end
        return native(id, ...)
      end
      okN = true
    end
    if type(ItemsData.pocketOf) == "function"
        and SP.claim(ItemsData, "__spEvoUsePocket") then
      local native = ItemsData.pocketOf
      ItemsData.pocketOf = function(id, ...)
        if isCustomId(id) then return "ITEMS" end
        return native(id, ...)
      end
      okP = true
    end
    if type(ItemsData.info) == "function"
        and SP.claim(ItemsData, "__spEvoUseInfo") then
      local native = ItemsData.info
      ItemsData.info = function(id, ...)
        if isCustomId(id) then
          local def, k = customDef(id)
          if def ~= nil then
            local n = numOf(k)
            return { id = n, name = def.name, pocket = "ITEMS",
              fieldUse = "none", price = DATA.CUSTOM_PRICE or 100 }
          end
        end
        return native(id, ...)
      end
      okI = true
    end
    if type(ItemsData.description) == "function"
        and SP.claim(ItemsData, "__spEvoUseDesc") then
      local native = ItemsData.description
      ItemsData.description = function(id, ...)
        if isCustomId(id) then
          local _, k = customDef(id)
          if k ~= nil and DESC[k] ~= nil then return DESC[k] end
        end
        return native(id, ...)
      end
      okD = true
    end
    return okN and okP and okI and okD
  end
  local imgCache = {}
  local function evoImgFor(id)
    if not isCustomId(id) then return nil end
    local n = SP.numId(id) or math.floor(tonumber(id) or 0)
    local key = nil
    for k in pairs(CUSTOM) do
      if numOf(k) == n then key = k break end
    end
    if key == nil then return nil end
    local artKey = "link"
    if imgCache[artKey] ~= nil then return imgCache[artKey] or nil end
    pcall(function()
      local lv = love
      if type(lv) ~= "table" or type(lv.image) ~= "table"
          or type(lv.graphics) ~= "table" then
        return
      end
      local art = SP.evoArt
      if type(art) ~= "table" then return end
      local base = art[artKey]
      if type(base) ~= "table" then return end
      local w = math.floor(tonumber(base.w) or 24)
      local h = math.floor(tonumber(base.h) or 24)
      local rows = base.rows
      local pal = base.pal
      if type(rows) ~= "table" or type(pal) ~= "table" then return end
      local data = lv.image.newImageData(w, h)
      if data == nil then return end
      for y = 0, h - 1 do
        local row = rows[y + 1]
        if type(row) ~= "string" then return end
        for x = 0, w - 1 do
          local idx = tonumber(row:sub(x + 1, x + 1), 16)
          if idx ~= nil and idx > 0 and type(pal[idx + 1]) == "string" then
            local c = pal[idx + 1]:gsub("#", "")
            if #c >= 6 then
              data:setPixel(x, y,
                math.floor(tonumber(c:sub(1, 2), 16) or 0) / 255,
                math.floor(tonumber(c:sub(3, 4), 16) or 0) / 255,
                math.floor(tonumber(c:sub(5, 6), 16) or 0) / 255, 1)
            end
          end
        end
      end
      local img = lv.graphics.newImage(data)
      if img == nil then return end
      pcall(function() img:setFilter("nearest", "nearest") end)
      imgCache[artKey] = img
    end)
    if imgCache[artKey] == nil then imgCache[artKey] = false end
    return imgCache[artKey] or nil
  end
  local function wrapIcons()
    local BC = SP.require("src.ui.game3.bag_chrome")
    if type(BC) ~= "table" then return false end
    local okI, okD = false, false
    if type(BC.iconImage) == "function"
        and SP.claim(BC, "__spEvoUseIconWrapped") then
      local native = BC.iconImage
      BC.iconImage = function(itemId)
        local img = nil
        pcall(function() img = evoImgFor(itemId) end)
        if img ~= nil then return img end
        return native(itemId)
      end
      okI = true
    end
    if type(BC.drawItemIcon) == "function"
        and SP.claim(BC, "__spEvoUseDrawWrapped") then
      local native = BC.drawItemIcon
      BC.drawItemIcon = function(itemId, px, py, scale)
        local img = nil
        pcall(function() img = evoImgFor(itemId) end)
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
    if not SP.claim(BC, "__spEvoUseRseWrapped") then return true end
    local native = BC.drawItemIcon
    BC.drawItemIcon = function(index, x, y, rotation, ox, oy)
      local img = nil
      pcall(function() img = evoImgFor(index) end)
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
  local done = { evo = false, kind = false, meta = false,
    icons = false, rse = false }
  local function ensure()
    pcall(function() done.evo = wrapEvo() == true end)
    pcall(function() done.kind = wrapKind() == true end)
    pcall(function() done.meta = wrapMeta() == true end)
    pcall(function() done.icons = wrapIcons() == true end)
    pcall(function() done.rse = wrapRse() == true end)
    return done.evo and done.kind and done.meta
  end
  ensure()
  if mod.events and type(mod.events.on) == "function" then
    mod.events:on("battle.started", function()
      if not (done.evo and done.kind and done.meta) then
        pcall(ensure)
      end
    end)
  end
  SP.evoUse = {
    isEvoItem = isEvoId,
    numOf = numOf,
    targetFor = fallback,
  }
  mod.log:info("safari-plus: evo use installed")
end
