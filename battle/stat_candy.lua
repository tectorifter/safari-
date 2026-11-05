return function(mod)
  local SP = mod.exports.safariPlus
  if not SP then return end
  local CD = assert(SP.candyData)
  local ORDER = { "hp", "atk", "def", "spa", "spd", "spe" }
  local EV_PER_STAT_DFLT = 252
  local EV_TOTAL_DFLT = 510
  local yieldCache = {}
  local pendingStat = nil
  local pendingStatLine = nil
  local pendingSpecies = nil
  local artWarned = false

  -- Self-contained EV caps: the 1512 EVS toggle in data/options.lua
  -- switches the total between classic 510 and 1512. Per-stat stays
  -- 252 in both modes (1512 = 6 x 252), so 252 per stat is always
  -- reachable. Read live per use so flipping the toggle takes effect
  -- without a reboot. No other mod is consulted.
  local function evPerStat()
    return EV_PER_STAT_DFLT
  end
  local function evTotalCap()
    if SP.opt("ev_1512", false) == true then return 1512 end
    return EV_TOTAL_DFLT
  end

  local function normKey(k)
    if type(k) ~= "string" then return nil end
    local s = k:lower():gsub("[^a-z]", "")
    if s == "hp" or s == "health" then return "hp" end
    if s == "atk" or s == "attack" then return "atk" end
    if s == "def" or s == "defense" then return "def" end
    if s == "spa" or s == "spattack" or s == "specialattack" then
      return "spa"
    end
    if s == "spd" or s == "spdef" or s == "specialdefense" then
      return "spd"
    end
    if s == "spe" or s == "speed" then return "spe" end
    return nil
  end

  local function normalizeYield(raw)
    if type(raw) ~= "table" then return nil end
    local out, any = {}, false
    for k, v in pairs(raw) do
      local nk = normKey(k)
      if nk and (tonumber(v) or 0) > 0 then
        out[nk] = math.floor(tonumber(v))
        any = true
      end
    end
    if any then return out end
    return nil
  end

  -- Runtime-agnostic EV-yield read: native evYield first, then a scratch
  -- mon through the native gainEVs probe.
  local function yieldFor(species)
    local ck = tostring(species)
    if yieldCache[ck] ~= nil then return yieldCache[ck] end
    local found = nil
    local Pokemon = SP.require("src.core.game3.pokemon")
    if type(Pokemon) == "table" then
      if type(Pokemon.evYield) == "function" then
        local ok, y = pcall(Pokemon.evYield, species)
        if ok then found = normalizeYield(y) end
      end
      if found == nil and type(Pokemon.gainEVs) == "function" then
        local scratch = { evs = {} }
        for _, key in ipairs(ORDER) do scratch.evs[key] = 0 end
        if pcall(Pokemon.gainEVs, scratch, species) then
          found = normalizeYield(scratch.evs)
        end
      end
    end
    if found == nil then
      found = { hp = 1 }
      mod.log:warn("safari-plus: EV yield unreadable for %s, using HP",
        tostring(species))
    end
    yieldCache[ck] = found
    return found
  end

  local function battleMod()
    return SP.require("src.core.game3.battle")
  end

  local function liveState()
    local B = battleMod()
    if type(B) == "table" and type(B.getState) == "function" then
      local ok, st = pcall(B.getState)
      if ok and type(st) == "table" then return st end
    end
    return nil
  end

  local function ours(st)
    if not SP.on() then return false end
    if type(st) ~= "table" or not st.safari then return false end
    if type(st.enemy) ~= "table" then return false end
    if SP.isTutorial(st) then return false end
    return true
  end

  local function grantStat(session, rewards)
    if type(session) ~= "table" then return false end
    local Bag = SP.require("src.core.game3.bag")
    if type(Bag) ~= "table" or type(Bag.add) ~= "function"
        or type(Bag.canAdd) ~= "function" then
      return false
    end
    local bag = session.bag
    for _, r in ipairs(rewards) do
      local _, fits = SP.try(Bag.canAdd, bag, r.id, r.qty)
      if fits ~= true then return false end
    end
    for _, r in ipairs(rewards) do
      local _, added = SP.try(Bag.add, bag, r.id, r.qty)
      if added ~= true then return false end
    end
    return true
  end

  -- Species candy: awarded with the EXP-candy conversion on duplicate
  -- catches, named for the line's base species only (e.g. converting an
  -- Ivysaur while Bulbasaur is already caught can drop "Bulbasaur
  -- candy"). Kept duplicates grant none. Using them on
  -- a mon of the same line raises every stat tied at the lowest IV by
  -- +1, costing 1 candy at 0-10, 3 at 11-20, 5 at 21-29, 10 for 30-31.
  local SPECIES_BASE = 9500
  local SPECIES_MAX = 10600
  local SPECIES_DROP_PCT = 100
  local IV_KEYS = { "hp", "atk", "def", "spa", "spd", "spe" }

  local function rng(n)
    n = math.max(1, math.floor(tonumber(n) or 1))
    local R = SP.require("src.core.game3.rng")
    if type(R) == "table" and type(R.Random) == "function" then
      local ok, v = pcall(R.Random)
      if ok and tonumber(v) ~= nil then return tonumber(v) % n end
    end
    return math.random(0, n - 1)
  end

  local SIZE_ROLL = {
    { qty = 0, pct = 5, msg = "You found a very small pokemon!" },
    { qty = 1, pct = 80, msg = "You found a normal sized pokemon" },
    { qty = 2, pct = 10, msg = "You found an above average sized pokemon!" },
    { qty = 3, pct = 5, msg = "You found a giant pokemon!" },
  }
  local function rollSize()
    local total = 0
    for _, row in ipairs(SIZE_ROLL) do
      total = total + math.floor(row.pct * 10 + 0.5)
    end
    if total < 1 then return SIZE_ROLL[2] end
    local r = rng(total)
    local acc = 0
    for _, row in ipairs(SIZE_ROLL) do
      acc = acc + math.floor(row.pct * 10 + 0.5)
      if r < acc then return row end
    end
    return SIZE_ROLL[#SIZE_ROLL]
  end

  local function numericSpecies(species)
    local id = tonumber(species)
    if id ~= nil then return id end
    if type(species) == "string" then
      local Pokemon = SP.require("src.core.game3.pokemon")
      if type(Pokemon) == "table"
          and type(Pokemon.speciesFromName) == "function" then
        local ok, v = pcall(Pokemon.speciesFromName, species)
        id = tonumber(v)
        if id ~= nil then return id end
      end
    end
    return nil
  end

  local function speciesOfMon(mon)
    if type(mon) ~= "table" then return nil end
    local Pokemon = SP.require("src.core.game3.pokemon")
    if type(Pokemon) == "table"
        and type(Pokemon.speciesOf) == "function" then
      local ok, v = pcall(Pokemon.speciesOf, mon)
      if ok and (tonumber(v) ~= nil or type(v) == "string") then
        local n = numericSpecies(v)
        if n ~= nil then return n end
      end
    end
    if mon.species ~= nil then
      local n = numericSpecies(mon.species)
      if n ~= nil then return n end
    end
    return numericSpecies(mon.speciesId)
  end

  -- Reverse evolution map: pre[target] = first predecessor found.
  local evoPre = nil
  local function buildEvoPre()
    if evoPre ~= nil then return evoPre end
    evoPre = {}
    local Pokemon = SP.require("src.core.game3.pokemon")
    if type(Pokemon) == "table" and type(Pokemon.name) == "function"
        and type(Pokemon.evolutions) == "function" then
      for id = 1, 2048 do
        local okN, n = pcall(Pokemon.name, id)
        if okN and type(n) == "string" and n ~= ""
            and n ~= "??????????" then
          local okR, rows = pcall(Pokemon.evolutions, id)
          if okR and type(rows) == "table" then
            for _, evo in ipairs(rows) do
              if type(evo) == "table" then
                local t = tonumber(evo.target or evo[3]) or 0
                if t > 0 and evoPre[t] == nil then evoPre[t] = id end
              end
            end
          end
        end
      end
    end
    return evoPre
  end

  local function baseSpeciesOf(species)
    local s = numericSpecies(species)
    if s == nil then return nil end
    local pre = buildEvoPre()
    local seen = {}
    local root = s
    while pre[root] ~= nil and not seen[root] do
      seen[root] = true
      root = pre[root]
    end
    return root
  end

  -- Returns base engine id + stable national key for the item id.
  local function resolveLine(species)
    local base = baseSpeciesOf(species)
    if base == nil then return nil, nil end
    local nat = base
    local Pokemon = SP.require("src.core.game3.pokemon")
    if type(Pokemon) == "table"
        and type(Pokemon.national) == "function" then
      local ok, v = pcall(Pokemon.national, base)
      local n = math.floor(tonumber(v) or 0)
      if n >= 1 then nat = n end
    end
    return base, nat
  end

  local function titleCase(name)
    if type(name) ~= "string" or name == "" then return "Unknown" end
    local s = name:lower()
    s = s:gsub("(%a)([%w']*)", function(a, b) return a:upper() .. b end)
    return s
  end

  -- Canonical engine<->national maps, built once per boot from the
  -- loop ids that name()/national() share, so every conversion below
  -- stays inside one id space. (Engine ids carry the Unown gap:
  -- Hoenn runs 277-411 there but 252-386 nationally. A bare number in
  -- 277-386 is AMBIGUOUS — Ralts's national 280 is Torchic's engine
  -- id — which is exactly how candies got misnamed. Numbers are
  -- never trusted for names; see the name-anchored resolution below.)
  local ENG_NAT = nil
  local NAT_ENG = nil
  local function buildIdMaps()
    if ENG_NAT ~= nil then return ENG_NAT, NAT_ENG end
    ENG_NAT, NAT_ENG = {}, {}
    local Pokemon = SP.require("src.core.game3.pokemon")
    if type(Pokemon) == "table"
        and type(Pokemon.name) == "function"
        and type(Pokemon.national) == "function" then
      for id = 1, 2048 do
        local okN, nm = pcall(Pokemon.name, id)
        if okN and type(nm) == "string" and nm ~= ""
            and nm ~= "??????????" then
          local okT, v = pcall(Pokemon.national, id)
          local nat = math.floor(tonumber(v) or 0)
          if nat >= 1 and nat <= 2048 then
            ENG_NAT[id] = nat
            if NAT_ENG[nat] == nil then NAT_ENG[nat] = id end
          end
        end
      end
    end
    return ENG_NAT, NAT_ENG
  end
  local function normName(nm)
    if type(nm) ~= "string" then return nil end
    local s = nm:upper():gsub("[^A-Z0-9]", "")
    if s == "" then return nil end
    return s
  end
  -- The mon's true species name: unambiguous under every numbering,
  -- unlike its numeric species value. Fresh catches are never
  -- nicknamed yet; nicknamed party mons fall back to numeric paths.
  local function trueSpeciesName(mon)
    if type(mon) ~= "table" then return nil end
    local Pokemon = SP.require("src.core.game3.pokemon")
    if type(Pokemon) == "table"
        and type(Pokemon.displayMonName) == "function" then
      local ok, nm = pcall(Pokemon.displayMonName, mon)
      if ok and type(nm) == "string" and nm ~= "" then return nm end
    end
    return nil
  end
  -- Engine id for a species name, verified by a name() round-trip
  -- (speciesFromName's own numbering is not assumed), else a full
  -- engine-id scan. Cached. Names can't lie about their space.
  local nameEngineCache = {}
  local function engineIdForName(raw)
    local norm = normName(raw)
    if norm == nil then return nil end
    if nameEngineCache[norm] ~= nil then
      return nameEngineCache[norm] or nil
    end
    local found = nil
    local Pokemon = SP.require("src.core.game3.pokemon")
    if type(Pokemon) == "table"
        and type(Pokemon.name) == "function" then
      if type(Pokemon.speciesFromName) == "function" then
        for _, form in ipairs({ raw, norm }) do
          local ok, v = pcall(Pokemon.speciesFromName, form)
          local cand = math.floor(tonumber(v) or 0)
          if cand >= 1 then
            local okN, nm = pcall(Pokemon.name, cand)
            if okN and normName(nm) == norm then
              found = cand
              break
            end
          end
        end
      end
      if found == nil then
        for id = 1, 2048 do
          local okN, nm = pcall(Pokemon.name, id)
          if okN and normName(nm) == norm then
            found = id
            break
          end
        end
      end
    end
    nameEngineCache[norm] = found or false
    return found
  end
  local function engineIdOfMon(mon)
    local raw = trueSpeciesName(mon)
    if raw == nil then return nil end
    return engineIdForName(raw)
  end
  local function walkPre(e)
    local pre = buildEvoPre()
    local seen = {}
    local root = e
    while pre[root] ~= nil and not seen[root] do
      seen[root] = true
      root = pre[root]
    end
    return root
  end
  -- Name-anchored line resolution for a mon table: (engineBase, nat,
  -- lineName, verified=true), every step in verified engine space.
  -- The name is always the BASE species' (Kirlia grants Ralts candy).
  -- Nils when the true name can't be established or the base is
  -- unnameable (refuse rather than poison).
  local function resolveMonLine(mon)
    local raw = trueSpeciesName(mon)
    if raw == nil then return nil, nil, nil, nil end
    local e = engineIdForName(raw)
    if e == nil then return nil, nil, nil, nil end
    local root = walkPre(e)
    buildIdMaps()
    local nat = (ENG_NAT ~= nil and ENG_NAT[root]) or root
    local Pokemon = SP.require("src.core.game3.pokemon")
    if type(Pokemon) == "table"
        and type(Pokemon.name) == "function" then
      local okB, bnm = pcall(Pokemon.name, root)
      if okB and type(bnm) == "string" and bnm ~= ""
          and bnm ~= "??????????" then
        return root, nat, titleCase(bnm), true
      end
    end
    return nil, nil, nil, nil
  end
  -- Numeric fallback. Tries the value as an engine id, then as a
  -- national number; a hint (the mon's normalized true name, when
  -- known) selects the interpretation whose engine name matches and
  -- marks the result verified. Placeholder names are always refused,
  -- so this path can never write a "???" candy.
  local function resolveNumericLine(species, hintNorm)
    local id = tonumber(species)
    if id == nil and type(species) == "string" then
      id = engineIdForName(species)
    end
    id = math.floor(tonumber(id) or 0)
    if id < 1 then return nil, nil, nil, nil end
    buildIdMaps()
    local cands = {}
    if ENG_NAT[id] ~= nil then cands[#cands + 1] = id end
    local e2 = NAT_ENG[id]
    if e2 ~= nil and e2 ~= id then cands[#cands + 1] = e2 end
    local Pokemon = SP.require("src.core.game3.pokemon")
    if type(Pokemon) ~= "table"
        or type(Pokemon.name) ~= "function" then
      return nil, nil, nil, nil
    end
    for _, e in ipairs(cands) do
      local okN, nm = pcall(Pokemon.name, e)
      if okN and type(nm) == "string" and nm ~= ""
          and nm ~= "??????????" then
        local matched = hintNorm ~= nil and normName(nm) == hintNorm
        if hintNorm == nil or matched then
          local root = walkPre(e)
          local nat = ENG_NAT[root] or root
          local okB, bnm = pcall(Pokemon.name, root)
          if okB and type(bnm) == "string" and bnm ~= ""
              and bnm ~= "??????????" then
            return root, nat, titleCase(bnm), matched == true
          end
          return nil, nil, nil, nil
        end
      end
    end
    return nil, nil, nil, nil
  end
  -- Read-only same-line check for use-targets (nicknamed mons can't
  -- name-verify): true when EITHER numbering interpretation lands on
  -- the candy's line. No defs are written here, so no poison risk.
  local function lineNatMatches(species, wantNat)
    wantNat = math.floor(tonumber(wantNat) or 0)
    if wantNat < 1 then return false end
    local id = tonumber(species)
    if id == nil and type(species) == "string" then
      id = engineIdForName(species)
    end
    id = math.floor(tonumber(id) or 0)
    if id < 1 then return false end
    buildIdMaps()
    local cands = {}
    if ENG_NAT[id] ~= nil then cands[#cands + 1] = id end
    local e2 = NAT_ENG[id]
    if e2 ~= nil and e2 ~= id then cands[#cands + 1] = e2 end
    for _, e in ipairs(cands) do
      local root = walkPre(e)
      local nat = ENG_NAT[root] or root
      if nat == wantNat then return true end
    end
    return false
  end

  -- Per-base-species caught tracking (evolution lines, not forms).
  local speciesSeen = nil
  local speciesSeeded = false
  local function scrubSeen(raw)
    local out = {}
    if type(raw) == "table" then
      for k, v in pairs(raw) do
        local n = math.floor(tonumber(k) or 0)
        if n >= 1 and n <= 99999 and v then out[n] = true end
      end
    end
    return out
  end
  local function seenStore()
    if speciesSeen ~= nil then return speciesSeen end
    speciesSeen = scrubSeen(SP.saveGet("speciesDex", nil))
    return speciesSeen
  end
  local function markSeen(nat)
    local seen = seenStore()
    if seen[nat] ~= true then
      seen[nat] = true
      SP.saveSet("speciesDex", seen)
    end
  end
  -- Backfill from this mod's own mastery counters so veterans keep
  -- their lines: any species with catches marks its base seen.
  local function seedFromMastery()
    if speciesSeeded then return end
    speciesSeeded = true
    local raw = SP.saveGet("mastery", nil)
    if type(raw) ~= "table" then return end
    local have = {}
    for k, v in pairs(raw) do
      if (tonumber(v) or 0) > 0 then
        local n = math.floor(tonumber(k) or 0)
        if n >= 1 then have[n] = true end
      end
    end
    if next(have) == nil then return end
    local Pokemon = SP.require("src.core.game3.pokemon")
    if type(Pokemon) ~= "table" then return end
    if type(Pokemon.name) ~= "function" then return end
    local seen = seenStore()
    local dirty = false
    for id = 1, 2048 do
      local okN, n = pcall(Pokemon.name, id)
      if okN and type(n) == "string" and n ~= ""
          and n ~= "??????????" then
        local nat = nil
        if type(Pokemon.national) == "function" then
          local ok, v = pcall(Pokemon.national, id)
          nat = math.floor(tonumber(v) or 0)
          if nat < 1 then nat = nil end
        end
        if nat ~= nil and have[nat] then
          local _, baseNat = resolveLine(id)
          if baseNat ~= nil and not seen[baseNat] then
            seen[baseNat] = true
            dirty = true
          end
        end
      end
    end
    if dirty then SP.saveSet("speciesDex", seen) end
  end

  -- Dominant sprite color: most abundant opaque color wins. The helper
  -- counts quantized buckets over whatever pixel source the engine
  -- offers (ImageData, Image via canvas, file path, raw rgba table).
  local speciesTintCache = {}
  local tintWarned = {}
  local function normChannel(v)
    local n = tonumber(v) or 0
    if n > 1 then n = n / 255 end
    if n < 0 then return 0 end
    if n > 1 then return 1 end
    return n
  end
  local function dominantBucket(counts, reps)
    local best, bestN = nil, 0
    for key, c in pairs(counts) do
      if c > bestN then
        best, bestN = key, c
      end
    end
    if best == nil then return nil end
    return reps[best]
  end
  local function scanPixels(n, getRGBA)
    local counts, reps = {}, {}
    for i = 1, n do
      local r, g, b, a = getRGBA(i)
      if normChannel(a == nil and 1 or a) >= 0.5 then
        r, g, b = normChannel(r), normChannel(g), normChannel(b)
        local key = math.floor(r * 16) * 256
          + math.floor(g * 16) * 16 + math.floor(b * 16)
        local c = (counts[key] or 0) + 1
        counts[key] = c
        if c == 1 then reps[key] = { r, g, b } end
      end
    end
    return dominantBucket(counts, reps)
  end
  local function tintFromImageData(data)
    local w = tonumber(data.getWidth and data:getWidth())
      or tonumber(data.getWidth and nil) or 0
    if w <= 0 then return nil end
    local h = 0
    pcall(function() h = data:getHeight() end)
    if not (h > 0) then return nil end
    if type(data.getPixel) ~= "function" then return nil end
    return scanPixels(w * h, function(i)
      local x = (i - 1) % w
      local y = math.floor((i - 1) / w)
      local r, g, b, a = data:getPixel(x, y)
      return r, g, b, a
    end)
  end
  local function tintFromImage(img)
    local lv = love
    if type(lv) ~= "table" or type(lv.graphics) ~= "table" then
      return nil
    end
    if type(img.getDimensions) ~= "function" then return nil end
    local w, h = img:getDimensions()
    w, h = tonumber(w) or 0, tonumber(h) or 0
    if w <= 0 or h <= 0 or w > 256 or h > 256 then return nil end
    local canvas = lv.graphics.newCanvas(w, h)
    if canvas == nil then return nil end
    local prev = nil
    pcall(function() prev = lv.graphics.getCanvas() end)
    lv.graphics.setCanvas(canvas)
    lv.graphics.clear(0, 0, 0, 0)
    lv.graphics.draw(img, 0, 0)
    lv.graphics.setCanvas(prev)
    if type(canvas.newImageData) ~= "function" then return nil end
    local data = canvas:newImageData()
    if data == nil then return nil end
    return tintFromImageData(data)
  end
  local function tintFromCandidate(cand)
    if type(cand) == "string" then
      local lv = love
      if type(lv) ~= "table" then return nil end
      if type(lv.image) == "table"
          and type(lv.image.newImageData) == "function" then
        local ok, data = pcall(lv.image.newImageData, cand)
        if ok and data ~= nil then
          local t = tintFromImageData(data)
          if t ~= nil then return t end
        end
      end
      if type(lv.graphics) == "table"
          and type(lv.graphics.newImage) == "function" then
        local ok, img = pcall(lv.graphics.newImage, cand)
        if ok and img ~= nil then return tintFromImage(img) end
      end
      return nil
    end
    if type(cand) == "table" or type(cand) == "userdata" then
      local okI, inner = pcall(function() return cand.image end)
      if okI and inner ~= nil and inner ~= cand then
        local t = tintFromCandidate(inner)
        if t ~= nil then return t end
      end
      if type(cand.getPixel) == "function" then
        local ok, t = pcall(tintFromImageData, cand)
        if ok and t ~= nil then return t end
      end
      if type(cand.getDimensions) == "function" then
        local ok, t = pcall(tintFromImage, cand)
        if ok and t ~= nil then return t end
      end
      local rgba = cand.rgba or cand.pixels or cand.data
      local w = tonumber(cand.w or cand.width)
      local h = tonumber(cand.h or cand.height)
      if type(rgba) == "table" and w ~= nil and h ~= nil
          and w > 0 and h > 0 and w * h <= 65536 then
        local ok, t = pcall(scanPixels, w * h, function(i)
          local p = rgba[i]
          if type(p) == "table" then
            return p[1] or p.r, p[2] or p.g, p[3] or p.b,
              p[4] or p.a
          end
          return 0, 0, 0, 0
        end)
        if ok and t ~= nil then return t end
      end
    end
    return nil
  end
  local function speciesSpriteTint(base, nat)
    if speciesTintCache[nat] ~= nil then return speciesTintCache[nat] end
    local tint = nil
    pcall(function()
      local cands = {}
      local Pokemon = SP.require("src.core.game3.pokemon")
      if type(Pokemon) == "table" then
        for _, fn in ipairs({ "frontSprite", "frontPic", "icon" }) do
          if type(Pokemon[fn]) == "function" then
            local ok, v = pcall(Pokemon[fn], base)
            if ok and v ~= nil then cands[#cands + 1] = v end
          end
        end
      end
      if type(mod.content) == "table"
          and type(mod.content.pokemon) == "table" then
        local reg = mod.content.pokemon
        local nm = nil
        if type(Pokemon) == "table"
            and type(Pokemon.name) == "function" then
          local ok, v = pcall(Pokemon.name, base)
          if ok and type(v) == "string" and v ~= "" then nm = v end
        end
        for _, key in ipairs({ nm, base }) do
          if key ~= nil and type(reg.get) == "function" then
            local ok, rec = pcall(reg.get, key)
            if not ok then
              ok, rec = pcall(function() return reg:get(key) end)
            end
            if ok and type(rec) == "table" then
              for _, f in ipairs(
                  { "color", "bodyColor", "dominantColor" }) do
                local c = rec[f]
                if type(c) == "table" then
                  local r = tonumber(c[1] or c.r)
                  local g = tonumber(c[2] or c.g)
                  local b = tonumber(c[3] or c.b)
                  if r ~= nil and g ~= nil and b ~= nil then
                    tint = { normChannel(r), normChannel(g),
                      normChannel(b) }
                    return
                  end
                end
              end
              for _, f in ipairs({ "sprite", "frontSprite", "icon",
                  "image", "path" }) do
                if rec[f] ~= nil then cands[#cands + 1] = rec[f] end
              end
            end
          end
        end
      end
      for _, cand in ipairs(cands) do
        tint = tintFromCandidate(cand)
        if tint ~= nil then break end
      end
    end)
    if tint == nil then
      tint = { 0.9, 0.9, 0.9 }
      if not tintWarned[nat] then
        tintWarned[nat] = true
        mod.log:warn("safari-plus: no sprite for species candy %s",
          tostring(nat))
      end
    end
    speciesTintCache[nat] = tint
    return tint
  end

  -- Species defs live in the shared BY_ID table so reward text, bag
  -- info, icons and use all resolve them; meta persists so defs
  -- rebuild after a reboot without touching the engine.
  local function metaStore()
    if SP.speciesCandyMeta ~= nil then return SP.speciesCandyMeta end
    local cache = {}
    local raw = SP.saveGet("speciesCandyMeta", nil)
    if type(raw) == "table" then
      for k, v in pairs(raw) do
        local n = math.floor(tonumber(k) or 0)
        if n >= 1 and type(v) == "table"
            and type(v.name) == "string" then
          local t = v.tint
          if type(t) ~= "table" then t = { 0.9, 0.9, 0.9 } end
          cache[n] = { base = tonumber(v.base), name = v.name,
            tint = { normChannel(t[1]), normChannel(t[2]),
              normChannel(t[3]) } }
        end
      end
    end
    SP.speciesCandyMeta = cache
    return cache
  end
  local function healSpeciesDef(id, nat, base, lineName)    local tint = speciesSpriteTint(base, nat)
    local meta = metaStore()
    meta[nat] = { base = base, name = lineName, tint = tint }
    SP.saveSet("speciesCandyMeta", meta)
    local def = CD.BY_ID[id]
    if type(def) ~= "table" then
      def = { id = id, kind = "species", price = 500 }
      CD.BY_ID[id] = def
    end
    def.name = lineName .. " candy"
    def.baseNat = nat
    def.base = base
    def.lineName = lineName
    def.tint = tint
    def.owner = "safari-plus"
    return def
  end
  -- verified must be true only for name-anchored results (grant
  -- primary, id-map scan): those heal a poisoned name. Legacy
  -- numeric callers pass false: they may create, never overwrite.
  -- Nameless results never create — no more "???" candies.
  local function ensureSpeciesDef(base, nat, lineName, verified)
    base = math.floor(tonumber(base) or 0)
    nat = math.floor(tonumber(nat) or 0)
    if base < 1 or nat < 1 then return nil end
    local id = SPECIES_BASE + nat
    if id < SPECIES_BASE or id > SPECIES_MAX then return nil end
    if type(lineName) ~= "string" or lineName == ""
        or lineName == "??????????" or lineName == "Unknown" then
      local exist = CD.BY_ID[id]
      if type(exist) == "table" then return exist end
      return nil
    end
    local exist = CD.BY_ID[id]
    if type(exist) == "table" then
      if type(exist.owner) == "string"
          and exist.owner ~= "safari-plus" then
        return exist
      end
      if verified == true and exist.lineName ~= lineName then
        speciesTintCache[nat] = nil
        return healSpeciesDef(id, nat, base, lineName)
      end
      return exist
    end
    return healSpeciesDef(id, nat, base, lineName)
  end
  function SP.speciesDef(nat)
    nat = math.floor(tonumber(nat) or 0)
    if nat < 1 then return nil end
    local id = SPECIES_BASE + nat
    if id < SPECIES_BASE or id > SPECIES_MAX then return nil end
    -- Rebuild from the id map, never from a bare name(nat) call:
    -- national/engine numbering differs by the gap, so name(nat)
    -- names the wrong species (and poisoned the meta with it).
    buildIdMaps()
    local e = NAT_ENG[nat]
    if e ~= nil then
      local Pokemon = SP.require("src.core.game3.pokemon")
      if type(Pokemon) == "table"
          and type(Pokemon.name) == "function" then
        local okN, nm = pcall(Pokemon.name, e)
        if okN and type(nm) == "string" and nm ~= ""
            and nm ~= "??????????" then
          return ensureSpeciesDef(e, nat, titleCase(nm), true)
        end
      end
    end
    local exist = CD.BY_ID[id]
    if type(exist) == "table" then return exist end
    local meta = metaStore()[nat]
    if type(meta) == "table" and type(meta.name) == "string"
        and meta.name ~= "" and meta.name ~= "??????????" then
      return ensureSpeciesDef(tonumber(meta.base) or e, nat,
        meta.name, false)
    end
    return nil
  end

  function SP.speciesCandyUse(session, bag, def, item, slot)
    if type(session) ~= "table" then
      session = SP.session()
    end
    local party = type(session) == "table" and session.party or nil
    local idx = math.floor(tonumber(slot) or 0)
    local mon = type(party) == "table" and party[idx] or nil
    if type(mon) ~= "table" or mon.isEgg then
      return { false, "no_effect", "It won't have any effect." }
    end
    local wantNat = tonumber(def.baseNat)
    if wantNat == nil then
      return { false, "no_effect", "It won't have any effect." }
    end
    -- Name-anchored when possible (exact, numbering-proof);
    -- nicknamed targets fall back to the either-interp check.
    local _, targetNat = resolveMonLine(mon)
    local okLine = targetNat ~= nil and targetNat == wantNat
    if not okLine then
      okLine = lineNatMatches(speciesOfMon(mon), wantNat)
    end
    if not okLine then
      return { false, "no_effect", "It won't have any effect." }
    end
    local ivs = mon.ivs
    if type(ivs) ~= "table" then ivs = {} end
    local vals = {}
    local low = 31
    for _, key in ipairs(IV_KEYS) do
      local v = math.floor(tonumber(ivs[key]) or 0)
      if v < 0 then v = 0 end
      if v > 31 then v = 31 end
      vals[key] = v
      if v < low then low = v end
    end
    if low >= 31 then
      return { false, "no_effect", "It won't have any effect." }
    end
    local cost = 1
    if low >= 30 then cost = 10
    elseif low >= 21 then cost = 5
    elseif low >= 11 then cost = 3
    end
    local targetBag = bag or (type(session) == "table" and session.bag)
      or nil
    local Bag = SP.require("src.core.game3.bag")
    if type(Bag) ~= "table" or type(Bag.remove) ~= "function" then
      return { false, "no_effect", "It won't have any effect." }
    end
    local has = select(2, SP.try(Bag.has, targetBag, item, cost))
    if has ~= true then
      return { false, "no_effect", "It won't have any effect." }
    end
    local removed = select(2, SP.try(Bag.remove, targetBag, item, cost))
    if removed ~= true then
      return { false, "no_effect", "It won't have any effect." }
    end
    mon.ivs = mon.ivs or {}
    local raised = {}
    for _, key in ipairs(IV_KEYS) do
      if vals[key] == low then
        mon.ivs[key] = math.min(31, vals[key] + 1)
        raised[#raised + 1] = CD.STAT_LABEL[key] or key:upper()
      end
    end
    local Pokemon = SP.require("src.core.game3.pokemon")
    if type(Pokemon) == "table" then
      SP.try(Pokemon.applyStats, mon)
    end
    local monName = mon.name or "POKéMON"
    if type(Pokemon) == "table"
        and type(Pokemon.displayMonName) == "function" then
      local ok, nm = pcall(Pokemon.displayMonName, mon)
      if ok and type(nm) == "string" and nm ~= "" then monName = nm end
    end
    local label = table.concat(raised, ", ")
    return { true, "iv", tostring(monName) .. " gained +1 "
      .. tostring(label) .. (#raised > 1 and " IVs!" or " IV!") }
  end

  local function berryBump(qty)
    local q = math.max(0, math.floor(tonumber(qty) or 0))
    local m = 1
    if type(SP.berryCandyMult) == "function" then
      m = tonumber(SP.berryCandyMult()) or 1
    end
    if m > 1 then q = math.ceil(q * m) end
    if q < 1 and (tonumber(qty) or 0) > 0 then q = 1 end
    return q
  end
  local function snapCandyMult()
    local m = 1
    if type(SP.berryCandyMult) == "function" then
      m = tonumber(SP.berryCandyMult()) or 1
    end
    if not (m > 1) then m = 1 end
    return m
  end
  local Catching = SP.require("src.core.game3.battle.catching")
  if type(Catching) == "table"
      and type(Catching.storeCaught) == "function"
      and SP.claim(Catching, "__spStatCandyWrapped") then
    local nativeStore = Catching.storeCaught
    Catching.storeCaught = function(session, foe, ballId, opts, ...)
      local res = nativeStore(session, foe, ballId, opts, ...)
      pcall(function()
        if not (type(res) == "table" and res.success) then return end
        local st = liveState()
        if not ours(st) then return end
        local mon = res.mon
        if type(mon) ~= "table" then return end
        local species = mon.species or mon.speciesId
        if species == nil and type(foe) == "table" then
          species = foe.species or foe.speciesId
        end
        if species == nil then return end
        local lvl = tonumber(mon.level)
          or (type(foe) == "table" and tonumber(foe.level))
          or 1
        local statOn = SP.opt("stat_candy", true) ~= false
        local specOn = SP.opt("species_candy", true) ~= false
        local size = CD.sizeForLevel(lvl)
        local monE = engineIdOfMon(mon)
        local awards = {}
        local roll = rollSize()
        if statOn then
          awards = CD.statRewardsFor(size, yieldFor(monE or species))
          if roll.qty <= 0 then
            awards = {}
          elseif roll.qty > 1 then
            for _, r in ipairs(awards) do
              r.qty = (tonumber(r.qty) or 1) * roll.qty
            end
          end
          for _, r in ipairs(awards) do
            r.qty = berryBump(r.qty)
          end
        end
        local base, baseNat, lineName, verified = resolveMonLine(mon)
        if base == nil then
          base, baseNat, lineName, verified =
            resolveNumericLine(species, normName(trueSpeciesName(mon)))
        end
        if base ~= nil and baseNat ~= nil then
          local seen = seenStore()
          local repeatCatch = (res.firstTimeCaught == false)
            or seen[baseNat] == true
          if repeatCatch and roll.qty > 0 and specOn then
            pendingSpecies = { mon = mon, base = base, nat = baseNat,
              name = lineName, verified = verified, qty = roll.qty,
              cmult = snapCandyMult() }
          else
            pendingSpecies = nil
          end
          markSeen(baseNat)
        else
          pendingSpecies = nil
        end
        if not statOn then
          pendingStat = nil
          pendingStatLine = nil
        elseif #awards == 0 then
          pendingStat = {}
          pendingStatLine = roll.msg
        else
          local sess = type(session) == "table" and session or SP.session()
          if grantStat(sess, awards) then
            pendingStat = awards
            pendingStatLine = roll.msg
          end
        end
        if type(SP.berryKind) == "function"
            and SP.berryKind() ~= nil
            and type(SP.clearBerry) == "function" then
          SP.clearBerry()
        end
      end)
      return res
    end
  end

  function SP.takeSpeciesConvert(mon)
    if SP.opt("species_candy", true) == false then
      pendingSpecies = nil
      return nil
    end
    local p = pendingSpecies
    if type(p) ~= "table" then return nil end
    if mon ~= nil and p.mon ~= nil and mon ~= p.mon
        and lineNatMatches(speciesOfMon(mon), p.nat) ~= true then
      return nil
    end
    pendingSpecies = nil
    if rng(100) >= SPECIES_DROP_PCT then return nil end
    local sdef = ensureSpeciesDef(p.base, p.nat, p.name, p.verified)
    if sdef == nil then return nil end
    local m = tonumber(p.cmult) or 1
    local q = math.max(0, math.floor(tonumber(p.qty) or 0))
    if m > 1 then q = math.ceil(q * m) end
    if q < 1 and (tonumber(p.qty) or 0) > 0 then q = 1 end
    return { id = sdef.id, qty = q }
  end

  -- Overworld-catch candy award: the same stat roll + line/species
  -- resolution as the battle storeCaught wrap, but granted directly
  -- (no battle state exists, so that wrap's ours(st) check never
  -- fires). extra is an optional EXP-candy reward list for converted
  -- duplicates; species candy only drops when isConvert is true (kept
  -- mons never yield it, matching the battle pipeline). All rewards
  -- are canAdd-checked together first, so a full bag grants nothing.
  -- Returns { ok = true, text = ... } or { ok = false, reason = ... }.
  function SP.awardOverworldCandy(session, mon, lvl, firstTime, extra,
      isConvert)
    local sess = type(session) == "table" and session or SP.session()
    if type(sess) ~= "table" then
      return { ok = false, reason = "no_session" }
    end
    if type(mon) ~= "table" then
      return { ok = false, reason = "bad_mon" }
    end
    local species = mon.species or mon.speciesId
    if species == nil then
      return { ok = false, reason = "bad_mon" }
    end
    local level = math.max(1, math.min(100, math.floor(tonumber(lvl)
      or tonumber(mon.level) or 1)))
    local statOn = SP.opt("stat_candy", true) ~= false
    local specOn = SP.opt("species_candy", true) ~= false
    local size = CD.sizeForLevel(level)
    local monE = engineIdOfMon(mon)
    local roll = rollSize()
    local awards = {}
    if statOn then
      awards = CD.statRewardsFor(size, yieldFor(monE or species))
      if roll.qty <= 0 then
        awards = {}
      elseif roll.qty > 1 then
        for _, r in ipairs(awards) do
          r.qty = (tonumber(r.qty) or 1) * roll.qty
        end
      end
      for _, r in ipairs(awards) do
        r.qty = berryBump(r.qty)
      end
    end
    local speciesReward = nil
    local base, baseNat, lineName, verified = resolveMonLine(mon)
    if base == nil then
      base, baseNat, lineName, verified =
        resolveNumericLine(species, normName(trueSpeciesName(mon)))
    end
    if base ~= nil and baseNat ~= nil then
      local seen = seenStore()
      local repeatCatch = (firstTime == false) or seen[baseNat] == true
      if isConvert and repeatCatch and roll.qty > 0 and specOn then
        local sdef = ensureSpeciesDef(base, baseNat, lineName, verified)
        if sdef ~= nil then
          speciesReward = { id = sdef.id, qty = berryBump(roll.qty) }
        end
      end
      markSeen(baseNat)
    end
    local all = {}
    for _, r in ipairs(awards) do all[#all + 1] = r end
    if speciesReward ~= nil then all[#all + 1] = speciesReward end
    if type(extra) == "table" then
      for _, r in ipairs(extra) do
        if type(r) == "table" and tonumber(r.id) ~= nil then
          all[#all + 1] = { id = r.id,
            qty = math.max(1, math.floor(tonumber(r.qty) or 1)) }
        end
      end
    end
    if #all == 0 then
      if statOn then
        return { ok = true, text = roll.msg, texts = { roll.msg } }
      end
      return { ok = true, text = nil, texts = {} }
    end
    if not grantStat(sess, all) then
      return { ok = false, reason = "bag_full" }
    end
    local lines = { roll.msg }
    if type(CD.rewardLines) == "function" then
      local okL, v = pcall(CD.rewardLines, all)
      if okL and type(v) == "table" then
        for _, part in ipairs(v) do
          if type(part) == "string" and part ~= "" then
            lines[#lines + 1] = "Received " .. part .. "!"
          end
        end
      end
    end
    if #lines == 1 then
      lines[#lines + 1] = "Received " .. CD.rewardText(all) .. "!"
    end
    return { ok = true, text = table.concat(lines, " "), texts = lines }
  end

  function SP.consumeStatLine()    local rewards = pendingStat
    local line = pendingStatLine
    pendingStat, pendingStatLine = nil, nil
    if type(rewards) ~= "table" then rewards = {} end
    if #rewards == 0 then
      if type(line) == "string" and line ~= "" then return line end
      return nil
    end
    local got = "Received " .. CD.rewardText(rewards) .. "!"
    if type(line) == "string" and line ~= "" then
      return line .. " " .. got
    end
    return got
  end

  function SP.clearStatPending()
    pendingStat = nil
    pendingStatLine = nil
  end

  -- Stat-candy use: +4 EVs to one stat inside its size window (S
  -- below 100, L 100-200, XL 200-252), honoring the per-stat cap
  -- (252) and the total cap (510 classic, 1512 with the 1512 EVS
  -- toggle), then recalculates via applyStats.
  function SP.statCandyUse(session, bag, def, item, slot)
    if type(session) ~= "table" then
      session = SP.session()
    end
    local party = type(session) == "table" and session.party or nil
    local idx = math.floor(tonumber(slot) or 0)
    local mon = type(party) == "table" and party[idx] or nil
    if type(mon) ~= "table" or mon.isEgg then
      return { false, "no_effect", "It won't have any effect." }
    end
    local targetBag = bag or (type(session) == "table" and session.bag)
      or nil
    local Bag = SP.require("src.core.game3.bag")
    if type(Bag) ~= "table" or type(Bag.remove) ~= "function" then
      return { false, "no_effect", "It won't have any effect." }
    end
    local has = select(2, SP.try(Bag.has, targetBag, item, 1))
    if has ~= true then
      return { false, "no_effect", "It won't have any effect." }
    end
    local stat = def.evStat
    local win = type(def.size) == "string" and CD.STAT_WINDOW ~= nil
      and CD.STAT_WINDOW[def.size] or nil
    if stat == nil or type(win) ~= "table" then
      return { false, "no_effect", "It won't have any effect." }
    end
    local lo = math.floor(tonumber(win.lo) or 0)
    local hi = math.floor(tonumber(win.hi) or 0)
    local evs = mon.evs
    if type(evs) ~= "table" then evs = {} end
    local cur = math.floor(tonumber(evs[stat]) or 0)
    if cur < 0 then cur = 0 end
    if cur < lo or cur >= hi then
      return { false, "no_effect", "It won't have any effect." }
    end
    local total = 0
    for _, key in ipairs(ORDER) do
      total = total + math.max(0, math.floor(tonumber(evs[key]) or 0))
    end
    local perStat = evPerStat()
    local totalCap = evTotalCap()
    local give = math.min(4, hi - cur, perStat - cur, totalCap - total)
    if give <= 0 then
      return { false, "no_effect", "It won't have any effect." }
    end
    local removed = select(2, SP.try(Bag.remove, targetBag, item, 1))
    if removed ~= true then
      return { false, "no_effect", "It won't have any effect." }
    end
    mon.evs = mon.evs or {}
    mon.evs[stat] = cur + give
    local Pokemon = SP.require("src.core.game3.pokemon")
    if type(Pokemon) == "table" then
      SP.try(Pokemon.applyStats, mon)
    end
    local monName = mon.name or "POKéMON"
    if type(Pokemon) == "table"
        and type(Pokemon.displayMonName) == "function" then
      local ok, nm = pcall(Pokemon.displayMonName, mon)
      if ok and type(nm) == "string" and nm ~= "" then monName = nm end
    end
    local label = CD.STAT_LABEL[stat] or stat:upper()
    return { true, "ev", tostring(monName) .. " gained +"
      .. tostring(give) .. " " .. tostring(label) .. " EVs!" }
  end

  -- Stripped gray base sprites, one per size; tinted per stat at draw.
  local artData = nil
  local baseCache = {}
  local function art()
    if artData ~= nil then return artData end
    local ok, body = pcall(mod.read, mod, "battle/stat_candy_art.lua")
    if not ok or type(body) ~= "string" then
      if not artWarned then
        artWarned = true
        mod.log:warn("safari-plus: stat candy art unreadable")
      end
      return nil
    end
    local chunk, err = loadstring(body, "@stat_candy_art")
    if not chunk then
      if not artWarned then
        artWarned = true
        mod.log:warn("safari-plus: stat candy art error: %s", tostring(err))
      end
      return nil
    end
    local okC, data = pcall(chunk)
    if okC and type(data) == "table" then artData = data end
    return artData
  end

  local HEXV = { 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15,
    ["0"] = 0, ["1"] = 1, ["2"] = 2, ["3"] = 3, ["4"] = 4, ["5"] = 5,
    ["6"] = 6, ["7"] = 7, ["8"] = 8, ["9"] = 9, ["a"] = 10, ["b"] = 11,
    ["c"] = 12, ["d"] = 13, ["e"] = 14, ["f"] = 15,
    ["A"] = 10, ["B"] = 11, ["C"] = 12, ["D"] = 13, ["E"] = 14,
    ["F"] = 15 }

  local function buildBase(key)
    local img = nil
    pcall(function()
      local data = art()
      local entry = type(data) == "table" and data[key] or nil
      if type(entry) ~= "table" then return end
      local lv = love
      if type(lv) ~= "table" or type(lv.image) ~= "table"
          or type(lv.graphics) ~= "table" then
        return
      end
      local w, h = entry.w or 24, entry.h or 24
      local imgData = lv.image.newImageData(w, h)
      if imgData == nil then return end
      for y = 1, h do
        local row = entry.rows and entry.rows[y] or ""
        for x = 1, w do
          local ch = row:sub(x, x)
          local q = HEXV[ch] or 0
          if q == 0 then
            imgData:setPixel(x - 1, y - 1, 0, 0, 0, 0)
          else
            local g = (tonumber(entry.pal[q]) or 255) / 255
            imgData:setPixel(x - 1, y - 1, g, g, g, 1)
          end
        end
      end
      img = lv.graphics.newImage(imgData)
      if img and img.setFilter then img:setFilter("nearest", "nearest") end
    end)
    return img
  end

  function SP.statCandyImage(size)
    if baseCache[size] ~= nil then return baseCache[size] or nil end
    local img = buildBase(size)
    baseCache[size] = img or false
    return img
  end

  function SP.speciesCandyImage()
    if baseCache.SPC ~= nil then return baseCache.SPC or nil end
    local img = buildBase("SPC")
    baseCache.SPC = img or false
    return img
  end

  function SP.pouchImage()
    if baseCache.POUCH ~= nil then return baseCache.POUCH or nil end
    local img = buildBase("POUCH")
    baseCache.POUCH = img or false
    return img
  end

  function SP.isStatBaseImage(img)
    for _, v in pairs(baseCache) do
      if v ~= false and v ~= nil and img == v then return true end
    end
    return false
  end

  seedFromMastery()
  if mod.events and type(mod.events.on) == "function" then
    mod.events:on("battle.started", function()
      pendingStat = nil
      pendingStatLine = nil
      pendingSpecies = nil
    end)
    mod.events:on("battle.ended", function()
      pendingStat = nil
      pendingStatLine = nil
      pendingSpecies = nil
    end)
    mod.events:on("save.loaded", function()
      pcall(seedFromMastery)
    end)
    mod.events:on("save.writing", function()
      pcall(function()
        if speciesSeen ~= nil then SP.saveSet("speciesDex", speciesSeen) end
        SP.saveSet("speciesCandyMeta", metaStore())
      end)
    end)
  end
  mod.log:info("safari-plus: stat candy installed")
end
