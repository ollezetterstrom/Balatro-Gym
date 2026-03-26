# AGENTS.md — Handoff Guide for AI Agents

## What This Is

Balatro-Gym: a headless (no graphics) simulation of the card game Balatro for reinforcement learning. Pure Lua engine, Python Gymnasium wrapper, deterministic RNG.

Repo: https://github.com/ollezetterstrom/Balatro-Gym

## Current State (March 2026)

- **145 jokers** registered with correct names/costs/rarity from real game's `game.lua`
- **~100 jokers** have working scoring behavior, 45 have stub implementations
- **49/49** scoring validation tests pass (`lua validate.lua`)
- **45/45** self-tests pass (`lua -e '_SIM_RUN_TESTS=true' balatro_sim.lua`)
- **1019/1019** cross-validation vs real game source (requires local game files)
- **12 hand types** evaluated identically to real Balatro
- **8 boss blinds**, 49 consumables (12 planets, 21 tarots, 16 spectrals)
- **180-dim observation** with deck composition, debuff status, boss state
- **Four Fingers, Shortcut, Splash** evaluator jokers implemented
- **Context hooks**: setting_blind, selling_card, open_booster, ending_shop
- **CI**: GitHub Actions runs Lua + Python tests on push/PR
- **pip install**: `pyproject.toml` for `pip install -e .`
- **`translate_jokers.py`**: extracts real game joker code as reference for stubs

## Architecture

The engine is split across 14 files in `src/`. `balatro_sim.lua` is a 40-line loader.

Load order matters — each file adds to the global `Sim` table:

```
00_header.lua     → creates Sim table
01_enums.lua      → Sim.ENUMS, Sim.HAND_BASE, Sim.DEFAULTS
02_rng.lua        → Sim.RNG (deterministic LCG)
03_cards.lua      → Sim.Card (constructor, chips)
04_jokers.lua     → Sim._reg_joker, 147 joker definitions
05_consumables.lua → Sim._reg_cons, 49 consumables + Sixth Sense/Hiker jokers
06_evaluator.lua  → Sim.Eval (poker hand detection)
07_engine.lua     → Sim.Engine.calculate (scoring)
08_state.lua      → Sim.State, Sim.DEFAULTS
09_blinds.lua     → Sim.Blind
10_shop.lua       → Sim.Shop
11_observation.lua → Sim.Obs (129-float vector)
12_env.lua        → Sim.Env (reset/step), Sim._do_reorder, Sim._use_consumable, Sim._advance_blind
13_test.lua       → 45 self-tests (runs when _SIM_RUN_TESTS=true)
```

**Critical: `dofile()` does NOT share `local` scope across files.** Anything that needs to be visible in multiple files must be on the `Sim` table (e.g., `Sim._reg_joker`, `Sim._do_reorder`). This was a major bug that took hours to find.

## How To Test

```bash
lua validate.lua                        # 49 scoring tests (fast)
lua -e '_SIM_RUN_TESTS=true' balatro_sim.lua  # 45 self-tests (fast)
```

Cross-validation requires game files (NOT in repo):
```bash
lua cross_validate.lua 1000 /path/to/Balatro/functions
```

## How Jokers Work

Each joker registers with `Sim._reg_joker(key, name, rarity, cost, fn)` where `fn(ctx, state, joker)` is called by the scoring engine with different contexts:

- `ctx.joker_main` — main joker phase (after hand type determined)
- `ctx.individual` — per scored card
- `ctx.other_card` — the card being processed
- `ctx.cardarea` — "play" or "hand"
- `ctx.held` — card is held in hand
- `ctx.all_hands` — table of all detected hand types
- `ctx.hand_type` — the best hand type (numeric)
- `ctx.after_play` — after scoring completes
- `ctx.round_end` — round ending
- `ctx.on_discard` — discard happened
- `ctx.setting_blind` — blind is being set up

Return values:
- `{ mult_mod = N }` — add to mult
- `{ chip_mod = N }` — add to chips
- `{ Xmult_mod = N }` — multiply mult
- `{ mult = N }` — per-card mult (individual context)
- `{ chips = N }` — per-card chips (individual context)
- `{ x_mult = N }` — per-card multiply (individual/held context)
- `{ dollars = N }` — gain money
- `{ destroy_self = true }` — joker destroys itself
- `{ level_up = hand_type }` — level up a hand type

## What Needs Work

### Priority 1: More joker behaviors
~100 jokers have `-- TODO` stubs. Each one needs its behavior ported from the real game's `card.lua:calculate_joker()` (lines 2291–4771). The real game file is at the SteamRIP path on Olle's machine:
`C:\Users\ozett\Downloads\Balatro-SteamRIP.com\Balatro\Balatro\card.lua`

### Priority 2: Missing context hooks
The engine doesn't fire `ctx.setting_blind`, `ctx.selling_self`, `ctx.selling_card`, `ctx.open_booster`, `ctx.ending_shop`, `ctx.skip_blind`, `ctx.skipping_booster`, `ctx.playing_card_added`, `ctx.first_hand_drawn`, `ctx.destroying_card`, `ctx.cards_destroyed`, `ctx.remove_playing_cards`, `ctx.on_after_play`. Many jokers need these.

### Priority 3: Evaluator joker integration
Four Fingers (4 cards for flush/straight), Shortcut (skip ranks), Splash (all played cards score) need to change `get_flush`/`get_straight` behavior in `06_evaluator.lua`. Check `if next(find_joker('Four Fingers'))` pattern in real game.

### Priority 4: More boss blinds
Real game has 25+ boss blinds. We have 8. Missing ones include: The Ox, The Fish, The Psychic, The Mouth, The Tooth, The Eye, The Plant, The Serpent, Pillar, Flint, Mark, Amber Acorn, Verdant Leaf, Violet Vessel, Crimson Heart, Cerulean Bell.

### Priority 5: Voucher system
Not started. Vouchers are permanent upgrades bought in the shop.

## Key Files For Reference

- Real game joker definitions: `game.lua` lines 368–526 (P_CENTERS table)
- Real game joker behavior: `card.lua` lines 2291–4771 (calculate_joker function)
- Real game scoring: `functions/state_events.lua` lines 571–800 (evaluate_play)
- Real game evaluator: `functions/misc_functions.lua` lines 376–611
- Real game blind system: `blind.lua`

These files are on Olle's machine at `C:\Users\ozett\Downloads\Balatro-SteamRIP.com\Balatro\Balatro\` but NOT in the repo (gitignored, copyrighted).

## Gotchas

1. **Don't use `local` for cross-file functions.** Use `function Sim._name()` instead.
2. **Don't use `replaceAll` for edits** — it hits function declarations too, creating `Sim.Sim._name`.
3. **Joker IDs change when new jokers are added.** Tests should use `Sim.JOKER_DEFS["key"].id` not hardcoded IDs.
4. **`build.py` module ranges are stale** — don't trust them, the loader approach makes them irrelevant.
5. **Observation space is 180 floats, not 129.** Includes debuff status, deck composition, boss state.
6. **HAND_BASE l_chips for Pair is 15** (not 20). Matches real game.
7. **Hiker gives +5 perma_bonus** (not +4). Matches real game.
8. **Lua 5.3+ required** — uses `>>`, `~`, `&` bitwise operators.
