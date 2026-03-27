-- src/16_vouchers.lua — Voucher system (32 vouchers from real Balatro)
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
