-- src/12_env.lua — Gymnasium env (reset/step/handlers)

Sim.Env = {}
Sim.Env.action_spec = {
    types = { "SELECT_CARDS","PLAY_DISCARD","SHOP_ACTION","USE_CONSUMABLE","PHASE_ACTION" },
    obs_dim = 180,
}

local E = Sim.ENUMS

function Sim.Env.reset(seed)
    local rng = Sim.RNG.new(seed)
    local state = Sim.State.new({ rng = rng, seed = seed })
    Sim.Blind.init_ante(state)
    local btype = Sim.Blind.next_type(state)
    if btype then
        Sim.Blind.setup(state, btype)
        state.phase = E.PHASE.SELECTING_HAND
    end
    return Sim.Obs.encode(state), { seed = seed, ante = state.ante }
end

function Sim._do_reorder(state, value)
    local R = E.REWARD
    local src  = (value & 0xF) + 1         -- bits 0-3: source (0-indexed → 1-indexed)
    local tgt  = ((value >> 4) & 0xF) + 1  -- bits 4-7: target
    local mode = (value >> 8) & 1          -- bit 8: 0=swap, 1=insert
    local area = (value >> 9) & 1          -- bit 9: 0=hand, 1=jokers

    local arr
    if area == 1 then arr = state.jokers else arr = state.hand end

    if src < 1 or src > #arr or tgt < 1 or tgt > #arr or src == tgt then
        return Sim.Obs.encode(state), R.INVALID, false
    end

    if mode == 0 then
        arr[src], arr[tgt] = arr[tgt], arr[src]
    else
        local item = table.remove(arr, src)
        table.insert(arr, tgt, item)
    end
    return Sim.Obs.encode(state), 0, false
end

function Sim._use_consumable(state, cons_index)
    local R = E.REWARD
    local cs = state.consumables[cons_index]
    if not cs then
        return Sim.Obs.encode(state), R.INVALID, false
    end
    local def = Sim._CONS_BY_ID[cs.id]
    if not def then
        return Sim.Obs.encode(state), R.INVALID, false
    end

    -- For Empress, we need selected cards from state.selection
    local ctx = { selected = state.selection }
    local fx = def.effect(ctx, state)

    -- Track last consumable for Fool
    if def.key ~= "c_fool" then
        state.last_consumable = cs.id
    end

    -- Remove the consumable
    table.remove(state.consumables, cons_index)

    return Sim.Obs.encode(state), 0, false
end

local function _step_selecting(state, atype, value)
    local R = E.REWARD

    if atype == E.ACTION.SELECT_CARDS then
        -- value = 8-bit bitmask
        local sel = {}
        for i = 0, 7 do
            if (value >> i) & 1 == 1 and state.hand[i+1] then
                sel[#sel+1] = i + 1
            end
        end
        state.selection = sel
        return Sim.Obs.encode(state), 0, false

    elseif atype == E.ACTION.PLAY_DISCARD then
        if #state.selection == 0 then
            return Sim.Obs.encode(state), R.INVALID, false
        end

        -- Sort selections descending for safe removal
        local sorted = {}
        for _, v in ipairs(state.selection) do sorted[#sorted+1] = v end
        table.sort(sorted, function(a,b) return a > b end)

        if value == 1 then
            -- PLAY
            if state.hands_left <= 0 then
                return Sim.Obs.encode(state), R.INVALID, false
            end
            local played = {}
            for _, idx in ipairs(sorted) do
                played[#played+1] = state.hand[idx]
                table.remove(state.hand, idx)
            end

            -- Boss: The Arm (decrease hand level before scoring)
            Sim.Blind.on_play(state, played)

            local total, chips, mult, ht, scoring, all_h =
                Sim.Engine.calculate(state, played)

            state.total_chips = state.total_chips + total
            state.chips = state.chips + total
            state.hands_left = state.hands_left - 1
            state.hands_played = state.hands_played + 1
            state.hand_type_counts[ht] = (state.hand_type_counts[ht] or 0) + 1

            -- Ride the Bus: reset on face cards, increment otherwise
            local has_face = false
            for _, c in ipairs(played) do
                if c.rank >= E.RANK.JACK and c.rank <= E.RANK.KING then has_face = true; break end
            end
            if has_face then
                state.ride_the_bus = 0
            else
                state.ride_the_bus = (state.ride_the_bus or 0) + 1
            end

            -- Glass card destruction (1/4 chance per Glass card)
            local destroyed = {}
            for _, c in ipairs(played) do
                if c.enhancement == E.ENHANCEMENT.GLASS and not Sim.Blind.is_card_debuffed(state, c) then
                    if state.rng and Sim.RNG.next(state.rng) < 0.25 then
                        destroyed[c] = true
                    end
                end
            end

            -- Add played cards to discard (except destroyed ones)
            for _, c in ipairs(played) do
                if not destroyed[c] then
                    state.discard[#state.discard+1] = c
                else
                    state.deck_count = state.deck_count - 1
                end
            end
            Sim.State.draw(state)
            state.selection = {}

            -- Boss: The Hook (discard 2 random cards after playing)
            Sim.Blind.on_after_play(state)

            -- Joker "play" triggers
            if state.jokers then
                for ji = 1, #state.jokers do
                    local jk = state.jokers[ji]
                    local def = Sim._JOKER_BY_ID[jk.id]
                    if def and def.apply then
                        local ctx = { after_play = true, hand_type = ht, scoring = scoring }
                        local fx = def.apply(ctx, state, jk)
                        if fx then
                            if fx.level_up then
                                Sim.State.level_up(state, fx.level_up)
                            end
                            if fx.chip_mod then
                                state.chips = state.chips + fx.chip_mod
                                total = total + fx.chip_mod
                            end
                            -- Note: after_play jokers should return chip_mod, not mult_mod.
                            -- Mult is already finalized at this point.
                        end
                    end
                end
            end

            local reward = math.log(math.max(1, total)) * R.HAND_SCORED
            -- Efficiency bonus: fewer hands = better
            reward = reward - 0.05 * state.hands_played
            local done = false

            if state.chips >= state.blind_chips then
                state.blind_beaten = true
                reward = reward + R.BLIND_BEATEN
                -- Dollar bonus for beating blind quickly
                reward = reward + math.log(math.max(1, state.dollars)) * 0.05
            end

            if state.hands_left <= 0 and not state.blind_beaten then
                done = true
                reward = reward + R.GAME_OVER
            end

            return Sim.Obs.encode(state), reward, done

        elseif value == 2 then
            -- DISCARD
            if state.discards_left <= 0 then
                return Sim.Obs.encode(state), R.INVALID, false
            end

            -- Determine discarded hand type BEFORE removing cards
            local disc_cards = {}
            for _, idx in ipairs(sorted) do
                disc_cards[#disc_cards+1] = state.hand[idx]
            end
            local disc_ht = Sim.Eval.get_hand(disc_cards, state)

            -- Trigger Burnt Joker (on_discard, is_first_discard) and Ramen
            local num_discarded = #sorted
            local destroyed_jokers = {}
            if state.jokers then
                for ji = 1, #state.jokers do
                    local jk = state.jokers[ji]
                    local def = Sim._JOKER_BY_ID[jk.id]
                    if def and def.apply then
                        local ctx = {
                            on_discard = true,
                            is_first_discard = (state.discards_left == Sim.DEFAULTS.discards),
                            discarded_hand_type = disc_ht,
                            cards_discarded = num_discarded,
                        }
                        local fx = def.apply(ctx, state, jk)
                        if fx then
                            if fx.level_up then
                                Sim.State.level_up(state, fx.level_up)
                            end
                            if fx.destroy_self then
                                destroyed_jokers[#destroyed_jokers+1] = ji
                            end
                        end
                    end
                end
            end
            -- Remove destroyed jokers (reverse order)
            for i = #destroyed_jokers, 1, -1 do
                table.remove(state.jokers, destroyed_jokers[i])
            end

            for _, idx in ipairs(sorted) do
                local c = table.remove(state.hand, idx)
                if c then state.discard[#state.discard+1] = c end
            end
            state.discards_left = state.discards_left - 1
            Sim.State.draw(state)
            state.selection = {}

            return Sim.Obs.encode(state), 0, false
        end

        return Sim.Obs.encode(state), R.INVALID, false

    elseif atype == E.ACTION.PHASE_ACTION then
        -- value 3 = next (after blind beaten)
        if value == 3 and state.blind_beaten then
            return Sim._advance_blind(state)
        end

    elseif atype == E.ACTION.USE_CONSUMABLE then
        return Sim._use_consumable(state, value)

    elseif atype == E.ACTION.REORDER then
        return Sim._do_reorder(state, value)
    end

    return Sim.Obs.encode(state), R.INVALID, false
end

function Sim._advance_blind(state)
    local R = E.REWARD
    local names = {"Small","Big","Boss"}
    local bname = state.blind_type
    for i = 1, 3 do
        if names[i] == bname then Sim.Blind.mark_done(state, i); break end
    end

    -- Collect blind reward + interest
    local reward_dollars = Sim.Blind.reward(
        bname=="Small" and 1 or bname=="Big" and 2 or 3)
    state.dollars = state.dollars + reward_dollars + Sim.State.interest(state)

    -- Round-end joker effects (Delayed Gratification, etc.)
    if state.jokers then
        for ji = 1, #state.jokers do
            local jk = state.jokers[ji]
            local def = Sim._JOKER_BY_ID[jk.id]
            if def and def.apply then
                local ctx = { round_end = true }
                local fx = def.apply(ctx, state, jk)
                if fx and fx.dollars then
                    state.dollars = state.dollars + fx.dollars
                end
            end
        end
    end

    -- Move played cards to discard, clear hand
    for _, c in ipairs(state.hand) do state.discard[#state.discard+1] = c end
    state.hand = {}
    state.selection = {}

    local next_btype = Sim.Blind.next_type(state)
    if not next_btype then
        -- Ante complete
        state.ante = state.ante + 1
        if state.ante > 8 then
            state.phase = E.PHASE.WIN
            return Sim.Obs.encode(state), R.GAME_WON, true
        end
        Sim.Blind.init_ante(state)
        next_btype = Sim.Blind.next_type(state)
        -- Voucher reset would go here
        Sim.Shop.generate(state)
        state.phase = E.PHASE.SHOP
        return Sim.Obs.encode(state), R.ANTE_UP, false
    else
        Sim.Blind.setup(state, next_btype)
        state.phase = E.PHASE.SELECTING_HAND
        return Sim.Obs.encode(state), 0, false
    end
end

local function _step_shop(state, atype, value)
    local R = E.REWARD

    if atype == E.ACTION.SHOP_ACTION then
        if value == 0 then
            Sim.Shop.reroll(state)
            return Sim.Obs.encode(state), 0, false
        elseif value >= 1 and value <= 2 then
            if Sim.Shop.buy_joker(state, value) then
                return Sim.Obs.encode(state), 0, false
            end
            return Sim.Obs.encode(state), R.INVALID, false
        elseif value == 3 then
            if Sim.Shop.buy_booster(state) then
                return Sim.Obs.encode(state), 0, false
            end
            return Sim.Obs.encode(state), R.INVALID, false
        elseif value == 4 then
            -- Buy consumable
            if Sim.Shop.buy_consumable(state) then
                return Sim.Obs.encode(state), 0, false
            end
            return Sim.Obs.encode(state), R.INVALID, false
        elseif value <= -1 and value >= -5 then
            if Sim.Shop.sell_joker(state, -value) then
                return Sim.Obs.encode(state), 0, false
            end
            return Sim.Obs.encode(state), R.INVALID, false
        end

    elseif atype == E.ACTION.USE_CONSUMABLE then
        -- Use consumable from area (not from shop)
        return Sim._use_consumable(state, value)

    elseif atype == E.ACTION.REORDER then
        return Sim._do_reorder(state, value)

    elseif atype == E.ACTION.PHASE_ACTION and value == 0 then
        -- End shop — fire ending_shop context for jokers (Perkeo, etc.)
        if state.jokers then
            for ji = 1, #state.jokers do
                local jk = state.jokers[ji]
                local def = Sim._JOKER_BY_ID[jk.id]
                if def and def.apply then
                    local ctx = { ending_shop = true, my_joker_index = ji }
                    def.apply(ctx, state, jk)
                end
            end
        end
        state.shop = nil
        local next_btype = Sim.Blind.next_type(state)
        if next_btype then
            Sim.Blind.setup(state, next_btype)
            state.phase = E.PHASE.SELECTING_HAND
        end
        return Sim.Obs.encode(state), 0, false
    end

    return Sim.Obs.encode(state), R.INVALID, false
end

local function _step_pack(state, atype, value)
    local R = E.REWARD

    if atype == E.ACTION.SELECT_CARDS then
        local idx = nil
        for i = 0, 2 do
            if (value >> i) & 1 == 1 then idx = i + 1; break end
        end
        if idx and Sim.Shop.select_pack(state, idx) then
            return Sim.Obs.encode(state), 0, false
        end
        return Sim.Obs.encode(state), R.INVALID, false

    elseif atype == E.ACTION.PHASE_ACTION and value == 0 then
        -- Skip pack
        Sim.Shop.skip_pack(state)
        return Sim.Obs.encode(state), 0, false
    end

    return Sim.Obs.encode(state), R.INVALID, false
end

function Sim.Env.step(state, atype, value)
    if state.phase == E.PHASE.SELECTING_HAND then
        return _step_selecting(state, atype, value)
    elseif state.phase == E.PHASE.SHOP then
        return _step_shop(state, atype, value)
    elseif state.phase == E.PHASE.PACK_OPEN then
        return _step_pack(state, atype, value)
    elseif state.phase == E.PHASE.BLIND_SELECT then
        -- Auto-start next blind
        local next_btype = Sim.Blind.next_type(state)
        if next_btype then
            Sim.Blind.setup(state, next_btype)
            state.phase = E.PHASE.SELECTING_HAND
        end
        return Sim.Obs.encode(state), 0, state.phase == E.PHASE.WIN
    end

    -- GAME_OVER or WIN
    return Sim.Obs.encode(state), 0, true
end

--- Simple env helpers (called from Python to avoid duplicated Lua logic)

--- Play cards by 1-indexed hand positions. Returns total score.
function Sim.play_cards_by_indices(state, indices)
    local played = {}
    for _, idx in ipairs(indices) do
        played[#played+1] = state.hand[idx]
    end
    local total, chips, mult, ht = Sim.Engine.calculate(state, played)
    state.total_chips = state.total_chips + total
    state.chips = state.chips + total
    state.hands_left = state.hands_left - 1
    state.hands_played = state.hands_played + 1
    state.hand_type_counts[ht] = (state.hand_type_counts[ht] or 0) + 1
    for _, c in ipairs(played) do state.discard[#state.discard+1] = c end
    table.sort(indices, function(a, b) return a > b end)
    for _, idx in ipairs(indices) do table.remove(state.hand, idx) end
    Sim.State.draw(state)
    if state.chips >= state.blind_chips then state.blind_beaten = true end
    return total
end

--- Discard the first n cards from hand.
function Sim.discard_first_n(state, n)
    n = math.min(n, #state.hand)
    for i = n, 1, -1 do
        local c = table.remove(state.hand, i)
        if c then state.discard[#state.discard+1] = c end
    end
    state.discards_left = state.discards_left - 1
    Sim.State.draw(state)
end

--- Auto-shop: buy affordable jokers/consumables, then advance.
function Sim.auto_shop(state)
    local shop = state.shop
    if shop then
        for si = 1, 2 do
            local jk = shop.jokers[si]
            if jk and state.dollars >= jk.cost and #state.jokers < state.joker_slots then
                Sim.Shop.buy_joker(state, si)
                break
            end
        end
        if shop.consumable and #state.consumables < state.consumable_slots then
            Sim.Shop.buy_consumable(state)
        end
    end
    state.shop = nil
    local bt = Sim.Blind.next_type(state)
    if bt then Sim.Blind.setup(state, bt); state.phase = E.PHASE.SELECTING_HAND end
end

--- Advance to next blind (simple env version, includes auto-shop on new ante).
function Sim.advance_simple(state)
    local names = {"Small", "Big", "Boss"}
    for i = 1, 3 do
        if names[i] == state.blind_type then Sim.Blind.mark_done(state, i); break end
    end
    local rd = Sim.Blind.reward(
        state.blind_type == "Small" and 1 or state.blind_type == "Big" and 2 or 3)
    state.dollars = state.dollars + rd + Sim.State.interest(state)
    for _, c in ipairs(state.hand) do state.discard[#state.discard+1] = c end
    state.hand = {}
    state.selection = {}
    local nb = Sim.Blind.next_type(state)
    if not nb then
        state.ante = state.ante + 1
        if state.ante > 8 then state.phase = E.PHASE.WIN; return end
        Sim.Blind.init_ante(state)
        nb = Sim.Blind.next_type(state)
        Sim.auto_shop(state)
    end
    Sim.Blind.setup(state, nb)
    state.phase = E.PHASE.SELECTING_HAND
end
