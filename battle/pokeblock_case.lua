return function(mod)
  local SP = mod.exports.safariPlus
  if not SP then return end
  -- POKéBLOCK CASE gate on flag 0x5F: without the case the battle shows
  -- the no-case line and returns to the menu; with it the case screen
  -- gets input pumped every frame (the engine never forwards input to
  -- it) and a lost close callback is recovered.
  local function battleState()
    local B = SP.require("src.core.game3.battle")
    if type(B) == "table" and type(B.getState) == "function" then
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
  local CASE_FLAG = 0x5F
  local function hasCase(session)
    if type(session) ~= "table" then return true end
    local f = session.flags
    if type(f) == "table" and f[CASE_FLAG] == true then
      return true
    end
    local Space = package.loaded["src.core.game3.scripting.space"]
    if Space and Space.store then
      local Flags = SP.require("src.core.game3.scripting.flags")
      if type(Flags) == "table" and type(Flags.getFlag) == "function" then
        local okG, v = pcall(Flags.getFlag, Space.store, nil, CASE_FLAG)
        if okG and v then
          return true
        end
      end
    end
    return false
  end

  local function wrapRse()
    local Rse = SP.require("src.core.game3.rse.init")
    if type(Rse) ~= "table" or type(Rse.call) ~= "function" then return false end
    if not SP.claim(Rse, "__spCaseWrapped") then return true end
    local native = Rse.call
    Rse.call = function(domain, name, ...)
      if SP.on() and domain == "pokeblock" and name == "chooseForBattle" then
        local st = battleState()
        if st and st.safari and not st.over then
          local session, cb = argSessionCb(...)
          if not hasCase(session) then
            local Ui = SP.require("src.core.game3.battle.ui")
            local pushed = false
            if Ui and type(Ui.push) == "function" then
              pushed = SP.try(Ui.push, "You don't have the POKéBLOCK CASE yet.",
                function()
                  if type(cb) == "function" then pcall(cb, nil) end
                end)
            end
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
    local Case = SP.require("src.ui.game3.rse.pokeblock_case")
    if type(Case) == "table" then return Case end
    return nil
  end
  local caseErrLogged = false
  local sawCase = false
  local function noteErr(where, err)
    if caseErrLogged then return end
    caseErrLogged = true
    mod.log:warn("safari-plus: pokeblock case %s: %s", where, tostring(err))
    print("[safari-plus] pokeblock case " .. tostring(where)
      .. ": " .. tostring(err))
  end
  local function pumpCase(B, game)
    if not SP.on() then return end
    if B._phase ~= "safari_pokeblock" then
      sawCase = false
      return
    end
    local Case = caseModule()
    local open = Case and type(Case.isOpen) == "function"
      and Case.isOpen() or false
    if open then
      sawCase = true
      local input = game and game.input
      if input ~= nil then
        if type(Case.handleInput) == "function" then
          Case.handleInput(input)
        end
        if type(Case.update) == "function" then Case.update() end
      end
      return
    end
    if not sawCase then return end
    sawCase = false
    local st = battleState()
    if st and not st.over then
      B._phase = "command"
      local Ui = SP.require("src.core.game3.battle.ui")
      if type(Ui) == "table" and type(Ui.openMenu) == "function" then
        Ui.openMenu()
      end
    end
  end
  local function wrapBattle()
    local B = SP.require("src.core.game3.battle")
    if type(B) ~= "table" or type(B.update) ~= "function" then return false end
    if not SP.claim(B, "__spCaseInputWrapped") then return true end
    local native = B.update
    B.update = function(dt, game, ...)
      local r = native(dt, game, ...)
      local ok, err = pcall(pumpCase, B, game)
      if not ok then noteErr("pump", err) end
      return r
    end
    return true
  end
  wrapRse()
  wrapBattle()
  if mod.events and type(mod.events.on) == "function" then
    mod.events:on("battle.started", function()
      caseErrLogged = false
      sawCase = false
      wrapRse()
      wrapBattle()
    end)
    mod.events:on("battle.ended", function()
      sawCase = false
    end)
  end
  mod.log:info("safari-plus: pokeblock case gated on flag 0x5F")
end
