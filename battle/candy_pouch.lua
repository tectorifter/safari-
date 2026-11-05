return function(mod)
  local SP = mod.exports.safariPlus
  if not SP then return end
  local CD = assert(SP.candyData)
  local POUCH_ID = math.floor(tonumber(CD.POUCH and CD.POUCH.id) or 9400)
  local function isCandy(id)
    return SP.candyDef(id) ~= nil
  end
  local function isPouch(id)
    return tonumber(SP.numId(id)) == POUCH_ID
  end
  local function loadStore()
    local raw = SP.saveGet("candyPouch", nil)
    local t = {}
    if type(raw) == "table" then
      for k, v in pairs(raw) do
        local id = math.floor(tonumber(k) or 0)
        local q = math.floor(tonumber(v) or 0)
        if id >= 1 and q >= 1 then t[id] = math.min(999, q) end
      end
    end
    return t
  end
  local function saveStore(t)
    SP.saveSet("candyPouch", t)
  end
  local function storeEmpty()
    for _ in pairs(loadStore()) do return false end
    return true
  end
  local function pouchName()
    return tostring(CD.POUCH and CD.POUCH.name or "CANDY POUCH")
  end
  local function cantHoldText(id)
    local disp = pouchName()
    local ItemsData = SP.require("src.core.game3.items_data")
    if type(ItemsData) == "table" and type(ItemsData.displayName) == "function" then
      local ok, n = SP.try(ItemsData.displayName, id)
      if ok and type(n) == "string" and n ~= "" then disp = n end
    end
    local rs = false
    local Profile = SP.require("src.core.game3.profile")
    if type(Profile) == "table" and type(Profile.forSession) == "function" then
      local ok, row = SP.try(Profile.forSession, SP.session())
      if ok and type(row) == "table" then
        rs = row.id == "ruby" or row.id == "sapphire"
      end
    end
    local RomText = SP.require("src.core.game3.rom_text")
    if type(RomText) == "table" and type(RomText.box) == "function" then
      local ok, text = SP.try(RomText.box,
        rs and "gOtherText_CantBeHeld" or "gText_ItemCantBeHeld",
        { stringVars = { disp } })
      if ok and type(text) == "string" and text ~= "" then return text end
    end
    return "The " .. tostring(disp) .. " can't be held."
  end
  local function tossBlockText()
    return "The " .. pouchName() .. " can't be tossed."
  end
  local function bagMod()
    return SP.require("src.core.game3.bag")
  end
  local NB = {}
  local function pouchAdd(bag, id, qty)
    qty = math.max(1, math.floor(tonumber(qty) or 1))
    local st = loadStore()
    local have = math.floor(tonumber(st[id]) or 0)
    if have + qty > 999 then qty = 999 - have end
    if qty <= 0 then return false, 0 end
    if type(NB.add) ~= "function" or type(NB.has) ~= "function" then
      return false, 0
    end
    local hasPouch = select(2, SP.try(NB.has, bag, POUCH_ID, 1))
    if hasPouch ~= true then
      local ok = select(1, SP.try(NB.add, bag, POUCH_ID, 1))
      if ok ~= true then return false, 0 end
    end
    st[id] = have + qty
    saveStore(st)
    return true, qty
  end
  local function pouchRemove(bag, id, qty)
    qty = math.max(1, math.floor(tonumber(qty) or 1))
    local st = loadStore()
    local have = math.floor(tonumber(st[id]) or 0)
    if have < qty then return false end
    have = have - qty
    if have <= 0 then st[id] = nil else st[id] = have end
    saveStore(st)
    local empty = true
    for _ in pairs(st) do empty = false break end
    if empty and type(NB.remove) == "function" then
      pcall(NB.remove, bag, POUCH_ID, 1)
    end
    return true
  end
  local function pouchGet(id)
    return math.floor(tonumber(loadStore()[id]) or 0)
  end
  local function pouchHas(id, qty)
    qty = math.max(1, math.floor(tonumber(qty) or 1))
    return pouchGet(id) >= qty
  end
  local function pouchCanAdd(id, qty)
    qty = math.max(1, math.floor(tonumber(qty) or 1))
    return pouchGet(id) + qty <= 999
  end
  local function wrapBag()
    local Bag = bagMod()
    if type(Bag) ~= "table" then return false end
    for _, fn in ipairs({ "add", "remove", "get", "has", "canAdd" }) do
      if type(Bag[fn]) ~= "function" then return false end
    end
    if not SP.claim(Bag, "__spPouchBagWrapped") then return true end
    NB.add = Bag.add
    NB.remove = Bag.remove
    NB.get = Bag.get
    NB.has = Bag.has
    NB.canAdd = Bag.canAdd
    Bag.add = function(bag, id, qty)
      local nid = tonumber(SP.numId(id))
      if nid ~= nil and isCandy(nid) then
        local ok, placed = pouchAdd(bag, nid, qty)
        if ok then return true, placed end
        return false, 0
      end
      return NB.add(bag, id, qty)
    end
    Bag.remove = function(bag, id, qty)
      local nid = tonumber(SP.numId(id))
      if nid == POUCH_ID and not storeEmpty() then
        return false
      end
      if nid ~= nil and isCandy(nid) then
        return pouchRemove(bag, nid, qty)
      end
      return NB.remove(bag, id, qty)
    end
    Bag.get = function(bag, id)
      local nid = tonumber(SP.numId(id))
      if nid ~= nil and isCandy(nid) then return pouchGet(nid) end
      return NB.get(bag, id)
    end
    Bag.has = function(bag, id, qty)
      local nid = tonumber(SP.numId(id))
      if nid ~= nil and isCandy(nid) then
        return pouchHas(nid, qty)
      end
      return NB.has(bag, id, qty)
    end
    Bag.canAdd = function(bag, id, qty)
      local nid = tonumber(SP.numId(id))
      if nid ~= nil and isCandy(nid) then
        return pouchCanAdd(nid, qty)
      end
      return NB.canAdd(bag, id, qty)
    end
    return true
  end
  local function migrated()
    return SP.saveGet("candyPouchMigrated", false) == true
  end
  local function migrate()
    if migrated() then return true end
    if type(NB.remove) ~= "function" or type(NB.add) ~= "function" then
      return false
    end
    local session = SP.session()
    local bag = type(session) == "table" and session.bag or nil
    if type(bag) ~= "table" then return false end
    local st = loadStore()
    local found = {}
    local pockets = bag.pockets
    if type(pockets) == "table" then
      for _, slots in pairs(pockets) do
        if type(slots) == "table" then
          for _, slot in ipairs(slots) do
            local sid = tonumber(SP.numId(slot.id))
            local q = math.floor(tonumber(slot.qty) or 0)
            if sid ~= nil and q > 0 and isCandy(sid) then
              found[sid] = math.floor(tonumber(found[sid]) or 0) + q
            end
          end
        end
      end
    end
    for sid, q in pairs(found) do
      pcall(NB.remove, bag, sid, q)
      st[sid] = math.min(999, math.floor(tonumber(st[sid]) or 0) + q)
    end
    saveStore(st)
    local empty = true
    for _ in pairs(st) do empty = false break end
    if not empty then
      local hasPouch = select(2, SP.try(NB.has, bag, POUCH_ID, 1))
      if hasPouch ~= true then
        pcall(NB.add, bag, POUCH_ID, 1)
      end
    end
    SP.saveSet("candyPouchMigrated", true)
    return true
  end
  local Gen = 0
  local function bagMenuMod(session)
    local Screens = SP.require("src.ui.game3.screens")
    if type(Screens) == "table" and type(Screens.get) == "function" then
      local ok, m = SP.try(Screens.get, "bag", session)
      if ok and type(m) == "table" then return m end
    end
    return SP.require("src.ui.game3.bag_menu")
  end
  local function candyRows()
    local st = loadStore()
    local exp, stat, spec = {}, {}, {}
    for sid, q in pairs(st) do
      if q > 0 then
        local def = SP.candyDef(sid)
        if type(def) == "table" then
          local row = { id = sid, name = def.name, qty = q }
          if def.kind == "species" then
            spec[#spec + 1] = row
          elseif def.evStat ~= nil then
            stat[#stat + 1] = row
          else
            exp[#exp + 1] = row
          end
        end
      end
    end
    local byId = function(a, b) return a.id < b.id end
    table.sort(exp, byId)
    table.sort(stat, byId)
    table.sort(spec, byId)
    local out = {}
    for _, row in ipairs(exp) do out[#out + 1] = row end
    for _, row in ipairs(stat) do out[#out + 1] = row end
    for _, row in ipairs(spec) do out[#out + 1] = row end
    return out
  end
  local showPicker, openPartyFor, backToBag, chainBegin, chainEnd
  local PickerOpen, TitleOn, ReturnBag = false, false, false
  local RealSession, RealBagMod, SavedLabel = nil, nil, nil
  local CANCEL_KEY = "gFameCheckerText_Cancel"
  local PICKER_TITLE = "Candy Pouch"
  local function wrapCancelText()
    local RomText = SP.require("src.core.game3.rom_text")
    if type(RomText) ~= "table"
        or type(RomText.plain) ~= "function" then
      return false
    end
    if not SP.claim(RomText, "__spPouchTextWrapped") then return true end
    local native = RomText.plain
    RomText.plain = function(key, ...)
      if PickerOpen and key == CANCEL_KEY then return "Close pouch" end
      return native(key, ...)
    end
    return true
  end
  local function pickerTitleOn()
    if TitleOn then return end
    local ItemsData = SP.require("src.core.game3.items_data")
    if type(ItemsData) ~= "table" then return end
    local cur = ItemsData.POCKET_LABEL
    if type(cur) ~= "table" then return end
    SavedLabel = cur
    ItemsData.POCKET_LABEL = setmetatable({ ITEMS = PICKER_TITLE },
      { __index = cur })
    TitleOn = true
  end
  local function pickerTitleOff()
    if not TitleOn then return end
    TitleOn = false
    local saved = SavedLabel
    SavedLabel = nil
    if saved == nil then return end
    local ItemsData = SP.require("src.core.game3.items_data")
    if type(ItemsData) == "table" then ItemsData.POCKET_LABEL = saved end
  end
  chainBegin = function()
    PickerOpen = true
    pickerTitleOn()
  end
  chainEnd = function()
    PickerOpen = false
    pickerTitleOff()
    ReturnBag = false
    RealSession = nil
    RealBagMod = nil
  end
  backToBag = function(g)
    if g ~= Gen then return end
    local sess, mod = RealSession, RealBagMod
    local back = ReturnBag
    chainEnd()
    if not back then return end
    if type(mod) ~= "table" or type(mod.show) ~= "function" then return end
    if type(sess) ~= "table" then return end
    local rbag = sess.bag
    if type(rbag) ~= "table" then rbag = sess end
    if not SP.try(mod.show, rbag, { session = sess, pocket = "ITEMS" }) then
      return
    end
    if type(mod.list) == "function" then
      local ok, rows = SP.try(mod.list)
      if ok and type(rows) == "table" then
        for i, r in ipairs(rows) do
          if type(r) == "table"
              and tonumber(SP.numId(r.id)) == POUCH_ID then
            mod.cursor = i
            break
          end
        end
      end
    end
  end
  showPicker = function(g)
    if g ~= Gen then return end
    local session = SP.session()
    local BagMenu = bagMenuMod(session)
    if type(BagMenu) ~= "table" or type(BagMenu.show) ~= "function" then
      BagMenu = RealBagMod
    end
    local Message = SP.require("src.ui.game3.message")
    if type(BagMenu) ~= "table" or type(BagMenu.show) ~= "function" then
      chainEnd()
      if type(Message) == "table"
          and type(Message.show) == "function" then
        Message.show("The pouch won't open right now.", function() end)
      end
      return
    end
    local rows = candyRows()
    if #rows == 0 then
      if type(Message) == "table"
          and type(Message.show) == "function" then
        Message.show("The pouch is empty.", function()
          backToBag(g)
        end)
      else
        backToBag(g)
      end
      return
    end
    local slots = {}
    for _, row in ipairs(rows) do
      slots[#slots + 1] = { id = row.id, qty = row.qty }
    end
    chainBegin()
    local okShow = SP.try(BagMenu.show, { pockets = { ITEMS = slots } }, {
      session = session,
      pocket = "ITEMS",
      location = "berry_tree",
      onChoose = function(id)
        if g ~= Gen then return end
        local nid = tonumber(SP.numId(id))
        if nid == nil or nid == 0 then
          backToBag(g)
          return
        end
        if pouchGet(nid) <= 0 then
          showPicker(g)
          return
        end
        openPartyFor(g, nid)
      end,
    })
    if not okShow then
      chainEnd()
      if type(Message) == "table"
          and type(Message.show) == "function" then
        Message.show("The pouch won't open right now.", function() end)
      end
    end
  end
  openPartyFor = function(g, candyId)
    if g ~= Gen then return end
    local session = SP.session()
    local party = type(session) == "table" and session.party or nil
    local PM = SP.require("src.ui.game3.party_menu")
    local Message = SP.require("src.ui.game3.message")
    if type(session) ~= "table" or type(party) ~= "table"
        or #party == 0 then
      if type(Message) == "table"
          and type(Message.show) == "function" then
        Message.show("There is no Pokémon.", function()
          if g == Gen then showPicker(g) end
        end)
      end
      return
    end
    if type(PM) ~= "table" or type(PM.show) ~= "function" then
      if type(Message) == "table"
          and type(Message.show) == "function" then
        Message.show("The pouch won't open right now.", function()
          if g == Gen then showPicker(g) end
        end)
      end
      return
    end
    local okOpen = SP.try(PM.show, party,
      session.move_overlay or session.moveOverlay, {
        session = session,
        bag = session.bag,
        item = candyId,
        mode = "use",
        onClose = function()
          if g == Gen then showPicker(g) end
        end,
      })
    if not okOpen and type(Message) == "table"
        and type(Message.show) == "function" then
      Message.show("The pouch won't open right now.", function()
        if g == Gen then showPicker(g) end
      end)
    end
  end
  local function openPouch(session, bag)
    local sess = type(session) == "table" and session or SP.session()
    local real = bagMenuMod(sess)
    ReturnBag = false
    RealSession = nil
    RealBagMod = nil
    if type(real) == "table" and type(real.isOpen) == "function"
        and type(real.close) == "function" then
      local ok, isOpen = SP.try(real.isOpen)
      if ok and isOpen then
        ReturnBag = true
        RealSession = sess
        RealBagMod = real
        SP.try(real.close)
      end
    end
    Gen = Gen + 1
    showPicker(Gen)
  end
  local function wrapUseField()
    local ItemUse = SP.require("src.core.game3.item_use")
    if type(ItemUse) ~= "table"
        or type(ItemUse.useField) ~= "function" then
      return false
    end
    if not SP.claim(ItemUse, "__spPouchUseWrapped") then return true end
    local native = ItemUse.useField
    ItemUse.useField = function(session, bag, item, slot, moveSlot, ...)
      if tonumber(SP.numId(item)) == POUCH_ID then
        local sess = type(session) == "table" and session or SP.session()
        local pbag = bag
        if pbag == nil and type(sess) == "table" then
          pbag = sess.bag
        end
        openPouch(sess, pbag)
        return true, "pouch", nil
      end
      return native(session, bag, item, slot, moveSlot, ...)
    end
    return true
  end
  local function wrapGive()
    local ItemUse = SP.require("src.core.game3.item_use")
    if type(ItemUse) ~= "table"
        or type(ItemUse.checkGive) ~= "function" then
      return false
    end
    if not SP.claim(ItemUse, "__spPouchGiveWrapped") then return true end
    local nativeCheck = ItemUse.checkGive
    local nativeHeld = ItemUse.giveHeld
    local nativeSwitch = ItemUse.switchHeld
    ItemUse.checkGive = function(session, id, partySlot, ...)
      if isPouch(id) then
        local party = type(session) == "table" and session.party or nil
        local mon = type(party) == "table" and party[partySlot] or nil
        if mon == nil then
          return nativeCheck(session, id, partySlot, ...)
        end
        return "cant_hold", nil, cantHoldText(id)
      end
      return nativeCheck(session, id, partySlot, ...)
    end
    if type(nativeHeld) == "function" then
      ItemUse.giveHeld = function(session, bag, id, partySlot, source, ...)
        if isPouch(id) then
          return cantHoldText(id)
        end
        return nativeHeld(session, bag, id, partySlot, source, ...)
      end
    end
    if type(nativeSwitch) == "function" then
      ItemUse.switchHeld = function(session, bag, id, partySlot, source, ...)
        if isPouch(id) then
          return false, cantHoldText(id)
        end
        return nativeSwitch(session, bag, id, partySlot, source, ...)
      end
    end
    return true
  end
  local function wrapBagSkin()
    local Screens = SP.require("src.ui.game3.screens")
    if type(Screens) ~= "table" or type(Screens.skin) ~= "function" then
      return false
    end
    if not SP.claim(Screens, "__spPouchSkinWrapped") then return true end
    local nativeSkinFn = Screens.skin
    Screens.skin = function(id, session, ...)
      local native = nativeSkinFn(id, session, ...)
      if id ~= "bag" then return native end
      local proxy = {}
      if type(native) == "table" then
        setmetatable(proxy, { __index = native })
      end
      proxy.canGive = function(row, pocket, ...)
        if type(row) == "table" and isPouch(row.id) then
          return false
        end
        if type(native) == "table" and type(native.canGive) == "function" then
          return native.canGive(row, pocket, ...)
        end
        return nil
      end
      proxy.beforeAction = function(menu, act, row, ...)
        if act == "TOSS" and type(row) == "table"
            and isPouch(row.id) and not storeEmpty() then
          if type(menu) == "table" and type(menu.showMessage) == "function" then
            SP.try(menu.showMessage, tossBlockText())
          end
          return true
        end
        if type(native) == "table" and type(native.beforeAction) == "function" then
          return native.beforeAction(menu, act, row, ...)
        end
        return nil
      end
      return proxy
    end
    return true
  end
  local function wrapStorage()
    local Storage = SP.require("src.core.game3.storage")
    if type(Storage) ~= "table" or type(Storage.addPcItem) ~= "function" then
      return false
    end
    if not SP.claim(Storage, "__spPouchStorageWrapped") then return true end
    local nativeAdd = Storage.addPcItem
    Storage.addPcItem = function(session, id, qty, ...)
      if isPouch(id) and not storeEmpty() then
        return false
      end
      return nativeAdd(session, id, qty, ...)
    end
    return true
  end
  local function scrubRow()
    if type(NB.remove) ~= "function" then return end
    if not storeEmpty() then return end
    local session = SP.session()
    local bag = type(session) == "table" and session.bag or nil
    if type(bag) ~= "table" then return end
    local qty = 0
    if type(NB.get) == "function" then
      local ok, q = SP.try(NB.get, bag, POUCH_ID)
      if ok then qty = math.floor(tonumber(q) or 0) end
    elseif type(NB.has) == "function" then
      local ok, h = SP.try(NB.has, bag, POUCH_ID, 1)
      if ok and h == true then qty = 1 end
    end
    if qty > 0 then pcall(NB.remove, bag, POUCH_ID, qty) end
  end
  local wrapsDone = false
  local function ensure()
    if not wrapsDone then
      local a, b, c, d, e, f = false, false, false, false, false, false
      pcall(function() a = wrapBag() == true end)
      pcall(function() b = wrapUseField() == true end)
      pcall(function() c = wrapGive() == true end)
      pcall(function() d = wrapBagSkin() == true end)
      pcall(function() e = wrapStorage() == true end)
      pcall(function() f = wrapCancelText() == true end)
      wrapsDone = a and b and c and d and e and f
    end
    if wrapsDone then
      if not migrated() then pcall(migrate) end
      pcall(scrubRow)
    end
    return wrapsDone
  end
  ensure()
  if mod.events and type(mod.events.on) == "function" then
    mod.events:on("battle.started", function()
      pcall(ensure)
    end)
    mod.events:on("map.entered", function()
      if wrapsDone and not migrated() then pcall(migrate) end
    end)
  end
  SP.candyPouch = {
    ensure = ensure,
    open = openPouch,
    pouchId = POUCH_ID,
  }
  mod.log:info("safari-plus: candy pouch installed")
end
