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
}
