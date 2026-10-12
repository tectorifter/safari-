return function(mod)
  local SP = mod.exports.safariPlus
  if not SP then return end
  -- Ball throw and catch animations run ~3x faster in safari scenes
  -- (native animation kept, throw arc stays visible).
  local SUBSTEPS = 3
  local function speedupOn()
    if not SP.on() then return false end
    return SP.opt("speedup", true) == true
  end
  local function throwActive()
    local CS = SP.require("src.core.game3.battle.catch_seq")
    if type(CS) ~= "table" or type(CS._steps) ~= "table" then return false end
    local step = CS._steps[tonumber(CS._i) or 0]
    local kind = step and step.kind
    return kind == "throw" or kind == "breakout"
  end
  local BallOpen = SP.require("src.core.game3.battle.ball_open")
  if type(BallOpen) ~= "table" or type(BallOpen.tick) ~= "function" then return end
  if not SP.claim(BallOpen, "__spSpeedWrapped") then return end
  local nativeTick = BallOpen.tick
  BallOpen.tick = function(...)
    local n = 1
    if speedupOn() then
      if throwActive() then n = SUBSTEPS end
    end
    for i = 1, n do nativeTick(...) end
  end
  mod.log:info("safari-plus: catch speedup installed")
end
