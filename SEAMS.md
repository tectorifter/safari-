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
  and ensures stock before starting.
- `battle.started` event: regen tick, then freeze the regen clock.
- `battle.ended` event: thaw the regen clock, write remaining
  `safariState.balls` back to the session stock, persist.
- `safari.takeStep` (`Safari.__spTakeStepWrapped`): regen tick, then
  zone steps are skipped while on.

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
  the no-balls text converted in the current battle.

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
  state.

## Duplicate candy (`battle/duplicate_candy.lua`)

- `battle.ui.askYesNo` (`Ui.__spCandyAskWrapped`): a duplicate catch at
  the nickname prompt first offers the EXP CANDY exchange. Yes removes
  the mon (party slot or deferred PC deposit) and grants candy via the
  stock `catch_pc_msg` pump; No (or a full bag) falls back to the stock
  nickname prompt. Tutorials, headless, and first-time catches pass
  through. Retries on `battle.started`.
- `items_data.info` (`ItemsData.__spCandyInfoWrapped`): ids 9101-9105
  report as EXP CANDY XS/S/M/L/XL (ITEMS pocket). Lazily re-runs
  `ensureWraps` until every wrap below sticks.
- `bag_chrome.iconImage` (`BC.__spCandyIconWrapped`) and `drawItemIcon`
  (`BC.__spCandyTintWrapped`): candy ids render the Rare Candy icon
  (68), tinted per tier, or a generated glyph when 68 has no art. Same
  for the RSE chrome (`src.ui.game3.rse.bag_chrome`, atlas-indexed;
  image+quad cached).
- `item_use.useField` (`ItemUse.__spCandyUseWrapped`): candy use applies
  XP via `experience.apply` (100/800/3000/10000/30000), consumes one,
  reports gains and new level. Lv 100, fainted, and egg targets are
  refused.
- `item_use.needsPartyTarget` (`ItemUse.__spCandyTargetWrapped`):
  candies open the party picker.

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

## Oldale upgrades (`overworld/shop.lua`)

- `bag_chrome._icons`: pre-seeded blank for 9001-9004.
- `bag.canAdd` / `bag.add` (`Bag.__spCanAddWrapped` /
  `Bag.__spAddWrapped`): upgrade ids convert to levels, never enter the
  bag. Qty > 1 refused; maxed levels refused; every other confirm
  applies exactly one level.
- `shop_menu.show` (`ShopMenu.__spShopWrapped`): Oldale mart appends
  non-maxed upgrade rows with dynamic prices; stock table is copied.
  Retries the RSE/FRLG wraps on every open.
- `rse.shop_menu.handleInput` (`RseShop.__spQtyWrapped`) and
  `shop_menu.handleInput` (`ShopMenu.__spUpgQtyWrapped`): upgrade rows
  clamped to qty 1, pre- and post-engine.
- `items_data._byId` gains 9001-9004 (name/price/description), refreshed
  per purchase.

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
  safari/exit-scripted NPCs. Restore runs only while still on the south
  map; otherwise the registry is dropped (respawn covers it).
  Re-applied on `save.loaded`, `game.ready`, `mods.loaded`,
  `map.entered`, and `mod.options_changed`.
- `safari.enter` (`Safari.__spEnterWrapped`): returns false while on, so
  the timed zone game can't start.
- `scripting.space.startScript` / `runImmediately`
  (`Space.__spScriptWrapped` / `__spRunWrapped`): the four
  entrance-desk scripts (counter, try-enter, no-case, exit-walk) are
  swallowed with the field unlocked — with or without the POKéBLOCK
  CASE you walk past with no fee and no timed game.

## Save/events (`shared.lua`)

- `save.loaded` → pull/scrub; `save.writing` → persist.
  `safariUpg` counts, `balls` stock, `safariRegenAt` stamp (reset if
  non-numeric or >120s in the future). `0.5.0` migration scrubs older
  buckets.
- Shared helpers used across seams: `SP.on`, `SP.session`, `SP.tick`
  (wall-clock regen; session-only update at cap, no save write),
  `SP.freeze`/`thaw`, `SP.isTutorial`, `SP.cap`, `SP.yieldPct`,
  upgrade count/price/level accessors.
