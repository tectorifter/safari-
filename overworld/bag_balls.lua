return function(mod)
  local SP = mod.exports.safariPlus
  if not SP then return end
  -- SAFARI BALL is virtual: the bag's balls pocket mirrors the live
  -- stock (listed even at 0), and stray real slots are absorbed into
  -- it, so regen, battles and the timer all show immediately.
  local BALL_ID = 5
  local function isBall(id)
    if id == BALL_ID then return true end
    if SP.numId(id) == BALL_ID then return true end
    return tostring(id) == "FRLG_5"
  end
  local function ballPocket()
    local ItemsData = SP.require("src.core.game3.items_data")
    if type(ItemsData) == "table" and type(ItemsData.pocketOf) == "function" then
      local ok, p = pcall(ItemsData.pocketOf, BALL_ID)
      if ok and type(p) == "string" then return p end
    end
    return "POKE_BALLS"
  end
  local Bag = SP.require("src.core.game3.bag")
  if type(Bag) ~= "table" then
    mod.log:warn("safari-plus: bag balls not installed -- no bag module")
    return
  end
  local nativeGet = Bag.get
  local nativeRemove = Bag.remove
  local function absorb(bag)
    if not SP.on() then return end
    SP.tick()
    if type(nativeGet) ~= "function" then return end
    local ok, have = pcall(nativeGet, bag, BALL_ID)
    have = (ok and math.floor(tonumber(have) or 0)) or 0
    if have > 0 then
      pcall(nativeRemove, bag, BALL_ID, have)
      SP.setStock(SP.stock() + have)
    end
  end
  if type(Bag.get) == "function" and SP.claim(Bag, "__spBallGetWrapped") then
    local native = Bag.get
    Bag.get = function(bag, id, ...)
      if SP.on() and isBall(id) then
        SP.tick()
        return SP.stock()
      end
      return native(bag, id, ...)
    end
  end
  if type(Bag.canAdd) == "function" and SP.claim(Bag, "__spBallCanAddWrapped") then
    local native = Bag.canAdd
    Bag.canAdd = function(bag, id, qty, ...)
      if SP.on() and isBall(id) then
        SP.tick()
        local q = math.max(1, math.floor(tonumber(qty) or 1))
        return SP.stock() + q <= SP.cap()
      end
      return native(bag, id, qty, ...)
    end
  end
  if type(Bag.add) == "function" and SP.claim(Bag, "__spBallAddWrapped") then
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
  if type(Bag.remove) == "function" and SP.claim(Bag, "__spBallRemoveWrapped") then
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
  if type(Bag.set) == "function" and SP.claim(Bag, "__spBallSetWrapped") then
    local native = Bag.set
    Bag.set = function(bag, id, qty, ...)
      if SP.on() and isBall(id) then
        absorb(bag)
        return SP.setStock(tonumber(qty) or 0)
      end
      return native(bag, id, qty, ...)
    end
  end
  if type(Bag.listPocket) == "function" and SP.claim(Bag, "__spBallListWrapped") then
    local native = Bag.listPocket
    Bag.listPocket = function(bag, pocket, ...)
      local rows = native(bag, pocket, ...)
      if not SP.on() then return rows end
      if pocket ~= ballPocket() then return rows end
      SP.tick()
      local out = {}
      if type(rows) == "table" then
        for _, r in ipairs(rows) do
          if not (type(r) == "table" and isBall(r.id)) then
            out[#out + 1] = r
          end
        end
      end
      local name, info, desc = "SAFARI BALL", nil, ""
      local ItemsData = SP.require("src.core.game3.items_data")
      if type(ItemsData) == "table" then
        local _, nm = SP.try(ItemsData.displayName, BALL_ID)
        if type(nm) == "string" then name = nm end
        local _, inf = SP.try(ItemsData.info, BALL_ID)
        if inf ~= nil then info = inf end
        local _, d = SP.try(ItemsData.description, BALL_ID)
        if type(d) == "string" then desc = d end
      end
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
