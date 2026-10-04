return function(mod)
  local SP = mod.exports.safariPlus
  if not SP then return end
  local function inject()
    for _, key in ipairs(SP.ORDER) do SP.refreshMeta(key) end
    pcall(function()
      local BC = require("src.ui.game3.bag_chrome")
      if BC then
        BC._icons = BC._icons or {}
        for _, def in pairs(SP.UPG) do BC._icons[def.id] = false end
      end
    end)
  end
  inject()
  local okBg, Bag = pcall(require, "src.core.game3.bag")
  if okBg and Bag then
    if type(Bag.canAdd) == "function" and not Bag.__spCanAddWrapped then
      Bag.__spCanAddWrapped = true
      local native = Bag.canAdd
      Bag.canAdd = function(bag, id, qty, ...)
        local key = SP.isUpgId(id) and SP.keyOf(id) or nil
        if key then
          if (tonumber(qty) or 1) > 1 then return false end
          if SP.count(key) >= SP.maxOf(key) then return false end
          return true
        end
        return native(bag, id, qty, ...)
      end
    end
    if type(Bag.add) == "function" and not Bag.__spAddWrapped then
      Bag.__spAddWrapped = true
      local native = Bag.add
      Bag.add = function(bag, id, qty, ...)
        local key = SP.isUpgId(id) and SP.keyOf(id) or nil
        if key then
          local k = SP.addLevels(key, 1)
          if k <= 0 then return false, 0 end
          SP.refreshMeta(key)
          return true, k
        end
        return native(bag, id, qty, ...)
      end
    end
  end
  local wrapRse, wrapFrlg
  local okS, ShopMenu = pcall(require, "src.ui.game3.shop_menu")  if okS and ShopMenu and type(ShopMenu.show) == "function"
      and not ShopMenu.__spShopWrapped then
    ShopMenu.__spShopWrapped = true
    local nativeShow = ShopMenu.show
    ShopMenu.show = function(opts)
      opts = opts or {}
      pcall(function()
        SP.tick()
        local sess = opts.session
        if SP.on() and type(sess) == "table"
            and sess.map == "EM_OLDALE_TOWN_MART"
            and type(opts.items) == "table" then
          local stock = {}
          for i, id in ipairs(opts.items) do stock[i] = id end
          for _, key in ipairs(SP.ORDER) do
            if SP.count(key) < SP.maxOf(key) then
              SP.refreshMeta(key)
              stock[#stock + 1] = SP.UPG[key].id
            end
          end
          opts.items = stock
        end
      end)
      pcall(function() if wrapRse then wrapRse() end end)
      pcall(function() if wrapFrlg then wrapFrlg() end end)
      return nativeShow(opts)
    end
  end
  local function clampRse(shop)
    if not SP.on() then return end
    if type(shop) ~= "table" then return end
    if shop.state ~= "qty" and shop.state ~= "confirm" then return end
    if tonumber(shop.qty) == 1 then return end
    if not SP.isUpgId(shop._itemId) then return end
    shop.qty = 1
    shop._totalCost = SP.price(SP.keyOf(shop._itemId))
  end
  wrapRse = function()
    local okRse, RseShop = pcall(require, "src.ui.game3.rse.shop_menu")
    if not (okRse and RseShop and type(RseShop.handleInput) == "function") then
      return false
    end
    if RseShop.__spQtyWrapped then return true end
    RseShop.__spQtyWrapped = true
    local nativeInput = RseShop.handleInput
    RseShop.handleInput = function(shop, input, ...)
      pcall(clampRse, shop)
      local r = nativeInput(shop, input, ...)
      pcall(function()
        if SP.on() and type(shop) == "table" and SP.isUpgId(shop._itemId)
            and (shop.state == "qty" or shop.state == "confirm")
            and tonumber(shop.qty) ~= 1 then
          local q = math.max(1, tonumber(shop.qty) or 1)
          shop._totalCost = math.floor((tonumber(shop._totalCost) or 0) / q)
          shop.qty = 1
        end
      end)
      return r
    end
    return true
  end
  local function clampFrlg(ShopMenu)
    if not SP.on() then return end
    if type(ShopMenu) ~= "table" then return end
    if ShopMenu.mode ~= "buy_qty" and ShopMenu.mode ~= "buy_confirm" then return end
    local p = ShopMenu._pending
    if type(p) ~= "table" then return end
    if tonumber(ShopMenu.qty) == 1 then return end
    if not SP.isUpgId(p.id) then return end
    ShopMenu.qty = 1
  end
  wrapFrlg = function()
    local okF, ShopMenu = pcall(require, "src.ui.game3.shop_menu")
    if not (okF and ShopMenu and type(ShopMenu.handleInput) == "function") then
      return false
    end
    if ShopMenu.__spUpgQtyWrapped then return true end
    ShopMenu.__spUpgQtyWrapped = true
    local nativeInput = ShopMenu.handleInput
    ShopMenu.handleInput = function(input, ...)
      pcall(clampFrlg, ShopMenu)
      local r = nativeInput(input, ...)
      pcall(clampFrlg, ShopMenu)
      return r
    end
    return true
  end
  wrapRse()
  wrapFrlg()
  mod.log:info("safari-plus: oldale upgrade shelf installed")
end
