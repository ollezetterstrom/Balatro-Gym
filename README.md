# Balatro-Gym

A headless, high-speed simulation of [Balatro](https://www.playbalatro.com/) for reinforcement learning research. Pure Lua, zero dependencies, deterministic RNG.

> [!NOTE]
> This is a fan project. Balatro is created by [LocalThunk](https://www.playbalatro.com/). All game design credit belongs to the original creator.

## What is this?

Balatro is a poker-themed roguelike deckbuilder where you score poker hands against escalating chip thresholds, augmented by Jokers, consumables, and deck manipulation. This project reimplements its core mechanics — scoring, poker evaluation, joker effects, shop, blinds, ante progression — as a fast, deterministic simulation for training AI agents.

**Design goals:**

| Goal | How |
|------|-----|
| **Fast** | ~90K+ score calculations/sec in standard Lua. No allocations in hot path. |
| **Deterministic** | LCG seeded once. Same seed = same game, every platform. |
| **Rust-ready** | Stateless functions, struct-like tables, explicit enums, no globals. |
| **RL-compatible** | 129-float observation vector, hierarchical action space, Gymnasium API. |

## Quick start

```bash
git clone https://github.com/ollezetterstrom/Balatro-Gym.git
cd Balatro-Gym
lua balatro_sim.lua
```

Runs 13 self-tests and a random agent that plays through an entire ante. No dependencies beyond Lua 5.1+ or LuaJIT.

## Usage

### As a library

```lua
local Sim = dofile("balatro_sim.lua")

-- Create a game with starting jokers
local state = Sim.new_game({
    seed = "MYSEED",
    ante = 1,
    jokers = {
        {id=1, edition=0, eternal=false, uid=1},  -- Joker (+4 Mult)
    },
})

-- Play the first 5 cards
local result = Sim.play(state, {1, 2, 3, 4, 5})
print(result.hand_name)  -- e.g. "Pair"
print(result.total)      -- e.g. 192
```

### Gymnasium interface

```lua
local obs, info = Sim.Env.reset("SEED")

-- Step: select 5 cards, then play them
local mask = (1<<0)|(1<<1)|(1<<2)|(1<<3)|(1<<4)  -- select cards 1-5
obs, reward, done = Sim.Env.step(state, 1, mask)   -- SELECT_CARDS
obs, reward, done = Sim.Env.step(state, 2, 1)      -- PLAY
```

## Observation space

129 floats encoding the full game state:

```
Index    Feature                          Encoding
─────    ───────────────────────────────  ──────────────────────────────────────
0–47     8 hand card slots (×6 each)     [rank/14, suit/4, enhance/8, edition/4,
                                          seal/4, has_card]
48–62    5 joker slots (×3 each)         [id/pool_size, edition/4, has_joker]
63–70    Core metrics                     chips%, $, hands_left, discards_left,
                                          ante, round, blind_beaten, deck/52
71–82    12 hand levels                   log₂(level+1) / 5
83–85    Phase one-hot                    [selecting, shop, pack_open]
86       Selection count                  count/8
87–88    2 consumable slots (×2 each)     [id/pool, has_consumable]
89       Pack open flag                   0 or 1
90–124   5 pack card slots (×6 each)     Same as hand cards
125–128  Shop flags                       [joker1, joker2, booster, consumable]
129–129  Counts                           joker_count/5, cons_count/2, round $
```

## Action space

6 action types, each with a `value` encoding:

| # | Name | Value | Description |
|---|------|-------|-------------|
| 1 | `SELECT_CARDS` | 8-bit bitmask | Toggle card selection in hand |
| 2 | `PLAY_DISCARD` | 1 or 2 | 1 = play selected, 2 = discard selected |
| 3 | `SHOP_ACTION` | see below | Buy/sell/reroll in shop |
| 4 | `USE_CONSUMABLE` | index (1-based) | Activate a consumable from your area |
| 5 | `PHASE_ACTION` | see below | Phase transitions |
| 6 | `REORDER` | encoded int | Swap or insert cards/jokers |

**SHOP_ACTION values:**
`0` = reroll · `1` = buy joker slot 1 · `2` = buy joker slot 2 · `3` = buy booster · `4` = buy consumable · `-1` to `-5` = sell joker at index

**PHASE_ACTION values:**
`0` = end shop · `1` = fight blind · `2` = skip blind · `3` = advance (after beating blind) · `4` = sell consumable

**REORDER encoding:**
```
[src:4 bits][tgt:4 bits][mode:1 bit][area:1 bit]
  mode: 0 = swap, 1 = insert
  area: 0 = hand cards, 1 = jokers
```

## Features

### Poker evaluator

All 12 Balatro hand types: High Card through Flush Five. Cascade logic (Five of a Kind also scores as Four, Three, Pair). Handles Wild Cards, Stone Cards.

### Scoring

```
total = floor((base_chips + card_chips + joker_chips) × (base_mult × card_mult × joker_mult))
```

- **Base:** hand type + level (leveled by Planet cards)
- **Card enhancements:** Bonus +30, Mult +4, Glass ×2, Steel ×1.5, Stone +50
- **Editions:** Foil +50, Holo +10, Polychrome ×1.5
- **Joker effects:** per-card, per-hand, conditional, copy (Blueprint)

### Jokers (11)

| Joker | Rarity | Effect |
|-------|--------|--------|
| Joker | Common | +4 Mult |
| Greedy Joker | Common | +3 Mult if hand contains a Diamond |
| Lusty Joker | Common | +3 Mult if hand contains a Heart |
| Wrathful Joker | Common | +3 Mult if hand contains a Spade |
| Gluttonous Joker | Common | +3 Mult if hand contains a Club |
| The Duo | Rare | ×2 Mult if hand contains Pair |
| The Trio | Rare | ×3 Mult if hand contains Three of a Kind |
| Blueprint | Rare | Copies the joker to its right |
| Burnt Joker | Rare | First discard each round levels up that hand |
| Sixth Sense | Uncommon | First hand: destroy a single 6, create a Spectral |
| Hiker | Common | Each scored card permanently gains +4 Chips |

### Consumables (4)

| Consumable | Set | Effect |
|------------|-----|--------|
| Pluto | Planet | Level up High Card |
| Mercury | Planet | Level up Pair |
| The Empress | Tarot | Enhance 2 selected cards to Mult |
| The Fool | Tarot | Copy the last used consumable |

### Game systems

- **Blinds:** Small → Big → Boss per ante, ante 1–8
- **Economy:** blind rewards, interest ($1 per $5, cap $5), joker selling
- **Shop:** 2 jokers + 1 booster + 1 free consumable per round
- **Packs:** nested phase, 3 joker choices, returns to shop after
- **Deck management:** draw, discard, rebuild between rounds

## Architecture

```
balatro_sim.lua          Single file, 1559 lines, zero dependencies
├── Sim.ENUMS            Constants: suits, ranks, hands, phases, actions
├── Sim.RNG              Deterministic LCG (seed → reproducible sequence)
├── Sim.Card             Card constructor, deck builder, chip calculator
├── Sim.JOKER_DEFS       Joker registry with apply(ctx, state) functions
├── Sim.CONSUMABLE_DEFS  Consumable registry with effect(ctx, state) functions
├── Sim.Eval             Poker hand evaluator (stateless, pure)
├── Sim.Engine           Scoring calculator (stateless, pure)
├── Sim.State            Game state, draw, discard, level_up, add_joker
├── Sim.Blind            Blind setup, chip thresholds, ante progression
├── Sim.Shop             Generation, buying, selling, packs
├── Sim.Obs              State → 129 float vector encoder
└── Sim.Env              Gymnasium interface: reset(), step()
```

Every function takes a `state` table and returns results. No global mutable state. No side effects outside explicit mutation functions. Designed for mechanical translation to Rust.

## Adding content

### New joker

```lua
_reg_joker("j_my_joker", "My Joker", 2, 6, function(ctx, state, joker)
    if ctx.joker_main and ctx.all_hands and ctx.all_hands[7] then  -- Flush
        return { Xmult_mod = 2 }
    end
end)
```

**Context triggers:** `joker_main`, `individual`, `repetition`, `on_discard`, `after_play`, `destroying_card`, `setting_blind`, `end_of_round`

**Return effects:** `{ mult_mod, chip_mod, Xmult_mod, level_up, destroy, ... }`

### New consumable

```lua
_reg_cons("c_my_planet", "My Planet", "Planet", function(ctx, state)
    Sim.State.level_up(state, Sim.ENUMS.HAND_TYPE.STRAIGHT, 1)
    return { level_up = Sim.ENUMS.HAND_TYPE.STRAIGHT }
end)
```

## Performance

| Benchmark | Standard Lua | LuaJIT (est.) |
|-----------|-------------|---------------|
| Score calculation | ~91K/sec | ~500K/sec |
| Full cycle (shuffle+draw+score) | ~92K/sec | ~500K/sec |

## Roadmap

1. **Engine** — Core scoring, poker evaluation, joker system, shop, blinds ✓
2. **Python bridge** — `lupa` wrapper, `gymnasium.Env`, fidelity testing
3. **Rust port** — Hot-path evaluator, JSON state contract, 10–100× speedup
4. **Full joker library** — All 150 jokers, tarots, planets, spectrals, boss blinds
5. **Training** — PPO/IMPALA experiments, reward shaping, strategy discovery

See [roadmap.md](roadmap.md) for detailed next steps.

## Contributing

The codebase is a single file (`balatro_sim.lua`). To add a feature:

1. Find the relevant `SECTION` header
2. Follow the existing patterns (explicit enums, stateless functions, `apply`/`effect` callbacks)
3. Add a test in the `SELF-TEST` section
4. Run `lua balatro_sim.lua` — all tests must pass

## License

Fan project for research and educational purposes. Balatro is created by [LocalThunk](https://www.playbalatro.com/). This project does not contain any copyrighted game assets.
