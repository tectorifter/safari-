return {
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
  {
    key = "speedup",
    label = "SPEED UP",
    type = "toggle",
    default = true,
    description = "ON: ball throw and catch animations run about 3x faster (a full catch lands in roughly 2s, throw arc stays visible). OFF: vanilla animation timing.",
  },
  {
    key = "mastery",
    label = "MASTERY",
    type = "toggle",
    default = true,
    description = "ON: every catch raises that species' mastery (kept across sessions); wild encounters of mastered species gain guaranteed plus bonus 31 IVs, up to 3 guaranteed and 3 bonus at 300 catches. OFF: no tracking, vanilla IVs.",
  },
  {
    key = "iv_guard",
    label = "IV GUARD",
    type = "choice",
    default = "3",
    choices = { { "1", "1" }, { "2", "2" }, { "3", "3" }, { "4", "4" }, { "5", "5" }, { "6", "6" } },
    description = "Duplicate catches with at least this many perfect (31) IV stats ask to keep first; anything below goes straight to the EXP CANDY question. Counts stats, never totals.",
  },
}
