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
lua cross_validate.lua 1000                   # 1019 hand evaluations against real game source

# Train an agent (requires pip install)
pip install lupa gymnasium numpy stable-baselines3
python3 train.py               # train PPO, then compare vs random
```

## Correctness

| Test suite | Tests | Result |
|-----------|-------|--------|
| `validate.lua` | 49 known-answer scoring tests | 49/49 |
| `cross_validate.lua` | 1019 hand evaluations vs real Balatro source | 1019/1019 |
| Self-tests | Joker effects, consumables, env integration | 45/45 |

Every poker hand type is evaluated identically to Balatro's actual engine. Every scoring calculation matches known game values. All joker data (names, costs, rarity) extracted from the real game's `game.lua`.

## Project structure

```
.
├── balatro_sim.lua          Module loader (40 lines, loads from src/)
├── balatro_gym.py           Python Gymnasium wrapper (requires lupa)
├── balatro_gym_simple.py    Simplified 247-action wrapper
├── train.py                 PPO training script
├── test_fidelity.py         State-transition recorder for Rust parity
├── build.py                 Merge src/*.lua into single file
├── validate.lua             49 known-answer scoring tests
├── cross_validate.lua       Evaluator parity tests vs real game
├── requirements.txt         Python deps (gymnasium, lupa, numpy)
└── src/                     Source modules (edit these)
    ├── 00_header.lua        Sim table + docstring
    ├── 01_enums.lua         Constants, hand stats, defaults
    ├── 02_rng.lua           Deterministic LCG
    ├── 03_cards.lua         Card constructor, deck builder
    ├── 04_jokers.lua        147 joker definitions + behaviors
    ├── 05_consumables.lua   49 consumables (12 planets, 21 tarots, 16 spectrals)
    ├── 06_evaluator.lua     Poker hand evaluator (12 hand types)
    ├── 07_engine.lua        Scoring engine
    ├── 08_state.lua         Game state, draw, discard
    ├── 09_blinds.lua        Blinds + 8 boss blinds
    ├── 10_shop.lua          Shop, packs, economy
    ├── 11_observation.lua   129-float observation encoder
    ├── 12_env.lua           Gymnasium env (reset/step)
    └── 13_test.lua          45 self-tests + random agent
```

## Features

### Poker evaluator
All 12 hand types (High Card through Flush Five). Cascade logic matches real game: Four of a Kind also scores Pair, but Full House does NOT cascade Three of a Kind. Wild Cards, Stone Cards.

### Scoring
```
total = floor((base_chips + card_chips + joker_chips) × (base_mult × card_mult × joker_mult))
```
Card enhancements, editions, seals, joker effects, hand leveling.

### Jokers (147)

147 jokers from the real game with correct names, costs, and rarity. ~50 have working scoring behavior (suit bonuses, type bonuses, Xmult, chip scaling, held-in-hand effects). Remaining jokers register with correct data but have `-- TODO` behavior stubs.

Working examples: Joker (+4 Mult), Greedy (+3 per Diamond), The Duo (×2 on Pair), Blueprint (copy neighbor), Hiker (+5 permabuff), Ramen (×2 decaying), Acrobat (×3 last hand), Fibonacci (+8 on A/2/3/5/8), Blackboard (×3 all dark), Supernova (+Mult = times played), and many more.

### Boss blinds (8)

| Boss | Effect |
|------|--------|
| The Wall | 2× chip requirement |
| The Arm | Decreases played hand's level by 1 |
| The Water | Start with 0 discards |
| The Manacle | Hand size reduced by 1 |
| The Needle | Only 1 hand this round |
| The Club | All Club cards debuffed |
| The Goad | All Spade cards debuffed |
| The Window | All Diamond cards debuffed |

### Consumables (49)

**Planets (12):** Pluto (High Card), Mercury (Pair), Venus (Three of a Kind), Earth (Full House), Mars (Four of a Kind), Jupiter (Flush), Saturn (Straight), Neptune (Straight Flush), Uranus (Two Pair), Planet X (Five of a Kind), Ceres (Flush House), Eris (Flush Five)

**Tarots (21):** The Fool, The Magician, The High Priestess, The Emperor, The Hierophant, The Lovers, The Chariot, Strength, The Hermit, Wheel of Fortune, Justice, The Hanged Man, Death, Temperance, The Devil, The Tower, The Star, The Moon, The Sun, The World, The Empress

**Spectrals (16):** Familiar, Grim, Incantation, Talisman, Aura, Wraith, Sigil, Ouija, Ectoplasm, Immolate, Ankh, Deja Vu, Hex, Trance, Medium, Cryptid

### Card enhancements
Bonus (+30 chips), Mult (+4 mult), Wild (any suit), Glass (×2 mult, 1/4 shatter), Steel (×1.5 mult held), Stone (+50 chips), Gold (+$3 held), Lucky (1/5 +20 mult, 1/15 +$20)

### Editions
Foil (+50 chips), Holographic (+10 mult), Polychrome (×1.5 mult), Negative (+1 joker slot)

### Seals
Red (re-trigger), Gold (+$3 on score), Blue (create planet at round end), Purple (create tarot on discard)

### Game systems
- Blinds: Small → Big → Boss, ante 1–8
- Economy: blind rewards, interest, joker selling
- Shop: 2 jokers + booster + consumable
- Packs: nested phase, 3 joker choices
- Deck management: draw, discard, rebuild

## Observation (129 floats, 1-indexed Lua)

| Index | Feature | Encoding |
|-------|---------|----------|
| 1–48 | 8 hand slots | `[rank/14, suit/4, enhance/8, edition/4, seal/4, has_card]` |
| 49–63 | 5 joker slots | `[id/pool, edition/4, has_joker]` |
| 64–71 | 8 global | chips%, $, hands, discards, ante, round, blind_beaten, deck% |
| 72–83 | 12 hand levels | log-scaled, capped at 1.0 |
| 84–86 | Phase | one-hot: SELECTING, SHOP, PACK_OPEN |
| 87 | Selection count | / 8 |
| 88–91 | 2 consumable slots | `[id/pool, has_consumable]` |
| 92 | Pack open flag | 0 or 1 |
| 93–122 | 5 pack slots | same encoding as hand cards |
| 123–126 | Shop flags | joker1, joker2, booster, consumable present |
| 127–129 | Counts | joker count/5, cons count/2, spare |

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
lua validate.lua                        # scoring correctness
lua -e '_SIM_RUN_TESTS=true' balatro_sim.lua  # self-tests
```

For distribution (single file):

```bash
python3 build.py merge      # src/*.lua → balatro_sim.lua
```

## Python bridge

```bash
pip install -r requirements.txt
python balatro_gym.py       # quick test
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

1. **Engine** — Core scoring, 147 jokers, 8 boss blinds, shop, packs
2. **Python bridge** — lupa wrapper, Gymnasium env
3. **Full joker behaviors** — Implement remaining ~100 TODO jokers
4. **More bosses** — 25+ boss blinds from real game
5. **Rust port** — Hot-path evaluator, JSON state contract
6. **Training** — PPO experiments, reward shaping

See [roadmap.md](roadmap.md).

## License

Fan project for research. Balatro is created by [LocalThunk](https://www.playbalatro.com/). No copyrighted game assets included.
