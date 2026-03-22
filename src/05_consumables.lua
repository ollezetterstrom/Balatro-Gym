-- src/05_consumables.lua — Consumables, pool, advanced jokers
-- Auto-split. Edit freely.

--  SECTION 5 — CONSUMABLE DEFINITIONS
-- ============================================================================

Sim.CONSUMABLE_DEFS = {}
Sim._CONS_BY_ID = {}

function _reg_cons(key, name, set, effect_fn)
    local def = { id = #Sim._CONS_BY_ID + 1, key = key, name = name,
                  set = set, effect = effect_fn }
    Sim.CONSUMABLE_DEFS[key] = def
    Sim._CONS_BY_ID[def.id] = def
    return def
end

_reg_cons("c_pluto", "Pluto", "Planet", function(ctx, state)
    -- Level up High Card
    Sim.State.level_up(state, Sim.ENUMS.HAND_TYPE.HIGH_CARD, 1)
    return { level_up = Sim.ENUMS.HAND_TYPE.HIGH_CARD }
end)

_reg_cons("c_mercury", "Mercury", "Planet", function(ctx, state)
    -- Level up Pair
    Sim.State.level_up(state, Sim.ENUMS.HAND_TYPE.PAIR, 1)
    return { level_up = Sim.ENUMS.HAND_TYPE.PAIR }
end)

_reg_cons("c_empress", "The Empress", "Tarot", function(ctx, state)
    -- Enhance up to 2 selected cards to Mult (+4 Mult)
    if not ctx.selected or #ctx.selected == 0 then return nil end
    local count = 0
    for _, idx in ipairs(ctx.selected) do
        local c = state.hand[idx]
        if c and count < 2 then
            c.enhancement = Sim.ENUMS.ENHANCEMENT.MULT
            count = count + 1
        end
    end
    return { enhanced = count }
end)

_reg_cons("c_fool", "The Fool", "Tarot", function(ctx, state)
    -- Spawn the last used consumable (other than The Fool)
    if not state.last_consumable then return nil end
    if #state.consumables >= state.consumable_slots then return nil end
    local def = Sim._CONS_BY_ID[state.last_consumable]
    if not def or def.key == "c_fool" then return nil end
    state.consumables[#state.consumables + 1] = {
        id = def.id, uid = state._cons_n or 0,
    }
    return { spawned = def.key }
end)

Sim.CONS_POOL = {}
for _, def in pairs(Sim.CONSUMABLE_DEFS) do
    Sim.CONS_POOL[#Sim.CONS_POOL + 1] = def.id
end

-- ============================================================================
--  SECTION 6 — ADVANCED JOKERS
-- ============================================================================

_reg_joker("j_sixth_sense", "Sixth Sense", 2, 6, function(ctx, st, jk)
    if ctx.destroying_card then
        if not ctx.is_first_hand then return nil end
        if not ctx.full_hand or #ctx.full_hand ~= 1 then return nil end
        if ctx.full_hand[1].rank ~= 6 then return nil end
        -- Create a spectral consumable if room
        if #st.consumables < st.consumable_slots then
            -- Pick a random spectral-ish consumable
            local cid = Sim.RNG.pick(st.rng, Sim.CONS_POOL)
            st.consumables[#st.consumables + 1] = { id = cid, uid = (st._cons_n or 0) + 1 }
            st._cons_n = (st._cons_n or 0) + 1
            return { destroy = true, message = "Spectral created" }
        end
        return { destroy = true }
    end
end)

_reg_joker("j_hiker", "Hiker", 1, 5, function(ctx, st, jk)
    if ctx.individual and ctx.cardarea == "play" then


        ctx.other_card.perma_bonus = (ctx.other_card.perma_bonus or 0) + 4
        return { chips = 0, message = "+4 permanent" }
    end
end)

Sim.JOKER_POOL = {}
for _, def in pairs(Sim.JOKER_DEFS) do
    Sim.JOKER_POOL[#Sim.JOKER_POOL + 1] = def.id
end

-- ============================================================================


