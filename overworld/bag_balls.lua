return function(mod)
  local SP = mod.exports.safariPlus
  if not SP then return end
  local BALL_ID = 5
  local function numId(id)
    local okI, ItemsData = pcall(require, "src.core.game3.items_data")
    if okI and ItemsData and type(ItemsData.toNumericId) == "function" then
      local ok, n = pcall(ItemsData.toNumericId, id)
      if ok and n ~= nil then return tonumber(n) end
    end
    return tonumber(id)
  end
  local function isBall(id)
    if id == BALL_ID then return true end
    if numId(id) == BALL_ID then return true end
    return tostring(id) == "FRLG_5"
  end
  local function ballPocket()
    local okI, ItemsData = pcall(require, "src.core.game3.items_data")
    if okI and ItemsData and type(ItemsData.pocketOf) == "function" then
      local ok, p = pcall(ItemsData.pocketOf, BALL_ID)
      if ok and type(p) == "string" then return p end
    end
    return "POKE_BALLS"
  end
  local okBg, Bag = pcall(require, "src.core.game3.bag")
  if not (okBg and Bag) then
    mod.log:warn("safari-plus: bag balls not installed -- no bag module")
    return
  end
  local nativeGet = Bag.get
  local nativeRemove = Bag.remove
  local function absorb(bag)
    if not SP.on() then return end
    if type(nativeGet) ~= "function" then return end
    local ok, have = pcall(nativeGet, bag, BALL_ID)
    have = (ok and math.floor(tonumber(have) or 0)) or 0
    if have > 0 then
      pcall(nativeRemove, bag, BALL_ID, have)
      SP.setStock(SP.stock() + have)
    end
  end
  if type(Bag.get) == "function" and not Bag.__spBallGetWrapped then
    Bag.__spBallGetWrapped = true
    local native = Bag.get
    Bag.get = function(bag, id, ...)
      if SP.on() and isBall(id) then
        return SP.stock()
      end
      return native(bag, id, ...)
    end
  end
  if type(Bag.canAdd) == "function" and not Bag.__spBallCanAddWrapped then
    Bag.__spBallCanAddWrapped = true
    local native = Bag.canAdd
    Bag.canAdd = function(bag, id, qty, ...)
      if SP.on() and isBall(id) then
        local q = math.max(1, math.floor(tonumber(qty) or 1))
        return SP.stock() + q <= SP.cap()
      end
      return native(bag, id, qty, ...)
    end
  end
  if type(Bag.add) == "function" and not Bag.__spBallAddWrapped then
    Bag.__spBallAddWrapped = true
    local native = Bag.add
    Bag.add = function(bag, id, qty, ...)
      if SP.on() and isBall(id) then
        absorb(bag)
        local q = math.max(0, math.floor(tonumber(qty) or 1))
        local placed = math.max(0, math.min(q, SP.cap() - SP.stock()))
        if placed <= 0 then return false, 0 end
        SP.setStock(SP.stock() + placed)
        return true, placed
      end
      return native(bag, id, qty, ...)
    end
  end
  if type(Bag.remove) == "function" and not Bag.__spBallRemoveWrapped then
    Bag.__spBallRemoveWrapped = true
    local native = Bag.remove
    Bag.remove = function(bag, id, qty, ...)
      if SP.on() and isBall(id) then
        absorb(bag)
        local q = math.max(1, math.floor(tonumber(qty) or 1))
        local have = SP.stock()
        if have < q then return false end
        SP.setStock(have - q)
        return true
      end
      return native(bag, id, qty, ...)
    end
  end
  if type(Bag.set) == "function" and not Bag.__spBallSetWrapped then
    Bag.__spBallSetWrapped = true
    local native = Bag.set
    Bag.set = function(bag, id, qty, ...)
      if SP.on() and isBall(id) then
        absorb(bag)
        return SP.setStock(tonumber(qty) or 0)
      end
      return native(bag, id, qty, ...)
    end
  end
  if type(Bag.listPocket) == "function" and not Bag.__spBallListWrapped then
    Bag.__spBallListWrapped = true
    local native = Bag.listPocket
    Bag.listPocket = function(bag, pocket, ...)
      local rows = native(bag, pocket, ...)
      if not SP.on() then return rows end
      if pocket ~= ballPocket() then return rows end
      local out = {}
      if type(rows) == "table" then
        for _, r in ipairs(rows) do
          if not (type(r) == "table" and isBall(r.id)) then
            out[#out + 1] = r
          end
        end
      end
      local name, info, desc = "SAFARI BALL", nil, ""
      pcall(function()
        local ItemsData = require("src.core.game3.items_data")
        name = ItemsData.displayName(BALL_ID)
        info = ItemsData.info(BALL_ID)
        desc = ItemsData.description(BALL_ID)
      end)
      local at = #out + 1
      for i, r in ipairs(out) do
        local rid = (type(r) == "table" and tonumber(r.id)) or 9999
        if BALL_ID < rid then
          at = i
          break
        end
      end
      table.insert(out, at, { id = BALL_ID, qty = SP.stock(), name = name, info = info, description = desc })
      return out
    end
  end
  mod.log:info("safari-plus: safari ball bag slot installed")
end
