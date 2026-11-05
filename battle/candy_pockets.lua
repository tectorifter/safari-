return function(mod)
  local SP = mod.exports.safariPlus
  if not SP then return end
  local CD = assert(SP.candyData)
  local DEX_ROOM = math.floor(tonumber(CD.SPECIES_ROOM) or 715)
  if DEX_ROOM < 1 then DEX_ROOM = 715 end
  local function ownCount()
    local n = 0
    if type(CD.CANDY) == "table" then
      for _ in pairs(CD.CANDY) do n = n + 1 end
    end
    if type(CD.STAT) == "table" then
      for _ in pairs(CD.STAT) do n = n + 1 end
    end
    local SPX = mod.exports.safariPlus
    if type(SPX) == "table" then
      n = n + math.floor(tonumber(SPX.evoCustomCount) or 0)
    end
    return n
  end
  local packStamp, vanillaItems = nil, nil
  local function vanillaCount(ItemsData)
    local ok, byId = false, nil
    pcall(function()
      if type(ItemsData.ensureLoaded) == "function" then
        ItemsData.ensureLoaded()
      end
      byId = ItemsData._byId
      ok = true
    end)
    if not ok or type(byId) ~= "table" then return nil end
    if packStamp == byId and vanillaItems ~= nil then
      return vanillaItems
    end
    local map = ItemsData.PACK_POCKET
    local n = 0
    for _, e in pairs(byId) do
      if type(e) == "table" then
        local p = type(map) == "table" and map[e.pocket] or e.pocket
        if p == nil then p = e.pocket end
        if p == "ITEMS" then n = n + 1 end
      end
    end
    packStamp, vanillaItems = byId, n
    return n
  end
  local capped = false
  local function applyCap(ItemsData)
    local vanilla = vanillaCount(ItemsData)
    if vanilla == nil then return false end
    local cap = ItemsData.CAPACITY
    if type(cap) ~= "table" then return false end
    local want = vanilla + ownCount() + DEX_ROOM
    local cur = math.floor(tonumber(cap.ITEMS) or 0)
    if want > cur then cap.ITEMS = want end
    capped = true
    return true
  end
  local function attempt()
    local ItemsData = SP.require("src.core.game3.items_data")
    if type(ItemsData) ~= "table" then return false end
    if type(ItemsData.applyProfile) == "function"
        and SP.claim(ItemsData, "__spCandyPocketWrapped") then
      local native = ItemsData.applyProfile
      ItemsData.applyProfile = function(...)
        local out = native(...)
        pcall(applyCap, ItemsData)
        return out
      end
    end
    local ok = false
    pcall(function() ok = applyCap(ItemsData) == true end)
    return ok
  end
  attempt()
  if mod.events and type(mod.events.on) == "function" then
    mod.events:on("battle.started", function()
      if not capped then pcall(attempt) end
    end)
  end
  SP.candyPockets = { ensure = attempt }
  mod.log:info("safari-plus: candy pockets installed")
end
