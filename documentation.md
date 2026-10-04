# safari-plus documentation

## Seams

- `src.core.game3.battle_bridge.start` (guard `Bridge.__spSafariWrapped`):
- wild battles (`opts.wild`, non-link, tutorials and trainer parties
- excluded) get `opts.safari = true`. Calls through.
- `src.core.game3.battle.rules.safari.newStateRse` / `newState`
- (guards `RS.__spRseWrapped` / `RS.__spNewWrapped`): battle ball stock
- comes from the live session stock.
- `Rules.safari.ballCatchRate` (guard `RS.__spRateWrapped`): adds
- +0.1 per SAFARI UPG level (60 max).
- `Rules.safari.fleeRate` (guard `RS.__spFleeWrapped`): escape factor
- reduced 0.1 per LIKEABLE level, floor 0.1.
- `src.core.game3.safari.takeStep` (guard `Safari.__spTakeStepWrapped`):
- wall-clock regen tick; calls through.
- `src.core.game3.bag.add` / `canAdd` (guards `Bag.__spAddWrapped` /
- `Bag.__spCanAddWrapped`): upgrade ids (9001-9004) convert to levels,
- never enter the bag. Single-level only (qty > 1 refused); a repeat
- of the same id at the same price, or within 2 wall seconds of the
- last buy, is refused, so a double-fired confirm at high game speed
- can neither double-apply nor double-charge.
- `src.core.game3.bag.get` / `canAdd` / `add` / `remove` / `set` /
- `listPocket` (guards `Bag.__spBall*Wrapped`): item id 5 (SAFARI
- BALL) is virtual and mirrors the live stock, so the balls pocket
- always lists it, even at 0. Stray real slots are absorbed into the
- stock; add/remove/set adjust the stock clamped to the live cap.
- `world.talk` hook: on the Route 121 Safari Zone entrance map
- (`EM_ROUTE121_SAFARI_ZONE_ENTRANCE`, dashes and the ENTRACE
- spelling also match), NPCs whose script key or def mentions safari
- are swallowed (no response) while the mod is on. All other maps,
- NPCs, and the OFF state call through.
- `src.ui.game3.shop_menu.show` (guard `ShopMenu.__spShopWrapped`):- Oldale mart (`session.map == "EM_OLDALE_TOWN_MART"`) appends
- non-maxed upgrade rows with dynamic prices; stock table is copied.
- `src.ui.game3.rse.shop_menu.handleInput` (guard
- `RseShop.__spQtyWrapped`): upgrade rows are clamped to qty 1 (total
- rescales to the single unit price); calls through.
- `ItemsData._byId` gains entries 9001-9004 (name/price/description).
- `BagChrome._icons` pre-seeded blank for 9001-9004.

- `src.core.game3.battle.catching.storeCaught` (guard
- `Catching.__spCatchExpWrapped`): on a safari catch, runs the engine's
- own `Experience.awardFoe` with every alive sub-100 non-egg party mon
- as recipient, then queues a custom "All your POKéMON gained N EXP.
- Points!" line, delivered after the Gotcha message. N is the scaled
- per-mon share (EXP YIELD setting, default 50%). Tutorials
- excluded. A `battle.ended` fallback silently awards only if the
- in-scene award never ran.
- `exp.gain` hook: inside safari battles the per-mon award is scaled
- by EXP YIELD (0-500%) relative to the defeated yield; other battles
- pass through untouched.

- `src.core.game3.battle.battle_text.get` (guard `BT.__spRunWrapped`):
- `STRINGID_OUTOFSAFARIBALLS` renders as the run-away string with the
- flee sound, once per battle; calls through otherwise.
- `src.core.game3.safari.endBattleRse` (guard `Safari.__spRunWrapped`):
- any of our safari battles (`st.safari` while the mod is on) keeps
- the zone counters but returns false before the out-of-balls script
- and the entrance warp, for every end kind (thrown-out, fled,
- last-ball catch). Non-safari battles call through. The wrap is
- installed at boot and retried on every `battle.started`, so a
- boot-time require miss cannot leave the eject pipeline armed.
- `src.core.game3.safari.outOfBallsMidBattle` (guard
- `Safari.__spMidWrapped`): skipped once the no-balls text converted
- in the current battle; calls through otherwise.

## Events

- `battle.started`: regen tick, then freeze the regen clock.
- `battle.ended`: thaw the regen clock (battle time never accrues balls),
- then write remaining safari balls back to the session stock.

## Save data (persisted in the game save via `mod.save`)

- `upg = { catch, like, regen, cap }` (counts, clamped to each line's max).
- `balls` (stock, clamped 0 to the live BALL CAP level), `regenAt`
- (host-clock stamp, reset if non-numeric or more than 120s in the future).
- The live session mirrors the save and is synced on boot, on
- `save.loaded`, on `save.writing` (so the saved total is exactly what
- is held), and on every mutation; a `0.5.0` migration scrubs
- pre-existing buckets. Session-only data from older versions is
- adopted into the save once if the bucket is empty.
