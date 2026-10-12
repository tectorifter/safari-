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
local PSEUDO = {
  [149] = true, [248] = true, [373] = true, [376] = true,
  DRAGONITE = true, TYRANITAR = true, SALAMENCE = true, METAGROSS = true,
}
local TIERS = {
  { max = 5, rewards = { { id = CANDY.XS.id, qty = 1 } } },
  { max = 8, rewards = { { id = CANDY.XS.id, qty = 2 } } },
  { max = 10, rewards = { { id = CANDY.XS.id, qty = 3 } } },
  { max = 15, rewards = { { id = CANDY.S.id, qty = 1 } } },
  { max = 20, rewards = { { id = CANDY.S.id, qty = 2 } } },
  { max = 29, rewards = { { id = CANDY.S.id, qty = 3 } } },
  { max = 35, rewards = { { id = CANDY.M.id, qty = 1 } } },
  { max = 40, rewards = {
    { id = CANDY.M.id, qty = 1 }, { id = CANDY.S.id, qty = 1 } } },
  { max = 45, rewards = { { id = CANDY.L.id, qty = 1 } } },
  { max = 100, rewards = {
    { id = CANDY.L.id, qty = 1 }, { id = CANDY.M.id, qty = 1 } } },
}
local function copyRewards(row)
  local out = {}
  for _, r in ipairs(row) do
    out[#out + 1] = { id = r.id, qty = r.qty }
  end
  return out
end
local function rewardsFor(species, cname, level, isLegend)
  if isLegend then
    return { { id = CANDY.XL.id, qty = 1 }, { id = CANDY.L.id, qty = 1 } }
  end
  local sid = tonumber(species)
  if (sid and PSEUDO[sid]) or PSEUDO[cname] then
    return { { id = CANDY.XL.id, qty = 1 } }
  end
  local lvl = math.max(1, math.min(100, math.floor(tonumber(level) or 1)))
  for _, tier in ipairs(TIERS) do
    if lvl <= tier.max then return copyRewards(tier.rewards) end
  end
  return copyRewards(TIERS[#TIERS].rewards)
end
local function rewardText(rewards)
  local parts = {}
  for _, r in ipairs(rewards) do
    local def = BY_ID[r.id]
    if def then parts[#parts + 1] = tostring(r.qty) .. " " .. def.name end
  end
  return table.concat(parts, " and ")
end
return {
  CANDY = CANDY,
  BY_ID = BY_ID,
  PSEUDO = PSEUDO,
  TIERS = TIERS,
  rewardsFor = rewardsFor,
  rewardText = rewardText,
}
