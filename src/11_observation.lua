-- src/11_observation.lua — Observation encoder
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
