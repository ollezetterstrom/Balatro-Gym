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

-- === Planet cards (10 remaining) ===

_reg_cons("c_venus", "Venus", "Planet", function(ctx, state)
    Sim.State.level_up(state, Sim.ENUMS.HAND_TYPE.THREE_OF_A_KIND, 1)
    return { level_up = Sim.ENUMS.HAND_TYPE.THREE_OF_A_KIND }
end)

_reg_cons("c_earth", "Earth", "Planet", function(ctx, state)
    Sim.State.level_up(state, Sim.ENUMS.HAND_TYPE.FULL_HOUSE, 1)
    return { level_up = Sim.ENUMS.HAND_TYPE.FULL_HOUSE }
end)

_reg_cons("c_mars", "Mars", "Planet", function(ctx, state)
    Sim.State.level_up(state, Sim.ENUMS.HAND_TYPE.FOUR_OF_A_KIND, 1)
    return { level_up = Sim.ENUMS.HAND_TYPE.FOUR_OF_A_KIND }
end)

_reg_cons("c_jupiter", "Jupiter", "Planet", function(ctx, state)
    Sim.State.level_up(state, Sim.ENUMS.HAND_TYPE.FLUSH, 1)
    return { level_up = Sim.ENUMS.HAND_TYPE.FLUSH }
end)

_reg_cons("c_saturn", "Saturn", "Planet", function(ctx, state)
    Sim.State.level_up(state, Sim.ENUMS.HAND_TYPE.STRAIGHT, 1)
    return { level_up = Sim.ENUMS.HAND_TYPE.STRAIGHT }
end)

_reg_cons("c_neptune", "Neptune", "Planet", function(ctx, state)
    Sim.State.level_up(state, Sim.ENUMS.HAND_TYPE.STRAIGHT_FLUSH, 1)
    return { level_up = Sim.ENUMS.HAND_TYPE.STRAIGHT_FLUSH }
end)

_reg_cons("c_uranus", "Uranus", "Planet", function(ctx, state)
    Sim.State.level_up(state, Sim.ENUMS.HAND_TYPE.TWO_PAIR, 1)
    return { level_up = Sim.ENUMS.HAND_TYPE.TWO_PAIR }
end)

_reg_cons("c_planet_x", "Planet X", "Planet", function(ctx, state)
    Sim.State.level_up(state, Sim.ENUMS.HAND_TYPE.FIVE_OF_A_KIND, 1)
    return { level_up = Sim.ENUMS.HAND_TYPE.FIVE_OF_A_KIND }
end)

_reg_cons("c_ceres", "Ceres", "Planet", function(ctx, state)
    Sim.State.level_up(state, Sim.ENUMS.HAND_TYPE.FLUSH_HOUSE, 1)
    return { level_up = Sim.ENUMS.HAND_TYPE.FLUSH_HOUSE }
end)

_reg_cons("c_eris", "Eris", "Planet", function(ctx, state)
    Sim.State.level_up(state, Sim.ENUMS.HAND_TYPE.FLUSH_FIVE, 1)
    return { level_up = Sim.ENUMS.HAND_TYPE.FLUSH_FIVE }
end)

-- === Tarot cards (16 remaining) ===

_reg_cons("c_magician", "The Magician", "Tarot", function(ctx, state)
    if not ctx.selected or #ctx.selected == 0 then return nil end
    local count = 0
    for _, idx in ipairs(ctx.selected) do
        local c = state.hand[idx]
        if c and count < 2 then
            c.enhancement = Sim.ENUMS.ENHANCEMENT.LUCKY
            count = count + 1
        end
    end
    return { enhanced = count }
end)

_reg_cons("c_high_priestess", "The High Priestess", "Tarot", function(ctx, state)
    local created = 0
    for _ = 1, 2 do
        if #state.consumables < state.consumable_slots then
            local planet_ids = {}
            for _, def in pairs(Sim.CONSUMABLE_DEFS) do
                if def.set == "Planet" then planet_ids[#planet_ids+1] = def.id end
            end
            local pid = Sim.RNG.pick(state.rng, planet_ids)
            state._cons_n = (state._cons_n or 0) + 1
            state.consumables[#state.consumables + 1] = { id = pid, uid = state._cons_n }
            created = created + 1
        end
    end
    return { created = created }
end)

_reg_cons("c_emperor", "The Emperor", "Tarot", function(ctx, state)
    local created = 0
    for _ = 1, 2 do
        if #state.consumables < state.consumable_slots then
            local tarot_ids = {}
            for _, def in pairs(Sim.CONSUMABLE_DEFS) do
                if def.set == "Tarot" and def.id ~= state.last_consumable then
                    tarot_ids[#tarot_ids+1] = def.id
                end
            end
            if #tarot_ids > 0 then
                local tid = Sim.RNG.pick(state.rng, tarot_ids)
                state._cons_n = (state._cons_n or 0) + 1
                state.consumables[#state.consumables + 1] = { id = tid, uid = state._cons_n }
                created = created + 1
            end
        end
    end
    return { created = created }
end)

_reg_cons("c_hierophant", "The Hierophant", "Tarot", function(ctx, state)
    if not ctx.selected or #ctx.selected == 0 then return nil end
    local count = 0
    for _, idx in ipairs(ctx.selected) do
        local c = state.hand[idx]
        if c and count < 2 then
            c.enhancement = Sim.ENUMS.ENHANCEMENT.BONUS
            count = count + 1
        end
    end
    return { enhanced = count }
end)

_reg_cons("c_lovers", "The Lovers", "Tarot", function(ctx, state)
    if not ctx.selected or #ctx.selected == 0 then return nil end
    local idx = ctx.selected[1]
    local c = state.hand[idx]
    if c then
        c.enhancement = Sim.ENUMS.ENHANCEMENT.WILD
        return { enhanced = 1 }
    end
    return nil
end)

_reg_cons("c_chariot", "The Chariot", "Tarot", function(ctx, state)
    if not ctx.selected or #ctx.selected == 0 then return nil end
    local idx = ctx.selected[1]
    local c = state.hand[idx]
    if c then
        c.enhancement = Sim.ENUMS.ENHANCEMENT.STEEL
        return { enhanced = 1 }
    end
    return nil
end)

_reg_cons("c_strength", "Strength", "Tarot", function(ctx, state)
    if not ctx.selected or #ctx.selected == 0 then return nil end
    local count = 0
    for _, idx in ipairs(ctx.selected) do
        local c = state.hand[idx]
        if c and c.rank < 14 and count < 2 then
            c.rank = c.rank + 1
            count = count + 1
        end
    end
    return { enhanced = count }
end)

_reg_cons("c_hermit", "The Hermit", "Tarot", function(ctx, state)
    local bonus = math.min(state.dollars, 20)
    state.dollars = state.dollars + bonus
    return { money = bonus }
end)

_reg_cons("c_wheel_of_fortune", "Wheel of Fortune", "Tarot", function(ctx, state)
    if not state.jokers or #state.jokers == 0 then return nil end
    if Sim.RNG.next(state.rng) >= 0.25 then return nil end
    local ji = Sim.RNG.int(state.rng, 1, #state.jokers)
    local jk = state.jokers[ji]
    if jk.edition == 0 then
        local editions = {
            Sim.ENUMS.EDITION.FOIL,
            Sim.ENUMS.EDITION.HOLO,
            Sim.ENUMS.EDITION.POLYCHROME,
        }
        jk.edition = Sim.RNG.pick(state.rng, editions)
        return { edition = jk.edition }
    end
    return nil
end)

_reg_cons("c_justice", "Justice", "Tarot", function(ctx, state)
    if not ctx.selected or #ctx.selected == 0 then return nil end
    local idx = ctx.selected[1]
    local c = state.hand[idx]
    if c then
        c.enhancement = Sim.ENUMS.ENHANCEMENT.GLASS
        return { enhanced = 1 }
    end
    return nil
end)

_reg_cons("c_hanged_man", "The Hanged Man", "Tarot", function(ctx, state)
    if not ctx.selected or #ctx.selected == 0 then return nil end
    local destroyed = 0
    local sorted = {}
    for _, v in ipairs(ctx.selected) do sorted[#sorted+1] = v end
    table.sort(sorted, function(a,b) return a > b end)
    for _, idx in ipairs(sorted) do
        if state.hand[idx] and destroyed < 2 then
            table.remove(state.hand, idx)
            destroyed = destroyed + 1
        end
    end
    state.deck_count = state.deck_count - destroyed
    return { destroyed = destroyed }
end)

_reg_cons("c_death", "Death", "Tarot", function(ctx, state)
    if not ctx.selected or #ctx.selected < 2 then return nil end
    local src = state.hand[ctx.selected[1]]
    local tgt_idx = ctx.selected[2]
    if src and state.hand[tgt_idx] then
        -- Copy src card properties to tgt
        local tgt = state.hand[tgt_idx]
        tgt.rank = src.rank
        tgt.suit = src.suit
        tgt.enhancement = src.enhancement
        tgt.edition = src.edition
        tgt.seal = src.seal
        tgt.perma_bonus = src.perma_bonus
        return { copied = true }
    end
    return nil
end)

_reg_cons("c_temperance", "Temperance", "Tarot", function(ctx, state)
    local total = 0
    if state.jokers then
        for _, jk in ipairs(state.jokers) do
            local def = Sim._JOKER_BY_ID[jk.id]
            if def then total = total + (def.cost or 3) end
        end
    end
    total = math.min(total, 50)
    state.dollars = state.dollars + total
    return { money = total }
end)

_reg_cons("c_devil", "The Devil", "Tarot", function(ctx, state)
    if not ctx.selected or #ctx.selected == 0 then return nil end
    local idx = ctx.selected[1]
    local c = state.hand[idx]
    if c then
        c.enhancement = Sim.ENUMS.ENHANCEMENT.GOLD
        return { enhanced = 1 }
    end
    return nil
end)

_reg_cons("c_tower", "The Tower", "Tarot", function(ctx, state)
    if not ctx.selected or #ctx.selected == 0 then return nil end
    local idx = ctx.selected[1]
    local c = state.hand[idx]
    if c then
        c.enhancement = Sim.ENUMS.ENHANCEMENT.STONE
        return { enhanced = 1 }
    end
    return nil
end)

_reg_cons("c_star", "The Star", "Tarot", function(ctx, state)
    if not ctx.selected or #ctx.selected == 0 then return nil end
    local count = 0
    for _, idx in ipairs(ctx.selected) do
        local c = state.hand[idx]
        if c and count < 3 then
            c.suit = Sim.ENUMS.SUIT.DIAMONDS
            count = count + 1
        end
    end
    return { changed = count }
end)

_reg_cons("c_moon", "The Moon", "Tarot", function(ctx, state)
    if not ctx.selected or #ctx.selected == 0 then return nil end
    local count = 0
    for _, idx in ipairs(ctx.selected) do
        local c = state.hand[idx]
        if c and count < 3 then
            c.suit = Sim.ENUMS.SUIT.CLUBS
            count = count + 1
        end
    end
    return { changed = count }
end)

_reg_cons("c_sun", "The Sun", "Tarot", function(ctx, state)
    if not ctx.selected or #ctx.selected == 0 then return nil end
    local count = 0
    for _, idx in ipairs(ctx.selected) do
        local c = state.hand[idx]
        if c and count < 3 then
            c.suit = Sim.ENUMS.SUIT.HEARTS
            count = count + 1
        end
    end
    return { changed = count }
end)

_reg_cons("c_world", "The World", "Tarot", function(ctx, state)
    if not ctx.selected or #ctx.selected == 0 then return nil end
    local count = 0
    for _, idx in ipairs(ctx.selected) do
        local c = state.hand[idx]
        if c and count < 3 then
            c.suit = Sim.ENUMS.SUIT.SPADES
            count = count + 1
        end
    end
    return { changed = count }
end)

-- === Spectral cards (16) ===

_reg_cons("c_familiar", "Familiar", "Spectral", function(ctx, state)
    if not state.hand or #state.hand == 0 then return nil end
    -- Destroy 1 random card
    local di = Sim.RNG.int(state.rng, 1, #state.hand)
    table.remove(state.hand, di)
    state.deck_count = state.deck_count - 1
    -- Create 3 random face cards with random enhancement
    local faces = {11, 12, 13}
    local enhancements = {1, 2, 3, 4, 5, 7, 8}
    local created = 0
    for _ = 1, 3 do
        if #state.hand < state.hand_limit then
            local rank = Sim.RNG.pick(state.rng, faces)
            local suit = Sim.RNG.int(state.rng, 1, 4)
            local enh = Sim.RNG.pick(state.rng, enhancements)
            state.hand[#state.hand+1] = Sim.Card.new(rank, suit, enh)
            created = created + 1
        end
    end
    return { created = created }
end)

_reg_cons("c_grim", "Grim", "Spectral", function(ctx, state)
    if not state.hand or #state.hand == 0 then return nil end
    -- Destroy 1 random card
    local di = Sim.RNG.int(state.rng, 1, #state.hand)
    table.remove(state.hand, di)
    state.deck_count = state.deck_count - 1
    -- Create 2 Aces with random enhancement
    local enhancements = {1, 2, 3, 4, 5, 7, 8}
    local created = 0
    for _ = 1, 2 do
        if #state.hand < state.hand_limit then
            local suit = Sim.RNG.int(state.rng, 1, 4)
            local enh = Sim.RNG.pick(state.rng, enhancements)
            state.hand[#state.hand+1] = Sim.Card.new(14, suit, enh)
            created = created + 1
        end
    end
    return { created = created }
end)

_reg_cons("c_incantation", "Incantation", "Spectral", function(ctx, state)
    if not state.hand or #state.hand == 0 then return nil end
    -- Destroy 1 random card
    local di = Sim.RNG.int(state.rng, 1, #state.hand)
    table.remove(state.hand, di)
    state.deck_count = state.deck_count - 1
    -- Create 4 numbered cards (2-10) with random enhancement
    local enhancements = {1, 2, 3, 4, 5, 7, 8}
    local created = 0
    for _ = 1, 4 do
        if #state.hand < state.hand_limit then
            local rank = Sim.RNG.int(state.rng, 2, 10)
            local suit = Sim.RNG.int(state.rng, 1, 4)
            local enh = Sim.RNG.pick(state.rng, enhancements)
            state.hand[#state.hand+1] = Sim.Card.new(rank, suit, enh)
            created = created + 1
        end
    end
    return { created = created }
end)

_reg_cons("c_talisman", "Talisman", "Spectral", function(ctx, state)
    if not ctx.selected or #ctx.selected == 0 then return nil end
    local c = state.hand[ctx.selected[1]]
    if c then
        c.seal = Sim.ENUMS.SEAL.GOLD
        return { sealed = true }
    end
    return nil
end)

_reg_cons("c_aura", "Aura", "Spectral", function(ctx, state)
    if not ctx.selected or #ctx.selected == 0 then return nil end
    local c = state.hand[ctx.selected[1]]
    if c and c.edition == 0 then
        local editions = {
            Sim.ENUMS.EDITION.FOIL,
            Sim.ENUMS.EDITION.HOLO,
            Sim.ENUMS.EDITION.POLYCHROME,
        }
        c.edition = Sim.RNG.pick(state.rng, editions)
        return { edition = c.edition }
    end
    return nil
end)

_reg_cons("c_wraith", "Wraith", "Spectral", function(ctx, state)
    -- Create 1 random Joker
    if #state.jokers >= state.joker_slots then return nil end
    local jid = Sim.RNG.pick(state.rng, Sim.JOKER_POOL)
    state._joker_n = (state._joker_n or 0) + 1
    state.jokers[#state.jokers+1] = {
        id = jid, edition = 0, eternal = false, uid = state._joker_n,
    }
    -- Set money to 0
    state.dollars = 0
    return { created = true }
end)

_reg_cons("c_sigil", "Sigil", "Spectral", function(ctx, state)
    local suit = Sim.RNG.int(state.rng, 1, 4)
    for _, c in ipairs(state.hand) do
        if c.enhancement ~= 6 then -- Skip Stone cards
            c.suit = suit
        end
    end
    return { suit = suit }
end)

_reg_cons("c_ouija", "Ouija", "Spectral", function(ctx, state)
    local rank = Sim.RNG.int(state.rng, 2, 14)
    for _, c in ipairs(state.hand) do
        if c.enhancement ~= 6 then -- Skip Stone cards
            c.rank = rank
        end
    end
    -- -1 hand size
    state.hand_limit = math.max(1, state.hand_limit - 1)
    return { rank = rank }
end)

_reg_cons("c_ectoplasm", "Ectoplasm", "Spectral", function(ctx, state)
    -- Add Negative edition to a random Joker
    local eligible = {}
    for _, jk in ipairs(state.jokers) do
        if jk.edition == 0 then eligible[#eligible+1] = jk end
    end
    if #eligible == 0 then return nil end
    local jk = Sim.RNG.pick(state.rng, eligible)
    jk.edition = Sim.ENUMS.EDITION.NEGATIVE
    -- -1 hand size
    state.hand_limit = math.max(1, state.hand_limit - 1)
    return { edition = Sim.ENUMS.EDITION.NEGATIVE }
end)

_reg_cons("c_immolate", "Immolate", "Spectral", function(ctx, state)
    if not state.hand or #state.hand == 0 then return nil end
    -- Destroy 5 random cards
    local destroyed = 0
    local indices = {}
    for i = 1, #state.hand do indices[i] = i end
    Sim.RNG.shuffle(state.rng, indices)
    local n = math.min(5, #state.hand)
    table.sort(indices, function(a,b) return a > b end)
    for i = 1, n do
        table.remove(state.hand, indices[i])
        destroyed = destroyed + 1
    end
    state.deck_count = state.deck_count - destroyed
    -- Gain $20
    state.dollars = state.dollars + 20
    return { destroyed = destroyed, money = 20 }
end)

_reg_cons("c_ankh", "Ankh", "Spectral", function(ctx, state)
    if not state.jokers or #state.jokers == 0 then return nil end
    -- Pick a random joker to copy
    local src = Sim.RNG.pick(state.rng, state.jokers)
    -- Destroy all other jokers
    state.jokers = { src }
    -- Create a copy
    if #state.jokers < state.joker_slots then
        state._joker_n = (state._joker_n or 0) + 1
        state.jokers[#state.jokers+1] = {
            id = src.id, edition = src.edition, eternal = src.eternal, uid = state._joker_n,
        }
    end
    return { copied = true }
end)

_reg_cons("c_deja_vu", "Deja Vu", "Spectral", function(ctx, state)
    if not ctx.selected or #ctx.selected == 0 then return nil end
    local c = state.hand[ctx.selected[1]]
    if c then
        c.seal = Sim.ENUMS.SEAL.RED
        return { sealed = true }
    end
    return nil
end)

_reg_cons("c_hex", "Hex", "Spectral", function(ctx, state)
    -- Add Polychrome to a random Joker
    local eligible = {}
    for _, jk in ipairs(state.jokers) do
        if jk.edition == 0 then eligible[#eligible+1] = jk end
    end
    if #eligible == 0 then return nil end
    local jk = Sim.RNG.pick(state.rng, eligible)
    jk.edition = Sim.ENUMS.EDITION.POLYCHROME
    -- Destroy all other jokers
    state.jokers = { jk }
    return { edition = Sim.ENUMS.EDITION.POLYCHROME }
end)

_reg_cons("c_trance", "Trance", "Spectral", function(ctx, state)
    if not ctx.selected or #ctx.selected == 0 then return nil end
    local c = state.hand[ctx.selected[1]]
    if c then
        c.seal = Sim.ENUMS.SEAL.BLUE
        return { sealed = true }
    end
    return nil
end)

_reg_cons("c_medium", "Medium", "Spectral", function(ctx, state)
    if not ctx.selected or #ctx.selected == 0 then return nil end
    local c = state.hand[ctx.selected[1]]
    if c then
        c.seal = Sim.ENUMS.SEAL.PURPLE
        return { sealed = true }
    end
    return nil
end)

_reg_cons("c_cryptid", "Cryptid", "Spectral", function(ctx, state)
    if not ctx.selected or #ctx.selected == 0 then return nil end
    local src = state.hand[ctx.selected[1]]
    if not src then return nil end
    local created = 0
    for _ = 1, 2 do
        if #state.hand < state.hand_limit then
            state.hand[#state.hand+1] = Sim.Card.new(
                src.rank, src.suit, src.enhancement, src.edition, src.seal, src.perma_bonus
            )
            state.deck_count = state.deck_count + 1
            created = created + 1
        end
    end
    return { created = created }
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


