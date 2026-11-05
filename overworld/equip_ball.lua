return function(mod)
  local SP = mod.exports.safariPlus
  if not SP then return end
  local function owOn()
    return SP.opt("overworld", false) == true
  end
  local function ballNum(id)
    local n = math.floor(tonumber(SP.numId(id)) or 0)
    if n >= 1 and n <= 12 then return n end
    return nil
  end
  local function ballName(id)
    local name = nil
    local ItemsData = SP.require("src.core.game3.items_data")
    if type(ItemsData) == "table"
        and type(ItemsData.displayName) == "function" then
      local ok, v = SP.try(ItemsData.displayName, id)
      if ok and type(v) == "string" and v ~= "" then name = v end
    end
    return name or "BALL"
  end
  local function defaultActions(pocket, row, menu)
    local BagMenu = type(menu) == "table" and menu or nil
    local ItemsData = SP.require("src.core.game3.items_data")
    local function numOf(id)
      if type(ItemsData) == "table"
          and type(ItemsData.toNumericId) == "function" then
        local ok, n = pcall(ItemsData.toNumericId, id)
        if ok then return tonumber(n) end
      end
      return tonumber(id)
    end
    local berryPouch, tmCase = nil, nil
    if type(ItemsData) == "table" then
      berryPouch = tonumber(ItemsData.ITEM_BERRY_POUCH)
      tmCase = tonumber(ItemsData.ITEM_TM_CASE)
    end
    local num = type(row) == "table" and numOf(row.id) or nil
    if type(BagMenu) == "table" and BagMenu._battle then
      if num ~= nil and num == berryPouch then
        return { "OPEN", "CANCEL" }
      end
      local usable = false
      pcall(function()
        local BI = SP.require("src.core.game3.battle.items")
        if type(BI) == "table"
            and type(BI.isBattleUsable) == "function"
            and type(row) == "table" then
          usable = BI.isBattleUsable(row.id) == true
        end
      end)
      if usable then return { "USE", "CANCEL" } end
      return { "CANCEL" }
    end
    pocket = pocket or "ITEMS"
    if type(BagMenu) == "table" and BagMenu._location == "blender" then
      return { "CONFIRM", "CHECK_TAG", "CANCEL" }
    end
    local linked = false
    pcall(function()
      local Map = SP.require("src.core.game3.map")
      if type(Map) ~= "table" or type(Map.current) ~= "string" then
        return
      end
      local UR = SP.require("src.core.game3.link.union_room")
      if type(UR) == "table" and type(UR.isUnionMap) == "function"
          and UR.isUnionMap(Map.current) then
        linked = true
        return
      end
      local Link = SP.require("src.core.game3.link")
      if type(Link) == "table" and Link.link ~= nil
          and type(Link.inLinkRoom) == "function"
          and Link.inLinkRoom() == true then
        linked = true
      end
    end)
    if linked then
      if num ~= nil and (num == tmCase or num == berryPouch) then
        return { "USE", "CANCEL" }
      end
      if pocket == "KEY_ITEMS" then return { "CANCEL" } end
      return { "GIVE", "CANCEL" }
    end
    local info = nil
    if type(row) == "table" then
      info = row.info
      if info == nil and type(ItemsData) == "table"
          and type(ItemsData.info) == "function" then
        local ok, v = pcall(ItemsData.info, row.id)
        if ok and type(v) == "table" then info = v end
      end
    end
    local registrable = type(info) == "table"
      and (tonumber(info.registrability) or 0) > 0
    if pocket == "KEY_ITEMS" then
      if registrable then return { "USE", "SET", "CANCEL" } end
      return { "USE", "CANCEL" }
    elseif pocket == "POKE_BALLS" then
      return { "GIVE", "TOSS", "CANCEL" }
    elseif pocket == "TM_CASE" then
      return { "USE", "CANCEL" }
    elseif pocket == "BERRY_POUCH" then
      local rse = false
      pcall(function()
        local P = SP.require("src.core.game3.profile")
        local sess = type(BagMenu) == "table" and BagMenu._session or nil
        if type(P) == "table" and type(P.family) == "function" then
          rse = P.family(sess) == "rse"
        end
      end)
      if rse then
        return { "CHECK_TAG", "USE", "GIVE", "TOSS", "CANCEL" }
      end
      return { "USE", "GIVE", "TOSS", "CANCEL" }
    end
    return { "USE", "GIVE", "TOSS", "CANCEL" }
  end
  local function wrapSkin()
    local Screens = SP.require("src.ui.game3.screens")
    if type(Screens) ~= "table" or type(Screens.skin) ~= "function" then
      return false
    end
    if not SP.claim(Screens, "__spEquipSkinWrapped") then return true end
    local nativeSkinFn = Screens.skin
    Screens.skin = function(id, session, ...)
      local native = nativeSkinFn(id, session, ...)
      if id ~= "bag" or not owOn() then return native end
      local proxy = {}
      if type(native) == "table" then
        setmetatable(proxy, { __index = native })
      end
      proxy.actionsForPocket = function(pocket, row, menu, ...)
        if type(menu) == "table" and menu._battle then
          if type(native) == "table"
              and type(native.actionsForPocket) == "function" then
            local okB, vB = pcall(native.actionsForPocket, pocket,
              row, menu, ...)
            if okB and type(vB) == "table" and #vB > 0 then return vB end
          end
          return defaultActions(pocket, row, menu)
        end
        if owOn() and type(row) == "table" and ballNum(row.id) ~= nil
            and (pocket == "POKE_BALLS" or pocket == nil) then
          return { "USE", "GIVE", "TOSS", "CANCEL" }
        end
        if type(native) == "table"
            and type(native.actionsForPocket) == "function" then
          local ok, v = pcall(native.actionsForPocket, pocket, row,
            menu, ...)
          if ok and type(v) == "table" and #v > 0 then return v end
        end
        return defaultActions(pocket, row, menu)
      end
      return proxy
    end
    return true
  end
  local function wrapTarget()
    local ItemUse = SP.require("src.core.game3.item_use")
    if type(ItemUse) ~= "table"
        or type(ItemUse.needsPartyTarget) ~= "function" then
      return false
    end
    if not SP.claim(ItemUse, "__spEquipTargetWrapped") then return true end
    local native = ItemUse.needsPartyTarget
    ItemUse.needsPartyTarget = function(id, ...)
      if owOn() and ballNum(id) ~= nil then return false end
      return native(id, ...)
    end
    return true
  end
  local function wrapUseField()
    local ItemUse = SP.require("src.core.game3.item_use")
    if type(ItemUse) ~= "table"
        or type(ItemUse.useField) ~= "function" then
      return false
    end
    if not SP.claim(ItemUse, "__spEquipUseWrapped") then return true end
    local native = ItemUse.useField
    ItemUse.useField = function(session, bag, item, slot, moveSlot, ...)
      local n = owOn() and ballNum(item) or nil
      if n == nil then
        return native(session, bag, item, slot, moveSlot, ...)
      end
      SP.setEquippedBall(n)
      return true, "equip", ballName(item) .. " equipped!"
    end
    return true
  end
  local function bagMenuMod(session)
    local Screens = SP.require("src.ui.game3.screens")
    if type(Screens) == "table" and type(Screens.get) == "function" then
      local ok, m = SP.try(Screens.get, "bag", session)
      if ok and type(m) == "table" then return m end
    end
    return SP.require("src.ui.game3.bag_menu")
  end
  function SP.openBallsBag()
    local session = SP.session()
    if type(session) ~= "table" then return false end
    local M = bagMenuMod(session)
    if type(M) ~= "table" or type(M.show) ~= "function" then
      return false
    end
    local bag = session.bag
    if type(bag) ~= "table" then bag = session end
    if not SP.try(M.show, bag, { session = session,
        pocket = "POKE_BALLS" }) then
      return false
    end
    if type(M.list) == "function" and type(SP.equippedBall) == "function" then
      pcall(function()
        local ok, rows = SP.try(M.list)
        if not ok or type(rows) ~= "table" then return end
        local want = SP.equippedBall()
        for i, r in ipairs(rows) do
          if type(r) == "table" and ballNum(r.id) == want then
            M.cursor = i
            break
          end
        end
      end)
    end
    return true
  end
  local wrapsDone = false
  local function ensure()
    if not wrapsDone then
      local a, b, c = false, false, false
      pcall(function() a = wrapSkin() == true end)
      pcall(function() b = wrapTarget() == true end)
      pcall(function() c = wrapUseField() == true end)
      wrapsDone = a and b and c
    end
    return wrapsDone
  end
  ensure()
  if mod.events and type(mod.events.on) == "function" then
    mod.events:on("battle.started", function()
      pcall(ensure)
    end)
  end
  mod.log:info("safari-plus: ball equip installed")
end
