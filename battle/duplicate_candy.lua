return function(mod)
  local SP = mod.exports.safariPlus
  if not SP then return end
  local ensureWraps, glyphFor, isGlyph, candyDef
  local function rseTinted(BC, def, x, y)
    local painted = false
    pcall(function()
      local lv = love
      if type(lv) ~= "table" or type(lv.graphics) ~= "table" then return end
      local m = nil
      pcall(function() m = BC.manifest() end)
      local icons = m and m.icons
      if not icons then return end
      local okK, Kit = pcall(require, "src.ui.game3.rse.scene_kit")
      if not (okK and Kit and type(Kit.rgbaImage) == "function") then return end
      local img = Kit.rgbaImage(icons.rgba, icons.w, icons.h)
      if img == nil then return end
      local sw, sh = img:getDimensions()
      if not (sw and sh) then return end
      local q = lv.graphics.newQuad(0, 68 * 24, 24, 24, sw, sh)
      if q == nil then return end
      lv.graphics.setColor(def.tint[1], def.tint[2], def.tint[3], 1)
      lv.graphics.draw(img, q, x, y)
      lv.graphics.setColor(1, 1, 1, 1)
      painted = true
    end)
    return painted
  end
  local function wrapRseDraw()
    local okC, BC = pcall(require, "src.ui.game3.rse.bag_chrome")
    if not (okC and BC and type(BC.drawItemIcon) == "function") then
      return false
    end
    if BC.__spCandyTintWrapped then return true end
    BC.__spCandyTintWrapped = true
    local native = BC.drawItemIcon
    BC.drawItemIcon = function(index, x, y, rotation, ox, oy)
      local def = candyDef(index)
      if def == nil then
        return native(index, x, y, rotation, ox, oy)
      end
      if rseTinted(BC, def, x, y) then return end
      return native(68, x, y, rotation, ox, oy)
    end
    return true
  end
  local CANDY = {
    XS = { id = 9101, name = "EXP CANDY XS", xp = 100,
      tint = { 1, 0.95, 0.35 } },
    S = { id = 9102, name = "EXP CANDY S", xp = 800,
      tint = { 0.45, 1, 0.45 } },
    M = { id = 9103, name = "EXP CANDY M", xp = 3000,
      tint = { 0.35, 0.55, 1 } },
    L = { id = 9104, name = "EXP CANDY L", xp = 10000,
      tint = { 1, 0.4, 0.7 } },
    XL = { id = 9105, name = "EXP CANDY XL", xp = 30000,
      tint = { 1, 0.3, 0.3 } },
  }
  local BY_ID = {}
  for _, def in pairs(CANDY) do BY_ID[def.id] = def end
  local PSEUDO_IDS = { [149] = true, [248] = true, [373] = true, [376] = true }
  local LEGEND_IDS = {
    [144] = true, [145] = true, [146] = true, [150] = true, [151] = true,
    [243] = true, [244] = true, [245] = true, [249] = true, [250] = true,
    [251] = true, [377] = true, [378] = true, [379] = true, [380] = true,
    [381] = true, [382] = true, [383] = true, [384] = true, [385] = true,
    [386] = true,
  }
  local PSEUDO_NAMES = {
    DRAGONITE = true, TYRANITAR = true, SALAMENCE = true, METAGROSS = true,
  }
  local LEGEND_NAMES = {
    ARTICUNO = true, ZAPDOS = true, MOLTRES = true, MEWTWO = true, MEW = true,
    RAIKOU = true, ENTEI = true, SUICUNE = true, LUGIA = true, HOOH = true,
    CELEBI = true, REGIROCK = true, REGICE = true, REGISTEEL = true,
    LATIAS = true, LATIOS = true, KYOGRE = true, GROUDON = true,
    RAYQUAZA = true, JIRACHI = true, DEOXYS = true,
  }
  local function numOf(id)
    local okI, ItemsData = pcall(require, "src.core.game3.items_data")
    if okI and ItemsData and type(ItemsData.toNumericId) == "function" then
      local ok, n = pcall(ItemsData.toNumericId, id)
      if ok and n ~= nil then return tonumber(n) end
    end
    return tonumber(id)
  end
  candyDef = function(id)
    local n = numOf(id)
    if n == nil then return nil end
    return BY_ID[n]
  end
  local function cleanName(mon, species)
    local nm = nil
    pcall(function()
      local Pokemon = require("src.core.game3.pokemon")
      if Pokemon and type(Pokemon.name) == "function" and species ~= nil then
        nm = Pokemon.name(species)
      end
    end)
    if type(nm) ~= "string" or nm == "" then
      nm = type(mon) == "table" and mon.name or nil
    end
    if type(nm) ~= "string" then return "" end
    return nm:upper():gsub("[^A-Z0-9]", "")
  end
  local function rewardsFor(species, cname, level)
    local lvl = math.max(1, math.min(100, math.floor(tonumber(level) or 1)))
    local sid = tonumber(species)
    if (sid and LEGEND_IDS[sid]) or LEGEND_NAMES[cname] then
      return { { id = CANDY.XL.id, qty = 1 }, { id = CANDY.L.id, qty = 1 } }
    end
    if (sid and PSEUDO_IDS[sid]) or PSEUDO_NAMES[cname] then
      return { { id = CANDY.XL.id, qty = 1 } }
    end
    if lvl <= 5 then return { { id = CANDY.XS.id, qty = 1 } } end
    if lvl <= 8 then return { { id = CANDY.XS.id, qty = 2 } } end
    if lvl <= 10 then return { { id = CANDY.XS.id, qty = 3 } } end
    if lvl <= 15 then return { { id = CANDY.S.id, qty = 1 } } end
    if lvl <= 20 then return { { id = CANDY.S.id, qty = 2 } } end
    if lvl <= 29 then return { { id = CANDY.S.id, qty = 3 } } end
    if lvl <= 35 then return { { id = CANDY.M.id, qty = 1 } } end
    if lvl <= 40 then
      return { { id = CANDY.M.id, qty = 1 }, { id = CANDY.S.id, qty = 1 } }
    end
    if lvl <= 45 then return { { id = CANDY.L.id, qty = 1 } } end
    return { { id = CANDY.L.id, qty = 1 }, { id = CANDY.M.id, qty = 1 } }
  end
  local function rewardText(rewards)
    local parts = {}
    for _, r in ipairs(rewards) do
      local def = BY_ID[r.id]
      if def then parts[#parts + 1] = tostring(r.qty) .. " " .. def.name end
    end
    return table.concat(parts, " and ")
  end
  local function wrapInfo()
    local okI, ItemsData = pcall(require, "src.core.game3.items_data")
    if not (okI and ItemsData and type(ItemsData.info) == "function") then
      return false
    end
    if ItemsData.__spCandyInfoWrapped then return true end
    ItemsData.__spCandyInfoWrapped = true
    local native = ItemsData.info
    ItemsData.info = function(id, ...)
      ensureWraps()
      local def = candyDef(id)
      if def then
        return {
          id = def.id,
          name = def.name,
          pocket = "ITEMS",
          fieldUse = "exp_candy",
          price = def.xp,
          description = "Gives " .. tostring(def.xp) .. " Exp. Points.",
        }
      end
      return native(id, ...)
    end
    return true
  end
  local function wrapIcons()
    local okC, BC = pcall(require, "src.ui.game3.bag_chrome")
    if not (okC and BC and type(BC.iconImage) == "function") then return false end
    if BC.__spCandyIconWrapped then return true end
    BC.__spCandyIconWrapped = true
    local native = BC.iconImage
    BC.iconImage = function(itemId)
      if candyDef(itemId) ~= nil then
        local base = nil
        pcall(function() base = native(68) end)
        if base ~= nil then return base end
        local def = candyDef(itemId)
        if def ~= nil then return glyphFor(def) end
        return nil
      end
      return native(itemId)
    end
    return true
  end
  local function useCandy(session, bag, def, item, slot)
    if type(session) ~= "table" then
      local okR, R = pcall(require, "src.core.game3.runtime")
      if okR and R and type(R.getSession) == "function" then
        local okS, s = pcall(R.getSession)
        if okS and type(s) == "table" then session = s end
      end
    end
    local party = type(session) == "table" and session.party or nil
    local idx = math.floor(tonumber(slot) or 0)
    local mon = type(party) == "table" and party[idx] or nil
    if type(mon) ~= "table" or mon.isEgg then
      return { false, "no_effect", "It won't have any effect." }
    end
    local lvl = math.floor(tonumber(mon.level) or 1)
    if lvl >= 100 or (tonumber(mon.hp) or 0) <= 0 then
      return { false, "no_effect", "It won't have any effect." }
    end
    local targetBag = bag or (type(session) == "table" and session.bag) or nil
    local okB, Bag = pcall(require, "src.core.game3.bag")
    if not (okB and Bag and type(Bag.remove) == "function") then
      return { false, "no_effect", "It won't have any effect." }
    end
    local has = false
    pcall(function() has = Bag.has(targetBag, item, 1) end)
    if has ~= true then
      return { false, "no_effect", "It won't have any effect." }
    end
    local removed = false
    pcall(function() removed = Bag.remove(targetBag, item, 1) end)
    if removed ~= true then
      return { false, "no_effect", "It won't have any effect." }
    end
    local okE, Exp = pcall(require, "src.core.game3.battle.experience")
    if not (okE and Exp and type(Exp.apply) == "function") then
      pcall(function() Bag.add(targetBag, item, 1) end)
      return { false, "no_effect", "It won't have any effect." }
    end
    local res = nil
    local okA = pcall(function() res = Exp.apply(mon, def.xp) end)
    if not (okA and type(res) == "table") then
      pcall(function() Bag.add(targetBag, item, 1) end)
      return { false, "no_effect", "It won't have any effect." }
    end
    local monName = mon.name or "POKéMON"
    pcall(function()
      local Pokemon = require("src.core.game3.pokemon")
      if Pokemon and type(Pokemon.displayMonName) == "function" then
        local nm = Pokemon.displayMonName(mon)
        if type(nm) == "string" and nm ~= "" then monName = nm end
      end
    end)
    local msg = tostring(monName) .. " gained " .. tostring(def.xp)
      .. " EXP. Points!"
    if tonumber(res.toLevel) and tonumber(res.fromLevel)
        and res.toLevel > res.fromLevel then
      msg = msg .. " Grew to Lv " .. tostring(res.toLevel) .. "!"
    end
    return { true, "exp", msg }
  end
  local function wrapUse()
    local okU, ItemUse = pcall(require, "src.core.game3.item_use")
    if not (okU and ItemUse and type(ItemUse.useField) == "function") then
      return false
    end
    if ItemUse.__spCandyUseWrapped then return true end
    ItemUse.__spCandyUseWrapped = true
    local native = ItemUse.useField
    ItemUse.useField = function(session, bag, item, slot, moveSlot, ...)
      local def = candyDef(item)
      if def == nil then
        return native(session, bag, item, slot, moveSlot, ...)
      end
      local out = nil
      pcall(function()
        out = useCandy(session, bag, def, item, slot)
      end)
      if type(out) == "table" then
        return out[1], out[2], out[3]
      end
      return native(session, bag, item, slot, moveSlot, ...)
    end
    return true
  end
  local function wrapDraw()
    local okC, BC = pcall(require, "src.ui.game3.bag_chrome")
    if not (okC and BC and type(BC.drawItemIcon) == "function") then
      return false
    end
    if BC.__spCandyTintWrapped then return true end
    BC.__spCandyTintWrapped = true
    local native = BC.drawItemIcon
    BC.drawItemIcon = function(itemId, px, py, scale)
      local def = candyDef(itemId)
      if def == nil then
        return native(itemId, px, py, scale)
      end
      local painted = false
      pcall(function()
        local img = BC.iconImage(itemId)
        if img == nil then return end
        local lv = love
        if type(lv) ~= "table" or type(lv.graphics) ~= "table" then return end
        local s = tonumber(scale) or 1
        if isGlyph(def, img) then
          lv.graphics.setColor(1, 1, 1, 1)
        else
          lv.graphics.setColor(def.tint[1], def.tint[2], def.tint[3], 1)
        end
        lv.graphics.draw(img, px or 0, py or 0, 0, s, s)
        lv.graphics.setColor(1, 1, 1, 1)
        painted = true
      end)
      if painted then return true end
      return native(itemId, px, py, scale)
    end
    return true
  end
  local function wrapTarget()
    local okU, ItemUse = pcall(require, "src.core.game3.item_use")
    if not (okU and ItemUse and type(ItemUse.needsPartyTarget) == "function") then
      return false
    end
    if ItemUse.__spCandyTargetWrapped then return true end
    ItemUse.__spCandyTargetWrapped = true
    local native = ItemUse.needsPartyTarget
    ItemUse.needsPartyTarget = function(id, ...)
      if candyDef(id) ~= nil then return true end
      return native(id, ...)
    end
    return true
  end
  local glyphCache = {}
  glyphFor = function(def)
    if glyphCache[def.id] ~= nil then
      return glyphCache[def.id] or nil
    end
    local img = nil
    pcall(function()
      local lv = love
      if type(lv) ~= "table" then return end
      if type(lv.image) ~= "table" then return end
      if type(lv.graphics) ~= "table" then return end
      local data = lv.image.newImageData(24, 24)
      if data == nil then return end
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
    end)
    glyphCache[def.id] = img or false
    return img
  end
  isGlyph = function(def, img)
    local g = glyphCache[def.id]
    return g ~= nil and g ~= false and img == g
  end
  local function battleMod()
    local ok, B = pcall(require, "src.core.game3.battle")
    if ok and type(B) == "table" then return B end
    return nil
  end
  local function liveCatchRes()
    local ok, CS = pcall(require, "src.core.game3.battle.catch_seq")
    if ok and CS and type(CS.catchResult) == "function" then
      local okR, res = pcall(CS.catchResult)
      if okR then return res end
    end
    return nil
  end
  local function isTutorial(st)
    if st.oldManTutorial or st.pokedude then return true end
    local okW, Wally = pcall(require, "src.core.game3.battle.tutorial_wally")
    if okW and Wally and type(Wally.active) == "function" then
      local ok, v = pcall(Wally.active, st)
      if ok and v then return true end
    end
    return false
  end
  local function convertRes(B, Ui, res, mon, rewards)
    local session = nil
    pcall(function()
      local R = require("src.core.game3.runtime")
      if R and type(R.getSession) == "function" then session = R.getSession() end
    end)
    if type(session) ~= "table" then return false end
    local okB, Bag = pcall(require, "src.core.game3.bag")
    if not (okB and Bag and type(Bag.add) == "function"
        and type(Bag.canAdd) == "function") then
      return false
    end
    local bag = session.bag
    for _, r in ipairs(rewards) do
      local okC = false
      pcall(function() okC = Bag.canAdd(bag, r.id, r.qty) end)
      if okC ~= true then return false end
    end
    local droppedPending = false
    local droppedIndex = nil
    if res.pending then
      res.pending = nil
      droppedPending = true
    else
      local party = session.party
      if type(party) == "table" then
        for i = #party, 1, -1 do
          if party[i] == mon then
            table.remove(party, i)
            droppedIndex = i
            break
          end
        end
      end
    end
    local granted = true
    pcall(function()
      for _, r in ipairs(rewards) do
        if Bag.add(bag, r.id, r.qty) ~= true then granted = false end
      end
    end)
    if not granted then
      if droppedPending then
        res.pending = true
      elseif droppedIndex ~= nil and type(session.party) == "table" then
        table.insert(session.party, math.min(droppedIndex, #session.party + 1), mon)
      end
      return false
    end
    res.location = "party"
    Ui.push("Converted into " .. rewardText(rewards) .. "!")
    B._phase = "catch_pc_msg"
    return true
  end
  local function wrapUi()
    local okU, Ui = pcall(require, "src.core.game3.battle.ui")
    if not (okU and Ui and type(Ui.askYesNo) == "function") then return false end
    if Ui.__spCandyAskWrapped then return true end
    Ui.__spCandyAskWrapped = true
    local nativeAsk = Ui.askYesNo
    Ui.askYesNo = function(a, b)
      ensureWraps()
      local cb = (type(a) == "function") and a or b
      local prompt = (type(a) == "string") and a or nil
      local B, st, res = nil, nil, nil
      local divert = false
      pcall(function()
        if not SP.on() then return end
        if type(prompt) ~= "string" then return end
        if type(cb) ~= "function" then return end
        B = battleMod()
        if B == nil or B._headless then return end
        if B._phase ~= "catch_nickname_prompt" then return end
        st = B._st
        if type(st) ~= "table" or isTutorial(st) then return end
        res = liveCatchRes()
        if type(res) ~= "table" or not res.success then return end
        if res.firstTimeCaught then return end
        if res.spCandyAsked then return end
        if type(res.mon) ~= "table" then return end
        divert = true
      end)
      if not divert then
        return nativeAsk(a, b)
      end
      res.spCandyAsked = true
      local caughtState = st
      local mon = res.mon
      local species = mon.species or mon.speciesId
      local rewards = rewardsFor(species, cleanName(mon, species),
        tonumber(mon.level) or 1)
      nativeAsk("You already have a copy of this POKéMON.\nExchange it for an EXP CANDY?",
        function(yes)
          if not B._active or B._st ~= caughtState
              or B._phase ~= "catch_nickname_prompt" then
            return
          end
          if not yes then
            nativeAsk(prompt, cb)
            return
          end
          local done = false
          pcall(function()
            done = convertRes(B, Ui, res, mon, rewards)
          end)
          if not done then
            nativeAsk(prompt, cb)
          end
        end)
      return
    end
    return true
  end
  local wrapsDone = false
  ensureWraps = function()
    if wrapsDone then return true end
    local ok = wrapInfo()
    ok = wrapIcons() and ok
    ok = wrapDraw() and ok
    ok = wrapRseDraw() and ok
    ok = wrapUse() and ok
    ok = wrapUi() and ok
    ok = wrapTarget() and ok
    wrapsDone = ok
    return wrapsDone
  end
  ensureWraps()
  if mod.events and type(mod.events.on) == "function" then
    mod.events:on("battle.started", function()
      ensureWraps()
    end)
  end
  mod.log:info("safari-plus: duplicate catch candy exchange installed")
end
