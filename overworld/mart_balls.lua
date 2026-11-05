return function(mod)
  local SP = mod.exports.safariPlus
  if not SP then return end
  local function ballNum(id)
    local n = math.floor(tonumber(SP.numId(id)) or 0)
    if n >= 1 and n <= 12 then return n end
    return nil
  end
  local function oldaleMartMap()
    local mapId = nil
    pcall(function()
      local M = SP.require("src.core.game3.map")
      if type(M) == "table" and type(M.current) == "string" then
        mapId = M.current
      end
    end)
    if type(mapId) ~= "string" then
      local s = SP.session()
      if type(s) == "table" and type(s.map) == "string" then
        mapId = s.map
      end
    end
    if type(mapId) ~= "string" then return false end
    local u = string.upper(mapId)
    return u:find("OLDALE", 1, true) ~= nil
      and u:find("MART", 1, true) ~= nil
  end
  local oldaleOpen = false
  local BERRY_STOCK = { 148, 152, 9401, 9402 }
  local function berryStockId(id)
    local n = math.floor(tonumber(SP.numId(id)) or 0)
    for _, b in ipairs(BERRY_STOCK) do
      if b == n then return true end
    end
    return false
  end
  local function wrapShop()
    local ShopMenu = SP.require("src.ui.game3.shop_menu")
    if type(ShopMenu) ~= "table" then return false end
    if type(ShopMenu.show) ~= "function" then return false end
    if not SP.claim(ShopMenu, "__spMartBallsShow") then return true end
    local nativeShow = ShopMenu.show
    ShopMenu.show = function(opts)
      opts = type(opts) == "table" and opts or {}
      oldaleOpen = false
      pcall(function()
        if oldaleMartMap() then
          oldaleOpen = true
          local list = {}
          for i = 1, 12 do list[#list + 1] = i end
          for _, b in ipairs(BERRY_STOCK) do list[#list + 1] = b end
          opts.items = list
        end
      end)
      return nativeShow(opts)
    end
    if type(ShopMenu.close) == "function"
        and SP.claim(ShopMenu, "__spMartBallsClose") then
      local nativeClose = ShopMenu.close
      ShopMenu.close = function(...)
        oldaleOpen = false
        return nativeClose(...)
      end
    end
    return true
  end
  local function wrapInfo()
    local ItemsData = SP.require("src.core.game3.items_data")
    if type(ItemsData) ~= "table" then return false end
    if type(ItemsData.info) ~= "function" then return false end
    if not SP.claim(ItemsData, "__spMartBallsInfo") then return true end
    local nativeInfo = ItemsData.info
    ItemsData.info = function(id, ...)
      local info = nativeInfo(id, ...)
      if oldaleOpen and type(info) == "table"
          and (ballNum(id) ~= nil or berryStockId(id)) then
        local copy = {}
        for k, v in pairs(info) do copy[k] = v end
        copy.price = 1
        return copy
      end
      return info
    end
    return true
  end
  local wrapsDone = false
  local function ensure()
    if not wrapsDone then
      local a, b = false, false
      pcall(function() a = wrapShop() == true end)
      pcall(function() b = wrapInfo() == true end)
      wrapsDone = a and b
    end
    return wrapsDone
  end
  ensure()
  if mod.events and type(mod.events.on) == "function" then
    mod.events:on("map.entered", function()
      pcall(ensure)
    end)
  end
  mod.log:info("safari-plus: oldale mart balls installed")
end
