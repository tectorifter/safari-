return function(mod)
  local SP = mod.exports.safariPlus
  if not SP then return end
  -- Start-menu SAFARI row: four chained bubbles with each skill's
  -- level, in-level progress, and current effect line.
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
    local tab = SP.XP_TABLE[skill]
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
    local Message = SP.require("src.ui.game3.message")
    if type(Message) ~= "table" or type(Message.show) ~= "function" then
      mod.log:warn("safari-plus: SAFARI unavailable (field message module missing)")
      return
    end
    local SM = SP.require("src.ui.game3.start_menu")
    if type(SM) == "table" and type(SM.close) == "function" then SM.close(true) end
    local texts = {}
    for _, skill in ipairs(SP.SKILL_ORDER) do texts[#texts + 1] = bubble(skill) end
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
