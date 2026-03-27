-- src/09_blinds.lua — Blind system, boss blinds

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
