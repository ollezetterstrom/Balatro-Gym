-- src/11_observation.lua — Observation encoder
-- Auto-split. Edit freely.

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
