--[[
    balatro_lua_sim.lua
    EXACT Balatro shop logic ported from source.
    Uses a deterministic random stream (not math.random).
    Outputs results as JSON lines for comparison with Python.
    
    Run: lua balatro_lua_sim.lua > lua_output.jsonl
]]

-- ============================================================================
-- DETERMINISTIC RANDOM STREAM
-- ============================================================================
local random_stream = {}
local stream_idx = 0

function load_random_stream(filename)
    random_stream = {}
    for line in io.lines(filename) do
        random_stream[#random_stream + 1] = tonumber(line)
    end
    stream_idx = 0
end

function next_float()
    stream_idx = stream_idx + 1
    return random_stream[stream_idx] or 0
end

function next_int(min, max)
    return min + math.floor(next_float() * (max - min + 1))
end

-- ============================================================================
-- UTILITY
-- ============================================================================
function shallow_copy(t)
    local c = {}
    for k,v in pairs(t) do c[k] = v end
    return c
end

-- ============================================================================
-- GAME STATE (mirrors G.GAME)
-- ============================================================================
local G = {
    GAME = {
        edition_rate = 1,
        joker_rate = 20,
        tarot_rate = 4,
        planet_rate = 4,
        spectral_rate = 0,
        playing_card_rate = 0,
        discount_percent = 0,
        interest_cap = 25,
        interest_amount = 1,
        inflation = 0,
        round_resets = {
            ante = 1,
            reroll_cost = 1,
            temp_reroll_cost = nil,
        },
        current_round = {
            reroll_cost_increase = 0,
            free_rerolls = 0,
        },
        used_jokers = {},
        used_vouchers = {},
        banned_keys = {},
        pool_flags = {},
        modifiers = {
            enable_eternals_in_shop = false,
            enable_perishables_in_shop = false,
            enable_rentals_in_shop = false,
            all_eternal = false,
        },
        perishable_rounds = 5,
        rental_rate = 3,
        probabilities = { normal = 1 },
    },
    jokers = { cards = {} },
    consumeables = { cards = {} },
}

-- Pool data
local JOKER_RARITY_POOLS = {
    [1] = {}, [2] = {}, [3] = {}, [4] = {}
}
for i = 1, 60 do JOKER_RARITY_POOLS[1][i] = "j_common_" .. i end
for i = 1, 60 do JOKER_RARITY_POOLS[2][i] = "j_uncommon_" .. i end
for i = 1, 20 do JOKER_RARITY_POOLS[3][i] = "j_rare_" .. i end
for i = 1, 5  do JOKER_RARITY_POOLS[4][i] = "j_legendary_" .. i end

local TAROT_KEYS = {}
for i = 1, 22 do TAROT_KEYS[i] = "c_tarot_" .. i end

local PLANET_KEYS = {}
for i = 1, 12 do PLANET_KEYS[i] = "c_planet_" .. i end

local SPECTRAL_KEYS = {}
for i = 1, 18 do SPECTRAL_KEYS[i] = "c_spectral_" .. i end

-- Card cost lookup
local JOKER_COSTS = {}
for i = 1, 60 do JOKER_COSTS["j_common_" .. i] = 3 + (i % 4) end
for i = 1, 60 do JOKER_COSTS["j_uncommon_" .. i] = 5 + (i % 4) end
for i = 1, 20 do JOKER_COSTS["j_rare_" .. i] = 7 + (i % 3) end
for i = 1, 5  do JOKER_COSTS["j_legendary_" .. i] = 8 end

-- ============================================================================
-- EMPTY() from misc_functions.lua:129
-- ============================================================================
local temp_pool_storage = {}
function EMPTY(t)
    if not t then return {} end
    for k in pairs(t) do t[k] = nil end
    return t
end

-- ============================================================================
-- get_current_pool EXACT PORT (common_events.lua:1963-2053)
-- ============================================================================
function get_current_pool(_type, _rarity, _legendary, _append, ante)
    local _pool = EMPTY(temp_pool_storage)
    local _starting_pool, _pool_key, _pool_size = nil, '', 0

    if _type == 'Joker' then
        local rarity = _rarity
        if rarity == nil then
            rarity = next_float()
        end
        rarity = (_legendary and 4) or (rarity > 0.95 and 3) or (rarity > 0.7 and 2) or 1
        _starting_pool = JOKER_RARITY_POOLS[rarity]
        _pool_key = 'Joker' .. rarity .. ((_legendary and '') or (_append or ''))
    else
        if _type == 'Tarot' then _starting_pool = TAROT_KEYS
        elseif _type == 'Planet' then _starting_pool = PLANET_KEYS
        elseif _type == 'Spectral' then _starting_pool = SPECTRAL_KEYS
        elseif _type == 'Enhanced' then _starting_pool = {}
        else _starting_pool = {}
        end
        _pool_key = _type .. (_append or '')
    end

    if not _starting_pool then _starting_pool = {} end

    for k, v in ipairs(_starting_pool) do
        local add = nil
        if _type == 'Enhanced' then
            add = true
        elseif not (G.GAME.used_jokers[v] and #find_joker("Showman") == 0) then
            if v:sub(1,2) == 'c_' then
                if v ~= 'c_soul' and v ~= 'c_black_hole' then
                    add = true
                end
            elseif v:sub(1,2) == 'v_' then
                if not G.GAME.used_vouchers[v] then
                    add = true
                end
            else
                add = true
            end
        end

        if G.GAME.banned_keys[v] then add = nil end

        if add then
            _pool[#_pool + 1] = v
            _pool_size = _pool_size + 1
        else
            _pool[#_pool + 1] = 'UNAVAILABLE'
        end
    end

    if _pool_size == 0 then
        _pool = EMPTY(temp_pool_storage)
        if _type == 'Tarot' or _type == 'Tarot_Planet' then
            _pool[1] = "c_tarot_1"
        elseif _type == 'Planet' then
            _pool[1] = "c_planet_12"
        elseif _type == 'Spectral' then
            _pool[1] = "c_spectral_1"
        elseif _type == 'Joker' then
            _pool[1] = "j_common_1"
        else
            _pool[1] = "j_common_1"
        end
    end

    return _pool, _pool_key .. (not _legendary and tostring(ante) or '')
end

-- ============================================================================
-- find_joker stub (misc_functions.lua:903)
-- ============================================================================
function find_joker(name)
    local results = {}
    for _, v in pairs(G.jokers.cards) do
        if v.ability and v.ability.name == name then
            results[#results + 1] = v
        end
    end
    for _, v in pairs(G.consumeables.cards) do
        if v.ability and v.ability.name == name then
            results[#results + 1] = v
        end
    end
    return results
end

-- ============================================================================
-- poll_edition EXACT PORT (common_events.lua:2055-2080)
-- ============================================================================
function poll_edition(_key, _mod, _no_neg, _guaranteed)
    _mod = _mod or 1
    local edition_poll = next_float()
    if _guaranteed then
        if edition_poll > 1 - 0.003*25 and not _no_neg then
            return {negative = true}
        elseif edition_poll > 1 - 0.006*25 then
            return {polychrome = true}
        elseif edition_poll > 1 - 0.02*25 then
            return {holo = true}
        elseif edition_poll > 1 - 0.04*25 then
            return {foil = true}
        end
    else
        if edition_poll > 1 - 0.003*_mod and not _no_neg then
            return {negative = true}
        elseif edition_poll > 1 - 0.006*G.GAME.edition_rate*_mod then
            return {polychrome = true}
        elseif edition_poll > 1 - 0.02*G.GAME.edition_rate*_mod then
            return {holo = true}
        elseif edition_poll > 1 - 0.04*G.GAME.edition_rate*_mod then
            return {foil = true}
        end
    end
    return nil
end

-- ============================================================================
-- create_card EXACT PORT (common_events.lua:2082-2154)
-- ============================================================================
function create_card(_type, area, legendary, _rarity, skip_materialize, soulable, forced_key, key_append, ante)
    local center_key = nil

    -- Soul / Black Hole check (lines 2088-2101)
    if not forced_key and soulable and not G.GAME.banned_keys['c_soul'] then
        if (_type == 'Tarot' or _type == 'Spectral' or _type == 'Tarot_Planet') and
           not (G.GAME.used_jokers['c_soul'] and #find_joker("Showman") == 0) then
            if next_float() > 0.997 then
                forced_key = 'c_soul'
            end
        end
        if (_type == 'Planet' or _type == 'Spectral') and
           not (G.GAME.used_jokers['c_black_hole'] and #find_joker("Showman") == 0) then
            if next_float() > 0.997 then
                forced_key = 'c_black_hole'
            end
        end
    end

    if _type == 'Base' then
        forced_key = 'c_base'
    end

    -- Pool selection (lines 2109-2122)
    if forced_key and not G.GAME.banned_keys[forced_key] then
        center_key = forced_key
    else
        local _pool, _pool_key = get_current_pool(_type, _rarity, legendary, key_append, ante)
        -- pseudorandom_element: pick random from pool
        local idx = next_int(1, #_pool)
        center_key = _pool[idx]
        local it = 1
        while center_key == 'UNAVAILABLE' do
            it = it + 1
            idx = next_int(1, #_pool)
            center_key = _pool[idx]
        end
    end

    -- Sticker polling (lines 2133-2147)
    local edition = nil
    local eternal = false
    local perishable = false
    local rental = false

    if _type == 'Joker' then
        if G.GAME.modifiers.all_eternal then
            eternal = true
        end

        if area == 'shop_jokers' or area == 'pack_cards' then
            local eternal_perishable_poll = next_float()
            if G.GAME.modifiers.enable_eternals_in_shop and eternal_perishable_poll > 0.7 then
                eternal = true
            elseif G.GAME.modifiers.enable_perishables_in_shop and
                   (eternal_perishable_poll > 0.4) and (eternal_perishable_poll <= 0.7) then
                perishable = true
            end
            if G.GAME.modifiers.enable_rentals_in_shop and next_float() > 0.7 then
                rental = true
            end
        end

        edition = poll_edition('edi' .. (key_append or '') .. tostring(ante))
    end

    return {
        key = center_key,
        type = _type,
        edition = edition,
        eternal = eternal,
        perishable = perishable,
        rental = rental,
    }
end

-- ============================================================================
-- create_card_for_shop EXACT PORT (UI_definitions.lua:742-800)
-- ============================================================================
function create_card_for_shop(area, ante)
    local spectral_rate = G.GAME.spectral_rate or 0
    local total_rate = G.GAME.joker_rate + G.GAME.tarot_rate + G.GAME.planet_rate +
                       G.GAME.playing_card_rate + spectral_rate
    local polled_rate = next_float() * total_rate
    local check_rate = 0

    local card_types = {
        {type = 'Joker',  val = G.GAME.joker_rate},
        {type = 'Tarot',  val = G.GAME.tarot_rate},
        {type = 'Planet', val = G.GAME.planet_rate},
        {type = 'Base',   val = G.GAME.playing_card_rate},
        {type = 'Spectral', val = spectral_rate},
    }

    local selected_type = 'Joker'
    for _, ct in ipairs(card_types) do
        if polled_rate > check_rate and polled_rate <= check_rate + ct.val then
            selected_type = ct.type
            break
        end
        check_rate = check_rate + ct.val
    end

    local card = create_card(selected_type, area, nil, nil, nil, true, nil, 'sho', ante)
    card.shop_type = selected_type
    return card
end

-- ============================================================================
-- set_cost EXACT PORT (card.lua:369-385)
-- ============================================================================
function calc_cost(base_cost, edition, rental, couponed)
    local extra_cost = 0 + G.GAME.inflation
    if edition then
        if edition.holo then extra_cost = extra_cost + 3 end
        if edition.foil then extra_cost = extra_cost + 2 end
        if edition.polychrome then extra_cost = extra_cost + 5 end
        if edition.negative then extra_cost = extra_cost + 5 end
    end
    local cost = math.max(1, math.floor((base_cost + extra_cost + 0.5) *
                (100 - G.GAME.discount_percent) / 100))
    if rental then cost = 1 end
    if couponed then cost = 0 end
    local sell_cost = math.max(1, math.floor(cost / 2))
    return cost, sell_cost
end

-- ============================================================================
-- calculate_reroll_cost EXACT PORT (common_events.lua:2263-2269)
-- ============================================================================
function calculate_reroll_cost(free_rerolls, reroll_cost_increase, skip_increment)
    if free_rerolls < 0 then free_rerolls = 0 end
    if free_rerolls > 0 then return 0, reroll_cost_increase end
    if not skip_increment then
        reroll_cost_increase = reroll_cost_increase + 1
    end
    local base = G.GAME.round_resets.temp_reroll_cost or G.GAME.round_resets.reroll_cost
    return base + reroll_cost_increase, reroll_cost_increase
end

-- ============================================================================
-- interest EXACT PORT (state_events.lua:1191-1203)
-- ============================================================================
function calc_interest(dollars)
    if dollars < 5 then return 0 end
    return G.GAME.interest_amount * math.min(
        math.floor(dollars / 5),
        G.GAME.interest_cap / 5
    )
end

-- ============================================================================
-- JSON OUTPUT HELPER
-- ============================================================================
function edition_to_str(ed)
    if not ed then return "null" end
    if ed.negative then return "negative" end
    if ed.polychrome then return "polychrome" end
    if ed.holo then return "holo" end
    if ed.foil then return "foil" end
    return "unknown"
end

function card_to_json(card)
    return string.format(
        '{"key":"%s","type":"%s","shop_type":"%s","edition":%s,"eternal":%s,"perishable":%s,"rental":%s}',
        card.key or "",
        card.type or "",
        card.shop_type or "",
        edition_to_str(card.edition) == "null" and "null" or ('"' .. edition_to_str(card.edition) .. '"'),
        card.eternal and "true" or "false",
        card.perishable and "true" or "false",
        card.rental and "true" or "false"
    )
end

-- ============================================================================
-- MAIN: Run test scenarios
-- ============================================================================
function run_test(test_name, seed_file, test_func)
    load_random_stream(seed_file)
    test_func()
end

-- Generate random stream file
function generate_stream(filename, count)
    local f = io.open(filename, "w")
    math.randomseed(12345)
    for i = 1, count do
        f:write(string.format("%.17g\n", math.random()))
    end
    f:close()
end

-- ============================================================================
-- RUN
-- ============================================================================
-- Generate random stream
generate_stream("random_stream.txt", 1000000)

-- Load it
load_random_stream("random_stream.txt")

local ante = 1

-- Test 1: Card type distribution (10000 iterations)
io.write('{"test":"type_dist","data":[\n')
for i = 1, 10000 do
    -- Reset state for each iteration
    G.GAME.used_jokers = {}
    G.GAME.banned_keys = {}
    local card = create_card_for_shop('shop_jokers', ante)
    io.write(card_to_json(card))
    if i < 10000 then io.write(",\n") end
end
io.write('\n]}\n')

-- Test 2: Edition distribution - non-guaranteed (100000 iterations)
-- Reset stream position
load_random_stream("random_stream.txt")
io.write('{"test":"edition_nonguaranteed","data":[\n')
for i = 1, 100000 do
    local ed = poll_edition('test', 1, false, false)
    io.write('"' .. edition_to_str(ed) .. '"')
    if i < 100000 then io.write(",") end
    if i % 100 == 0 then io.write("\n") end
end
io.write('\n]}\n')

-- Test 3: Edition distribution - guaranteed (100000 iterations)
load_random_stream("random_stream.txt")
io.write('{"test":"edition_guaranteed","data":[\n')
for i = 1, 100000 do
    local ed = poll_edition('test', 1, false, true)
    io.write('"' .. edition_to_str(ed) .. '"')
    if i < 100000 then io.write(",") end
    if i % 100 == 0 then io.write("\n") end
end
io.write('\n]}\n')

-- Test 4: Soul/Black Hole (100000 iterations)
load_random_stream("random_stream.txt")
io.write('{"test":"soul_check","data":[\n')
for i = 1, 100000 do
    G.GAME.used_jokers = {}
    G.GAME.banned_keys = {}
    local card = create_card('Tarot', 'shop_jokers', nil, nil, nil, true, nil, '', ante)
    io.write('"' .. card.key .. '"')
    if i < 100000 then io.write(",") end
    if i % 100 == 0 then io.write("\n") end
end
io.write('\n]}\n')

-- Test 5: Sticker polling (100000 iterations)
load_random_stream("random_stream.txt")
G.GAME.modifiers.enable_eternals_in_shop = true
G.GAME.modifiers.enable_perishables_in_shop = true
G.GAME.modifiers.enable_rentals_in_shop = true
io.write('{"test":"stickers","data":[\n')
for i = 1, 100000 do
    G.GAME.used_jokers = {}
    local card = create_card('Joker', 'shop_jokers', nil, nil, nil, false, nil, '', ante)
    local sticker = "none"
    if card.eternal then sticker = "eternal"
    elseif card.perishable then sticker = "perishable"
    end
    local rental = card.rental and "rental" or "none"
    io.write('{"s":"' .. sticker .. '","r":"' .. rental .. '"}')
    if i < 100000 then io.write(",") end
    if i % 100 == 0 then io.write("\n") end
end
io.write('\n]}\n')

-- Test 6: Cost calculation (all combos)
G.GAME.modifiers.enable_eternals_in_shop = false
G.GAME.modifiers.enable_perishables_in_shop = false
G.GAME.modifiers.enable_rentals_in_shop = false
io.write('{"test":"costs","data":[\n')
local first = true
for _, base in ipairs({1,2,3,4,5,6,8,10}) do
    for _, ed_key in ipairs({"none","foil","holo","polychrome","negative"}) do
        for _, disc in ipairs({0,25,50,75}) do
            for _, infl in ipairs({0,1,2,3,4}) do
                G.GAME.discount_percent = disc
                G.GAME.inflation = infl
                local ed = nil
                if ed_key ~= "none" then ed = {[ed_key] = true} end
                local cost, sell = calc_cost(base, ed, false, false)
                if not first then io.write(",\n") end
                first = false
                io.write(string.format('{"b":%d,"e":"%s","d":%d,"i":%d,"c":%d,"s":%d}',
                    base, ed_key, disc, infl, cost, sell))
            end
        end
    end
end
io.write('\n]}\n')

-- Test 7: Reroll cost (20 iterations from fresh state)
io.write('{"test":"reroll","data":[\n')
local free = 0
local inc = 0
for i = 1, 20 do
    local cost, new_inc = calculate_reroll_cost(free, inc, false)
    inc = new_inc
    io.write(string.format('%d', cost))
    if i < 20 then io.write(",") end
end
io.write('\n]}\n')

-- Test 8: Interest
io.write('{"test":"interest","data":[\n')
local first = true
for _, d in ipairs({0,1,4,5,9,10,14,15,19,20,24,25,30,50,100}) do
    local interest = calc_interest(d)
    if not first then io.write(",") end
    first = false
    io.write(string.format('{"d":%d,"i":%d}', d, interest))
end
io.write('\n]}\n')

io.stderr:write("Lua done.\n")
