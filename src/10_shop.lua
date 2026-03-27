-- src/10_shop.lua — Shop, economy, packs
--
-- Shop generation uses weighted card type selection:
--   Joker: 71.4%, Tarot: 14.3%, Planet: 14.3%
-- Pricing respects discounts and vouchers.
-- Edition rolls match real game probabilities.

Sim.Shop = {}

--- Calculate card cost with discounts.
local function apply_discount(base_cost, state)
    local discount = state._discount or 0
    if discount > 0 then
        return math.max(0, math.floor(base_cost * (100 - discount) / 100 + 0.5))
    end
    return base_cost
end

--- Select a card type using weighted random (matches real game).
--- Returns: "Joker", "Tarot", "Planet", or "Spectral"
local function pick_card_type(state)
    local joker_rate = 20
    local tarot_rate = 4
    local planet_rate = 4
    local spectral_rate = 0

    -- Voucher modifiers
    if Sim.CardFactory.has_voucher(state, "v_tarot_merchant") then tarot_rate = 8 end
    if Sim.CardFactory.has_voucher(state, "v_tarot_tycoon") then tarot_rate = 16 end
    if Sim.CardFactory.has_voucher(state, "v_planet_merchant") then planet_rate = 8 end
    if Sim.CardFactory.has_voucher(state, "v_planet_tycoon") then planet_rate = 16 end

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
