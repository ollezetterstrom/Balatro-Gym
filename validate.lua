--[[
    validate.lua — Known-answer test suite for Balatro correctness.

    Every test checks a specific scoring calculation against Balatro's
    actual game values. If a test fails, the engine is wrong.

    Usage:
        lua validate.lua

    These values come from the real Balatro game. Each test documents
    the exact calculation so you can verify independently.
]]

local Sim = dofile("balatro_sim.lua")
local C = Sim.Card.new
local E = Sim.ENUMS
local J = Sim.JOKER_DEFS
local function jid(key) return J[key].id end

local passed, failed, total = 0, 0, 0

local function check(name, got, expected)
    total = total + 1
    if got == expected then
        passed = passed + 1
        print(string.format("  [OK]   %-50s = %s", name, tostring(got)))
    else
        failed = failed + 1
        print(string.format("  [FAIL] %-50s  got %s  expected %s", name, tostring(got), tostring(expected)))
    end
end

-- Helper: create state, play cards, return (total, chips, mult)
local function score(hand_cards, jokers, play_indices)
    local state = Sim.State.new({seed="V", jokers=jokers or {}})
    state.hand = {}
    for _, c in ipairs(hand_cards) do state.hand[#state.hand+1] = c end
    local played = {}
    for _, idx in ipairs(play_indices) do played[#played+1] = state.hand[idx] end
    local total, chips, mult = Sim.Engine.calculate(state, played)
    return total, chips, mult, state
end

print("=== BALATRO VALIDATION SUITE ===\n")

-- ================================================================
-- PART 1: Base hand scoring (no enhancements, no jokers)
-- ================================================================
print("--- Part 1: Base hand scoring ---")

-- High Card of Ace: base 5 chips × 1 mult, Ace nominal = 11
-- = (5 + 11) × 1 = 16
local t, c, m = score({C(14,1), C(2,2), C(5,3), C(9,4), C(3,1), C(7,2), C(10,3), C(6,4)}, {}, {1})
check("High Card (Ace)", t, 16)

-- Pair of 2s: base 10 chips × 2 mult, 2 nominal = 2
-- = (10 + 2 + 2) × 2 = 28
t, c, m = score({C(2,1), C(2,2), C(5,3), C(9,4), C(3,1), C(7,2), C(10,3), C(6,4)}, {}, {1, 2})
check("Pair of 2s", t, 28)

-- Pair of Aces: base 10 chips × 2 mult, Ace nominal = 11
-- = (10 + 11 + 11) × 2 = 64
t, c, m = score({C(14,1), C(14,2), C(5,3), C(9,4), C(3,1), C(7,2), C(10,3), C(6,4)}, {}, {1, 2})
check("Pair of Aces", t, 64)

-- Two Pair (5s and 9s): base 20 chips × 2 mult
-- = (20 + 5 + 5 + 9 + 9) × 2 = 96
t, c, m = score({C(5,1), C(5,2), C(9,3), C(9,4), C(3,1), C(7,2), C(10,3), C(6,4)}, {}, {1, 2, 3, 4})
check("Two Pair (5s+9s)", t, 96)

-- Three of a Kind (7s): base 30 chips × 3 mult
-- = (30 + 7 + 7 + 7) × 3 = 153
t, c, m = score({C(7,1), C(7,2), C(7,3), C(9,4), C(3,1), C(2,2), C(10,3), C(6,4)}, {}, {1, 2, 3})
check("Three of a Kind (7s)", t, 153)

-- Straight (A-2-3-4-5): base 30 chips × 4 mult
-- = (30 + 11 + 2 + 3 + 4 + 5) × 4 = 220
t, c, m = score({C(14,1), C(2,2), C(3,3), C(4,4), C(5,1), C(7,2), C(10,3), C(6,4)}, {}, {1, 2, 3, 4, 5})
check("Straight (A-2-3-4-5)", t, 220)

-- Flush (all Hearts): base 35 chips × 4 mult
-- = (35 + 2 + 5 + 9 + 10 + 11) × 4 = 288
t, c, m = score({C(2,2), C(5,2), C(9,2), C(10,2), C(14,2), C(7,1), C(3,3), C(6,4)}, {}, {1, 2, 3, 4, 5})
check("Flush (Hearts)", t, 288)

-- Full House (3×7 + 2×K): base 40 chips × 4 mult
-- = (40 + 7 + 7 + 7 + 10 + 10) × 4 = 324
t, c, m = score({C(7,1), C(7,2), C(7,3), C(13,4), C(13,1), C(2,2), C(5,3), C(9,4)}, {}, {1, 2, 3, 4, 5})
check("Full House (7s+Ks)", t, 324)

-- Four of a Kind (10s): base 60 chips × 7 mult
-- = (60 + 10 + 10 + 10 + 10) × 7 = 700
t, c, m = score({C(10,1), C(10,2), C(10,3), C(10,4), C(3,1), C(7,2), C(2,3), C(6,4)}, {}, {1, 2, 3, 4})
check("Four of a Kind (10s)", t, 700)

-- Straight Flush (5-6-7-8-9 of Spades): base 100 chips × 8 mult
-- = (100 + 5 + 6 + 7 + 8 + 9) × 8 = 1080
t, c, m = score({C(5,1), C(6,1), C(7,1), C(8,1), C(9,1), C(2,2), C(3,3), C(14,4)}, {}, {1, 2, 3, 4, 5})
check("Straight Flush (5-9♠)", t, 1080)

-- Five of a Kind (Kings): base 120 chips × 12 mult
-- = (120 + 10 + 10 + 10 + 10 + 10) × 12 = 2040
t, c, m = score({C(13,1), C(13,2), C(13,3), C(13,4), C(13,1), C(2,2), C(5,3), C(9,4)}, {}, {1, 2, 3, 4, 5})
check("Five of a Kind (Kings)", t, 2040)

-- ================================================================
-- PART 2: Card enhancements
-- ================================================================
print("\n--- Part 2: Card enhancements ---")

-- Bonus card (+30 chips): Pair of 2s, one with Bonus
-- = (10 + 2 + (2+30)) × 2 = 88
t, c, m = score({C(2,1,1), C(2,2), C(5,3), C(9,4), C(3,1), C(7,2), C(10,3), C(6,4)}, {}, {1, 2})
check("Bonus enhancement (+30)", t, 88)

-- Mult card (+4 mult): Pair of 2s, one with Mult
-- = (10 + 2 + 2) × (2 + 4) = 84
t, c, m = score({C(2,1,2), C(2,2), C(5,3), C(9,4), C(3,1), C(7,2), C(10,3), C(6,4)}, {}, {1, 2})
check("Mult enhancement (+4)", t, 84)

-- Glass card (×2 mult): Pair of 2s, one with Glass
-- = (10 + 2 + 2) × (2 × 2) = 56
t, c, m = score({C(2,1,4), C(2,2), C(5,3), C(9,4), C(3,1), C(7,2), C(10,3), C(6,4)}, {}, {1, 2})
check("Glass enhancement (×2)", t, 56)

-- Glass on both cards (×2 × 2 = ×4)
-- = (10 + 2 + 2) × (2 × 2 × 2) = 112
t, c, m = score({C(2,1,4), C(2,2,4), C(5,3), C(9,4), C(3,1), C(7,2), C(10,3), C(6,4)}, {}, {1, 2})
check("Double Glass (×2×2)", t, 112)

-- Stone card (+50 chips, no nominal): played as High Card
-- = (5 + 50) × 1 = 55
t, c, m = score({C(2,1,6), C(3,2), C(5,3), C(9,4), C(7,1), C(10,2), C(4,3), C(8,4)}, {}, {1})
check("Stone enhancement (+50)", t, 55)

-- ================================================================
-- PART 3: Card editions
-- ================================================================
print("\n--- Part 3: Card editions ---")

-- Foil (+50 chips): Pair of 2s, one with Foil
-- = (10 + 2 + 2 + 50) × 2 = 128
t, c, m = score({C(2,1,0,1), C(2,2), C(5,3), C(9,4), C(3,1), C(7,2), C(10,3), C(6,4)}, {}, {1, 2})
check("Foil edition (+50)", t, 128)

-- Holographic (+10 mult): Pair of 2s, one with Holo
-- = (10 + 2 + 2) × (2 + 10) = 168
t, c, m = score({C(2,1,0,2), C(2,2), C(5,3), C(9,4), C(3,1), C(7,2), C(10,3), C(6,4)}, {}, {1, 2})
check("Holographic edition (+10)", t, 168)

-- Polychrome (×1.5 mult): Pair of 2s, one with Poly
-- = (10 + 2 + 2) × (2 × 1.5) = 42
t, c, m = score({C(2,1,0,3), C(2,2), C(5,3), C(9,4), C(3,1), C(7,2), C(10,3), C(6,4)}, {}, {1, 2})
check("Polychrome edition (×1.5)", t, 42)

-- ================================================================
-- PART 4: Joker effects
-- ================================================================
print("\n--- Part 4: Joker effects ---")

-- Joker (+4 mult): Pair of 2s
-- = (10 + 2 + 2) × (2 + 4) = 84
t, c, m = score(
    {C(2,1), C(2,2), C(5,3), C(9,4), C(3,1), C(7,2), C(10,3), C(6,4)},
    {{id=1, edition=0, eternal=false, uid=1}},
    {1, 2}
)
check("Joker (+4 mult)", t, 84)

-- Two Jokers (+4 + 4 = +8): Pair of 2s
-- = (10 + 2 + 2) × (2 + 4 + 4) = 140
t, c, m = score(
    {C(2,1), C(2,2), C(5,3), C(9,4), C(3,1), C(7,2), C(10,3), C(6,4)},
    {{id=jid"j_joker", edition=0, eternal=false, uid=1}, {id=jid"j_joker", edition=0, eternal=false, uid=2}},
    {1, 2}
)
check("Two Jokers (+8 mult)", t, 140)

-- Sly Joker (+50 chips): Pair of 2s
-- = (10 + 2 + 2 + 50) × 2 = 128
t, c, m = score(
    {C(2,1), C(2,2), C(5,3), C(9,4), C(3,1), C(7,2), C(10,3), C(6,4)},
    {{id=jid"j_sly", edition=0, eternal=false, uid=1}},
    {1, 2}
)
check("Sly Joker (+50 chips)", t, 128)

-- The Duo (×2 on Pair): Pair of 2s
-- = (10 + 2 + 2) × (2 × 2) = 56
t, c, m = score(
    {C(2,1), C(2,2), C(5,3), C(9,4), C(3,1), C(7,2), C(10,3), C(6,4)},
    {{id=jid"j_the_duo", edition=0, eternal=false, uid=1}},
    {1, 2}
)
check("The Duo (×2 on Pair)", t, 56)

-- The Trio (×3 on Three of a Kind): Three 7s
-- = (30 + 7 + 7 + 7) × (3 × 3) = 459
t, c, m = score(
    {C(7,1), C(7,2), C(7,3), C(9,4), C(3,1), C(2,2), C(10,3), C(6,4)},
    {{id=jid"j_the_trio", edition=0, eternal=false, uid=1}},
    {1, 2, 3}
)
check("The Trio (×3 on Trips)", t, 459)

-- Greedy Joker (+3 per Diamond scored): Pair of 2♦s
-- Scoring cards: 2♦, 2♦ (both Diamond) → +3 +3 = +6 mult
-- = (10 + 2 + 2) × (2 + 6) = 112
t, c, m = score(
    {C(2,4), C(2,4), C(5,3), C(9,3), C(3,1), C(7,2), C(10,3), C(6,1)},
    {{id=jid"j_greedy", edition=0, eternal=false, uid=1}},
    {1, 2}  -- pair of 2♦
)
check("Greedy Joker (+3 on ♦)", t, 112)

-- Fibonacci (+8 per Ace/2/3/5/8): Pair of 2s
-- = (10 + 2 + 2) × (2 + 8 + 8) = 252
t, c, m = score(
    {C(2,1), C(2,2), C(5,3), C(9,4), C(3,1), C(7,2), C(10,3), C(6,4)},
    {{id=jid"j_fibonacci", edition=0, eternal=false, uid=1}},
    {1, 2}
)
check("Fibonacci (+8 per 2)", t, 252)

-- Scary Face (+30 per face card): Pair of Kings
-- = (10 + 10 + 10 + 30 + 30) × 2 = 180
t, c, m = score(
    {C(13,1), C(13,2), C(5,3), C(9,4), C(3,1), C(7,2), C(10,3), C(6,4)},
    {{id=jid"j_scary_face", edition=0, eternal=false, uid=1}},
    {1, 2}
)
check("Scary Face (+30 per face)", t, 180)

-- Even Steven (+4 per even scored card): Pair of 8s
-- = (10 + 8 + 8) × (2 + 4 + 4) = 260
t, c, m = score(
    {C(8,1), C(8,2), C(5,3), C(9,4), C(3,1), C(7,2), C(10,3), C(6,4)},
    {{id=jid"j_even_steven", edition=0, eternal=false, uid=1}},
    {1, 2}
)
check("Even Steven (+4 per even)", t, 260)

-- Odd Todd (+31 per odd): Pair of 3s
-- = (10 + 3 + 3 + 31 + 31) × 2 = 156
t, c, m = score(
    {C(3,1), C(3,2), C(5,3), C(9,4), C(7,1), C(10,2), C(4,3), C(8,4)},
    {{id=jid"j_odd_todd", edition=0, eternal=false, uid=1}},
    {1, 2, 3, 4, 5}  -- pair of 3s + 5, 9, 7 (all odd)
)
check("Odd Todd (+31 per odd)", t, 156)

-- Scholar (+20 chips +4 mult per Ace): Pair of Aces
-- Base: chips=10, mult=2
-- Card 1 (A♠, not debuff): chips += 11 (nominal). Scholar: chips += 20, mult += 4
-- Card 2 (A♥): chips += 11, Scholar: chips += 20, mult += 4
-- = (10 + 11 + 11 + 20 + 20) × (2 + 4 + 4) = 72 × 10 = 720
t, c, m = score(
    {C(14,1), C(14,2), C(5,3), C(9,4), C(3,1), C(7,2), C(10,3), C(6,4)},
    {{id=jid"j_scholar", edition=0, eternal=false, uid=1}},
    {1, 2}
)
check("Scholar (+20+4 per Ace)", t, 720)

-- Joker + The Duo stacking: Pair of 2s
-- = (10 + 2 + 2) × (2 + 4) × 2 = 168
t, c, m = score(
    {C(2,1), C(2,2), C(5,3), C(9,4), C(3,1), C(7,2), C(10,3), C(6,4)},
    {{id=jid"j_joker", edition=0, eternal=false, uid=1}, {id=jid"j_the_duo", edition=0, eternal=false, uid=2}},
    {1, 2}
)
check("Joker(+4) + Duo(×2) = 168", t, 168)

-- Joker Stencil (×(1+empty slots)): 2 jokers in 5 slots = 3 empty
-- Order: Stencil (×4 on mult=2) → mult=8, then Joker (+4) → mult=12
-- Pair of 2s: = (10 + 2 + 2) × 12 = 168
t, c, m = score(
    {C(2,1), C(2,2), C(5,3), C(9,4), C(3,1), C(7,2), C(10,3), C(6,4)},
    {{id=jid"j_stencil", edition=0, eternal=false, uid=1}, {id=jid"j_joker", edition=0, eternal=false, uid=2}},
    {1, 2}
)
check("Joker Stencil (×4 empty)", t, 168)

-- Banner (+30 per remaining discard): Pair of 2s, 3 discards left
-- = (10 + 2 + 2 + 90) × 2 = 208
do
    local state = Sim.State.new({seed="V", jokers={{id=jid"j_banner", edition=0, eternal=false, uid=1}}})
    state.hand = {C(2,1), C(2,2), C(5,3), C(9,4), C(3,1), C(7,2), C(10,3), C(6,4)}
    state.discards_left = 3
    local total = Sim.Engine.calculate(state, {state.hand[1], state.hand[2]})
    check("Banner (+30 × 3 discards)", total, 208)
end

-- Mystic Summit (+15 when discards=0): Pair of 2s
-- = (10 + 2 + 2) × (2 + 15) = 238
do
    local state = Sim.State.new({seed="V", jokers={{id=jid"j_mystic_summit", edition=0, eternal=false, uid=1}}})
    state.hand = {C(2,1), C(2,2), C(5,3), C(9,4), C(3,1), C(7,2), C(10,3), C(6,4)}
    state.discards_left = 0
    local total = Sim.Engine.calculate(state, {state.hand[1], state.hand[2]})
    check("Mystic Summit (+15 at 0 discards)", total, 238)
end

-- ================================================================
-- PART 5: Hand leveling
-- ================================================================
print("\n--- Part 5: Hand leveling ---")

-- Pair level 2: base_mult = 2 + 1*(2-1) = 3, base_chips = 10 + 15*(2-1) = 25
-- = (25 + 2 + 2) × 3 = 87
do
    local state = Sim.State.new({seed="V"})
    state.hand = {C(2,1), C(2,2), C(5,3), C(9,4)}
    state.hand_levels[11] = 2  -- Pair
    local total = Sim.Engine.calculate(state, {state.hand[1], state.hand[2]})
    check("Pair level 2 (25×3)", total, 87)
end

-- Pair level 5: base_mult = 2 + 1*4 = 6, base_chips = 10 + 15*4 = 70
-- = (70 + 2 + 2) × 6 = 444
do
    local state = Sim.State.new({seed="V"})
    state.hand = {C(2,1), C(2,2), C(5,3), C(9,4)}
    state.hand_levels[11] = 5
    local total = Sim.Engine.calculate(state, {state.hand[1], state.hand[2]})
    check("Pair level 5 (70×6)", total, 444)
end

-- ================================================================
-- PART 6: Complex stacking
-- ================================================================
print("\n--- Part 6: Complex stacking ---")

-- Glass + Holo + Fibonacci: Pair of 2s
-- Glass card: chips = 2+2 = 4, mult = 2 × 2 = 4 (glass ×2)
-- Wait, glass is applied in the card loop. Let me trace:
-- Base: chips=10, mult=2
-- Card 1 (2♠, Glass): chips += 2 (nominal), mult *= 2 (glass) → chips=12, mult=4
-- Card 2 (2♥, normal): chips += 2 → chips=14, mult=4
-- Fibonacci fires per card: +8 mult each → mult = 4+8+8 = 20
-- = 14 × 20 = 280
t, c, m = score(
    {C(2,1,4), C(2,2), C(5,3), C(9,4), C(3,1), C(7,2), C(10,3), C(6,4)},
    {{id=jid"j_fibonacci", edition=0, eternal=false, uid=1}},
    {1, 2}
)
check("Glass + Fibonacci (14×20)", t, 280)

-- Foil + Holo on joker: Pair of 2s, Joker with Foil
-- = (10 + 2 + 2 + 50) × (2 + 4) = 384
t, c, m = score(
    {C(2,1), C(2,2), C(5,3), C(9,4), C(3,1), C(7,2), C(10,3), C(6,4)},
    {{id=jid"j_joker", edition=1, eternal=false, uid=1}},  -- Joker with Foil
    {1, 2}
)
check("Joker Foil edition (+50)", t, 384)

-- Polychrome on joker: Pair of 2s, Joker with Poly
-- = (10 + 2 + 2) × (2 + 4) × 1.5 = 126
t, c, m = score(
    {C(2,1), C(2,2), C(5,3), C(9,4), C(3,1), C(7,2), C(10,3), C(6,4)},
    {{id=jid"j_joker", edition=3, eternal=false, uid=1}},  -- Joker with Polychrome
    {1, 2}
)
check("Joker Polychrome edition (×1.5)", t, 126)

-- Bonus + Mult on same card: Pair of 2s, one with Bonus+Mult
-- = (10 + (2+30) + 2) × (2 + 4) = 264
-- Wait, can a card have both? In Balatro, no. But let me test the order:
-- Just Mult: = (10 + 2 + 2) × (2 + 4) = 84
-- Just Bonus: = (10 + 32 + 2) × 2 = 88
t, c, m = score({C(2,1,1), C(2,2), C(5,3), C(9,4), C(3,1), C(7,2), C(10,3), C(6,4)}, {}, {1, 2})
check("Bonus only (verification)", t, 88)

-- ================================================================
-- PART 7: Blind amounts
-- ================================================================
print("\n--- Part 7: Blind amounts ---")

-- Ante 1: Small=300, Big=450, Boss=600
check("Ante 1 Small blind", Sim.Blind.chips(1, 1), 300)
check("Ante 1 Big blind", Sim.Blind.chips(1, 2), 450)
check("Ante 1 Boss blind", Sim.Blind.chips(1, 3), 600)

-- Ante 2: Small=800, Big=1200, Boss=1600
check("Ante 2 Small blind", Sim.Blind.chips(2, 1), 800)
check("Ante 2 Big blind", Sim.Blind.chips(2, 2), 1200)
check("Ante 2 Boss blind", Sim.Blind.chips(2, 3), 1600)

-- Ante 8: Small=50000, Big=75000, Boss=100000
check("Ante 8 Small blind", Sim.Blind.chips(8, 1), 50000)
check("Ante 8 Big blind", Sim.Blind.chips(8, 2), 75000)
check("Ante 8 Boss blind", Sim.Blind.chips(8, 3), 100000)

-- ================================================================
-- RESULTS
-- ================================================================
print(string.format("\n=== RESULTS: %d/%d passed, %d failed ===", passed, total, failed))
if failed > 0 then
    print("\nNOTE: Failed tests indicate scoring differences from real Balatro.")
    print("Check the calculation comments in this file to verify.")
    os.exit(1)
else
    print("\nAll validations match Balatro's scoring. Engine is correct.")
end
