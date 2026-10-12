# safari-plus seams

Every engine function the mod wraps, and every hook/event it subscribes
to. Guard flags are idempotence keys: a second boot (or a late module
load) re-runs the installer but never double-wraps. Unless noted, the
wrapper calls through to native when the mod is OFF, the battle/state
isn't ours, or the arguments aren't ours.

## Battle start (`battle/safari_force.lua`)

- `battle_bridge.start` (`Bridge.__spSafariWrapped`): wild, non-link,
  non-tutorial, non-trainer encounters run on a COPY of opts with
  `safari = true`. The caller's table is never mutated. Ticks regen
  and ensures stock before starting. The copy's `done`, when present,
  is wrapped so safari-only outcomes read as wins to encounter-chain
  listeners (`SP.chainResult`: catch/caught always, `run` only when
  the live battle state's `endReason` is `enemy_fled`; player-run,
  out-of-balls and everything else pass through untouched).
- `battle.started` event: regen tick, then freeze the regen clock.
- `battle.ended` event: thaw the regen clock, write remaining
  `safariState.balls` back to the session stock, persist.
- Zone stepping (`src.core.game3.safari.takeStep`) is left fully
  native: the mod never wraps or gates it. Regen is wall-clock math
  resolved lazily at read points (bag access, shop, battle start),
  never per step.

## Catch/escape factors (`battle/factors.lua`)

- `rules.safari.newStateRse` / `newState` (`RS.__spRseWrapped` /
  `RS.__spNewWrapped`): battle ball count comes from the live session
  stock.
- `rules.safari.ballCatchRate` (`RS.__spRateWrapped`): +0.35 per
  SAFARI UPG level. The native formula itself is untouched.
- `rules.safari.fleeRate` (`RS.__spFleeWrapped`): per-species flee from
  BST as `((BST/100)/likeability)*5`, likeability =
  `min(4, 1 + 0.1 per LIKEABLE level)`; old escape-factor math when the
  BST is unavailable.

## Zero balls (`battle/ball_guard.lua`, `battle/no_balls_run.lua`)

- `catching.tryCatch` (`Catching.__spBallGuardWrapped`): safari throw
  with no balls left fails without rolling.
- `battle.safariSyncBalls` (`B.__spBallGuardSyncWrapped`): after the
  engine syncs each throw, the live stock is forced to the battle
  counter.
- `battle.ui.openMenu` (`Ui.__spZeroMenuWrapped`), `takeCommand`
  (`Ui.__spZeroTakeWrapped`), `battle.update`
  (`B.__spZeroUpdateWrapped`): zero balls in the command phase ends the
  battle via the out-of-balls text. All retry on `battle.started`.
- `battle_text.get` (`BT.__spRunWrapped`):
  `STRINGID_OUTOFSAFARIBALLS` renders as the run-away string with the
  flee sound, once per battle.
- `safari.endBattleRse` (`Safari.__spRunWrapped`): our safari battles
  return false before the out-of-balls script and the entrance warp.
- `safari.outOfBallsMidBattle` (`Safari.__spMidWrapped`): skipped once
  the no-balls text converted in the current battle. The converted flag
  clears on `battle.ended` too, so no battle state is retained overworld.

## Catch EXP (`battle/catch_exp.lua`)

- `catching.storeCaught` (`Catching.__spCatchExpWrapped`): on a safari
  catch, runs the engine's own `experience.awardFoe` over every alive
  sub-100 non-egg party mon, then queues the custom EXP line.
- `exp.gain` hook: inside our safari battles the per-mon award is
  scaled by EXP YIELD (default 50%); the scaled amounts are summed so
  the announced line reports what was actually distributed (no line at
  0%). Other battles pass through.
- `battle.ui.push` (`Ui.__spCatchExpWrapped`): delivers the queued line
  after the Gotcha message.
- `battle.started` event: resets the per-battle payment/accumulator
  state. `battle.ended` clears it too, so a dead battle never retains
  its state, learn/evolution queues, or parked phase into the overworld.
  Queues abort if the battle is already inactive, and the parked phase
  is restored even when no EXP line is due.

## Duplicate candy (`battle/candy_data.lua`, `battle/candy_icons.lua`, `battle/candy_flow.lua`, `battle/candy_dialog.lua`, `battle/duplicate_candy.lua`)

- `battle.ui.askYesNo` (`Ui.__spCandyAskWrapped`, in candy_dialog):
  a duplicate catch at
  the nickname prompt first offers the EXP CANDY exchange. Yes removes
  the mon (party slot or deferred PC deposit) and grants candy via the
  stock `catch_pc_msg` pump; No (or a full bag) falls back to the stock
  nickname prompt. Tutorials, headless, and first-time catches pass
  through. Retries on `battle.started`.
- `items_data.info` (`ItemsData.__spCandyInfoWrapped`, in candy_dialog):
  ids 9101-9105
  report as EXP CANDY XS/S/M/L/XL (ITEMS pocket). Lazily re-runs
  `ensureWraps` until every wrap below sticks; each installer gets two
  attempts per battle before it stops retrying (first failure logged
  once), so a permanently missing module costs nothing per bag row.
  The pending candy-learn slot clears on `battle.started`,
  `battle.ended`, and `map.entered`.
- `bag_chrome.iconImage` (`BC.__spCandyIconWrapped`) and `drawItemIcon`
  (`BC.__spCandyTintWrapped`): candy ids render the Rare Candy icon
  (68), tinted per tier, or a generated glyph when 68 has no art. Same
  for the RSE chrome (`src.ui.game3.rse.bag_chrome`, atlas-indexed;
  image+quad cached).
- `item_use.useField` (`ItemUse.__spCandyUseWrapped`, in candy_flow):
  candy use applies
  XP via `experience.apply` (100/800/3000/10000/30000), consumes one,
  reports gains and new level. Lv 100, fainted, and egg targets are
  refused.
- `item_use.needsPartyTarget` (`ItemUse.__spCandyTargetWrapped`,
  in candy_flow):
  candies open the party picker.
- Reward tiers live in `candy_data.lua` as a `{ max, rewards }` row
  table, so thresholds edit without touching code; the single id
  lookup is `SP.candyDef` in `shared.lua` (over `SP.candyData` plus
  `SP.numId`), and `candy_data.lua` stays pure data. The exchange
  itself is two-phase: every reward passes a `canAdd` pre-check,
  then the mon is dropped (deferred PC deposit, else its party
  slot) and the candy granted; if any grant fails the mon is put
  back (deposit flag restored, else reinserted at its old index),
  so a failed exchange always falls back to the stock nickname
  prompt with nothing lost. The level curves in `data/skills.lua`
  are authored
  literals kept verbatim from the 1.3.18 studio export, not
  generated — any future formula must reproduce those exact
  values (cap shares like's table by design).

## IV guard (`battle/iv_guard.lua`)

- `battle.ui.askYesNo` (`Ui.__spIvGuardWrapped`): wraps outside the candy
  wrap, so it sees the nickname prompt first. A duplicate catch whose
  mon has at least IV GUARD perfect (31) IV stats asks to keep it; Yes
  marks the result so the inner candy wrap passes through to the stock
  nickname prompt, No falls through to the candy exchange question.
  Counts per-stat 31s, never totals. Retries on `battle.started`.

## Pokeblock case (`battle/pokeblock_case.lua`)

- `rse.init.call` (`Rse.__spCaseWrapped`): safari-battle
  `pokeblock.chooseForBattle` is gated on flag 0x5F. Without the case,
  shows "You don't have the POKéBLOCK CASE yet." and returns to the
  safari menu; with it, re-wires to `chooseForBattle(session, cb)`.
  Retries on `battle.started`.
- `battle.update` (`B.__spCaseInputWrapped`): while
  `safari_pokeblock`, pumps input into the open case screen; forces
  phase back to `command` if the case closed without resuming. First
  pump error logged once per battle.

## Mastery (`battle/mastery.lua`)

- `battle_bridge.start` (`Bridge.__spMasteryWrapped`): wild, non-link,
  non-tutorial, non-trainer foes with no preset IVs get a full random
  IV table with mastery 31s applied (guaranteed picks then 50% bonus
  picks, swap-remove over non-31 stats), keyed by National Dex with the
  caught species (never the evolution line). Counts cap at 300.
  Tiers: 5: 0+1, 15: 0+2, 30: 1+1, 50: 1+2, 75: 2+1, 100: 2+2,
  150: 2+3, 200: 2+4, 300: 3+3.
- `catching.storeCaught` (`Catching.__spMasteryWrapped`): a successful
  non-tutorial catch increments that species' counter and persists it.
- `save.loaded` → pull/scrub; `save.writing` → persist. Sparse
  `{ [natDex] = count }` under save key `mastery`, mirrored on the
  session.

## Safari XP (`battle/safari_xp.lua`, level math in `shared.lua`, curves in `data/skills.lua`)

- `catching.storeCaught` (`Catching.__spSafariXpWrapped`): a successful
  non-tutorial catch awards Catch XP — `20 + (255 - rate) / 2` from the
  species catch rate (rate 255 → 20, rate 3 → 146), ×5 on legendary
  repeats, ×30 on first-time legendary catches (`SP.isLegendary`, the
  single shared list), +1000 on shiny catches (`SP.isShiny`); every catch also awards Cap XP from throwing
  efficiency: +8 on the first ball, -1 per failed ball this combat,
  floor +4 (`Catching.tryCatch` guard `Catching.__spXpThrowWrapped`
  counts failed SAFARI BALL throws; the count resets on
  `battle.started` and clears on `battle.ended`, so it never survives
  combats), plus +8 more on a first-time species catch. Accumulates per skill in the session, persisted
  under save key `xp`; `SP.xp(skill)` / `SP.addXp(skill, amount)` are the
  interface event emitters use.
- `rules.safari.watchStep` (`RS.__spXpWatchWrapped`): a "watching"
  reaction (the flee-fail, "<mon> is watching carefully!") in our
  safari battles awards +6 Like XP. Installed at boot, retried on
  every `battle.started`.
- `rules.safari.throwPokeblock` (`RS.__spXpBlockWrapped`): throwing a
  POKéBLOCK (the bait axis) in our safari battles awards +8 Like XP.
  Same install/retry.
- `battle.ended`: an ended safari battle of ours awards +10 Regen XP.
- `world.stepped`: a field step while below cap awards +1 Regen XP.
- `shared.tick`: each ball granted by the wall-clock tick awards
  +4 Regen XP.
- Levels derive from XP in `shared.level` (highest threshold met in
  the `data/skills.lua` curves, clamped to the old maxes 60/30/70/30);
  `M.count` returns the XP level, so the catch/like/regen/cap
  formulas follow with no other changes. No shop: the mart is
  vanilla stock. Legacy purchased counts seed XP once at their
  level's threshold (max wins, earned XP never clobbered).
- `save.loaded` → pull/scrub (+ one-time legacy seed when the `xp`
  bucket is absent); `save.writing` → persist.

## SAFARI menu row (`overworld/safari_menu.lua`)

- `ui.start_menu.items` (same hook method as RADIO NEWS, separate row
  id `sp_safari`, so both rows coexist): appends a SAFARI row that
  closes the menu and chains four field-message bubbles (catch, like,
  regen, cap), each `Safari <skill> Lv <lvl>/<max> <prog>/<need>`
  with the skill's current effect line (`catch rate +N`, `like xN`,
  `ball/Ns`, `cap N/70`). Progress is XP into the current level over
  that level's XP requirement.

## Safari balls (`overworld/bag_balls.lua`)

- `bag.get` / `canAdd` / `add` / `remove` / `set` / `listPocket`
  (`Bag.__spBall*Wrapped`): item id 5 (SAFARI BALL) is virtual and
  mirrors the live stock, listed even at 0. Stray real slots are
  absorbed; add/remove/set adjust the stock clamped to the live cap.
  `remove` / `set` pass `qty` through for non-ball ids.

## Entrance (`overworld/entrance.lua`)

- `objects.loadMap` / `spawnFromDefs` / `adoptPool`
  (`Objects.__spLoadWrapped` etc.): every south map load re-parks the
  exit-door guard 1 left and 6 up via `setObjectXY`, plus nearby
  safari/exit-scripted NPCs. South is a suffix-exact match, so
  SOUTHEAST/SOUTHWEST never trigger it. Each parked guard is logged
  once with its local id and script key. Restore runs only while still
  on the south map; otherwise the registry is dropped (respawn covers
  it). Re-applied on `save.loaded`, `game.ready`, `mods.loaded`,
  `map.entered`, and `mod.options_changed`.
- `safari.enter` (`Safari.__spEnterWrapped`): returns false while on, so
  the timed zone game can't start.
- `scripting.space.startScript` / `runImmediately`
  (`Space.__spScriptWrapped` / `__spRunWrapped`): the four
  entrance-desk scripts (counter, try-enter, no-case, exit-walk) are
  swallowed with the field unlocked — with or without the POKéBLOCK
  CASE you walk past with no fee and no timed game.

## Save/events (`shared.lua`, static data in `data/skills.lua`)

- `save.loaded` → pull/scrub; `save.writing` → persist.
  `safariUpg` counts (legacy purchase mirror, migration source only),
  `balls` stock, `safariRegenAt` stamp (reset if
  non-numeric or >120s in the future). `0.5.0` migration scrubs older
  buckets.
- Shared helpers used across seams: `SP.require` (safe engine
  require, the single choke point), `SP.claim` (idempotent hook
  installer: true = just claimed, false = already installed; a
  non-table errors loudly instead of reading as success),
  `SP.opt` (guarded option read with default), `SP.numId`
  (guarded numeric item id), `SP.candyDef` (candy id lookup over
  `SP.candyData`), `SP.cleanName` (species-name normalisation),
  `SP.try` (guarded call returning ok, value — the replacement for
  single-call `pcall(function() ... end)` closures),
  `SP.once` (run-once wrapper), `SP.saveGet`/`SP.saveSet`, `SP.on`,
  `SP.session`, `SP.tick` (wall-clock regen; session-only update at
  cap, no save write), `SP.freeze`/`thaw`, `SP.isTutorial`, `SP.cap`,
  `SP.yieldPct`, `SP.level`/`SP.count` (XP-driven skill levels).
- Trust model: our own data files (`data/skills.lua`,
  `data/options.lua`, `battle/candy_data.lua`) load with `assert`
  in `main.lua`, so consumers use them directly with no guards.
  Engine modules stay guarded (`SP.require` + type checks + retry)
  because they load lazily. `pcall` remains only on engine/native
  calls that can plausibly fail and on the boot/install backstops.
