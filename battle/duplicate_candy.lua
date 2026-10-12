return function(mod)
  local SP = mod.exports.safariPlus
  if not SP then return end
  local CI = SP.candyIcons
  local DG = assert(SP.candyDialog)
  local FL = assert(SP.candyFlow)
  local wrapsDone = false
  local wrapFails = {}
  local wrapLogged = {}
  local function attempt(name, fn)
    local fails = tonumber(wrapFails[name]) or 0
    if fails >= 2 then return false end
    local ok = false
    pcall(function() ok = fn() == true end)
    if ok then
      wrapFails[name] = 0
      return true
    end
    wrapFails[name] = fails + 1
    if not wrapLogged[name] then
      wrapLogged[name] = true
      mod.log:warn("safari-plus: candy wrap %s unavailable", tostring(name))
    end
    return false
  end
  local function attemptOpt(name, fn)
    if type(fn) ~= "function" then return false end
    return attempt(name, fn)
  end
  local ensureWraps
  ensureWraps = function()
    if wrapsDone then return true end
    local ok = attempt("info", function() return DG.wrapInfo(ensureWraps) end)
    ok = attemptOpt("icons", CI and CI.wrapIcons) and ok
    ok = attemptOpt("draw", CI and CI.wrapDraw) and ok
    ok = attemptOpt("rsedraw", CI and CI.wrapRseDraw) and ok
    ok = attempt("use", function() return FL.wrapUse(ensureWraps) end) and ok
    ok = attempt("ask", function() return DG.wrapUi(FL.convertRes, ensureWraps) end) and ok
    ok = attempt("target", FL.wrapTarget) and ok
    ok = attempt("partymsg", FL.wrapPartyMsg) and ok
    wrapsDone = ok
    return wrapsDone
  end
  ensureWraps()
  if mod.events and type(mod.events.on) == "function" then
    mod.events:on("battle.started", function()
      FL.reset()
      wrapsDone = false
      wrapFails = {}
      ensureWraps()
    end)
    mod.events:on("battle.ended", function()
      FL.reset()
    end)
    mod.events:on("map.entered", function()
      FL.reset()
    end)
  end
  mod.log:info("safari-plus: duplicate catch candy exchange installed")
end
