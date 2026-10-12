return function(mod)
  local SP = mod.exports.safariPlus
  if not SP then return end
  local glyphImpl, isGlyphImpl
  local rseAtlasCache = nil
  local function setTint(def)
    love.graphics.setColor(def.tint[1], def.tint[2], def.tint[3], 1)
  end
  local function clearTint()
    love.graphics.setColor(1, 1, 1, 1)
  end
  local function rseTinted(BC, def, x, y)
    local lv = love
    if type(lv) ~= "table" or type(lv.graphics) ~= "table" then return false end
    if type(BC.manifest) ~= "function" then return false end
    local m = BC.manifest()
    local icons = m and m.icons
    if not icons then return false end
    local c = rseAtlasCache
    if not (c and c.icons == icons and c.img ~= nil and c.q ~= nil) then
      c = nil
      local Kit = SP.require("src.ui.game3.rse.scene_kit")
      if not (Kit and type(Kit.rgbaImage) == "function") then return false end
      local img = Kit.rgbaImage(icons.rgba, icons.w, icons.h)
      if img == nil then return false end
      local sw, sh = img:getDimensions()
      if not (sw and sh) then return false end
      local q = lv.graphics.newQuad(0, 68 * 24, 24, 24, sw, sh)
      if q == nil then return false end
      c = { icons = icons, img = img, q = q }
      rseAtlasCache = c
    end
    setTint(def)
    lv.graphics.draw(c.img, c.q, x, y)
    clearTint()
    return true
  end
  local function wrapRseDraw()
    local BC = SP.require("src.ui.game3.rse.bag_chrome")
    if not (BC and type(BC.drawItemIcon) == "function") then
      return false
    end
    if not SP.claim(BC, "__spCandyTintWrapped") then return true end
    local native = BC.drawItemIcon
    BC.drawItemIcon = function(index, x, y, rotation, ox, oy)
      local def = SP.candyDef(index)
      if def == nil then
        return native(index, x, y, rotation, ox, oy)
      end
      if rseTinted(BC, def, x, y) then return end
      return native(68, x, y, rotation, ox, oy)
    end
    return true
  end
  local function wrapIcons()
    local BC = SP.require("src.ui.game3.bag_chrome")
    if not (BC and type(BC.iconImage) == "function") then return false end
    if not SP.claim(BC, "__spCandyIconWrapped") then return true end
    local native = BC.iconImage
    BC.iconImage = function(itemId)
      local def = SP.candyDef(itemId)
      if def ~= nil then
        local base = native(68)
        if base ~= nil then return base end
        return glyphImpl(def)
      end
      return native(itemId)
    end
    return true
  end
  local function wrapDraw()
    local BC = SP.require("src.ui.game3.bag_chrome")
    if not (BC and type(BC.drawItemIcon) == "function") then
      return false
    end
    if not SP.claim(BC, "__spCandyTintWrapped") then return true end
    local native = BC.drawItemIcon
    BC.drawItemIcon = function(itemId, px, py, scale)
      local def = SP.candyDef(itemId)
      if def == nil then
        return native(itemId, px, py, scale)
      end
      local img = BC.iconImage(itemId)
      if img == nil then
        return native(itemId, px, py, scale)
      end
      local lv = love
      if type(lv) ~= "table" or type(lv.graphics) ~= "table" then
        return native(itemId, px, py, scale)
      end
      local s = tonumber(scale) or 1
      if isGlyphImpl(def, img) then
        clearTint()
      else
        setTint(def)
      end
      lv.graphics.draw(img, px or 0, py or 0, 0, s, s)
      clearTint()
      return true
    end
    return true
  end
  local glyphCache = {}
  glyphImpl = function(def)
    if glyphCache[def.id] ~= nil then
      return glyphCache[def.id] or nil
    end
    local img = nil
    local lv = love
    if type(lv) == "table" and type(lv.image) == "table"
        and type(lv.graphics) == "table" then
      local data = lv.image.newImageData(24, 24)
      if data ~= nil then
        local t = def.tint
        local function shade(f)
          return math.min(1, t[1] * f), math.min(1, t[2] * f),
            math.min(1, t[3] * f)
        end
        for y = 0, 23 do
          for x = 0, 23 do
            local dx = x - 11.5
            local dy = y - 11.5
            local d = math.sqrt(dx * dx + dy * dy)
            local ax = math.abs(dx)
            local ay = math.abs(dy)
            if d <= 8.5 then
              local r, g, b = shade(1.15 - 0.75 * (d / 8.5))
              data:setPixel(x, y, r, g, b, 1)
            elseif ax >= 8 and ax <= 11.5
                and ay <= (11.5 - ax) * 1.1 + 0.5 then
              local r, g, b = shade(0.85)
              data:setPixel(x, y, r, g, b, 1)
            end
          end
        end
        for y = 7, 10 do
          for x = 7, 10 do
            local dx = x - 8
            local dy = y - 8
            if dx * dx + dy * dy <= 4 then
              data:setPixel(x, y, 1, 1, 1, 0.9)
            end
          end
        end
        img = lv.graphics.newImage(data)
        if img and img.setFilter then img:setFilter("nearest", "nearest") end
      end
    end
    glyphCache[def.id] = img or false
    return img
  end
  isGlyphImpl = function(def, img)
    local g = glyphCache[def.id]
    return g ~= nil and g ~= false and img == g
  end
  SP.candyIcons = {
    wrapIcons = wrapIcons,
    wrapDraw = wrapDraw,
    wrapRseDraw = wrapRseDraw,
  }
  mod.log:info("safari-plus: candy icons installed")
end
