# safari-plus

Emerald Safari overhaul. Every wild encounter and every fated
(scripted/static) encounter opens the native Emerald Safari scene
instead of the normal combat scene. Trainer battles are untouched.

## Balls

- Safari stock starts at 10, base cap 10. Each BALL CAP level raises
- the cap by 2, up to 70 at level 30.
- Each safari battle draws its ball stock from the live stock; whatever
- is left is written back afterwards.
- Regen ticks on the host wall clock (`love.timer.getTime`, immune
- to emulation/game speed; `os.time` fallback) on field steps and
- shop visits: +1 ball per interval while below cap.
- The clock freezes when any battle starts and resumes after (battle
- time never accrues balls). Interval starts at 12 real seconds (see
- BALL RECOVERY).
- SAFARI BALL is always listed in the bag's balls pocket with the live
- stock, even at 0. It is virtual: the count is the stock itself, so
- regen, battles and the regen timer all show immediately, and the
- `save.writing` persist keeps the saved total exactly what was held.
- A safari catch pays experience through the normal in-battle pipeline:
- every alive sub-100 non-egg party mon is passed as a recipient to the
- engine's own award, so the "gained EXP" messages, bars and level-ups
- play in the battle scene before the dex/nickname flow. The award is
- scaled by the EXP YIELD setting (default 50% of what the species
- would yield if defeated).

## Oldale upgrades

Four stacking lines, 50 + 50 per owned level starting at 50.
Maxed lines leave the shelf. Upgrade rows are services, not items:
one level per purchase (quantity is forced to 1 so every level pays
the current dynamic price); buying applies the level at once and
never touches the bag.

- `SAFARI UPG` (60): +0.1 catch rate inside the catch-factor formula
- per level (max +6).
- `LIKEABLE` (30): -0.1 escape factor per level, floor 0.1.
- `BALL RECOVERY` (70): -100ms regen interval per level, floor
- 1 ball per 5 seconds.
- `BALL CAP` (30): +2 ball cap per level, from 10 up to 70.

## Options

- `SAFARI` toggle (default ON).
- `EXP YIELD` (default 50%): 0/10/25/50/75/100/150/200/300/400/500%.

## Layout

- `main.lua` — entry: options, boots everything.
- `options.lua` — the SAFARI toggle and the EXP YIELD choice.
- `shared.lua` — upgrade counts/prices, stock, wall-clock regen.
- `battle/safari_force.lua` — wild/fated encounters into the Safari
- scene (tutorials and trainer parties excluded); stock write-back;
- regen freeze/thaw around battles.
- `battle/catch_exp.lua` — safari catches pay party-wide EXP through
- the normal in-scene award presentation.
- `battle/no_balls_run.lua` — running out of balls plays the run-away
- pipeline (got-away message + flee sound, no zone eject) instead of
- the safari out-of-balls pipeline.
- `battle/factors.lua` — catch/escape factor bonuses; battle stock
- from the live stock.
- `overworld/shop.lua` — Oldale shelf, dynamic pricing, purchase
- conversion via `Bag.add`/`Bag.canAdd` wraps.
- `overworld/bag_balls.lua` — permanent virtual SAFARI BALL bag slot
- mirroring the live stock.
- `overworld/entrance.lua` — `world.talk` hook: on the Route 121
- Safari Zone entrance map, NPCs whose script identity mentions
- safari don't respond while the mod is on. Also breaks the zone
- game pipeline while on: `Safari.enter`/`exit`/`exitToEntrance`/
- `timesUp`/`outOfBalls`/`retirePrompt` are neutralized (specials 208
- and 209 can't start the step counter, lock the party, or teleport
- you to the lobby), the zone flag is cleared on boot and load, and
- zone steps never tick down — the zone is free-roam. The counter
- trigger and entry scripts are swallowed at the script runner (the
- field is unlocked so movement never sticks), so you walk past the
- desk and through the door warp with no Pokéblock Case check, no
- 500 charge, and no timed game. The exit-door guard inside the
- zone south is hidden while on (safari-scripted NPCs near you, or
- anything standing within a tile), so the way back out stays open;
- it returns when you leave or switch the mod off. All other maps
- and NPCs, and the OFF state, pass through untouched.

## Verify

luaparse 5.1 clean on all .lua files; page_refresh with no console errors.
