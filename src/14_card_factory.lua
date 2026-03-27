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
--- Real game: pseudorandom('rarity'..ante..append) → roll
--- >0.95 = Rare(3), >0.70 = Uncommon(2), else Common(1)
--- Legendary(4) only from The Soul, never from normal roll.
function Sim.CardFactory.roll_rarity(state, rng)
    local roll = Sim.RNG.next(rng)
    if roll > 0.95 then return 3     -- Rare: 5%
    elseif roll > 0.70 then return 2 -- Uncommon: 25%
    else return 1                    -- Common: 70%
    end
end

--- Roll edition for a card. Returns edition number (0=none, 1=foil, 2=holo, 3=poly, 4=neg).
--- Real game poll_edition (common_events.lua:2055-2080):
---   p = pseudorandom(key)
---   if p > 1 - 0.003*_mod and not _no_neg → negative
---   elseif p > 1 - 0.006*edition_rate*_mod → polychrome
---   elseif p > 1 - 0.02*edition_rate*_mod → holo
---   elseif p > 1 - 0.04*edition_rate*_mod → foil
--- MARGINAL probabilities: neg 0.3%, poly 0.3%, holo 1.4%, foil 2.0%
function Sim.CardFactory.roll_edition(state, rng, _mod, _no_neg, _guaranteed)
    _mod = _mod or 1.0
    local p = Sim.RNG.next(rng)
    local er = state._edition_rate or 1.0
    if _guaranteed then
        if p > 1 - 0.003*25 and not _no_neg then return 4 end
        if p > 1 - 0.006*25 then return 3 end
        if p > 1 - 0.02*25 then return 2 end
        if p > 1 - 0.04*25 then return 1 end
    else
        if p > 1 - 0.003*_mod and not _no_neg then return 4 end
        if p > 1 - 0.006*er*_mod then return 3 end
        if p > 1 - 0.02*er*_mod then return 2 end
        if p > 1 - 0.04*er*_mod then return 1 end
    end
    return 0
end

--- Roll stickers for a joker (eternal/perishable/rental).
--- Real game create_card (common_events.lua:2133-2147):
---   epp = pseudorandom(poll_key..ante)
---   if enable_eternals and epp > 0.7 → eternal
---   elseif enable_perishables and 0.4 < epp <= 0.7 → perishable
---   rental check: pseudorandom(key..ante) > 0.7 → rental
--- All independent probabilities.
function Sim.CardFactory.roll_stickers(state, rng)
    local eternal = false
    local perishable = false
    local rental = false

    if state.modifiers and state.modifiers.all_eternal then
        eternal = true
    end

    if state.modifiers then
        local epp = Sim.RNG.next(rng)
        if state.modifiers.enable_eternals and epp > 0.7 then
            eternal = true
        elseif state.modifiers.enable_perishables and epp > 0.4 and epp <= 0.7 then
            perishable = true
        end
        if state.modifiers.enable_rentals and Sim.RNG.next(rng) > 0.7 then
            rental = true
        end
    end

    return eternal, perishable, rental
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
--- Exact port of create_card (common_events.lua:2082-2154)
---
--- card_type: "Joker", "Tarot", "Planet", "Spectral", "Playing Card"
--- state: game state
--- rng: RNG instance
--- opts: optional table { rarity, force_key, showman, soulable, area, key_append }
---
--- Returns: card table or nil if pool is empty
function Sim.CardFactory.create(card_type, state, rng, opts)
    opts = opts or {}
    local rarity = opts.rarity
    local force_key = opts.force_key
    local showman = opts.showman
    local soulable = opts.soulable  -- default true for consumables
    local area = opts.area or ""
    local key_append = opts.key_append or ""

    -- Default soulable to true for Tarot/Planet/Spectral
    if soulable == nil and (card_type == "Tarot" or card_type == "Planet" or card_type == "Spectral") then
        soulable = true
    end
    if soulable == nil then soulable = false end

    if card_type == "Joker" then
        -- Roll rarity if not specified
        local r = rarity or Sim.CardFactory.roll_rarity(state, rng)
        if r == 4 then r = 4 end

        -- Legendary only via Soul card, not normal creation
        if r == 4 then
            local leg_pool = Sim.JOKER_RARITY_POOLS[4]
            if not leg_pool or #leg_pool == 0 then return nil end
            local jid = Sim.RNG.pick(rng, leg_pool)
            state._uid_n = (state._uid_n or 0) + 1
            return { id = jid, edition = 0, eternal = false, perishable = false,
                     rental = false, uid = state._uid_n, _new = true }
        end

        -- Get pool for this rarity
        local pool = Sim.CardFactory.get_joker_pool(state, r, showman)
        if #pool == 0 then
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

        -- Roll edition (EXACT: common_events.lua poll_edition)
        local edition = Sim.CardFactory.roll_edition(state, rng)

        -- Roll stickers (EXACT: common_events.lua:2133-2147)
        -- Only for shop_jokers and pack_cards areas
        local eternal, perishable, rental = false, false, false
        if area == "shop_jokers" or area == "pack_cards" then
            eternal, perishable, rental = Sim.CardFactory.roll_stickers(state, rng)
        end
        -- Override: all_eternal modifier
        if state.modifiers and state.modifiers.all_eternal then
            eternal = true
        end

        state._uid_n = (state._uid_n or 0) + 1
        return { id = jid, edition = edition, eternal = eternal, perishable = perishable,
                 rental = rental, uid = state._uid_n, _new = true }

    elseif card_type == "Tarot" or card_type == "Planet" or card_type == "Spectral" then
        -- Soul / Black Hole check (EXACT: common_events.lua:2088-2101)
        -- Soul: 0.3% when creating Tarot or Spectral (not if already used and no Showman)
        if soulable and card_type ~= "Planet" then
            local soul_roll = Sim.RNG.next(rng)
            if soul_roll > 0.997 then  -- NOTE: > 0.997, not < 0.003
                local soul_def = Sim.CONSUMABLE_DEFS["c_soul"]
                if soul_def then
                    state._uid_n = (state._uid_n or 0) + 1
                    return { id = soul_def.id, uid = state._uid_n, _new = true }
                end
            end
        end
        -- Black Hole: 0.3% when creating Planet or Spectral
        if soulable and card_type ~= "Tarot" then
            local bh_roll = Sim.RNG.next(rng)
            if bh_roll > 0.997 then
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
