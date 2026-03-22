-- src/13_test.lua — Self-tests, random agent, return Sim
-- Auto-split. Edit freely.


function Sim.Env.step(state, atype, value)
    local E = Sim.ENUMS

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

-- ============================================================================


--  SECTION 12 — SELF-TEST & RANDOM AGENT
-- ============================================================================

if not pcall(debug.getlocal, 4, 1) then
    local E = Sim.ENUMS
    local C = Sim.Card.new
    local passed, total = 0, 0
    local function test(name, cond)
        total = total + 1
        if cond then passed = passed + 1; print("  [OK] " .. name)
        else print("  [FAIL] " .. name) end
    end

    print("=== BALATRO SIM v2 — Self-Test ===\n")

    -- Test: Pair + Joker
    local s = Sim.State.new({ seed="T1", jokers={{id=1,edition=0,eternal=false,uid=1}} })
    s.hand = { C(14,1), C(14,2), C(3,3), C(7,4), C(10,1), C(5,2), C(9,3), C(12,4) }
    local t,c,m,ht = Sim.Engine.calculate(s, {s.hand[1], s.hand[2]})
    test("Pair + Joker = 192", t == 192 and ht == 11)

    -- Test: Two Pair + Duo
    s = Sim.State.new({ seed="T2", jokers={{id=6,edition=0,eternal=false,uid=1}} })
    s.hand = { C(5,1), C(5,2), C(9,3), C(9,4), C(12,1), C(2,2), C(6,3), C(11,4) }
    t,c,m,ht = Sim.Engine.calculate(s, {s.hand[1],s.hand[2],s.hand[3],s.hand[4]})
    test("Two Pair + Duo = 192", t == 192 and ht == 10)

    -- Test: Blueprint copies Joker
    s = Sim.State.new({ seed="T3", jokers={
        {id=8,edition=0,eternal=false,uid=1},  -- Blueprint
        {id=1,edition=0,eternal=false,uid=2},  -- Joker
    }})
    s.hand = { C(7,1), C(7,2), C(2,3), C(4,4), C(11,1), C(8,2), C(13,3), C(6,4) }
    t,c,m,ht = Sim.Engine.calculate(s, {s.hand[1], s.hand[2]})
    test("Blueprint + Joker = 240", t == 240)

    -- Test: Flush
    s = Sim.State.new({ seed="T4" })
    s.hand = { C(2,2), C(5,2), C(9,2), C(11,2), C(14,2), C(3,1), C(8,3), C(13,4) }
    t,c,m,ht = Sim.Engine.calculate(s, {s.hand[1],s.hand[2],s.hand[3],s.hand[4],s.hand[5]})
    test("Flush = 288", t == 288 and ht == 7)

    -- Test: Observation dim
    local obs = Sim.Obs.encode(s)
    test("Observation dim = 129", #obs == 129)

    -- Test: Env reset
    obs, info = Sim.Env.reset("TEST_SEED")
    test("Env.reset returns obs", #obs == 129 and info.ante == 1)

    -- Test: Burnt Joker
    local bs = Sim.State.new({ seed="BJ", jokers={{id=9,edition=0,eternal=false,uid=1}} })
    bs.hand = { C(5,1), C(5,2), C(3,3), C(7,4), C(10,1), C(2,2), C(6,3), C(12,4) }
    bs.discards_left = 4  -- first discard of round
    -- Simulate discard via engine context
    local def = Sim._JOKER_BY_ID[9]  -- Burnt Joker
    local disc_ht = Sim.Eval.get_hand({bs.hand[3], bs.hand[4]})
    local ctx = { on_discard = true, is_first_discard = true, discarded_hand_type = disc_ht }
    local fx = def.apply(ctx, bs, bs.jokers[1])
    test("Burnt Joker triggers", fx ~= nil and fx.level_up ~= nil)

    -- Test: Consumable (Pluto levels up High Card)
    local cs = Sim.State.new({ seed="CONS" })
    cs.hand = { C(2,1), C(5,2), C(9,3), C(11,4), C(14,1), C(3,2), C(7,3), C(13,4) }
    local hl_before = cs.hand_levels[12]
    local pluto = Sim.CONSUMABLE_DEFS["c_pluto"]
    pluto.effect({}, cs)
    test("Pluto levels High Card", cs.hand_levels[12] == hl_before + 1)

    -- Test: REORDER swaps jokers
    local rs = Sim.State.new({ seed="REO", jokers={
        {id=1, edition=0, eternal=false, uid=1},
        {id=6, edition=0, eternal=false, uid=2},
    }})
    local id_before_1, id_before_2 = rs.jokers[1].id, rs.jokers[2].id
    local rv = (1 << 4) | 0 | (1 << 9)  -- src=0, tgt=1, mode=swap, area=joker
    _do_reorder(rs, rv)
    test("REORDER swaps jokers", rs.jokers[1].id == id_before_2 and rs.jokers[2].id == id_before_1)

    -- Test: Hiker gives permanent chips
    local hs = Sim.State.new({ seed="HIK", jokers={{id=21, edition=0, eternal=false, uid=1}} })
    hs.hand = { C(5,1), C(5,2), C(3,3), C(7,4), C(10,1), C(2,2), C(6,3), C(12,4) }
    local pb_before = hs.hand[1].perma_bonus
    Sim.Engine.calculate(hs, {hs.hand[1], hs.hand[2]})
    test("Hiker +4 perma_bonus", hs.hand[1].perma_bonus == pb_before + 4)

    -- Test: Shop has consumable slot
    local ss = Sim.State.new({ seed="SHOP" })
    Sim.Shop.generate(ss)
    test("Shop has consumable", ss.shop.consumable ~= nil)

    -- Test: Buy consumable from shop
    local bs2 = Sim.State.new({ seed="SHOP2" })
    Sim.Shop.generate(bs2)
    Sim.Shop.buy_consumable(bs2)
    test("Buy consumable works", #bs2.consumables == 1)

    -- Test: Empress enhances cards
    local es = Sim.State.new({ seed="EMP", consumables={{id=3, uid=1}} })
    es.hand = { C(5,1), C(5,2), C(3,3), C(7,4), C(10,1), C(2,2), C(6,3), C(12,4) }
    es.selection = {1, 2}
    _use_consumable(es, 1)
    test("Empress enhances to Mult", es.hand[1].enhancement == 2 and es.hand[2].enhancement == 2)

    print(string.format("\n  %d/%d tests passed\n", passed, total))

    -- ================================================================
    -- RANDOM AGENT: Play one full ante with Jokers + Consumables + Packs
    -- ================================================================
    print("=== Random Agent — Full Ante ===\n")

    local rng = Sim.RNG.new("AGENT42")
    local state = Sim.State.new({
        rng = rng, seed = "AGENT42",
        jokers = {
            {id=1, edition=0, eternal=false, uid=1},  -- Joker (+4 mult)
            {id=6, edition=0, eternal=false, uid=2},  -- The Duo (x2 on pair)
        },
    })
    Sim.Blind.init_ante(state)
    Sim.Blind.setup(state, 1)
    state.phase = E.PHASE.SELECTING_HAND

    local episode_reward = 0
    local step_count = 0

    while step_count < 500 do
        step_count = step_count + 1
        local atype, value

        if state.phase == E.PHASE.SELECTING_HAND then
            if state.blind_beaten then
                atype = E.ACTION.PHASE_ACTION; value = 3
            elseif state.hands_left <= 0 then
                break
            elseif #state.consumables > 0 and Sim.RNG.next(state.rng) < 0.4 then
                -- Use a consumable 40% of the time
                atype = E.ACTION.USE_CONSUMABLE; value = 1
            elseif #state.selection == 0 then
                local mask = 0
                local n = math.min(5, #state.hand)
                local indices = {}
                for i = 1, #state.hand do indices[#indices+1] = i end
                Sim.RNG.shuffle(state.rng, indices)
                for i = 1, n do mask = mask | (1 << (indices[i] - 1)) end
                atype = E.ACTION.SELECT_CARDS; value = mask
            else
                atype = E.ACTION.PLAY_DISCARD
                value = (state.discards_left > 0 and Sim.RNG.next(state.rng) < 0.3) and 2 or 1
            end

        elseif state.phase == E.PHASE.SHOP then
            local action_taken = false
            if state.shop then
                -- Buy a joker if affordable and has slot
                for si = 1, 2 do
                    if not action_taken and state.shop.jokers[si] and
                       state.dollars >= state.shop.jokers[si].cost and
                       #state.jokers < state.joker_slots then
                        atype = E.ACTION.SHOP_ACTION; value = si; action_taken = true
                    end
                end
                -- Buy a booster pack (50% chance if affordable)
                if not action_taken and state.shop.booster and
                   state.dollars >= state.shop.booster.cost and
                   Sim.RNG.next(state.rng) < 0.5 then
                    atype = E.ACTION.SHOP_ACTION; value = 3; action_taken = true
                end
                -- Grab free consumable
                if not action_taken and state.shop.consumable and
                   #state.consumables < state.consumable_slots then
                    atype = E.ACTION.SHOP_ACTION; value = 4; action_taken = true
                end
            end
            if not action_taken then atype = E.ACTION.PHASE_ACTION; value = 0 end

        elseif state.phase == E.PHASE.PACK_OPEN then
            if state.pack_cards and #state.pack_cards > 0 then
                local pick = Sim.RNG.int(state.rng, 1, #state.pack_cards)
                atype = E.ACTION.SELECT_CARDS; value = 1 << (pick - 1)
            else
                atype = E.ACTION.PHASE_ACTION; value = 0
            end

        elseif state.phase == E.PHASE.BLIND_SELECT then
            atype = E.ACTION.PHASE_ACTION; value = 1

        else break end

        if atype then
            local obs, reward, done = Sim.Env.step(state, atype, value)
            episode_reward = episode_reward + reward
            if done then break end
        end
    end

    -- Print final stats
    if state.phase == E.PHASE.WIN then
        print(string.format("  [WIN] GAME WON! Ante %d", state.ante))
    else
        print(string.format("  Game Over at Ante %d %s: %d / %d chips",
            state.ante, state.blind_type, state.chips, state.blind_chips))
    end
    print(string.format("  Steps: %d | Reward: %.1f | Jokers: %d | Consumables: %d | $%d",
        step_count, episode_reward, #state.jokers, #state.consumables, state.dollars))
    if #state.jokers > 0 then
        for _, jk in ipairs(state.jokers) do
            local def = Sim._JOKER_BY_ID[jk.id]
            print(string.format("    - %s", def.name))
        end
    end
    local has_levels = false
    for i = 1, 12 do
        if state.hand_levels[i] > 1 then has_levels = true; break end
    end
    if has_levels then
        print("  Hand levels:")
        for i = 1, 12 do
            if state.hand_levels[i] > 1 then
                print(string.format("    - %s: Lv.%d", E.HAND_NAME[i], state.hand_levels[i]))
            end
        end
    end

    print("\n=== Done ===\n")
end

return Sim

