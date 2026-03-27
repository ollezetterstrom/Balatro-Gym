--[[
    balatro_sim.lua — Headless Balatro Simulation Engine v3

    Merged build from src/*.lua modules. Do not edit directly — edit src/ instead.
    To regenerate: python build.py merge

    Usage:
        lua balatro_sim.lua              — runs self-tests + random agent
        local Sim = dofile("balatro_sim.lua")  — use as library

    API:
        Sim.Env.reset(seed) → obs, info
        Sim.Env.step(state, action_type, action_value) → obs, reward, done, info
        Sim.Obs.encode(state) → flat float array (129 floats)
        Sim.Env.action_spec → { types, obs_dim }
]]


--[[
    balatro_sim.lua — Headless Balatro Simulation Engine v3

    Pure-Lua, zero-graphics simulation of Balatro for AI training.
    Deterministic RNG, stateless scoring, synchronous execution.

    Usage:
        lua validate.lua                     — run scoring validation (49 tests)
        lua -e "_SIM_RUN_TESTS=true" balatro_sim.lua  — run self-tests + random agent
        local Sim = dofile("balatro_sim.lua")  — use as library

    API:
        Sim.Env.reset(seed) → obs, info
        Sim.Env.step(state, action_type, action_value) → obs, reward, done, info
        Sim.Obs.encode(state) → flat float array (129 floats)
        Sim.Env.action_spec → { types, obs_dim }

    Observation layout (129 floats, 1-indexed Lua):
        [1..48]    8 hand card slots × 6 features (rank, suit, enh, edition, seal, has_card)
        [49..63]   5 joker slots × 3 features (id, edition, has_joker)
        [64..71]   8 global features (chips%, $, hands_left, discards_left, ante, round, blind_beaten, deck%)
        [72..83]   12 hand levels (log-scaled, capped at 1.0)
        [84..86]   Phase one-hot (SELECTING_HAND, SHOP, PACK_OPEN)
        [87]       Selection count / 8
        [88..91]   2 consumable slots × 2 features (id, has_consumable)
        [92]       Pack open flag
        [93..122]  5 pack card slots × 6 features
        [123..126] Shop items present (joker1, joker2, booster, consumable)
        [127]      Joker count / 5
        [128]      Consumable count / 2
        [129]      Spare (currently round_dollars or 0)
]]

Sim = Sim or {}


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
function Sim.RNG.int(r, lo, hi)
    local n = hi - lo + 1
    return lo + math.floor(Sim.RNG.next(r) * n * (1 - 1e-9))
end
function Sim.RNG.shuffle(r, t)
    for i = #t, 2, -1 do
        local j = 1 + math.floor(Sim.RNG.next(r) * i * (1 - 1e-9))
        t[i], t[j] = t[j], t[i]
    end
    return t
end
function Sim.RNG.pick(r, t) return t[Sim.RNG.int(r, 1, #t)] end


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
    if card.enhancement == Sim.ENUMS.ENHANCEMENT.STONE then return 50 + card.perma_bonus end
    return Sim.ENUMS.RANK_NOMINAL[card.rank] + card.perma_bonus
end
function Sim.Card.str(card)
    local E = Sim.ENUMS
    local t = (E.RANK_SYM[card.rank] or "?") .. (E.SUIT_SYM[card.suit] or "?")
    if card.enhancement == E.ENHANCEMENT.BONUS then t = t.."+30" end
    if card.enhancement == E.ENHANCEMENT.GLASS then t = t.."x2" end
    if card.enhancement == E.ENHANCEMENT.STONE then t = t.."." end
    if card.edition == E.EDITION.FOIL then t = t.."[F]" end
    if card.edition == E.EDITION.HOLO then t = t.."[H]" end
    if card.edition == E.EDITION.POLYCHROME then t = t.."[P]" end
    return t
end


Sim.JOKER_DEFS = {}
Sim._JOKER_BY_ID = {}

function Sim._reg_joker(key, name, rarity, cost, apply_fn)
    if Sim.JOKER_DEFS[key] then
        local old = Sim.JOKER_DEFS[key]
        old.apply = apply_fn
        old.name = name
        old.rarity = rarity
        old.cost = cost
        return old
    end
    local def = { id = #Sim._JOKER_BY_ID + 1, key = key, name = name,
                  rarity = rarity, cost = cost, apply = apply_fn }
    Sim.JOKER_DEFS[key] = def
    Sim._JOKER_BY_ID[def.id] = def
    return def
end

Sim._reg_joker("j_joker", "Joker", 1, 3, function(ctx, st, jk)
    if ctx.joker_main then return { mult_mod = 4 } end
end)

local E = Sim.ENUMS

local function _is_suit(card, target_suit)
    return card.suit == target_suit or card.enhancement == E.ENHANCEMENT.WILD
end

Sim._reg_joker("j_greedy", "Greedy Joker", 1, 5, function(ctx, st, jk)
    if ctx.individual and ctx.other_card and ctx.cardarea == "play" then
        if _is_suit(ctx.other_card, E.SUIT.DIAMONDS) then return { mult = 3 } end
    end
end)

Sim._reg_joker("j_lusty", "Lusty Joker", 1, 5, function(ctx, st, jk)
    if ctx.individual and ctx.other_card and ctx.cardarea == "play" then
        if _is_suit(ctx.other_card, E.SUIT.HEARTS) then return { mult = 3 } end
    end
end)

Sim._reg_joker("j_wrathful", "Wrathful Joker", 1, 5, function(ctx, st, jk)
    if ctx.individual and ctx.other_card and ctx.cardarea == "play" then
        if _is_suit(ctx.other_card, E.SUIT.SPADES) then return { mult = 3 } end
    end
end)

Sim._reg_joker("j_gluttonous", "Gluttonous Joker", 1, 5, function(ctx, st, jk)
    if ctx.individual and ctx.other_card and ctx.cardarea == "play" then
        if _is_suit(ctx.other_card, E.SUIT.CLUBS) then return { mult = 3 } end
    end
end)

Sim._reg_joker("j_the_duo", "The Duo", 3, 8, function(ctx, st, jk)
    if ctx.joker_main and ctx.all_hands and ctx.all_hands[11] then
        return { Xmult_mod = 2 }
    end
end)

Sim._reg_joker("j_the_trio", "The Trio", 3, 8, function(ctx, st, jk)
    if ctx.joker_main and ctx.all_hands and ctx.all_hands[9] then
        return { Xmult_mod = 3 }
    end
end)

Sim._reg_joker("j_blueprint", "Blueprint", 3, 10, function(ctx, st, jk)
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

Sim._reg_joker("j_burnt_joker", "Burnt Joker", 3, 8, function(ctx, st, jk)
    if ctx.on_discard and ctx.is_first_discard then
        return { level_up = ctx.discarded_hand_type }
    end
end)

-- === New jokers (10 common/uncommon) ===

Sim._reg_joker("j_stencil", "Joker Stencil", 2, 8, function(ctx, st, jk)
    if ctx.joker_main then
        local empty = st.joker_slots - #st.jokers
        if empty > 0 then return { Xmult_mod = 1 + empty } end
    end
end)

Sim._reg_joker("j_banner", "Banner", 1, 5, function(ctx, st, jk)
    if ctx.joker_main then
        return { chip_mod = 30 * (st.discards_left or 0) }
    end
end)

Sim._reg_joker("j_mystic_summit", "Mystic Summit", 1, 5, function(ctx, st, jk)
    if ctx.joker_main and (st.discards_left or 0) == 0 then
        return { mult_mod = 15 }
    end
end)

Sim._reg_joker("j_misprint", "Misprint", 1, 4, function(ctx, st, jk)
    if ctx.joker_main then
        return { mult_mod = Sim.RNG.int(st.rng, 0, 23) }
    end
end)

Sim._reg_joker("j_fibonacci", "Fibonacci", 2, 8, function(ctx, st, jk)
    if ctx.individual and ctx.other_card then
        local r = ctx.other_card.rank
        if r == 14 or r == 2 or r == 3 or r == 5 or r == 8 then
            return { mult = 8 }
        end
    end
end)

Sim._reg_joker("j_scary_face", "Scary Face", 1, 4, function(ctx, st, jk)
    if ctx.individual and ctx.other_card then
        local r = ctx.other_card.rank
        if r == E.RANK.JACK or r == E.RANK.QUEEN or r == E.RANK.KING then
            return { chips = 30 }
        end
    end
end)

Sim._reg_joker("j_even_steven", "Even Steven", 1, 5, function(ctx, st, jk)
    if ctx.individual and ctx.other_card then
        local r = ctx.other_card.rank
        if r == 2 or r == 4 or r == 6 or r == 8 or r == 10 then
            return { mult = 4 }
        end
    end
end)

Sim._reg_joker("j_odd_todd", "Odd Todd", 1, 5, function(ctx, st, jk)
    if ctx.individual and ctx.other_card then
        local r = ctx.other_card.rank
        if r == 3 or r == 5 or r == 7 or r == 9 or r == E.RANK.ACE then
            return { chips = 31 }
        end
    end
end)

Sim._reg_joker("j_scholar", "Scholar", 1, 4, function(ctx, st, jk)
    if ctx.individual and ctx.other_card then
        if ctx.other_card.rank == E.RANK.ACE then
            return { chips = 20, mult = 4 }
        end
    end
end)

Sim._reg_joker("j_sly", "Sly Joker", 1, 3, function(ctx, st, jk)
    if ctx.joker_main then
        return { chip_mod = 50 }
    end
end)

-- === New jokers (7 uncommon/rare) ===

Sim._reg_joker("j_delayed_gratification", "Delayed Gratification", 1, 4, function(ctx, st, jk)
    if ctx.round_end then
        -- Only if no discards were used this round
        local total_discards = Sim.DEFAULTS.discards
        if st.discards_left == total_discards then
            return { dollars = 2 * st.discards_left }
        end
    end
end)

Sim._reg_joker("j_supernova", "Supernova", 1, 5, function(ctx, st, jk)
    if ctx.joker_main and ctx.hand_type then
        local played = st.hand_type_counts[ctx.hand_type] or 0
        if played > 0 then return { mult_mod = played } end
    end
end)

Sim._reg_joker("j_ride_the_bus", "Ride the Bus", 1, 5, function(ctx, st, jk)
    if ctx.joker_main then
        if st.ride_the_bus and st.ride_the_bus > 0 then
            return { mult_mod = st.ride_the_bus }
        end
    end
end)

Sim._reg_joker("j_blackboard", "Blackboard", 2, 6, function(ctx, st, jk)
    if ctx.joker_main then
        local all_dark = true
        for _, c in ipairs(st.hand) do
            if c.enhancement ~= E.ENHANCEMENT.STONE
               and c.enhancement ~= E.ENHANCEMENT.WILD
               and c.suit ~= E.SUIT.SPADES
               and c.suit ~= E.SUIT.CLUBS then
                all_dark = false; break
            end
        end
        if all_dark then return { Xmult_mod = 3 } end
    end
end)

Sim._reg_joker("j_ramen", "Ramen", 2, 6, function(ctx, st, jk)
    if ctx.on_discard then
        -- Lose 0.01 x_mult per card discarded
        jk._ramen_x = (jk._ramen_x or 2.0) - 0.01 * (ctx.cards_discarded or 1)
        if jk._ramen_x <= 1 then
            return { destroy_self = true }
        end
    end
    if ctx.joker_main then
        local x = jk._ramen_x or 2.0
        if x > 1 then return { Xmult_mod = x } end
    end
end)

Sim._reg_joker("j_acrobat", "Acrobat", 2, 6, function(ctx, st, jk)
    if ctx.joker_main and st.hands_left == 0 then
        return { Xmult_mod = 3 }
    end
end)

Sim._reg_joker("j_sock_and_buskin", "Sock and Buskin", 2, 6, function(ctx, st, jk)
    -- Handled in engine re-trigger loop
end)

-- === Type Mult (hand-type bonus mult) ===

Sim._reg_joker("j_jolly", "Jolly Joker", 1, 3, function(ctx, st, jk)
    if ctx.joker_main and ctx.all_hands and ctx.all_hands[E.HAND_TYPE.PAIR] then return { mult_mod = 8 } end
end)
Sim._reg_joker("j_zany", "Zany Joker", 1, 4, function(ctx, st, jk)
    if ctx.joker_main and ctx.all_hands and ctx.all_hands[E.HAND_TYPE.THREE_OF_A_KIND] then return { mult_mod = 12 } end
end)
Sim._reg_joker("j_mad", "Mad Joker", 1, 4, function(ctx, st, jk)
    if ctx.joker_main and ctx.all_hands and ctx.all_hands[E.HAND_TYPE.TWO_PAIR] then return { mult_mod = 10 } end
end)
Sim._reg_joker("j_crazy", "Crazy Joker", 1, 4, function(ctx, st, jk)
    if ctx.joker_main and ctx.all_hands and ctx.all_hands[E.HAND_TYPE.STRAIGHT] then return { mult_mod = 12 } end
end)
Sim._reg_joker("j_droll", "Droll Joker", 1, 4, function(ctx, st, jk)
    if ctx.joker_main and ctx.all_hands and ctx.all_hands[E.HAND_TYPE.FLUSH] then return { mult_mod = 10 } end
end)

-- === Type Chips (hand-type bonus chips) ===

Sim._reg_joker("j_wily", "Wily Joker", 1, 4, function(ctx, st, jk)
    if ctx.joker_main and ctx.all_hands and ctx.all_hands[E.HAND_TYPE.THREE_OF_A_KIND] then return { chip_mod = 100 } end
end)
Sim._reg_joker("j_clever", "Clever Joker", 1, 4, function(ctx, st, jk)
    if ctx.joker_main and ctx.all_hands and ctx.all_hands[E.HAND_TYPE.TWO_PAIR] then return { chip_mod = 80 } end
end)
Sim._reg_joker("j_devious", "Devious Joker", 1, 4, function(ctx, st, jk)
    if ctx.joker_main and ctx.all_hands and ctx.all_hands[E.HAND_TYPE.STRAIGHT] then return { chip_mod = 100 } end
end)
Sim._reg_joker("j_crafty", "Crafty Joker", 1, 4, function(ctx, st, jk)
    if ctx.joker_main and ctx.all_hands and ctx.all_hands[E.HAND_TYPE.FLUSH] then return { chip_mod = 80 } end
end)

-- === Xmult for hand type ===

Sim._reg_joker("j_the_family", "The Family", 3, 8, function(ctx, st, jk)
    if ctx.joker_main and ctx.all_hands and ctx.all_hands[E.HAND_TYPE.FOUR_OF_A_KIND] then return { Xmult_mod = 4 } end
end)
Sim._reg_joker("j_the_order", "The Order", 3, 8, function(ctx, st, jk)
    if ctx.joker_main and ctx.all_hands and ctx.all_hands[E.HAND_TYPE.STRAIGHT] then return { Xmult_mod = 3 } end
end)
Sim._reg_joker("j_the_tribe", "The Tribe", 3, 8, function(ctx, st, jk)
    if ctx.joker_main and ctx.all_hands and ctx.all_hands[E.HAND_TYPE.FLUSH] then return { Xmult_mod = 2 } end
end)

-- === Simple scoring jokers ===

Sim._reg_joker("j_half_joker", "Half Joker", 1, 5, function(ctx, st, jk)
    if ctx.joker_main and #st.hand <= 3 then return { mult_mod = 20 } end
end)
Sim._reg_joker("j_juggler", "Juggler", 1, 4, function(ctx, st, jk)
    -- +1 hand size (passive, handled in state)
end)
Sim._reg_joker("j_drunkard", "Drunkard", 1, 4, function(ctx, st, jk)
    -- +1 discard (passive, handled in state)
end)
Sim._reg_joker("j_abstract", "Abstract Joker", 1, 4, function(ctx, st, jk)
    if ctx.joker_main then return { mult_mod = 3 * #st.jokers } end
end)
Sim._reg_joker("j_raised_fist", "Raised Fist", 1, 5, function(ctx, st, jk)
    if ctx.joker_main then
        local min_rank, min_card = 15, nil
        for _, c in ipairs(st.hand) do
            if c.enhancement ~= E.ENHANCEMENT.STONE and c.rank < min_rank then min_rank = c.rank; min_card = c end
        end
        if min_card then return { mult_mod = min_rank * 2 } end
    end
end)
Sim._reg_joker("j_swashbuckler", "Swashbuckler", 1, 4, function(ctx, st, jk)
    if ctx.joker_main then return { mult_mod = #st.jokers } end
end)
Sim._reg_joker("j_walkie_talkie", "Walkie Talkie", 1, 4, function(ctx, st, jk)
    if ctx.individual and ctx.other_card then
        local r = ctx.other_card.rank
        if r == 10 or r == 4 then return { chips = 10, mult = 4 } end
    end
end)
Sim._reg_joker("j_smiley", "Smiley Face", 1, 4, function(ctx, st, jk)
    if ctx.individual and ctx.other_card and ctx.cardarea == "play" then
        local r = ctx.other_card.rank
        if r >= E.RANK.JACK and r <= E.RANK.KING then return { mult = 5 } end
    end
end)
Sim._reg_joker("j_shoot_the_moon", "Shoot the Moon", 1, 5, function(ctx, st, jk)
    if ctx.individual and ctx.other_card and ctx.cardarea == "hand" then
        if _is_suit(ctx.other_card, E.SUIT.HEARTS) then return { mult = 13 } end
    end
end)
Sim._reg_joker("j_popcorn", "Popcorn", 1, 5, function(ctx, st, jk)
    if ctx.joker_main then
        jk._popcorn_mult = (jk._popcorn_mult or 20) - 4
        if jk._popcorn_mult <= 0 then return { destroy_self = true } end
        return { mult_mod = jk._popcorn_mult }
    end
end)
Sim._reg_joker("j_golden", "Golden Joker", 1, 6, function(ctx, st, jk)
    if ctx.round_end then return { dollars = 4 } end
end)
Sim._reg_joker("j_credit_card", "Credit Card", 1, 1, function(ctx, st, jk)
    -- -$20 debt limit (passive)
end)
Sim._reg_joker("j_chaos", "Chaos the Clown", 1, 4, function(ctx, st, jk)
    -- Free reroll per shop (passive)
end)
Sim._reg_joker("j_egg", "Egg", 1, 4, function(ctx, st, jk)
    -- +3 sell value per round (passive)
end)
Sim._reg_joker("j_faceless", "Faceless Joker", 1, 4, function(ctx, st, jk)
    if ctx.round_end and st.discard then
        local faces = 0
        for _, c in ipairs(st.discard) do
            if c.rank >= E.RANK.JACK and c.rank <= E.RANK.KING then faces = faces + 1 end
        end
        if faces >= 3 then return { dollars = 5 } end
    end
end)
Sim._reg_joker("j_business", "Business Card", 1, 4, function(ctx, st, jk)
    if ctx.individual and ctx.other_card and ctx.cardarea == "play" then
        local r = ctx.other_card.rank
        if r >= E.RANK.JACK and r <= E.RANK.KING then
            if Sim.RNG.next(st.rng) < 0.5 then return { dollars = 2 } end
        end
    end
end)
Sim._reg_joker("j_reserved_parking", "Reserved Parking", 1, 6, function(ctx, st, jk)
    if ctx.individual and ctx.other_card and ctx.cardarea == "hand" then
        local r = ctx.other_card.rank
        if r >= E.RANK.JACK and r <= E.RANK.KING then
            if Sim.RNG.next(st.rng) < 0.5 then return { dollars = 1 } end
        end
    end
end)
Sim._reg_joker("j_mail", "Mail-In Rebate", 1, 4, function(ctx, st, jk)
    if ctx.individual and ctx.other_card then
        if ctx.other_card.rank == jk._mail_rank then return { dollars = 5 } end
    end
    if ctx.joker_main then
        jk._mail_rank = Sim.RNG.int(st.rng, 2, 14)
    end
end)
Sim._reg_joker("j_hanging_chad", "Hanging Chad", 1, 4, function(ctx, st, jk)
    -- Re-trigger first scored card 2 extra times (handled in engine)
end)
Sim._reg_joker("j_ticket", "Golden Ticket", 1, 5, function(ctx, st, jk)
    if ctx.individual and ctx.other_card and ctx.cardarea == "play" then
        if ctx.other_card.enhancement == E.ENHANCEMENT.GOLD then return { dollars = 4 } end
    end
end)
Sim._reg_joker("j_fortune_teller", "Fortune Teller", 1, 6, function(ctx, st, jk)
    if ctx.joker_main then return { mult_mod = st._tarot_used or 0 } end
end)

-- === Uncommon jokers ===

Sim._reg_joker("j_four_fingers", "Four Fingers", 2, 7, function(ctx, st, jk)
    -- 4 cards for flush/straight (handled in evaluator)
end)
Sim._reg_joker("j_shortcut", "Shortcut", 2, 7, function(ctx, st, jk)
    -- Skip ranks in straight (handled in evaluator)
end)
Sim._reg_joker("j_pareidolia", "Pareidolia", 2, 5, function(ctx, st, jk)
    -- All cards count as face cards (handled in is_face checks)
end)
Sim._reg_joker("j_mime", "Mime", 2, 5, function(ctx, st, jk)
    -- Re-trigger held-in-hand effects (handled in engine)
end)
Sim._reg_joker("j_marble", "Marble Joker", 2, 6, function(ctx, st, jk)
    -- Add Stone card to deck on blind start (complex)
end)
Sim._reg_joker("j_loyalty_card", "Loyalty Card", 2, 5, function(ctx, st, jk)
    if ctx.joker_main then
        jk._loyalty = (jk._loyalty or 0) + 1
        if jk._loyalty >= 5 then jk._loyalty = 0; return { Xmult_mod = 4 } end
    end
end)
Sim._reg_joker("j_8_ball", "8 Ball", 1, 5, function(ctx, st, jk)
    if ctx.individual and ctx.other_card and ctx.cardarea == "play" then
        if ctx.other_card.rank == 8 then
            if Sim.RNG.next(st.rng) < 0.25 then return { create_tarot = true } end
        end
    end
end)
Sim._reg_joker("j_dusk", "Dusk", 2, 5, function(ctx, st, jk)
    -- Re-trigger all played cards on last hand (handled in engine)
end)
Sim._reg_joker("j_hack", "Hack", 2, 6, function(ctx, st, jk)
    -- Re-trigger 2-5 cards (handled in engine)
end)
Sim._reg_joker("j_gros_michel", "Gros Michel", 1, 5, function(ctx, st, jk)
    if ctx.joker_main then
        if Sim.RNG.next(st.rng) < (1/6) then
            return { destroy_self = true }
        end
        return { mult_mod = 15 }
    end
end)
Sim._reg_joker("j_cavendish", "Cavendish", 1, 4, function(ctx, st, jk)
    if ctx.joker_main then
        if Sim.RNG.next(st.rng) < (1/1000) then return { destroy_self = true } end
        return { Xmult_mod = 3 }
    end
end)
Sim._reg_joker("j_steel_joker", "Steel Joker", 2, 7, function(ctx, st, jk)
    if ctx.joker_main then
        local steel_count = 0
        for _, c in ipairs(st.deck) do if c.enhancement == E.ENHANCEMENT.STEEL then steel_count = steel_count + 1 end end
        for _, c in ipairs(st.hand) do if c.enhancement == E.ENHANCEMENT.STEEL then steel_count = steel_count + 1 end end
        if steel_count > 0 then return { Xmult_mod = 1 + 0.2 * steel_count } end
    end
end)
Sim._reg_joker("j_stone", "Stone Joker", 2, 6, function(ctx, st, jk)
    if ctx.joker_main then
        local stone_count = 0
        for _, c in ipairs(st.deck) do if c.enhancement == E.ENHANCEMENT.STONE then stone_count = stone_count + 1 end end
        for _, c in ipairs(st.hand) do if c.enhancement == E.ENHANCEMENT.STONE then stone_count = stone_count + 1 end end
        return { chip_mod = 25 * stone_count }
    end
end)
Sim._reg_joker("j_space", "Space Joker", 2, 5, function(ctx, st, jk)
    if ctx.after_play then
        if Sim.RNG.next(st.rng) < 0.25 then return { level_up = ctx.hand_type } end
    end
end)
Sim._reg_joker("j_burglar", "Burglar", 2, 6, function(ctx, st, jk)
    if ctx.setting_blind then
        st.hands_left = st.hands_left + 3
        st.discards_left = 0
    end
end)
Sim._reg_joker("j_runner", "Runner", 1, 5, function(ctx, st, jk)
    if ctx.after_play and ctx.all_hands and ctx.all_hands[E.HAND_TYPE.STRAIGHT] then
        jk._runner_chips = (jk._runner_chips or 0) + 15
    end
    if ctx.joker_main then return { chip_mod = jk._runner_chips or 0 } end
end)
Sim._reg_joker("j_ice_cream", "Ice Cream", 1, 5, function(ctx, st, jk)
    if ctx.joker_main then
        jk._ice_chips = (jk._ice_chips or 100) - 5
        if jk._ice_chips <= 0 then return { destroy_self = true } end
        return { chip_mod = jk._ice_chips }
    end
end)
Sim._reg_joker("j_blue_joker", "Blue Joker", 1, 5, function(ctx, st, jk)
    if ctx.joker_main then return { chip_mod = 2 * #st.deck } end
end)
Sim._reg_joker("j_constellation", "Constellation", 2, 6, function(ctx, st, jk)
    if ctx.after_play and ctx.planet_used then
        jk._constellation_x = (jk._constellation_x or 1) + 0.1
    end
    if ctx.joker_main then return { Xmult_mod = jk._constellation_x or 1 } end
end)
Sim._reg_joker("j_green_joker", "Green Joker", 1, 4, function(ctx, st, jk)
    if ctx.after_play then jk._green_mult = (jk._green_mult or 0) + 1 end
    if ctx.on_discard then jk._green_mult = math.max(0, (jk._green_mult or 0) - 1) end
    if ctx.joker_main then return { mult_mod = jk._green_mult or 0 } end
end)
Sim._reg_joker("j_card_sharp", "Card Sharp", 2, 6, function(ctx, st, jk)
    if ctx.joker_main and ctx.hand_type then
        if (st.hand_type_counts[ctx.hand_type] or 0) > 0 then return { Xmult_mod = 3 } end
    end
end)
Sim._reg_joker("j_red_card", "Red Card", 1, 5, function(ctx, st, jk)
    if ctx.skipping_booster then jk._red_mult = (jk._red_mult or 0) + 3 end
    if ctx.joker_main then return { mult_mod = jk._red_mult or 0 } end
end)
Sim._reg_joker("j_square", "Square Joker", 1, 4, function(ctx, st, jk)
    if ctx.after_play and #st.hand == 4 then
        jk._square_chips = (jk._square_chips or 0) + 4
    end
    if ctx.joker_main then return { chip_mod = jk._square_chips or 0 } end
end)
Sim._reg_joker("j_vampire", "Vampire", 2, 7, function(ctx, st, jk)
    if ctx.after_play then
        local enhanced = 0
        for _, c in ipairs(ctx.scoring or {}) do
            if c.enhancement > 0 then enhanced = enhanced + 1; c.enhancement = 0 end
        end
        if enhanced > 0 then jk._vamp_x = (jk._vamp_x or 1) + 0.1 * enhanced end
    end
    if ctx.joker_main then return { Xmult_mod = jk._vamp_x or 1 } end
end)
Sim._reg_joker("j_hologram", "Hologram", 2, 7, function(ctx, st, jk)
    if ctx.playing_card_added then jk._holo_x = (jk._holo_x or 1) + 0.25 end
    if ctx.joker_main then return { Xmult_mod = jk._holo_x or 1 } end
end)
Sim._reg_joker("j_baron", "Baron", 3, 8, function(ctx, st, jk)
    if ctx.individual and ctx.other_card and ctx.cardarea == "hand" then
        if ctx.other_card.rank == E.RANK.KING then return { x_mult = 1.5 } end
    end
end)
Sim._reg_joker("j_cloud_9", "Cloud 9", 2, 7, function(ctx, st, jk)
    if ctx.round_end then
        local nines = 0
        for _, c in ipairs(st.deck) do if c.rank == 9 then nines = nines + 1 end end
        for _, c in ipairs(st.hand) do if c.rank == 9 then nines = nines + 1 end end
        return { dollars = nines }
    end
end)
Sim._reg_joker("j_rocket", "Rocket", 2, 6, function(ctx, st, jk)
    if ctx.round_end then
        jk._rocket_dollars = (jk._rocket_dollars or 1) + 2
        return { dollars = jk._rocket_dollars }
    end
end)
Sim._reg_joker("j_obelisk", "Obelisk", 3, 8, function(ctx, st, jk)
    if ctx.after_play and ctx.hand_type then
        if (st.hand_type_counts[ctx.hand_type] or 0) == 0 then jk._obelisk_reset = true end
        if jk._obelisk_reset then jk._obelisk_x = 1 else jk._obelisk_x = (jk._obelisk_x or 1) + 0.2 end
    end
    if ctx.joker_main then return { Xmult_mod = jk._obelisk_x or 1 } end
end)
Sim._reg_joker("j_to_the_moon", "To the Moon", 2, 5, function(ctx, st, jk)
    -- +1 extra interest per $5 (passive, handled in interest calc)
end)
Sim._reg_joker("j_flash", "Flash Card", 2, 5, function(ctx, st, jk)
    if ctx.reroll_shop then jk._flash_mult = (jk._flash_mult or 0) + 2 end
    if ctx.joker_main then return { mult_mod = jk._flash_mult or 0 } end
end)
Sim._reg_joker("j_trousers", "Spare Trousers", 2, 6, function(ctx, st, jk)
    if ctx.after_play and ctx.all_hands and ctx.all_hands[E.HAND_TYPE.TWO_PAIR] then
        jk._trousers_mult = (jk._trousers_mult or 0) + 2
    end
    if ctx.joker_main then return { mult_mod = jk._trousers_mult or 0 } end
end)
Sim._reg_joker("j_lucky_cat", "Lucky Cat", 2, 6, function(ctx, st, jk)
    if ctx.lucky_trigger then jk._lucky_x = (jk._lucky_x or 1) + 0.25 end
    if ctx.joker_main then return { Xmult_mod = jk._lucky_x or 1 } end
end)
Sim._reg_joker("j_baseball", "Baseball Card", 3, 8, function(ctx, st, jk)
    if ctx.joker_main then
        local bonus = 1
        for _, j in ipairs(st.jokers) do
            if j ~= jk then
                local def = Sim._JOKER_BY_ID[j.id]
                if def and def.rarity == 2 then bonus = bonus * 1.5 end
            end
        end
        if bonus > 1 then return { Xmult_mod = bonus } end
    end
end)
Sim._reg_joker("j_bull", "Bull", 2, 6, function(ctx, st, jk)
    if ctx.joker_main then return { chip_mod = 2 * math.max(st.dollars, 0) } end
end)
Sim._reg_joker("j_trading", "Trading Card", 2, 6, function(ctx, st, jk)
    -- Discard 1 card for $3 if first discard (complex)
end)
Sim._reg_joker("j_ancient", "Ancient Joker", 3, 8, function(ctx, st, jk)
    if ctx.individual and ctx.other_card and ctx.cardarea == "play" then
        if _is_suit(ctx.other_card, jk._ancient_suit or E.SUIT.SPADES) then
            return { x_mult = 1.5 }
        end
    end
    if ctx.joker_main then
        local suits = {E.SUIT.SPADES, E.SUIT.HEARTS, E.SUIT.CLUBS, E.SUIT.DIAMONDS}
        jk._ancient_suit = suits[Sim.RNG.int(st.rng, 1, 4)]
    end
end)
Sim._reg_joker("j_selzer", "Seltzer", 2, 6, function(ctx, st, jk)
    -- Re-trigger all played cards for next 10 hands (handled in engine)
end)
Sim._reg_joker("j_castle", "Castle", 2, 6, function(ctx, st, jk)
    if ctx.on_discard and ctx.other_card then
        if ctx.other_card.suit == jk._castle_suit then jk._castle_chips = (jk._castle_chips or 0) + 3 end
    end
    if ctx.joker_main then return { chip_mod = jk._castle_chips or 0 } end
end)
Sim._reg_joker("j_campfire", "Campfire", 3, 9, function(ctx, st, jk)
    if ctx.selling_card then jk._campfire_x = (jk._campfire_x or 1) + 0.25 end
    if ctx.joker_main then return { Xmult_mod = jk._campfire_x or 1 } end
end)
Sim._reg_joker("j_midas_mask", "Midas Mask", 2, 7, function(ctx, st, jk)
    -- Face cards played become Gold (complex)
end)
Sim._reg_joker("j_luchador", "Luchador", 2, 5, function(ctx, st, jk)
    -- Disable boss blind when sold (complex)
end)
Sim._reg_joker("j_photograph", "Photograph", 1, 5, function(ctx, st, jk)
    if ctx.individual and ctx.other_card and ctx.cardarea == "play" then
        local r = ctx.other_card.rank
        if r >= E.RANK.JACK and r <= E.RANK.KING then
            if not jk._photo_triggered then jk._photo_triggered = true; return { x_mult = 2 } end
        end
    end
    if ctx.joker_main then jk._photo_triggered = false end
end)
Sim._reg_joker("j_dna", "DNA", 3, 8, function(ctx, st, jk)
    -- Copy first card if only 1 played on first hand (complex)
end)
Sim._reg_joker("j_splash", "Splash", 1, 3, function(ctx, st, jk)
    -- All played cards count toward scoring (handled in evaluator)
end)
-- j_sixth_sense registered in 05_consumables.lua (needs CONS_POOL)
Sim._reg_joker("j_seance", "Seance", 2, 6, function(ctx, st, jk)
    -- Create Spectral if hand is Straight Flush (complex)
end)
Sim._reg_joker("j_riff_raff", "Riff-raff", 1, 6, function(ctx, st, jk)
    -- Create 2 common jokers on blind set (complex)
end)
Sim._reg_joker("j_diet_cola", "Diet Cola", 2, 6, function(ctx, st, jk)
    -- Create Double Tag when sold (complex)
end)
Sim._reg_joker("j_gift", "Gift Card", 2, 6, function(ctx, st, jk)
    -- +1 sell value to all jokers/consumables each round (complex)
end)
Sim._reg_joker("j_turtle_bean", "Turtle Bean", 2, 6, function(ctx, st, jk)
    -- +5 hand size, -1 per round (complex)
end)
Sim._reg_joker("j_erosion", "Erosion", 2, 6, function(ctx, st, jk)
    if ctx.joker_main then
        local diff = 52 - (#st.deck + #st.hand + #st.discard)
        if diff > 0 then return { mult_mod = 4 * diff } end
    end
end)
Sim._reg_joker("j_hallucination", "Hallucination", 1, 4, function(ctx, st, jk)
    -- 1 in 2 chance to create Tarot when opening booster (complex)
end)

-- === Rare jokers ===

Sim._reg_joker("j_wee", "Wee Joker", 3, 8, function(ctx, st, jk)
    if ctx.after_play then jk._wee_chips = (jk._wee_chips or 0) + 8 end
    if ctx.joker_main then return { chip_mod = jk._wee_chips or 0 } end
end)
Sim._reg_joker("j_merry_andy", "Merry Andy", 2, 7, function(ctx, st, jk)
    -- +3 discards, -1 hand size (passive)
end)
Sim._reg_joker("j_oops", "Oops! All 6s", 2, 4, function(ctx, st, jk)
    -- Double all listed probabilities (complex)
end)
Sim._reg_joker("j_idol", "The Idol", 2, 6, function(ctx, st, jk)
    if ctx.individual and ctx.other_card and ctx.cardarea == "play" then
        if ctx.other_card.rank == jk._idol_rank and ctx.other_card.suit == jk._idol_suit then
            return { x_mult = 2 }
        end
    end
    if ctx.joker_main then
        jk._idol_rank = Sim.RNG.int(st.rng, 2, 14)
        jk._idol_suit = Sim.RNG.int(st.rng, 1, 4)
    end
end)
Sim._reg_joker("j_seeing_double", "Seeing Double", 2, 6, function(ctx, st, jk)
    if ctx.joker_main and ctx.all_hands then
        local has_club = false
        for _, c in ipairs(st.hand) do if _is_suit(c, E.SUIT.CLUBS) then has_club = true end end
        local has_other = false
        for _, c in ipairs(st.hand) do if not _is_suit(c, E.SUIT.CLUBS) and c.enhancement ~= E.ENHANCEMENT.STONE then has_other = true end end
        if has_club and has_other then return { x_mult = 2 } end
    end
end)
Sim._reg_joker("j_matador", "Matador", 2, 7, function(ctx, st, jk)
    if ctx.after_play and st.boss_triggered then return { dollars = 8 } end
end)
Sim._reg_joker("j_hit_the_road", "Hit the Road", 3, 8, function(ctx, st, jk)
    if ctx.on_discard and ctx.other_card and ctx.other_card.rank == E.RANK.JACK then
        jk._htr_x = (jk._htr_x or 1) + 0.5
    end
    if ctx.joker_main then return { Xmult_mod = jk._htr_x or 1 } end
end)
Sim._reg_joker("j_stuntman", "Stuntman", 3, 7, function(ctx, st, jk)
    if ctx.joker_main then return { chip_mod = 250 } end
    -- -2 hand size (passive)
end)
Sim._reg_joker("j_invisible", "Invisible Joker", 3, 8, function(ctx, st, jk)
    -- Duplicate random joker after 2 rounds (complex)
end)
Sim._reg_joker("j_brainstorm", "Brainstorm", 3, 10, function(ctx, st, jk)
    -- Copy leftmost joker (similar to Blueprint)
    if ctx.blueprint then return end
    local target = st.jokers[1]
    if not target or target == jk then return end
    local def = Sim._JOKER_BY_ID[target.id]
    if not def or not def.apply then return end
    local cc = {}
    for k,v in pairs(ctx) do cc[k] = v end
    cc.blueprint = true
    return def.apply(cc, st, target)
end)
Sim._reg_joker("j_satellite", "Satellite", 2, 6, function(ctx, st, jk)
    -- $1 per unique planet used this run (complex)
end)
Sim._reg_joker("j_drivers_license", "Driver's License", 3, 7, function(ctx, st, jk)
    if ctx.joker_main then
        local enhanced = 0
        for _, c in ipairs(st.deck) do if c.enhancement > 0 then enhanced = enhanced + 1 end end
        for _, c in ipairs(st.hand) do if c.enhancement > 0 then enhanced = enhanced + 1 end end
        if enhanced >= 16 then return { Xmult_mod = 3 } end
    end
end)
Sim._reg_joker("j_cartomancer", "Cartomancer", 2, 6, function(ctx, st, jk)
    -- Create Tarot on blind set (complex)
end)
Sim._reg_joker("j_astronomer", "Astronomer", 2, 8, function(ctx, st, jk)
    -- Planet cards free in shop (passive)
end)
Sim._reg_joker("j_bootstraps", "Bootstraps", 2, 7, function(ctx, st, jk)
    if ctx.joker_main then return { mult_mod = 2 * math.floor(math.max(st.dollars, 0) / 5) } end
end)
Sim._reg_joker("j_ring_master", "Showman", 2, 5, function(ctx, st, jk)
    -- Cards can appear multiple times in shop (passive)
end)
Sim._reg_joker("j_flower_pot", "Flower Pot", 2, 6, function(ctx, st, jk)
    if ctx.joker_main then
        local suits_found = {}
        for _, c in ipairs(st.hand) do
            if c.enhancement ~= E.ENHANCEMENT.STONE then
                local s = c.enhancement == E.ENHANCEMENT.WILD and 1 or c.suit
                suits_found[s] = true
            end
        end
        if suits_found[1] and suits_found[2] and suits_found[3] and suits_found[4] then
            return { x_mult = 3 }
        end
    end
end)
Sim._reg_joker("j_smeared", "Smeared Joker", 2, 7, function(ctx, st, jk)
    -- Hearts=Diamonds, Spades=Clubs (handled in _is_suit)
end)
Sim._reg_joker("j_throwback", "Throwback", 2, 6, function(ctx, st, jk)
    -- +0.25 Xmult per blind skipped (complex)
end)
Sim._reg_joker("j_rough_gem", "Rough Gem", 2, 7, function(ctx, st, jk)
    if ctx.individual and ctx.other_card and ctx.cardarea == "play" then
        if _is_suit(ctx.other_card, E.SUIT.DIAMONDS) then return { dollars = 1 } end
    end
end)
Sim._reg_joker("j_bloodstone", "Bloodstone", 2, 7, function(ctx, st, jk)
    if ctx.individual and ctx.other_card and ctx.cardarea == "play" then
        if _is_suit(ctx.other_card, E.SUIT.HEARTS) then
            if Sim.RNG.next(st.rng) < 0.5 then return { x_mult = 1.5 } end
        end
    end
end)
Sim._reg_joker("j_arrowhead", "Arrowhead", 2, 7, function(ctx, st, jk)
    if ctx.individual and ctx.other_card and ctx.cardarea == "play" then
        if _is_suit(ctx.other_card, E.SUIT.SPADES) then return { chips = 50 } end
    end
end)
Sim._reg_joker("j_onyx_agate", "Onyx Agate", 2, 7, function(ctx, st, jk)
    if ctx.individual and ctx.other_card and ctx.cardarea == "play" then
        if _is_suit(ctx.other_card, E.SUIT.CLUBS) then return { mult = 7 } end
    end
end)
Sim._reg_joker("j_glass", "Glass Joker", 2, 6, function(ctx, st, jk)
    -- +0.75 Xmult per Glass card destroyed (complex)
end)
Sim._reg_joker("j_mr_bones", "Mr. Bones", 2, 5, function(ctx, st, jk)
    -- Prevent death if chips >= 25% of blind (complex)
end)
Sim._reg_joker("j_superposition", "Superposition", 1, 4, function(ctx, st, jk)
    -- Create Tarot if straight contains Ace (complex)
end)
Sim._reg_joker("j_todo_list", "To Do List", 1, 4, function(ctx, st, jk)
    -- $4 if hand type matches random target (complex)
end)
Sim._reg_joker("j_certificate", "Certificate", 2, 6, function(ctx, st, jk)
    -- Create random sealed card on first hand drawn (complex)
end)
Sim._reg_joker("j_troubadour", "Troubadour", 2, 6, function(ctx, st, jk)
    -- +2 hand size, -1 hand per round (passive)
end)

-- === Legendary jokers (rarity 4) ===

Sim._reg_joker("j_caino", "Caino", 4, 20, function(ctx, st, jk)
    -- +1 Xmult per face card destroyed (complex)
end)
Sim._reg_joker("j_triboulet", "Triboulet", 4, 20, function(ctx, st, jk)
    if ctx.individual and ctx.other_card and ctx.cardarea == "play" then
        local r = ctx.other_card.rank
        if r == E.RANK.KING or r == E.RANK.QUEEN then return { x_mult = 2 } end
    end
end)
Sim._reg_joker("j_yorick", "Yorick", 4, 20, function(ctx, st, jk)
    if ctx.on_discard then
        jk._yorick_discards = (jk._yorick_discards or 0) + ctx.cards_discarded
        if jk._yorick_discards >= 23 then
            jk._yorick_discards = 0
            jk._yorick_x = (jk._yorick_x or 1) + 1
        end
    end
    if ctx.joker_main then return { Xmult_mod = jk._yorick_x or 1 } end
end)
Sim._reg_joker("j_chicot", "Chicot", 4, 20, function(ctx, st, jk)
    -- Disable boss blind effect (complex)
end)
Sim._reg_joker("j_perkeo", "Perkeo", 4, 20, function(ctx, st, jk)
    -- Create negative copy of random consumable at shop end (complex)
end)


Sim.CONSUMABLE_DEFS = {}
Sim._CONS_BY_ID = {}

function Sim._reg_cons(key, name, set, effect_fn)
    local def = { id = #Sim._CONS_BY_ID + 1, key = key, name = name,
                  set = set, effect = effect_fn }
    Sim.CONSUMABLE_DEFS[key] = def
    Sim._CONS_BY_ID[def.id] = def
    return def
end

Sim._reg_cons("c_pluto", "Pluto", "Planet", function(ctx, state)
    -- Level up High Card
    Sim.State.level_up(state, Sim.ENUMS.HAND_TYPE.HIGH_CARD, 1)
    return { level_up = Sim.ENUMS.HAND_TYPE.HIGH_CARD }
end)

Sim._reg_cons("c_mercury", "Mercury", "Planet", function(ctx, state)
    -- Level up Pair
    Sim.State.level_up(state, Sim.ENUMS.HAND_TYPE.PAIR, 1)
    return { level_up = Sim.ENUMS.HAND_TYPE.PAIR }
end)

Sim._reg_cons("c_empress", "The Empress", "Tarot", function(ctx, state)
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

Sim._reg_cons("c_fool", "The Fool", "Tarot", function(ctx, state)
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

-- === Planet cards (10 remaining) ===

Sim._reg_cons("c_venus", "Venus", "Planet", function(ctx, state)
    Sim.State.level_up(state, Sim.ENUMS.HAND_TYPE.THREE_OF_A_KIND, 1)
    return { level_up = Sim.ENUMS.HAND_TYPE.THREE_OF_A_KIND }
end)

Sim._reg_cons("c_earth", "Earth", "Planet", function(ctx, state)
    Sim.State.level_up(state, Sim.ENUMS.HAND_TYPE.FULL_HOUSE, 1)
    return { level_up = Sim.ENUMS.HAND_TYPE.FULL_HOUSE }
end)

Sim._reg_cons("c_mars", "Mars", "Planet", function(ctx, state)
    Sim.State.level_up(state, Sim.ENUMS.HAND_TYPE.FOUR_OF_A_KIND, 1)
    return { level_up = Sim.ENUMS.HAND_TYPE.FOUR_OF_A_KIND }
end)

Sim._reg_cons("c_jupiter", "Jupiter", "Planet", function(ctx, state)
    Sim.State.level_up(state, Sim.ENUMS.HAND_TYPE.FLUSH, 1)
    return { level_up = Sim.ENUMS.HAND_TYPE.FLUSH }
end)

Sim._reg_cons("c_saturn", "Saturn", "Planet", function(ctx, state)
    Sim.State.level_up(state, Sim.ENUMS.HAND_TYPE.STRAIGHT, 1)
    return { level_up = Sim.ENUMS.HAND_TYPE.STRAIGHT }
end)

Sim._reg_cons("c_neptune", "Neptune", "Planet", function(ctx, state)
    Sim.State.level_up(state, Sim.ENUMS.HAND_TYPE.STRAIGHT_FLUSH, 1)
    return { level_up = Sim.ENUMS.HAND_TYPE.STRAIGHT_FLUSH }
end)

Sim._reg_cons("c_uranus", "Uranus", "Planet", function(ctx, state)
    Sim.State.level_up(state, Sim.ENUMS.HAND_TYPE.TWO_PAIR, 1)
    return { level_up = Sim.ENUMS.HAND_TYPE.TWO_PAIR }
end)

Sim._reg_cons("c_planet_x", "Planet X", "Planet", function(ctx, state)
    Sim.State.level_up(state, Sim.ENUMS.HAND_TYPE.FIVE_OF_A_KIND, 1)
    return { level_up = Sim.ENUMS.HAND_TYPE.FIVE_OF_A_KIND }
end)

Sim._reg_cons("c_ceres", "Ceres", "Planet", function(ctx, state)
    Sim.State.level_up(state, Sim.ENUMS.HAND_TYPE.FLUSH_HOUSE, 1)
    return { level_up = Sim.ENUMS.HAND_TYPE.FLUSH_HOUSE }
end)

Sim._reg_cons("c_eris", "Eris", "Planet", function(ctx, state)
    Sim.State.level_up(state, Sim.ENUMS.HAND_TYPE.FLUSH_FIVE, 1)
    return { level_up = Sim.ENUMS.HAND_TYPE.FLUSH_FIVE }
end)

-- === Tarot cards (16 remaining) ===

Sim._reg_cons("c_magician", "The Magician", "Tarot", function(ctx, state)
    if not ctx.selected or #ctx.selected == 0 then return nil end
    local count = 0
    for _, idx in ipairs(ctx.selected) do
        local c = state.hand[idx]
        if c and count < 2 then
            c.enhancement = Sim.ENUMS.ENHANCEMENT.LUCKY
            count = count + 1
        end
    end
    return { enhanced = count }
end)

Sim._reg_cons("c_high_priestess", "The High Priestess", "Tarot", function(ctx, state)
    local created = 0
    for _ = 1, 2 do
        if #state.consumables < state.consumable_slots then
            local planet_ids = {}
            for _, def in pairs(Sim.CONSUMABLE_DEFS) do
                if def.set == "Planet" then planet_ids[#planet_ids+1] = def.id end
            end
            local pid = Sim.RNG.pick(state.rng, planet_ids)
            state._cons_n = (state._cons_n or 0) + 1
            state.consumables[#state.consumables + 1] = { id = pid, uid = state._cons_n }
            created = created + 1
        end
    end
    return { created = created }
end)

Sim._reg_cons("c_emperor", "The Emperor", "Tarot", function(ctx, state)
    local created = 0
    for _ = 1, 2 do
        if #state.consumables < state.consumable_slots then
            local tarot_ids = {}
            for _, def in pairs(Sim.CONSUMABLE_DEFS) do
                if def.set == "Tarot" and def.id ~= state.last_consumable then
                    tarot_ids[#tarot_ids+1] = def.id
                end
            end
            if #tarot_ids > 0 then
                local tid = Sim.RNG.pick(state.rng, tarot_ids)
                state._cons_n = (state._cons_n or 0) + 1
                state.consumables[#state.consumables + 1] = { id = tid, uid = state._cons_n }
                created = created + 1
            end
        end
    end
    return { created = created }
end)

Sim._reg_cons("c_hierophant", "The Hierophant", "Tarot", function(ctx, state)
    if not ctx.selected or #ctx.selected == 0 then return nil end
    local count = 0
    for _, idx in ipairs(ctx.selected) do
        local c = state.hand[idx]
        if c and count < 2 then
            c.enhancement = Sim.ENUMS.ENHANCEMENT.BONUS
            count = count + 1
        end
    end
    return { enhanced = count }
end)

Sim._reg_cons("c_lovers", "The Lovers", "Tarot", function(ctx, state)
    if not ctx.selected or #ctx.selected == 0 then return nil end
    local idx = ctx.selected[1]
    local c = state.hand[idx]
    if c then
        c.enhancement = Sim.ENUMS.ENHANCEMENT.WILD
        return { enhanced = 1 }
    end
    return nil
end)

Sim._reg_cons("c_chariot", "The Chariot", "Tarot", function(ctx, state)
    if not ctx.selected or #ctx.selected == 0 then return nil end
    local idx = ctx.selected[1]
    local c = state.hand[idx]
    if c then
        c.enhancement = Sim.ENUMS.ENHANCEMENT.STEEL
        return { enhanced = 1 }
    end
    return nil
end)

Sim._reg_cons("c_strength", "Strength", "Tarot", function(ctx, state)
    if not ctx.selected or #ctx.selected == 0 then return nil end
    local count = 0
    for _, idx in ipairs(ctx.selected) do
        local c = state.hand[idx]
        if c and c.rank < 14 and count < 2 then
            c.rank = c.rank + 1
            count = count + 1
        end
    end
    return { enhanced = count }
end)

Sim._reg_cons("c_hermit", "The Hermit", "Tarot", function(ctx, state)
    local bonus = math.min(state.dollars, 20)
    state.dollars = state.dollars + bonus
    return { money = bonus }
end)

Sim._reg_cons("c_wheel_of_fortune", "Wheel of Fortune", "Tarot", function(ctx, state)
    if not state.jokers or #state.jokers == 0 then return nil end
    if Sim.RNG.next(state.rng) >= 0.25 then return nil end
    local ji = Sim.RNG.int(state.rng, 1, #state.jokers)
    local jk = state.jokers[ji]
    if jk.edition == 0 then
        local editions = {
            Sim.ENUMS.EDITION.FOIL,
            Sim.ENUMS.EDITION.HOLO,
            Sim.ENUMS.EDITION.POLYCHROME,
        }
        jk.edition = Sim.RNG.pick(state.rng, editions)
        return { edition = jk.edition }
    end
    return nil
end)

Sim._reg_cons("c_justice", "Justice", "Tarot", function(ctx, state)
    if not ctx.selected or #ctx.selected == 0 then return nil end
    local idx = ctx.selected[1]
    local c = state.hand[idx]
    if c then
        c.enhancement = Sim.ENUMS.ENHANCEMENT.GLASS
        return { enhanced = 1 }
    end
    return nil
end)

Sim._reg_cons("c_hanged_man", "The Hanged Man", "Tarot", function(ctx, state)
    if not ctx.selected or #ctx.selected == 0 then return nil end
    local destroyed = 0
    local sorted = {}
    for _, v in ipairs(ctx.selected) do sorted[#sorted+1] = v end
    table.sort(sorted, function(a,b) return a > b end)
    for _, idx in ipairs(sorted) do
        if state.hand[idx] and destroyed < 2 then
            table.remove(state.hand, idx)
            destroyed = destroyed + 1
        end
    end
    state.deck_count = state.deck_count - destroyed
    return { destroyed = destroyed }
end)

Sim._reg_cons("c_death", "Death", "Tarot", function(ctx, state)
    if not ctx.selected or #ctx.selected < 2 then return nil end
    local src = state.hand[ctx.selected[1]]
    local tgt_idx = ctx.selected[2]
    if src and state.hand[tgt_idx] then
        -- Copy src card properties to tgt
        local tgt = state.hand[tgt_idx]
        tgt.rank = src.rank
        tgt.suit = src.suit
        tgt.enhancement = src.enhancement
        tgt.edition = src.edition
        tgt.seal = src.seal
        tgt.perma_bonus = src.perma_bonus
        return { copied = true }
    end
    return nil
end)

Sim._reg_cons("c_temperance", "Temperance", "Tarot", function(ctx, state)
    local total = 0
    if state.jokers then
        for _, jk in ipairs(state.jokers) do
            local def = Sim._JOKER_BY_ID[jk.id]
            if def then total = total + (def.cost or 3) end
        end
    end
    total = math.min(total, 50)
    state.dollars = state.dollars + total
    return { money = total }
end)

Sim._reg_cons("c_devil", "The Devil", "Tarot", function(ctx, state)
    if not ctx.selected or #ctx.selected == 0 then return nil end
    local idx = ctx.selected[1]
    local c = state.hand[idx]
    if c then
        c.enhancement = Sim.ENUMS.ENHANCEMENT.GOLD
        return { enhanced = 1 }
    end
    return nil
end)

Sim._reg_cons("c_tower", "The Tower", "Tarot", function(ctx, state)
    if not ctx.selected or #ctx.selected == 0 then return nil end
    local idx = ctx.selected[1]
    local c = state.hand[idx]
    if c then
        c.enhancement = Sim.ENUMS.ENHANCEMENT.STONE
        return { enhanced = 1 }
    end
    return nil
end)

Sim._reg_cons("c_star", "The Star", "Tarot", function(ctx, state)
    if not ctx.selected or #ctx.selected == 0 then return nil end
    local count = 0
    for _, idx in ipairs(ctx.selected) do
        local c = state.hand[idx]
        if c and count < 3 then
            c.suit = Sim.ENUMS.SUIT.DIAMONDS
            count = count + 1
        end
    end
    return { changed = count }
end)

Sim._reg_cons("c_moon", "The Moon", "Tarot", function(ctx, state)
    if not ctx.selected or #ctx.selected == 0 then return nil end
    local count = 0
    for _, idx in ipairs(ctx.selected) do
        local c = state.hand[idx]
        if c and count < 3 then
            c.suit = Sim.ENUMS.SUIT.CLUBS
            count = count + 1
        end
    end
    return { changed = count }
end)

Sim._reg_cons("c_sun", "The Sun", "Tarot", function(ctx, state)
    if not ctx.selected or #ctx.selected == 0 then return nil end
    local count = 0
    for _, idx in ipairs(ctx.selected) do
        local c = state.hand[idx]
        if c and count < 3 then
            c.suit = Sim.ENUMS.SUIT.HEARTS
            count = count + 1
        end
    end
    return { changed = count }
end)

Sim._reg_cons("c_world", "The World", "Tarot", function(ctx, state)
    if not ctx.selected or #ctx.selected == 0 then return nil end
    local count = 0
    for _, idx in ipairs(ctx.selected) do
        local c = state.hand[idx]
        if c and count < 3 then
            c.suit = Sim.ENUMS.SUIT.SPADES
            count = count + 1
        end
    end
    return { changed = count }
end)

-- === Spectral cards (16) ===

Sim._reg_cons("c_familiar", "Familiar", "Spectral", function(ctx, state)
    if not state.hand or #state.hand == 0 then return nil end
    -- Destroy 1 random card
    local di = Sim.RNG.int(state.rng, 1, #state.hand)
    table.remove(state.hand, di)
    state.deck_count = state.deck_count - 1
    -- Create 3 random face cards with random enhancement
    local faces = {11, 12, 13}
    local enhancements = {1, 2, 3, 4, 5, 7, 8}
    local created = 0
    for _ = 1, 3 do
        if #state.hand < state.hand_limit then
            local rank = Sim.RNG.pick(state.rng, faces)
            local suit = Sim.RNG.int(state.rng, 1, 4)
            local enh = Sim.RNG.pick(state.rng, enhancements)
            state.hand[#state.hand+1] = Sim.Card.new(rank, suit, enh)
            created = created + 1
        end
    end
    return { created = created }
end)

Sim._reg_cons("c_grim", "Grim", "Spectral", function(ctx, state)
    if not state.hand or #state.hand == 0 then return nil end
    -- Destroy 1 random card
    local di = Sim.RNG.int(state.rng, 1, #state.hand)
    table.remove(state.hand, di)
    state.deck_count = state.deck_count - 1
    -- Create 2 Aces with random enhancement
    local enhancements = {1, 2, 3, 4, 5, 7, 8}
    local created = 0
    for _ = 1, 2 do
        if #state.hand < state.hand_limit then
            local suit = Sim.RNG.int(state.rng, 1, 4)
            local enh = Sim.RNG.pick(state.rng, enhancements)
            state.hand[#state.hand+1] = Sim.Card.new(14, suit, enh)
            created = created + 1
        end
    end
    return { created = created }
end)

Sim._reg_cons("c_incantation", "Incantation", "Spectral", function(ctx, state)
    if not state.hand or #state.hand == 0 then return nil end
    -- Destroy 1 random card
    local di = Sim.RNG.int(state.rng, 1, #state.hand)
    table.remove(state.hand, di)
    state.deck_count = state.deck_count - 1
    -- Create 4 numbered cards (2-10) with random enhancement
    local enhancements = {1, 2, 3, 4, 5, 7, 8}
    local created = 0
    for _ = 1, 4 do
        if #state.hand < state.hand_limit then
            local rank = Sim.RNG.int(state.rng, 2, 10)
            local suit = Sim.RNG.int(state.rng, 1, 4)
            local enh = Sim.RNG.pick(state.rng, enhancements)
            state.hand[#state.hand+1] = Sim.Card.new(rank, suit, enh)
            created = created + 1
        end
    end
    return { created = created }
end)

Sim._reg_cons("c_talisman", "Talisman", "Spectral", function(ctx, state)
    if not ctx.selected or #ctx.selected == 0 then return nil end
    local c = state.hand[ctx.selected[1]]
    if c then
        c.seal = Sim.ENUMS.SEAL.GOLD
        return { sealed = true }
    end
    return nil
end)

Sim._reg_cons("c_aura", "Aura", "Spectral", function(ctx, state)
    if not ctx.selected or #ctx.selected == 0 then return nil end
    local c = state.hand[ctx.selected[1]]
    if c and c.edition == 0 then
        local editions = {
            Sim.ENUMS.EDITION.FOIL,
            Sim.ENUMS.EDITION.HOLO,
            Sim.ENUMS.EDITION.POLYCHROME,
        }
        c.edition = Sim.RNG.pick(state.rng, editions)
        return { edition = c.edition }
    end
    return nil
end)

Sim._reg_cons("c_wraith", "Wraith", "Spectral", function(ctx, state)
    -- Create 1 random Joker
    if #state.jokers >= state.joker_slots then return nil end
    local jid = Sim.RNG.pick(state.rng, Sim.JOKER_POOL)
    state._joker_n = (state._joker_n or 0) + 1
    state.jokers[#state.jokers+1] = {
        id = jid, edition = 0, eternal = false, uid = state._joker_n,
    }
    -- Set money to 0
    state.dollars = 0
    return { created = true }
end)

Sim._reg_cons("c_sigil", "Sigil", "Spectral", function(ctx, state)
    local suit = Sim.RNG.int(state.rng, 1, 4)
    for _, c in ipairs(state.hand) do
        if c.enhancement ~= 6 then -- Skip Stone cards
            c.suit = suit
        end
    end
    return { suit = suit }
end)

Sim._reg_cons("c_ouija", "Ouija", "Spectral", function(ctx, state)
    local rank = Sim.RNG.int(state.rng, 2, 14)
    for _, c in ipairs(state.hand) do
        if c.enhancement ~= 6 then -- Skip Stone cards
            c.rank = rank
        end
    end
    -- -1 hand size
    state.hand_limit = math.max(1, state.hand_limit - 1)
    return { rank = rank }
end)

Sim._reg_cons("c_ectoplasm", "Ectoplasm", "Spectral", function(ctx, state)
    -- Add Negative edition to a random Joker
    local eligible = {}
    for _, jk in ipairs(state.jokers) do
        if jk.edition == 0 then eligible[#eligible+1] = jk end
    end
    if #eligible == 0 then return nil end
    local jk = Sim.RNG.pick(state.rng, eligible)
    jk.edition = Sim.ENUMS.EDITION.NEGATIVE
    -- -1 hand size
    state.hand_limit = math.max(1, state.hand_limit - 1)
    return { edition = Sim.ENUMS.EDITION.NEGATIVE }
end)

Sim._reg_cons("c_immolate", "Immolate", "Spectral", function(ctx, state)
    if not state.hand or #state.hand == 0 then return nil end
    -- Destroy 5 random cards
    local destroyed = 0
    local indices = {}
    for i = 1, #state.hand do indices[i] = i end
    Sim.RNG.shuffle(state.rng, indices)
    local n = math.min(5, #state.hand)
    table.sort(indices, function(a,b) return a > b end)
    for i = 1, n do
        table.remove(state.hand, indices[i])
        destroyed = destroyed + 1
    end
    state.deck_count = state.deck_count - destroyed
    -- Gain $20
    state.dollars = state.dollars + 20
    return { destroyed = destroyed, money = 20 }
end)

Sim._reg_cons("c_ankh", "Ankh", "Spectral", function(ctx, state)
    if not state.jokers or #state.jokers == 0 then return nil end
    -- Pick a random joker to copy
    local src = Sim.RNG.pick(state.rng, state.jokers)
    -- Destroy all other jokers
    state.jokers = { src }
    -- Create a copy
    if #state.jokers < state.joker_slots then
        state._joker_n = (state._joker_n or 0) + 1
        state.jokers[#state.jokers+1] = {
            id = src.id, edition = src.edition, eternal = src.eternal, uid = state._joker_n,
        }
    end
    return { copied = true }
end)

Sim._reg_cons("c_deja_vu", "Deja Vu", "Spectral", function(ctx, state)
    if not ctx.selected or #ctx.selected == 0 then return nil end
    local c = state.hand[ctx.selected[1]]
    if c then
        c.seal = Sim.ENUMS.SEAL.RED
        return { sealed = true }
    end
    return nil
end)

Sim._reg_cons("c_hex", "Hex", "Spectral", function(ctx, state)
    -- Add Polychrome to a random Joker
    local eligible = {}
    for _, jk in ipairs(state.jokers) do
        if jk.edition == 0 then eligible[#eligible+1] = jk end
    end
    if #eligible == 0 then return nil end
    local jk = Sim.RNG.pick(state.rng, eligible)
    jk.edition = Sim.ENUMS.EDITION.POLYCHROME
    -- Destroy all other jokers
    state.jokers = { jk }
    return { edition = Sim.ENUMS.EDITION.POLYCHROME }
end)

Sim._reg_cons("c_trance", "Trance", "Spectral", function(ctx, state)
    if not ctx.selected or #ctx.selected == 0 then return nil end
    local c = state.hand[ctx.selected[1]]
    if c then
        c.seal = Sim.ENUMS.SEAL.BLUE
        return { sealed = true }
    end
    return nil
end)

Sim._reg_cons("c_medium", "Medium", "Spectral", function(ctx, state)
    if not ctx.selected or #ctx.selected == 0 then return nil end
    local c = state.hand[ctx.selected[1]]
    if c then
        c.seal = Sim.ENUMS.SEAL.PURPLE
        return { sealed = true }
    end
    return nil
end)

Sim._reg_cons("c_cryptid", "Cryptid", "Spectral", function(ctx, state)
    if not ctx.selected or #ctx.selected == 0 then return nil end
    local src = state.hand[ctx.selected[1]]
    if not src then return nil end
    local created = 0
    for _ = 1, 2 do
        if #state.hand < state.hand_limit then
            state.hand[#state.hand+1] = Sim.Card.new(
                src.rank, src.suit, src.enhancement, src.edition, src.seal, src.perma_bonus
            )
            state.deck_count = state.deck_count + 1
            created = created + 1
        end
    end
    return { created = created }
end)

Sim.CONS_POOL = {}
for _, def in pairs(Sim.CONSUMABLE_DEFS) do
    Sim.CONS_POOL[#Sim.CONS_POOL + 1] = def.id
end

Sim._reg_joker("j_sixth_sense", "Sixth Sense", 2, 6, function(ctx, st, jk)
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

Sim._reg_joker("j_hiker", "Hiker", 2, 5, function(ctx, st, jk)
    if ctx.individual and ctx.other_card then
        ctx.other_card.perma_bonus = (ctx.other_card.perma_bonus or 0) + 5
    end
end)

Sim.JOKER_POOL = {}
for _, def in pairs(Sim.JOKER_DEFS) do
    Sim.JOKER_POOL[#Sim.JOKER_POOL + 1] = def.id
end

--
-- Provides Sim.create_card() for creating cards with proper pools, rarity rolls,
-- and pool culling (removes owned cards, respects flags).
--
-- Depends on: 04_jokers.lua (Sim.JOKER_DEFS), 05_consumables.lua (Sim.CONSUMABLE_DEFS)

Sim.CardFactory = {}

--- Rarity pools (built from joker definitions)
Sim.JOKER_RARITY_POOLS = { [1] = {}, [2] = {}, [3] = {}, [4] = {} }
for _, def in pairs(Sim.JOKER_DEFS) do
    local r = def.rarity or 1
    Sim.JOKER_RARITY_POOLS[r] = Sim.JOKER_RARITY_POOLS[r] or {}
    Sim.JOKER_RARITY_POOLS[r][#Sim.JOKER_RARITY_POOLS[r] + 1] = def.id
end

--- Consumable type pools
Sim.TAROT_POOL = {}
Sim.PLANET_POOL = {}
Sim.SPECTRAL_POOL = {}
for _, def in pairs(Sim.CONSUMABLE_DEFS) do
    local k = def.key or ""
    if k:find("pluto") or k:find("mercury") or k:find("venus") or k:find("earth") or
       k:find("mars") or k:find("jupiter") or k:find("saturn") or k:find("neptune") or
       k:find("uranus") or k:find("planet_x") or k:find("ceres") or k:find("eris") then
        Sim.PLANET_POOL[#Sim.PLANET_POOL + 1] = def.id
    elseif k:find("familiar") or k:find("grim") or k:find("incantation") or
           k:find("talisman") or k:find("aura") or k:find("wraith") or
           k:find("sigil") or k:find("ouija") or k:find("ectoplasm") or
           k:find("immolate") or k:find("ankh") or k:find("deja_vu") or
           k:find("hex") or k:find("trance") or k:find("medium") or k:find("cryptid") then
        Sim.SPECTRAL_POOL[#Sim.SPECTRAL_POOL + 1] = def.id
    else
        Sim.TAROT_POOL[#Sim.TAROT_POOL + 1] = def.id
    end
end

--- Playing card pool (52 standard cards)
Sim.PLAYING_CARD_POOL = {}
for suit = 1, 4 do
    for rank = 2, 14 do
        Sim.PLAYING_CARD_POOL[#Sim.PLAYING_CARD_POOL + 1] = { rank = rank, suit = suit }
    end
end

--- Roll rarity for a joker. Returns 1-4.
--- Uses pseudorandom seeded by ante (matches real game's rarity roll).
function Sim.CardFactory.roll_rarity(state, rng)
    local roll = Sim.RNG.next(rng)
    if roll > 0.95 then return 3     -- Rare: 5%
    elseif roll > 0.70 then return 2 -- Uncommon: 25%
    else return 1                    -- Common: 70%
    end
end

--- Get available joker IDs for a given rarity, excluding owned jokers.
--- If showman is true, does NOT exclude owned jokers.
function Sim.CardFactory.get_joker_pool(state, rarity, showman)
    local pool = Sim.JOKER_RARITY_POOLS[rarity]
    if not pool or #pool == 0 then return {} end
    if showman then return pool end

    -- Build set of owned joker IDs
    local owned = {}
    for _, jk in ipairs(state.jokers) do
        owned[jk.id] = true
    end

    -- Filter out owned
    local available = {}
    for _, jid in ipairs(pool) do
        if not owned[jid] then
            local def = Sim._JOKER_BY_ID[jid]
            -- Skip locked/undiscovered
            if def and def.key ~= "j_locked" and def.key ~= "j_undiscovered" then
                available[#available + 1] = jid
            end
        end
    end
    return available
end

--- Get available consumable IDs for a given type.
--- type: "tarot", "planet", "spectral"
function Sim.CardFactory.get_consumable_pool(state, ctype, showman)
    local pool
    if ctype == "tarot" then pool = Sim.TAROT_POOL
    elseif ctype == "planet" then pool = Sim.PLANET_POOL
    elseif ctype == "spectral" then pool = Sim.SPECTRAL_POOL
    else return {}
    end
    if showman then return pool end

    -- Filter out owned consumables
    local owned = {}
    for _, cs in ipairs(state.consumables) do
        owned[cs.id] = true
    end

    local available = {}
    for _, cid in ipairs(pool) do
        if not owned[cid] then
            available[#available + 1] = cid
        end
    end
    return available
end

--- Create a card of the given type.
---
--- card_type: "Joker", "Tarot", "Planet", "Spectral", "Playing Card"
--- state: game state
--- rng: RNG instance
--- rarity: (optional) for Joker type, force rarity 1-4. nil = roll.
--- force_key: (optional) force a specific key instead of random
--- showman: (optional) if true, don't exclude owned cards from pool
---
--- Returns: card table or nil if pool is empty
function Sim.CardFactory.create(card_type, state, rng, rarity, force_key, showman)
    if card_type == "Joker" then
        -- Roll rarity if not specified
        local r = rarity or Sim.CardFactory.roll_rarity(state, rng)
        if r == 4 then r = 4 end  -- Legendary only via Soul

        -- Check for Soul card (0.3% when creating Tarot/Spectral/Planet)
        -- Legendary jokers only come from Soul card, not normal creation
        if r == 4 then
            local leg_pool = Sim.JOKER_RARITY_POOLS[4]
            if not leg_pool or #leg_pool == 0 then return nil end
            local jid = Sim.RNG.pick(rng, leg_pool)
            return { id = jid, edition = 0, eternal = false, perishable = false,
                     rental = false, uid = (state._uid_n or 0) + 1, _new = true }
        end

        -- Get pool for this rarity
        local pool = Sim.CardFactory.get_joker_pool(state, r, showman)
        if #pool == 0 then
            -- Pool exhausted, try fallback to any rarity
            for fallback_r = 1, 3 do
                pool = Sim.CardFactory.get_joker_pool(state, fallback_r, showman)
                if #pool > 0 then break end
            end
        end
        if #pool == 0 then return nil end

        local jid
        if force_key then
            local def = Sim.JOKER_DEFS[force_key]
            jid = def and def.id or Sim.RNG.pick(rng, pool)
        else
            jid = Sim.RNG.pick(rng, pool)
        end

        -- Roll edition (from real game common_events.lua)
        local edition = 0
        local edition_roll = Sim.RNG.next(rng)
        local edition_rate = state._edition_rate or 1.0
        if edition_roll < 0.003 * edition_rate then
            edition = 4  -- Negative
        elseif edition_roll < 0.006 * edition_rate + 0.003 * edition_rate then
            edition = 3  -- Polychrome
        elseif edition_roll < 0.02 * edition_rate + 0.009 * edition_rate then
            edition = 2  -- Holographic
        elseif edition_roll < 0.04 * edition_rate + 0.029 * edition_rate then
            edition = 1  -- Foil
        end

        state._uid_n = (state._uid_n or 0) + 1
        return { id = jid, edition = edition, eternal = false, perishable = false,
                 rental = false, uid = state._uid_n, _new = true }

    elseif card_type == "Tarot" or card_type == "Planet" or card_type == "Spectral" then
        -- Check for Soul / Black Hole chance (0.3%)
        if card_type ~= "Planet" then
            -- 0.3% chance for The Soul when creating Tarot or Spectral
            local soul_roll = Sim.RNG.next(rng)
            if soul_roll < 0.003 then
                -- Create The Soul consumable (if exists)
                local soul_def = Sim.CONSUMABLE_DEFS["c_soul"]
                if soul_def then
                    state._uid_n = (state._uid_n or 0) + 1
                    return { id = soul_def.id, uid = state._uid_n, _new = true }
                end
            end
        end
        if card_type ~= "Tarot" then
            -- 0.3% chance for Black Hole when creating Planet or Spectral
            local bh_roll = Sim.RNG.next(rng)
            if bh_roll < 0.003 then
                local bh_def = Sim.CONSUMABLE_DEFS["c_black_hole"]
                if bh_def then
                    state._uid_n = (state._uid_n or 0) + 1
                    return { id = bh_def.id, uid = state._uid_n, _new = true }
                end
            end
        end

        local ctype = card_type:lower()
        local pool = Sim.CardFactory.get_consumable_pool(state, ctype, showman)
        if #pool == 0 then return nil end

        local cid
        if force_key then
            local def = Sim.CONSUMABLE_DEFS[force_key]
            cid = def and def.id or Sim.RNG.pick(rng, pool)
        else
            cid = Sim.RNG.pick(rng, pool)
        end

        state._uid_n = (state._uid_n or 0) + 1
        return { id = cid, uid = state._uid_n, _new = true }

    elseif card_type == "Playing Card" then
        -- Random playing card
        local roll = Sim.RNG.pick(rng, Sim.PLAYING_CARD_POOL)
        local rank = roll.rank
        local suit = roll.suit
        state._uid_n = (state._uid_n or 0) + 1
        return Sim.Card.new(rank, suit, 0, 0, 0, state._uid_n)
    end

    return nil
end

--- Check if the player has a specific joker by key.
function Sim.CardFactory.has_joker(state, key)
    local def = Sim.JOKER_DEFS[key]
    if not def then return false end
    for _, jk in ipairs(state.jokers) do
        if jk.id == def.id then return true end
    end
    return false
end

--- Check if the player has a specific voucher.
function Sim.CardFactory.has_voucher(state, key)
    return state.vouchers and state.vouchers[key] == true
end

--- Count cards in deck with a given enhancement.
function Sim.CardFactory.count_enhancement(state, enhancement)
    local count = 0
    for _, c in ipairs(state.deck) do
        if c.enhancement == enhancement then count = count + 1 end
    end
    return count
end

--- Count cards in deck with a given suit.
function Sim.CardFactory.count_suit(state, suit)
    local count = 0
    for _, c in ipairs(state.deck) do
        if c.suit == suit then count = count + 1 end
    end
    return count
end

--
-- Tags are gained when blinds are skipped. Each tag has a trigger type
-- that determines when it activates. All 24 tags implemented with
-- exact configs from game.lua P_TAGS.

Sim.Tag = {}
Sim.Tag.DEFS = {}

--- Register a tag definition.
function Sim.Tag.reg(key, name, trigger_type, config, min_ante)
    Sim.Tag.DEFS[key] = {
        key = key, name = name, type = trigger_type,
        config = config or {}, min_ante = min_ante,
    }
end

-- === Tag definitions (from game.lua P_TAGS) ===

Sim.Tag.reg("tag_uncommon",   "Uncommon Tag",      "store_joker_create", {rarity = 2}, nil)
Sim.Tag.reg("tag_rare",       "Rare Tag",           "store_joker_create", {rarity = 3}, nil)
Sim.Tag.reg("tag_negative",   "Negative Tag",       "store_joker_modify", {edition = 4}, 2)
Sim.Tag.reg("tag_foil",       "Foil Tag",           "store_joker_modify", {edition = 1}, nil)
Sim.Tag.reg("tag_holo",       "Holographic Tag",    "store_joker_modify", {edition = 2}, nil)
Sim.Tag.reg("tag_polychrome", "Polychrome Tag",     "store_joker_modify", {edition = 3}, nil)
Sim.Tag.reg("tag_investment", "Investment Tag",     "eval",               {dollars = 25}, nil)
Sim.Tag.reg("tag_voucher",    "Voucher Tag",        "voucher_add",        {}, nil)
Sim.Tag.reg("tag_boss",       "Boss Tag",           "new_blind_choice",   {}, nil)
Sim.Tag.reg("tag_standard",   "Standard Tag",       "new_blind_choice",   {}, 2)
Sim.Tag.reg("tag_charm",      "Charm Tag",          "new_blind_choice",   {}, nil)
Sim.Tag.reg("tag_meteor",     "Meteor Tag",         "new_blind_choice",   {}, 2)
Sim.Tag.reg("tag_buffoon",    "Buffoon Tag",        "new_blind_choice",   {}, 2)
Sim.Tag.reg("tag_handy",      "Handy Tag",          "immediate",          {dollars_per_hand = 1}, 2)
Sim.Tag.reg("tag_garbage",    "Garbage Tag",        "immediate",          {dollars_per_discard = 1}, 2)
Sim.Tag.reg("tag_ethereal",   "Ethereal Tag",       "new_blind_choice",   {}, 2)
Sim.Tag.reg("tag_coupon",     "Coupon Tag",         "shop_final_pass",    {}, nil)
Sim.Tag.reg("tag_double",     "Double Tag",         "tag_add",            {}, nil)
Sim.Tag.reg("tag_juggle",     "Juggle Tag",         "round_start_bonus",  {h_size = 3}, nil)
Sim.Tag.reg("tag_d_six",      "D6 Tag",             "shop_start",         {}, nil)
Sim.Tag.reg("tag_top_up",     "Top-up Tag",         "immediate",          {spawn_jokers = 2}, 2)
Sim.Tag.reg("tag_skip",       "Skip Tag",           "immediate",          {skip_bonus = 5}, nil)
Sim.Tag.reg("tag_orbital",    "Orbital Tag",        "immediate",          {levels = 3}, 2)
Sim.Tag.reg("tag_economy",    "Economy Tag",        "immediate",          {max = 40}, nil)

--- Add a tag to the state. Returns true if added.
function Sim.Tag.add(state, tag_key)
    if not Sim.Tag.DEFS[tag_key] then return false end
    state.tags = state.tags or {}
    local tag = { key = tag_key, triggered = false, config = Sim.Tag.DEFS[tag_key].config }
    state.tags[#state.tags + 1] = tag

    -- Fire immediate tags right away
    local def = Sim.Tag.DEFS[tag_key]
    if def.type == "immediate" then
        Sim.Tag.apply_immediate(state, tag, def)
    end

    -- Double Tag: when any tag is gained, copy it
    for _, existing in ipairs(state.tags) do
        if existing ~= tag and existing.key == "tag_double" and not existing.triggered then
            if tag_key ~= "tag_double" then
                existing.triggered = true
                Sim.Tag.add(state, tag_key)
            end
        end
    end

    return true
end

--- Apply an immediate tag effect.
function Sim.Tag.apply_immediate(state, tag, def)
    if tag.triggered then return end
    local cfg = def.config or {}

    if def.key == "tag_handy" then
        local earned = (state.total_hands_played or 0) * (cfg.dollars_per_hand or 1)
        state.dollars = state.dollars + earned
    elseif def.key == "tag_garbage" then
        local earned = (state.total_unused_discards or 0) * (cfg.dollars_per_discard or 1)
        state.dollars = state.dollars + earned
    elseif def.key == "tag_skip" then
        local earned = (state.skips or 0) * (cfg.skip_bonus or 5)
        state.dollars = state.dollars + earned
    elseif def.key == "tag_economy" then
        local max = cfg.max or 40
        local earned = math.min(max, math.max(0, state.dollars))
        state.dollars = state.dollars + earned
    elseif def.key == "tag_top_up" then
        local count = cfg.spawn_jokers or 2
        for i = 1, count do
            if #state.jokers < state.joker_slots then
                local jk = Sim.CardFactory.create("Joker", state, state.rng, 1)  -- Common only
                if jk then
                    local jdef = Sim._JOKER_BY_ID[jk.id]
                    if jdef then Sim.State.add_joker(state, jdef) end
                end
            end
        end
    elseif def.key == "tag_orbital" then
        -- Level up most played hand by 3
        local best_hand = nil
        local best_count = 0
        for ht, count in pairs(state.hand_type_counts or {}) do
            if type(ht) == "number" and count > best_count then
                best_count = count
                best_hand = ht
            end
        end
        if best_hand then
            state.hand_levels[best_hand] = (state.hand_levels[best_hand] or 1) + (cfg.levels or 3)
            Sim.State.level_up(state, best_hand)
        end
    end

    tag.triggered = true
end

--- Apply tags for a context (eval, new_blind_choice, store_joker_create, etc.)
--- Returns effects that should be applied.
function Sim.Tag.apply(state, context_type, context)
    if not state.tags then return {} end
    local effects = {}

    for _, tag in ipairs(state.tags) do
        if not tag.triggered then
            local def = Sim.Tag.DEFS[tag.key]
            if def and def.type == context_type then
                if context_type == "eval" then
                    -- Investment Tag: +$25 after defeating boss
                    if tag.key == "tag_investment" and context and context.was_boss then
                        state.dollars = state.dollars + (tag.config.dollars or 25)
                        tag.triggered = true
                    end
                elseif context_type == "new_blind_choice" then
                    -- Pack tags: open a free pack
                    if tag.key == "tag_charm" then
                        effects[#effects + 1] = { type = "free_pack", pack = "arcana_mega" }
                        tag.triggered = true
                    elseif tag.key == "tag_meteor" then
                        effects[#effects + 1] = { type = "free_pack", pack = "celestial_mega" }
                        tag.triggered = true
                    elseif tag.key == "tag_standard" then
                        effects[#effects + 1] = { type = "free_pack", pack = "standard_mega" }
                        tag.triggered = true
                    elseif tag.key == "tag_buffoon" then
                        effects[#effects + 1] = { type = "free_pack", pack = "buffoon_mega" }
                        tag.triggered = true
                    elseif tag.key == "tag_ethereal" then
                        effects[#effects + 1] = { type = "free_pack", pack = "spectral_normal" }
                        tag.triggered = true
                    elseif tag.key == "tag_boss" then
                        effects[#effects + 1] = { type = "reroll_boss" }
                        tag.triggered = true
                    end
                elseif context_type == "store_joker_create" then
                    -- Uncommon/Rare Tag: create free joker
                    if tag.key == "tag_uncommon" then
                        local jk = Sim.CardFactory.create("Joker", state, state.rng, 2)
                        if jk then
                            effects[#effects + 1] = { type = "free_joker", joker = jk }
                        end
                        tag.triggered = true
                    elseif tag.key == "tag_rare" then
                        local pool = Sim.CardFactory.get_joker_pool(state, 3)
                        if #pool > 0 then
                            local jk = Sim.CardFactory.create("Joker", state, state.rng, 3)
                            if jk then
                                effects[#effects + 1] = { type = "free_joker", joker = jk }
                            end
                        end
                        tag.triggered = true
                    end
                elseif context_type == "store_joker_modify" then
                    -- Edition tags: apply edition to first uneditioned joker
                    if tag.key == "tag_foil" or tag.key == "tag_holo" or
                       tag.key == "tag_polychrome" or tag.key == "tag_negative" then
                        if context and context.joker then
                            local jk = context.joker
                            if jk.edition == 0 then
                                jk.edition = tag.config.edition or 0
                                effects[#effects + 1] = { type = "edition_applied", edition = jk.edition }
                            end
                        end
                        tag.triggered = true
                    end
                elseif context_type == "shop_start" then
                    -- D6 Tag: first reroll free
                    if tag.key == "tag_d_six" then
                        state._reroll_cost = 0
                        tag.triggered = true
                    end
                elseif context_type == "shop_final_pass" then
                    -- Coupon Tag: all items free
                    if tag.key == "tag_coupon" then
                        effects[#effects + 1] = { type = "all_free" }
                        tag.triggered = true
                    end
                elseif context_type == "round_start_bonus" then
                    -- Juggle Tag: +3 hand size this round
                    if tag.key == "tag_juggle" then
                        local h = tag.config.h_size or 3
                        state.hand_limit = (state.hand_limit or 8) + h
                        state._juggle_bonus = (state._juggle_bonus or 0) + h
                        tag.triggered = true
                    end
                elseif context_type == "voucher_add" then
                    -- Voucher Tag: extra voucher in shop
                    if tag.key == "tag_voucher" then
                        effects[#effects + 1] = { type = "extra_voucher" }
                        tag.triggered = true
                    end
                end
            end
        end
    end

    return effects
end

--- Pick a random tag that's available at the given ante.
function Sim.Tag.pick(state)
    local available = {}
    local ante = state.ante or 1
    local owned = {}
    for _, tag in ipairs(state.tags or {}) do
        owned[tag.key] = true
    end
    for key, def in pairs(Sim.Tag.DEFS) do
        if not owned[key] then
            if not def.min_ante or ante >= def.min_ante then
                available[#available + 1] = key
            end
        end
    end
    if #available == 0 then return nil end
    return available[Sim.RNG.int(state.rng, 1, #available)]
end

--
-- Vouchers are permanent upgrades bought in the shop. Each has a tier 1
-- base version and a tier 2 upgrade. Tier 2 requires having redeemed tier 1.
-- All vouchers cost $10 in the real game.

Sim.Voucher = {}
Sim.Voucher.DEFS = {}

--- Register a voucher definition.
function Sim.Voucher.reg(key, name, tier, requires, apply_fn)
    Sim.Voucher.DEFS[key] = {
        key = key, name = name, tier = tier,
        requires = requires, apply = apply_fn, cost = 10,
    }
end

--- Apply voucher effects to state.
--- Called when voucher is redeemed (bought from shop).

-- === Tier 1 (Base) Vouchers ===

Sim.Voucher.reg("v_overstock_norm", "Overstock", 1, nil, function(state)
    state.shop_joker_max = (state.shop_joker_max or 2) + 1
end)

Sim.Voucher.reg("v_clearance_sale", "Clearance Sale", 1, nil, function(state)
    state._discount = 25
end)

Sim.Voucher.reg("v_hone", "Hone", 1, nil, function(state)
    state._edition_rate = 2  -- Real: G.GAME.edition_rate = extra (2)
end)

Sim.Voucher.reg("v_reroll_surplus", "Reroll Surplus", 1, nil, function(state)
    state._reroll_discount = 2
end)

Sim.Voucher.reg("v_crystal_ball", "Crystal Ball", 1, nil, function(state)
    state.consumable_slots = (state.consumable_slots or 2) + 1
end)

Sim.Voucher.reg("v_telescope", "Telescope", 1, nil, function(state)
    state._telescope = true
end)

Sim.Voucher.reg("v_grabber", "Grabber", 1, nil, function(state)
    state.hands = (state.hands or 4) + 1
end)

Sim.Voucher.reg("v_wasteful", "Wasteful", 1, nil, function(state)
    state.discards = (state.discards or 3) + 1
end)

Sim.Voucher.reg("v_tarot_merchant", "Tarot Merchant", 1, nil, function(state)
    state._tarot_rate = 9.6  -- 4 * (9.6/4) per real game
end)

Sim.Voucher.reg("v_planet_merchant", "Planet Merchant", 1, nil, function(state)
    state._planet_rate = 9.6
end)

Sim.Voucher.reg("v_seed_money", "Seed Money", 1, nil, function(state)
    state._interest_cap = 50
end)

Sim.Voucher.reg("v_blank", "Blank", 1, nil, function(state)
    -- Does nothing (required for Antimatter)
end)

Sim.Voucher.reg("v_magic_trick", "Magic Trick", 1, nil, function(state)
    state._magic_trick = true
end)

Sim.Voucher.reg("v_hieroglyph", "Hieroglyph", 1, nil, function(state)
    state.ante = math.max(1, state.ante - 1)
    state.hands = (state.hands or 4) - 1  -- Secondary: -1 hand per round
end)

Sim.Voucher.reg("v_directors_cut", "Director's Cut", 1, nil, function(state)
    state._directors_cut = true
end)

Sim.Voucher.reg("v_paint_brush", "Paint Brush", 1, nil, function(state)
    state.hand_limit = (state.hand_limit or 8) + 1
end)

-- === Tier 2 (Upgrades) ===

Sim.Voucher.reg("v_overstock_plus", "Overstock Plus", 2, "v_overstock_norm", function(state)
    state.shop_joker_max = (state.shop_joker_max or 2) + 1
end)

Sim.Voucher.reg("v_liquidation", "Liquidation", 2, "v_clearance_sale", function(state)
    state._discount = 50
end)

Sim.Voucher.reg("v_glow_up", "Glow Up", 2, "v_hone", function(state)
    state._edition_rate = 4  -- Real: G.GAME.edition_rate = extra (4)
end)

Sim.Voucher.reg("v_reroll_glut", "Reroll Glut", 2, "v_reroll_surplus", function(state)
    state._reroll_discount = 4
end)

Sim.Voucher.reg("v_omen_globe", "Omen Globe", 2, "v_crystal_ball", function(state)
    state.consumable_slots = (state.consumable_slots or 2) + 1
    state._omen_globe = true  -- Spectrals in Arcana packs
end)

Sim.Voucher.reg("v_observatory", "Observatory", 2, "v_telescope", function(state)
    state._observatory = true  -- Planets in hand give x1.5 mult
end)

Sim.Voucher.reg("v_nacho_tong", "Nacho Tong", 2, "v_grabber", function(state)
    state.hands = (state.hands or 4) + 1
end)

Sim.Voucher.reg("v_recyclomancy", "Recyclomancy", 2, "v_wasteful", function(state)
    state.discards = (state.discards or 3) + 1
end)

Sim.Voucher.reg("v_tarot_tycoon", "Tarot Tycoon", 2, "v_tarot_merchant", function(state)
    state._tarot_rate = 32  -- 4 * (32/4) per real game
end)

Sim.Voucher.reg("v_planet_tycoon", "Planet Tycoon", 2, "v_planet_merchant", function(state)
    state._planet_rate = 32
end)

Sim.Voucher.reg("v_money_tree", "Money Tree", 2, "v_seed_money", function(state)
    state._interest_cap = 100
end)

Sim.Voucher.reg("v_antimatter", "Antimatter", 2, "v_blank", function(state)
    state.joker_slots = (state.joker_slots or 5) + 1
end)

Sim.Voucher.reg("v_illusion", "Illusion", 2, "v_magic_trick", function(state)
    state._illusion = true  -- Playing cards can have editions/enhancements
end)

Sim.Voucher.reg("v_petroglyph", "Petroglyph", 2, "v_hieroglyph", function(state)
    state.ante = math.max(1, state.ante - 1)
    state.discards = (state.discards or 3) - 1  -- Secondary: -1 discard per round
end)

Sim.Voucher.reg("v_retcon", "Retcon", 2, "v_directors_cut", function(state)
    state._retcon = true  -- Unlimited boss rerolls at $10
end)

Sim.Voucher.reg("v_palette", "Palette", 2, "v_paint_brush", function(state)
    state.hand_limit = (state.hand_limit or 8) + 1
end)

--- Redeem (buy) a voucher. Applies its effect and marks it as owned.
function Sim.Voucher.redeem(state, voucher_key)
    local def = Sim.Voucher.DEFS[voucher_key]
    if not def then return false end

    -- Check prerequisites
    if def.requires and not (state.vouchers and state.vouchers[def.requires]) then
        return false
    end

    -- Check if already owned
    if state.vouchers and state.vouchers[voucher_key] then return false end

    -- Deduct cost
    local cost = def.cost or 10
    local discount = state._discount or 0
    if discount > 0 then
        cost = math.max(0, math.floor(cost * (100 - discount) / 100 + 0.5))
    end
    if state.dollars < cost then return false end
    state.dollars = state.dollars - cost

    -- Mark as owned
    state.vouchers = state.vouchers or {}
    state.vouchers[voucher_key] = true

    -- Apply effect
    if def.apply then def.apply(state) end

    return true
end

--- Get the next voucher available in a tier chain.
--- Returns a voucher key that can appear in the shop.
function Sim.Voucher.get_next(state)
    state.vouchers = state.vouchers or {}
    local available = {}

    for key, def in pairs(Sim.Voucher.DEFS) do
        -- Not already owned
        if not state.vouchers[key] then
            -- Check prerequisites
            if not def.requires or state.vouchers[def.requires] then
                -- Tier 1 always available, tier 2 needs tier 1
                available[#available + 1] = key
            end
        end
    end

    if #available == 0 then return nil end
    return available[Sim.RNG.int(state.rng, 1, #available)]
end


Sim.Eval = {}

local E = Sim.ENUMS
local STONE = E.ENHANCEMENT.STONE
local WILD = E.ENHANCEMENT.WILD

local function _cid(card) return card.enhancement == STONE and 0 or card.rank end

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
    local fallback = hand[1]
    for i = 1, #hand do
        local c = hand[i]
        if c.enhancement ~= STONE then
            local v = E.RANK_NOMINAL[c.rank] + c.rank * 0.01
            if v > bv then bv = v; best = c end
        end
    end
    return best and {best} or (fallback and {fallback} or {})
end

local function _is_wild(card) return card.enhancement == WILD end
local function _is_stone(card) return card.enhancement == STONE end

local function _flush(hand, required)
    if #hand < required then return {} end
    local suit = nil
    for i = 1, #hand do
        if _is_wild(hand[i]) then
        elseif _is_stone(hand[i]) then return {}
        else
            if not suit then suit = hand[i].suit
            elseif hand[i].suit ~= suit then return {} end
        end
    end
    return {hand}
end

local function _straight(hand, required, can_skip)
    if #hand < required then return {} end
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
    -- Check ace-low straight (A-2-3-4-5)
    if seen[14] and seen[2] and seen[3] and seen[4] and seen[5] then
        br = 5
        for _, r in ipairs({14,2,3,4,5}) do
            for _, c in ipairs(seen[r]) do bc[#bc+1] = c end
        end
    end
    if can_skip then
        -- Shortcut: can skip ranks, just need `required` unique ranks in sequence
        local ranks_present = {}
        for r = 2, 14 do if seen[r] then ranks_present[#ranks_present+1] = r end end
        if #ranks_present >= required then
            for start = 1, #ranks_present - required + 1 do
                local run_cards = {}
                for j = start, start + required - 1 do
                    for _, c in ipairs(seen[ranks_present[j]]) do
                        run_cards[#run_cards+1] = c
                    end
                end
                if #run_cards > #bc then
                    bc = run_cards
                    br = required
                end
            end
        end
        -- Also check ace-low with skipping
        if seen[14] then
            local low_ranks = {}
            for r = 2, 14 do if seen[r] then low_ranks[#low_ranks+1] = r end end
            if #low_ranks >= required then
                for start = 1, #low_ranks - required + 1 do
                    local run_cards = {}
                    for j = start, start + required - 1 do
                        for _, c in ipairs(seen[low_ranks[j]]) do
                            run_cards[#run_cards+1] = c
                        end
                    end
                    if #run_cards > #bc then
                        bc = run_cards
                        br = required
                    end
                end
            end
        end
    else
        -- Normal straight detection (consecutive ranks)
        for r = 2, 14 do
            if seen[r] then
                run = run + 1
                for _, c in ipairs(seen[r]) do cards[#cards+1] = c end
                if run > br then br = run; bc = {} for _,c in ipairs(cards) do bc[#bc+1]=c end end
            else run = 0; cards = {} end
        end
    end
    return br >= required and {bc} or {}
end

--- Returns: best_type, scoring_cards, all_hands_table
--- state is optional — if provided, checks for Four Fingers / Shortcut / Splash jokers
function Sim.Eval.get_hand(cards, state)
    if not cards or #cards == 0 then
        return E.HAND_TYPE.HIGH_CARD, {}, {}
    end

    -- Check for evaluator-modifying jokers
    local four_fingers, shortcut, splash = false, false, false
    if state and state.jokers then
        for _, jk in ipairs(state.jokers) do
            local def = Sim._JOKER_BY_ID[jk.id]
            if def then
                if def.key == "j_four_fingers" then four_fingers = true
                elseif def.key == "j_shortcut" then shortcut = true
                elseif def.key == "j_splash" then splash = true end
            end
        end
    end
    local required = four_fingers and 4 or 5

    local _5, _4, _3, _2 = _x_same(5,cards), _x_same(4,cards), _x_same(3,cards), _x_same(2,cards)
    local _fl, _st, _hi = _flush(cards, required), _straight(cards, required, shortcut), _highest(cards)
    local HT = E.HAND_TYPE
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
        -- Do NOT cascade Three of a Kind or Pair from Full House (matches real game)
    end
    if #_fl > 0 then
        all[HT.FLUSH] = _fl[1]
        if HT.FLUSH < best then best = HT.FLUSH; best_sc = _fl[1] end
    end
    if #_st > 0 then
        all[HT.STRAIGHT] = _st[1]
        if HT.STRAIGHT < best then best = HT.STRAIGHT; best_sc = _st[1] end
    end
    if #_3 > 0 and not all[HT.FULL_HOUSE] then
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


Sim.Engine = {}

local E = Sim.ENUMS

local function _score_card_effects(state, c, insc, debuffed, chips, mult)
    if not insc or debuffed then return chips, mult end

    if c.enhancement ~= E.ENHANCEMENT.STONE then chips = chips + Sim.Card.chips(c) end

    if c.enhancement == E.ENHANCEMENT.BONUS then
        chips = chips + 30
    elseif c.enhancement == E.ENHANCEMENT.MULT then
        mult = mult + 4
    elseif c.enhancement == E.ENHANCEMENT.GLASS then
        mult = mult * 2
    elseif c.enhancement == E.ENHANCEMENT.STONE then
        chips = chips + 50
    elseif c.enhancement == E.ENHANCEMENT.LUCKY then
        if state.rng and Sim.RNG.next(state.rng) < 0.2 then mult = mult + 20 end
        if state.rng and Sim.RNG.next(state.rng) < (1/15) then state.dollars = state.dollars + 20 end
    end

    if c.edition == E.EDITION.FOIL then chips = chips + 50
    elseif c.edition == E.EDITION.HOLO then mult = mult + 10
    elseif c.edition == E.EDITION.POLYCHROME then mult = mult * 1.5 end

    return chips, mult
end

function Sim.Engine.calculate(state, played)
    local hand_type, scoring, all_hands = Sim.Eval.get_hand(played, state)

    local base = Sim.HAND_BASE[hand_type]
    local level = state.hand_levels[hand_type] or 1
    local chips = base[2] + base[4] * (level - 1)
    local mult  = base[1] + base[3] * (level - 1)

    local is_sc = {}
    for i = 1, #scoring do is_sc[scoring[i]] = true end

    -- Splash: all played cards count toward scoring
    local has_splash = false
    if state.jokers then
        for _, jk in ipairs(state.jokers) do
            local def = Sim._JOKER_BY_ID[jk.id]
            if def and def.key == "j_splash" then has_splash = true; break end
        end
    end
    if has_splash then
        for i = 1, #played do is_sc[played[i]] = true end
    end

    for i = 1, #played do
        local c = played[i]
        local insc = is_sc[c]
        local debuffed = Sim.Blind.is_card_debuffed(state, c)

        chips, mult = _score_card_effects(state, c, insc, debuffed, chips, mult)

        if insc and not debuffed and c.seal == E.SEAL.RED then
            chips, mult = _score_card_effects(state, c, insc, debuffed, chips, mult)
        end

        if insc and not debuffed and c.seal == E.SEAL.GOLD then
            state.dollars = state.dollars + 3
        end

        -- Individual card joker effects (scoring cards only)
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
                    scoring = scoring, all_played = played,
                    my_joker_index = ji,
                }
                local fx = def.apply(ctx, state, jk)
                if fx then
                    if fx.chip_mod then chips = chips + fx.chip_mod end
                    if fx.mult_mod then mult = mult + fx.mult_mod end
                    if fx.Xmult_mod then mult = mult * fx.Xmult_mod end
                end
            end
            if jk.edition == E.EDITION.FOIL then chips = chips + 50
            elseif jk.edition == E.EDITION.HOLO then mult = mult + 10
            elseif jk.edition == E.EDITION.POLYCHROME then mult = mult * 1.5 end
        end
    end

    -- Held-in-hand effects: cards remaining in hand after play
    for i = 1, #state.hand do
        local c = state.hand[i]
        local debuffed = Sim.Blind.is_card_debuffed(state, c)
        if not debuffed then
            local reps = 1
            if c.seal == E.SEAL.RED then reps = 2 end
            for r = 1, reps do
                if c.enhancement == E.ENHANCEMENT.STEEL then
                    mult = mult * 1.5
                elseif c.enhancement == E.ENHANCEMENT.GOLD then
                    state.dollars = state.dollars + 3
                end
                -- Joker effects on held cards
                if state.jokers then
                    for ji = 1, #state.jokers do
                        local jk = state.jokers[ji]
                        local def = Sim._JOKER_BY_ID[jk.id]
                        if def and def.apply then
                            local ctx = {
                                held = true, cardarea = "hand",
                                other_card = c, my_joker_index = ji,
                            }
                            local fx = def.apply(ctx, state, jk)
                            if fx then
                                if fx.x_mult then mult = mult * fx.x_mult end
                                if fx.mult then mult = mult + fx.mult end
                                if fx.chips then chips = chips + fx.chips end
                            end
                        end
                    end
                end
            end
        end
    end

    -- Sock and Buskin: re-trigger individual effects for face cards
    local has_sock = false
    if state.jokers then
        for ji = 1, #state.jokers do
            local jdef = Sim._JOKER_BY_ID[state.jokers[ji].id]
            if jdef and jdef.key == "j_sock_and_buskin" then has_sock = true; break end
        end
    end
    if has_sock then
        for i = 1, #played do
            local c = played[i]
            local insc = is_sc[c]
            local debuffed = Sim.Blind.is_card_debuffed(state, c)
            if insc and not debuffed and c.rank >= E.RANK.JACK and c.rank <= E.RANK.KING then
                -- Re-trigger individual card joker effects for face cards
                if state.jokers then
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
        end
    end

    -- Boss blind modify_hand hook (The Flint halves chips and mult)
    local mod_chips, mod_mult = Sim.Blind.modify_hand(state, chips, mult)
    if mod_chips then chips = mod_chips end
    if mod_mult then mult = mod_mult end

    return math.floor(chips * mult), chips, mult, hand_type, scoring, all_hands
end


Sim.State = {}
Sim.DEFAULTS = { hands=4, discards=4, hand_size=8, joker_slots=5, cons_slots=2, start_money=4 }

function Sim.State.new(opts)
    opts = opts or {}
    local d = Sim.DEFAULTS
    local deck = opts.deck or Sim.Card.new_deck()
    local rng = opts.rng or Sim.RNG.new(opts.seed or "BALATRO")
    if not opts.deck then Sim.RNG.shuffle(rng, deck) end
    local hl = {}
    for i = 1, 12 do hl[i] = 1 end
    local htc = {}
    for i = 1, 12 do htc[i] = 0 end
    return {
        deck=deck, hand={}, discard={}, hand_limit=opts.hand_size or d.hand_size,
        jokers=opts.jokers or {}, joker_slots=d.joker_slots,
        consumables=opts.consumables or {}, consumable_slots=d.cons_slots,
        phase=opts.phase or Sim.ENUMS.PHASE.BLIND_SELECT,
        dollars=opts.dollars or d.start_money,
        ante=opts.ante or 1, round=0,
        hands_left=d.hands, discards_left=d.discards, hands_played=0,
        blind_type="none", blind_chips=300, blind_beaten=false,
        selection={}, hand_levels=hl, hand_type_counts=htc,
        chips=0, total_chips=0,
        deck_count=52,
        pack_cards=nil, last_consumable=nil,
        rng=rng, _joker_n=0, _cons_n=0,
        ride_the_bus=0, cards_drawn=0,
        round_dollars=0,
    }
end

function Sim.State.draw(state)
    if #state.hand >= state.hand_limit then return state end
    local n = math.min(state.hand_limit - #state.hand, #state.deck)
    for i = 1, n do
        local card = table.remove(state.deck, 1)
        -- Boss blind: stay_flipped check (The Wheel, House, Mark, Fish)
        if card and Sim.Blind.stay_flipped(state, card) then
            card._flipped = true
        end
        state.hand[#state.hand+1] = card
        state.cards_drawn = state.cards_drawn + 1
    end
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
    local cap = state._interest_cap or 5
    return math.min(math.floor(state.dollars / 5), cap)
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


Sim.Blind = {}
local BLIND_DATA = {
    {name="Small", mult=1.0, reward=3},
    {name="Big",   mult=1.5, reward=4},
    {name="Boss",  mult=2.0, reward=5},
}

local SUIT = Sim.ENUMS.SUIT

Sim.BOSS_BLINDS = {
    -- Regular bosses (23) — behaviors match blind.lua exactly
    { name = "The Club",       chip_mult = 1.0, min_ante = 1, setup = function(st) st._boss_debuff_suit = SUIT.CLUBS end },
    { name = "The Goad",       chip_mult = 1.0, min_ante = 1, setup = function(st) st._boss_debuff_suit = SUIT.SPADES end },
    { name = "The Head",       chip_mult = 1.0, min_ante = 1, setup = function(st) st._boss_debuff_suit = SUIT.HEARTS end },
    { name = "The Window",     chip_mult = 1.0, min_ante = 1, setup = function(st) st._boss_debuff_suit = SUIT.DIAMONDS end },
    { name = "The Psychic",    chip_mult = 1.0, min_ante = 1, setup = function(st) st._boss_h_size_ge = 5 end },
    { name = "The Hook",       chip_mult = 1.0, min_ante = 1, setup = function(st) end },
    { name = "The Manacle",    chip_mult = 1.0, min_ante = 1, setup = function(st) st.hand_limit = st.hand_limit - 1 end },
    { name = "The Water",      chip_mult = 1.0, min_ante = 2, setup = function(st) st._boss_discards_removed = st.discards_left; st.discards_left = 0 end },
    { name = "The Wall",       chip_mult = 2.0, min_ante = 2, setup = function(st) end },
    { name = "The House",      chip_mult = 1.0, min_ante = 2, setup = function(st) end },
    { name = "The Arm",        chip_mult = 1.0, min_ante = 2, setup = function(st) end },
    { name = "The Wheel",      chip_mult = 1.0, min_ante = 2, setup = function(st) end },
    { name = "The Fish",       chip_mult = 1.0, min_ante = 2, setup = function(st) st._boss_fish_prepped = false end },
    { name = "The Mouth",      chip_mult = 1.0, min_ante = 2, setup = function(st) st._boss_only_hand = false end },
    { name = "The Mark",       chip_mult = 1.0, min_ante = 2, setup = function(st) end },
    { name = "The Tooth",      chip_mult = 1.0, min_ante = 3, setup = function(st) end },
    { name = "The Eye",        chip_mult = 1.0, min_ante = 3, setup = function(st) st._boss_hands_played = {} end },
    { name = "The Plant",      chip_mult = 1.0, min_ante = 4, setup = function(st) st._boss_debuff_faces = true end },
    { name = "The Needle",     chip_mult = 0.5, min_ante = 2, setup = function(st) st.hands_left = 1 end },
    { name = "The Pillar",     chip_mult = 1.0, min_ante = 1, setup = function(st) end },
    { name = "The Serpent",    chip_mult = 1.0, min_ante = 5, setup = function(st) end },
    { name = "The Ox",         chip_mult = 1.0, min_ante = 6, setup = function(st) end },
    { name = "The Flint",      chip_mult = 1.0, min_ante = 2, setup = function(st) end },
    -- Showdown bosses (ante 8 only, 5)
    { name = "Cerulean Bell",  chip_mult = 1.0, min_ante = 8, showdown = true, setup = function(st) end },
    { name = "Verdant Leaf",   chip_mult = 1.0, min_ante = 8, showdown = true, setup = function(st) st._boss_debuff_all = true end },
    { name = "Violet Vessel",  chip_mult = 3.0, min_ante = 8, showdown = true, setup = function(st) end },
    { name = "Amber Acorn",    chip_mult = 1.0, min_ante = 8, showdown = true, setup = function(st)
        -- Shuffle jokers (from real game set_blind)
        Sim.RNG.shuffle(st.rng, st.jokers)
    end },
    { name = "Crimson Heart",  chip_mult = 1.0, min_ante = 8, showdown = true, setup = function(st) end },
}

function Sim.Blind.pick_boss(state, ante)
    -- Boss rotation: don't repeat until all seen
    if not state._bosses_seen then state._bosses_seen = {} end

    -- Filter to eligible bosses (ante range, showdown only on ante 8)
    local eligible = {}
    local is_showdown = (ante % 8 == 0 and ante >= 8)
    for i = 1, #Sim.BOSS_BLINDS do
        local boss = Sim.BOSS_BLINDS[i]
        local min = boss.min_ante or 1
        if boss.showdown then
            if is_showdown and ante >= min then
                eligible[#eligible + 1] = i
            end
        else
            if ante >= min and not is_showdown then
                eligible[#eligible + 1] = i
            end
        end
    end

    -- If all eligible bosses seen, reset
    local all_seen = true
    for _, idx in ipairs(eligible) do
        if not state._bosses_seen[idx] then all_seen = false; break end
    end
    if all_seen then state._bosses_seen = {} end

    -- Pick from unseen eligible
    local unseen = {}
    for _, idx in ipairs(eligible) do
        if not state._bosses_seen[idx] then unseen[#unseen+1] = idx end
    end
    if #unseen == 0 then unseen = eligible end
    local idx = Sim.RNG.pick(state.rng, unseen)
    state._bosses_seen[idx] = true
    return Sim.BOSS_BLINDS[idx]
end

function Sim.Blind.is_card_debuffed(state, card)
    if not state.boss_name then return false end
    -- Generic suit debuff (Club, Goad/Spade, Head/Heart, Window/Diamond)
    if state._boss_debuff_suit and card.suit == state._boss_debuff_suit then
        return true
    end
    -- Face card debuff (The Plant) — uses is_face check (rank >= 11)
    if state._boss_debuff_faces and card.rank >= 11 and card.rank <= 13 then
        return true
    end
    -- The Pillar: debuff cards played this ante
    if state.boss_name == "The Pillar" and card._played_this_ante then
        return true
    end
    -- Verdant Leaf: debuff ALL non-joker cards
    if state._boss_debuff_all then
        return true
    end
    return false
end

--- Check if a card should stay face-down (The Wheel, The House, The Mark, The Fish).
--- Called when drawing cards. Returns true to keep card flipped.
function Sim.Blind.stay_flipped(state, card)
    if not state.boss_name then return false end
    -- The House: first hand stays face down (hands_played==0 AND discards_used==0)
    if state.boss_name == "The House" and state.hands_played == 0 and state._discards_used == 0 then
        return true
    end
    -- The Wheel: 1/7 chance per card
    if state.boss_name == "The Wheel" then
        return Sim.RNG.next(state.rng) < (1/7)
    end
    -- The Mark: face cards stay face down
    if state.boss_name == "The Mark" and card.rank >= 11 and card.rank <= 13 then
        return true
    end
    -- The Fish: cards stay face down after first play
    if state.boss_name == "The Fish" and state._boss_fish_prepped then
        return true
    end
    return false
end

--- Modify hand scoring (The Flint halves both chips and mult).
--- Returns modified_chips, modified_mult, or nil to not modify.
function Sim.Blind.modify_hand(state, chips, mult)
    if state.boss_name == "The Flint" then
        return math.max(math.floor(chips * 0.5 + 0.5), 0),
               math.max(math.floor(mult * 0.5 + 0.5), 1)
    end
    return chips, mult
end

--- Check if hand is invalid due to boss debuff (The Psychic, The Eye, The Mouth).
--- Returns true if the hand should be debuffed/invalidated.
function Sim.Blind.debuff_hand(state, hand_type, hand_name, played_cards)
    if not state.boss_name then return false end

    -- The Psychic: must play 5 cards
    if state.boss_name == "The Psychic" and #played_cards < 5 then
        return true
    end

    -- The Eye: can't play same hand type twice
    if state.boss_name == "The Eye" then
        if state._boss_hands_played[hand_type] then
            return true
        end
        state._boss_hands_played[hand_type] = true
    end

    -- The Mouth: can only play one hand type
    if state.boss_name == "The Mouth" then
        if state._boss_only_hand and state._boss_only_hand ~= hand_type then
            return true
        end
        if not state._boss_only_hand then
            state._boss_only_hand = hand_type
        end
    end

    return false
end

function Sim.Blind.on_play(state, played_cards)
    if not state.boss_name then return end

    -- The Arm: decrease played hand level by 1 (if level > 1)
    if state.boss_name == "The Arm" then
        local ht = Sim.Eval.get_hand(played_cards, state)
        if state.hand_levels[ht] and state.hand_levels[ht] > 1 then
            state.hand_levels[ht] = state.hand_levels[ht] - 1
        end
    end

    -- The Tooth: -$1 per card played
    if state.boss_name == "The Tooth" then
        state.dollars = math.max(0, state.dollars - #played_cards)
    end

    -- The Ox: if play most played hand, set money to 0
    if state.boss_name == "The Ox" then
        local ht = Sim.Eval.get_hand(played_cards, state)
        local hand_names = {"High Card","Pair","Two Pair","Three of a Kind","Straight",
            "Flush","Full House","Four of a Kind","Straight Flush","Five of a Kind",
            "Flush House","Flush Five"}
        local hand_name = hand_names[ht]
        if hand_name and hand_name == state._most_played_hand then
            state.dollars = 0
        end
    end

    -- Track played cards for The Pillar
    for _, c in ipairs(played_cards) do
        c._played_this_ante = true
    end

    -- The Fish: set prepped flag after first play
    if state.boss_name == "The Fish" then
        state._boss_fish_prepped = true
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
    local defs = Sim.DEFAULTS
    state.hand_limit = defs.hand_size
    state._boss_debuff_suit = nil
    state.boss_name = nil

    state.blind_type = BLIND_DATA[btype].name
    state.blind_chips = Sim.Blind.chips(state.ante, btype)
    state.blind_beaten = false
    state.chips = 0
    state.hands_left = defs.hands
    state.discards_left = defs.discards
    state.hands_played = 0
    state.round = state.round + 1
    state.selection = {}

    if btype == 3 then
        local boss = Sim.Blind.pick_boss(state, state.ante)
        state.boss_name = boss.name
        if boss.chip_mult and boss.chip_mult ~= 1.0 then
            state.blind_chips = math.floor(state.blind_chips * boss.chip_mult)
        end
        boss.setup(state)
    end

    -- Fire setting_blind context for jokers (Burglar, Marble, Cartomancer, etc.)
    if state.jokers then
        for ji = 1, #state.jokers do
            local jk = state.jokers[ji]
            local def = Sim._JOKER_BY_ID[jk.id]
            if def and def.apply then
                local ctx = { setting_blind = true, my_joker_index = ji }
                def.apply(ctx, state, jk)
            end
        end
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

--
-- Shop generation uses weighted card type selection:
--   Joker: 71.4%, Tarot: 14.3%, Planet: 14.3%
-- Pricing respects discounts and vouchers.
-- Edition rolls match real game probabilities.

Sim.Shop = {}

--- Calculate card cost with discounts.
--- Real formula: math.max(1, math.floor((base_cost + 0.5) * (100 - discount) / 100))
local function apply_discount(base_cost, state)
    local discount = state._discount or 0
    return math.max(1, math.floor((base_cost + 0.5) * (100 - discount) / 100))
end

--- Select a card type using weighted random (matches real game).
--- Returns: "Joker", "Tarot", "Planet", or "Spectral"
local function pick_card_type(state)
    local joker_rate = 20
    local tarot_rate = state._tarot_rate or 4    -- 9.6 with Tarot Merchant, 32 with Tycoon
    local planet_rate = state._planet_rate or 4  -- 9.6 with Planet Merchant, 32 with Tycoon
    local spectral_rate = 0

    local total = joker_rate + tarot_rate + planet_rate + spectral_rate
    local roll = Sim.RNG.next(state.rng) * total

    if roll < joker_rate then return "Joker"
    elseif roll < joker_rate + tarot_rate then return "Tarot"
    elseif roll < joker_rate + tarot_rate + planet_rate then return "Planet"
    else return "Spectral"
    end
end

--- Generate a shop slot (could be joker, tarot, or planet).
local function generate_shop_slot(state, slot_num)
    local card_type = pick_card_type(state)
    local card = Sim.CardFactory.create(card_type, state, state.rng)
    if not card then return nil end

    if card_type == "Joker" then
        local def = Sim._JOKER_BY_ID[card.id]
        if not def then return nil end
        local base_cost = def.cost or 3
        return { type = "joker", joker_id = card.id, cost = apply_discount(base_cost, state),
                 edition = card.edition, slot = slot_num, uid = card.uid }
    else
        -- Consumable
        local def = Sim.CONSUMABLE_DEFS
        local name = nil
        for k, v in pairs(def) do
            if v.id == card.id then name = v.name; break end
        end
        local base_cost = card_type == "Planet" and 3 or 3
        return { type = "consumable", cons_id = card.id, cost = apply_discount(base_cost, state),
                 card_type = card_type, slot = slot_num, uid = card.uid }
    end
end

--- Generate boosters for the shop.
local function generate_boosters(state)
    local boosters = {}
    -- Always 2 booster slots
    for i = 1, 2 do
        local roll = Sim.RNG.next(state.rng)
        local pack_type, cost, picks
        if roll < 0.4 then
            pack_type = "buffoon_normal"; cost = apply_discount(4, state); picks = 1
        elseif roll < 0.7 then
            pack_type = "buffoon_jumbo"; cost = apply_discount(6, state); picks = 1
        else
            pack_type = "arcana_normal"; cost = apply_discount(4, state); picks = 1
        end
        boosters[i] = { type = "booster", pack_type = pack_type, cost = cost, picks = picks, slot = 100 + i }
    end
    return boosters
end

function Sim.Shop.generate(state)
    local joker_max = 2
    -- Voucher modifiers for shop slots
    if Sim.CardFactory.has_voucher(state, "v_overstock_norm") then joker_max = joker_max + 1 end
    if Sim.CardFactory.has_voucher(state, "v_overstock_plus") then joker_max = joker_max + 1 end

    local shop = { items = {}, boosters = {}, voucher = nil, jokers = {} }

    -- Generate card slots (joker_max total, weighted by type)
    for i = 1, joker_max do
        local item = generate_shop_slot(state, i)
        if item then
            shop.items[#shop.items + 1] = item
            if item.type == "joker" then
                shop.jokers[i] = item  -- Keep backward compat
            end
        end
    end

    -- Generate boosters
    shop.boosters = generate_boosters(state)
    -- Keep backward compat: first booster
    shop.booster = shop.boosters[1]

    -- Consumable slot (if room)
    if #state.consumables < (state.consumable_slots or 2) then
        local cons_card = Sim.CardFactory.create(pick_card_type(state), state, state.rng)
        if cons_card then
            shop.consumable = { cons_id = cons_card.id, cost = 0, slot = 99, uid = cons_card.uid }
        end
    end

    state.shop = shop
    return state
end

function Sim.Shop.reroll(state)
    if not state.shop then return state end
    -- Reroll costs
    local base_cost = state._reroll_cost or 5
    local discount = state._reroll_discount or 0
    local cost = math.max(0, base_cost - discount)
    if state.dollars < cost then return false end
    state.dollars = state.dollars - cost
    state._reroll_cost = (state._reroll_cost or 5) + 1

    -- Regenerate
    return Sim.Shop.generate(state)
end

function Sim.Shop.buy_joker(state, slot)
    if not state.shop then return false end
    local item = state.shop.jokers[slot]
    if not item then return false end
    if state.dollars < item.cost then return false end
    local def = Sim._JOKER_BY_ID[item.joker_id]
    if not def then return false end
    if #state.jokers >= state.joker_slots then return false end
    state.dollars = state.dollars - item.cost
    local jk = Sim.State.add_joker(state, def)
    if jk and item.edition then jk.edition = item.edition end
    state.shop.jokers[slot] = nil
    -- Also remove from items list
    for i, it in ipairs(state.shop.items) do
        if it == item then table.remove(state.shop.items, i); break end
    end
    return true
end

function Sim.Shop.sell_joker(state, joker_idx)
    local jk = state.jokers[joker_idx]
    if not jk then return false end
    local def = Sim._JOKER_BY_ID[jk.id]
    state.dollars = state.dollars + math.floor((def.cost or 3) / 2)
    -- Fire selling_card context for jokers (Campfire, Gift Card, etc.)
    if state.jokers then
        for ji = 1, #state.jokers do
            local ojk = state.jokers[ji]
            if ojk ~= jk then
                local odef = Sim._JOKER_BY_ID[ojk.id]
                if odef and odef.apply then
                    local ctx = { selling_card = true, my_joker_index = ji }
                    odef.apply(ctx, state, ojk)
                end
            end
        end
    end
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
    -- Fire open_booster context for jokers (Hallucination, etc.)
    if state.jokers then
        for ji = 1, #state.jokers do
            local jk = state.jokers[ji]
            local def = Sim._JOKER_BY_ID[jk.id]
            if def and def.apply then
                local ctx = { open_booster = true, my_joker_index = ji }
                def.apply(ctx, state, jk)
            end
        end
    end
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

--
-- Layout (180 floats):
--   [0-55]    Hand cards:     8 slots × 7 features = 56
--   [56-70]   Jokers:         5 slots × 3 features = 15
--   [71-80]   Global:         10 features
--   [81-92]   Hand levels:    12 (log-scaled)
--   [93-95]   Phase:          3 one-hot
--   [96]      Selection:      1
--   [97-100]  Consumables:    2 slots × 2 features = 4
--   [101]     Pack open:      1
--   [102-131] Pack cards:     5 slots × 6 features = 30
--   [132-135] Shop items:     4
--   [136]     Joker count:    1
--   [137]     Consumable cnt: 1
--   [138-150] Deck ranks:     13 (2-A histogram)
--   [151-154] Deck suits:     4
--   [155]     Boss active:    1
--   [156]     Boss chip mult: 1
--   [157-159] Blind states:   3 (Small/Big/Boss progress)
--   [160-179] Spare:          20

Sim.Obs = {}
Sim.Obs.DIM = 180

function Sim.Obs.encode(state)
    local o = {}
    local n = 0
    local defs = Sim.DEFAULTS

    -- Helper: check if a hand card is debuffed by current boss
    local function _is_debuffed(c)
        if not state._boss_debuff_suit then return false end
        return c.suit == state._boss_debuff_suit
    end

    -- 8 hand card slots × 7 features = 56
    for i = 1, 8 do
        local c = state.hand[i]
        if c then
            o[n+1] = c.rank / 14
            o[n+2] = c.suit / 4
            o[n+3] = c.enhancement / 8
            o[n+4] = c.edition / 4
            o[n+5] = c.seal / 4
            o[n+6] = _is_debuffed(c) and 1.0 or 0.0
            o[n+7] = 1
        else
            for j = 1, 7 do o[n+j] = 0 end
        end
        n = n + 7
    end

    -- 5 joker slots × 3 features = 15
    local jcount = #Sim._JOKER_BY_ID
    for i = 1, 5 do
        local jk = state.jokers[i]
        if jk then
            o[n+1] = jk.id / math.max(jcount, 1)
            o[n+2] = jk.edition / 4
            o[n+3] = 1
        else
            for j = 1, 3 do o[n+j] = 0 end
        end
        n = n + 3
    end

    -- 10 global features
    o[n+1] = math.min(state.chips / math.max(state.blind_chips, 1), 1.0)
    o[n+2] = math.min(state.dollars / 50.0, 1.0)
    o[n+3] = state.hands_left / defs.hands
    o[n+4] = state.discards_left / defs.discards
    o[n+5] = state.ante / 8.0
    o[n+6] = math.min(state.round / 24.0, 1.0)
    o[n+7] = state.blind_beaten and 1.0 or 0.0
    o[n+8] = math.min(state.deck_count / 52.0, 1.0)
    o[n+9] = math.min(state.total_chips / math.max(state.blind_chips, 1), 1.0)
    o[n+10] = math.min((state.hands_played or 0) / 8.0, 1.0)
    n = n + 10

    -- 12 hand levels (log-scaled, capped to [0, 1])
    -- Scale = 1/ln(32) so level 31 maps to 1.0
    local LOG_SCALE = 1.0 / math.log(32)
    for i = 1, 12 do
        local v = math.log((state.hand_levels[i] or 1) + 1) * LOG_SCALE
        o[n+1] = math.min(v, 1.0)
        n = n + 1
    end

    -- Phase one-hot (SELECTING_HAND, SHOP, PACK_OPEN)
    local p = state.phase
    o[n+1] = (p == 1) and 1.0 or 0.0
    o[n+2] = (p == 2) and 1.0 or 0.0
    o[n+3] = (p == 3) and 1.0 or 0.0
    n = n + 3

    -- Selection count / 8
    o[n+1] = #state.selection / 8.0
    n = n + 1

    -- 2 consumable slots × 2 features = 4
    local ccount = #Sim._CONS_BY_ID
    for i = 1, 2 do
        local cs = state.consumables[i]
        if cs then
            o[n+1] = cs.id / math.max(ccount, 1)
            o[n+2] = 1
        else
            o[n+1] = 0; o[n+2] = 0
        end
        n = n + 2
    end

    -- Pack open flag
    o[n+1] = state.pack_cards and 1.0 or 0.0
    n = n + 1

    -- 5 pack card slots × 6 features = 30
    for i = 1, 5 do
        local pc = state.pack_cards and state.pack_cards[i] or nil
        if pc then
            if type(pc) == "table" and pc.rank then
                o[n+1] = pc.rank / 14
                o[n+2] = pc.suit / 4
                o[n+3] = pc.enhancement / 8
                o[n+4] = pc.edition / 4
                o[n+5] = pc.seal / 4
                o[n+6] = 1
            elseif type(pc) == "number" then
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

    -- Shop items present (joker1, joker2, booster, consumable)
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

    -- Deck rank histogram: 13 ranks (2-14), each count/4
    local rank_counts = {}
    for i = 2, 14 do rank_counts[i] = 0 end
    for _, c in ipairs(state.deck) do
        if c.rank >= 2 and c.rank <= 14 then
            rank_counts[c.rank] = (rank_counts[c.rank] or 0) + 1
        end
    end
    for r = 2, 14 do
        o[n+1] = (rank_counts[r] or 0) / 4.0
        n = n + 1
    end

    -- Deck suit counts: 4 suits, each count/13
    local suit_counts = {}
    for i = 1, 4 do suit_counts[i] = 0 end
    for _, c in ipairs(state.deck) do
        if c.suit >= 1 and c.suit <= 4 then
            suit_counts[c.suit] = (suit_counts[c.suit] or 0) + 1
        end
    end
    for s = 1, 4 do
        o[n+1] = (suit_counts[s] or 0) / 13.0
        n = n + 1
    end

    -- Boss blind active
    o[n+1] = (state.boss_name ~= nil) and 1.0 or 0.0
    n = n + 1

    -- Boss chip multiplier (normalized: 1.0 = normal, 2.0 = The Wall)
    local boss_mult = 1.0
    if state.boss_name and state.blind_chips > 0 then
        -- Infer from chip amounts: boss mult = actual / (base * blind_type_mult)
        local btype_mult = ({1.0, 1.5, 2.0})[3] or 1.0  -- Boss blind type
        local amounts = {300,800,2000,5000,11000,20000,35000,50000}
        local base = amounts[math.min(state.ante, 8)] or 50000
        local expected = math.floor(base * btype_mult)
        boss_mult = state.blind_chips / math.max(expected, 1)
    end
    o[n+1] = math.min(boss_mult / 2.5, 1.0)
    n = n + 1

    -- Blind selection states: 3 values (0=pending, 0.5=skipped, 1.0=done)
    local bs = state._blind_states
    if bs then
        for _, name in ipairs({"Small", "Big", "Boss"}) do
            local s = bs[name]
            if s == "done" then o[n+1] = 1.0
            elseif s == "skipped" then o[n+1] = 0.5
            else o[n+1] = 0.0 end
            n = n + 1
        end
    else
        for j = 1, 3 do o[n+j] = 0.0 end
        n = n + 3
    end

    -- Spare to fill to 180
    while n < 180 do
        n = n + 1
        o[n] = 0
    end

    return o
end


Sim.Env = {}
Sim.Env.action_spec = {
    types = { "SELECT_CARDS","PLAY_DISCARD","SHOP_ACTION","USE_CONSUMABLE","PHASE_ACTION" },
    obs_dim = 180,
}

local E = Sim.ENUMS

function Sim.Env.reset(seed)
    local rng = Sim.RNG.new(seed)
    local state = Sim.State.new({ rng = rng, seed = seed })
    Sim.Blind.init_ante(state)
    local btype = Sim.Blind.next_type(state)
    if btype then
        Sim.Blind.setup(state, btype)
        state.phase = E.PHASE.SELECTING_HAND
    end
    return Sim.Obs.encode(state), { seed = seed, ante = state.ante }
end

function Sim._do_reorder(state, value)
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

function Sim._use_consumable(state, cons_index)
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

local function _step_selecting(state, atype, value)
    local R = E.REWARD

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
            state.hand_type_counts[ht] = (state.hand_type_counts[ht] or 0) + 1

            -- Ride the Bus: reset on face cards, increment otherwise
            local has_face = false
            for _, c in ipairs(played) do
                if c.rank >= E.RANK.JACK and c.rank <= E.RANK.KING then has_face = true; break end
            end
            if has_face then
                state.ride_the_bus = 0
            else
                state.ride_the_bus = (state.ride_the_bus or 0) + 1
            end

            -- Glass card destruction (1/4 chance per Glass card)
            local destroyed = {}
            for _, c in ipairs(played) do
                if c.enhancement == E.ENHANCEMENT.GLASS and not Sim.Blind.is_card_debuffed(state, c) then
                    if state.rng and Sim.RNG.next(state.rng) < 0.25 then
                        destroyed[c] = true
                    end
                end
            end

            -- Add played cards to discard (except destroyed ones)
            for _, c in ipairs(played) do
                if not destroyed[c] then
                    state.discard[#state.discard+1] = c
                else
                    state.deck_count = state.deck_count - 1
                end
            end
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
                        if fx then
                            if fx.level_up then
                                Sim.State.level_up(state, fx.level_up)
                            end
                            if fx.chip_mod then
                                state.chips = state.chips + fx.chip_mod
                                total = total + fx.chip_mod
                            end
                            -- Note: after_play jokers should return chip_mod, not mult_mod.
                            -- Mult is already finalized at this point.
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
            local disc_ht = Sim.Eval.get_hand(disc_cards, state)

            -- Trigger Burnt Joker (on_discard, is_first_discard) and Ramen
            local num_discarded = #sorted
            local destroyed_jokers = {}
            if state.jokers then
                for ji = 1, #state.jokers do
                    local jk = state.jokers[ji]
                    local def = Sim._JOKER_BY_ID[jk.id]
                    if def and def.apply then
                        local ctx = {
                            on_discard = true,
                            is_first_discard = (state.discards_left == Sim.DEFAULTS.discards),
                            discarded_hand_type = disc_ht,
                            cards_discarded = num_discarded,
                        }
                        local fx = def.apply(ctx, state, jk)
                        if fx then
                            if fx.level_up then
                                Sim.State.level_up(state, fx.level_up)
                            end
                            if fx.destroy_self then
                                destroyed_jokers[#destroyed_jokers+1] = ji
                            end
                        end
                    end
                end
            end
            -- Remove destroyed jokers (reverse order)
            for i = #destroyed_jokers, 1, -1 do
                table.remove(state.jokers, destroyed_jokers[i])
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
            return Sim._advance_blind(state)
        end
        -- value 2 = skip blind
        if value == 2 and not state.blind_beaten then
            return Sim._skip_blind(state)
        end

    elseif atype == E.ACTION.USE_CONSUMABLE then
        return Sim._use_consumable(state, value)

    elseif atype == E.ACTION.REORDER then
        return Sim._do_reorder(state, value)
    end

    return Sim.Obs.encode(state), R.INVALID, false
end

function Sim._advance_blind(state)
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

    -- Round-end joker effects (Delayed Gratification, etc.)
    if state.jokers then
        for ji = 1, #state.jokers do
            local jk = state.jokers[ji]
            local def = Sim._JOKER_BY_ID[jk.id]
            if def and def.apply then
                local ctx = { round_end = true }
                local fx = def.apply(ctx, state, jk)
                if fx and fx.dollars then
                    state.dollars = state.dollars + fx.dollars
                end
            end
        end
    end

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

function Sim._skip_blind(state)
    local R = E.REWARD
    local names = {"Small","Big","Boss"}
    local bname = state.blind_type
    for i = 1, 3 do
        if names[i] == bname then Sim.Blind.mark_done(state, i, true); break end
    end

    -- Track skips
    state.skips = (state.skips or 0) + 1
    state._blind_states = state._blind_states or {}
    state._blind_states[bname] = "skipped"

    -- Pick and add a tag
    local tag_key = Sim.Tag.pick(state)
    if tag_key then
        Sim.Tag.add(state, tag_key)
    end

    -- Fire skip_blind context for jokers (Throwback, etc.)
    if state.jokers then
        for ji = 1, #state.jokers do
            local jk = state.jokers[ji]
            local def = Sim._JOKER_BY_ID[jk.id]
            if def and def.apply then
                local ctx = { skip_blind = true, my_joker_index = ji }
                def.apply(ctx, state, jk)
            end
        end
    end

    -- Fire new_blind_choice tags
    Sim.Tag.apply(state, "new_blind_choice")

    -- Discard hand, clear state
    for _, c in ipairs(state.hand) do state.discard[#state.discard+1] = c end
    state.hand = {}
    state.selection = {}

    -- Advance to next blind
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
        return Sim._use_consumable(state, value)

    elseif atype == E.ACTION.REORDER then
        return Sim._do_reorder(state, value)

    elseif atype == E.ACTION.PHASE_ACTION and value == 0 then
        -- End shop — fire ending_shop context for jokers (Perkeo, etc.)
        if state.jokers then
            for ji = 1, #state.jokers do
                local jk = state.jokers[ji]
                local def = Sim._JOKER_BY_ID[jk.id]
                if def and def.apply then
                    local ctx = { ending_shop = true, my_joker_index = ji }
                    def.apply(ctx, state, jk)
                end
            end
        end
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

function Sim.Env.step(state, atype, value)
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

--- Simple env helpers (called from Python to avoid duplicated Lua logic)

--- Play cards by 1-indexed hand positions. Returns total score.
function Sim.play_cards_by_indices(state, indices)
    local played = {}
    for _, idx in ipairs(indices) do
        played[#played+1] = state.hand[idx]
    end
    local total, chips, mult, ht = Sim.Engine.calculate(state, played)
    state.total_chips = state.total_chips + total
    state.chips = state.chips + total
    state.hands_left = state.hands_left - 1
    state.hands_played = state.hands_played + 1
    state.hand_type_counts[ht] = (state.hand_type_counts[ht] or 0) + 1
    for _, c in ipairs(played) do state.discard[#state.discard+1] = c end
    table.sort(indices, function(a, b) return a > b end)
    for _, idx in ipairs(indices) do table.remove(state.hand, idx) end
    Sim.State.draw(state)
    if state.chips >= state.blind_chips then state.blind_beaten = true end
    return total
end

--- Discard the first n cards from hand.
function Sim.discard_first_n(state, n)
    n = math.min(n, #state.hand)
    for i = n, 1, -1 do
        local c = table.remove(state.hand, i)
        if c then state.discard[#state.discard+1] = c end
    end
    state.discards_left = state.discards_left - 1
    Sim.State.draw(state)
end

--- Auto-shop: buy affordable jokers/consumables, then advance.
function Sim.auto_shop(state)
    local shop = state.shop
    if shop then
        for si = 1, 2 do
            local jk = shop.jokers[si]
            if jk and state.dollars >= jk.cost and #state.jokers < state.joker_slots then
                Sim.Shop.buy_joker(state, si)
                break
            end
        end
        if shop.consumable and #state.consumables < state.consumable_slots then
            Sim.Shop.buy_consumable(state)
        end
    end
    state.shop = nil
    local bt = Sim.Blind.next_type(state)
    if bt then Sim.Blind.setup(state, bt); state.phase = E.PHASE.SELECTING_HAND end
end

--- Advance to next blind (simple env version, includes auto-shop on new ante).
function Sim.advance_simple(state)
    local names = {"Small", "Big", "Boss"}
    for i = 1, 3 do
        if names[i] == state.blind_type then Sim.Blind.mark_done(state, i); break end
    end
    local rd = Sim.Blind.reward(
        state.blind_type == "Small" and 1 or state.blind_type == "Big" and 2 or 3)
    state.dollars = state.dollars + rd + Sim.State.interest(state)
    for _, c in ipairs(state.hand) do state.discard[#state.discard+1] = c end
    state.hand = {}
    state.selection = {}
    local nb = Sim.Blind.next_type(state)
    if not nb then
        state.ante = state.ante + 1
        if state.ante > 8 then state.phase = E.PHASE.WIN; return end
        Sim.Blind.init_ante(state)
        nb = Sim.Blind.next_type(state)
        Sim.auto_shop(state)
    end
    Sim.Blind.setup(state, nb)
    state.phase = E.PHASE.SELECTING_HAND
end


if _SIM_RUN_TESTS or ({...})[1] == "_RUN_TESTS" then
    local E = Sim.ENUMS
    local C = Sim.Card.new
    local passed, total = 0, 0
    local function test(name, cond)
        total = total + 1
        if cond then passed = passed + 1; print("  [OK] " .. name)
        else print("  [FAIL] " .. name) end
    end

    print("=== BALATRO SIM v2 — Self-Test ===\n")

    local J = Sim.JOKER_DEFS
    local function jid(key) return J[key].id end
    local function cid(key) return Sim.CONSUMABLE_DEFS[key].id end

    -- Test: Pair + Joker
    local s = Sim.State.new({ seed="T1", jokers={{id=J["j_joker"].id,edition=0,eternal=false,uid=1}} })
    s.hand = { C(14,1), C(14,2), C(3,3), C(7,4), C(10,1), C(5,2), C(9,3), C(12,4) }
    local t,c,m,ht = Sim.Engine.calculate(s, {s.hand[1], s.hand[2]})
    test("Pair + Joker = 192", t == 192 and ht == 11)

    -- Test: Two Pair + Duo
    s = Sim.State.new({ seed="T2", jokers={{id=J["j_the_duo"].id,edition=0,eternal=false,uid=1}} })
    s.hand = { C(5,1), C(5,2), C(9,3), C(9,4), C(12,1), C(2,2), C(6,3), C(11,4) }
    t,c,m,ht = Sim.Engine.calculate(s, {s.hand[1],s.hand[2],s.hand[3],s.hand[4]})
    test("Two Pair + Duo = 192", t == 192 and ht == 10)

    -- Test: Blueprint copies Joker
    s = Sim.State.new({ seed="T3", jokers={
        {id=J["j_blueprint"].id,edition=0,eternal=false,uid=1},
        {id=J["j_joker"].id,edition=0,eternal=false,uid=2},
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
    test("Observation dim = 180", #obs == 180)

    -- Test: Env reset
    obs, info = Sim.Env.reset("TEST_SEED")
    test("Env.reset returns obs", #obs == 180 and info.ante == 1)

    -- Test: Burnt Joker
    local burnt_id = J["j_burnt_joker"].id
    local bs = Sim.State.new({ seed="BJ", jokers={{id=burnt_id,edition=0,eternal=false,uid=1}} })
    bs.hand = { C(5,1), C(5,2), C(3,3), C(7,4), C(10,1), C(2,2), C(6,3), C(12,4) }
    bs.discards_left = 4  -- first discard of round
    local def = Sim._JOKER_BY_ID[burnt_id]
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
        {id=J["j_joker"].id, edition=0, eternal=false, uid=1},
        {id=J["j_the_duo"].id, edition=0, eternal=false, uid=2},
    }})
    local id_before_1, id_before_2 = rs.jokers[1].id, rs.jokers[2].id
    local rv = (1 << 4) | 0 | (1 << 9)  -- src=0, tgt=1, mode=swap, area=joker
    Sim._do_reorder(rs, rv)
    test("REORDER swaps jokers", rs.jokers[1].id == id_before_2 and rs.jokers[2].id == id_before_1)

    -- Test: Hiker gives permanent chips
    local hiker_id = Sim.JOKER_DEFS["j_hiker"].id
    local hs = Sim.State.new({ seed="HIK", jokers={{id=hiker_id, edition=0, eternal=false, uid=1}} })
    hs.hand = { C(5,1), C(5,2), C(3,3), C(7,4), C(10,1), C(2,2), C(6,3), C(12,4) }
    local pb_before = hs.hand[1].perma_bonus
    Sim.Engine.calculate(hs, {hs.hand[1], hs.hand[2]})
    test("Hiker +5 perma_bonus", hs.hand[1].perma_bonus == pb_before + 5)

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
    local es = Sim.State.new({ seed="EMP", consumables={{id=cid"c_empress", uid=1}} })
    es.hand = { C(5,1), C(5,2), C(3,3), C(7,4), C(10,1), C(2,2), C(6,3), C(12,4) }
    es.selection = {1, 2}
    Sim._use_consumable(es, 1)
    test("Empress enhances to Mult", es.hand[1].enhancement == 2 and es.hand[2].enhancement == 2)

    -- Test: Venus levels Three of a Kind
    local vs = Sim.State.new({ seed="VEN", consumables={{id=cid"c_venus", uid=1}} })
    vs.hand = { C(2,1), C(5,2), C(9,3), C(11,4), C(14,1), C(3,2), C(7,3), C(13,4) }
    local vhl = vs.hand_levels[9]
    Sim._use_consumable(vs, 1)
    test("Venus levels Three of a Kind", vs.hand_levels[9] == vhl + 1)

    -- Test: Jupiter levels Flush
    local js = Sim.State.new({ seed="JUP", consumables={{id=cid"c_jupiter", uid=1}} })
    js.hand = { C(2,1), C(5,2), C(9,3), C(11,4), C(14,1), C(3,2), C(7,3), C(13,4) }
    local jhl = js.hand_levels[7]
    Sim._use_consumable(js, 1)
    test("Jupiter levels Flush", js.hand_levels[7] == jhl + 1)

    -- Test: The Magician enhances to Lucky
    local ms = Sim.State.new({ seed="MAG", consumables={{id=cid"c_magician", uid=1}} })
    ms.hand = { C(5,1), C(5,2), C(3,3), C(7,4), C(10,1), C(2,2), C(6,3), C(12,4) }
    ms.selection = {1, 2}
    Sim._use_consumable(ms, 1)
    test("Magician enhances to Lucky", ms.hand[1].enhancement == 8 and ms.hand[2].enhancement == 8)

    -- Test: The Hermit doubles money
    local hermit_s = Sim.State.new({ seed="HER", consumables={{id=cid"c_hermit", uid=1}} })
    hermit_s.dollars = 15
    hermit_s.hand = { C(5,1), C(5,2), C(3,3), C(7,4), C(10,1), C(2,2), C(6,3), C(12,4) }
    Sim._use_consumable(hermit_s, 1)
    test("Hermit doubles money", hermit_s.dollars == 30)

    -- Test: The Hermit caps at +$20
    local hermit2_s = Sim.State.new({ seed="HER2", consumables={{id=cid"c_hermit", uid=1}} })
    hermit2_s.dollars = 30
    hermit2_s.hand = { C(5,1), C(5,2), C(3,3), C(7,4), C(10,1), C(2,2), C(6,3), C(12,4) }
    Sim._use_consumable(hermit2_s, 1)
    test("Hermit caps at +$20", hermit2_s.dollars == 50)

    -- Test: Strength increases rank
    local str_s = Sim.State.new({ seed="STR", consumables={{id=cid"c_strength", uid=1}} })
    str_s.hand = { C(5,1), C(5,2), C(3,3), C(7,4), C(10,1), C(2,2), C(6,3), C(12,4) }
    str_s.selection = {1, 2}
    Sim._use_consumable(str_s, 1)
    test("Strength +1 rank", str_s.hand[1].rank == 6 and str_s.hand[2].rank == 6)

    -- Test: The Star changes suit to Diamonds
    local star_s = Sim.State.new({ seed="STAR", consumables={{id=cid"c_star", uid=1}} })
    star_s.hand = { C(5,1), C(5,2), C(3,3), C(7,4), C(10,1), C(2,2), C(6,3), C(12,4) }
    star_s.selection = {1}
    Sim._use_consumable(star_s, 1)
    test("Star changes to Diamonds", star_s.hand[1].suit == 4)

    -- Test: Temperance gives money for jokers
    local temp_s = Sim.State.new({ seed="TEMP", consumables={{id=cid"c_temperance", uid=1}},
        jokers={{id=jid"j_joker",edition=0,eternal=false,uid=1}} })
    temp_s.dollars = 4
    temp_s.hand = { C(5,1), C(5,2), C(3,3), C(7,4), C(10,1), C(2,2), C(6,3), C(12,4) }
    Sim._use_consumable(temp_s, 1)
    test("Temperance gives joker value", temp_s.dollars > 4)

    -- Test: Steel card held in hand = ×1.5 mult
    local steel_s = Sim.State.new({ seed="STEEL" })
    steel_s.hand = {
        C(10,1,5),  -- Steel 10 (held in hand)
        C(10,2),    -- Normal 10 (played)
        C(10,3),    -- Normal 10 (played)
        C(3,4), C(7,1), C(5,2), C(9,3), C(12,4)
    }
    local st1,_,sm1 = Sim.Engine.calculate(steel_s, {steel_s.hand[2], steel_s.hand[3]})
    -- Pair of 10s: base 10+10 chips, mult 2. Steel in hand: ×1.5
    test("Steel held = ×1.5 mult", sm1 == 3.0)  -- 2 * 1.5 = 3

    -- Test: Gold card held in hand = +$3
    local gold_s = Sim.State.new({ seed="GOLD" })
    gold_s.dollars = 4
    gold_s.hand = {
        C(10,1,7),  -- Gold 10 (held in hand)
        C(10,2),    -- Normal 10 (played)
        C(3,3), C(7,4), C(5,1), C(9,2), C(12,3), C(6,4)
    }
    Sim.Engine.calculate(gold_s, {gold_s.hand[2], gold_s.hand[3]})
    test("Gold held = +$3", gold_s.dollars == 7)

    -- Test: Gold seal = +$3 when scored
    local gs_s = Sim.State.new({ seed="GSEAL" })
    gs_s.dollars = 4
    local gold_seal_card = C(10,1,0,0,1)  -- Gold seal
    gs_s.hand = { gold_seal_card, C(10,2), C(3,3), C(7,4), C(5,1), C(9,2), C(12,3), C(6,4) }
    Sim.Engine.calculate(gs_s, {gs_s.hand[1], gs_s.hand[2]})
    test("Gold seal = +$3 on score", gs_s.dollars == 7)

    -- Test: Red seal re-triggers scoring
    local rs_s = Sim.State.new({ seed="RSEAL" })
    local red_seal_card = C(10,1,2,0,2)  -- Red seal + Mult enhancement (+4 mult)
    rs_s.hand = { red_seal_card, C(10,2), C(3,3), C(7,4), C(5,1), C(9,2), C(12,3), C(6,4) }
    local _,_,rsm = Sim.Engine.calculate(rs_s, {rs_s.hand[1], rs_s.hand[2]})
    -- Pair of 10s: base mult 2. Mult card +4, re-trigger +4 = mult 10
    test("Red seal re-triggers Mult", rsm == 10)

    -- Test: Wild card counts as any suit for flush
    local wild_s = Sim.State.new({ seed="WILD" })
    wild_s.hand = {
        C(2,1,3),   -- Wild 2 of Spades
        C(5,2),     -- 5 of Hearts
        C(9,2),     -- 9 of Hearts
        C(11,2),    -- J of Hearts
        C(14,2),    -- A of Hearts
        C(3,3), C(8,4), C(13,1)
    }
    local _,_,_,wht = Sim.Engine.calculate(wild_s, {wild_s.hand[1],wild_s.hand[2],wild_s.hand[3],wild_s.hand[4],wild_s.hand[5]})
    test("Wild card makes flush", wht == 7)

    -- Test: Lucky card with seeded RNG
    local lucky_s = Sim.State.new({ seed="LUCKY" })
    local lucky_card = C(10,1,8)  -- Lucky enhancement
    lucky_s.hand = { lucky_card, C(10,2), C(3,3), C(7,4), C(5,1), C(9,2), C(12,3), C(6,4) }
    local l_money_before = lucky_s.dollars
    Sim.Engine.calculate(lucky_s, {lucky_s.hand[1], lucky_s.hand[2]})
    -- Lucky is random, just verify no crash
    test("Lucky card scoring works", lucky_s.dollars >= l_money_before)

    -- Test: Supernova (+mult = times played this hand type)
    local sn_s = Sim.State.new({ seed="SN", jokers={{id=jid"j_supernova",edition=0,eternal=false,uid=1}} })
    sn_s.hand = { C(10,1), C(10,2), C(3,3), C(7,4), C(5,1), C(9,2), C(12,3), C(6,4) }
    sn_s.hand_type_counts[11] = 3  -- Pair played 3 times before
    local _,_,snm = Sim.Engine.calculate(sn_s, {sn_s.hand[1], sn_s.hand[2]})
    -- Pair base mult 2 + Supernova +3 = 5
    test("Supernova adds played count", snm == 5)

    -- Test: Ride the Bus stacks
    local rtb_s = Sim.State.new({ seed="RTB", jokers={{id=jid"j_ride_the_bus",edition=0,eternal=false,uid=1}} })
    rtb_s.hand = { C(2,1), C(2,2), C(3,3), C(7,4), C(5,1), C(9,2), C(12,3), C(6,4) }
    rtb_s.ride_the_bus = 3
    local _,_,rtbm = Sim.Engine.calculate(rtb_s, {rtb_s.hand[1], rtb_s.hand[2]})
    -- Pair base mult 2 + Ride the Bus +3 = 5
    test("Ride the Bus adds stacks", rtbm == 5)

    -- Test: Blackboard (all Spade/Club in hand)
    local bb_s = Sim.State.new({ seed="BB", jokers={{id=jid"j_blackboard",edition=0,eternal=false,uid=1}} })
    bb_s.hand = { C(2,1), C(2,3), C(3,1), C(7,3), C(5,1), C(9,3), C(12,1), C(6,3) }
    local _,_,bbm = Sim.Engine.calculate(bb_s, {bb_s.hand[1], bb_s.hand[2]})
    -- Pair base mult 2 * Blackboard ×3 = 6
    test("Blackboard ×3 when all dark", bbm == 6)

    -- Test: Blackboard fails with Hearts
    local bb2_s = Sim.State.new({ seed="BB2", jokers={{id=jid"j_blackboard",edition=0,eternal=false,uid=1}} })
    bb2_s.hand = { C(2,1), C(2,2), C(3,3), C(7,4), C(5,1), C(9,2), C(12,3), C(6,4) }
    local _,_,bb2m = Sim.Engine.calculate(bb2_s, {bb2_s.hand[1], bb2_s.hand[2]})
    test("Blackboard fails with Hearts", bb2m == 2)

    -- Test: Ramen starts at ×2
    local rm_s = Sim.State.new({ seed="RM", jokers={{id=jid"j_ramen",edition=0,eternal=false,uid=1}} })
    rm_s.hand = { C(2,1), C(2,2), C(3,3), C(7,4), C(5,1), C(9,2), C(12,3), C(6,4) }
    rm_s.cards_drawn = 0
    local _,_,rmm = Sim.Engine.calculate(rm_s, {rm_s.hand[1], rm_s.hand[2]})
    test("Ramen ×2 at 0 draws", rmm == 4)  -- 2 * 2 = 4

    -- Test: Acrobat ×3 on last hand
    local ac_s = Sim.State.new({ seed="AC", jokers={{id=jid"j_acrobat",edition=0,eternal=false,uid=1}} })
    ac_s.hand = { C(2,1), C(2,2), C(3,3), C(7,4), C(5,1), C(9,2), C(12,3), C(6,4) }
    ac_s.hands_left = 0
    local _,_,acm = Sim.Engine.calculate(ac_s, {ac_s.hand[1], ac_s.hand[2]})
    test("Acrobat ×3 on last hand", acm == 6)  -- 2 * 3 = 6

    -- Test: Sock and Buskin re-triggers face card effects
    local sb_s = Sim.State.new({ seed="SB", jokers={
        {id=jid"j_sock_and_buskin",edition=0,eternal=false,uid=1},
        {id=jid"j_scary_face",edition=0,eternal=false,uid=2},
    }})
    sb_s.hand = { C(11,1), C(11,2), C(3,3), C(7,4), C(5,1), C(9,2), C(12,3), C(6,4) }
    local sb_total = Sim.Engine.calculate(sb_s, {sb_s.hand[1], sb_s.hand[2]})
    -- Pair of Jacks: base 10 + (10+10) = 30 chips, mult 2. Scary Face +30+30, re-trigger +30+30 = 150 chips
    -- Total = 150 * 2 = 300
    test("Sock and Buskin re-triggers face", sb_total == 300)

    -- Test: Wild card triggers suit-based joker (Greedy = Diamonds)
    local wild_joker_s = Sim.State.new({ seed="WJ", jokers={{id=jid"j_greedy",edition=0,eternal=false,uid=1}} })
    wild_joker_s.hand = { C(2,1,3), C(2,2), C(3,3), C(7,4), C(5,1), C(9,2), C(12,3), C(6,4) }
    local _,_,wj_m = Sim.Engine.calculate(wild_joker_s, {wild_joker_s.hand[1], wild_joker_s.hand[2]})
    -- Pair base mult 2 + Greedy +3 = 5 (Wild card counts as Diamond)
    test("Wild triggers Greedy Joker", wj_m == 5)

    -- Test: Glass card scoring works
    local glass_s = Sim.State.new({ seed="GLASS" })
    glass_s.hand = { C(10,1,4), C(10,2), C(3,3), C(7,4), C(5,1), C(9,2), C(12,3), C(6,4) }
    local g_total = Sim.Engine.calculate(glass_s, {glass_s.hand[1], glass_s.hand[2]})
    -- Pair of 10s: base 10 + 10 + 10 = 30 chips, mult 2 × 2 (Glass) = 4. Total = 120
    test("Glass card scoring works", g_total == 120)

    -- Test: Red seal on held card re-triggers Steel
    local red_held_s = Sim.State.new({ seed="RH2" })
    red_held_s.hand = {
        C(10,1,5,0,2),  -- Steel + Red seal (held in hand)
        C(10,2), C(10,3),  -- Pair of 10s (played)
        C(7,4), C(5,1), C(9,2), C(12,3), C(6,4)
    }
    local _,_,rh_m = Sim.Engine.calculate(red_held_s, {red_held_s.hand[2], red_held_s.hand[3]})
    -- Pair mult 2. Steel ×1.5, re-trigger ×1.5 = 2 × 1.5 × 1.5 = 4.5
    test("Red seal re-triggers Steel held", rh_m == 4.5)

    -- Test: Talisman adds Gold seal
    local tal_s = Sim.State.new({ seed="TAL", consumables={{id=cid"c_talisman", uid=1}} })
    tal_s.hand = { C(5,1), C(5,2), C(3,3), C(7,4), C(10,1), C(2,2), C(6,3), C(12,4) }
    tal_s.selection = {1}
    Sim._use_consumable(tal_s, 1)
    test("Talisman adds Gold seal", tal_s.hand[1].seal == 1)

    -- Test: Deja Vu adds Red seal
    local dv_s = Sim.State.new({ seed="DV", consumables={{id=cid"c_deja_vu", uid=1}} })
    dv_s.hand = { C(5,1), C(5,2), C(3,3), C(7,4), C(10,1), C(2,2), C(6,3), C(12,4) }
    dv_s.selection = {1}
    Sim._use_consumable(dv_s, 1)
    test("Deja Vu adds Red seal", dv_s.hand[1].seal == 2)

    -- Test: Trance adds Blue seal
    local tr_s = Sim.State.new({ seed="TR", consumables={{id=cid"c_trance", uid=1}} })
    tr_s.hand = { C(5,1), C(5,2), C(3,3), C(7,4), C(10,1), C(2,2), C(6,3), C(12,4) }
    tr_s.selection = {1}
    Sim._use_consumable(tr_s, 1)
    test("Trance adds Blue seal", tr_s.hand[1].seal == 3)

    -- Test: Immolate destroys cards and gives $20
    local imm_s = Sim.State.new({ seed="IMM", consumables={{id=cid"c_immolate", uid=1}} })
    imm_s.hand = { C(5,1), C(5,2), C(3,3), C(7,4), C(10,1), C(2,2), C(6,3), C(12,4) }
    imm_s.dollars = 0
    Sim._use_consumable(imm_s, 1)
    test("Immolate gives $20", imm_s.dollars == 20)
    test("Immolate destroys cards", #imm_s.hand == 3)  -- 8 - 5 = 3

    -- Test: Cryptid copies card
    local cry_s = Sim.State.new({ seed="CRY", consumables={{id=cid"c_cryptid", uid=1}} })
    cry_s.hand = { C(14,1), C(5,2), C(3,3), C(7,4), C(10,1), C(2,2) }
    cry_s.selection = {1}
    local hand_before = #cry_s.hand
    Sim._use_consumable(cry_s, 1)
    test("Cryptid creates 2 copies", #cry_s.hand == hand_before + 2)
    test("Cryptid copies are Aces", cry_s.hand[#cry_s.hand].rank == 14)

    -- Test: Sigil changes all suits
    local sig_s = Sim.State.new({ seed="SIG", consumables={{id=cid"c_sigil", uid=1}} })
    sig_s.hand = { C(2,1), C(5,2), C(9,3), C(11,4), C(14,1), C(3,2), C(7,3), C(13,4) }
    Sim._use_consumable(sig_s, 1)
    local all_same = true
    local s = sig_s.hand[1].suit
    for _, c in ipairs(sig_s.hand) do
        if c.enhancement ~= 6 and c.suit ~= s then all_same = false end
    end
    test("Sigil changes all suits", all_same)

    -- === Card Factory ===
    local cf_state = Sim.State.new({ seed="CF" })
    cf_state._uid_n = 0
    local cf_jk = Sim.CardFactory.create("Joker", cf_state, cf_state.rng, 1)
    test("CardFactory creates common joker", cf_jk ~= nil and cf_jk.id > 0)
    local cf_tarot = Sim.CardFactory.create("Tarot", cf_state, cf_state.rng)
    test("CardFactory creates tarot", cf_tarot ~= nil and cf_tarot.id > 0)
    local cf_planet = Sim.CardFactory.create("Planet", cf_state, cf_state.rng)
    test("CardFactory creates planet", cf_planet ~= nil and cf_planet.id > 0)
    local cf_card = Sim.CardFactory.create("Playing Card", cf_state, cf_state.rng)
    test("CardFactory creates playing card", cf_card ~= nil and cf_card.rank >= 2)
    test("CardFactory rarity pools", #Sim.JOKER_RARITY_POOLS[1] > 0 and #Sim.JOKER_RARITY_POOLS[4] == 5)

    -- === Tags ===
    local tag_state = Sim.State.new({ seed="TAG", dollars=0 })
    tag_state.tags = {}
    tag_state.skips = 0
    tag_state.total_hands_played = 10
    Sim.Tag.add(tag_state, "tag_handy")
    test("Handy Tag gives $10 (10 hands)", tag_state.dollars == 10)
    Sim.Tag.add(tag_state, "tag_top_up")
    test("Top-up Tag creates 2 jokers", #tag_state.jokers == 2)

    -- === Vouchers ===
    local v_state = Sim.State.new({ seed="VCH" })
    v_state.dollars = 50
    v_state.vouchers = {}
    Sim.Voucher.redeem(v_state, "v_grabber")
    test("Grabber gives +1 hand", v_state.hands == 5)
    Sim.Voucher.redeem(v_state, "v_overstock_norm")
    test("Overstock gives +1 shop slot", v_state.shop_joker_max == 3)
    Sim.Voucher.redeem(v_state, "v_seed_money")
    test("Seed Money raises interest cap", v_state._interest_cap == 50)
    test("Voucher definitions exist", Sim.Voucher.DEFS["v_antimatter"].tier == 2)

    -- === Boss Blinds ===
    test("28 boss blinds defined", #Sim.BOSS_BLINDS == 28)
    local b_state = Sim.State.new({ seed="BOS" })
    local boss1 = Sim.Blind.pick_boss(b_state, 1)
    test("Ante 1 gets regular boss", not boss1.showdown)
    local b_state8 = Sim.State.new({ seed="BOS8" })
    local boss8 = Sim.Blind.pick_boss(b_state8, 8)
    test("Ante 8 gets showdown boss", boss8.showdown == true)
    test("Violet Vessel has 3x mult", Sim.BOSS_BLINDS[26].chip_mult == 3.0)

    print(string.format("\n  %d/%d tests passed\n", passed, total))

    -- ================================================================
    -- RANDOM AGENT: Play one full ante with Jokers + Consumables + Packs
    -- ================================================================
    print("=== Random Agent — Full Ante ===\n")

    local rng = Sim.RNG.new("AGENT42")
    local state = Sim.State.new({
        rng = rng, seed = "AGENT42",
        jokers = {
            {id=jid"j_joker", edition=0, eternal=false, uid=1},
            {id=jid"j_the_duo", edition=0, eternal=false, uid=2},
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


