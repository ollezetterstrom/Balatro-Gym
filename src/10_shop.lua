-- src/10_shop.lua — Shop, economy, packs
-- Auto-split. Edit freely.

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
