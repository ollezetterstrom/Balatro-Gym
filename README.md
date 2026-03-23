# Balatro-Gym

A headless, high-speed simulation of [Balatro](https://www.playbalatro.com/) for reinforcement learning research. Pure Lua, zero dependencies, deterministic RNG.

> [!NOTE]
> Fan project for research. Balatro is created by [LocalThunk](https://www.playbalatro.com/).

## Quick start

```bash
git clone https://github.com/ollezetterstrom/Balatro-Gym.git
cd Balatro-Gym

# Run the engine (no install needed)
lua balatro_sim.lua            # 13 self-tests
lua validate.lua               # 49 scoring tests against real Balatro
lua cross_validate.lua 1000    # 1000 hand evaluations against real game source

# Train an agent (requires pip install)
pip install lupa gymnasium numpy stable-baselines3
python3 train.py               # train PPO, then compare vs random
```

## Results

PPO agent trained for 500K steps, tested against random baseline:

| Agent | Mean Reward | Max Reward | Beats blinds? |
|-------|------------|------------|---------------|
| Random | -89.9 | -79.9 | Never |
| **Trained** | **-9.5** | **+20.1** | **Frequently** |

**+77.5 reward improvement** over random. Agent learns to play valid poker hands, beat blinds, and progress through ante 1.

Training speed: ~2500 steps/sec (500K steps in ~3 minutes).

## Correctness

| Test suite | Tests | Result |
|-----------|-------|--------|
| `validate.lua` | 49 known-answer scoring tests | 49/49 ✓ |
| `cross_validate.lua` | 5019 hand evaluations vs real Balatro source | 5019/5019 ✓ |
| `balatro_sim.lua` | Self-consistency tests | 13/13 ✓ |

Every poker hand type is evaluated identically to Balatro's actual engine. Every scoring calculation matches known game values.

## Project structure

```
.
├── balatro_sim.lua          Single-file distribution (1789 lines, zero deps)
├── balatro_sim_dev.lua      Dev loader (dofile's all src/*.lua)
├── balatro_gym.py           Python Gymnasium wrapper (requires lupa)
├── test_fidelity.py         State-transition recorder for Rust parity
├── build.py                 Split/merge tool
├── requirements.txt         Python deps (gymnasium, lupa, numpy)
├── roadmap.md               Project roadmap
└── src/                     Source modules (edit these)
    ├── 00_header.lua        Sim = {}
    ├── 01_enums.lua         Constants, hand stats, defaults
    ├── 02_rng.lua           Deterministic LCG
    ├── 03_cards.lua         Card constructor, deck builder
    ├── 04_jokers.lua        All 21 joker definitions
    ├── 05_consumables.lua   Consumables + advanced jokers
    ├── 06_evaluator.lua     Poker hand evaluator (12 hand types)
    ├── 07_engine.lua        Scoring engine
    ├── 08_state.lua         Game state, draw, discard
    ├── 09_blinds.lua        Blinds + 8 boss blinds
    ├── 10_shop.lua          Shop, packs, economy
    ├── 11_observation.lua   129-float observation encoder
    ├── 12_env.lua           Gymnasium env (reset/step)
    └── 13_test.lua          Self-tests + random agent
```

## Development workflow

Edit files in `src/`, then test with the dev loader:

```bash
lua balatro_sim_dev.lua     # loads all modules, runs tests
```

For distribution (single file):

```bash
python3 build.py merge      # src/*.lua → balatro_sim.lua
python3 build.py split      # balatro_sim.lua → src/*.lua (reverse)
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

## Features

### Poker evaluator
All 12 hand types (High Card → Flush Five). Cascade logic (Five of a Kind also scores as Four, Three, Pair). Wild Cards, Stone Cards.

### Scoring
```
total = floor((base_chips + card_chips + joker_chips) × (base_mult × card_mult × joker_mult))
```
Card enhancements, editions, seals, joker effects, hand leveling.

### Jokers (21)

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
| Burnt Joker | Rare | First discard levels up that hand |
| Joker Stencil | Uncommon | ×(1 + empty slots) Mult |
| Banner | Common | +30 Chips per remaining discard |
| Mystic Summit | Common | +15 Mult when discards = 0 |
| Misprint | Common | +0-23 Mult randomly |
| Fibonacci | Uncommon | +8 Mult per played Ace/2/3/5/8 |
| Scary Face | Common | +30 Chips per played face card |
| Even Steven | Common | +4 Mult per played even card |
| Odd Todd | Common | +31 Chips per played odd card |
| Scholar | Common | +20 Chips +4 Mult per played Ace |
| Sly Joker | Common | +50 Chips |
| Sixth Sense | Uncommon | First hand: single 6 → destroy + Spectral |
| Hiker | Common | Each scored card permanently gains +4 Chips |

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

### Consumables (4)

| Consumable | Set | Effect |
|------------|-----|--------|
| Pluto | Planet | Level up High Card |
| Mercury | Planet | Level up Pair |
| The Empress | Tarot | Enhance 2 selected cards to Mult |
| The Fool | Tarot | Copy the last used consumable |

### Game systems
- Blinds: Small → Big → Boss, ante 1–8
- Economy: blind rewards, interest, joker selling
- Shop: 2 jokers + booster + consumable
- Packs: nested phase, 3 joker choices
- Deck management: draw, discard, rebuild

## Observation (129 floats)

| Index | Feature | Encoding |
|-------|---------|----------|
| 0–47 | 8 hand slots | `[rank/14, suit/4, enhance/8, edition/4, seal/4, has_card]` |
| 48–62 | 5 joker slots | `[id/pool, edition/4, has_joker]` |
| 63–92 | 30 global | chips%, $, hands, discards, ante, 12 levels, phase, etc. |
| 93–127 | 5 pack slots | Same encoding as hand cards |
| 128–129 | Shop flags | items present, counts |

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
_reg_joker("j_my_joker", "My Joker", 2, 6, function(ctx, state, joker)
    if ctx.joker_main and ctx.all_hands and ctx.all_hands[7] then  -- Flush
        return { Xmult_mod = 2 }
    end
end)
```

Run `lua balatro_sim_dev.lua` to verify. Then `python3 build.py merge`.

## Performance

| Benchmark | Standard Lua | LuaJIT (est.) |
|-----------|-------------|---------------|
| Score calculation | ~91K/sec | ~500K/sec |
| Full cycle (shuffle+draw+score) | ~92K/sec | ~500K/sec |

## Roadmap

1. **Engine** — Core scoring, 21 jokers, 8 boss blinds, shop, packs ✓
2. **Python bridge** — lupa wrapper, Gymnasium env ✓
3. **Rust port** — Hot-path evaluator, JSON state contract
4. **Full joker library** — All 150 jokers, tarots, planets, spectrals
5. **Training** — PPO experiments, reward shaping

See [roadmap.md](roadmap.md).

## License

Fan project for research. Balatro is created by [LocalThunk](https://www.playbalatro.com/). No copyrighted game assets included.
