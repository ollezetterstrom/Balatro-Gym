-- src/04_jokers.lua — Joker definitions (all)

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

Sim._reg_joker("j_joker", "Joker", 1, 2, function(ctx, st, jk)
    if ctx.joker_main then return { mult_mod = 4 } end
end)

local E = Sim.ENUMS

local function _is_suit(card, target_suit)
    return card.suit == target_suit or card.enhancement == E.ENHANCEMENT.WILD
end

Sim._reg_joker("j_greedy_joker", "Greedy Joker", 1, 5, function(ctx, st, jk)
    if ctx.individual and ctx.other_card and ctx.cardarea == "play" then
        if _is_suit(ctx.other_card, E.SUIT.DIAMONDS) then return { mult = 3 } end
    end
end)

Sim._reg_joker("j_lusty_joker", "Lusty Joker", 1, 5, function(ctx, st, jk)
    if ctx.individual and ctx.other_card and ctx.cardarea == "play" then
        if _is_suit(ctx.other_card, E.SUIT.HEARTS) then return { mult = 3 } end
    end
end)

Sim._reg_joker("j_wrathful_joker", "Wrathful Joker", 1, 5, function(ctx, st, jk)
    if ctx.individual and ctx.other_card and ctx.cardarea == "play" then
        if _is_suit(ctx.other_card, E.SUIT.SPADES) then return { mult = 3 } end
    end
end)

Sim._reg_joker("j_gluttenous_joker", "Gluttonous Joker", 1, 5, function(ctx, st, jk)
    if ctx.individual and ctx.other_card and ctx.cardarea == "play" then
        if _is_suit(ctx.other_card, E.SUIT.CLUBS) then return { mult = 3 } end
    end
end)

Sim._reg_joker("j_duo", "The Duo", 3, 8, function(ctx, st, jk)
    if ctx.joker_main and ctx.all_hands and ctx.all_hands[11] then
        return { Xmult_mod = 2 }
    end
end)

Sim._reg_joker("j_trio", "The Trio", 3, 8, function(ctx, st, jk)
    if ctx.joker_main and ctx.all_hands and ctx.all_hands[9] then
        return { Xmult_mod = 3 }
    end
end)

Sim._reg_joker("j_blueprint", "Blueprint", 3, 10, function(ctx, st, jk)
    -- Blueprint copies the FIRST joker in the list (real game behavior)
    if ctx.blueprint then return end
    if not ctx.my_joker_index then return end
    local first = st.jokers[1]
    if not first or first == jk then return end
    local def = Sim._JOKER_BY_ID[first.id]
    if not def or not def.apply then return end
    local cc = {}
    for k,v in pairs(ctx) do cc[k] = v end
    cc.blueprint = true
    return def.apply(cc, st, first)
end)

Sim._reg_joker("j_brainstorm", "Brainstorm", 4, 20, function(ctx, st, jk)
    if ctx.blueprint then return end
    if not ctx.my_joker_index then return end
    local first = st.jokers[1]
    if not first or first == jk then return end
    local def = Sim._JOKER_BY_ID[first.id]
    if not def or not def.apply then return end
    local cc = {}
    for k,v in pairs(ctx) do cc[k] = v end
    cc.blueprint = true
    return def.apply(cc, st, first)
end)

Sim._reg_joker("j_burnt", "Burnt Joker", 3, 8, function(ctx, st, jk)
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

Sim._reg_joker("j_even_steven", "Even Steven", 1, 4, function(ctx, st, jk)
    if ctx.individual and ctx.other_card then
        local r = ctx.other_card.rank
        if r == 2 or r == 4 or r == 6 or r == 8 or r == 10 then
            return { mult = 4 }
        end
    end
end)

Sim._reg_joker("j_odd_todd", "Odd Todd", 1, 4, function(ctx, st, jk)
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

Sim._reg_joker("j_delayed_grat", "Delayed Gratification", 1, 4, function(ctx, st, jk)
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

Sim._reg_joker("j_ride_the_bus", "Ride the Bus", 1, 6, function(ctx, st, jk)
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

Sim._reg_joker("j_family", "The Family", 3, 8, function(ctx, st, jk)
    if ctx.joker_main and ctx.all_hands and ctx.all_hands[E.HAND_TYPE.FOUR_OF_A_KIND] then return { Xmult_mod = 4 } end
end)
Sim._reg_joker("j_order", "The Order", 3, 8, function(ctx, st, jk)
    if ctx.joker_main and ctx.all_hands and ctx.all_hands[E.HAND_TYPE.STRAIGHT] then return { Xmult_mod = 3 } end
end)
Sim._reg_joker("j_tribe", "The Tribe", 3, 8, function(ctx, st, jk)
    if ctx.joker_main and ctx.all_hands and ctx.all_hands[E.HAND_TYPE.FLUSH] then return { Xmult_mod = 2 } end
end)

-- === Simple scoring jokers ===

Sim._reg_joker("j_half", "Half Joker", 1, 5, function(ctx, st, jk)
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
    -- Passive: allows debt down to -$20 (handled in interest/money calc)
end)
Sim._reg_joker("j_chaos", "Chaos the Clown", 1, 4, function(ctx, st, jk)
    if ctx.shop_start then
        st._free_rerolls = (st._free_rerolls or 0) + 1
    end
end)
Sim._reg_joker("j_egg", "Egg", 1, 4, function(ctx, st, jk)
    if ctx.round_end then jk._egg_bonus = (jk._egg_bonus or 0) + 3 end
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
    if ctx.setting_blind then
        local rank = Sim.RNG.int(st.rng, 2, 14)
        local suit = Sim.RNG.int(st.rng, 1, 4)
        local uid = (st._uid_n or 0) + 1; st._uid_n = uid
        local stone = Sim.Card.new(rank, suit, E.ENHANCEMENT.STONE, 0, 0, uid)
        st.deck[#st.deck + 1] = stone
        st.deck_count = (st.deck_count or 52) + 1
    end
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
Sim._reg_joker("j_ceremonial", "Ceremonial Dagger", 2, 6, function(ctx, st, jk)
    if ctx.setting_blind and #st.jokers > 1 then
        local my_pos = nil
        for i = 1, #st.jokers do
            if st.jokers[i] == jk then my_pos = i; break end
        end
        if my_pos and st.jokers[my_pos + 1] then
            local sliced = st.jokers[my_pos + 1]
            local def = Sim._JOKER_BY_ID[sliced.id]
            if def then
                jk._ceremonial_mult = (jk._ceremonial_mult or 0) + def.cost * 2
            end
            table.remove(st.jokers, my_pos + 1)
        end
    end
    if ctx.joker_main then return { mult_mod = jk._ceremonial_mult or 0 } end
end)
Sim._reg_joker("j_sixth_sense", "Sixth Sense", 2, 6, function(ctx, st, jk)
    if ctx.cards_destroyed and ctx.first_card_is_6 then
        return { create_spectral = true }
    end
end)
Sim._reg_joker("j_hiker", "Hiker", 2, 5, function(ctx, st, jk)
    if ctx.after_play then
        for _, c in ipairs(ctx.scoring or {}) do
            c.perma_bonus = (c.perma_bonus or 0) + 5
        end
    end
end)
Sim._reg_joker("j_madness", "Madness", 2, 7, function(ctx, st, jk)
    if ctx.setting_blind and not st.boss_name then
        jk._madness_x = (jk._madness_x or 1) + 0.5
        if #st.jokers > 1 then
            local others = {}
            for i, j in ipairs(st.jokers) do
                if j ~= jk then others[#others + 1] = i end
            end
            if #others > 0 then
                local idx = others[Sim.RNG.int(st.rng, 1, #others)]
                table.remove(st.jokers, idx)
            end
        end
    end
    if ctx.joker_main then return { Xmult_mod = jk._madness_x or 1 } end
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
Sim._reg_joker("j_vagabond", "Vagabond", 3, 8, function(ctx, st, jk)
    if ctx.joker_main and st.dollars < 4 then
        return { create_tarot = true }
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
    if ctx.on_discard and (st._discards_used or 0) == 0 and ctx.cards_discarded == 1 then
        return { dollars = 3 }
    end
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
    if ctx.after_play and ctx.scoring then
        for _, c in ipairs(ctx.scoring) do
            if c.rank >= E.RANK.JACK and c.rank <= E.RANK.KING and c.enhancement == 0 then
                c.enhancement = E.ENHANCEMENT.GOLD
            end
        end
    end
end)
Sim._reg_joker("j_luchador", "Luchador", 2, 5, function(ctx, st, jk)
    if ctx.selling_self and st.boss_name then
        st._boss_disabled = true
    end
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
    if ctx.first_hand_drawn then
        st._dna_active = true
        st._dna_first_hand = true
    end
    if ctx.after_play and st._dna_first_hand and ctx.all_played and #ctx.all_played == 1 then
        local src = ctx.all_played[1]
        local uid = (st._uid_n or 0) + 1; st._uid_n = uid
        local copy = Sim.Card.new(src.rank, src.suit, src.enhancement, src.edition, src.seal, uid)
        copy.perma_bonus = src.perma_bonus or 0
        st.hand[#st.hand + 1] = copy
        st._dna_first_hand = false
    end
end)
Sim._reg_joker("j_splash", "Splash", 1, 3, function(ctx, st, jk)
    -- All played cards count toward scoring (handled in evaluator)
end)
-- j_sixth_sense registered in 05_consumables.lua (needs CONS_POOL)
Sim._reg_joker("j_seance", "Seance", 2, 6, function(ctx, st, jk)
    if ctx.after_play and ctx.all_hands and ctx.all_hands[E.HAND_TYPE.STRAIGHT_FLUSH] then
        return { create_spectral = true }
    end
end)
Sim._reg_joker("j_riff_raff", "Riff-raff", 1, 6, function(ctx, st, jk)
    if ctx.setting_blind then
        local count = math.min(2, st.joker_slots - #st.jokers)
        for i = 1, count do
            local pool = Sim.CardFactory.get_joker_pool(st, 1)
            if #pool > 0 then
                local jid = Sim.RNG.pick(st.rng, pool)
                local def = Sim._JOKER_BY_ID[jid]
                if def and #st.jokers < st.joker_slots then
                    Sim.State.add_joker(st, def)
                end
            end
        end
    end
end)
Sim._reg_joker("j_diet_cola", "Diet Cola", 2, 6, function(ctx, st, jk)
    if ctx.selling_self then
        Sim.Tag.add(st, "tag_double")
    end
end)
Sim._reg_joker("j_gift", "Gift Card", 2, 6, function(ctx, st, jk)
    if ctx.round_end then
        st._gift_bonus = (st._gift_bonus or 0) + 1
    end
end)
Sim._reg_joker("j_turtle_bean", "Turtle Bean", 2, 6, function(ctx, st, jk)
    if ctx.setting_blind then
        st.hand_limit = st.hand_limit + 5
        jk._turtle_h = 5
    end
    if ctx.round_end then
        jk._turtle_h = (jk._turtle_h or 5) - 1
        if jk._turtle_h <= 0 then
            return { destroy_self = true }
        end
        st.hand_limit = math.max(1, st.hand_limit - 1)
    end
end)
Sim._reg_joker("j_erosion", "Erosion", 2, 6, function(ctx, st, jk)
    if ctx.joker_main then
        local diff = 52 - (#st.deck + #st.hand + #st.discard)
        if diff > 0 then return { mult_mod = 4 * diff } end
    end
end)
Sim._reg_joker("j_hallucination", "Hallucination", 1, 4, function(ctx, st, jk)
    if ctx.open_booster and #st.consumables < st.consumable_slots then
        if Sim.RNG.next(st.rng) < 0.5 then
            return { create_tarot = true }
        end
    end
end)

-- === Rare jokers ===

Sim._reg_joker("j_wee", "Wee Joker", 3, 8, function(ctx, st, jk)
    if ctx.after_play then jk._wee_chips = (jk._wee_chips or 0) + 8 end
    if ctx.joker_main then return { chip_mod = jk._wee_chips or 0 } end
end)
Sim._reg_joker("j_merry_andy", "Merry Andy", 2, 7, function(ctx, st, jk)
    if ctx.setting_blind then
        st.discards_left = st.discards_left + 3
        st.hand_limit = math.max(1, st.hand_limit - 1)
    end
end)
Sim._reg_joker("j_oops", "Oops! All 6s", 2, 4, function(ctx, st, jk)
    -- Double all listed probabilities (passive, handled in probability checks)
    -- Any code checking Sim.RNG.next(st.rng) < odds should use 2*odds when this joker is present
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
    if ctx.setting_blind then
        st.hand_limit = math.max(1, st.hand_limit - 2)
    end
    if ctx.joker_main then return { chip_mod = 250 } end
end)
Sim._reg_joker("j_invisible", "Invisible Joker", 3, 8, function(ctx, st, jk)
    if ctx.round_end then
        jk._invis_rounds = (jk._invis_rounds or 0) + 1
    end
    if ctx.selling_self and jk._invis_rounds and jk._invis_rounds >= 2 then
        local candidates = {}
        for _, j in ipairs(st.jokers) do
            if j ~= jk and #st.jokers < st.joker_slots then
                candidates[#candidates+1] = j
            end
        end
        if #candidates > 0 then
            local target = candidates[Sim.RNG.int(st.rng, 1, #candidates)]
            local def = Sim._JOKER_BY_ID[target.id]
            if def and #st.jokers < st.joker_slots then
                Sim.State.add_joker(st, def)
            end
        end
    end
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
    if ctx.round_end then
        local count = 0
        for k, _ in pairs(st._planets_used or {}) do count = count + 1 end
        return { dollars = count }
    end
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
    if ctx.setting_blind and #st.consumables < st.consumable_slots then
        return { create_tarot = true }
    end
end)
Sim._reg_joker("j_astronomer", "Astronomer", 2, 8, function(ctx, st, jk)
    -- Passive: planet cards cost $0 in shop (handled in shop pricing)
    st._planets_free = true
end)
Sim._reg_joker("j_bootstraps", "Bootstraps", 2, 7, function(ctx, st, jk)
    if ctx.joker_main then return { mult_mod = 2 * math.floor(math.max(st.dollars, 0) / 5) } end
end)
Sim._reg_joker("j_ring_master", "Showman", 2, 5, function(ctx, st, jk)
    -- Passive: showman flag allows duplicate cards in shop
    st._showman = true
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
    if ctx.joker_main then
        local skips = st._blinds_skipped or 0
        if skips > 0 then return { Xmult_mod = 1 + 0.25 * skips } end
    end
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
    if ctx.cards_destroyed then
        for _, c in ipairs(ctx.destroyed or {}) do
            if c.enhancement == E.ENHANCEMENT.GLASS then
                jk._glass_x = (jk._glass_x or 1) + 0.75
            end
        end
    end
    if ctx.joker_main then return { Xmult_mod = jk._glass_x or 1 } end
end)
Sim._reg_joker("j_mr_bones", "Mr. Bones", 2, 5, function(ctx, st, jk)
    -- Prevent death if scored chips >= 25% of blind (checked in env step)
    if ctx.game_over and st.chips >= st.blind_chips * 0.25 then
        return { save_from_death = true }
    end
end)
Sim._reg_joker("j_superposition", "Superposition", 1, 4, function(ctx, st, jk)
    if ctx.after_play and ctx.all_hands and ctx.all_hands[E.HAND_TYPE.STRAIGHT] then
        for _, c in ipairs(ctx.scoring or {}) do
            if c.rank == E.RANK.ACE then
                return { create_tarot = true }
            end
        end
    end
end)
Sim._reg_joker("j_todo_list", "To Do List", 1, 4, function(ctx, st, jk)
    if ctx.after_play and ctx.hand_name then
        if ctx.hand_name == (jk._todo_hand or "High Card") then
            return { dollars = 4 }
        end
    end
    if ctx.round_end then
        local hands = {"High Card","Pair","Two Pair","Three of a Kind","Straight",
            "Flush","Full House","Four of a Kind","Straight Flush","Five of a Kind",
            "Flush House","Flush Five"}
        jk._todo_hand = hands[Sim.RNG.int(st.rng, 1, #hands)]
    end
end)
Sim._reg_joker("j_certificate", "Certificate", 2, 6, function(ctx, st, jk)
    if ctx.first_hand_drawn then
        local seals = {E.SEAL.RED, E.SEAL.BLUE, E.SEAL.GOLD, E.SEAL.PURPLE}
        local seal = seals[Sim.RNG.int(st.rng, 1, #seals)]
        local rank = Sim.RNG.int(st.rng, 2, 14)
        local suit = Sim.RNG.int(st.rng, 1, 4)
        local uid = (st._uid_n or 0) + 1; st._uid_n = uid
        local card = Sim.Card.new(rank, suit, 0, 0, seal, uid)
        st.hand[#st.hand + 1] = card
    end
end)
Sim._reg_joker("j_troubadour", "Troubadour", 2, 6, function(ctx, st, jk)
    if ctx.setting_blind then
        st.hand_limit = st.hand_limit + 2
        st.hands_left = math.max(1, st.hands_left - 1)
    end
end)

-- === Legendary jokers (rarity 4) ===

Sim._reg_joker("j_caino", "Caino", 4, 20, function(ctx, st, jk)
    if ctx.cards_destroyed then
        for _, c in ipairs(ctx.destroyed or {}) do
            if c.rank >= E.RANK.JACK and c.rank <= E.RANK.KING then
                jk._caino_x = (jk._caino_x or 1) + 1
            end
        end
    end
    if ctx.joker_main then return { Xmult_mod = jk._caino_x or 1 } end
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
    if ctx.setting_blind and st.boss_name then
        st._boss_disabled = true
    end
end)
Sim._reg_joker("j_perkeo", "Perkeo", 4, 20, function(ctx, st, jk)
    if ctx.ending_shop and #st.consumables > 0 then
        local src = st.consumables[Sim.RNG.int(st.rng, 1, #st.consumables)]
        if src then
            return { create_negative_copy = src.id }
        end
    end
end)
