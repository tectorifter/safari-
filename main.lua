return function(mod)
  local function loadSibling(file)
    local body, readErr = mod:read(file)
    assert(body, readErr)
    local chunk, err = loadstring(body, "@" .. mod.path .. "/" .. file)
    assert(chunk, err)
    return chunk()
  end
  local function boot(label, fn)
    local ok, err = pcall(fn)
    if not ok then
      mod.log:warn("safari-plus: %s failed: %s", label, tostring(err))
    end
    return ok
  end
  mod.options:define({
    {
      key = "safari",
      label = "SAFARI",
      type = "toggle",
      default = true,
      description = "ON: wild and fated encounters use the native Safari scene with a deep ball stock and wall-clock regen. OFF: vanilla battles.",
    },
    {
      key = "exp_yield",
      label = "EXP YIELD",
      type = "choice",
      default = "50",
      choices = { { "0%", "0" }, { "10%", "10" }, { "25%", "25" }, { "50%", "50" }, { "75%", "75" }, { "100%", "100" }, { "150%", "150" }, { "200%", "200" }, { "300%", "300" }, { "400%", "400" }, { "500%", "500" } },
      description = "Scales the EXP a safari catch pays, relative to what the caught species would yield if defeated: 50% default. 0% pays nothing.",
    },
  })
  boot("shared", function() loadSibling("shared.lua")(mod) end)
  boot("safari_force", function() loadSibling("battle/safari_force.lua")(mod) end)
  boot("factors", function() loadSibling("battle/factors.lua")(mod) end)
  boot("ball_guard", function() loadSibling("battle/ball_guard.lua")(mod) end)
  boot("catch_exp", function() loadSibling("battle/catch_exp.lua")(mod) end)
  boot("duplicate_candy", function() loadSibling("battle/duplicate_candy.lua")(mod) end)
  boot("no_balls_run", function() loadSibling("battle/no_balls_run.lua")(mod) end)
  boot("pokeblock_case", function() loadSibling("battle/pokeblock_case.lua")(mod) end)
  boot("shop", function() loadSibling("overworld/shop.lua")(mod) end)
  boot("bag_balls", function() loadSibling("overworld/bag_balls.lua")(mod) end)
  boot("entrance", function() loadSibling("overworld/entrance.lua")(mod) end)
  mod.log:info("safari-plus: loaded (emerald safari overhaul)")
end
