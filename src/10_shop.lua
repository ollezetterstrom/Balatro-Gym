-- src/10_shop.lua — Shop, economy, packs

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
    -- Replace all joker slots with new random jokers
    for i = 1, 2 do
        local jid = Sim.RNG.pick(state.rng, pool)
        local def = Sim._JOKER_BY_ID[jid]
        state.shop.jokers[i] = { joker_id = jid, cost = def.cost or 3, slot = i }
    end
    -- Replace consumable slot if room
    if #state.consumables < state.consumable_slots then
        local cid = Sim.RNG.pick(state.rng, Sim.CONS_POOL)
        state.shop.consumable = { cons_id = cid, cost = 0, slot = 4 }
    else
        state.shop.consumable = nil
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
