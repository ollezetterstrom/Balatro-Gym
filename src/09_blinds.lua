-- src/09_blinds.lua — Blind system, boss blinds

Sim.Blind = {}
local BLIND_DATA = {
    {name="Small", mult=1.0, reward=3},
    {name="Big",   mult=1.5, reward=4},
    {name="Boss",  mult=2.0, reward=5},
}

local SUIT = Sim.ENUMS.SUIT

Sim.BOSS_BLINDS = {
    -- Regular bosses (25)
    { name = "The Club",       chip_mult = 1.0, min_ante = 1, setup = function(st) st._boss_debuff_suit = SUIT.CLUBS end },
    { name = "The Goad",       chip_mult = 1.0, min_ante = 1, setup = function(st) st._boss_debuff_suit = SUIT.SPADES end },
    { name = "The Head",       chip_mult = 1.0, min_ante = 1, setup = function(st) st._boss_debuff_suit = SUIT.HEARTS end },
    { name = "The Window",     chip_mult = 1.0, min_ante = 1, setup = function(st) st._boss_debuff_suit = SUIT.DIAMONDS end },
    { name = "The Psychic",    chip_mult = 1.0, min_ante = 1, setup = function(st) st._boss_must_play_5 = true end },
    { name = "The Hook",       chip_mult = 1.0, min_ante = 1, setup = function(st) end },
    { name = "The Manacle",    chip_mult = 1.0, min_ante = 1, setup = function(st) st.hand_limit = st.hand_limit - 1 end },
    { name = "The Water",      chip_mult = 1.0, min_ante = 2, setup = function(st) st.discards_left = 0 end },
    { name = "The Wall",       chip_mult = 2.0, min_ante = 2, setup = function(st) end },
    { name = "The House",      chip_mult = 1.0, min_ante = 2, setup = function(st) st._boss_flip_first = true end },
    { name = "The Arm",        chip_mult = 1.0, min_ante = 2, setup = function(st) end },
    { name = "The Wheel",      chip_mult = 1.0, min_ante = 2, setup = function(st) st._boss_flip_chance = 1/7 end },
    { name = "The Fish",       chip_mult = 1.0, min_ante = 2, setup = function(st) st._boss_flip_after_play = true end },
    { name = "The Mouth",      chip_mult = 1.0, min_ante = 2, setup = function(st) st._boss_one_hand_type = true end },
    { name = "The Mark",       chip_mult = 1.0, min_ante = 2, setup = function(st) st._boss_flip_faces = true end },
    { name = "The Tooth",      chip_mult = 1.0, min_ante = 3, setup = function(st) end },
    { name = "The Eye",        chip_mult = 1.0, min_ante = 3, setup = function(st) st._boss_no_repeat = true end },
    { name = "The Plant",      chip_mult = 1.0, min_ante = 4, setup = function(st) st._boss_debuff_faces = true end },
    { name = "The Needle",     chip_mult = 0.5, min_ante = 2, setup = function(st) st.hands_left = 1 end },
    { name = "The Pillar",     chip_mult = 1.0, min_ante = 1, setup = function(st) st._boss_debuff_played = true end },
    { name = "The Serpent",    chip_mult = 1.0, min_ante = 5, setup = function(st) st._boss_serpent = true end },
    { name = "The Ox",         chip_mult = 1.0, min_ante = 6, setup = function(st) st._boss_ox = true end },
    { name = "The Flint",      chip_mult = 1.0, min_ante = 2, setup = function(st) st._boss_halve = true end },
    -- Showdown bosses (ante 8 only, 5)
    { name = "Cerulean Bell",  chip_mult = 1.0, min_ante = 8, showdown = true, setup = function(st) st._boss_force_select = true end },
    { name = "Verdant Leaf",   chip_mult = 1.0, min_ante = 8, showdown = true, setup = function(st) st._boss_debuff_all = true end },
    { name = "Violet Vessel",  chip_mult = 3.0, min_ante = 8, showdown = true, setup = function(st) end },
    { name = "Amber Acorn",    chip_mult = 1.0, min_ante = 8, showdown = true, setup = function(st) st._boss_shuffle_jokers = true end },
    { name = "Crimson Heart",  chip_mult = 1.0, min_ante = 8, showdown = true, setup = function(st) st._boss_debuff_random_joker = true end },
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
    -- Suit debuffs (Club, Goad/Spade, Head/Heart, Window/Diamond)
    if state._boss_debuff_suit and card.suit == state._boss_debuff_suit then
        return true
    end
    -- Face card debuff (The Plant)
    if state._boss_debuff_faces and card.rank >= 11 and card.rank <= 13 then
        return true
    end
    -- Verdent Leaf: debuff ALL cards until a joker is sold
    if state._boss_debuff_all then
        return true
    end
    -- Cards played this ante debuff (The Pillar)
    if state._boss_debuff_played and card._played_this_ante then
        return true
    end
    return false
end

function Sim.Blind.on_play(state, played_cards)
    -- Boss: The Arm — decrease played hand level by 1
    if state.boss_name == "The Arm" then
        local ht = Sim.Eval.get_hand(played_cards, state)
        if state.hand_levels[ht] and state.hand_levels[ht] > 1 then
            state.hand_levels[ht] = state.hand_levels[ht] - 1
        end
    end
    -- Boss: The Tooth — -$1 per card played
    if state.boss_name == "The Tooth" then
        state.dollars = math.max(0, state.dollars - #played_cards)
    end
    -- Boss: The Ox — if play most played hand type, set money to 0
    if state.boss_name == "The Ox" and state._boss_ox then
        local ht = Sim.Eval.get_hand(played_cards, state)
        local hand_name = Sim.ENUMS.HAND_NAME[ht]
        if hand_name then
            local most_played = state._most_played_hand
            if most_played and hand_name == most_played then
                state.dollars = 0
            end
        end
    end
    -- Boss: The Psychic — must play exactly 5 cards
    if state.boss_name == "The Psychic" and #played_cards ~= 5 then
        -- Hand is invalidated (debuffed)
        state._boss_invalid_hand = true
    end
    -- Boss: The Eye — can't repeat hand type
    if state.boss_name == "The Eye" and state._boss_no_repeat then
        local ht = Sim.Eval.get_hand(played_cards, state)
        state._played_hand_types = state._played_hand_types or {}
        if state._played_hand_types[ht] then
            state._boss_invalid_hand = true
        end
        state._played_hand_types[ht] = true
    end
    -- Boss: The Mouth — can only play one hand type
    if state.boss_name == "The Mouth" and state._boss_one_hand_type then
        local ht = Sim.Eval.get_hand(played_cards, state)
        if state._mouth_allowed_type and ht ~= state._mouth_allowed_type then
            state._boss_invalid_hand = true
        elseif not state._mouth_allowed_type then
            state._mouth_allowed_type = ht
        end
    end
    -- Boss: The Flint — halves both chips and mult
    if state._boss_halve then
        state._boss_halve_applied = true
    end
    -- Track played cards for The Pillar
    if state._boss_debuff_played then
        for _, c in ipairs(played_cards) do
            c._played_this_ante = true
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
