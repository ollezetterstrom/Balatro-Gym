# Balatro-Gym Roadmap

## Current state

A working headless Balatro simulation engine with a Gymnasium wrapper, ready for RL training.

**What's done:**
- [x] Core scoring engine (chips × mult, all 12 hand types)
- [x] Deterministic RNG (LCG, same seed = same game everywhere)
- [x] 147 jokers registered with correct data from real game; ~50 with full scoring behavior (Blueprint copy, Hiker permabuff, Sock and Buskin re-trigger, etc.)
- [x] 8 boss blinds with debuff/setup effects (The Wall, The Arm, The Water, etc.)
- [x] Boss blind rotation (don't repeat until all seen)
- [x] 49 consumables (12 planets, 21 tarots, 16 spectrals)
- [x] Card enhancements: Bonus, Mult, Wild, Glass (1/4 shatter), Steel (×1.5 held), Stone, Gold (+$3 held), Lucky (1/5 +20 mult, 1/15 +$20)
- [x] Card editions: Foil, Holographic, Polychrome, Negative
- [x] Seals: Red (re-trigger), Gold (+$3), Blue (planet), Purple (tarot)
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
- [x] 45 self-tests passing
- [x] ~92K score calculations/sec in standard Lua
- [x] Validation suite (`validate.lua`) - 49 known-answer tests, ALL PASSING
- [x] Cross-validation (`cross_validate.lua`) - 1019 tests vs real Balatro source, ALL MATCHING
- [x] Joker effects audited against real game source (`card.lua`)

---

## Phase 1: Get training running (NOW)

**Goal:** PPO agent beats a random agent within 10 minutes of training.

- [x] Test the Python bridge (`balatro_gym.py`) with lupa installed
- [x] Fix any Lua↔Python data conversion issues
- [x] Write a minimal training script (PPO via StableBaselines3)
- [x] Run 100K training steps, measure if agent improves over random
- [x] If lupa is too slow → profile and identify bottleneck
- [x] Graph the learning curve (reward vs steps)

**Why this matters:** Proves the architecture works. If the agent can't learn, the observation/action space needs redesigning before investing in more content.

**Results:**
- Random baseline: mean -89.9, max -79.9
- Trained (500K steps): mean -9.5, max +20.1
- +77.5 mean reward improvement over random
- Training speed: ~2500 steps/sec
- Catastrophic forgetting observed at ~160K and ~470K steps → needs learning rate schedule

---

## Phase 1.5: Simplified env (DONE)

**Goal:** Easier action space for faster learning.

- [x] Created `balatro_gym_simple.py` with 247 Discrete actions (246 card combinations + 1 discard)
- [x] Auto-handles shop/blinds decisions (no hierarchical actions)
- [x] Much easier for PPO to learn than full hierarchical action space

---

## Phase 2: Content completeness (DONE)

**Goal:** Match the full game's common card library. All effects verified against real Balatro source.

- [x] Card enhancements:
  - [x] Steel (×1.5 mult when held in hand)
  - [x] Gold (+3 money when held in hand)
  - [x] Lucky (1/5 chance +20 mult, 1/15 chance +$20)
  - [x] Wild (counts as any suit for flushes + suit jokers)
  - [x] Glass destruction (1/4 chance to shatter after scoring)
  - [x] Red seal (re-trigger scoring + held-in-hand effects)
  - [x] Gold seal (+3 money when scored)
  - [x] Blue seal (create planet at round end)
  - [x] Purple seal (create tarot on discard)
- [x] New jokers (7):
  - [x] Delayed Gratification (+$2 per remaining discard if none used, round end)
  - [x] Supernova (+mult = times played this hand type)
  - [x] Ride the Bus (+1 mult per hand without face cards, reset on face)
  - [x] Blackboard (×3 if all remaining hand cards are Spade/Club/Wild)
  - [x] Ramen (×2 mult, -0.01 per card discarded, destroys at ×1)
  - [x] Acrobat (×3 on last hand of round)
  - [x] Sock and Buskin (re-trigger all played face card effects)
- [x] Tarot cards (21):
  - [x] All suit-change, enhancement, rank-change, and special tarots
- [x] Planet cards (12):
  - [x] All 12 hand types
- [x] Spectral cards (16):
  - [x] Familiar, Grim, Incantation, Talisman, Aura, Wraith, Sigil, Ouija, Ectoplasm, Immolate, Ankh, Deja Vu, Hex, Trance, Medium, Cryptid
- [x] Boss blind rotation (don't repeat until all seen)
- [x] Interest cap system (configurable via state._interest_cap)
- [x] Joker effects audited against real game source (4 discrepancies found and fixed)
- [ ] More deck types (Red, Blue, Yellow, Green, Black, Abandoned, Checkered, Zodiac, Plasma) — low priority

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
| Gym wrapper | ✓ | ✓ |
| Jokers | 28 (all common/uncommon) | stubs |
| Consumables | 49 (planets, tarots, spectrals) | none |
| Boss blinds | 8 (with rotation) | stubs |
| Full game loop | ✓ (shop, packs, blinds) | simplified |
| RNG | deterministic | platform-dependent |
| Rust port | planned | not planned |
| Speed | ~92K/sec (Lua), ~500K/sec (LuaJIT) | ~10K/sec (Python) |
| Stars | new | 38 |

**Our advantage:** We own the engine. They wrapped an existing game. Our engine is faster, more complete, deterministic, and designed for Rust porting. They're ahead on tested Python integration.
