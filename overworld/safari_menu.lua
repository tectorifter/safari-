return function(mod)
  local SP = mod.exports.safariPlus
  if not SP then return end
  local function effect(skill)
    if skill == "catch" then
      return "catch rate +" .. string.format("%.1f", SP.catchBonus())
    elseif skill == "like" then
      return "like x" .. string.format("%.1f", SP.likeValue())
    elseif skill == "regen" then
      return "ball/" .. string.format("%.1f", SP.regenInterval()) .. "s"
    elseif skill == "cap" then
      return "cap " .. SP.cap() .. "/70"
    end
    return ""
  end
  local function bubble(skill)
    local lvl = SP.level(skill)
    local max = SP.maxOf(skill)
    local total = 0
    if type(SP.xp) == "function" then total = SP.xp(skill) end
    local tab = type(SP.XP_TABLE) == "table" and SP.XP_TABLE[skill]
    local floor = 0
    if type(tab) == "table" then floor = tonumber(tab[lvl + 1]) or 0 end
    local need = type(tab) == "table" and tonumber(tab[lvl + 2]) or nil
    if need == nil or lvl >= max then
      return "Safari " .. skill .. " Lv " .. lvl .. "/" .. max .. " MAX\n" .. effect(skill)
    end
    local span = need - floor
    if span <= 0 then span = 1 end
    local prog = total - floor
    if prog < 0 then prog = 0 end
    if prog > span then prog = span end
    return "Safari " .. skill .. " Lv " .. lvl .. "/" .. max .. " "
      .. prog .. "/" .. span .. "\n" .. effect(skill)
  end
  local function open(game, session)
    local okM, Message = pcall(require, "src.ui.game3.message")
    if not okM or type(Message) ~= "table" or type(Message.show) ~= "function" then
      mod.log:warn("safari-plus: SAFARI unavailable (field message module missing)")
      return
    end
    local okS, SM = pcall(require, "src.ui.game3.start_menu")
    if okS and type(SM) == "table" and type(SM.close) == "function" then pcall(SM.close, true) end
    local texts = {}
    if type(SP.playerLevel) == "function"
        and type(SP.playerXp) == "function" then
      local okP, lv = pcall(SP.playerLevel)
      local okX, total = pcall(SP.playerXp)
      if okP and okX then
        lv = math.floor(tonumber(lv) or 1)
        total = math.floor(tonumber(total) or 0)
        local TH = type(SP.playerLevelData) == "table"
          and SP.playerLevelData.THRESHOLDS or nil
        local max = type(TH) == "table" and #TH or 80
        if lv >= max then
          texts[#texts + 1] = "Player Lv " .. lv .. "/" .. max .. " MAX"
        else
          local floor = type(TH) == "table"
            and math.floor(tonumber(TH[lv]) or 0) or 0
          local ceil = type(TH) == "table"
            and math.floor(tonumber(TH[lv + 1]) or 0) or 0
          local need = ceil - floor
          if need < 1 then need = 1 end
          local have = total - floor
          if have < 0 then have = 0 end
          if have > need then have = need end
          texts[#texts + 1] = "Player Lv " .. lv .. "/" .. max
            .. " " .. have .. "/" .. need .. "\nGO trainer levels"
        end
      end
    end
    for _, skill in ipairs(SP.ORDER) do texts[#texts + 1] = bubble(skill) end
    local function showAt(i)
      if i > #texts then return end
      local ok = pcall(Message.show, texts[i], function() showAt(i + 1) end)
      if not ok then mod.log:warn("safari-plus: SAFARI bubble %d failed", i) end
    end
    showAt(1)
  end
  if mod.hooks and type(mod.hooks.wrap) == "function" then
    mod.hooks:wrap("ui.start_menu.items", function(next, game, items)
      items[#items + 1] = { id = "sp_safari", label = "SAFARI",
        onSelect = function(g, session) open(g, session) end }
      return next(game, items)
    end)
  end
  mod.log:info("safari-plus: SAFARI menu row registered")
end
