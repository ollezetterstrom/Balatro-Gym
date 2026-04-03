# Balatro-Gym

A headless, high-speed simulation of [Balatro](https://www.playbalatro.com/) for reinforcement learning research. Pure Lua, zero dependencies, deterministic RNG.

> Fan project for research. Balatro is created by [LocalThunk](https://www.playbalatro.com/).

## Quick start

```bash
git clone https://github.com/ollezetterstrom/Balatro-Gym.git
cd Balatro-Gym

# Run the engine (no install needed)
lua -e '_SIM_RUN_TESTS=true' balatro_sim.lua  # 45 self-tests
lua validate.lua                              # 49 scoring tests against real Balatro

# Install for training
pip install -e .                        # gymnasium, lupa, numpy
pip install -e ".[train]"               # + stable-baselines3, tensorboard

# Train an agent
python3 train.py               # train PPO, then compare vs random
```

## Correctness

| Test suite | Tests | Result | Requires |
|-----------|-------|--------|----------|
| `validate.lua` | 49 known-answer scoring tests | 49/49 | — |
| Self-tests | Joker effects, consumables, env integration | 60/60 | — |
| Data comparison | 288 items vs real game source | 0 diffs | game files¹ |

Every poker hand type is evaluated identically to Balatro's actual engine. Every scoring calculation matches known game values. All 150 joker data (names, keys, costs, rarity), 52 consumables, 32 vouchers, 24 tags, and 30 blinds extracted and verified against the real game's `game.lua`.

¹ `scripts/compare_real_game.py` requires a local copy of the Balatro game files (not included in this repo).

## Project structure

```
.
├── balatro_sim.lua          Module loader (loads from src/)
├── balatro_gym.py           Python Gymnasium wrapper (requires lupa)
├── balatro_gym_simple.py    Simplified 247-action wrapper
├── train.py                 PPO training script
├── test_fidelity.py         State-transition recorder for Rust parity
├── test_wrapper.py          CI smoke test for full wrapper
├── test_simple_wrapper.py   CI smoke test for simple wrapper
├── build.py                 Merge src/*.lua into single file
├── translate_jokers.py      Extract joker logic from real game source
├── pyproject.toml           Python packaging (pip install -e .)
├── validate.lua             49 known-answer scoring tests
├── cross_validate.lua       Evaluator parity tests vs real game
├── requirements.txt         Python deps
├── .github/workflows/ci.yml GitHub Actions (Lua + Python tests)
└── src/                     Source modules (edit these)
    ├── 00_header.lua        Sim table + docstring
    ├── 01_enums.lua         Constants, hand stats, defaults
    ├── 02_rng.lua           Deterministic LCG
    ├── 03_cards.lua         Card constructor, deck builder
    ├── 04_jokers.lua        150 joker definitions + behaviors
    ├── 05_consumables.lua   52 consumables (12 planets, 22 tarots, 18 spectrals)
    ├── 06_evaluator.lua     Poker hand evaluator (12 hand types)
    ├── 07_engine.lua        Scoring engine
    ├── 08_state.lua         Game state, draw, discard
    ├── 09_blinds.lua        Blinds + 28 boss blinds
    ├── 10_shop.lua          Shop, packs, economy
    ├── 11_observation.lua   180-float observation encoder
    ├── 12_env.lua           Gymnasium env (reset/step) + helper functions
    ├── 13_test.lua          60 self-tests + random agent
    ├── 14_card_factory.lua  Card creation, rarity rolls, pool culling
    ├── 15_tags.lua          24 tags with 10 trigger types
    └── 16_vouchers.lua      32 vouchers (16 tier-1 + 16 tier-2)
```

## Features

### Poker evaluator
All 12 hand types (High Card through Flush Five). Cascade logic matches real game: Four of a Kind also scores Pair, but Full House does NOT cascade Three of a Kind. Wild Cards, Stone Cards. Four Fingers (4-card flush/straight), Shortcut (skip-rank straights), Splash (all played cards score).

### Scoring
```
total = floor((base_chips + card_chips + joker_chips) × (base_mult × card_mult × joker_mult))
```
Card enhancements, editions, seals, joker effects, hand leveling.

### Jokers (150)

All 150 jokers from the real game with correct names, keys, costs, and rarity. All have working behavior implementations matching the real game's `card.lua` `calculate_joker` function.

Working examples: Joker (+4 Mult), Greedy (+3 per Diamond), The Duo (×2 on Pair), Blueprint (copy neighbor), Hiker (+5 permabuff), Ramen (×2 decaying), Acrobat (×3 last hand), Fibonacci (+8 on A/2/3/5/8), Blackboard (×3 all dark), Supernova (+Mult = times played), Photograph (×2 first face), Bloodstone (1/2 ×1.5 per Heart), and many more.

Use `translate_jokers.py` to get the real game code as a reference for implementing stub jokers:
```bash
python translate_jokers.py --game-dir path/to/Balatro --output joker_stubs.lua
```

### Boss blinds (28)

25 regular bosses + 3 showdown bosses, all from the real game. Includes suit debuffs, card flips, hand restrictions, money effects, and chip multipliers.

### Consumables (52)

**Planets (12):** Pluto (High Card), Mercury (Pair), Venus (Three of a Kind), Earth (Full House), Mars (Four of a Kind), Jupiter (Flush), Saturn (Straight), Neptune (Straight Flush), Uranus (Two Pair), Planet X (Five of a Kind), Ceres (Flush House), Eris (Flush Five)

**Tarots (22):** The Fool, The Magician, The High Priestess, The Emperor, The Hierophant, The Lovers, The Chariot, Strength, The Hermit, Wheel of Fortune, Justice, The Hanged Man, Death, Temperance, The Devil, The Tower, The Star, The Moon, The Sun, Judgement, The World, The Empress

**Spectrals (18):** Familiar, Grim, Incantation, Talisman, Aura, Wraith, Sigil, Ouija, Ectoplasm, Immolate, Ankh, Deja Vu, Hex, Trance, Medium, Cryptid, The Soul, Black Hole

### Card enhancements
Bonus (+30 chips), Mult (+4 mult), Wild (any suit), Glass (×2 mult, 1/4 shatter), Steel (×1.5 mult held), Stone (+50 chips), Gold (+$3 held), Lucky (1/5 +20 mult, 1/15 +$20)

### Editions
Foil (+50 chips), Holographic (+10 mult), Polychrome (×1.5 mult), Negative (+1 joker slot)

### Seals
Red (re-trigger), Gold (+$3 on score), Blue (create planet at round end), Purple (create tarot on discard)

### Game systems
- Blinds: Small → Big → Boss, ante 1–8, 28 boss blinds (25 regular + 3 showdown)
- Economy: blind rewards, interest, joker selling, debt support (Credit Card)
- Shop: weighted card type selection (71% Joker, 14% Tarot, 14% Planet), 2 joker slots + 2 boosters + 1 voucher
- Pricing: exact formula with edition markups (foil +2, holo +3, poly/neg +5), discounts, inflation
- Editions: rolled per card (0.3% neg, 0.3% poly, 1.4% holo, 2.0% foil)
- Stickers: eternal/perishable/rental for stake support
- Reroll: base=1 + incrementing cost, free reroll support (Chaos)
- Interest: min(floor($/5), cap/5) earned at round end
- Packs: nested phase, weighted pack selection, first shop always Buffoon
- Tags: 24 tags with 10 trigger types (immediate, new_blind_choice, store_joker_create, eval, voucher_add, tag_add, round_start_bonus, shop_start, shop_final_pass)
- Vouchers: 32 vouchers (16 tier-1 + 16 tier-2) with prerequisite chains
- Deck management: draw, discard, rebuild
- Context hooks: setting_blind, selling_card, open_booster, ending_shop, first_hand_drawn, after_play, round_end, cards_destroyed, pre_discard, on_discard, using_consumeable, skipping_booster, skip_blind, game_over, debuffed_hand

## Observation (180 floats, 1-indexed Lua)

| Index | Feature | Encoding |
|-------|---------|----------|
| 1–56 | 8 hand slots | `[rank/14, suit/4, enhance/8, edition/4, seal/4, debuffed, has_card]` |
| 57–71 | 5 joker slots | `[id/pool, edition/4, has_joker]` |
| 72–81 | 10 global | chips%, $, hands, discards, ante, round, blind_beaten, deck%, total_chips%, hands_played |
| 82–93 | 12 hand levels | log-scaled, capped at 1.0 |
| 94–96 | Phase | one-hot: SELECTING, SHOP, PACK_OPEN |
| 97 | Selection count | / 8 |
| 98–101 | 2 consumable slots | `[id/pool, has_consumable]` |
| 102 | Pack open flag | 0 or 1 |
| 103–132 | 5 pack slots | same encoding as hand cards |
| 133–136 | Shop flags | joker1, joker2, booster, consumable present |
| 137–138 | Counts | joker count/5, cons count/2 |
| 139–151 | Deck ranks | 13 rank counts (2–Ace) / 4 each |
| 152–155 | Deck suits | 4 suit counts / 13 each |
| 156 | Boss active | 0 or 1 |
| 157 | Boss chip mult | normalized boss multiplier |
| 158–160 | Blind states | 3 (Small/Big/Boss: 0=pending, 0.5=skipped, 1=done) |
| 161–180 | Spare | reserved for future use |

## Action space

| # | Name | Value |
|---|------|-------|
| 1 | SELECT_CARDS | 8-bit bitmask |
| 2 | PLAY_DISCARD | 1 = play, 2 = discard |
| 3 | SHOP_ACTION | 0=reroll, 1-2=buy joker, 3=booster, 4=consumable, -1~-5=sell |
| 4 | USE_CONSUMABLE | index |
| 5 | PHASE_ACTION | 0=end shop, 1=fight, 2=skip, 3=advance |
| 6 | REORDER | `[src:4][tgt:4][mode:1][area:1]` |

## Adding a joker

Edit `src/04_jokers.lua`:

```lua
Sim._reg_joker("j_my_joker", "My Joker", 2, 6, function(ctx, st, jk)
    if ctx.joker_main and ctx.all_hands and ctx.all_hands[E.HAND_TYPE.FLUSH] then
        return { Xmult_mod = 2 }
    end
end)
```

Run `lua validate.lua` to verify scoring still works.

## Development workflow

Edit files in `src/`, then test:

```bash
lua validate.lua                        # scoring correctness (49 tests)
lua -e '_SIM_RUN_TESTS=true' balatro_sim.lua  # self-tests (45 tests)
```

For distribution (single file):

```bash
python3 build.py merge      # src/*.lua -> balatro_sim.lua
```

CI runs automatically on push via GitHub Actions (`.github/workflows/ci.yml`).

## Python bridge

```bash
pip install -e .              # or: pip install -r requirements.txt
python balatro_gym.py         # quick test
```

```python
import gymnasium as gym
import balatro_gym

env = gym.make("BalatroGym-v0")
obs, info = env.reset(seed=42)
obs, reward, done, trunc, info = env.step((1, 31))
```

## Fidelity testing (for Rust port)

```bash
pip install lupa
python test_fidelity.py --steps 1000 --output trajectories.json
```

Saves `(state, action, next_state, reward)` tuples. When building the Rust port, load this JSON and verify identical output.

## Performance

| Benchmark | Standard Lua | LuaJIT (est.) |
|-----------|-------------|---------------|
| Score calculation | ~91K/sec | ~500K/sec |
| Full cycle (shuffle+draw+score) | ~92K/sec | ~500K/sec |

## Roadmap

1. **Engine** — Core scoring, 150 jokers, 28 boss blinds, shop, packs, consumables, tags, vouchers ✅
2. **Python bridge** — lupa wrapper, Gymnasium env, pip install, CI ✅
3. **Full joker behaviors** — All 150 jokers implemented with behavior matching real game ✅
4. **1:1 data verification** — All joker/consumable/voucher/tag/blind data verified against real game source ✅
5. **Rust port** — Hot-path evaluator, JSON state contract
6. **Training** — PPO experiments, reward shaping

See [roadmap.md](roadmap.md).

## License

Fan project for research. Balatro is created by [LocalThunk](https://www.playbalatro.com/). No copyrighted game assets included.
