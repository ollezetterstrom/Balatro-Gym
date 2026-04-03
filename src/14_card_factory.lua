-- src/14_card_factory.lua — Card creation system with pools and culling
--
-- EXACT port of real game's create_card and get_current_pool.
-- Real game sources:
--   common_events.lua:1963-2053  get_current_pool
--   common_events.lua:2055-2080  poll_edition
--   common_events.lua:2082-2154  create_card
--   UI_definitions.lua:742-800   create_card_for_shop

Sim.CardFactory = {}

-- ========================================================================= --
-- POOL DEFINITIONS (built from joker/consumable definitions)
-- ========================================================================= --

--- Joker rarity pools
Sim.JOKER_RARITY_POOLS = { [1] = {}, [2] = {}, [3] = {}, [4] = {} }
for _, def in pairs(Sim.JOKER_DEFS) do
    local r = def.rarity or 1
    Sim.JOKER_RARITY_POOLS[r] = Sim.JOKER_RARITY_POOLS[r] or {}
    Sim.JOKER_RARITY_POOLS[r][#Sim.JOKER_RARITY_POOLS[r] + 1] = def.key
end

--- Consumable type pools
Sim.TAROT_POOL = {}
Sim.PLANET_POOL = {}
Sim.SPECTRAL_POOL = {}
for key, def in pairs(Sim.CONSUMABLE_DEFS) do
    if def.set == "Planet" then
        Sim.PLANET_POOL[#Sim.PLANET_POOL + 1] = key
    elseif def.set == "Spectral" then
        Sim.SPECTRAL_POOL[#Sim.SPECTRAL_POOL + 1] = key
    elseif def.set == "Tarot" then
        Sim.TAROT_POOL[#Sim.TAROT_POOL + 1] = key
    end
end

--- Voucher pool
Sim.VOUCHER_POOL = {}
for key, def in pairs(Sim.Voucher.DEFS) do
    Sim.VOUCHER_POOL[#Sim.VOUCHER_POOL + 1] = key
end

--- Playing card pool (52 standard cards)
Sim.PLAYING_CARD_POOL = {}
for suit = 1, 4 do
    for rank = 2, 14 do
        Sim.PLAYING_CARD_POOL[#Sim.PLAYING_CARD_POOL + 1] = { rank = rank, suit = suit }
    end
end

-- ========================================================================= --
-- CHECK IF PLAYER HAS A JOKER (like real game's find_joker)
-- ========================================================================= --

--- Check if player has a joker by key. Returns list of matching jokers.
function Sim.CardFactory.find_joker(state, key)
    local results = {}
    for _, jk in ipairs(state.jokers or {}) do
        local def = Sim._JOKER_BY_ID[jk.id]
        if def and def.key == key then
            results[#results + 1] = jk
        end
    end
    return results
end

--- Check if player has a joker by key (boolean).
function Sim.CardFactory.has_joker(state, key)
    return #Sim.CardFactory.find_joker(state, key) > 0
end

--- Check if player has a specific voucher.
function Sim.CardFactory.has_voucher(state, key)
    return state.vouchers and state.vouchers[key] == true
end

-- ========================================================================= --
-- GET CURRENT POOL (EXACT port of get_current_pool, common_events.lua:1963)
-- ========================================================================= --

--- Build the current pool for a card type, applying all culling rules.
--- Returns: pool (list of keys), pool_key (string for RNG seed)
function Sim.CardFactory.get_current_pool(state, _type, _rarity, _legendary, _append)
    local pool = {}
    local starting_pool, pool_key = nil, ''

    if _type == 'Joker' then
        local rarity = _rarity or Sim.RNG.next(state.rng)
        rarity = (_legendary and 4) or (rarity > 0.95 and 3) or (rarity > 0.7 and 2) or 1
        starting_pool = Sim.JOKER_RARITY_POOLS[rarity]
        pool_key = 'Joker' .. rarity .. ((not _legendary and _append) or '')
    else
        if _type == 'Tarot' then starting_pool = Sim.TAROT_POOL
        elseif _type == 'Planet' then starting_pool = Sim.PLANET_POOL
        elseif _type == 'Spectral' then starting_pool = Sim.SPECTRAL_POOL
        elseif _type == 'Voucher' then starting_pool = Sim.VOUCHER_POOL
        else starting_pool = {}
        end
        pool_key = _type .. (_append or '')
    end

    if not starting_pool or #starting_pool == 0 then
        -- Fallback pools (real game line 2039-2049)
        if _type == 'Tarot' then return { 'c_strength' }, 'Tarot'
        elseif _type == 'Planet' then return { 'c_pluto' }, 'Planet'
        elseif _type == 'Spectral' then return { 'c_incantation' }, 'Spectral'
        elseif _type == 'Joker' then return { 'j_joker' }, 'Joker'
        elseif _type == 'Voucher' then return { 'v_blank' }, 'Voucher'
        else return { 'j_joker' }, 'Joker'
        end
    end

    -- Check for Showman
    local has_showman = #Sim.CardFactory.find_joker(state, 'j_ring_master') > 0

    -- Cull the pool (real game line 1976-2036)
    local pool_size = 0
    for _, key in ipairs(starting_pool) do
        local add = nil

        if _type == 'Joker' then
            local def = Sim.JOKER_DEFS[key]
            if not def then
                pool[#pool + 1] = 'UNAVAILABLE'
            elseif not (state._used_jokers and state._used_jokers[key]) and not has_showman then
                -- Joker not used and no Showman: include if unlocked
                if def.unlocked ~= false or def.rarity == 4 then
                    -- Enhancement gate check
                    if def.enhancement_gate then
                        -- Only include if deck has a card with this enhancement
                        local has_enhancement = false
                        for _, c in ipairs(state.deck) do
                            if c.enhancement == def.enhancement_gate then
                                has_enhancement = true
                                break
                            end
                        end
                        if has_enhancement then add = true end
                    else
                        add = true
                    end
                end
            elseif has_showman then
                -- Showman: include all jokers
                if def.unlocked ~= false or def.rarity == 4 then
                    if def.enhancement_gate then
                        local has_enhancement = false
                        for _, c in ipairs(state.deck) do
                            if c.enhancement == def.enhancement_gate then
                                has_enhancement = true
                                break
                            end
                        end
                        if has_enhancement then add = true end
                    else
                        add = true
                    end
                end
            end
            -- Black Hole and The Soul are never in normal pools
            if def and (def.key == 'j_black_hole' or def.key == 'j_the_soul') then
                add = nil
            end

        elseif _type == 'Voucher' then
            local def = Sim.Voucher.DEFS[key]
            if def then
                if not (state._used_vouchers and state._used_vouchers[key]) then
                    local include = true
                    -- Check prerequisites
                    if def.requires then
                        if not state._used_vouchers or not state._used_vouchers[def.requires] then
                            include = false
                        end
                    end
                    -- Check if already in shop
                    if state.shop and state.shop.voucher and state.shop.voucher == key then
                        include = false
                    end
                    if include then add = true end
                end
            end

        elseif _type == 'Planet' then
            local def = Sim.CONSUMABLE_DEFS[key]
            if def then
                -- Softlock: only include if hand type has been played
                if def.config and def.config.softlock then
                    local ht = def.config.hand_type
                    if ht and state.hand_type_counts and state.hand_type_counts[ht] and state.hand_type_counts[ht] > 0 then
                        add = true
                    end
                else
                    add = true
                end
            end

        elseif _type == 'Tarot' or _type == 'Spectral' then
            local def = Sim.CONSUMABLE_DEFS[key]
            if def then
                -- Black Hole and The Soul excluded from normal pools
                if def.key == 'c_black_hole' or def.key == 'c_soul' then
                    add = nil
                else
                    add = true
                end
            end
        end

        -- Pool flags
        if _type == 'Joker' then
            local def = Sim.JOKER_DEFS[key]
            if def then
                if def.no_pool_flag and state._pool_flags and state._pool_flags[def.no_pool_flag] then add = nil end
                if def.yes_pool_flag and state._pool_flags and not state._pool_flags[def.yes_pool_flag] then add = nil end
            end
        end

        -- Banned keys
        if state._banned_keys and state._banned_keys[key] then add = nil end

        if add then
            pool[#pool + 1] = key
            pool_size = pool_size + 1
        else
            pool[#pool + 1] = 'UNAVAILABLE'
        end
    end

    -- If pool is empty, use fallback
    if pool_size == 0 then
        if _type == 'Tarot' then return { 'c_strength' }, 'Tarot'
        elseif _type == 'Planet' then return { 'c_pluto' }, 'Planet'
        elseif _type == 'Spectral' then return { 'c_incantation' }, 'Spectral'
        elseif _type == 'Joker' then return { 'j_joker' }, 'Joker'
        elseif _type == 'Voucher' then return { 'v_blank' }, 'Voucher'
        else return { 'j_joker' }, 'Joker'
        end
    end

    return pool, pool_key .. (not _legendary and (state.ante or 1) or '')
end

-- ========================================================================= --
-- RARITY ROLL (EXACT port)
-- ========================================================================= --

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

-- ========================================================================= --
-- EDITION ROLL (EXACT port of poll_edition, common_events.lua:2055)
-- ========================================================================= --

--- Roll edition for a card.
--- _key: RNG seed key
--- _mod: multiplier (default 1)
--- _no_neg: if true, never roll negative
--- _guaranteed: if true, use fixed thresholds (for packs)
function Sim.CardFactory.roll_edition(state, rng, _key, _mod, _no_neg, _guaranteed)
    _mod = _mod or 1
    local p = Sim.RNG.next(rng)
    local er = state._edition_rate or 1.0
    if _guaranteed then
        if p > 1 - 0.003 * 25 and not _no_neg then return { negative = true }
        elseif p > 1 - 0.006 * 25 then return { polychrome = true }
        elseif p > 1 - 0.02 * 25 then return { holo = true }
        elseif p > 1 - 0.04 * 25 then return { foil = true }
        end
    else
        if p > 1 - 0.003 * _mod and not _no_neg then return { negative = true }
        elseif p > 1 - 0.006 * er * _mod then return { polychrome = true }
        elseif p > 1 - 0.02 * er * _mod then return { holo = true }
        elseif p > 1 - 0.04 * er * _mod then return { foil = true }
        end
    end
    return nil
end

-- ========================================================================= --
-- STICKER ROLL (EXACT port of create_card sticker logic, common_events.lua:2133)
-- ========================================================================= --

function Sim.CardFactory.roll_stickers(state, rng, area)
    local eternal = false
    local perishable = false
    local rental = false

    if state.modifiers and state.modifiers.all_eternal then
        eternal = true
    end

    if area == "shop_jokers" or area == "pack_cards" then
        local epp = Sim.RNG.next(rng)
        if state.modifiers and state.modifiers.enable_eternals and epp > 0.7 then
            eternal = true
        elseif state.modifiers and state.modifiers.enable_perishables and epp > 0.4 and epp <= 0.7 then
            perishable = true
        end
        if state.modifiers and state.modifiers.enable_rentals and Sim.RNG.next(rng) > 0.7 then
            rental = true
        end
    end

    return eternal, perishable, rental
end

-- ========================================================================= --
-- SOUL / BLACK HOLE CHECK (EXACT port of create_card, common_events.lua:2088)
-- ========================================================================= --

function Sim.CardFactory.check_soul(state, rng, _type, _append)
    -- Soul: 0.3% when creating Tarot or Spectral
    if _type == 'Tarot' or _type == 'Spectral' then
        -- Check if c_soul is already used and no Showman
        local soul_used = state._used_jokers and state._used_jokers['c_soul']
        local has_showman = #Sim.CardFactory.find_joker(state, 'j_ring_master') > 0
        if not soul_used or has_showman then
            if Sim.RNG.next(rng) > 0.997 then
                return 'c_soul'
            end
        end
    end
    -- Black Hole: 0.3% when creating Planet or Spectral
    if _type == 'Planet' or _type == 'Spectral' then
        local bh_used = state._used_jokers and state._used_jokers['c_black_hole']
        local has_showman = #Sim.CardFactory.find_joker(state, 'j_ring_master') > 0
        if not bh_used or has_showman then
            if Sim.RNG.next(rng) > 0.997 then
                return 'c_black_hole'
            end
        end
    end
    return nil
end

-- ========================================================================= --
-- CREATE CARD (EXACT port of create_card, common_events.lua:2082)
-- ========================================================================= --

function Sim.CardFactory.create(card_type, state, rng, opts)
    opts = opts or {}
    local area = opts.area or ""
    local soulable = opts.soulable
    local forced_key = opts.force_key
    local key_append = opts.key_append or ""
    local _rarity = opts.rarity
    local legendary = opts.legendary or false

    -- Default soulable
    if soulable == nil and (card_type == "Tarot" or card_type == "Planet" or card_type == "Spectral") then
        soulable = true
    end
    if soulable == nil then soulable = false end

    -- Soul / Black Hole check
    if soulable and not forced_key then
        local soul_key = Sim.CardFactory.check_soul(state, rng, card_type, key_append)
        if soul_key then
            forced_key = soul_key
        end
    end

    -- Base type
    if card_type == 'Base' then
        forced_key = 'c_base'
    end

    local center_key = nil

    if forced_key then
        -- Check if banned
        if not (state._banned_keys and state._banned_keys[forced_key]) then
            center_key = forced_key
        end
    end

    if not center_key then
        -- Get pool and pick
        local pool, pool_key = Sim.CardFactory.get_current_pool(state, card_type, _rarity, legendary, key_append)
        center_key = Sim.RNG.pick(rng, pool)
        local it = 1
        while center_key == 'UNAVAILABLE' do
            it = it + 1
            center_key = Sim.RNG.pick(rng, pool)
        end
    end

    if not center_key then return nil end

    -- Create the card
    if card_type == "Joker" then
        local def = Sim.JOKER_DEFS[center_key]
        if not def then return nil end

        -- Roll edition
        local edition = Sim.CardFactory.roll_edition(state, rng, 'edi' .. key_append .. (state.ante or 1))

        -- Roll stickers
        local eternal, perishable, rental = Sim.CardFactory.roll_stickers(state, rng, area)

        state._uid_n = (state._uid_n or 0) + 1
        return {
            id = def.id, edition = edition and (edition.negative and 4 or edition.polychrome and 3 or edition.holo and 2 or edition.foil and 1 or 0) or 0,
            eternal = eternal, perishable = perishable, rental = rental,
            uid = state._uid_n, _new = true
        }

    elseif card_type == "Tarot" or card_type == "Planet" or card_type == "Spectral" then
        local def = Sim.CONSUMABLE_DEFS[center_key]
        if not def then return nil end

        state._uid_n = (state._uid_n or 0) + 1
        return { id = def.id, uid = state._uid_n, _new = true }

    elseif card_type == "Playing Card" then
        local roll = Sim.RNG.pick(rng, Sim.PLAYING_CARD_POOL)
        state._uid_n = (state._uid_n or 0) + 1
        return Sim.Card.new(roll.rank, roll.suit, 0, 0, 0, state._uid_n)

    elseif card_type == "Voucher" then
        local def = Sim.Voucher.DEFS[center_key]
        if not def then return nil end
        return { key = center_key, _new = true }
    end

    return nil
end

-- ========================================================================= --
-- UTILITY FUNCTIONS
-- ========================================================================= --

function Sim.CardFactory.count_enhancement(state, enhancement)
    local count = 0
    for _, c in ipairs(state.deck) do
        if c.enhancement == enhancement then count = count + 1 end
    end
    return count
end

function Sim.CardFactory.count_suit(state, suit)
    local count = 0
    for _, c in ipairs(state.deck) do
        if c.suit == suit then count = count + 1 end
    end
    return count
end
