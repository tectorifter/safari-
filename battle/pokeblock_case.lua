return function(mod)
  local SP = mod.exports.safariPlus
  if not SP then return end
  local function battleState()
    local okB, B = pcall(require, "src.core.game3.battle")
    if okB and B and type(B.getState) == "function" then
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
    local flagged = false
    pcall(function()
      local f = session.flags
      if type(f) == "table" and f[CASE_FLAG] == true then
        flagged = true
        return
      end
      local Space = package.loaded["src.core.game3.scripting.space"]
      if Space and Space.store then
        local okF, Flags = pcall(require, "src.core.game3.scripting.flags")
        if okF and Flags and type(Flags.getFlag) == "function" then
          if Flags.getFlag(Space.store, nil, CASE_FLAG) then
            flagged = true
          end
        end
      end
    end)
    return flagged
  end

  local function wrapRse()
    local okR, Rse = pcall(require, "src.core.game3.rse.init")
    if not (okR and Rse and type(Rse.call) == "function") then return false end
    if Rse.__spCaseWrapped then return true end
    Rse.__spCaseWrapped = true
    local native = Rse.call
    Rse.call = function(domain, name, ...)
      if SP.on() and domain == "pokeblock" and name == "chooseForBattle" then
        local st = battleState()
        if st and st.safari and not st.over then
          local session, cb = argSessionCb(...)
          if not hasCase(session) then
            local pushed = false
            pcall(function()
              local Ui = require("src.core.game3.battle.ui")
              if Ui and type(Ui.push) == "function" then
                Ui.push("You don't have the POKéBLOCK CASE yet.",
                  function()
                    if type(cb) == "function" then pcall(cb, nil) end
                  end)
                pushed = true
              end
            end)
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
    local okC, Case = pcall(require, "src.ui.game3.rse.pokeblock_case")
    if okC and type(Case) == "table" then return Case end
    return nil
  end
  local caseErrLogged = false
  local sawCase = false
  local function noteErr(where, err)
    if caseErrLogged then return end
    caseErrLogged = true
    pcall(function()
      mod.log:warn("safari-plus: pokeblock case %s: %s", where, tostring(err))
    end)
    pcall(print, "[safari-plus] pokeblock case " .. tostring(where)
      .. ": " .. tostring(err))
  end
  local function wrapBattle()
    local okB, B = pcall(require, "src.core.game3.battle")
    if not (okB and B and type(B.update) == "function") then return false end
    if B.__spCaseInputWrapped then return true end
    B.__spCaseInputWrapped = true
    local native = B.update
    B.update = function(dt, game, ...)
      local r = native(dt, game, ...)
      local ok, err = pcall(function()
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
          local okU, Ui = pcall(require, "src.core.game3.battle.ui")
          if okU and Ui and type(Ui.openMenu) == "function" then
            Ui.openMenu()
          end
        end
      end)
      if not ok then noteErr("pump", err) end
      return r
    end
    return true
  end
  wrapRse()
  pcall(wrapBattle)
  if mod.events and type(mod.events.on) == "function" then
    mod.events:on("battle.started", function()
      caseErrLogged = false
      sawCase = false
      pcall(wrapRse)
      pcall(wrapBattle)
    end)
  end
  mod.log:info("safari-plus: pokeblock case gated on flag 0x5F")
end
