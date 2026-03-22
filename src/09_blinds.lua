-- src/09_blinds.lua — Blind system, boss blinds
-- Auto-split. Edit freely.

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
