# Balatro-Gym Roadmap

## Current State (March 2026)

Working headless Balatro simulation with Gymnasium wrapper. Core scoring is verified against real game (49/49 tests). Missing game systems (tags, vouchers, shop pools, most bosses) that make the strategy deep.

### What's Done

**Engine:**
- [x] 12 hand types, cascade logic matching real Balatro
- [x] Deterministic LCG RNG (seeded, portable)
- [x] 180-float observation vector (hand, jokers, deck composition, blind state, boss info)
- [x] 6-type hierarchical action space
- [x] 49/49 scoring validation tests (known-answer, against real game values)
- [x] 45/45 self-tests
- [x] 1019/1019 cross-validation vs real game source

**Jokers (145 registered, ~100 with working behavior):**
- [x] Joker (+4), Greedy/Lusty/Wrathful/Gluttonous (+3 suit), Jolly/Zany/Mad/Crazy/Droll (+mult type), Sly/Wily/Clever/Devious/Crafty (+chips type)
- [x] The Duo (×2 Pair), The Trio (×3 Trips), The Family (×4 Four), The Order (×3 Straight), The Tribe (×2 Flush)
- [x] Fibonacci (+8 Ace/2/3/5/8), Scary Face (+30 face), Even Steven (+4 even), Odd Todd (+31 odd), Scholar (+20+4 Ace)
- [x] Walkie Talkie (+10+10 10/4), Smiley (+5 face), Business Card ($2 face), Raised Fist (+mult lowest rank)
- [x] Blueprint (copy neighbor), Brainstorm (copy leftmost), Stencil (×1 per empty slot)
- [x] Banner (+30 × discards), Mystic Summit (+15 at 0 discards), Misprint (random 0-23)
- [x] Blackboard (×3 all dark), Ramen (×2 decaying), Acrobat (×3 last hand), Sock and Buskin (re-trigger face)
- [x] Hiker (+5 perma_bonus per face), Supernova (+mult = times played), Ride the Bus (+1 per no-face, reset)
- [x] Delayed Gratification (+$2/discard if none used), Burnt Joker (level up first discard)
- [x] Gros Michel (+15 mult, 1/6 die), Cavendish (×3 mult, 1/1000 die), Steel Joker (+0.2 per Steel)
- [x] Stone Joker (+25 per Stone in deck), Abstract (+3 per joker), Half Joker (+20 if ≤3 cards)
- [x] Photograph (×2 first face), Hanging Chad (re-trigger first card ×2), Lucky Cat (+0.25 per Lucky trigger)
- [x] Baseball Card (×1.5 per uncommon), Bull (+2 per $1 above 0), Constellation (+0.1 per Planet)
- [x] Green Joker (+1/hand, -1/discard), Card Sharp (×3 if hand played before), Red Card (+3 per pack skip)
- [x] Square Joker (+4/hand if exactly 4 played), Vampire (+0.1 per enhanced scored), Hologram (+0.25 per card added)
- [x] Baron (×1.5 per King held), Cloud 9 (+$1 per 9 in deck), Rocket (+$2 base, +$5/boss)
- [x] Obelisk (×0.2 if most played), To the Moon (+1 interest cap), Flash (+2/reroll), Spare Trousers (+2 Two Pair)
- [x] Flower Pot (×3 if all suits scored), Bootstraps (+2 per $5), Driver's License (×3 if ≥16 enhanced)
- [x] Blueprint_copy, DNA, Triboulet, Yorick, Canio (5 legendaries)
- [x] All suit-based individual jokers (Rough Gem/$, Bloodstone/1/2 ×1.5, Arrowhead/+50, Onyx Agate/+7)
- [x] Bloodstone uses real game RNG (0.5 probability), Gros Michel/Cavendish use seeded odds

**Consumables (49):**
- [x] 12 planets (all hand types)
- [x] 21 tarots (enhance, suit change, rank change, special)
- [x] 16 spectrals (destroy, enhance, modify, special)

**Card System:**
- [x] 8 enhancements (Bonus +30, Mult +4, Wild, Glass ×2/1/4 shatter, Steel ×1.5 held, Stone +50, Gold +$3 held, Lucky 1/5+20/1/15+$20)
- [x] 4 editions (Foil +50, Holographic +10, Polychrome ×1.5, Negative +1 slot)
- [x] 4 seals (Red re-trigger, Gold +$3, Blue planet, Purple tarot)

**Infrastructure:**
- [x] Python Gymnasium wrapper (full 293-action + simplified 247-action)
- [x] pip install via pyproject.toml
- [x] GitHub Actions CI (Lua + Python tests)
- [x] Module split (14 files in src/, build script merges to monolith)
- [x] Fidelity tester for Rust port
- [x] AGENTS.md handoff guide for AI agents

---

## Phase 2: Card Creation System (NEXT)

**Goal:** Build the foundation that tags, vouchers, more bosses, and stub jokers all depend on.

### 2a. `create_card()` helper (in `src/14_cards_factory.lua`)

Need a function that creates cards with proper pools, matching the real game's `create_card()` in `functions/common_events.lua`.

```
Sim.create_card(card_type, area, rarity, rng, key_append)
```

**Card types and their pools:**
- `"Joker"` — weighted by rarity pool
  - Common (rarity 1): `P_JOKER_RARITY_POOLS[1]`
  - Uncommon (rarity 2): `P_JOKER_RARITY_POOLS[2]`
  - Rare (rarity 3): `P_JOKER_RARITY_POOLS[3]`
  - Legendary (rarity 4): `P_JOKER_RARITY_POOLS[4]` (only via The Soul)
- `"Tarot"` — pool of 22 tarot keys
- `"Planet"` — pool of 12 planet keys
- `"Spectral"` — pool of 16 spectral keys
- `"Playing Card"` — random card from P_CARDS (52 cards)

**Rarity selection (for Joker type):**
- Roll `Sim.RNG.next(state.rng)`
- `> 0.95` → Rare (3)
- `> 0.70` → Uncommon (2)
- `else` → Common (1)
- `legendary=true` → Legendary (4) (only via Soul card)

**Pool culling rules (from real game):**
- Remove cards the player already owns (unless Showman present)
- Remove locked cards (except legendary)
- Vouchers: only if not used AND prerequisites met AND not already in shop
- Planets: only if that hand type has been played > 0
- Enhancement-gated jokers: only if enhancement exists in deck
- Respect `no_pool_flag` (e.g., Gros Michel sets `gros_michel_extinct`)
- Always exclude "The Soul" and "Black Hole" from normal pools

**Soul/Black Hole chance:**
- When creating Tarot/Spectral: 0.3% chance to create The Soul instead
- When creating Planet/Spectral: 0.3% chance to create Black Hole instead

**Sticker system (for future stake support):**
- Eternal: 30% chance (stake 4+) — can't be sold
- Perishable: 30% chance (stake 7+) — destroyed after 5 rounds
- Rental: 30% chance (stake 8+) — costs $3/round

### 2b. Pool definition tables (in `src/00_header.lua` or new `src/01b_pools.lua`)

Add these to the Sim table:
```lua
Sim.P_JOKER_RARITY_POOLS = {
    [1] = { "j_joker", "j_greedy_joker", ... },  -- ~73 common jokers
    [2] = { "j_four_fingers", "j_mime", ... },     -- ~50 uncommon jokers
    [3] = { "j_blueprint", "j_baron", ... },       -- ~20 rare jokers
    [4] = { "j_caino", "j_triboulet", ... },       -- 5 legendary jokers
}
Sim.P_TAROT_POOL = { "c_fool", "c_magician", ... }  -- 21 tarots
Sim.P_PLANET_POOL = { "c_pluto", "c_mercury", ... }  -- 12 planets
Sim.P_SPECTRAL_POOL = { "c_familiar", "c_grim", ... } -- 16 spectrals
```

### 2c. Wire up stub jokers that need card creation

Once `create_card` exists, these jokers become straightforward:
- Marble Joker (setting_blind → create Stone card)
- Riff-raff (setting_blind → create 2 common jokers)
- Cartomancer (setting_blind → create Tarot)
- Certificate (first_hand_drawn → create random sealed card)
- DNA (after_play → copy played card)
- Seance (joker_main + Straight Flush → create Spectral)
- Superposition (joker_main + Ace in straight → create Tarot)
- Hallucination (open_booster → 1/2 create Tarot)

---

## Phase 3: Shop Pool System (NEXT)

**Goal:** Make the shop generate items with correct weighted probabilities and pool culling.

### Current shop (wrong):
- Fixed 2 jokers, 1 booster, 1 consumable
- No pool weighting
- No item removal from pool

### Real shop (from `game.lua` and `UI_definitions.lua`):

**Shop slots:**
- Jokers: `G.GAME.shop.joker_max` = 2 (base), modified by Overstock (+1), Overstock Plus (+2)
- Vouchers: 1 slot (always)
- Boosters: 2 slots
- Consumable: 1 slot (from tarot/planet pool)

**Card type selection (weighted random):**
```
joker_rate = 20      -- 71.4% chance
tarot_rate = 4       -- 14.3% chance
planet_rate = 4      -- 14.3% chance
spectral_rate = 0    -- 0% by default (increased by vouchers)
playing_card_rate = 0 -- 0% by default (increased by Magic Trick voucher)
```

**Pricing (from `card.lua` set_cost):**
- Base cost defined per card in P_CENTERS (e.g., Joker = $2, Rare = $8-10)
- All vouchers = $10
- Boosters: Normal = $4, Jumbo = $6, Mega = $8
- Discounts: Clearance Sale = 25% off, Liquidation = 50% off
- `couponed = true` → cost = $0
- Egg adds +$3 to sell value per round
- Gift Card adds +$1 to sell value of all jokers/consumables per round

**Edition roll (from `common_events.lua`):**
- Normal (modified by edition_rate, default 1):
  - Foil: 4% * edition_rate
  - Holographic: 2% * edition_rate
  - Polychrome: 0.6% * edition_rate
  - Negative: 0.3% * edition_rate
- With Hone voucher: edition_rate = 2
- With Glow Up voucher: edition_rate = 4

**Reroll cost:**
- Base: $5
- Each reroll: +$1
- Reroll Surplus: -$2
- Reroll Glut: -$4 total
- D6 Tag: first reroll free

### Implementation in `src/10_shop.lua`:

Add `Sim.Shop.generate(state)`:
1. Roll card type (weighted by joker_rate/tarot_rate/planet_rate/spectral_rate)
2. If Joker: call `create_card("Joker", area, rarity, rng)` with pool culling
3. If Tarot/Planet: call `create_card(type, area, nil, rng)`
4. Roll edition (if joker, based on edition_rate)
5. Calculate cost (base - discount)
6. Place in shop slot

---

## Phase 4: Tags System (NEXT)

**Goal:** All 24 tags from the real game, matching every quirk.

### Complete tag definitions (from `game.lua` P_TAGS):

| Key | Name | Type | Config | Min Ante | Effect |
|-----|------|------|--------|----------|--------|
| tag_uncommon | Uncommon Tag | store_joker_create | - | nil | Free uncommon joker in next shop |
| tag_rare | Rare Tag | store_joker_create | odds=3 | nil | Free rare joker in next shop (if rare pool not exhausted) |
| tag_negative | Negative Tag | store_joker_modify | edition=negative, odds=5 | 2 | First uneditioned joker gets Negative, free |
| tag_foil | Foil Tag | store_joker_modify | edition=foil, odds=2 | nil | First uneditioned joker gets Foil, free |
| tag_holo | Holographic Tag | store_joker_modify | edition=holo, odds=3 | nil | First uneditioned joker gets Holographic, free |
| tag_polychrome | Polychrome Tag | store_joker_modify | edition=polychrome, odds=4 | nil | First uneditioned joker gets Polychrome, free |
| tag_investment | Investment Tag | eval | dollars=25 | nil | +$25 after defeating boss |
| tag_voucher | Voucher Tag | voucher_add | - | nil | Extra voucher in next shop |
| tag_boss | Boss Tag | new_blind_choice | - | nil | Reroll current boss blind |
| tag_standard | Standard Tag | new_blind_choice | - | 2 | Free Mega Standard Pack |
| tag_charm | Charm Tag | new_blind_choice | - | nil | Free Mega Arcana Pack |
| tag_meteor | Meteor Tag | new_blind_choice | - | 2 | Free Mega Celestial Pack |
| tag_buffoon | Buffoon Tag | new_blind_choice | - | 2 | Free Mega Buffoon Pack |
| tag_handy | Handy Tag | immediate | dollars_per_hand=1 | 2 | +$1 per hand played this run |
| tag_garbage | Garbage Tag | immediate | dollars_per_discard=1 | 2 | +$1 per unused discard this run |
| tag_ethereal | Ethereal Tag | new_blind_choice | - | 2 | Free Normal Spectral Pack |
| tag_coupon | Coupon Tag | shop_final_pass | - | nil | All shop items free next shop |
| tag_double | Double Tag | tag_add | - | nil | Copies next tag gained (except Double Tag) |
| tag_juggle | Juggle Tag | round_start_bonus | h_size=3 | nil | +3 hand size this round |
| tag_d_six | D6 Tag | shop_start | - | nil | First reroll costs $0 next shop |
| tag_top_up | Top-up Tag | immediate | spawn_jokers=2 | 2 | Create 2 free common jokers (if space) |
| tag_skip | Skip Tag | immediate | skip_bonus=5 | nil | +$5 per blind skipped this run |
| tag_orbital | Orbital Tag | immediate | levels=3 | 2 | Level up designated hand by 3 |
| tag_economy | Economy Tag | immediate | max=40 | nil | +min($40, current $) |

### Tag trigger contexts:
- `immediate` — triggers when tag is gained (blind skip)
- `new_blind_choice` — triggers when entering blind selection
- `store_joker_create` — triggers during shop joker creation
- `store_joker_modify` — triggers during shop joker modification
- `eval` — triggers after blind defeat
- `voucher_add` — triggers when shop vouchers are generated
- `tag_add` — triggers when any tag is gained
- `round_start_bonus` — triggers at round start
- `shop_start` — triggers at shop open
- `shop_final_pass` — triggers after shop items created

### Implementation in new `src/14_tags.lua`:
- `Sim.Tag.defs` — all 24 tag definitions
- `Sim.Tag.add(state, tag_key)` — add tag to state
- `Sim.Tag.apply(state, context)` — fire all tags for a context
- `Sim.Tag.pick(state)` — pick a random tag (respecting min_ante, not already held)

### State additions:
```lua
state.tags = {}           -- list of {key=..., triggered=false, config={...}}
state.skips = 0           -- total blinds skipped this run
state.unused_discards = 0 -- discards unused this round
state.hands_played = 0    -- total hands played this run
```

---

## Phase 5: Vouchers System (NEXT)

**Goal:** All 32 vouchers with correct tier upgrades and effects.

### Complete voucher table (from `game.lua` P_CENTERS):

**Tier 1 (Base):**

| Key | Name | Cost | Effect |
|-----|------|------|--------|
| v_overstock_norm | Overstock | $10 | +1 shop slot (joker_max + 1) |
| v_clearance_sale | Clearance Sale | $10 | 25% discount on all shop items |
| v_hone | Hone | $10 | 2× edition rate |
| v_reroll_surplus | Reroll Surplus | $10 | -$2 to reroll cost |
| v_crystal_ball | Crystal Ball | $10 | +1 consumable slot (total 3) |
| v_telescope | Telescope | $10 | Planet for most played hand always in packs |
| v_grabber | Grabber | $10 | +1 hand per round |
| v_wasteful | Wasteful | $10 | +1 discard per round |
| v_tarot_merchant | Tarot Merchant | $10 | 2× tarot rate in shop |
| v_planet_merchant | Planet Merchant | $10 | 2× planet rate in shop |
| v_seed_money | Seed Money | $10 | Interest cap → $50 |
| v_blank | Blank | $10 | Does nothing (required for Antimatter) |
| v_magic_trick | Magic Trick | $10 | Playing cards appear in shop |
| v_hieroglyph | Hieroglyph | $10 | -1 ante |
| v_directors_cut | Director's Cut | $10 | Reroll boss for $10 |
| v_paint_brush | Paint Brush | $10 | +1 hand size |

**Tier 2 (Upgrades):**

| Key | Name | Cost | Requires | Effect |
|-----|------|------|----------|--------|
| v_overstock_plus | Overstock Plus | $10 | v_overstock_norm | +2 shop slots total |
| v_liquidation | Liquidation | $10 | v_clearance_sale | 50% discount |
| v_glow_up | Glow Up | $10 | v_hone | 4× edition rate |
| v_reroll_glut | Reroll Glut | $10 | v_reroll_surplus | -$4 reroll cost total |
| v_omen_globe | Omen Globe | $10 | v_crystal_ball | +1 consumable slot (total 4), Spectrals in Arcana |
| v_observatory | Observatory | $10 | v_telescope | Planets in hand give ×1.5 mult |
| v_nacho_tong | Nacho Tong | $10 | v_grabber | +2 hands total |
| v_recyclomancy | Recyclomancy | $10 | v_wasteful | +2 discards total |
| v_tarot_tycoon | Tarot Tycoon | $10 | v_tarot_merchant | 4× tarot rate |
| v_planet_tycoon | Planet Tycoon | $10 | v_planet_merchant | 4× planet rate |
| v_money_tree | Money Tree | $10 | v_seed_money | Interest cap → $100 |
| v_antimatter | Antimatter | $10 | v_blank | +1 joker slot |
| v_illusion | Illusion | $10 | v_magic_trick | Playing cards can have editions/enhancements |
| v_petroglyph | Petroglyph | $10 | v_hieroglyph | -2 ante total |
| v_retcon | Retcon | $10 | v_directors_cut | Unlimited boss rerolls at $10 |
| v_palette | Palette | $10 | v_paint_brush | +2 hand size total |

### Voucher unlock conditions (from game source):
- Overstock Plus: Spend $2500 in shop
- Liquidation: Redeem 10 vouchers
- Glow Up: Have 5 editions active
- Reroll Glut: 100 total rerolls
- Omen Globe: Use 25 tarot readings
- Observatory: Use 25 planet cards
- Nacho Tong: Play 2500 cards total
- Recyclomancy: Discard 2500 cards total
- Tarot Tycoon: Buy 50 tarots total
- Planet Tycoon: Buy 50 planets total
- Money Tree: 10 interest streaks
- Antimatter: Redeem Blank 10 times
- Illusion: Buy 20 playing cards
- Petroglyph: Reach ante 12
- Retcon: Discover 25 different boss blinds
- Palette: Have 5 hand size (via Juggler, Paint Brush, etc.)

### Implementation in new `src/15_vouchers.lua`:
- `Sim.Voucher.defs` — all 32 voucher definitions
- `Sim.Voucher.redeem(state, voucher_key)` — apply voucher effect
- `Sim.Voucher.get_next(state)` — get next voucher in tier chain
- `Sim.Voucher.available(state)` — check unlock conditions

### State additions:
```lua
state.vouchers = {}           -- set of redeemed voucher keys
state.shop.joker_max = 2      -- modified by Overstock
state.consumable_slots = 2    -- modified by Crystal Ball
state._discount = 0           -- 0%, 25%, or 50%
state._edition_rate = 1.0     -- 1x, 2x, or 4x
state._reroll_discount = 0    -- -$2 or -$4
state._interest_cap = 25      -- $25, $50, or $100
state._tarot_rate_mult = 1    -- 1x, 2x, or 4x
state._planet_rate_mult = 1   -- 1x, 2x, or 4x
state._magic_trick = false    -- playing cards in shop
state._illusion = false       -- enhanced/editioned playing cards
```

---

## Phase 6: Boss Blinds (NEXT)

**Goal:** All 30 boss blinds with correct debuff/effect behavior.

### Complete boss blind table (from `game.lua` P_BLINDS):

**Regular bosses (25):**

| Key | Name | Mult | Min Ante | Debuff/Effect |
|-----|------|------|----------|---------------|
| bl_club | The Club | 2× | 1 | Debuffs all Club cards |
| bl_goad | The Goad | 2× | 1 | Debuffs all Spade cards |
| bl_head | The Head | 2× | 1 | Debuffs all Heart cards |
| bl_window | The Window | 2× | 1 | Debuffs all Diamond cards |
| bl_psychic | The Psychic | 2× | 1 | Must play exactly 5 cards |
| bl_hook | The Hook | 2× | 1 | Discards 2 random cards from hand when playing |
| bl_manacle | The Manacle | 2× | 1 | -1 hand size (restored when beaten) |
| bl_water | The Water | 2× | 2 | Start with 0 discards |
| bl_wall | The Wall | **4×** | 2 | Double chip requirement |
| bl_house | The House | 2× | 2 | First hand drawn face down |
| bl_arm | The Arm | 2× | 2 | Decreases hand level if > 1 |
| bl_wheel | The Wheel | 2× | 2 | 1/7 chance each drawn card is face down |
| bl_fish | The Fish | 2× | 2 | Cards drawn face down after first play |
| bl_mouth | The Mouth | 2× | 2 | Can only play one hand type |
| bl_mark | The Mark | 2× | 2 | Face cards drawn face down |
| bl_tooth | The Tooth | 2× | 3 | -$1 per card played |
| bl_eye | The Eye | 2× | 3 | Can't play same hand type twice |
| bl_plant | The Plant | 2× | 4 | Debuffs all face cards |
| bl_needle | The Needle | **1×** | 2 | Only 1 hand this round |
| bl_pillar | The Pillar | 2× | 1 | Debuffs cards played this ante |
| bl_serpent | The Serpent | 2× | 5 | After first play/discard, draw only 3 |
| bl_ox | The Ox | 2× | 6 | If play most played hand, set money to $0 |
| bl_flint | The Flint | 2× | 2 | Halves both chips and mult |

**Showdown bosses (ante 8 only, 5):**

| Key | Name | Mult | Effect |
|-----|------|------|--------|
| bl_final_bell | Cerulean Bell | 2× | Forces one card to always be selected |
| bl_final_leaf | Verdant Leaf | 2× | Debuffs ALL cards until a joker is sold |
| bl_final_vessel | Violet Vessel | **6×** | Triple normal chip requirement |
| bl_final_acorn | Amber Acorn | 2× | Flips and shuffles all jokers |
| bl_final_heart | Crimson Heart | 2× | Randomly debuffs one joker each hand |

### Boss selection logic:
- Regular bosses: available when `ante >= min` and `ante % 8 != 0`
- Showdown bosses: available when `ante % 8 == 0`
- Prioritize least-used bosses
- Don't repeat until all eligible bosses seen

### Implementation in `src/09_blinds.lua`:
- Add all 30 boss definitions
- Add `Sim.Blind.setup_boss(state, boss_key)` with debuff logic
- Add per-hand/per-play effect hooks for behavioral bosses
- Wire up deck interaction (face down → debuffed)

---

## Phase 7: Stub Joker Completion (AFTER 2-6)

**Goal:** Implement all 45 remaining stub jokers.

### Already working (just need proper marking):
- Four Fingers, Shortcut, Splash (in evaluator)
- Pareidolia, Mime, Smeared Joker (in helper functions)
- Sock and Buskin, Dusk, Hack, Seltzer, Hanging Chad (in engine re-trigger)
- Splash (in engine)

### Passive (need state initialization):
- Juggler: +1 hand size
- Drunkard: +1 discard
- Credit Card: -$20 debt limit
- Egg: +$3 sell value per round
- To the Moon: +1 extra interest cap
- Merry Andy: +3 discards, -1 hand size
- Astronomer: Planet cards free in shop
- Showman: Cards can appear multiple times in shop/packs
- Troubadour: +2 hand size, -1 hand per round

### Need `create_card()` (Phase 2):
- Marble Joker: setting_blind → add Stone card
- Riff-raff: setting_blind → create 2 common jokers
- Cartomancer: setting_blind → create Tarot
- Certificate: first_hand_drawn → create random sealed card
- DNA: after_play, first hand, 1 card → copy to hand
- Seance: joker_main + Straight Flush → create Spectral
- Superposition: joker_main + Ace in straight → create Tarot
- Hallucination: open_booster → 1/2 create Tarot
- Invisible Joker: sell after 2 rounds → duplicate random joker

### Need state tracking:
- Trading Card: discard 1 card for $3 if first discard this round
- Gift Card: +$1 sell value to all jokers/consumables per round end
- Satellite: $1 per unique planet used this run
- Throwback: +0.25 Xmult per blind skipped
- To Do List: $4 if hand type matches random target (changes each round)

### Need boss/voucher integration:
- Luchador: sell → disable boss blind
- Diet Cola: sell → create Double Tag (needs Tags)
- Chicot: disable boss blind effect passively

### Complex state modification:
- Turtle Bean: +5 hand size, -1 per round end (destroys at 0)
- Oops! All 6s: doubles all listed probabilities (affects every RNG check)
- Glass Joker: +0.75 Xmult per Glass card destroyed (needs destroying_card hook)
- Caino: +1 Xmult per face card destroyed (needs destroying_card hook)
- Mr. Bones: prevent death if chips ≥ 25% of blind (needs death check in engine)
- Midas Mask: face cards played become Gold (needs after_play card modification)

---

## Phase 8: Training Experiments (AFTER 7)

- [ ] Compare simplified env vs full env
- [ ] Action masking (only legal actions)
- [ ] Reward shaping experiments
- [ ] Different algorithms (PPO, SAC, IMPALA, DreamerV3)
- [ ] Publish learning curves

---

## Phase 9: Rust Port (FUTURE)

- [ ] Port Evaluator, Engine, State to Rust
- [ ] Use fidelity tester as correctness contract
- [ ] Expose via PyO3
- [ ] Target: 1M+ steps/sec

---

## Implementation Order (Dependency Graph)

```
Phase 2 (create_card) ─────────────────┐
                                        ├─→ Phase 7 (stub jokers)
Phase 3 (shop pools) ──→ Phase 4 (tags)─┤
        │                               │
        ├─→ Phase 5 (vouchers) ─────────┤
        │                               │
Phase 6 (boss blinds) ──────────────────┘
```

Phase 2 and 3 can be worked on in parallel. Phase 4 depends on 2+3. Phase 5 depends on 3. Phase 7 depends on everything above.

## Verification

After each phase:
1. `lua validate.lua` — must pass 49/49 (existing scoring not broken)
2. `lua -e "_SIM_RUN_TESTS=true" balatro_sim.lua` — must pass 45/45
3. Add new tests for the new system
4. Run a full random agent ante and verify no crashes
5. Spot-check 3+ items against real game source
