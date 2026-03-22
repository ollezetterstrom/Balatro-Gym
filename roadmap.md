# Balatro-Gym Roadmap

## Current state

A working headless Balatro simulation engine with a Gymnasium wrapper, ready for RL training.

**What's done:**
- [x] Core scoring engine (chips × mult, all 12 hand types)
- [x] Deterministic RNG (LCG, same seed = same game everywhere)
- [x] 21 jokers with full scoring integration (Blueprint copy, Hiker permabuff, Fibonacci per-card, etc.)
- [x] 8 boss blinds with debuff/setup effects (The Wall, The Arm, The Water, etc.)
- [x] 4 consumables (Pluto, Mercury, The Empress, The Fool)
- [x] Shop system (jokers, boosters, consumables, reroll, sell)
- [x] Pack opening phase (nested state, 3 joker choices)
- [x] Economy (blind rewards, interest, joker selling)
- [x] Ante 1–8 progression with win condition
- [x] 129-float observation vector
- [x] 6-type hierarchical action space (select, play, shop, consumable, phase, reorder)
- [x] Card debuff system (boss blind suit debuffs)
- [x] Gymnasium Python wrapper (`balatro_gym.py`)
- [x] Fidelity tester for Rust port (`test_fidelity.py`)
- [x] Module split (14 files in `src/` + build script)
- [x] 13 self-tests passing
- [x] ~92K score calculations/sec in standard Lua

---

## Phase 1: Get training running (NOW)

**Goal:** PPO agent beats a random agent within 10 minutes of training.

- [ ] Test the Python bridge (`balatro_gym.py`) with lupa installed
- [ ] Fix any Lua↔Python data conversion issues
- [ ] Write a minimal training script (PPO via StableBaselines3)
- [ ] Run 100K training steps, measure if agent improves over random
- [ ] If lupa is too slow → profile and identify bottleneck
- [ ] Graph the learning curve (reward vs steps)

**Why this matters:** Proves the architecture works. If the agent can't learn, the observation/action space needs redesigning before investing in more content.

---

## Phase 2: Content completeness

**Goal:** Match the full game's joker/card library (at least the common ones).

- [ ] Missing card effects:
  - [ ] Steel (×1.5 mult when held in hand)
  - [ ] Gold (+3 money when held in hand)
  - [ ] Lucky (20% chance +20 mult, 1/5 chance +$20)
  - [ ] Wild (counts as any suit for flushes)
  - [ ] Glass destruction (1/4 chance to shatter)
  - [ ] Red seal (re-trigger scoring)
  - [ ] Gold seal (+3 money when scored)
- [ ] Missing jokers (next batch):
  - [ ] Joker Stencil bonus fix (currently works)
  - [ ] Delayed Gratification (+2 per discard if none used)
  - [ ] Supernova (+mult = times played this hand type)
  - [ ] Ride the Bus (+1 mult per hand without face cards, reset on face)
  - [ ] Blackboard (×3 if all remaining hand cards are Spade/Club)
  - [ ] Ramen (×2 mult, -0.01 per card drawn)
  - [ ] Acrobat (×3 on last hand of round)
  - [ ] Sock and Buskin (re-trigger all face cards)
- [ ] Missing tarot cards (18 remaining):
  - [ ] The Magician (Lucky enhancement)
  - [ ] The High Priestess (create 2 planets)
  - [ ] The Emperor (create 2 tarots)
  - [ ] The Hierophant (Bonus enhancement)
  - [ ] The Lovers (Wild enhancement)
  - [ ] The Chariot (Steel enhancement)
  - [ ] Strength (+1 rank to 2 cards)
  - [ ] The Hermit (double money, max $20)
  - [ ] Wheel of Fortune (25% chance edition)
  - [ ] Justice (Glass enhancement)
  - [ ] The Hanged Man (destroy 2 cards)
  - [ ] Death (copy 1 card to another)
  - [ ] Temperance (sell value of all jokers)
  - [ ] The Devil (Gold enhancement)
  - [ ] The Tower (Stone enhancement)
  - [ ] The Star/Moon/Sun/World (change suit)
- [ ] Missing planet cards (10 remaining):
  - [ ] Venus (Three of a Kind), Earth (Full House), Mars (Four of a Kind),
  - [ ] Jupiter (Flush), Saturn (Straight), Neptune (Straight Flush),
  - [ ] Uranus (Two Pair), Planet X (Five of a Kind),
  - [ ] Ceres (Flush House), Eris (Flush Five)
- [ ] Spectral cards:
  - [ ] Familiar, Grim, Incantation, Talisman, Aura, Wraith, Sigil, Ouija, Ectoplasm, Immolate, Ankh, Deja Vu, Hex, Trance, Medium, Cryptid
- [ ] Boss blind rotation (don't repeat until all seen)
- [ ] Interest cap voucher ($20)
- [ ] More deck types (Red, Blue, Yellow, Green, Black, Abandoned, Checkered, Zodiac, Plasma)

---

## Phase 3: Training experiments

**Goal:** Understand what makes Balatro learnable.

- [ ] Compare simplified env (play only, no shop) vs full env (shop decisions)
- [ ] Experiment with action space:
  - [ ] Flat discrete (too large?) vs hierarchical (current)
  - [ ] Action masking (only legal actions)
- [ ] Experiment with reward shaping:
  - [ ] Sparse (win/lose only)
  - [ ] Dense (log(chips) per hand)
  - [ ] Shaped (efficiency bonus, economy bonus)
- [ ] Experiment with observation:
  - [ ] Current (129 floats)
  - [ ] Card embeddings (neural card representation)
  - [ ] Include full discard pile state
- [ ] Try different algorithms:
  - [ ] PPO (baseline)
  - [ ] SAC (continuous action space variant)
  - [ ] IMPALA (distributed)
  - [ ] DreamerV3 (model-based)
- [ ] Publish results (reward curves, win rates by ante)

---

## Phase 4: Rust port

**Goal:** 10-100× speedup over Lua for training at scale.

- [ ] Port `Evaluator` (poker hand detection) to Rust
- [ ] Port `Engine` (scoring calculation) to Rust
- [ ] Port `State` (game state transitions) to Rust
- [ ] Keep joker definitions in Lua/JSON (load at runtime)
- [ ] Use `test_fidelity.py` output as correctness contract:
  - [ ] Run 10,000 random transitions in Lua
  - [ ] Save to JSON
  - [ ] Run same transitions in Rust
  - [ ] Verify identical (obs, reward, done) output
- [ ] Expose Rust engine via PyO3 (Python native module)
- [ ] Benchmark: Rust vs Lua vs Python
- [ ] Target: 1M+ steps/sec for GPU training

---

## Phase 5: Scale

**Goal:** Train a competitive Balatro agent.

- [ ] Distributed training (Ray/RLlib or CleanRL)
- [ ] Full 150-joker library
- [ ] All boss blinds with complete effects
- [ ] All tarot/planet/spectral cards
- [ ] All 15 deck types
- [ ] Stake system (difficulty levels 1-8)
- [ ] Challenge mode support
- [ ] Save/load trained models
- [ ] Agent visualization (replay a game step by step)
- [ ] Leaderboard: best ante reached, highest score, fastest win

---

## Comparison with cassiusfive/balatro-gym

| | Us | Them |
|---|---|---|
| Language | Lua (portable, fast) | Python only |
| Dependencies | zero | numpy, gymnasium, poetry |
| Gym wrapper | ✓ (untested) | ✓ (tested) |
| Jokers | 21 | stubs |
| Boss blinds | 8 | stubs |
| Full game loop | ✓ (shop, packs, blinds) | simplified |
| RNG | deterministic | platform-dependent |
| Rust port | planned | not planned |
| Speed | ~92K/sec (Lua), ~500K/sec (LuaJIT) | ~10K/sec (Python) |
| Stars | new | 38 |

**Our advantage:** We own the engine. They wrapped an existing game. Our engine is faster, more complete, deterministic, and designed for Rust porting. They're ahead on tested Python integration.
