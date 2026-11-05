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
local POUCH = { id = 9400, name = "CANDY POUCH", price = 0,
  tint = { 0.85, 0.72, 0.5 } }
local BY_ID = {}
for _, def in pairs(CANDY) do BY_ID[def.id] = def end
-- Stat (EV) candies: 6 stats x 3 sizes. Size follows the caught mon's
-- level (S 1-18, L 19-36, XL 37-100); the stat follows the caught
-- species' own EV yield, read at runtime. Every size grants +4 EVs,
-- gated by the stat's current EVs: S below 100, L from 100 below
-- 200, XL from 200 to 252. The tint colors the stripped gray
-- candy base, so one base sprite serves all six stats.
local STAT_ORDER = { "hp", "atk", "def", "spa", "spd", "spe" }
local STAT_LABEL = {
  hp = "HP", atk = "ATTACK", def = "DEFENSE",
  spa = "SP. ATK", spd = "SP. DEF", spe = "SPEED",
}
local STAT_TINT = {
  hp = { 1, 0.85, 0.2 },
  atk = { 1, 0.25, 0.25 },
  def = { 0.35, 0.9, 0.4 },
  spa = { 1, 0.25, 0.9 },
  spd = { 0.6, 0.3, 0.95 },
  spe = { 1, 0.55, 0.7 },
}
local STAT_SIZE = {
  S = { ev = 4, price = 800 },
  L = { ev = 4, price = 1600 },
  XL = { ev = 4, price = 3200 },
}
local STAT_WINDOW = {
  S = { lo = 0, hi = 100 },
  L = { lo = 100, hi = 200 },
  XL = { lo = 200, hi = 252 },
}
local STAT_BASE_ID = 9120
local STAT = {}
for i, stat in ipairs(STAT_ORDER) do
  for j, size in ipairs({ "S", "L", "XL" }) do
    local id = STAT_BASE_ID + (i - 1) * 3 + j
    local def = {
      id = id,
      name = STAT_LABEL[stat] .. " CANDY " .. size,
      kind = "stat",
      evStat = stat,
      ev = STAT_SIZE[size].ev,
      size = size,
      tint = STAT_TINT[stat],
      price = STAT_SIZE[size].price,
    }
    STAT[stat .. "_" .. size] = def
    BY_ID[id] = def
  end
end
local function sizeForLevel(level)
  local lvl = math.max(1, math.min(100, math.floor(tonumber(level) or 1)))
  if lvl <= 18 then return "S" end
  if lvl <= 36 then return "L" end
  return "XL"
end
-- One candy (qty 1) per yielded stat, all at the level's size. Yield
-- amounts don't scale the reward; every size grants +4 EVs, gated by
-- the stat's current-EV window for that size.
local function statRewardsFor(size, yield)
  local list = {}
  if type(yield) ~= "table" then return list end
  for _, stat in ipairs(STAT_ORDER) do
    if (tonumber(yield[stat]) or 0) > 0 then
      local def = STAT[stat .. "_" .. size]
      if def then list[#list + 1] = { id = def.id, qty = 1 } end
    end
  end
  return list
end
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
local function rewardLines(rewards)
  local out = {}
  if type(rewards) ~= "table" then return out end
  for _, r in ipairs(rewards) do
    local def = type(r) == "table" and BY_ID[r.id] or nil
    if def then
      out[#out + 1] = tostring(r.qty) .. " " .. def.name
    end
  end
  return out
end
return {
  CANDY = CANDY,
  POUCH = POUCH,
  BY_ID = BY_ID,
  PSEUDO = PSEUDO,
  TIERS = TIERS,
  rewardsFor = rewardsFor,
  rewardText = rewardText,
  rewardLines = rewardLines,
  STAT = STAT,
  STAT_ORDER = STAT_ORDER,
  STAT_LABEL = STAT_LABEL,
  STAT_TINT = STAT_TINT,
  STAT_SIZE = STAT_SIZE,
  STAT_WINDOW = STAT_WINDOW,
  sizeForLevel = sizeForLevel,
  statRewardsFor = statRewardsFor,
  SPECIES_ROOM = 1025,
}
