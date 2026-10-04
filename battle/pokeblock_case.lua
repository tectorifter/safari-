return function(mod)
  local SP = mod.exports.safariPlus
  if not SP then return end
  local function battleState()
    local okB, B = pcall(require, "src.core.game3.battle")
    if okB and B and type(B.getState) == "function" then
      local ok, st = pcall(B.getState)
      if ok and type(st) == "table" then return st end
    end
    return nil
  end
  local function argSessionCb(...)
    local session, cb = nil, nil
    for i = select("#", ...), 1, -1 do
      local a = select(i, ...)
      if type(a) == "function" and cb == nil then cb = a
      elseif type(a) == "table" and session == nil then session = a end
    end
    return session or SP.session(), cb
  end
  local CASE_NUM = 260
  local CASE_NAMES = { "ITEM_POKEBLOCK_CASE", "POKEBLOCK_CASE" }
  local function itemsData()
    local okI, ItemsData = pcall(require, "src.core.game3.items_data")
    if not okI or type(ItemsData) ~= "table" then return nil end
    pcall(function()
      if type(ItemsData.ensureLoaded) == "function" then
        ItemsData.ensureLoaded()
      end
    end)
    return ItemsData
  end
  local function caseIds(ItemsData)
    local ids = { CASE_NUM, tostring(CASE_NUM) }
    for _, n in ipairs(CASE_NAMES) do
      ids[#ids + 1] = n
    end
    if ItemsData then
      if type(ItemsData.toNumericId) == "function" then
        for _, n in ipairs(CASE_NAMES) do
          local num = nil
          pcall(function() num = ItemsData.toNumericId(n) end)
          if num ~= nil then ids[#ids + 1] = num end
        end
      end
      if type(ItemsData.bagKey) == "function" then
        for _, v in ipairs({ CASE_NUM, CASE_NAMES[1], CASE_NAMES[2] }) do
          local k = nil
          pcall(function() k = ItemsData.bagKey(v) end)
          if k ~= nil then ids[#ids + 1] = k end
        end
      end
    end
    return ids
  end
  local function entryIds(entry)
    if type(entry) ~= "table" then return { entry } end
    return {
      entry.id, entry.itemId, entry.item, entry[1],
      entry.key, entry.name,
    }
  end
  local function entryQty(entry)
    if type(entry) ~= "table" then return tonumber(entry) or 1 end
    local q = entry.qty
    if q == nil then q = entry.quantity end
    if q == nil then q = entry.count end
    if q == nil then q = entry[2] end
    if q == nil then return 1 end
    return tonumber(q) or 0
  end
  local function idMatches(slotId, ids, ItemsData)
    if slotId == nil then return false end
    for _, want in ipairs(ids) do
      if slotId == want or tostring(slotId) == tostring(want) then
        return true
      end
    end
    if tonumber(slotId) == CASE_NUM then return true end
    if ItemsData then
      local got = nil
      if type(ItemsData.toNumericId) == "function" then
        pcall(function() got = ItemsData.toNumericId(slotId) end)
      end
      if got ~= nil then
        if got == CASE_NUM or tostring(got) == tostring(CASE_NUM) then
          return true
        end
        for _, want in ipairs(ids) do
          if got == want or tostring(got) == tostring(want) then
            return true
          end
        end
      end
      if type(ItemsData.bagKey) == "function" then
        local gk = nil
        pcall(function() gk = ItemsData.bagKey(slotId) end)
        if gk ~= nil then
          for _, want in ipairs(ids) do
            if gk == want or gk == tostring(want) then return true end
          end
        end
      end
    end
    return false
  end
  local function listHas(list, ids, ItemsData)
    if type(list) ~= "table" then return false end
    for _, entry in pairs(list) do
      if entryQty(entry) > 0 then
        for _, id in ipairs(entryIds(entry)) do
          if idMatches(id, ids, ItemsData) then return true end
        end
      end
    end
    return false
  end
  local CASE_FLAG = 0x5F
  local function hasCase(session)
    if type(session) ~= "table" then return true end
    local flagged = false
    pcall(function()
      local f = session.flags
      if type(f) == "table" then
        if f[CASE_FLAG] == true or f[95] == true
            or f["95"] == true or f["0x5F"] == true then
          flagged = true
          return
        end
      end
      local Space = package.loaded["src.core.game3.scripting.space"]
      if Space and Space.store then
        local okF, Flags = pcall(require, "src.core.game3.scripting.flags")
        if okF and Flags and type(Flags.getFlag) == "function" then
          if Flags.getFlag(Space.store, nil, CASE_FLAG) then
            flagged = true
          end
        end
      end
    end)
    if flagged then return true end
    local ItemsData = itemsData()
    local ids = caseIds(ItemsData)
    local bag = session.bag
    if type(bag) == "table" then
      local okB, Bag = pcall(require, "src.core.game3.bag")
      if okB and Bag and type(Bag.has) == "function" then
        for _, want in ipairs(ids) do
          local ok, has = pcall(Bag.has, bag, want, 1)
          if ok and has == true then return true end
        end
      end
      local found = false
      pcall(function()
        if type(bag.pockets) == "table" then
          for _, slots in pairs(bag.pockets) do
            if type(slots) == "table" then
              if listHas(slots, ids, ItemsData) then
                found = true
                return
              end
            end
          end
        end
        if not found and type(bag.stacks) == "table" then
          for k, qty in pairs(bag.stacks) do
            if (tonumber(qty) or 0) > 0 and idMatches(k, ids, ItemsData) then
              found = true
              return
            end
          end
        end
        if not found then
          for _, field in ipairs({ "keyItems", "key_items", "items",
              "key", "inventory" }) do
            if listHas(bag[field], ids, ItemsData) then
              found = true
              return
            end
          end
        end
      end)
      if found then return true end
    end
    local found = false
    pcall(function()
      for _, field in ipairs({ "keyItems", "key_items", "items",
          "inventory", "keyitems" }) do
        if listHas(session[field], ids, ItemsData) then
          found = true
          return
        end
      end
      local prof = session.profile
      if type(prof) == "table" and not found then
        for _, field in ipairs({ "keyItems", "key_items", "items",
            "inventory", "bag" }) do
          local v = prof[field]
          if type(v) == "table" then
            if type(v.pockets) == "table" then
              for _, slots in pairs(v.pockets) do
                if listHas(slots, ids, ItemsData) then
                  found = true
                  return
                end
              end
            elseif listHas(v, ids, ItemsData) then
              found = true
              return
            end
          end
          if found then return end
        end
      end
    end)
    return found
  end

  local function wrapRse()
    local okR, Rse = pcall(require, "src.core.game3.rse.init")
    if not (okR and Rse and type(Rse.call) == "function") then return false end
    if Rse.__spCaseWrapped then return true end
    Rse.__spCaseWrapped = true
    local native = Rse.call
    Rse.call = function(domain, name, ...)
      if SP.on() and domain == "pokeblock" and name == "chooseForBattle" then
        local st = battleState()
        if st and st.safari and not st.over then
          local session, cb = argSessionCb(...)
          if not hasCase(session) then
            local pushed = false
            pcall(function()
              local Ui = require("src.core.game3.battle.ui")
              if Ui and type(Ui.push) == "function" then
                Ui.push("You don't have the POKéBLOCK CASE yet.",
                  function()
                    if type(cb) == "function" then pcall(cb, nil) end
                  end)
                pushed = true
              end
            end)
            if not pushed and type(cb) == "function" then pcall(cb, nil) end
            return nil, true
          end
          return native(domain, name, session, cb)
        end
      end
      return native(domain, name, ...)
    end
    return true
  end
  local function caseModule()
    local loaded = package.loaded["src.ui.game3.rse.pokeblock_case"]
    if type(loaded) == "table" then return loaded end
    local okC, Case = pcall(require, "src.ui.game3.rse.pokeblock_case")
    if okC and type(Case) == "table" then return Case end
    return nil
  end
  local caseErrLogged = false
  local function noteErr(where, err)
    if caseErrLogged then return end
    caseErrLogged = true
    pcall(function()
      mod.log:warn("safari-plus: pokeblock case %s: %s", where, tostring(err))
    end)
    pcall(print, "[safari-plus] pokeblock case " .. tostring(where)
      .. ": " .. tostring(err))
  end
  local function wrapBattle()
    local okB, B = pcall(require, "src.core.game3.battle")
    if not (okB and B and type(B.update) == "function") then return false end
    if B.__spCaseInputWrapped then return true end
    B.__spCaseInputWrapped = true
    local native = B.update
    B.update = function(dt, game, ...)
      local r = native(dt, game, ...)
      local ok, err = pcall(function()
        if not SP.on() then return end
        if B._phase ~= "safari_pokeblock" then return end
        local Case = caseModule()
        local open = Case and type(Case.isOpen) == "function"
          and Case.isOpen() or false
        if open then
          local input = game and game.input
          if input ~= nil then
            if type(Case.handleInput) == "function" then
              Case.handleInput(input)
            end
            if type(Case.update) == "function" then Case.update() end
          end
          return
        end
        local st = battleState()
        if st and not st.over then
          B._phase = "command"
          local okU, Ui = pcall(require, "src.core.game3.battle.ui")
          if okU and Ui and type(Ui.openMenu) == "function" then
            Ui.openMenu()
          end
        end
      end)
      if not ok then noteErr("pump", err) end
      return r
    end
    return true
  end
  wrapRse()
  pcall(wrapBattle)
  if mod.events and type(mod.events.on) == "function" then
    mod.events:on("battle.started", function()
      caseErrLogged = false
      pcall(wrapRse)
      pcall(wrapBattle)
    end)
  end
  mod.log:info("safari-plus: pokeblock case gated on item 260")
end
