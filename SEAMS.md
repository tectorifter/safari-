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
  and ensures stock before starting. The copy's `done` passes the
  outgoing result through `SP.chainResult`, which maps a converted
  catch or a fled wild mon to `"win"` so the encounter chain keeps
  chaining (player runs, forced out-of-balls ends and losses still
  break it).
- `battle.started` event: regen tick, then freeze the regen clock,
  then clear the fled snapshot.
- `battle.ended` event: thaw the regen clock, write remaining
  `safariState.balls` back to the session stock, persist. Snapshots
  the endReason (`SP.chainSnap`) and whether the mon fled
  (`SP.chainFled`, for `done` calls that run after the state is
  gone); an endReason outside the known win/caught/flee/run/loss
  family is logged once so it can be classified.
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

## Catch speedup (`battle/catch_speed.lua`)

- `ball_open.tick` (`BallOpen.__spSpeedWrapped`): while SAFARI is on
  and the SPEEDUP toggle is on (default ON), the native tick runs 3x
  per call during the throw and breakout steps (read live off
  `catch_seq._steps[_i].kind`); the throw arc stays visible, the
  catch lands in ~2s. All other steps and toggle/SAFARI OFF call
  through once.

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
  At 0% EXP YIELD the award is skipped entirely (no EXP, no EVs),
  while the queued stat-candy line still delivers.
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

## Duplicate candy (`battle/duplicate_candy.lua`)

- `battle.ui.askYesNo` (`Ui.__spCandyAskWrapped`): a duplicate catch at
  the nickname prompt first offers the EXP CANDY exchange (toggle ON)
  or a plain release (toggle OFF). Yes removes
  the mon (party slot or deferred PC deposit) and grants candy (or
  nothing on a pure release) via the
  stock `catch_pc_msg` pump; No (or a full bag) falls back to the stock
  nickname prompt. A conversion counts as winning the wild battle: the
  outgoing `done` result is mapped to `"win"` by `SP.chainResult`, so
  the encounter chain keeps chaining. Tutorials, headless, and
  first-time catches pass through. Retries on `battle.started`.
- `release_seq.start` (`RS.__spReleaseCandyWrapped`): a completed PC
  release (`onComplete(true)`) pays the same bundle as a conversion
  (stat + species per their toggles, EXP candy per its toggle) via
  `SP.awardOverworldCandy(..., firstTime=false, extra, isConvert=true)`;
  eggs and partners pay nothing. Retried on `map.entered` /
  `save.loaded`.
- `items_data.info` (`ItemsData.__spCandyInfoWrapped`): ids 9101-9105
  report as EXP CANDY XS/S/M/L/XL (ITEMS pocket); ids 9121-9138 as
  `<STAT> CANDY <SIZE>` (ITEMS pocket, `stat_candy` fieldUse). Lazily
  re-runs `ensureWraps` until every wrap below sticks; each installer
  gets two attempts per battle before it stops retrying (first failure
  logged once), so a permanently missing module costs nothing per bag
  row. The pending candy-learn slot clears on `battle.started`,
  `battle.ended`, and `map.entered`.
- `ItemsData.applyProfile` (`__spCandyPocketWrapped`) + boot: the
  ITEMS pocket cap becomes vanilla ITEMS pack count + our EXP/stat
  count + `SPECIES_ROOM` (1025) species ids, so every candy fits;
  re-applied after each profile apply, retried on battle start
  until the pack is readable.
- `bag_chrome.iconImage` (`BC.__spCandyIconWrapped`) and `drawItemIcon`
  (`BC.__spCandyTintWrapped`): EXP candy ids render the Rare Candy
  icon (68), tinted per tier, or a generated glyph when 68 has no art;
  stat candy ids render their size's stripped gray base sprite tinted
  per stat (HP yellow, ATTACK red, DEFENSE green, SP. ATK fuchsia,
  SP. DEF purple, SPEED pink). Same for the RSE chrome
  (`src.ui.game3.rse.bag_chrome`, atlas-indexed; image+quad cached).
- `item_use.useField` (`ItemUse.__spCandyUseWrapped`): EXP candy use
  applies XP via `experience.apply` (100/800/3000/10000/30000),
  consumes one, reports gains and new level. Lv 100, fainted, and egg
  targets are refused. Stat candy use grants +4 EVs inside its size
  window (S below 100, L 100-200, XL 200-252 of that stat's current
  EVs) via `Pokemon.applyStats`, still capped at 252 per stat and 510
  total (1512 with this mod's own 1512 EVS toggle ON, read live per
  use; no other mod consulted)
  (partial near window/cap edges, refused with no consume outside the
  window or when full); eggs refused, Lv 100 allowed. Species candy
  use raises every stat tied at the lowest IV by +1 on a same-line
  mon, costing 1 candy at lowest 0-10, 3 at 11-20, 5 at 21-29, 10
  for 30-31 (refused with no consume off-line, all-perfect, or short
  on the cost).
- `catching.storeCaught` (`Catching.__spStatCandyWrapped`): every
  successful safari catch rolls size then grants stat candy per stat in the caught
  species' runtime EV yield (read at the mon's name-anchored engine id,
  else the raw species value; `Pokemon.evYield`, else a scratch mon
  through native `gainEVs`; HP fallback logged), sized S/L/XL by
  caught level 1-18/19-36/37-100 (5% very small: 0, 80% normal: 1,
  10% above average: 2, 5% giant: 3), kept or converted, always;
  repeat catches stash a species-candy claim in the rolled size qty
  (seen set backfilled once from this mod's mastery counters,
  persisted; the line is resolved from the mon's true species NAME via
  `displayMonName` + round-trip-verified `speciesFromName`/engine-id scan, never from a
  bare numeric id — engine ids carry the Unown gap, so a bare
  national number names the wrong species. Verified resolutions heal
  poisoned defs/meta on sight; unnameable results grant no species
  candy stashed rather than granted). The size-led award ("You found
  a ...! Received ...!") rides the post-catch EXP line in
  `catch_exp`'s `Ui.push` wrap, or its own line at 0% yield; a full
  bag skips silently. Tutorials, non-safari, and failed catches pass
  through.
- `item_use.needsPartyTarget` (`ItemUse.__spCandyTargetWrapped`):
  candies open the party picker.

## Partner (`battle/partner.lua`)

- `pokemon.applyStats` (`Pokemon.__spPartnerWrapped`): flagged mons
  get +10 HP, +25 Attack, +10 Defense, +25 Sp. Atk, +10 Sp. Def,
  +30 Speed added to base before the native formula (natures included);
  current HP tops up by the max-HP gain. No dex entries: wild,
  unflagged, and toggle-off mons compute vanilla.
- Flagging (`mon.spPartner`, save key `partnerAssigned`): the first
  `pokemon.before_give` of a starter-line species arms the bond; the
  new party mon stamps on `battle.started` / `map.entered`.
  `save.loaded` adopts the first party line mon on older saves.
  Evolutions carry the flag; `pokemon.evolved` recalcs. Rival-line
  enemy mons stamp on trainer `battle.started` (rival ids only).
- Release guard: `ui.party.submenu` drops RELEASE for the flagged
  partner; `convertRes` refuses it ("won't leave your side!").
  Toggle OFF restores vanilla stats and release.
- Abilities follow the toggle: partner ON assigns the line
  ability at bond time (Torchic Intimidate, Treecko Lightning
  Rod, Mudkip MUD_FORCE + rain Attack) and re-syncs it on
  `battle.started` / `save.loaded` / `map.entered`-if-nil /
  evolve; partner OFF restores the native species ability
  (`Pokemon.abilityId` from live species + personality, MUD_FORCE
  cleared) in the same spots plus `mod.options_changed`, and
  battlers sync `bt.ability` either way. Surface:
  `SP.partnerRestoreAbility(For)`.

## Partner moves (`battle/partner_moves.lua`, data in `data/partner_moves.lua`)

- Install (`ensure` on `battle.started`, `save.loaded`,
  `map.entered`): home ids 355-366 (Torchic 355-358, Treecko
  359-362, Mudkip 363-366), relocated past any foreign occupancy
  (900+ when the dex mod is present or anything else holds 355+;
  at home otherwise) with every `DATA` num set rebuilt from the
  live base; rows carry `spPartner = true` so foreign scans skip
  them. Saved `pmBase` migrates party/box moves between bases in
  both directions, once per change. Names install into
  `Pokemon._moveNames` / `_romMoveNames`, ids into
  `Moves.BY_NUM` — each only when the table already exists, so a
  not-yet-installed engine pack is never clobbered;
  `Moves._numByName` only when already built. Native-effect
  riders (first-turn flinch 158, confusion 76, Defense-down 69,
  Speed-down 70) need no custom code.
- `gen3MoveEffects` records (via `ModBattle.data()`, which the
  `mod.content.move_effects` gate skips for gen3): dual-stat
  drop, team Reflect (5 turns, refresh-safe), self Speed, 15%
  drain heal, Leech Seed (grass/substitute/seeded fail),
  priority Protect (own streak continuing the vanilla Protect
  ids, same fail curve).
- `Damage.calc` (`__spPartnerMovesWrapped`): friendship power
  (`floor(10 * friendship / 25)`, min 1) unless the call presets
  power; Mud Force copies the attacker with +30% Attack in rain.
- `Engine.resolveMove` (`__spPartnerMovesResolveWrapped`):
  singles, non-called, non-user-targeted hits only — a Hydro
  Shield block changing neither HP nor status cures the user's
  status with a message.
- `battle.accuracy`: friendship-power moves always hit; Mud
  Traps misses unless the target's planned turn action is a
  power>0 move (fail-closed when the plan is unknown).
- `trainer.party`: rival rows take their line's badge-allowed
  moves (count from live badge flags) with the line ability;
  Wally appends the third line (neither yours nor the rival's)
  at top party level and parks line mons last. Non-line rows,
  wilds, and other trainers untouched.
- Tutoring (Mom NPC in Littleroot, `world.talk` intercept): her chat
  opens with a greeting plus TUTOR / REST / CANCEL — Cancel closes
  it untouched, REST runs her usual event, TUTOR opens the ROM's own Battle Frontier tutor screen: the
  native kind-9 exchange listmenu (right-aligned SC prices, the
  field stays visible behind it) with the native description
  pane fed by the ROM tutor bins, which the mod extends with the
  partner line's move ids for the visit; move descriptions fall
  back to the mod's one-liners only where the ROM text has none.
  No mod-drawn screen remains: prompts, warnings, the price
  confirm and the learn flow all run through the native message
  box, yes/no choice, LearnMove and summary screens. Locked/
  short/known picks warn with exactly what's missing (badges
  have/need, candy have/need); cost taken only on success, and
  the shop stays open for more teaching. PARTNER-off leaves her
  chat vanilla; taught moves stay live.
- Surface: `SP.partnerMoveData` (defs, lines, unlocks, costs),
  `SP.partnerMoves` (`allowedFor`, `costFor`, `ensure`, `lineOf`,
  `moveDef`, `applyPartnerRow`, `trainerKind`, `rowLine`).

## IV guard (`battle/iv_guard.lua`)
- `battle.ui.askYesNo` (`Ui.__spIvGuardWrapped`): wraps outside the candy
  wrap, so it sees the nickname prompt first. A duplicate catch whose
  mon has at least IV GUARD perfect (31) IV stats asks to keep it; Yes
  marks the result so the inner candy wrap passes through to the stock
  nickname prompt, No falls through to the candy exchange question.
  The keep question itself travels through the inner candy-wrapped ask,
  so SP.ivGuardAsking is raised while it is up and the candy wrap
  passes it through untouched (it keys off phase + catch-result state,
  not prompt identity, and would otherwise hijack it into a candy
  exchange, consuming spCandyAsked before the guard resolves).
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
- `SP.masteryCount` / `SP.masteryTierFor`: the same counters/tiers
  for overworld mon gen (no battle state exists yet there).

## Safari XP (`battle/safari_xp.lua`, level math in `shared.lua`)

- `catching.storeCaught` (`Catching.__spSafariXpWrapped`): a successful
  non-tutorial catch awards Catch XP — `20 + (255 - rate) / 2` from the
  species catch rate (rate 255 → 20, rate 3 → 146), ×5 on legendary
  repeats, ×30 on first-time legendary catches (`SP.isLegendary`, the
  single shared list); every catch also awards Cap XP from throwing
  efficiency: +8 on the first ball, -1 per failed ball this combat,
  floor +4 (`Catching.tryCatch` guard `Catching.__spXpThrowWrapped`
  counts failed SAFARI BALL throws; the count resets on
  `battle.started` and clears on `battle.ended`, so it never survives
  combats), plus +8 more on a first-time species catch. Overworld
  catches bypass the scaling and pay a flat +4 Cap XP instead
  (see below). Accumulates per skill in the session, persisted
  under save key `xp`; `SP.xp(skill)` / `SP.addXp(skill, amount)` are the
  interface event emitters use.
- `rules.safari.watchStep` (`RS.__spXpWatchWrapped`): a "watching"
  reaction (the flee-fail, "<mon> is watching carefully!") in our
  safari battles awards +6 Like XP. Installed at boot, retried on
  every `battle.started`.
- `rules.safari.throwPokeblock` (`RS.__spXpBlockWrapped`): throwing a
  POKéBLOCK (the bait axis) in our safari battles awards +8 Like XP.
  Same install/retry.
- Overworld (`overworld/overworld_catch.lua` `breakOut`): a failed
  overworld throw (no safari battle, so neither Like source above can
  fire) awards +2 Like XP (`GAIN.likeFail`) and +1 Regen XP
  (`GAIN.regenOwFail`).
- An overworld catch (`resolveCatch`) awards +3 Regen XP
  (`GAIN.regenOwCatch`); its Cap award is a flat +4
  (`GAIN.capOwCatch`, via the `SP.owFlatCap` flag on
  `storeCaught`) instead of the battle scaling below.
- Both overworld paths snapshot skill levels first (`SP.count`)
  and queue a `Safari <skill> up! Lv <n>` toast per skill that
  leveled, in the same HUD toast queue as the Gotcha/broke-free
  messages; a player level-up (or drained backlog) adds a
  `Player up! Lv <n>` toast the same way.
- `battle.ended`: an ended safari battle of ours awards +10 Regen XP.
- `world.stepped`: a field step while below cap awards +1 Regen XP.
- Levels derive from XP in `shared.level` (highest threshold met in
  `XP_TABLE`, clamped to the old maxes 60/30/70/30);
  `M.count` returns the XP level, so the catch/like/regen/cap
  formulas follow with no other changes. No shop: the mart is
  vanilla stock. Legacy purchased counts seed XP once at their
  level's threshold (max wins, earned XP never clobbered).
- `save.loaded` → pull/scrub (+ one-time legacy seed when the `xp`
  bucket is absent); `save.writing` → persist.
- Every `SP.addXp` gain also pays 100x as trainer XP via
  `SP.playerAddXp` (PLAYER LEVEL toggle, default ON), halved
  (rounded down) while `SP.playerLevel()` is below 40, and every
  successful catch (battle or overworld, through the same
  `storeCaught` wrap) pays flat trainer XP via
  `SP.playerNoteCatch`: 400 catch + 1000 first-time species +
  1500 legendary.

## Player level (`battle/player_level.lua`, data in `data/player_levels.lua`)

- GO 1-80 trainer curve (L80 = 203,622,000; L2-25 gaps x1.5, later
  levels shifted +269,000 to stay monotonic) in `THRESHOLDS`;
  session `playerXp` + save key `playerXp`, scrubbed/clamped,
  `save.loaded`/`save.writing` synced. `SP.playerXp` /
  `SP.playerLevel` / `SP.playerToNext` / `SP.playerAddXp` (returns
  gained + level ups, counts `SP.playerPendingUps`) are the
  surface; `SP.playerTakePendingUps` drains the toast backlog.
- Flat awards: catch 400 / new species 1000 / legendary 1500
  (`SP.playerNoteCatch`, both battle and overworld catches),
  wild-battle win 400 (uncaught only), trainer 500, gym 1000
  (265-272 + 770-801 rematches), rival 1000 (RIVAL_IDS), E4 2000
  (261-264), champion 2000 (Wallace 335), evolve 1000
  (`pokemon.evolved`, party members only), hatch 1000
  (`egg.hatched`), item-ball pickup 350 (`SP.playerNotePokestop`),
  max-raids den win 6000 (`SP.playerNoteDenWin`, via a wrapped
  `raid.startCatch`, installed at boot and retried on
  `save.loaded` / `map.entered`, 60s double-grant guard). Den
  catches always succeed (100%): `battle/max_raids.lua` wraps the
  max-raids `_test.rewards.chance` to return 100 (claim-guarded,
  no-op while the mod is absent), retried on the same events.
  `battle.started` records trainerId (nil = wild) and
  `storeCaught` marks caught battles; `battle.ended` pays
  `SP.playerBattleWin` on win-like results, skipping safari
  battles and tutorials.
- Drop gates (`SP.playerDropLocked`, used by item balls):
  great ball 14, evo items 16, pinap 18, ultra ball 20, silver
  pinap 22, golden razz 25. Toggle OFF disables all trainer XP
  and opens every drop.

## SAFARI menu row (`overworld/safari_menu.lua`)

- `ui.start_menu.items` (same hook method as RADIO NEWS, separate row
  id `sp_safari`, so both rows coexist): appends a SAFARI row that
  closes the menu and chains four field-message bubbles (catch, like,
  regen, cap), each `Safari <skill> Lv <lvl>/<max> <prog>/<need>`
  with the skill's current effect line (`catch rate +N`, `like xN`,
  `ball/Ns`, `cap N/70`). Progress is XP into the current level over
  that level's XP requirement.

## Ball equip (`overworld/equip_ball.lua`)

- `SP.equippedBall()` / `SP.setEquippedBall(id)` (shared): the
  equipped ball id (1-12, default 5 SAFARI), session + save
  (`equippedBall`); a non-safari pick with zero owned in the bag
  falls back to 5.
- Bag skin `actionsForPocket`
  (`Screens.__spEquipSkinWrapped`): with OVERWORLD on, ball rows in
  POKE_BALLS gain
  USE, so `USE`, `GIVE`, `TOSS`, `CANCEL` (battle menus always fall
  through to native). OVERWORLD off is vanilla even with SAFARI on.
  Every other row calls
  through to the native skin, or to the engine's own pocket
  defaults when the skin has no such method — never nil, so the
  action menu can't crash on candy/pouch rows.
- `item_use.needsPartyTarget`
  (`ItemUse.__spEquipTargetWrapped`): with OVERWORLD on, balls never
  take a party
  target; `item_use.useField` (`ItemUse.__spEquipUseWrapped`):
  with OVERWORLD on, USE on a ball equips it and reports
  `<name> equipped!` (OVERWORLD off calls through to native).
- `SP.openBallsBag()`: opens the real bag at the POKE_BALLS pocket
  with the cursor parked on the equipped row.
- Overworld throws never use a safari ball, SAFARI on or off: an
  equipped id 5 reads as the first owned real ball, and a throw
  with no owned real ball reports no stock and throws nothing (the
  native `tryCatch` safari branch in `rollCatch` is a dead backstop
  only). Every real ball rolls its own formula (see Ball rates).
  The equipped id drives the HUD/throw art
  (`ballIdForItem`) and the stored `mon.pokeball`. Throws spend the
  equipped ball itself: safari stock for id 5, the real bag slot
  otherwise (the HUD chip shows the equipped ball's remaining
  count). The thrown id latches into the flight sequence at throw
  time: while a sequence is active the equipped read prefers the
  latched id, so HUD/throw art/stored `mon.pokeball` keep the thrown
  ball even after its count drops to 0 mid-throw; the zero-owned
  fallback to safari re-applies only once the sequence fully ends
  (break-out, catch resolve, or early teardown), persisted via
  `setEquippedBall`. Tapping a mon with no
  balls left runs the no-balls run-away in the overworld too: the
  actor despawns through Untamed with SE_FLEE + `Got away safely!`,
  mirroring the battle pipeline.

## Ball rates (`overworld/ball_rates.lua`)

- Non-safari overworld throws skip `tryCatch` and roll
- `P = 1 - (1 - baseCaptureRate / (2 x CPM))^modifier`, with four
- sequential shake checks at `P^0.25` each (caught iff all four
- pass, so the overall rate is exactly P; master returns 4 shakes).
- The SAFARI UPG bonus only enters the native safari-ball path, and
- catch/cap skill XP rides `storeCaught` for every ball id.
- `baseCaptureRate` is the native full-HP no-status x1 shake
- probability cubed: `catchOdds` for POKE BALL (id 4) into
- `b = floor(1048560 / sqrt(sqrt(16711680 / a)))`, `base = (b /
- 65535)^3`. Anchors: rate 45 (mew) gives 11.9%, rate 255
- (rattata) gives 43.9%. Falls back to `floor(rate / 3)` if the
- engine call is unavailable.
- `SP.cpmForLevel(lvl)`: level clamped to 1-70, linear
- 0.594 (lv 1) to 0.895 (lv 70).
- `SP.ballValue(ballId, ctx)`: poke/premier/luxury 1, great 1.5,
- ultra 2, master auto-catch; net 3 on Water/Bug (via
- `Pokemon.types`, else 1); dive 3.5 while surfing (player
- `surfing`), else 1; nest `(40 - level) / 10` (min 1) under
- level 40; repeat 3 when `Dex.isCaught(dex, species)` (else 1);
- timer `0.1 + 3.9 x age / 15.5` clamped to 4 (see below).
- Unknown ids read 1.
- `SP.distMult(d)`: Chebyshev tiles player-to-mon at throw time:
- 1 tile 2, 2 tiles 1.5, 3+ tiles 1.2.
- Timer age is always seconds since the actor was first seen
- (tracked per frame in `overworld_catch`; Untamed's `actor.age`
- is a spawn-order rank, never seconds, so it is ignored). The
- window is a fixed 16s (`TIMER_DEFAULT_MAX` in `ball_rates`;
- `SP.timerSpan` still probes `actor`/Untamed `engine.C` for a
- real lifespan field first, but Untamed has none: mons despawn
- on replacement/map-change, never on a timer). Full 4x at
- 15.5s on screen — matches the natural turnover (4s cadence x
- 4 slots ≈ 16s max life at cap). Entries are cleared in the
- `Owe.remove` wrap (slots are reused, so a replacement starts a
- fresh 0s timer); the weak-keyed table is the backstop.
- Berries (`overworld/berries.lua`):
- razz 148 (1.5x catch), pinap 152 (1.2x catch, 2x candy),
- golden razz 9401 (2.5x catch), silver pinap 9402 (1.8x catch,
- 3x candy rounded up). Candy mults apply to stat + species
- candy only, never EXP candy, at grant time (`berryBump` in
- `stat_candy`: battle + overworld stat loops and the overworld
- species reward read the live mult; `takeSpeciesConvert` pays the
- mult snapshotted at the battle catch, since the berry is already
- eaten by conversion time). `SP.armBerry(kind)` /
- `SP.tryUseBerry(kind)` (bag spend, `active`/`empty` errors) /
- `SP.berryKind()` / `SP.berryCandyMult()` share the
- `session().safariBerry` shape with the old hook (`setBerryMult`
- still arms a kind-less multiplier). One berry at a time: any
- armed berry blocks all presses (`Another berry is in effect!`);
- zero count says `No <name> left!`. The effect is eaten by the
- next catch resolution only: battle safari catches consume it in
- the `storeCaught` wrap (which also snapshots the candy mult into
- the species claim, so the later conversion still pays it), and
- overworld catches consume it in `resolveCatch`/`breakOut` via
- `eatBerry(s)` on `usedBerry` throws (incl. box-full/bag-full
- exits). The wrap never eats it for non-safari catches, so the
- overworld `storeCaught` call leaves it armed for the
- `awardOverworldCandy` bump that follows. Never mid-flight
- arming (the throw snapshots `berry > 1` into `seq.usedBerry`). Customs get
- `displayName`/`pocketOf` (`BERRY_POUCH`)/`info` (price 1) wraps,
- `BERRY_POUCH` cap 45, and bag-chrome + RSE icon wraps serving
- the golden/silver icons (native razz/pinap sprites baked with
- a gold/silver multiply; razz/pinap stay fully native). Base
- sprites come from the FRLG `bag_chrome.iconImage` cache when
- present, else from a 24x24 crop of the RSE icon atlas row for
- the id (the FRLG cache is empty in RSE sessions, which had
- blanked every HUD berry icon). Soil
- guard: the RSE `bag.chooseBerry` wrap intercepts golden/silver
- picks, shows `This berry can't be sown!`, and re-opens the
- picker, so the soil script never receives the id (no plant, no
- consumption; natively the id would mis-plant as Cheri via
- `itemToBerry`). Razz/pinap and cancel pass through untouched.
- HUD: two rows under the ball
- chip (`hudBerryBoxes`, tap-to-use, active cell outlined green;
- hidden with the chip when the field/HUD gates shut).
- If `SP.customCatch` is missing/broken at throw time, the roll
- falls back to native `tryCatch` with the real ball id and no
- safari state (engine per-ball rates, no skill bonus). Custom
- throws bypass the `catch.rate` hook and `battle.ball_thrown`
- telemetry that native throws emit.
## Overworld HUD (`overworld/overworld_catch.lua` `drawStockHud`)

- Flush-left chip: equipped-ball sprite + `x <equipped count>`;
  the old `CR:` line is gone. Tapping the chip (no throw in
  flight) opens the bag at POKE_BALLS via `SP.openBallsBag`
  instead of throwing; the tap box clears whenever the HUD is
  hidden. Two berry rows sit under the chip (razz | pinap,
  golden | silver): icon + `x <bag count>` per cell, tap spends
  one from the bag (`hudBerryBoxes`, no-throw gate, tap consumed
  so it never throws); the armed kind gets a green outline.
  Boxes clear whenever the HUD is hidden.
- Flush-right eye button: an eye icon (slashed while hidden)
  hides/shows the ball chip and both berry rows; the eye itself
  stays visible so it can be tapped back on. Under the eye sits a
  24-hour game-clock chip (`HH:MM` from the RTC local time,
  host clock fallback) with no background; it stays visible
  while hidden. All HUD numbers (ball/berry counts, clock) draw
  white with a 1px black outline, and the eye shapes carry a
  black underlay. The hidden flag
  persists in the session + save (`owHudHidden`). Toasts and the
  thrown-ball animation still draw while hidden.

## Safari balls (`overworld/bag_balls.lua`)

- `bag.get` / `canAdd` / `add` / `remove` / `set` / `listPocket`
  (`Bag.__spBall*Wrapped`): item id 5 (SAFARI BALL) is virtual and
  mirrors the live stock, listed even at 0. Stray real slots are
  absorbed; add/remove/set adjust the stock clamped to the live cap.
  `remove` / `set` pass `qty` through for non-ball ids.

## Evolution items (`battle/evo_use.lua`, data in `data/evo_drops.lua`, art in `battle/evo_art.lua`)

- One custom item (id 9407 LINKING CORD) with `displayName` /
  `pocketOf` (ITEMS) / `info` (price 100) / `description` wraps plus
  bag-chrome and RSE icon wraps serving original 24x24 art
  (`SP.evoArt`, same build as berry art). ITEMS capacity counts it
  through `SP.evoCustomCount` (set before `candy_pockets` boots).
- `ItemsData.fieldUseKind` reports "evo" for the 12 native evo items
  (stones, King's Rock, Metal Coat, Dragon Scale, Upgrade, Deep Sea
  Tooth/Scale) plus the custom cord, so the bag offers USE and the
  party screen treats them as evolution items. Nothing else changes:
  non-evo items call through.
- `Evolution.itemTarget` / `itemCheck`: the native result wins; the
  fallback covers trade-item rows (held param == used item, e.g.
  King's Rock on Poliwhirl) and no-item trade rows for the Linking
  Cord (Kadabra/Machoke/Graveler/Haunter). Everstone holders and
  national-dex gates still refuse. The native scene + consume path
  runs the evolution, so cancel rules and nickname handling are
  untouched.

## Item balls (`overworld/item_balls.lua`, natives in `data/item_ball_natives.lua`)

- `world.talk` diverts the 162 real item balls: `data/
  item_ball_natives.lua` is keyed by pret script label, but runtime
  defs carry address keys (`g3:…` via `Opcodes.key`), so the divert
  translates every label through `Space.scriptKey` into a runtime-key
  table (rebuilt when the script bundle identity changes; raw labels
  still match directly). Pyramid randoms, Voltorb/Electrode, gift-mon
  and flavor balls call through. The native script never runs, so its
  flag never sets and the ball stays on the map. Matching needs no
  gfx and falls back to the baked map when the session map is
  missing, and the whole divert runs under pcall with a keep-the-ball
  fallback, so no engine difference can fall through to native
  consumption. A first pickup that grants nothing says "Your bag is
  full!" instead of running native.
- First pickup grants the native item + a drop bundle; recharges
  grant only the bundle. A bundle is 6 weighted rolls (balls
  48.36/13.93/2.36, berries 7.64/0.03/6.20/0.03, 13 evo items at
  0.03 each, random-species egg 0.45%) capped at 4 balls, 4 berries,
  1 of each evo item and 1 egg per pickup; the pool is filtered by
  PLAYER LEVEL (great 14, evo 16, pinap 18, ultra 20, silver
  pinap 22, golden razz 25). Eggs are random 1-386
  non-legendary via `Party.giveEggToPlayer`. Every granted pickup
  pays 350 trainer XP (`SP.playerNotePokestop`) and appends a
  "Player level up!" line when the pickup leveled.
- State lives in `mod.save` (`itemBalls`, keyed map + local id):
  taken + wall-clock recharge (5 min). Stale-future deadlines (save/
  reload residue) are treated as expired in both the talk and the
  HUD, so a reload never wedges a ball gray or empty. Cooling balls
  redraw their own sprite pixels through the map's own
  `OwSprites.draw` (same sheet, quad, facing and position the
  engine just drew, so the tint rides the ball under every
  camera), graying only the ball; cooled talks show "It's
  empty..." until the 5 min pass.

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

## Overworld catch (`overworld/overworld_catch.lua`)

- `encounter.roll`: while the OVERWORLD toggle is on, returns nil
  only when Untamed itself parks step battles (OW encounters on,
  vanilla random off) — mirroring its gate, so Random-battles-ON
  setups keep their rolls. Scripted/fishing/roamer rolls call
  through untouched. Wilds of Hoenn rolls are never suppressed:
  it self-manages vanilla encounters (`classic_enc`, on by default).
- No spawner lives here: tap targets are the live actors of
  whichever spawner answers — Untamed's OWE actors (via
  `mod.find("untamed_advanced").exports.engine`, 1.0.2 shape
  required) or, failing that, Wilds of Hoenn `spawnManager`
  entities (available/encounter_starting; leaving is never
  tappable) — filtered to generated spawns with a
  real species/level; the follower (slot 1) and manual actors are
  never tappable. Targeting runs on an owned replica of that live
  state (per-tap records plus an owned camera and blit mapping, no
  Untamed spawn/draw/behavior change); `Owe.remove` is wrapped only
  to drop stale landing-prediction velocity. A Wilds of Hoenn
  catch despawns through `spawnManager:despawn`; hiding rides
  `markEncounterStarting` plus a `collectActors` filter that drops
  the hidden entity's actors until the sequence ends.
- `input.step` (calls `next` first): samples live actor positions
  for landing prediction (velocity capped at the engine's fastest
  step rate, so a frame hitch can't fake a sprint and throw the
  landing tiles off), runs the throw/fly/rock/still/fade
  sequence, and toast timers. Frozen while the field gate is shut
  (menus, scripts, battles, warps). With no spawner it warns once
  per map and idles. Map change clears sequence/toasts.
- `input.pointer` (pressed): window→game mapping through the cached
  hud viewport, using the engine's TRUE per-axis scales
  (scx = viewport.scale, scy = viewport.gameHeight/160; the engine
  letterboxes per axis), hit-tested against the mon's VISIBLE sprite — the
  occupied tile plus the sprite body above it (feet-anchored art:
  sprite top = tile bottom minus atlas frame height, read from
  Untamed's own `E.Data.ATLAS.sheets`, 16x32 standard on fallback;
  +4px hop slack; widened for wide frames); consumed (returns true)
  only on a real throw or an out-of-stock tap, else calls through.
  A tile-only box misses taps aimed at the creature (the head of a
  16x32 mon is a full tile above its tile, and tall grass hides the
  bottom half). Mapping
  is owned end to end: the camera comes from an owned
  `FieldView.draw` capture (player + live world-canvas size, pan
  included; the old actor-median inference is fallback only), and
  taps convert window→world through the live world blit
  (`Renderer.frameRects` + world-canvas size + `Zoom.scale`,
  recomputed per tap, so portrait growth, dpi split, lift and zoom
  all cancel exactly). The per-actor draw record is used only as a
  freshness/visibility gate (freshest draw serial, sprite rect
  inside the owned world canvas). Overlapping
  sprite boxes resolve to the nearest mon. Throw gate:
  toggle on, no active sequence, 1s cooldown, field gate
  clear, player standing still, a spawner present. Landing =
  predicted tile center (3-tile clamp), snapped to the mon's live
  tile on landing; the mon hides inside the ball (Untamed:
  visible=false; Wilds of Hoenn: encounter_starting + actor
  filter) through rock/still/fade and reappears only on a
  break-out. A tap that finds nothing toasts "Missed!"
  only when a tappable mon is on screen; tapping while moving
  toasts "Stand still to throw!" (both throttled) — other gates
  stay silent so stray field taps never nag.
- `render.hud` (calls `next` first, draw-only): the equipped ball's
  sprite (battle ball sheet quad for the thrown id, same sprite
  cycle the safari battle throw uses:
  closed frame in flight with no spin, open-frame flicker on the
  landing gulp, closed with a slow tilt-rock per shake, still,
  then fade; a small ground shadow sits under the ball in every
  phase, nothing else is ever drawn). The mon hides inside the
  ball from landing until a break-out reveals it; the ball stays
  parked at the snapped landing tile, plus bottom toasts — all
  projected through the same owned world blit as the taps, so
  portrait presentation matches the hitboxes. The spawner draws the
  mons themselves — this mod draws no Pokémon.
- Foe shape is Untamed's own battle shape (actor species, level,
  personality, kept moves) plus the built mon; the mon is assembled
  from confirmed seams only — `Pokemon.learnset` for the wild
  moveset (most recent 4 at or below level, validated through
  `moveName`, `movePp` for PP, content-registry fallback),
  `applyStats` (stats-table formula fallback) for stats,
  guarded `natureId`/`gender` — so an unresolvable piece degrades
  instead of refusing the throw. IVs roll fresh (+
  `SP.masteryCount` / `SP.masteryTierFor` picks, as a bumped battle
  would grant), except Wilds of Hoenn foes keep the entity's own
  IVs/personality/moves when valid. The roll is `SP.customCatch` for the thrown real
  ball (per-ball value x berry x distance, timer age; master
  auto-catches). If the custom roller is missing or refuses, the
  fallback is native `Catching.tryCatch` with the real ball id and
  no safari state (engine per-ball rates, no skill bonus).
- `Catching.storeCaught` (existing mastery + safari-XP wraps fire
  as-is; EXP/candy wraps skip without a battle state): new species
  and IV-guard/shiny duplicates are kept, other duplicates convert
  via `CD.rewardsFor` (+ species candy through
  `SP.awardOverworldCandy`, which also pays the stat roll; kept mons
  get the stat roll only). EXP-candy OFF converts to a plain
  release. Party EXP/EVs are manual (vanilla /7 split, EXP YIELD
  scale, native `gainEVs`, auto-`teachMove` on free slots, no
  evolution scene). Full bag keeps the mon with a toast; a full PC
  leaves the actor wandering with a toast (nothing was despawned).
  Award text is one toast per candy row (`texts`: size line, then
  `Received <qty> <name>!` each) so long combined messages never run
  off the HUD; the conversion `You found` line is likewise one row
  per candy type.

## Save/events (`shared.lua`)

- `save.loaded` → pull/scrub; `save.writing` → persist.
  `safariUpg` counts (legacy purchase mirror, migration source only),
  `balls` stock, `safariRegenAt` stamp (reset if
  non-numeric or >120s in the future). `0.5.0` migration scrubs older
  buckets.
- Shared helpers used across seams: `SP.on`, `SP.session`, `SP.tick`
  (wall-clock regen; session-only update at cap, no save write),
  `SP.freeze`/`thaw`, `SP.isTutorial`, `SP.cap`, `SP.yieldPct`,
  upgrade count/price/level accessors, plus the refactor utilities
  `SP.require` (nil-safe require), `SP.try` (pcall guard), `SP.claim`
  (idempotent wrap flags), `SP.once`, `SP.opt` (options with default),
  `SP.numId`, `SP.saveGet`/`saveSet`, `SP.candyDef` (EXP + stat lookup
  over `SP.candyData.BY_ID`), `SP.cleanName`, `SP.isShiny`,
  `SP.chainResult` (maps a candy-converted battle's outgoing result
  and a fled wild mon's to `"win"`; player runs, out-of-balls ends
  and losses pass through), `SP.isFleeReason` / `SP.isChainQuiet` /
  `SP.liveEndReason` (the reason classifiers behind it), and the stat-candy surface
  (`SP.statCandyUse`, `SP.statCandyImage`, `SP.isStatBaseImage`,
  `SP.consumeStatLine`, `SP.clearStatPending`, `SP.takeSpeciesConvert`,
  `SP.awardOverworldCandy`, `SP.pouchImage`) plus the species-candy
  surface (`SP.speciesDef`, `SP.speciesCandyUse`,
  `SP.speciesCandyImage`, `SP.evTotalCap`) and the self-contained
  EV-cap readers (own 1512 EVS toggle via `SP.opt`, 252 per stat
  always; pokemon-trainer reads `SP.evTotalCap` for combat gains),
  `SP.candyPockets.ensure` (recompute the ITEMS cap) and the pouch
  surface (`SP.candyPouch.ensure/open/pouchId`; candies live in
  the pouch save store, Bag add/remove/get/has/canAdd redirect
  candy ids there, the CANDY POUCH (id 9400) is the only ITEMS
  row, USE opens the native bag candy picker (icons +
  descriptions, berry-tree choose mode over a transient ITEMS
  bag built from the store, titled Candy Pouch, Close pouch
  row returns to the bag's ITEMS list with the pouch row
  selected) then the native party-use flow,
  stocked pouch refuses GIVE (checkGive/canGive/giveHeld/
  switchHeld) and TOSS/deposit (bag-skin beforeAction,
  Bag.remove/Storage guards); stray empty rows scrub).
  Species candy
  ids are 9500+national (room to 9500+1025); defs carry `owner`
  ("safari-plus", partner defs respected and never healed), so a
  partner mod can register evolved-stage candies in the same
  range and this mod will use them as-is.
  plus the partner surface (`SP.isPartnerMon`, `SP.partnerLine`,
  `SP.partnerRecalc`) and the partner-moves surface
  (`SP.partnerMoveData`, `SP.partnerMoves`).
