return function(mod)
  local SP = mod.exports.safariPlus
  if not SP then return end
  local DATA = SP.partnerMoveData
  if type(DATA) ~= "table" then return end
  local _unpack = table.unpack or unpack
  local SCR_MENU_CANCEL = 0x7F
  local function partnerOn()
    return SP.opt("partner", true) ~= false
  end
  local MOM_GFX = 215
  local function mentions(v, words, depth)
    if depth > 2 then return false end
    if type(v) == "string" then
      local s = v:upper()
      for _, w in ipairs(words) do
        if s:find(w, 1, true) ~= nil then return true end
      end
      return false
    end
    if type(v) == "number" then return v == MOM_GFX end
    if type(v) == "table" then
      for _, sub in pairs(v) do
        if mentions(sub, words, depth + 1) then return true end
      end
    end
    return false
  end
  local function isMomEo(eo)
    if type(eo) ~= "table" then return false end
    if tonumber(eo.graphicsId) == MOM_GFX
        or tonumber(eo.gfxId) == MOM_GFX
        or tonumber(eo.gfx) == MOM_GFX then
      return true
    end
    if mentions(eo.scriptKey, { "MOM" }, 0) then return true end
    if type(eo.def) == "table" then
      if tonumber(eo.def.graphicsId) == MOM_GFX
          or tonumber(eo.def.gfxId) == MOM_GFX
          or tonumber(eo.def.gfx) == MOM_GFX then
        return true
      end
      if mentions(eo.def.scriptKey, { "MOM" }, 0) then return true end
    end
    return false
  end
  local function lidOf(eo)
    if type(eo) ~= "table" then return 0 end
    return eo.localId
      or (eo.def and (eo.def.localId or eo.def.index)) or 0
  end
  local function findPartner()
    local session = SP.session()
    local party = (type(session) == "table") and session.party or nil
    if type(party) ~= "table" then return nil end
    for i, mon in ipairs(party) do
      if type(mon) == "table" and mon.spPartner and not mon.isEgg then
        return mon, i
      end
    end
    return nil
  end
  local function countBadges()
    local session = SP.session()
    local base = 0x820
    local BP = SP.require("src.core.game3.battle.profile")
    if type(BP) == "table" and type(BP.get) == "function" then
      local ok, p = pcall(BP.get, session)
      if ok and type(p) == "table" and type(p.badgeFlags) == "table"
          and tonumber(p.badgeFlags[1]) then
        base = math.floor(tonumber(p.badgeFlags[1]))
      end
    end
    local Flags = SP.require("src.core.game3.scripting.flags")
    local Space = SP.require("src.core.game3.scripting.space")
    local store = (type(Space) == "table") and Space.store or nil
    local n = 0
    for i = 0, 7 do
      if type(Flags) == "table" and type(Flags.getFlag) == "function"
          and store ~= nil then
        local ok, v = pcall(Flags.getFlag, store, nil, base + i)
        if ok and v == true then n = n + 1 end
      end
    end
    return n
  end
  local NAT_CAP = 1025
  local function candyTotal(bag)
    local Bag = SP.require("src.core.game3.bag")
    if type(Bag) ~= "table" or type(Bag.get) ~= "function" then return 0 end
    local total = 0
    for nat = 1, NAT_CAP do
      local ok, q = SP.try(Bag.get, bag, 9500 + nat)
      if ok then total = total + math.floor(tonumber(q) or 0) end
    end
    return total
  end
  local function candyTake(bag, cost)
    local Bag = SP.require("src.core.game3.bag")
    if type(Bag) ~= "table" or type(Bag.remove) ~= "function"
        or type(Bag.get) ~= "function" then
      return false
    end
    local need = math.floor(tonumber(cost) or 0)
    for nat = 1, NAT_CAP do
      if need <= 0 then break end
      local id = 9500 + nat
      local ok, q = SP.try(Bag.get, bag, id)
      local have = (ok and math.floor(tonumber(q) or 0)) or 0
      if have > 0 then
        local take = math.min(have, need)
        local okR, removed = SP.try(Bag.remove, bag, id, take)
        if okR and removed == true then need = need - take end
      end
    end
    return need <= 0
  end
  local function moveKnown(mon, num)
    local Pokemon = SP.require("src.core.game3.pokemon")
    if type(Pokemon) == "table"
        and type(Pokemon.knowsMove) == "function" then
      local ok, v = pcall(Pokemon.knowsMove, mon, num)
      if ok then return v == true end
    end
    if type(mon) == "table" and type(mon.moves) == "table" then
      for i = 1, 4 do
        if tonumber(mon.moves[i]) == tonumber(num) then return true end
      end
    end
    return false
  end
  local function moveName(num)
    local PM = SP.partnerMoves
    if type(PM) == "table" and type(PM.moveDef) == "function" then
      local ok, def = pcall(PM.moveDef, num)
      if ok and type(def) == "table"
          and type(def.name) == "string" then
        return def.name
      end
    end
    return "that move"
  end
  local function monName(mon)
    local Pokemon = SP.require("src.core.game3.pokemon")
    if type(Pokemon) == "table"
        and type(Pokemon.displayMonName) == "function" then
      local ok, v = pcall(Pokemon.displayMonName, mon)
      if ok and type(v) == "string" and v ~= "" then return v end
    end
    return "POKéMON"
  end
  local DESC = {
    SP_RELENTLESS_STRIKE = "Always hits. Power grows with friendship.",
    SP_BLINDPOINT_STRIKE = "Lowers the foe's Attack and Sp. Atk.",
    SP_AVALANCHE_STOMP = "Raises your side's DEFENSE.",
    SP_EMBER_PULSE = "Raises the user's Speed.",
    SP_GRASSY_SPRINT = "Strikes first. May cause flinching.",
    SP_DRAGON_ROAR = "Power grows with friendship. Restores HP.",
    SP_TERRA_SHOT = "Seeds the foe to drain HP every turn.",
    SP_LEAF_GALE = "May lower the foe's Speed.",
    SP_HYDRO_SHIELD = "A shield that blocks, then cures status.",
    SP_TREMOR = "Always hits. Power grows with friendship.",
    SP_MUD_TRAPS = "Strikes first at foes using weak moves.",
    SP_FROST_SWAMP = "May lower the foe's Defense.",
  }
  local function descFor(id, name)
    local PM = SP.partnerMoves
    if type(PM) == "table" and type(PM.moveDef) == "function" then
      local ok, def = pcall(PM.moveDef, id)
      if ok and type(def) == "table" and type(def.id) == "string"
          and DESC[def.id] ~= nil then
        return DESC[def.id]
      end
    end
    if type(name) == "string" and DESC[name] ~= nil then return DESC[name] end
    return nil
  end
  local function extendDescs()
    local SD = SP.require("src.core.game3.summary_data")
    if type(SD) ~= "table"
        or type(SD.moveDescription) ~= "function" then
      return
    end
    if not SP.claim(SD, "__spMomTutorDescWrapped") then return end
    local native = SD.moveDescription
    SD.moveDescription = function(id, name)
      local ours = descFor(id, name)
      if ours ~= nil then
        local ok, d = pcall(native, id, name)
        if ok and type(d) == "string" and d ~= "" and d ~= "---" then
          return d
        end
        return ours
      end
      return native(id, name)
    end
  end
  local TutorNums = nil
  local function extendPreview()
    local Screens = SP.require("src.ui.game3.screens")
    local Space = SP.require("src.core.game3.scripting.space")
    local store = (type(Space) == "table") and Space.store or nil
    local Preview = nil
    if type(Screens) == "table"
        and type(Screens.get) == "function" then
      local ok, p = pcall(Screens.get, "frontier_preview",
        store or SP.session())
      if ok and type(p) == "table" then Preview = p end
    end
    if Preview == nil or type(Preview.ids) ~= "function" then return end
    if not SP.claim(Preview, "__spMomTutorIdsWrapped") then return end
    local nativeIds = Preview.ids
    Preview.ids = function(file)
      if file == "tutor1" and TutorNums ~= nil then return TutorNums end
      return nativeIds(file)
    end
  end
  local Active = nil
  local function menuMod()
    local LM = SP.require("src.core.game3.scripting.natives_listmenu")
    if type(LM) == "table" and type(LM.Menu) == "table" then
      return LM.Menu
    end
    return nil
  end
  local function textWidth(text)
    local Font = SP.require("src.ui.game3.frlg_font")
    if type(Font) == "table" and type(Font.measure) == "function" then
      local ok, w = pcall(Font.measure, text)
      if ok and tonumber(w) then return tonumber(w) end
    end
    return #tostring(text) * 6
  end
  local function failTalk(text, lid)
    TutorNums = nil
    Active = nil
    local Message = SP.require("src.ui.game3.message")
    if type(Message) == "table"
        and type(Message.show) == "function" then
      Message.show(text, function()
        pcall(function()
          local Objects = SP.require("src.core.game3.objects")
          if type(Objects) == "table"
              and type(Objects.unfreeze) == "function" then
            Objects.unfreeze(lid)
          end
        end)
      end)
    else
      pcall(function()
        local Objects = SP.require("src.core.game3.objects")
        if type(Objects) == "table"
            and type(Objects.unfreeze) == "function" then
          Objects.unfreeze(lid)
        end
      end)
    end
  end
  local function closeShop(ctx)
    TutorNums = nil
    if Active == ctx then Active = nil end
    if type(ctx) == "table" and tonumber(ctx.lid) ~= nil then
      pcall(function()
        local Objects = SP.require("src.core.game3.objects")
        if type(Objects) == "table"
            and type(Objects.unfreeze) == "function" then
          Objects.unfreeze(ctx.lid)
        end
      end)
    end
  end
  local function promptFor(ctx)
    local session = SP.session()
    local bag = (type(session) == "table") and session.bag or nil
    return "Which move should I teach " .. monName(ctx.mon) .. "?\nCandy: "
      .. tostring(candyTotal(bag)) .. "SC"
  end
  local onPick, showPromptAndList, startLearn
  local function showList(ctx, sel)
    local Menu = menuMod()
    if Menu == nil or type(Menu.showItems) ~= "function" then
      return false
    end
    local labels = {}
    local nameW, tailW = 0, 0
    for _, num in ipairs(ctx.nums) do
      local price = tostring(ctx.costOf(num)) .. "SC"
      local nm = moveName(num)
      labels[#labels + 1] = { text = nm, tail = price }
      local w = textWidth(nm)
      if w > nameW then nameW = w end
      local tw = textWidth(price)
      if tw > tailW then tailW = tw end
    end
    labels[#labels + 1] = "CANCEL"
    local tailRight = math.floor(nameW + 14 + tailW)
    for _, label in ipairs(labels) do
      if type(label) == "table" then label.tailRight = tailRight end
    end
    local width = math.floor((tailRight + 9) / 8) + 1
    if width < 8 then width = 8 end
    local left = 29 - width
    if left < 13 then left = 13 end
    if left > 16 then left = 16 end
    TutorNums = ctx.nums
    local okShow = SP.try(Menu.showItems, 9, labels, {
      count = #labels,
      maxShowed = #labels,
      left = left,
      top = 1,
      height = 12,
      keepOpen = false,
      exchangeMenuId = 9,
    }, 0, math.floor(tonumber(sel) or 0), function(index)
      onPick(ctx, index)
    end)
    if not okShow then
      TutorNums = nil
      return false
    end
    return true
  end
  showPromptAndList = function(ctx, sel)
    if Active ~= ctx then return end
    local Message = SP.require("src.ui.game3.message")
    if type(Message) ~= "table"
        or type(Message.show) ~= "function" then
      failTalk("Mom can't teach right now.", ctx.lid)
      return
    end
    Message.show(promptFor(ctx), function()
      if Active ~= ctx then return end
      if not showList(ctx, sel) then
        failTalk("Mom can't teach right now.", ctx.lid)
      end
    end)
  end
  local function settleLearn(ctx, num)
    local cost = 0
    for i, n in ipairs(ctx.nums) do
      if tonumber(n) == tonumber(num) then
        cost = math.floor(tonumber(DATA.COSTS[i]) or 0)
        break
      end
    end
    local Pokemon = SP.require("src.core.game3.pokemon")
    local def = nil
    local PM = SP.partnerMoves
    if type(PM) == "table" and type(PM.moveDef) == "function" then
      local ok, d = pcall(PM.moveDef, num)
      if ok and type(d) == "table" then def = d end
    end
    local pp = (def ~= nil and tonumber(def.pp)) or 10
    local mon = ctx.mon
    if type(mon) == "table" then
      for i = 1, 4 do
        if tonumber(mon.moves and mon.moves[i]) == tonumber(num) then
          mon.pp = mon.pp or {}
          mon.maxPp = mon.maxPp or {}
          mon.moveIds = mon.moveIds or {}
          mon.pp[i] = pp
          mon.maxPp[i] = pp
          mon.moveIds[i] = tonumber(num)
        end
      end
    end
    local session = SP.session()
    local bag = (type(session) == "table") and session.bag or nil
    candyTake(bag, cost)
  end
  local function openForget(ctx, labels, cb)
    local okS, SummaryMenu = pcall(SP.require, "src.ui.game3.summary_menu")
    if not (okS and type(SummaryMenu) == "table"
        and type(SummaryMenu.openMenu) == "function") then
      if cb then cb(nil) end
      return
    end
    local party = nil
    local session = SP.session()
    if type(session) == "table" and type(session.party) == "table" then
      party = session.party
    end
    local slot = 1
    if type(party) == "table" then
      for i = 1, #party do
        if party[i] == ctx.mon then
          slot = i
          break
        end
      end
    end
    local okOpen = pcall(SummaryMenu.openMenu, party or { ctx.mon },
      slot, {
        session = session,
        mode = "select_move",
        moveToLearn = ctx.pendingNum,
        onSelectMove = function(slotIdx)
          if cb then cb(slotIdx) end
        end,
      })
    if not okOpen and cb then cb(nil) end
  end
  startLearn = function(ctx, num)
    local LearnMove = SP.require("src.core.game3.battle.learn_move")
    local Message = SP.require("src.ui.game3.message")
    local Choice = SP.require("src.ui.game3.choice")
    if type(LearnMove) ~= "table"
        or type(LearnMove.begin) ~= "function"
        or type(Message) ~= "table"
        or type(Message.show) ~= "function" then
      Message.show("Mom can't teach right now.", function()
        showPromptAndList(ctx)
      end)
      return
    end
    if type(Choice) ~= "table" or type(Choice.yesNo) ~= "function" then
      Message.show("Mom can't teach right now.", function()
        showPromptAndList(ctx)
      end)
      return
    end
    ctx.pendingNum = tonumber(num)
    local mon = ctx.mon
    local full = type(mon) == "table" and type(mon.moves) == "table"
      and #mon.moves >= 4
    local function beginNow()
      if Active ~= ctx then return end
      LearnMove.begin({
        mon = mon,
        moveId = tonumber(num),
        relearner = true,
        displayName = monName(mon),
        pushMsg = function(text, cb)
          Message.show(text, cb)
        end,
        askYesNo = function(text, cb)
          Message.show(text, function()
            if Active ~= ctx then
              if cb then cb(false) end
              return
            end
            Choice.yesNo(function(yes)
              pcall(Message.close, Message)
              if cb then cb(yes) end
            end)
          end)
        end,
        askForget = function(labels, cb)
          openForget(ctx, labels, cb)
        end,
        onDone = function(learned)
          ctx.pendingNum = nil
          if Active ~= ctx then return end
          if learned == true then
            settleLearn(ctx, tonumber(num))
          end
          showPromptAndList(ctx)
        end,
      })
    end
    if full then
      Message.show("Which move should be forgotten?", function()
        if Active ~= ctx then return end
        openForget(ctx, nil, function(slotIdx)
          if Active ~= ctx then return end
          if slotIdx == nil then
            showPromptAndList(ctx)
            return
          end
          local ML = SP.require("src.core.game3.move_learn")
          if type(ML) == "table"
              and type(ML.forgetMove) == "function" then
            SP.try(ML.forgetMove, mon, slotIdx)
          end
          beginNow()
        end)
      end)
    else
      beginNow()
    end
  end
  onPick = function(ctx, index)
    if Active ~= ctx then return end
    if index == SCR_MENU_CANCEL or index == nil
        or tonumber(index) == nil
        or tonumber(index) + 1 > #ctx.nums then
      closeShop(ctx)
      return
    end
    ctx.lastSel = math.floor(tonumber(index))
    local num = ctx.nums[ctx.lastSel + 1]
    local PM = SP.partnerMoves
    local badges = countBadges()
    local allowed = 0
    if type(PM) == "table" and type(PM.allowedFor) == "function" then
      allowed = math.floor(tonumber(PM.allowedFor(badges)) or 0)
    end
    local session = SP.session()
    local bag = (type(session) == "table") and session.bag or nil
    local candy = candyTotal(bag)
    local cost = ctx.costOf(num)
    local needBadges = ctx.needOf(num)
    local Message = SP.require("src.ui.game3.message")
    local Choice = SP.require("src.ui.game3.choice")
    if type(Message) ~= "table"
        or type(Message.show) ~= "function"
        or type(Choice) ~= "table"
        or type(Choice.yesNo) ~= "function" then
      failTalk("Mom can't teach right now.", ctx.lid)
      return
    end
    if moveKnown(ctx.mon, num) then
      Message.show("Your partner already knows " .. moveName(num) .. ".",
        function()
          showPromptAndList(ctx, ctx.lastSel)
        end)
      return
    end
    if ctx.lastSel + 1 > allowed then
      Message.show("That lesson needs " .. needBadges .. " badges (you have "
        .. badges .. ").", function()
          showPromptAndList(ctx, ctx.lastSel)
        end)
      return
    end
    if candy < cost then
      Message.show("That lesson needs " .. cost .. " species candy (you have "
        .. candy .. ").", function()
          showPromptAndList(ctx, ctx.lastSel)
        end)
      return
    end
    Message.show("Teach " .. moveName(num) .. " to " .. monName(ctx.mon)
      .. " for " .. cost .. " species candy?", function()
        if Active ~= ctx then return end
        Choice.yesNo(function(yes)
          pcall(Message.close, Message)
          if Active ~= ctx then return end
          if yes then
            startLearn(ctx, num)
          else
            showPromptAndList(ctx, ctx.lastSel)
          end
        end)
      end)
  end
  local function openTutor(lid)
    if type(SP.partnerMoves) ~= "table"
        or type(SP.partnerMoves.lineOf) ~= "function" then
      failTalk("Mom has nothing to teach yet.", lid)
      return
    end
    local PM = SP.partnerMoves
    if type(PM.ensure) == "function" then SP.try(PM.ensure) end
    local mon = findPartner()
    if mon == nil then
      failTalk("Mom has nothing to teach yet.", lid)
      return
    end
    local line = PM.lineOf(mon)
    if line == nil then
      failTalk("Mom has nothing to teach yet.", lid)
      return
    end
    local entry = DATA.LINES[line]
    if type(entry) ~= "table" or type(entry.nums) ~= "table" then
      failTalk("Mom can't teach right now.", lid)
      return
    end
    extendDescs()
    extendPreview()
    local ctx = { mon = mon, nums = entry.nums, lid = lid }
    ctx.costOf = function(num)
      for i, n in ipairs(ctx.nums) do
        if tonumber(n) == tonumber(num) then
          return math.floor(tonumber(DATA.COSTS[i]) or 0)
        end
      end
      return 0
    end
    ctx.needOf = function(num)
      for i, n in ipairs(ctx.nums) do
        if tonumber(n) == tonumber(num) then
          return math.floor(tonumber(DATA.UNLOCK[i]) or 0)
        end
      end
      return 0
    end
    Active = ctx
    showPromptAndList(ctx)
  end
  local function playerName()
    local session = SP.session()
    if type(session) == "table"
        and type(session.name) == "string"
        and session.name ~= "" then
      return session.name
    end
    return nil
  end
  if mod.hooks and type(mod.hooks.wrap) == "function" then
    mod.hooks:wrap("world.talk", function(nextFn, ...)
      local args = { ... }
      local game = args[1]
      local eo = nil
      for i = 1, #args do
        local a = args[i]
        if type(a) == "table"
            and (a.def or a.scriptKey or a.localId) then
          eo = a
          break
        end
      end
      if type(nextFn) ~= "function" then return end
      if not partnerOn() or not isMomEo(eo) then
        return nextFn(...)
      end
      local Message = SP.require("src.ui.game3.message")
      local Choice = SP.require("src.ui.game3.choice")
      local Objects = SP.require("src.core.game3.objects")
      if type(Message) ~= "table"
          or type(Message.show) ~= "function"
          or type(Choice) ~= "table"
          or type(Choice.multi) ~= "function"
          or type(Objects) ~= "table" then
        return nextFn(...)
      end
      if Active ~= nil then return true end
      local lid = lidOf(eo)
      pcall(function()
        if type(Objects.freeze) == "function" then Objects.freeze(lid) end
        if type(Objects.facePlayer) == "function" then
          Objects.facePlayer(lid, game)
        end
      end)
      mod.log:info("safari-plus: mom tutor intercept sk=%s map=%s",
        tostring(eo.scriptKey),
        tostring(SP.session() and SP.session().map))
      local nm = playerName()
      local greet = (nm ~= nil and ("How are you doing " .. nm .. "?")
        or "How are you doing?")
        .. "\nDo you need help with anything?"
      Message.show(greet, function()
        Choice.multi({ "TUTOR", "REST", "CANCEL" }, 0, function(idx)
          if idx == 0 then
            pcall(Message.close, Message)
            openTutor(lid)
          elseif idx == 1 then
            pcall(Message.close, Message)
            local rest = { game }
            for i = 2, #args do rest[#rest + 1] = args[i] end
            nextFn(_unpack(rest))
          else
            pcall(Message.close, Message)
            pcall(function()
              if type(Objects.unfreeze) == "function" then
                Objects.unfreeze(lid)
              end
            end)
          end
        end)
      end)
      return true
    end)
  end
  mod.log:info("safari-plus: mom tutor installed")
end
