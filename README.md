# BalatroSim

A headless, high-speed simulation of [Balatro](https://www.playbalatro.com/) for AI training and research. Pure Lua, zero graphics, deterministic RNG.

## What is this?

Balatro is a poker-themed roguelike deckbuilder where you score poker hands against escalating chip thresholds, augmented by Jokers, consumables, and deck manipulation. This project is a faithful reimplementation of its core mechanics — scoring engine, poker hand evaluation, joker effects, shop, blinds, ante progression — stripped of all rendering and UI.

**Design goals:**

- **Fast.** ~90K+ score calculations per second in standard Lua. No allocations in the hot path.
- **Deterministic.** Linear Congruential Generator seeded once. Same seed = same game, every platform.
- **Rust-ready.** Stateless functions, struct-like tables, explicit enums, no globals. Designed to port to Rust with minimal friction.
- **RL-compatible.** Fixed-size observation vector (129 floats), hierarchical action space, Gymnasium-compatible interface.

## Quick start

```bash
lua balatro_sim.lua
```

Runs 13 self-tests and a random agent demo. No dependencies beyond Lua 5.1+ or LuaJIT.

## As a library

```lua
local Sim = dofile("balatro_sim.lua")

-- Create a game
local state = Sim.new_game({ seed = "MYSEED", ante = 1 })

-- Play the first 5 cards
local result = Sim.play(state, {1, 2, 3, 4, 5})
print(result.hand_name)  -- e.g. "Pair"
print(result.total)      -- e.g. 192
```

## Gymnasium interface

```lua
local obs, info = Sim.Env.reset("SEED")
local obs, reward, done, info = Sim.Env.step(state, action_type, action_value)
```

### Observation (129 floats)

| Index | Feature | Encoding |
|-------|---------|----------|
| 0–47 | 8 hand card slots | `[rank/14, suit/4, enhance/8, edition/4, seal/4, has_card]` |
| 48–62 | 5 joker slots | `[id/pool, edition/4, has_joker]` |
| 63–92 | 30 global features | chips%, $, hands, discards, ante, 12 hand levels, phase, selection, consumables |
| 93–127 | 5 pack card slots | Same encoding as hand cards |
| 128–129 | Shop flags | joker1, joker2, booster, consumable present |

### Action space (6 types)

| Type | Name | Value encoding |
|------|------|----------------|
| 1 | SELECT_CARDS | 8-bit bitmask of hand positions |
| 2 | PLAY_DISCARD | 1 = play, 2 = discard |
| 3 | SHOP_ACTION | 0 = reroll, 1–2 = buy joker, 3 = buy booster, 4 = buy consumable, −1 to −5 = sell joker |
| 4 | USE_CONSUMABLE | 1-based consumable index |
| 5 | PHASE_ACTION | 0 = end shop, 1 = fight blind, 2 = skip, 3 = advance, 4 = sell consumable |
| 6 | REORDER | `[src:4][tgt:4][mode:1][area:1]` — swap or insert in hand/jokers |

## Features

### Poker evaluator
All 12 Balatro hand types: High Card through Flush Five. Handles Wild Cards, Stone Cards, Four Fingers (partial), and cascade logic (Five of a Kind also scores as Four, Three, Pair).

### Scoring engine
```
total = floor((base_chips + card_chips + joker_chips) × (base_mult × card_mult × joker_mult))
```
- Base from hand type + level
- Card enhancements (Bonus +30, Mult +4, Glass ×2, Steel ×1.5, Stone +50)
- Editions (Foil +50, Holo +10, Polychrome ×1.5)
- Joker effects (per-card, per-hand, conditional)

### Implemented jokers (11)

| Joker | Effect |
|-------|--------|
| Joker | +4 Mult |
| Greedy/Lusty/Wrathful/Gluttonous | +3 Mult for Diamond/Heart/Spade/Club |
| The Duo | ×2 Mult if hand contains Pair |
| The Trio | ×3 Mult if hand contains Three of a Kind |
| Blueprint | Copies the joker to its right |
| Burnt Joker | Upgrades first discarded hand each round |
| Sixth Sense | First hand of round: single 6 → destroy + create consumable |
| Hiker | Each scored card permanently gains +4 Chips |

### Consumables (4)

| Consumable | Effect |
|------------|--------|
| Pluto | Level up High Card |
| Mercury | Level up Pair |
| The Empress | Enhance 2 selected cards to Mult |
| The Fool | Copy last used consumable |

### Game systems
- Blind progression: Small → Big → Boss per ante, ante 1–8
- Economy: blind rewards, interest ($1 per $5, cap $5), joker selling
- Shop: 2 jokers + 1 booster + 1 free consumable per round
- Pack opening: nested phase, 3 joker choices
- Hand leveling: Planet card effects
- Deck management: draw, discard, rebuild

## Architecture

```
balatro_sim.lua
├── Sim.ENUMS          All constants (suits, ranks, hands, phases, actions)
├── Sim.RNG            Deterministic LCG (seed → reproducible sequence)
├── Sim.Card           Card constructor and helpers
├── Sim.JOKER_DEFS     Joker registry with apply() functions
├── Sim.CONSUMABLE_DEFS Consumable registry with effect() functions
├── Sim.Eval           Poker hand evaluator (stateless)
├── Sim.Engine         Scoring calculator (stateless)
├── Sim.State          Game state constructor and transitions
├── Sim.Blind          Blind setup and progression
├── Sim.Shop           Shop generation, buying, selling, packs
├── Sim.Obs            Observation encoder (state → 129 floats)
└── Sim.Env            Gymnasium interface (reset, step)
```

Every function takes a `state` table and returns a result or a new state. No global mutable state. No side effects outside of explicit state mutation functions.

## Roadmap

1. **Engine** ← *you are here*
   - Core scoring, poker evaluation, joker system, shop, blinds
   - 11 jokers, 4 consumables, full ante progression

2. **Python bridge** (next)
   - `lupa` wrapper exposing `gymnasium.Env`
   - Observation/action normalization
   - Fidelity testing (Lua vs future Rust)

3. **Rust port**
   - Hot-path evaluator rewritten in Rust
   - JSON state-transition contract for correctness
   - 10–100× speedup target

4. **Full joker library**
   - All 150 jokers from Balatro
   - All tarot, planet, spectral cards
   - All boss blinds with special effects

5. **Training**
   - PPO/IMPALA agent training
   - Reward shaping experiments
   - Strategy discovery and analysis

## Adding a joker

```lua
_reg_joker("j_my_joker", "My Joker", 2, 6, function(ctx, state, joker)
    if ctx.joker_main and ctx.all_hands and ctx.all_hands[7] then  -- Flush
        return { Xmult_mod = 2 }
    end
end)
```

Contexts: `joker_main`, `individual`, `repetition`, `on_discard`, `after_play`, `destroying_card`, `setting_blind`, `end_of_round`.

Return values: `{ mult_mod, chip_mod, Xmult_mod, level_up, destroy, ... }`

## Performance

| Benchmark | Standard Lua | LuaJIT (est.) |
|-----------|-------------|---------------|
| Score calculation | ~91K/sec | ~500K/sec |
| Full cycle (shuffle+draw+score) | ~92K/sec | ~500K/sec |

## License

This is a fan project for research and educational purposes. Balatro is created by [LocalThunk](https://www.playbalatro.com/). All game design credit belongs to the original creator.
