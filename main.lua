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
  local skills = loadSibling("data/skills.lua")
  assert(type(skills) == "table", "safari-plus: data/skills.lua must return a table")
  mod.exports.spSkillData = skills
  local options = loadSibling("data/options.lua")
  assert(type(options) == "table", "safari-plus: data/options.lua must return a table")
  mod.options:define(options)
  boot("shared", function() loadSibling("shared.lua")(mod) end)
  local SP = mod.exports.safariPlus
  assert(SP, "safari-plus: shared failed")
  local candy = loadSibling("battle/candy_data.lua")
  assert(type(candy) == "table", "safari-plus: battle/candy_data.lua must return a table")
  SP.candyData = candy
  boot("safari_force", function() loadSibling("battle/safari_force.lua")(mod) end)
  boot("factors", function() loadSibling("battle/factors.lua")(mod) end)
  boot("ball_guard", function() loadSibling("battle/ball_guard.lua")(mod) end)
  boot("catch_exp", function() loadSibling("battle/catch_exp.lua")(mod) end)
  boot("candy_icons", function() loadSibling("battle/candy_icons.lua")(mod) end)
  boot("candy_flow", function() loadSibling("battle/candy_flow.lua")(mod) end)
  boot("candy_dialog", function() loadSibling("battle/candy_dialog.lua")(mod) end)
  boot("duplicate_candy", function() loadSibling("battle/duplicate_candy.lua")(mod) end)
  boot("iv_guard", function() loadSibling("battle/iv_guard.lua")(mod) end)
  boot("no_balls_run", function() loadSibling("battle/no_balls_run.lua")(mod) end)
  boot("pokeblock_case", function() loadSibling("battle/pokeblock_case.lua")(mod) end)
  boot("catch_speed", function() loadSibling("battle/catch_speed.lua")(mod) end)
  boot("mastery", function() loadSibling("battle/mastery.lua")(mod) end)
  boot("safari_xp", function() loadSibling("battle/safari_xp.lua")(mod) end)
  boot("bag_balls", function() loadSibling("overworld/bag_balls.lua")(mod) end)
  boot("safari_menu", function() loadSibling("overworld/safari_menu.lua")(mod) end)
  boot("entrance", function() loadSibling("overworld/entrance.lua")(mod) end)
  mod.log:info("safari-plus: loaded (emerald safari overhaul)")
end
