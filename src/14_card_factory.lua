-- src/14_card_factory.lua — Card creation system with pools and rarity
--
-- Provides Sim.create_card() for creating cards with proper pools, rarity rolls,
-- and pool culling (removes owned cards, respects flags).
--
-- Depends on: 04_jokers.lua (Sim.JOKER_DEFS), 05_consumables.lua (Sim.CONSUMABLE_DEFS)

Sim.CardFactory = {}

--- Rarity pools (built from joker definitions)
Sim.JOKER_RARITY_POOLS = { [1] = {}, [2] = {}, [3] = {}, [4] = {} }
for _, def in pairs(Sim.JOKER_DEFS) do
    local r = def.rarity or 1
    Sim.JOKER_RARITY_POOLS[r] = Sim.JOKER_RARITY_POOLS[r] or {}
    Sim.JOKER_RARITY_POOLS[r][#Sim.JOKER_RARITY_POOLS[r] + 1] = def.id
end

--- Consumable type pools
Sim.TAROT_POOL = {}
Sim.PLANET_POOL = {}
Sim.SPECTRAL_POOL = {}
for _, def in pairs(Sim.CONSUMABLE_DEFS) do
    local k = def.key or ""
    if k:find("pluto") or k:find("mercury") or k:find("venus") or k:find("earth") or
       k:find("mars") or k:find("jupiter") or k:find("saturn") or k:find("neptune") or
       k:find("uranus") or k:find("planet_x") or k:find("ceres") or k:find("eris") then
        Sim.PLANET_POOL[#Sim.PLANET_POOL + 1] = def.id
    elseif k:find("familiar") or k:find("grim") or k:find("incantation") or
           k:find("talisman") or k:find("aura") or k:find("wraith") or
           k:find("sigil") or k:find("ouija") or k:find("ectoplasm") or
           k:find("immolate") or k:find("ankh") or k:find("deja_vu") or
           k:find("hex") or k:find("trance") or k:find("medium") or k:find("cryptid") then
        Sim.SPECTRAL_POOL[#Sim.SPECTRAL_POOL + 1] = def.id
    else
        Sim.TAROT_POOL[#Sim.TAROT_POOL + 1] = def.id
    end
end

--- Playing card pool (52 standard cards)
Sim.PLAYING_CARD_POOL = {}
for suit = 1, 4 do
    for rank = 2, 14 do
        Sim.PLAYING_CARD_POOL[#Sim.PLAYING_CARD_POOL + 1] = { rank = rank, suit = suit }
    end
end

--- Roll rarity for a joker. Returns 1-4.
--- Uses pseudorandom seeded by ante (matches real game's rarity roll).
function Sim.CardFactory.roll_rarity(state, rng)
    local roll = Sim.RNG.next(rng)
    if roll > 0.95 then return 3     -- Rare: 5%
    elseif roll > 0.70 then return 2 -- Uncommon: 25%
    else return 1                    -- Common: 70%
    end
end

--- Get available joker IDs for a given rarity, excluding owned jokers.
--- If showman is true, does NOT exclude owned jokers.
function Sim.CardFactory.get_joker_pool(state, rarity, showman)
    local pool = Sim.JOKER_RARITY_POOLS[rarity]
    if not pool or #pool == 0 then return {} end
    if showman then return pool end

    -- Build set of owned joker IDs
    local owned = {}
    for _, jk in ipairs(state.jokers) do
        owned[jk.id] = true
    end

    -- Filter out owned
    local available = {}
    for _, jid in ipairs(pool) do
        if not owned[jid] then
            local def = Sim._JOKER_BY_ID[jid]
            -- Skip locked/undiscovered
            if def and def.key ~= "j_locked" and def.key ~= "j_undiscovered" then
                available[#available + 1] = jid
            end
        end
    end
    return available
end

--- Get available consumable IDs for a given type.
--- type: "tarot", "planet", "spectral"
function Sim.CardFactory.get_consumable_pool(state, ctype, showman)
    local pool
    if ctype == "tarot" then pool = Sim.TAROT_POOL
    elseif ctype == "planet" then pool = Sim.PLANET_POOL
    elseif ctype == "spectral" then pool = Sim.SPECTRAL_POOL
    else return {}
    end
    if showman then return pool end

    -- Filter out owned consumables
    local owned = {}
    for _, cs in ipairs(state.consumables) do
        owned[cs.id] = true
    end

    local available = {}
    for _, cid in ipairs(pool) do
        if not owned[cid] then
            available[#available + 1] = cid
        end
    end
    return available
end

--- Create a card of the given type.
---
--- card_type: "Joker", "Tarot", "Planet", "Spectral", "Playing Card"
--- state: game state
--- rng: RNG instance
--- rarity: (optional) for Joker type, force rarity 1-4. nil = roll.
--- force_key: (optional) force a specific key instead of random
--- showman: (optional) if true, don't exclude owned cards from pool
---
--- Returns: card table or nil if pool is empty
function Sim.CardFactory.create(card_type, state, rng, rarity, force_key, showman)
    if card_type == "Joker" then
        -- Roll rarity if not specified
        local r = rarity or Sim.CardFactory.roll_rarity(state, rng)
        if r == 4 then r = 4 end  -- Legendary only via Soul

        -- Check for Soul card (0.3% when creating Tarot/Spectral/Planet)
        -- Legendary jokers only come from Soul card, not normal creation
        if r == 4 then
            local leg_pool = Sim.JOKER_RARITY_POOLS[4]
            if not leg_pool or #leg_pool == 0 then return nil end
            local jid = Sim.RNG.pick(rng, leg_pool)
            return { id = jid, edition = 0, eternal = false, perishable = false,
                     rental = false, uid = (state._uid_n or 0) + 1, _new = true }
        end

        -- Get pool for this rarity
        local pool = Sim.CardFactory.get_joker_pool(state, r, showman)
        if #pool == 0 then
            -- Pool exhausted, try fallback to any rarity
            for fallback_r = 1, 3 do
                pool = Sim.CardFactory.get_joker_pool(state, fallback_r, showman)
                if #pool > 0 then break end
            end
        end
        if #pool == 0 then return nil end

        local jid
        if force_key then
            local def = Sim.JOKER_DEFS[force_key]
            jid = def and def.id or Sim.RNG.pick(rng, pool)
        else
            jid = Sim.RNG.pick(rng, pool)
        end

        -- Roll edition (from real game common_events.lua)
        local edition = 0
        local edition_roll = Sim.RNG.next(rng)
        local edition_rate = state._edition_rate or 1.0
        if edition_roll < 0.003 * edition_rate then
            edition = 4  -- Negative
        elseif edition_roll < 0.006 * edition_rate + 0.003 * edition_rate then
            edition = 3  -- Polychrome
        elseif edition_roll < 0.02 * edition_rate + 0.009 * edition_rate then
            edition = 2  -- Holographic
        elseif edition_roll < 0.04 * edition_rate + 0.029 * edition_rate then
            edition = 1  -- Foil
        end

        state._uid_n = (state._uid_n or 0) + 1
        return { id = jid, edition = edition, eternal = false, perishable = false,
                 rental = false, uid = state._uid_n, _new = true }

    elseif card_type == "Tarot" or card_type == "Planet" or card_type == "Spectral" then
        -- Check for Soul / Black Hole chance (0.3%)
        if card_type ~= "Planet" then
            -- 0.3% chance for The Soul when creating Tarot or Spectral
            local soul_roll = Sim.RNG.next(rng)
            if soul_roll < 0.003 then
                -- Create The Soul consumable (if exists)
                local soul_def = Sim.CONSUMABLE_DEFS["c_soul"]
                if soul_def then
                    state._uid_n = (state._uid_n or 0) + 1
                    return { id = soul_def.id, uid = state._uid_n, _new = true }
                end
            end
        end
        if card_type ~= "Tarot" then
            -- 0.3% chance for Black Hole when creating Planet or Spectral
            local bh_roll = Sim.RNG.next(rng)
            if bh_roll < 0.003 then
                local bh_def = Sim.CONSUMABLE_DEFS["c_black_hole"]
                if bh_def then
                    state._uid_n = (state._uid_n or 0) + 1
                    return { id = bh_def.id, uid = state._uid_n, _new = true }
                end
            end
        end

        local ctype = card_type:lower()
        local pool = Sim.CardFactory.get_consumable_pool(state, ctype, showman)
        if #pool == 0 then return nil end

        local cid
        if force_key then
            local def = Sim.CONSUMABLE_DEFS[force_key]
            cid = def and def.id or Sim.RNG.pick(rng, pool)
        else
            cid = Sim.RNG.pick(rng, pool)
        end

        state._uid_n = (state._uid_n or 0) + 1
        return { id = cid, uid = state._uid_n, _new = true }

    elseif card_type == "Playing Card" then
        -- Random playing card
        local roll = Sim.RNG.pick(rng, Sim.PLAYING_CARD_POOL)
        local rank = roll.rank
        local suit = roll.suit
        state._uid_n = (state._uid_n or 0) + 1
        return Sim.Card.new(rank, suit, 0, 0, 0, state._uid_n)
    end

    return nil
end

--- Check if the player has a specific joker by key.
function Sim.CardFactory.has_joker(state, key)
    local def = Sim.JOKER_DEFS[key]
    if not def then return false end
    for _, jk in ipairs(state.jokers) do
        if jk.id == def.id then return true end
    end
    return false
end

--- Check if the player has a specific voucher.
function Sim.CardFactory.has_voucher(state, key)
    return state.vouchers and state.vouchers[key] == true
end

--- Count cards in deck with a given enhancement.
function Sim.CardFactory.count_enhancement(state, enhancement)
    local count = 0
    for _, c in ipairs(state.deck) do
        if c.enhancement == enhancement then count = count + 1 end
    end
    return count
end

--- Count cards in deck with a given suit.
function Sim.CardFactory.count_suit(state, suit)
    local count = 0
    for _, c in ipairs(state.deck) do
        if c.suit == suit then count = count + 1 end
    end
    return count
end
