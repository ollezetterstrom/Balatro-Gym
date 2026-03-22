

--[[
    balatro_sim.lua — Headless Balatro Simulation Engine v3

    Pure-Lua, zero-graphics simulation of Balatro for AI training.
    Deterministic RNG, stateless scoring, synchronous execution.

    Usage:
        lua balatro_sim.lua              — runs self-tests + random agent
        local Sim = dofile("balatro_sim.lua")  — use as library

    API:
        Sim.Env.reset(seed) → obs, info
        Sim.Env.step(state, action_type, action_value) → obs, reward, done, info
        Sim.Obs.encode(state) → flat float array (129 floats)
        Sim.Env.action_spec → { types, obs_dim }

    Observation layout (124 floats):
        [0..47]   8 hand card slots × 6 features
        [48..62]  5 joker slots × 3 features
        [63..92]  30 global features (chips%, $, hands, discards, ante, levels, phase...)
        [93..100] 2 consumable slots × 2 features + misc
        [101..130] 5 pack card slots × 6 features (during PACK_OPEN phase)
        [131..124] shop flags, counts, spare
]]

local Sim = {}



-- ============================================================================


--  SECTION 1 — ENUMS
-- ============================================================================

Sim.ENUMS = {
    SUIT = { SPADES = 1, HEARTS = 2, CLUBS = 3, DIAMONDS = 4 },
    RANK = {
        TWO = 2, THREE = 3, FOUR = 4, FIVE = 5, SIX = 6, SEVEN = 7,
        EIGHT = 8, NINE = 9, TEN = 10, JACK = 11, QUEEN = 12,
        KING = 13, ACE = 14,
    },
    RANK_NOMINAL = {
        [2]=2, [3]=3, [4]=4, [5]=5, [6]=6, [7]=7,
        [8]=8, [9]=9, [10]=10, [11]=10, [12]=10, [13]=10, [14]=11,
    },
    RANK_SYM = {
        [2]="2",[3]="3",[4]="4",[5]="5",[6]="6",[7]="7",
        [8]="8",[9]="9",[10]="10",[11]="J",[12]="Q",[13]="K",[14]="A",
    },
    SUIT_SYM = { [1]="S", [2]="H", [3]="C", [4]="D" },

    HAND_TYPE = {
        FLUSH_FIVE = 1, FLUSH_HOUSE = 2, FIVE_OF_A_KIND = 3,
        STRAIGHT_FLUSH = 4, FOUR_OF_A_KIND = 5, FULL_HOUSE = 6,
        FLUSH = 7, STRAIGHT = 8, THREE_OF_A_KIND = 9,
        TWO_PAIR = 10, PAIR = 11, HIGH_CARD = 12,
    },
    HAND_NAME = {
        [1]="Flush Five",[2]="Flush House",[3]="Five of a Kind",
        [4]="Straight Flush",[5]="Four of a Kind",[6]="Full House",
        [7]="Flush",[8]="Straight",[9]="Three of a Kind",
        [10]="Two Pair",[11]="Pair",[12]="High Card",
    },

    ENHANCEMENT = {
        NONE=0, BONUS=1, MULT=2, WILD=3, GLASS=4,
        STEEL=5, STONE=6, GOLD=7, LUCKY=8,
    },
    EDITION = { NONE=0, FOIL=1, HOLO=2, POLYCHROME=3, NEGATIVE=4 },
    SEAL = { NONE=0, GOLD=1, RED=2, BLUE=3, PURPLE=4 },

    PHASE = {
        SELECTING_HAND = 1, SHOP = 2, PACK_OPEN = 3,
        BLIND_SELECT = 4, GAME_OVER = 5, WIN = 6,
    },

    ACTION = {
        SELECT_CARDS = 1,   -- value = 8-bit bitmask of hand positions
        PLAY_DISCARD = 2,   -- value: 1 = play, 2 = discard
        SHOP_ACTION = 3,    -- value: 0=reroll, 1-5=buy slot, -1~-5=sell joker
        USE_CONSUMABLE = 4, -- value: 1-based consumable index
        PHASE_ACTION = 5,   -- value: 0=end_shop, 1=fight, 2=skip, 3=next, 4=sell cons
        REORDER = 6,        -- value: [src:4][tgt:4][mode:1][area:1]  mode:0=swap 1=insert
    },

    REORDER_AREA = { HAND = 0, JOKER = 1 },

    REWARD = {
        HAND_SCORED  = 0.01,
        BLIND_BEATEN = 10.0,
        ANTE_UP      = 50.0,
        GAME_WON     = 200.0,
        GAME_OVER    = -100.0,
        INVALID      = -0.1,
    },
}

-- Hand base stats {s_mult, s_chips, l_mult, l_chips} from game.lua
Sim.HAND_BASE = {
    [1]={16,160,3,50}, [2]={14,140,4,40}, [3]={12,120,3,35},
    [4]={8,100,4,40},  [5]={7,60,3,30},   [6]={4,40,2,25},
    [7]={4,35,2,15},   [8]={4,30,3,30},   [9]={3,30,2,20},
    [10]={2,20,1,20},  [11]={2,10,1,15},  [12]={1,5,1,10},


}

-- ============================================================================


--  SECTION 2 — DETERMINISTIC RNG (LCG)
-- ============================================================================

Sim.RNG = {}
function Sim.RNG.hash(s)
    local h = 0
    for i = 1, #s do
        h = (h + string.byte(s, i)) * 2654435761 % 4294967296
        h = ((h >> 16) ~ h) * 2246822519 % 4294967296
        h = ((h >> 13) ~ h) * 3266489917 % 4294967296
        h = (h >> 16) ~ h
    end
    return h % 4294967296
end
function Sim.RNG.new(seed) return { state = Sim.RNG.hash(seed) } end
function Sim.RNG.next(r)
    r.state = (r.state * 1664525 + 1013904223) % 4294967296
    return r.state / 4294967296
end
function Sim.RNG.int(r, lo, hi) return lo + math.floor(Sim.RNG.next(r) * (hi - lo + 1)) end
function Sim.RNG.shuffle(r, t)
    for i = #t, 2, -1 do
        local j = 1 + math.floor(Sim.RNG.next(r) * i)
        t[i], t[j] = t[j], t[i]
    end


    return t
end
function Sim.RNG.pick(r, t) return t[Sim.RNG.int(r, 1, #t)] end

-- ============================================================================


--  SECTION 3 — CARD CONSTRUCTOR
-- ============================================================================

Sim.Card = {}
function Sim.Card.new(rank, suit, enh, ed, seal, pb)
    return { rank=rank, suit=suit, enhancement=enh or 0, edition=ed or 0,
             seal=seal or 0, perma_bonus=pb or 0 }
end
function Sim.Card.new_deck()
    local d = {}
    for s = 1, 4 do for r = 2, 14 do d[#d+1] = Sim.Card.new(r, s) end end
    return d
end
function Sim.Card.chips(card)
    if card.enhancement == 6 then return 50 + card.perma_bonus end  -- Stone
    return Sim.ENUMS.RANK_NOMINAL[card.rank] + card.perma_bonus
end
function Sim.Card.str(card)
    local E = Sim.ENUMS
    local t = (E.RANK_SYM[card.rank] or "?") .. (E.SUIT_SYM[card.suit] or "?")
    if card.enhancement == 1 then t = t.."+30" end
    if card.enhancement == 4 then t = t.."x2" end
    if card.enhancement == 6 then t = t.."." end


    if card.edition == 1 then t = t.."[F]" end
    if card.edition == 2 then t = t.."[H]" end
    if card.edition == 3 then t = t.."[P]" end
    return t
end

-- ============================================================================


--  SECTION 4 — JOKER DEFINITIONS
-- ============================================================================

Sim.JOKER_DEFS = {}
Sim._JOKER_BY_ID = {}

local function _reg_joker(key, name, rarity, cost, apply_fn)
    local def = { id = #Sim._JOKER_BY_ID + 1, key = key, name = name,
                  rarity = rarity, cost = cost, apply = apply_fn }
    Sim.JOKER_DEFS[key] = def
    Sim._JOKER_BY_ID[def.id] = def
    return def
end

_reg_joker("j_joker", "Joker", 1, 3, function(ctx, st, jk)
    if ctx.joker_main then return { mult_mod = 4 } end
end)

_reg_joker("j_greedy", "Greedy Joker", 1, 5, function(ctx, st, jk)
    if ctx.joker_main and ctx.scoring then
        for _, c in ipairs(ctx.scoring) do
            if c.suit == 4 then return { mult_mod = 3 } end  -- Diamonds
        end
    end
end)

_reg_joker("j_lusty", "Lusty Joker", 1, 5, function(ctx, st, jk)
    if ctx.joker_main and ctx.scoring then
        for _, c in ipairs(ctx.scoring) do
            if c.suit == 2 then return { mult_mod = 3 } end  -- Hearts
        end
    end
end)

_reg_joker("j_wrathful", "Wrathful Joker", 1, 5, function(ctx, st, jk)
    if ctx.joker_main and ctx.scoring then
        for _, c in ipairs(ctx.scoring) do
            if c.suit == 1 then return { mult_mod = 3 } end  -- Spades
        end
    end
end)

_reg_joker("j_gluttonous", "Gluttonous Joker", 1, 5, function(ctx, st, jk)
    if ctx.joker_main and ctx.scoring then
        for _, c in ipairs(ctx.scoring) do
            if c.suit == 3 then return { mult_mod = 3 } end  -- Clubs
        end
    end
end)

_reg_joker("j_the_duo", "The Duo", 3, 8, function(ctx, st, jk)
    if ctx.joker_main and ctx.all_hands and ctx.all_hands[11] then
        return { Xmult_mod = 2 }
    end
end)

_reg_joker("j_the_trio", "The Trio", 3, 8, function(ctx, st, jk)
    if ctx.joker_main and ctx.all_hands and ctx.all_hands[9] then
        return { Xmult_mod = 3 }
    end
end)

_reg_joker("j_blueprint", "Blueprint", 3, 10, function(ctx, st, jk)
    if ctx.blueprint then return end
    if not ctx.my_joker_index then return end
    local target = st.jokers[ctx.my_joker_index + 1]
    if not target or target == jk then return end
    local def = Sim._JOKER_BY_ID[target.id]
    if not def or not def.apply then return end
    local cc = {}
    for k,v in pairs(ctx) do cc[k] = v end
    cc.blueprint = true
    return def.apply(cc, st, target)
end)

_reg_joker("j_burnt_joker", "Burnt Joker", 3, 8, function(ctx, st, jk)
    if ctx.on_discard and ctx.is_first_discard then
        return { level_up = ctx.discarded_hand_type }
    end
end)

-- === New jokers (10 common/uncommon) ===

_reg_joker("j_stencil", "Joker Stencil", 2, 8, function(ctx, st, jk)
    if ctx.joker_main then
        local empty = st.joker_slots - #st.jokers
        if empty > 0 then return { Xmult_mod = 1 + empty } end
    end
end)

_reg_joker("j_banner", "Banner", 1, 5, function(ctx, st, jk)
    if ctx.joker_main then
        return { chip_mod = 30 * (st.discards_left or 0) }
    end
end)

_reg_joker("j_mystic_summit", "Mystic Summit", 1, 5, function(ctx, st, jk)
    if ctx.joker_main and (st.discards_left or 0) == 0 then
        return { mult_mod = 15 }
    end
end)

_reg_joker("j_misprint", "Misprint", 1, 4, function(ctx, st, jk)
    if ctx.joker_main then
        return { mult_mod = Sim.RNG.int(st.rng, 0, 23) }
    end
end)

_reg_joker("j_fibonacci", "Fibonacci", 2, 8, function(ctx, st, jk)
    if ctx.individual and ctx.other_card then
        local r = ctx.other_card.rank
        if r == 14 or r == 2 or r == 3 or r == 5 or r == 8 then
            return { mult = 8 }
        end
    end
end)

_reg_joker("j_scary_face", "Scary Face", 1, 4, function(ctx, st, jk)
    if ctx.individual and ctx.other_card then
        local r = ctx.other_card.rank
        if r == 11 or r == 12 or r == 13 then
            return { chips = 30 }
        end
    end
end)

_reg_joker("j_even_steven", "Even Steven", 1, 5, function(ctx, st, jk)
    if ctx.individual and ctx.other_card then
        local r = ctx.other_card.rank
        if r == 2 or r == 4 or r == 6 or r == 8 or r == 10 then
            return { mult = 4 }
        end
    end
end)

_reg_joker("j_odd_todd", "Odd Todd", 1, 5, function(ctx, st, jk)
    if ctx.individual and ctx.other_card then
        local r = ctx.other_card.rank
        if r == 3 or r == 5 or r == 7 or r == 9 or r == 14 then
            return { chips = 31 }
        end
    end
end)

_reg_joker("j_scholar", "Scholar", 1, 4, function(ctx, st, jk)
    if ctx.individual and ctx.other_card then
        if ctx.other_card.rank == 14 then
            return { chips = 20, mult = 4 }
        end
    end
end)

_reg_joker("j_sly", "Sly Joker", 1, 3, function(ctx, st, jk)
    if ctx.joker_main then
        return { chip_mod = 50 }


    end
end)

Sim.JOKER_POOL = {}
for _, def in pairs(Sim.JOKER_DEFS) do
    Sim.JOKER_POOL[#Sim.JOKER_POOL + 1] = def.id
end

-- ============================================================================


--  SECTION 5 — CONSUMABLE DEFINITIONS
-- ============================================================================

Sim.CONSUMABLE_DEFS = {}
Sim._CONS_BY_ID = {}

local function _reg_cons(key, name, set, effect_fn)
    local def = { id = #Sim._CONS_BY_ID + 1, key = key, name = name,
                  set = set, effect = effect_fn }
    Sim.CONSUMABLE_DEFS[key] = def
    Sim._CONS_BY_ID[def.id] = def
    return def
end

_reg_cons("c_pluto", "Pluto", "Planet", function(ctx, state)
    -- Level up High Card
    Sim.State.level_up(state, Sim.ENUMS.HAND_TYPE.HIGH_CARD, 1)
    return { level_up = Sim.ENUMS.HAND_TYPE.HIGH_CARD }
end)

_reg_cons("c_mercury", "Mercury", "Planet", function(ctx, state)
    -- Level up Pair
    Sim.State.level_up(state, Sim.ENUMS.HAND_TYPE.PAIR, 1)
    return { level_up = Sim.ENUMS.HAND_TYPE.PAIR }
end)

_reg_cons("c_empress", "The Empress", "Tarot", function(ctx, state)
    -- Enhance up to 2 selected cards to Mult (+4 Mult)
    if not ctx.selected or #ctx.selected == 0 then return nil end
    local count = 0
    for _, idx in ipairs(ctx.selected) do
        local c = state.hand[idx]
        if c and count < 2 then
            c.enhancement = Sim.ENUMS.ENHANCEMENT.MULT
            count = count + 1
        end
    end
    return { enhanced = count }
end)

_reg_cons("c_fool", "The Fool", "Tarot", function(ctx, state)
    -- Spawn the last used consumable (other than The Fool)
    if not state.last_consumable then return nil end
    if #state.consumables >= state.consumable_slots then return nil end
    local def = Sim._CONS_BY_ID[state.last_consumable]
    if not def or def.key == "c_fool" then return nil end
    state.consumables[#state.consumables + 1] = {
        id = def.id, uid = state._cons_n or 0,
    }
    return { spawned = def.key }
end)

Sim.CONS_POOL = {}
for _, def in pairs(Sim.CONSUMABLE_DEFS) do
    Sim.CONS_POOL[#Sim.CONS_POOL + 1] = def.id
end

-- ============================================================================
--  SECTION 6 — ADVANCED JOKERS
-- ============================================================================

_reg_joker("j_sixth_sense", "Sixth Sense", 2, 6, function(ctx, st, jk)
    if ctx.destroying_card then
        if not ctx.is_first_hand then return nil end
        if not ctx.full_hand or #ctx.full_hand ~= 1 then return nil end
        if ctx.full_hand[1].rank ~= 6 then return nil end
        -- Create a spectral consumable if room
        if #st.consumables < st.consumable_slots then
            -- Pick a random spectral-ish consumable
            local cid = Sim.RNG.pick(st.rng, Sim.CONS_POOL)
            st.consumables[#st.consumables + 1] = { id = cid, uid = (st._cons_n or 0) + 1 }
            st._cons_n = (st._cons_n or 0) + 1
            return { destroy = true, message = "Spectral created" }
        end
        return { destroy = true }
    end
end)

_reg_joker("j_hiker", "Hiker", 1, 5, function(ctx, st, jk)
    if ctx.individual and ctx.cardarea == "play" then


        ctx.other_card.perma_bonus = (ctx.other_card.perma_bonus or 0) + 4
        return { chips = 0, message = "+4 permanent" }
    end
end)

Sim.JOKER_POOL = {}
for _, def in pairs(Sim.JOKER_DEFS) do
    Sim.JOKER_POOL[#Sim.JOKER_POOL + 1] = def.id
end

-- ============================================================================


--  SECTION 7 — POKER HAND EVALUATOR
-- ============================================================================

Sim.Eval = {}

local function _cid(card) return card.enhancement == 6 and 0 or card.rank end

local function _x_same(num, hand)
    local counts = {}
    for i = 1, #hand do
        local id = _cid(hand[i])
        if id > 0 then
            counts[id] = counts[id] or {}
            counts[id][#counts[id]+1] = hand[i]
        end
    end
    local out = {}
    for rank = 14, 2, -1 do
        if counts[rank] and #counts[rank] == num then out[#out+1] = counts[rank] end
    end
    return out
end

local function _highest(hand)
    local best, bv = nil, -1
    for i = 1, #hand do
        local c = hand[i]
        if c.enhancement ~= 6 then
            local v = Sim.ENUMS.RANK_NOMINAL[c.rank] + c.rank * 0.01
            if v > bv then bv = v; best = c end
        end
    end
    return best and {best} or {}
end

local function _flush(hand)
    if #hand ~= 5 then return {} end
    local suit = nil
    for i = 1, #hand do
        if hand[i].enhancement == 3 then -- Wild
        elseif hand[i].enhancement == 6 then return {} -- Stone
        else
            if not suit then suit = hand[i].suit
            elseif hand[i].suit ~= suit then return {} end
        end
    end
    return {hand}
end

local function _straight(hand)
    if #hand ~= 5 then return {} end
    local seen = {}
    for i = 1, #hand do
        local id = _cid(hand[i])
        if id > 1 and id < 15 then
            seen[id] = seen[id] or {}
            seen[id][#seen[id]+1] = hand[i]
        end
    end
    local br, bc = 0, {}
    local run, cards = 0, {}
    if seen[14] and seen[2] and seen[3] and seen[4] and seen[5] then
        br = 5
        for _, r in ipairs({14,2,3,4,5}) do
            for _, c in ipairs(seen[r]) do bc[#bc+1] = c end
        end
    end
    for r = 2, 14 do
        if seen[r] then
            run = run + 1
            for _, c in ipairs(seen[r]) do cards[#cards+1] = c end
            if run > br then br = run; bc = {} for _,c in ipairs(cards) do bc[#bc+1]=c end end
        else run = 0; cards = {} end
    end
    return br >= 5 and {bc} or {}
end

--- Returns: best_type, scoring_cards, all_hands_table
function Sim.Eval.get_hand(cards)
    if not cards or #cards == 0 then
        return 12, {}, {}
    end
    local _5, _4, _3, _2 = _x_same(5,cards), _x_same(4,cards), _x_same(3,cards), _x_same(2,cards)
    local _fl, _st, _hi = _flush(cards), _straight(cards), _highest(cards)
    local HT = Sim.ENUMS.HAND_TYPE
    local best, best_sc, all = HT.HIGH_CARD, _hi, {}

    if #_5 > 0 and #_fl > 0 then
        all[HT.FLUSH_FIVE] = _5[1]
        if HT.FLUSH_FIVE < best then best = HT.FLUSH_FIVE; best_sc = _5[1] end
    end
    if #_3 > 0 and #_2 > 0 and #_fl > 0 then
        local fh = {}
        for _,c in ipairs(_3[1]) do fh[#fh+1]=c end
        for _,c in ipairs(_2[1]) do fh[#fh+1]=c end
        all[HT.FLUSH_HOUSE] = fh
        if HT.FLUSH_HOUSE < best then best = HT.FLUSH_HOUSE; best_sc = fh end
    end
    if #_5 > 0 then
        all[HT.FIVE_OF_A_KIND] = _5[1]
        if HT.FIVE_OF_A_KIND < best then best = HT.FIVE_OF_A_KIND; best_sc = _5[1] end
    end
    if #_fl > 0 and #_st > 0 then
        local set = {}
        for _,c in ipairs(_fl[1]) do set[c]=true end
        for _,c in ipairs(_st[1]) do set[c]=true end
        local sf = {}
        for c in pairs(set) do sf[#sf+1]=c end
        all[HT.STRAIGHT_FLUSH] = sf
        if HT.STRAIGHT_FLUSH < best then best = HT.STRAIGHT_FLUSH; best_sc = sf end
    end
    if #_4 > 0 then
        local sc = {}
        for _,c in ipairs(_4[1]) do sc[#sc+1]=c end
        all[HT.FOUR_OF_A_KIND] = sc
        if HT.FOUR_OF_A_KIND < best then best = HT.FOUR_OF_A_KIND; best_sc = sc end
        all[HT.THREE_OF_A_KIND] = {_4[1][1],_4[1][2],_4[1][3]}
        all[HT.PAIR] = {_4[1][1],_4[1][2]}
    end
    if #_3 > 0 and #_2 > 0 then
        local fh = {}
        for _,c in ipairs(_3[1]) do fh[#fh+1]=c end
        for _,c in ipairs(_2[1]) do fh[#fh+1]=c end
        all[HT.FULL_HOUSE] = fh
        if HT.FULL_HOUSE < best then best = HT.FULL_HOUSE; best_sc = fh end
    end
    if #_fl > 0 then
        all[HT.FLUSH] = _fl[1]
        if HT.FLUSH < best then best = HT.FLUSH; best_sc = _fl[1] end
    end
    if #_st > 0 then
        all[HT.STRAIGHT] = _st[1]
        if HT.STRAIGHT < best then best = HT.STRAIGHT; best_sc = _st[1] end
    end
    if #_3 > 0 then
        all[HT.THREE_OF_A_KIND] = _3[1]
        if HT.THREE_OF_A_KIND < best then best = HT.THREE_OF_A_KIND; best_sc = _3[1] end
        if not all[HT.PAIR] then all[HT.PAIR] = {_3[1][1],_3[1][2]} end
    end
    if #_2 >= 2 then
        local tp = {}
        for _,c in ipairs(_2[1]) do tp[#tp+1]=c end
        for _,c in ipairs(_2[2]) do tp[#tp+1]=c end


        all[HT.TWO_PAIR] = tp
        if HT.TWO_PAIR < best then best = HT.TWO_PAIR; best_sc = tp end
        if not all[HT.PAIR] then all[HT.PAIR] = _2[1] end
    end
    if #_2 > 0 then
        all[HT.PAIR] = _2[1]
        if HT.PAIR < best then best = HT.PAIR; best_sc = _2[1] end
    end
    all[HT.HIGH_CARD] = _hi
    return best, best_sc, all
end

-- ============================================================================


--  SECTION 6 — SCORING ENGINE
-- ============================================================================

Sim.Engine = {}

function Sim.Engine.calculate(state, played)
    local E = Sim.ENUMS
    local hand_type, scoring, all_hands = Sim.Eval.get_hand(played)

    local base = Sim.HAND_BASE[hand_type]
    local level = state.hand_levels[hand_type] or 1
    local chips = base[2] + base[4] * (level - 1)
    local mult  = base[1] + base[3] * (level - 1)

    local is_sc = {}
    for i = 1, #scoring do is_sc[scoring[i]] = true end

    for i = 1, #played do
        local c = played[i]
        local insc = is_sc[c]
        local debuffed = Sim.Blind.is_card_debuffed(state, c)

        if insc and not debuffed and c.enhancement ~= 6 then chips = chips + Sim.Card.chips(c) end
        if insc and not debuffed then
            if c.enhancement == 1 then chips = chips + 30        -- Bonus
            elseif c.enhancement == 2 then mult = mult + 4       -- Mult
            elseif c.enhancement == 6 then chips = chips + 50    -- Stone
            elseif c.enhancement == 4 then mult = mult * 2 end   -- Glass
        end
        if insc and not debuffed then
            if c.edition == 1 then chips = chips + 50            -- Foil
            elseif c.edition == 2 then mult = mult + 10          -- Holo
            elseif c.edition == 3 then mult = mult * 1.5 end     -- Poly
        end

        -- Individual card joker effects (Hiker, etc.)
        if insc and not debuffed and state.jokers then
            for ji = 1, #state.jokers do
                local jk = state.jokers[ji]
                local def = Sim._JOKER_BY_ID[jk.id]
                if def and def.apply then
                    local ctx = {
                        individual = true, cardarea = "play",
                        other_card = c, scoring_hand = scoring,
                        my_joker_index = ji,
                    }
                    local fx = def.apply(ctx, state, jk)
                    if fx then
                        if fx.chips then chips = chips + fx.chips end
                        if fx.mult then mult = mult + fx.mult end
                        if fx.x_mult then mult = mult * fx.x_mult end
                    end
                end
            end
        end
    end

    if state.jokers then
        for ji = 1, #state.jokers do
            local jk = state.jokers[ji]
            local def = Sim._JOKER_BY_ID[jk.id]
            if def and def.apply then
                local ctx = {
                    joker_main = true, hand_type = hand_type,
                    all_hands = all_hands, poker_hands = all_hands,
                    scoring = scoring, my_joker_index = ji,
                }
                local fx = def.apply(ctx, state, jk)
                if fx then


                    if fx.chip_mod then chips = chips + fx.chip_mod end
                    if fx.mult_mod then mult = mult + fx.mult_mod end
                    if fx.Xmult_mod then mult = mult * fx.Xmult_mod end
                end
            end
            if jk.edition == 1 then chips = chips + 50
            elseif jk.edition == 2 then mult = mult + 10
            elseif jk.edition == 3 then mult = mult * 1.5 end
        end
    end

    return math.floor(chips * mult), chips, mult, hand_type, scoring, all_hands
end

-- ============================================================================


--  SECTION 7 — GAME STATE
-- ============================================================================

Sim.State = {}
local D = { hands=4, discards=4, hand_size=8, joker_slots=5, cons_slots=2, start_money=4 }

function Sim.State.new(opts)
    opts = opts or {}
    local deck = opts.deck or Sim.Card.new_deck()
    local rng = opts.rng or Sim.RNG.new(opts.seed or "BALATRO")
    if not opts.deck then Sim.RNG.shuffle(rng, deck) end
    local hl = {}
    for i = 1, 12 do hl[i] = 1 end
    return {
        deck=deck, hand={}, discard={}, hand_limit=opts.hand_size or D.hand_size,
        jokers=opts.jokers or {}, joker_slots=D.joker_slots,
        consumables=opts.consumables or {}, consumable_slots=D.cons_slots,
        phase=opts.phase or Sim.ENUMS.PHASE.BLIND_SELECT,
        dollars=opts.dollars or D.start_money,
        ante=opts.ante or 1, round=0,
        hands_left=D.hands, discards_left=D.discards, hands_played=0,
        blind_type="none", blind_chips=300, blind_beaten=false,
        selection={}, hand_levels=hl,
        chips=0, total_chips=0,
        deck_count=52,
        pack_cards=nil, last_consumable=nil,
        rng=rng, _joker_n=0, _cons_n=0,
    }
end

function Sim.State.draw(state)
    if #state.hand >= state.hand_limit then return state end
    local n = math.min(state.hand_limit - #state.hand, #state.deck)
    for i = 1, n do state.hand[#state.hand+1] = table.remove(state.deck, 1) end
    return state
end

function Sim.State.rebuild_deck(state)
    local all = {}
    for _,c in ipairs(state.deck) do all[#all+1]=c end
    for _,c in ipairs(state.hand) do all[#all+1]=c end
    for _,c in ipairs(state.discard) do all[#all+1]=c end
    Sim.RNG.shuffle(state.rng, all)
    state.deck = all; state.hand = {}; state.discard = {}
    state.deck_count = #all
    return state
end

function Sim.State.interest(state)
    return math.min(math.floor(state.dollars / 5), 5)
end

function Sim.State.level_up(state, ht, amt)
    amt = amt or 1
    state.hand_levels[ht] = (state.hand_levels[ht] or 1) + amt
    return state
end

function Sim.State.add_joker(state, joker_def)
    if #state.jokers >= state.joker_slots then return false end
    state._joker_n = state._joker_n + 1
    state.jokers[#state.jokers+1] = {


        id = joker_def.id, edition = 0, eternal = false,
        uid = state._joker_n,
    }
    return true
end

function Sim.State.remove_joker(state, uid)
    for i = #state.jokers, 1, -1 do
        if state.jokers[i].uid == uid then
            table.remove(state.jokers, i)
            return true
        end
    end
    return false
end

-- ============================================================================


--  SECTION 8 — BLIND SYSTEM
-- ============================================================================

Sim.Blind = {}
local BLIND_DATA = {
    {name="Small", mult=1.0, reward=3},
    {name="Big",   mult=1.5, reward=4},
    {name="Boss",  mult=2.0, reward=5},
}

-- Boss blind pool (name, chip_mult_override, setup_fn)
-- setup_fn(state) runs when the boss is set, applies debuffs/penalties
Sim.BOSS_BLINDS = {
    { name = "The Wall",     chip_mult = 2.0, setup = function(st) end },
    { name = "The Arm",      chip_mult = 1.0, setup = function(st) end },
    { name = "The Water",    chip_mult = 1.0, setup = function(st) st.discards_left = 0 end },
    { name = "The Manacle",  chip_mult = 1.0, setup = function(st) st.hand_limit = st.hand_limit - 1 end },
    { name = "The Needle",   chip_mult = 1.0, setup = function(st) st.hands_left = 1 end },
    { name = "The Club",     chip_mult = 1.0, setup = function(st) st._boss_debuff_suit = 3 end },
    { name = "The Goad",     chip_mult = 1.0, setup = function(st) st._boss_debuff_suit = 1 end },
    { name = "The Window",   chip_mult = 1.0, setup = function(st) st._boss_debuff_suit = 4 end },
}

function Sim.Blind.pick_boss(state, ante)
    -- Pick a deterministic boss from the pool based on ante + rng
    local idx = Sim.RNG.int(state.rng, 1, #Sim.BOSS_BLINDS)
    return Sim.BOSS_BLINDS[idx]
end

function Sim.Blind.is_card_debuffed(state, card)
    if not state._boss_debuff_suit then return false end
    return card.suit == state._boss_debuff_suit
end

function Sim.Blind.on_play(state, played_cards)
    -- Boss: The Arm — decrease played hand level by 1
    if state.boss_name == "The Arm" then
        local ht = Sim.Eval.get_hand(played_cards)
        if state.hand_levels[ht] and state.hand_levels[ht] > 1 then
            state.hand_levels[ht] = state.hand_levels[ht] - 1
        end
    end
end

function Sim.Blind.on_after_play(state)
    -- Boss: The Hook — discard 2 random cards from hand
    if state.boss_name == "The Hook" and #state.hand >= 2 then
        local idx1 = Sim.RNG.int(state.rng, 1, #state.hand)
        local idx2 = Sim.RNG.int(state.rng, 1, #state.hand - 1)
        if idx2 >= idx1 then idx2 = idx2 + 1 end
        local c1 = table.remove(state.hand, math.max(idx1, idx2))
        local c2 = table.remove(state.hand, math.min(idx1, idx2))
        if c1 then state.discard[#state.discard+1] = c1 end
        if c2 then state.discard[#state.discard+1] = c2 end
    end
end

function Sim.Blind.chips(ante, btype)
    local amounts = {300,800,2000,5000,11000,20000,35000,50000}
    local base = ante <= 8 and amounts[ante] or amounts[8]
    return math.floor(base * BLIND_DATA[btype].mult)
end
function Sim.Blind.name(btype) return BLIND_DATA[btype].name end
function Sim.Blind.reward(btype) return BLIND_DATA[btype].reward end

function Sim.Blind.setup(state, btype)
    -- Restore defaults (boss effects from previous round are cleared)
    state.hand_limit = D.hand_size
    state._boss_debuff_suit = nil
    state.boss_name = nil

    state.blind_type = BLIND_DATA[btype].name
    state.blind_chips = Sim.Blind.chips(state.ante, btype)
    state.blind_beaten = false
    state.chips = 0
    state.hands_left = D.hands
    state.discards_left = D.discards
    state.hands_played = 0
    state.round = state.round + 1
    state.selection = {}

    -- Boss blind: pick specific boss and apply effects
    if btype == 3 then
        local boss = Sim.Blind.pick_boss(state, state.ante)
        state.boss_name = boss.name
        if boss.chip_mult and boss.chip_mult ~= 1.0 then
            state.blind_chips = math.floor(state.blind_chips * boss.chip_mult)
        end
        boss.setup(state)
    end

    Sim.State.rebuild_deck(state)
    Sim.State.draw(state)
    return state
end

-- Return the next blind type to fight: 1=Small, 2=Big, 3=Boss


function Sim.Blind.next_type(state)
    local st = state._blind_states
    if not st then return 1 end
    if st.Small ~= "done" then return 1 end
    if st.Big ~= "done" then return 2 end
    if st.Boss ~= "done" then return 3 end
    return nil
end

function Sim.Blind.init_ante(state)
    state._blind_states = {Small="pending", Big="pending", Boss="pending"}
end

function Sim.Blind.mark_done(state, btype, skipped)
    local names = {"Small","Big","Boss"}
    state._blind_states[names[btype]] = skipped and "skipped" or "done"
end

-- ============================================================================


--  SECTION 9 — SHOP & ECONOMY
-- ============================================================================

Sim.Shop = {}

function Sim.Shop.generate(state)
    local shop = { jokers = {}, booster = nil, consumable = nil }
    local pool = Sim.JOKER_POOL
    for i = 1, 2 do
        local jid = Sim.RNG.pick(state.rng, pool)
        local def = Sim._JOKER_BY_ID[jid]
        shop.jokers[i] = { joker_id = jid, cost = def.cost or 3, slot = i }
    end
    shop.booster = { cost = 4, pack_type = "buffoon", slot = 3 }
    -- Free consumable slot
    if #state.consumables < state.consumable_slots then
        local cid = Sim.RNG.pick(state.rng, Sim.CONS_POOL)
        shop.consumable = { cons_id = cid, cost = 0, slot = 4 }
    end
    state.shop = shop
    return state
end

function Sim.Shop.reroll(state)
    if not state.shop then return state end
    local pool = Sim.JOKER_POOL
    for i = 1, 2 do
        if not state.shop.jokers[i] then
            local jid = Sim.RNG.pick(state.rng, pool)
            local def = Sim._JOKER_BY_ID[jid]
            state.shop.jokers[i] = { joker_id = jid, cost = def.cost or 3, slot = i }
        end
    end
    if not state.shop.consumable and #state.consumables < state.consumable_slots then
        local cid = Sim.RNG.pick(state.rng, Sim.CONS_POOL)
        state.shop.consumable = { cons_id = cid, cost = 0, slot = 4 }
    end
    return state
end

function Sim.Shop.buy_joker(state, slot)
    if not state.shop or not state.shop.jokers[slot] then return false end
    local item = state.shop.jokers[slot]
    if state.dollars < item.cost then return false end
    local def = Sim._JOKER_BY_ID[item.joker_id]
    if not def then return false end
    if #state.jokers >= state.joker_slots then return false end
    state.dollars = state.dollars - item.cost
    Sim.State.add_joker(state, def)
    state.shop.jokers[slot] = nil
    return true
end

function Sim.Shop.sell_joker(state, joker_idx)
    local jk = state.jokers[joker_idx]
    if not jk then return false end
    local def = Sim._JOKER_BY_ID[jk.id]
    state.dollars = state.dollars + math.floor((def.cost or 3) / 2)
    table.remove(state.jokers, joker_idx)
    return true
end

function Sim.Shop.buy_consumable(state)
    if not state.shop or not state.shop.consumable then return false end
    if #state.consumables >= state.consumable_slots then return false end
    local item = state.shop.consumable
    state._cons_n = (state._cons_n or 0) + 1
    state.consumables[#state.consumables + 1] = {
        id = item.cons_id, uid = state._cons_n,
    }
    state.shop.consumable = nil
    return true
end

function Sim.Shop.buy_booster(state)
    if not state.shop or not state.shop.booster then return false end
    if state.dollars < state.shop.booster.cost then return false end
    state.dollars = state.dollars - state.shop.booster.cost
    -- Generate 3 joker cards for the pack
    local pack = {}
    for i = 1, 3 do
        pack[i] = Sim.RNG.pick(state.rng, Sim.JOKER_POOL)
    end
    state.pack_cards = pack
    state.shop.booster = nil
    state._prev_phase = state.phase  -- remember where to return
    state.phase = Sim.ENUMS.PHASE.PACK_OPEN
    return true
end

function Sim.Shop.select_pack(state, idx)


    if not state.pack_cards or not state.pack_cards[idx] then return false end
    local jid = state.pack_cards[idx]
    local def = Sim._JOKER_BY_ID[jid]
    if not def then return false end
    if #state.jokers < state.joker_slots then
        Sim.State.add_joker(state, def)
    end
    state.pack_cards = nil
    state.phase = state._prev_phase or Sim.ENUMS.PHASE.SHOP
    state._prev_phase = nil
    return true
end

function Sim.Shop.skip_pack(state)
    state.pack_cards = nil
    state.phase = state._prev_phase or Sim.ENUMS.PHASE.SHOP
    state._prev_phase = nil
    return true
end

-- ============================================================================


--  SECTION 10 — OBSERVATION ENCODING
-- ============================================================================

Sim.Obs = {}
Sim.Obs.DIM = 129  -- 48(hand) + 15(jokers) + 30(global) + 4(cons) + 1(pack_flag) + 30(pack) + 1(shop_misc)

function Sim.Obs.encode(state)
    local o = {}
    local n = 0

    -- 8 hand card slots × 6 floats = 48
    for i = 1, 8 do
        local c = state.hand[i]
        if c then
            o[n+1] = c.rank / 14
            o[n+2] = c.suit / 4
            o[n+3] = c.enhancement / 8
            o[n+4] = c.edition / 4
            o[n+5] = c.seal / 4
            o[n+6] = 1  -- has card
        else
            for j = 1, 6 do o[n+j] = 0 end
        end
        n = n + 6
    end

    -- 5 joker slots × 3 floats = 15
    local jcount = #Sim._JOKER_BY_ID
    for i = 1, 5 do
        local jk = state.jokers[i]
        if jk then
            o[n+1] = jk.id / math.max(jcount, 1)
            o[n+2] = jk.edition / 4
            o[n+3] = 1  -- has joker
        else
            for j = 1, 3 do o[n+j] = 0 end
        end
        n = n + 3
    end

    -- Global features = 30 floats
    o[n+1] = math.min(state.chips / math.max(state.blind_chips, 1), 1.0)
    o[n+2] = math.min(state.dollars / 25.0, 1.0)
    o[n+3] = state.hands_left / D.hands
    o[n+4] = state.discards_left / D.discards
    o[n+5] = state.ante / 8.0
    o[n+6] = math.min(state.round / 24.0, 1.0)
    o[n+7] = state.blind_beaten and 1.0 or 0.0
    o[n+8] = math.min(state.deck_count / 52.0, 1.0)
    n = n + 8

    -- 12 hand levels (log-scaled)
    for i = 1, 12 do
        o[n+1] = math.log((state.hand_levels[i] or 1) + 1) * 1.4426950408889634 / 5.0
        n = n + 1
    end

    -- Phase one-hot (3 floats)
    local p = state.phase
    o[n+1] = (p == 1) and 1.0 or 0.0
    o[n+2] = (p == 2) and 1.0 or 0.0
    o[n+3] = (p == 3) and 1.0 or 0.0
    n = n + 3

    -- Selection count / 8
    o[n+1] = #state.selection / 8.0
    n = n + 1

    -- Consumable slots × 3 floats = 6
    local ccount = #Sim._CONS_BY_ID
    for i = 1, 2 do
        local cs = state.consumables[i]
        if cs then
            o[n+1] = cs.id / math.max(ccount, 1)
            o[n+2] = 1  -- has consumable
        else
            o[n+1] = 0; o[n+2] = 0
        end
        n = n + 2
    end

    -- Pack open flag
    o[n+1] = state.pack_cards and 1.0 or 0.0
    n = n + 1

    -- 5 pack card slots × 6 floats = 30
    for i = 1, 5 do
        local pc = state.pack_cards and state.pack_cards[i] or nil
        if pc then
            -- pack_cards stores card IDs (joker IDs or card data)
            if type(pc) == "table" and pc.rank then
                -- Playing card
                o[n+1] = pc.rank / 14
                o[n+2] = pc.suit / 4
                o[n+3] = pc.enhancement / 8
                o[n+4] = pc.edition / 4
                o[n+5] = pc.seal / 4
                o[n+6] = 1
            elseif type(pc) == "number" then
                -- Joker ID
                o[n+1] = pc / math.max(jcount, 1)
                o[n+2] = 0; o[n+3] = 0; o[n+4] = 0; o[n+5] = 0
                o[n+6] = 1
            else
                for j = 1, 6 do o[n+j] = 0 end
            end
        else
            for j = 1, 6 do o[n+j] = 0 end
        end
        n = n + 6
    end

    -- Shop items present (joker1, joker2, booster, consumable) = 4
    if state.shop then
        o[n+1] = state.shop.jokers[1] and 1.0 or 0.0
        o[n+2] = state.shop.jokers[2] and 1.0 or 0.0
        o[n+3] = state.shop.booster and 1.0 or 0.0
        o[n+4] = state.shop.consumable and 1.0 or 0.0
    else


        o[n+1] = 0; o[n+2] = 0; o[n+3] = 0; o[n+4] = 0
    end
    n = n + 4

    -- Joker count / 5
    o[n+1] = #state.jokers / 5.0
    n = n + 1

    -- Consumable count / 2
    o[n+1] = #state.consumables / 2.0
    n = n + 1

    -- Round dollars earned so far (normalized)
    o[n+1] = math.min((state.round_dollars or 0) / 25.0, 1.0)
    n = n + 1

    -- Spare to fill to 129
    while n < 129 do n = n + 1; o[n] = 0 end

    return o
end

-- ============================================================================


--  SECTION 11 — ENVIRONMENT (Gym-style Interface)
-- ============================================================================

Sim.Env = {}
Sim.Env.action_spec = {
    types = { "SELECT_CARDS","PLAY_DISCARD","SHOP_ACTION","USE_CONSUMABLE","PHASE_ACTION" },
    obs_dim = 129,
}

function Sim.Env.reset(seed)
    local rng = Sim.RNG.new(seed)
    local state = Sim.State.new({ rng = rng, seed = seed })
    Sim.Blind.init_ante(state)
    local btype = Sim.Blind.next_type(state)
    if btype then
        Sim.Blind.setup(state, btype)
        state.phase = Sim.ENUMS.PHASE.SELECTING_HAND
    end
    return Sim.Obs.encode(state), { seed = seed, ante = state.ante }
end

-- ============================================================
-- Shared helper functions
-- ============================================================

function _do_reorder(state, value)
    local E = Sim.ENUMS
    local R = E.REWARD
    local src  = (value & 0xF) + 1         -- bits 0-3: source (0-indexed → 1-indexed)
    local tgt  = ((value >> 4) & 0xF) + 1  -- bits 4-7: target
    local mode = (value >> 8) & 1          -- bit 8: 0=swap, 1=insert
    local area = (value >> 9) & 1          -- bit 9: 0=hand, 1=jokers

    local arr
    if area == 1 then arr = state.jokers else arr = state.hand end

    if src < 1 or src > #arr or tgt < 1 or tgt > #arr or src == tgt then
        return Sim.Obs.encode(state), R.INVALID, false
    end

    if mode == 0 then
        arr[src], arr[tgt] = arr[tgt], arr[src]
    else
        local item = table.remove(arr, src)
        table.insert(arr, tgt, item)
    end
    return Sim.Obs.encode(state), 0, false
end

function _use_consumable(state, cons_index)
    local E = Sim.ENUMS
    local R = E.REWARD
    local cs = state.consumables[cons_index]
    if not cs then
        return Sim.Obs.encode(state), R.INVALID, false
    end
    local def = Sim._CONS_BY_ID[cs.id]
    if not def then
        return Sim.Obs.encode(state), R.INVALID, false
    end

    -- For Empress, we need selected cards from state.selection
    local ctx = { selected = state.selection }
    local fx = def.effect(ctx, state)

    -- Track last consumable for Fool
    if def.key ~= "c_fool" then
        state.last_consumable = cs.id
    end

    -- Remove the consumable
    table.remove(state.consumables, cons_index)

    return Sim.Obs.encode(state), 0, false
end

-- ============================================================
-- Phase handlers (internal, called by step)
-- ============================================================

local function _step_selecting(state, atype, value)
    local E = Sim.ENUMS
    local R = Sim.ENUMS.REWARD

    if atype == E.ACTION.SELECT_CARDS then
        -- value = 8-bit bitmask
        local sel = {}
        for i = 0, 7 do
            if (value >> i) & 1 == 1 and state.hand[i+1] then
                sel[#sel+1] = i + 1
            end
        end
        state.selection = sel
        return Sim.Obs.encode(state), 0, false

    elseif atype == E.ACTION.PLAY_DISCARD then
        if #state.selection == 0 then
            return Sim.Obs.encode(state), R.INVALID, false
        end

        -- Sort selections descending for safe removal
        local sorted = {}
        for _, v in ipairs(state.selection) do sorted[#sorted+1] = v end
        table.sort(sorted, function(a,b) return a > b end)

        if value == 1 then
            -- PLAY
            if state.hands_left <= 0 then
                return Sim.Obs.encode(state), R.INVALID, false
            end
            local played = {}
            for _, idx in ipairs(sorted) do
                played[#played+1] = state.hand[idx]
                table.remove(state.hand, idx)
            end

            -- Boss: The Arm (decrease hand level before scoring)
            Sim.Blind.on_play(state, played)

            local total, chips, mult, ht, scoring, all_h =
                Sim.Engine.calculate(state, played)

            state.total_chips = state.total_chips + total
            state.chips = state.chips + total
            state.hands_left = state.hands_left - 1
            state.hands_played = state.hands_played + 1
            for _, c in ipairs(played) do state.discard[#state.discard+1] = c end
            Sim.State.draw(state)
            state.selection = {}

            -- Boss: The Hook (discard 2 random cards after playing)
            Sim.Blind.on_after_play(state)

            -- Joker "play" triggers
            if state.jokers then
                for ji = 1, #state.jokers do
                    local jk = state.jokers[ji]
                    local def = Sim._JOKER_BY_ID[jk.id]
                    if def and def.apply then
                        local ctx = { after_play = true, hand_type = ht, scoring = scoring }
                        local fx = def.apply(ctx, state, jk)
                        if fx and fx.level_up then
                            Sim.State.level_up(state, fx.level_up)
                        end
                    end
                end
            end

            local reward = math.log(math.max(1, total)) * R.HAND_SCORED
            -- Efficiency bonus: fewer hands = better
            reward = reward - 0.05 * state.hands_played
            local done = false

            if state.chips >= state.blind_chips then
                state.blind_beaten = true
                reward = reward + R.BLIND_BEATEN
                -- Dollar bonus for beating blind quickly
                reward = reward + math.log(math.max(1, state.dollars)) * 0.05
            end

            if state.hands_left <= 0 and not state.blind_beaten then
                done = true
                reward = reward + R.GAME_OVER
            end

            return Sim.Obs.encode(state), reward, done

        elseif value == 2 then
            -- DISCARD
            if state.discards_left <= 0 then
                return Sim.Obs.encode(state), R.INVALID, false
            end

            -- Determine discarded hand type BEFORE removing cards
            local disc_cards = {}
            for _, idx in ipairs(sorted) do
                disc_cards[#disc_cards+1] = state.hand[idx]
            end
            local disc_ht = Sim.Eval.get_hand(disc_cards)

            -- Trigger Burnt Joker (on_discard, is_first_discard)
            if state.jokers then
                for ji = 1, #state.jokers do
                    local jk = state.jokers[ji]
                    local def = Sim._JOKER_BY_ID[jk.id]
                    if def and def.apply then
                        local ctx = {
                            on_discard = true,
                            is_first_discard = (state.discards_left == D.discards),
                            discarded_hand_type = disc_ht,
                        }
                        local fx = def.apply(ctx, state, jk)
                        if fx and fx.level_up then
                            Sim.State.level_up(state, fx.level_up)
                        end
                    end
                end
            end

            for _, idx in ipairs(sorted) do
                local c = table.remove(state.hand, idx)
                if c then state.discard[#state.discard+1] = c end
            end
            state.discards_left = state.discards_left - 1
            Sim.State.draw(state)
            state.selection = {}

            return Sim.Obs.encode(state), 0, false
        end

        return Sim.Obs.encode(state), R.INVALID, false

    elseif atype == E.ACTION.PHASE_ACTION then
        -- value 3 = next (after blind beaten)
        if value == 3 and state.blind_beaten then
            return _advance_blind(state)
        end

    elseif atype == E.ACTION.USE_CONSUMABLE then
        return _use_consumable(state, value)

    elseif atype == E.ACTION.REORDER then
        return _do_reorder(state, value)
    end

    return Sim.Obs.encode(state), R.INVALID, false
end

function _advance_blind(state)
    local E = Sim.ENUMS
    local R = E.REWARD
    local names = {"Small","Big","Boss"}
    local bname = state.blind_type
    for i = 1, 3 do
        if names[i] == bname then Sim.Blind.mark_done(state, i); break end
    end

    -- Collect blind reward + interest
    local reward_dollars = Sim.Blind.reward(
        bname=="Small" and 1 or bname=="Big" and 2 or 3)
    state.dollars = state.dollars + reward_dollars + Sim.State.interest(state)

    -- Move played cards to discard, clear hand
    for _, c in ipairs(state.hand) do state.discard[#state.discard+1] = c end
    state.hand = {}
    state.selection = {}

    local next_btype = Sim.Blind.next_type(state)
    if not next_btype then
        -- Ante complete
        state.ante = state.ante + 1
        if state.ante > 8 then
            state.phase = E.PHASE.WIN
            return Sim.Obs.encode(state), R.GAME_WON, true
        end
        Sim.Blind.init_ante(state)
        next_btype = Sim.Blind.next_type(state)
        -- Voucher reset would go here
        Sim.Shop.generate(state)
        state.phase = E.PHASE.SHOP
        return Sim.Obs.encode(state), R.ANTE_UP, false
    else
        Sim.Blind.setup(state, next_btype)
        state.phase = E.PHASE.SELECTING_HAND
        return Sim.Obs.encode(state), 0, false
    end
end

local function _step_shop(state, atype, value)
    local E = Sim.ENUMS
    local R = E.REWARD

    if atype == E.ACTION.SHOP_ACTION then
        if value == 0 then
            Sim.Shop.reroll(state)
            return Sim.Obs.encode(state), 0, false
        elseif value >= 1 and value <= 2 then
            if Sim.Shop.buy_joker(state, value) then
                return Sim.Obs.encode(state), 0, false
            end
            return Sim.Obs.encode(state), R.INVALID, false
        elseif value == 3 then
            if Sim.Shop.buy_booster(state) then
                return Sim.Obs.encode(state), 0, false
            end
            return Sim.Obs.encode(state), R.INVALID, false
        elseif value == 4 then
            -- Buy consumable
            if Sim.Shop.buy_consumable(state) then
                return Sim.Obs.encode(state), 0, false
            end
            return Sim.Obs.encode(state), R.INVALID, false
        elseif value <= -1 and value >= -5 then
            if Sim.Shop.sell_joker(state, -value) then
                return Sim.Obs.encode(state), 0, false
            end
            return Sim.Obs.encode(state), R.INVALID, false
        end

    elseif atype == E.ACTION.USE_CONSUMABLE then
        -- Use consumable from area (not from shop)
        return _use_consumable(state, value)

    elseif atype == E.ACTION.REORDER then
        return _do_reorder(state, value)

    elseif atype == E.ACTION.PHASE_ACTION and value == 0 then
        -- End shop
        state.shop = nil
        local next_btype = Sim.Blind.next_type(state)
        if next_btype then
            Sim.Blind.setup(state, next_btype)
            state.phase = E.PHASE.SELECTING_HAND
        end
        return Sim.Obs.encode(state), 0, false
    end

    return Sim.Obs.encode(state), R.INVALID, false
end

local function _step_pack(state, atype, value)
    local E = Sim.ENUMS
    local R = E.REWARD

    if atype == E.ACTION.SELECT_CARDS then
        local idx = nil
        for i = 0, 2 do
            if (value >> i) & 1 == 1 then idx = i + 1; break end
        end
        if idx and Sim.Shop.select_pack(state, idx) then
            return Sim.Obs.encode(state), 0, false
        end
        return Sim.Obs.encode(state), R.INVALID, false

    elseif atype == E.ACTION.PHASE_ACTION and value == 0 then
        -- Skip pack
        Sim.Shop.skip_pack(state)
        return Sim.Obs.encode(state), 0, false
    end

    return Sim.Obs.encode(state), R.INVALID, false
end

-- ============================================================
-- Main step function
-- ============================================================



function Sim.Env.step(state, atype, value)
    local E = Sim.ENUMS

    if state.phase == E.PHASE.SELECTING_HAND then
        return _step_selecting(state, atype, value)
    elseif state.phase == E.PHASE.SHOP then
        return _step_shop(state, atype, value)
    elseif state.phase == E.PHASE.PACK_OPEN then
        return _step_pack(state, atype, value)
    elseif state.phase == E.PHASE.BLIND_SELECT then
        -- Auto-start next blind
        local next_btype = Sim.Blind.next_type(state)
        if next_btype then
            Sim.Blind.setup(state, next_btype)
            state.phase = E.PHASE.SELECTING_HAND
        end
        return Sim.Obs.encode(state), 0, state.phase == E.PHASE.WIN
    end

    -- GAME_OVER or WIN
    return Sim.Obs.encode(state), 0, true
end

-- ============================================================================


--  SECTION 12 — SELF-TEST & RANDOM AGENT
-- ============================================================================

if not pcall(debug.getlocal, 4, 1) then
    local E = Sim.ENUMS
    local C = Sim.Card.new
    local passed, total = 0, 0
    local function test(name, cond)
        total = total + 1
        if cond then passed = passed + 1; print("  [OK] " .. name)
        else print("  [FAIL] " .. name) end
    end

    print("=== BALATRO SIM v2 — Self-Test ===\n")

    -- Test: Pair + Joker
    local s = Sim.State.new({ seed="T1", jokers={{id=1,edition=0,eternal=false,uid=1}} })
    s.hand = { C(14,1), C(14,2), C(3,3), C(7,4), C(10,1), C(5,2), C(9,3), C(12,4) }
    local t,c,m,ht = Sim.Engine.calculate(s, {s.hand[1], s.hand[2]})
    test("Pair + Joker = 192", t == 192 and ht == 11)

    -- Test: Two Pair + Duo
    s = Sim.State.new({ seed="T2", jokers={{id=6,edition=0,eternal=false,uid=1}} })
    s.hand = { C(5,1), C(5,2), C(9,3), C(9,4), C(12,1), C(2,2), C(6,3), C(11,4) }
    t,c,m,ht = Sim.Engine.calculate(s, {s.hand[1],s.hand[2],s.hand[3],s.hand[4]})
    test("Two Pair + Duo = 192", t == 192 and ht == 10)

    -- Test: Blueprint copies Joker
    s = Sim.State.new({ seed="T3", jokers={
        {id=8,edition=0,eternal=false,uid=1},  -- Blueprint
        {id=1,edition=0,eternal=false,uid=2},  -- Joker
    }})
    s.hand = { C(7,1), C(7,2), C(2,3), C(4,4), C(11,1), C(8,2), C(13,3), C(6,4) }
    t,c,m,ht = Sim.Engine.calculate(s, {s.hand[1], s.hand[2]})
    test("Blueprint + Joker = 240", t == 240)

    -- Test: Flush
    s = Sim.State.new({ seed="T4" })
    s.hand = { C(2,2), C(5,2), C(9,2), C(11,2), C(14,2), C(3,1), C(8,3), C(13,4) }
    t,c,m,ht = Sim.Engine.calculate(s, {s.hand[1],s.hand[2],s.hand[3],s.hand[4],s.hand[5]})
    test("Flush = 288", t == 288 and ht == 7)

    -- Test: Observation dim
    local obs = Sim.Obs.encode(s)
    test("Observation dim = 129", #obs == 129)

    -- Test: Env reset
    obs, info = Sim.Env.reset("TEST_SEED")
    test("Env.reset returns obs", #obs == 129 and info.ante == 1)

    -- Test: Burnt Joker
    local bs = Sim.State.new({ seed="BJ", jokers={{id=9,edition=0,eternal=false,uid=1}} })
    bs.hand = { C(5,1), C(5,2), C(3,3), C(7,4), C(10,1), C(2,2), C(6,3), C(12,4) }
    bs.discards_left = 4  -- first discard of round
    -- Simulate discard via engine context
    local def = Sim._JOKER_BY_ID[9]  -- Burnt Joker
    local disc_ht = Sim.Eval.get_hand({bs.hand[3], bs.hand[4]})
    local ctx = { on_discard = true, is_first_discard = true, discarded_hand_type = disc_ht }
    local fx = def.apply(ctx, bs, bs.jokers[1])
    test("Burnt Joker triggers", fx ~= nil and fx.level_up ~= nil)

    -- Test: Consumable (Pluto levels up High Card)
    local cs = Sim.State.new({ seed="CONS" })
    cs.hand = { C(2,1), C(5,2), C(9,3), C(11,4), C(14,1), C(3,2), C(7,3), C(13,4) }
    local hl_before = cs.hand_levels[12]
    local pluto = Sim.CONSUMABLE_DEFS["c_pluto"]
    pluto.effect({}, cs)
    test("Pluto levels High Card", cs.hand_levels[12] == hl_before + 1)

    -- Test: REORDER swaps jokers
    local rs = Sim.State.new({ seed="REO", jokers={
        {id=1, edition=0, eternal=false, uid=1},
        {id=6, edition=0, eternal=false, uid=2},
    }})
    local id_before_1, id_before_2 = rs.jokers[1].id, rs.jokers[2].id
    local rv = (1 << 4) | 0 | (1 << 9)  -- src=0, tgt=1, mode=swap, area=joker
    _do_reorder(rs, rv)
    test("REORDER swaps jokers", rs.jokers[1].id == id_before_2 and rs.jokers[2].id == id_before_1)

    -- Test: Hiker gives permanent chips
    local hs = Sim.State.new({ seed="HIK", jokers={{id=21, edition=0, eternal=false, uid=1}} })
    hs.hand = { C(5,1), C(5,2), C(3,3), C(7,4), C(10,1), C(2,2), C(6,3), C(12,4) }
    local pb_before = hs.hand[1].perma_bonus
    Sim.Engine.calculate(hs, {hs.hand[1], hs.hand[2]})
    test("Hiker +4 perma_bonus", hs.hand[1].perma_bonus == pb_before + 4)

    -- Test: Shop has consumable slot
    local ss = Sim.State.new({ seed="SHOP" })
    Sim.Shop.generate(ss)
    test("Shop has consumable", ss.shop.consumable ~= nil)

    -- Test: Buy consumable from shop
    local bs2 = Sim.State.new({ seed="SHOP2" })
    Sim.Shop.generate(bs2)
    Sim.Shop.buy_consumable(bs2)
    test("Buy consumable works", #bs2.consumables == 1)

    -- Test: Empress enhances cards
    local es = Sim.State.new({ seed="EMP", consumables={{id=3, uid=1}} })
    es.hand = { C(5,1), C(5,2), C(3,3), C(7,4), C(10,1), C(2,2), C(6,3), C(12,4) }
    es.selection = {1, 2}
    _use_consumable(es, 1)
    test("Empress enhances to Mult", es.hand[1].enhancement == 2 and es.hand[2].enhancement == 2)

    print(string.format("\n  %d/%d tests passed\n", passed, total))

    -- ================================================================
    -- RANDOM AGENT: Play one full ante with Jokers + Consumables + Packs
    -- ================================================================
    print("=== Random Agent — Full Ante ===\n")

    local rng = Sim.RNG.new("AGENT42")
    local state = Sim.State.new({
        rng = rng, seed = "AGENT42",
        jokers = {
            {id=1, edition=0, eternal=false, uid=1},  -- Joker (+4 mult)
            {id=6, edition=0, eternal=false, uid=2},  -- The Duo (x2 on pair)
        },
    })
    Sim.Blind.init_ante(state)
    Sim.Blind.setup(state, 1)
    state.phase = E.PHASE.SELECTING_HAND

    local episode_reward = 0
    local step_count = 0

    while step_count < 500 do
        step_count = step_count + 1
        local atype, value

        if state.phase == E.PHASE.SELECTING_HAND then
            if state.blind_beaten then
                atype = E.ACTION.PHASE_ACTION; value = 3
            elseif state.hands_left <= 0 then
                break
            elseif #state.consumables > 0 and Sim.RNG.next(state.rng) < 0.4 then
                -- Use a consumable 40% of the time
                atype = E.ACTION.USE_CONSUMABLE; value = 1
            elseif #state.selection == 0 then
                local mask = 0
                local n = math.min(5, #state.hand)
                local indices = {}
                for i = 1, #state.hand do indices[#indices+1] = i end
                Sim.RNG.shuffle(state.rng, indices)
                for i = 1, n do mask = mask | (1 << (indices[i] - 1)) end
                atype = E.ACTION.SELECT_CARDS; value = mask
            else
                atype = E.ACTION.PLAY_DISCARD
                value = (state.discards_left > 0 and Sim.RNG.next(state.rng) < 0.3) and 2 or 1
            end

        elseif state.phase == E.PHASE.SHOP then
            local action_taken = false
            if state.shop then
                -- Buy a joker if affordable and has slot
                for si = 1, 2 do
                    if not action_taken and state.shop.jokers[si] and
                       state.dollars >= state.shop.jokers[si].cost and
                       #state.jokers < state.joker_slots then
                        atype = E.ACTION.SHOP_ACTION; value = si; action_taken = true
                    end
                end
                -- Buy a booster pack (50% chance if affordable)
                if not action_taken and state.shop.booster and
                   state.dollars >= state.shop.booster.cost and
                   Sim.RNG.next(state.rng) < 0.5 then
                    atype = E.ACTION.SHOP_ACTION; value = 3; action_taken = true
                end
                -- Grab free consumable
                if not action_taken and state.shop.consumable and
                   #state.consumables < state.consumable_slots then
                    atype = E.ACTION.SHOP_ACTION; value = 4; action_taken = true
                end
            end
            if not action_taken then atype = E.ACTION.PHASE_ACTION; value = 0 end

        elseif state.phase == E.PHASE.PACK_OPEN then
            if state.pack_cards and #state.pack_cards > 0 then
                local pick = Sim.RNG.int(state.rng, 1, #state.pack_cards)
                atype = E.ACTION.SELECT_CARDS; value = 1 << (pick - 1)
            else
                atype = E.ACTION.PHASE_ACTION; value = 0
            end

        elseif state.phase == E.PHASE.BLIND_SELECT then
            atype = E.ACTION.PHASE_ACTION; value = 1

        else break end

        if atype then
            local obs, reward, done = Sim.Env.step(state, atype, value)
            episode_reward = episode_reward + reward
            if done then break end
        end
    end

    -- Print final stats
    if state.phase == E.PHASE.WIN then
        print(string.format("  [WIN] GAME WON! Ante %d", state.ante))
    else
        print(string.format("  Game Over at Ante %d %s: %d / %d chips",
            state.ante, state.blind_type, state.chips, state.blind_chips))
    end
    print(string.format("  Steps: %d | Reward: %.1f | Jokers: %d | Consumables: %d | $%d",
        step_count, episode_reward, #state.jokers, #state.consumables, state.dollars))
    if #state.jokers > 0 then
        for _, jk in ipairs(state.jokers) do
            local def = Sim._JOKER_BY_ID[jk.id]
            print(string.format("    - %s", def.name))
        end
    end
    local has_levels = false
    for i = 1, 12 do
        if state.hand_levels[i] > 1 then has_levels = true; break end
    end
    if has_levels then
        print("  Hand levels:")
        for i = 1, 12 do
            if state.hand_levels[i] > 1 then
                print(string.format("    - %s: Lv.%d", E.HAND_NAME[i], state.hand_levels[i]))
            end
        end
    end

    print("\n=== Done ===\n")
end

return Sim

