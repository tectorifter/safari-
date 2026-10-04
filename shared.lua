return function(mod)
  local M = {}
  M.BALL_START = 10
  M.BALL_HARD = 70
  M.BALL_STEP = 2
  M.UPG = {
    catch = { id = 9001, name = "SAFARI UPG", max = 60 },
    like = { id = 9002, name = "LIKEABLE", max = 30 },
    regen = { id = 9003, name = "BALL RECOVERY", max = 70 },
    cap = { id = 9004, name = "BALL CAP", max = 30 },
  }
  M.UPG_BY_ID = { [9001] = "catch", [9002] = "like", [9003] = "regen", [9004] = "cap" }
  M.ORDER = { "catch", "like", "regen", "cap" }
  function M.on()
    local ok, v = pcall(function() return mod.options:get("safari") end)
    if not ok or v == nil then return true end
    return v == true
  end
  function M.session()
    local okR, R = pcall(require, "src.core.game3.runtime")
    if okR and R and type(R.getSession) == "function" then
      local okS, s = pcall(R.getSession)
      if okS and type(s) == "table" then return s end
    end
    return nil
  end
  local function saveGet(k, d)
    local v = d
    pcall(function()
      local sv = mod.save
      if sv and type(sv.get) == "function" then v = sv:get(k, d) end
    end)
    return v
  end
  local function saveSet(k, v)
    pcall(function()
      local sv = mod.save
      if sv and type(sv.set) == "function" then sv:set(k, v) end
    end)
  end
  local function cleanNum(v, lo, hi, dflt)
    local n = tonumber(v)
    if n == nil or n ~= n or n == math.huge or n == -math.huge then
      return dflt
    end
    n = math.floor(n)
    if n < lo then return lo end
    if n > hi then return hi end
    return n
  end
  function M.maxOf(key)
    local d = M.UPG[key]
    return d and d.max or 0
  end
  function M.now()
    local t = nil
    pcall(function()
      local lv = love
      if type(lv) == "table" and type(lv.timer) == "table"
          and type(lv.timer.getTime) == "function" then
        t = lv.timer.getTime()
      end
    end)
    t = tonumber(t)
    if t ~= nil then return t end
    return os.time()
  end
  function M.scrubState(u, balls, regenAt)
    local c = {}
    for _, key in ipairs(M.ORDER) do
      c[key] = cleanNum(type(u) == "table" and u[key], 0, M.maxOf(key), 0)
    end
    local cap = math.min(M.BALL_HARD, M.BALL_START + M.BALL_STEP * (c.cap or 0))
    local now = M.now()
    local ra = tonumber(regenAt)
    if ra == nil or ra ~= ra or ra == math.huge or ra == -math.huge then
      ra = now
    end
    if ra < 0 or ra > now + 120 then ra = now end
    return c, cleanNum(balls, 0, cap, M.BALL_START), ra
  end
  function M.cap()
    return math.min(M.BALL_HARD, M.BALL_START + M.BALL_STEP * M.count("cap"))
  end
  function M.yieldPct()
    local v = nil
    pcall(function()
      if mod.options and type(mod.options.get) == "function" then
        v = mod.options:get("exp_yield")
      end
    end)
    local n = tonumber(v)
    if n == nil then return 50 end
    n = math.floor(n)
    if n < 0 then return 0 end
    if n > 500 then return 500 end
    return n
  end
  function M.persist()
    local s = M.session()
    local u = s and s.safariUpg
    local b = s and s.safari and s.safari.balls
    local c, cb, cra = M.scrubState(u, b, s and s.safariRegenAt)
    if s then
      s.safariUpg = c
      s.safari = type(s.safari) == "table" and s.safari or {}
      s.safari.balls = cb
      s.safariRegenAt = cra
    end
    saveSet("upg", c)
    saveSet("balls", cb)
    saveSet("regenAt", cra)
  end
  function M.pull()
    local s = M.session()
    local gu = saveGet("upg", nil)
    local gb = saveGet("balls", nil)
    local gra = saveGet("regenAt", nil)
    local c, cb, cra
    if gu ~= nil or gb ~= nil or gra ~= nil then
      c, cb, cra = M.scrubState(gu, gb, gra)
    else
      c, cb, cra = M.scrubState(s and s.safariUpg,
        s and s.safari and s.safari.balls, s and s.safariRegenAt)
    end
    if s then
      s.safariUpg = c
      s.safari = type(s.safari) == "table" and s.safari or {}
      s.safari.balls = cb
      s.safariRegenAt = cra
    end
    saveSet("upg", c)
    saveSet("balls", cb)
    saveSet("regenAt", cra)
  end
  function M.store()
    local s = M.session()
    if not s then return nil end
    local u = s.safariUpg
    if type(u) ~= "table" then u = {} s.safariUpg = u end
    return u
  end
  function M.count(key)
    local s = M.session()
    local u = s and s.safariUpg
    return cleanNum(type(u) == "table" and u[key], 0, M.maxOf(key), 0)
  end
  function M.price(key)
    return 50 + 50 * M.count(key)
  end
  function M.addLevels(key, n)
    local s = M.session()
    local cur = M.count(key)
    local room = M.maxOf(key) - cur
    local k = cleanNum(n, 0, math.max(0, room), 0)
    if k > 0 then
      local u = M.store()
      if u then u[key] = cur + k end
    end
    M.persist()
    return k
  end
  function M.isUpgId(id)
    return M.UPG_BY_ID[tonumber(id)] ~= nil
  end
  function M.keyOf(id)
    return M.UPG_BY_ID[tonumber(id)]
  end
  function M.regenInterval()
    return math.max(5, 12 - 0.1 * M.count("regen"))
  end
  function M.catchBonus()
    return 0.35 * M.count("catch")
  end
  function M.likeCut()
    return 0.1 * M.count("like")
  end
  function M.likeValue()
    return math.min(4, 1 + 0.1 * M.count("like"))
  end
  function M.desc(key)
    local c = M.count(key)
    if key == "catch" then
      return "Catch +" .. string.format("%.1f", 0.35 * c) .. " Lv" .. c .. "/60\nNext " .. M.price(key)
    elseif key == "like" then
      return "Like x" .. string.format("%.1f", M.likeValue()) .. " Lv" .. c .. "/30\nNext " .. M.price(key)
    elseif key == "regen" then
      return "Ball/" .. string.format("%.1f", M.regenInterval()) .. "s Lv" .. c .. "/70\nNext " .. M.price(key)
    elseif key == "cap" then
      return "Cap " .. M.cap() .. "/70 Lv" .. c .. "/30\nNext " .. M.price(key)
    end
    return ""
  end
  function M.refreshMeta(key)
    local d = M.UPG[key]
    if not d then return end
    local okI, ItemsData = pcall(require, "src.core.game3.items_data")
    if not (okI and ItemsData) then return end
    pcall(function()
      if ItemsData.ensureLoaded then ItemsData.ensureLoaded() end
    end)
    local byId = ItemsData._byId
    if type(byId) ~= "table" then return end
    byId[d.id] = {
      name = d.name,
      price = M.price(key),
      description = M.desc(key),
      pocket = "ITEMS",
    }
  end
  function M.ensureStock()
    local s = M.session()
    if not s then return end
    s.safari = type(s.safari) == "table" and s.safari or {}
    if tonumber(s.safari.balls) == nil then s.safari.balls = M.BALL_START end
    M.persist()
  end
  function M.stock()
    local s = M.session()
    if not s then return M.BALL_START end
    local b = s.safari and s.safari.balls
    return cleanNum(b, 0, M.cap(), M.BALL_START)
  end
  function M.setStock(n)
    local s = M.session()
    local v = cleanNum(n, 0, M.cap(), 0)
    if s then
      s.safari = type(s.safari) == "table" and s.safari or {}
      s.safari.balls = v
    end
    M.persist()
    return v
  end
  function M.inBattle()
    local okB, B = pcall(require, "src.core.game3.battle")
    if okB and B and type(B.isActive) == "function" then
      local ok, active = pcall(B.isActive)
      if ok and active then return true end
    end
    return false
  end
  function M.freeze()
    local s = M.session()
    if not s then return end
    if s.safariFrozenAt == nil then s.safariFrozenAt = M.now() end
  end
  function M.thaw()
    local s = M.session()
    if not s then return end
    local f = tonumber(s.safariFrozenAt)
    s.safariFrozenAt = nil
    if not f then return end
    local now = M.now()
    local last = tonumber(s.safariRegenAt)
    if last == nil then
      s.safariRegenAt = now
      M.persist()
      return
    end
    s.safariRegenAt = math.min(now, last + math.max(0, now - f))
    M.persist()
  end
  function M.tick()
    if M.inBattle() then return end
    local s = M.session()
    if not s then return end
    s.safari = type(s.safari) == "table" and s.safari or {}
    local now = M.now()
    local cap = M.cap()
    if cleanNum(s.safari.balls, 0, cap, 0) >= cap then
      s.safariRegenAt = now
      M.persist()
      return
    end
    local last = tonumber(s.safariRegenAt) or now
    if now <= last then
      s.safariRegenAt = now
      M.persist()
      return
    end
    local grants = math.floor((now - last) / M.regenInterval())
    if grants > 0 then
      grants = math.min(grants, cap)
      s.safari.balls = math.min(cap,
        cleanNum(s.safari.balls, 0, cap, 0) + grants)
      s.safariRegenAt = last + grants * M.regenInterval()
      M.persist()
    end
  end
  M.pull()
  if mod.events and type(mod.events.on) == "function" then
    mod.events:on("save.loaded", function()
      pcall(M.pull)
    end)
    mod.events:on("save.writing", function()
      pcall(M.persist)
    end)
  end
  if mod.migrations and type(mod.migrations.add) == "function" then
    pcall(function()
      mod.migrations:add("0.5.0", function(save)
        local id = mod.id or "safari-plus"
        local md = type(save) == "table" and save.modData
        local b = md and md[id]
        if type(b) ~= "table" then return end
        local c, cb, cra = M.scrubState(b.upg, b.balls, b.regenAt)
        b.upg, b.balls, b.regenAt = c, cb, cra
      end)
    end)
  end
  mod.exports.safariPlus = M
end
