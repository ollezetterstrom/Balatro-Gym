-- src/13_test.lua — Self-tests, random agent, return Sim
-- Auto-split. Edit freely.

--  SECTION 12 — SELF-TEST & RANDOM AGENT
-- ============================================================================

if _SIM_RUN_TESTS or not pcall(debug.getlocal, 4, 1) then
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
    local hs = Sim.State.new({ seed="HIK", jokers={{id=28, edition=0, eternal=false, uid=1}} })
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

    -- Test: Venus levels Three of a Kind
    local vs = Sim.State.new({ seed="VEN", consumables={{id=5, uid=1}} })
    vs.hand = { C(2,1), C(5,2), C(9,3), C(11,4), C(14,1), C(3,2), C(7,3), C(13,4) }
    local vhl = vs.hand_levels[9]
    _use_consumable(vs, 1)
    test("Venus levels Three of a Kind", vs.hand_levels[9] == vhl + 1)

    -- Test: Jupiter levels Flush
    local js = Sim.State.new({ seed="JUP", consumables={{id=8, uid=1}} })
    js.hand = { C(2,1), C(5,2), C(9,3), C(11,4), C(14,1), C(3,2), C(7,3), C(13,4) }
    local jhl = js.hand_levels[7]
    _use_consumable(js, 1)
    test("Jupiter levels Flush", js.hand_levels[7] == jhl + 1)

    -- Test: The Magician enhances to Lucky
    local ms = Sim.State.new({ seed="MAG", consumables={{id=15, uid=1}} })
    ms.hand = { C(5,1), C(5,2), C(3,3), C(7,4), C(10,1), C(2,2), C(6,3), C(12,4) }
    ms.selection = {1, 2}
    _use_consumable(ms, 1)
    test("Magician enhances to Lucky", ms.hand[1].enhancement == 8 and ms.hand[2].enhancement == 8)

    -- Test: The Hermit doubles money
    local hermit_s = Sim.State.new({ seed="HER", consumables={{id=22, uid=1}} })
    hermit_s.dollars = 15
    hermit_s.hand = { C(5,1), C(5,2), C(3,3), C(7,4), C(10,1), C(2,2), C(6,3), C(12,4) }
    _use_consumable(hermit_s, 1)
    test("Hermit doubles money", hermit_s.dollars == 30)

    -- Test: The Hermit caps at +$20
    local hermit2_s = Sim.State.new({ seed="HER2", consumables={{id=22, uid=1}} })
    hermit2_s.dollars = 30
    hermit2_s.hand = { C(5,1), C(5,2), C(3,3), C(7,4), C(10,1), C(2,2), C(6,3), C(12,4) }
    _use_consumable(hermit2_s, 1)
    test("Hermit caps at +$20", hermit2_s.dollars == 50)

    -- Test: Strength increases rank
    local str_s = Sim.State.new({ seed="STR", consumables={{id=21, uid=1}} })
    str_s.hand = { C(5,1), C(5,2), C(3,3), C(7,4), C(10,1), C(2,2), C(6,3), C(12,4) }
    str_s.selection = {1, 2}
    _use_consumable(str_s, 1)
    test("Strength +1 rank", str_s.hand[1].rank == 6 and str_s.hand[2].rank == 6)

    -- Test: The Star changes suit to Diamonds
    local star_s = Sim.State.new({ seed="STAR", consumables={{id=30, uid=1}} })
    star_s.hand = { C(5,1), C(5,2), C(3,3), C(7,4), C(10,1), C(2,2), C(6,3), C(12,4) }
    star_s.selection = {1}
    _use_consumable(star_s, 1)
    test("Star changes to Diamonds", star_s.hand[1].suit == 4)

    -- Test: Temperance gives money for jokers
    local temp_s = Sim.State.new({ seed="TEMP", consumables={{id=27, uid=1}},
        jokers={{id=1,edition=0,eternal=false,uid=1}} })
    temp_s.dollars = 4
    temp_s.hand = { C(5,1), C(5,2), C(3,3), C(7,4), C(10,1), C(2,2), C(6,3), C(12,4) }
    _use_consumable(temp_s, 1)
    test("Temperance gives joker value", temp_s.dollars > 4)

    -- Test: Steel card held in hand = ×1.5 mult
    local steel_s = Sim.State.new({ seed="STEEL" })
    steel_s.hand = {
        C(10,1,5),  -- Steel 10 (held in hand)
        C(10,2),    -- Normal 10 (played)
        C(10,3),    -- Normal 10 (played)
        C(3,4), C(7,1), C(5,2), C(9,3), C(12,4)
    }
    local st1,_,sm1 = Sim.Engine.calculate(steel_s, {steel_s.hand[2], steel_s.hand[3]})
    -- Pair of 10s: base 10+10 chips, mult 2. Steel in hand: ×1.5
    test("Steel held = ×1.5 mult", sm1 == 3.0)  -- 2 * 1.5 = 3

    -- Test: Gold card held in hand = +$3
    local gold_s = Sim.State.new({ seed="GOLD" })
    gold_s.dollars = 4
    gold_s.hand = {
        C(10,1,7),  -- Gold 10 (held in hand)
        C(10,2),    -- Normal 10 (played)
        C(3,3), C(7,4), C(5,1), C(9,2), C(12,3), C(6,4)
    }
    Sim.Engine.calculate(gold_s, {gold_s.hand[2], gold_s.hand[3]})
    test("Gold held = +$3", gold_s.dollars == 7)

    -- Test: Gold seal = +$3 when scored
    local gs_s = Sim.State.new({ seed="GSEAL" })
    gs_s.dollars = 4
    local gold_seal_card = C(10,1,0,0,1)  -- Gold seal
    gs_s.hand = { gold_seal_card, C(10,2), C(3,3), C(7,4), C(5,1), C(9,2), C(12,3), C(6,4) }
    Sim.Engine.calculate(gs_s, {gs_s.hand[1], gs_s.hand[2]})
    test("Gold seal = +$3 on score", gs_s.dollars == 7)

    -- Test: Red seal re-triggers scoring
    local rs_s = Sim.State.new({ seed="RSEAL" })
    local red_seal_card = C(10,1,2,0,2)  -- Red seal + Mult enhancement (+4 mult)
    rs_s.hand = { red_seal_card, C(10,2), C(3,3), C(7,4), C(5,1), C(9,2), C(12,3), C(6,4) }
    local _,_,rsm = Sim.Engine.calculate(rs_s, {rs_s.hand[1], rs_s.hand[2]})
    -- Pair of 10s: base mult 2. Mult card +4, re-trigger +4 = mult 10
    test("Red seal re-triggers Mult", rsm == 10)

    -- Test: Wild card counts as any suit for flush
    local wild_s = Sim.State.new({ seed="WILD" })
    wild_s.hand = {
        C(2,1,3),   -- Wild 2 of Spades
        C(5,2),     -- 5 of Hearts
        C(9,2),     -- 9 of Hearts
        C(11,2),    -- J of Hearts
        C(14,2),    -- A of Hearts
        C(3,3), C(8,4), C(13,1)
    }
    local _,_,_,wht = Sim.Engine.calculate(wild_s, {wild_s.hand[1],wild_s.hand[2],wild_s.hand[3],wild_s.hand[4],wild_s.hand[5]})
    test("Wild card makes flush", wht == 7)

    -- Test: Lucky card with seeded RNG
    local lucky_s = Sim.State.new({ seed="LUCKY" })
    local lucky_card = C(10,1,8)  -- Lucky enhancement
    lucky_s.hand = { lucky_card, C(10,2), C(3,3), C(7,4), C(5,1), C(9,2), C(12,3), C(6,4) }
    local l_money_before = lucky_s.dollars
    Sim.Engine.calculate(lucky_s, {lucky_s.hand[1], lucky_s.hand[2]})
    -- Lucky is random, just verify no crash
    test("Lucky card scoring works", lucky_s.dollars >= l_money_before)

    -- Test: Supernova (+mult = times played this hand type)
    local sn_s = Sim.State.new({ seed="SN", jokers={{id=21,edition=0,eternal=false,uid=1}} })
    sn_s.hand = { C(10,1), C(10,2), C(3,3), C(7,4), C(5,1), C(9,2), C(12,3), C(6,4) }
    sn_s.hand_type_counts[11] = 3  -- Pair played 3 times before
    local _,_,snm = Sim.Engine.calculate(sn_s, {sn_s.hand[1], sn_s.hand[2]})
    -- Pair base mult 2 + Supernova +3 = 5
    test("Supernova adds played count", snm == 5)

    -- Test: Ride the Bus stacks
    local rtb_s = Sim.State.new({ seed="RTB", jokers={{id=22,edition=0,eternal=false,uid=1}} })
    rtb_s.hand = { C(2,1), C(2,2), C(3,3), C(7,4), C(5,1), C(9,2), C(12,3), C(6,4) }
    rtb_s.ride_the_bus = 3
    local _,_,rtbm = Sim.Engine.calculate(rtb_s, {rtb_s.hand[1], rtb_s.hand[2]})
    -- Pair base mult 2 + Ride the Bus +3 = 5
    test("Ride the Bus adds stacks", rtbm == 5)

    -- Test: Blackboard (all Spade/Club in hand)
    local bb_s = Sim.State.new({ seed="BB", jokers={{id=23,edition=0,eternal=false,uid=1}} })
    bb_s.hand = { C(2,1), C(2,3), C(3,1), C(7,3), C(5,1), C(9,3), C(12,1), C(6,3) }
    local _,_,bbm = Sim.Engine.calculate(bb_s, {bb_s.hand[1], bb_s.hand[2]})
    -- Pair base mult 2 * Blackboard ×3 = 6
    test("Blackboard ×3 when all dark", bbm == 6)

    -- Test: Blackboard fails with Hearts
    local bb2_s = Sim.State.new({ seed="BB2", jokers={{id=23,edition=0,eternal=false,uid=1}} })
    bb2_s.hand = { C(2,1), C(2,2), C(3,3), C(7,4), C(5,1), C(9,2), C(12,3), C(6,4) }
    local _,_,bb2m = Sim.Engine.calculate(bb2_s, {bb2_s.hand[1], bb2_s.hand[2]})
    test("Blackboard fails with Hearts", bb2m == 2)

    -- Test: Ramen starts at ×2
    local rm_s = Sim.State.new({ seed="RM", jokers={{id=24,edition=0,eternal=false,uid=1}} })
    rm_s.hand = { C(2,1), C(2,2), C(3,3), C(7,4), C(5,1), C(9,2), C(12,3), C(6,4) }
    rm_s.cards_drawn = 0
    local _,_,rmm = Sim.Engine.calculate(rm_s, {rm_s.hand[1], rm_s.hand[2]})
    test("Ramen ×2 at 0 draws", rmm == 4)  -- 2 * 2 = 4

    -- Test: Acrobat ×3 on last hand
    local ac_s = Sim.State.new({ seed="AC", jokers={{id=25,edition=0,eternal=false,uid=1}} })
    ac_s.hand = { C(2,1), C(2,2), C(3,3), C(7,4), C(5,1), C(9,2), C(12,3), C(6,4) }
    ac_s.hands_left = 0
    local _,_,acm = Sim.Engine.calculate(ac_s, {ac_s.hand[1], ac_s.hand[2]})
    test("Acrobat ×3 on last hand", acm == 6)  -- 2 * 3 = 6

    -- Test: Sock and Buskin re-triggers face card effects
    local sb_s = Sim.State.new({ seed="SB", jokers={
        {id=26,edition=0,eternal=false,uid=1},  -- Sock and Buskin
        {id=15,edition=0,eternal=false,uid=2},  -- Scary Face (+30 chips per face)
    }})
    sb_s.hand = { C(11,1), C(11,2), C(3,3), C(7,4), C(5,1), C(9,2), C(12,3), C(6,4) }
    local sb_total = Sim.Engine.calculate(sb_s, {sb_s.hand[1], sb_s.hand[2]})
    -- Pair of Jacks: base 10 + (10+10) = 30 chips, mult 2. Scary Face +30+30, re-trigger +30+30 = 150 chips
    -- Total = 150 * 2 = 300
    test("Sock and Buskin re-triggers face", sb_total == 300)

    -- Test: Wild card triggers suit-based joker (Greedy = Diamonds)
    local wild_joker_s = Sim.State.new({ seed="WJ", jokers={{id=2,edition=0,eternal=false,uid=1}} })
    wild_joker_s.hand = { C(2,1,3), C(2,2), C(3,3), C(7,4), C(5,1), C(9,2), C(12,3), C(6,4) }
    local _,_,wj_m = Sim.Engine.calculate(wild_joker_s, {wild_joker_s.hand[1], wild_joker_s.hand[2]})
    -- Pair base mult 2 + Greedy +3 = 5 (Wild card counts as Diamond)
    test("Wild triggers Greedy Joker", wj_m == 5)

    -- Test: Glass card scoring works
    local glass_s = Sim.State.new({ seed="GLASS" })
    glass_s.hand = { C(10,1,4), C(10,2), C(3,3), C(7,4), C(5,1), C(9,2), C(12,3), C(6,4) }
    local g_total = Sim.Engine.calculate(glass_s, {glass_s.hand[1], glass_s.hand[2]})
    -- Pair of 10s: base 10 + 10 + 10 = 30 chips, mult 2 × 2 (Glass) = 4. Total = 120
    test("Glass card scoring works", g_total == 120)

    -- Test: Red seal on held card re-triggers Steel
    local red_held_s = Sim.State.new({ seed="RH2" })
    red_held_s.hand = {
        C(10,1,5,0,2),  -- Steel + Red seal (held in hand)
        C(10,2), C(10,3),  -- Pair of 10s (played)
        C(7,4), C(5,1), C(9,2), C(12,3), C(6,4)
    }
    local _,_,rh_m = Sim.Engine.calculate(red_held_s, {red_held_s.hand[2], red_held_s.hand[3]})
    -- Pair mult 2. Steel ×1.5, re-trigger ×1.5 = 2 × 1.5 × 1.5 = 4.5
    test("Red seal re-triggers Steel held", rh_m == 4.5)

    -- Test: Talisman adds Gold seal
    local tal_s = Sim.State.new({ seed="TAL", consumables={{id=37, uid=1}} })
    tal_s.hand = { C(5,1), C(5,2), C(3,3), C(7,4), C(10,1), C(2,2), C(6,3), C(12,4) }
    tal_s.selection = {1}
    _use_consumable(tal_s, 1)
    test("Talisman adds Gold seal", tal_s.hand[1].seal == 1)

    -- Test: Deja Vu adds Red seal
    local dv_s = Sim.State.new({ seed="DV", consumables={{id=45, uid=1}} })
    dv_s.hand = { C(5,1), C(5,2), C(3,3), C(7,4), C(10,1), C(2,2), C(6,3), C(12,4) }
    dv_s.selection = {1}
    _use_consumable(dv_s, 1)
    test("Deja Vu adds Red seal", dv_s.hand[1].seal == 2)

    -- Test: Trance adds Blue seal
    local tr_s = Sim.State.new({ seed="TR", consumables={{id=47, uid=1}} })
    tr_s.hand = { C(5,1), C(5,2), C(3,3), C(7,4), C(10,1), C(2,2), C(6,3), C(12,4) }
    tr_s.selection = {1}
    _use_consumable(tr_s, 1)
    test("Trance adds Blue seal", tr_s.hand[1].seal == 3)

    -- Test: Immolate destroys cards and gives $20
    local imm_s = Sim.State.new({ seed="IMM", consumables={{id=43, uid=1}} })
    imm_s.hand = { C(5,1), C(5,2), C(3,3), C(7,4), C(10,1), C(2,2), C(6,3), C(12,4) }
    imm_s.dollars = 0
    _use_consumable(imm_s, 1)
    test("Immolate gives $20", imm_s.dollars == 20)
    test("Immolate destroys cards", #imm_s.hand == 3)  -- 8 - 5 = 3

    -- Test: Cryptid copies card
    local cry_s = Sim.State.new({ seed="CRY", consumables={{id=49, uid=1}} })
    cry_s.hand = { C(14,1), C(5,2), C(3,3), C(7,4), C(10,1), C(2,2) }
    cry_s.selection = {1}
    local hand_before = #cry_s.hand
    _use_consumable(cry_s, 1)
    test("Cryptid creates 2 copies", #cry_s.hand == hand_before + 2)
    test("Cryptid copies are Aces", cry_s.hand[#cry_s.hand].rank == 14)

    -- Test: Sigil changes all suits
    local sig_s = Sim.State.new({ seed="SIG", consumables={{id=40, uid=1}} })
    sig_s.hand = { C(2,1), C(5,2), C(9,3), C(11,4), C(14,1), C(3,2), C(7,3), C(13,4) }
    _use_consumable(sig_s, 1)
    local all_same = true
    local s = sig_s.hand[1].suit
    for _, c in ipairs(sig_s.hand) do
        if c.enhancement ~= 6 and c.suit ~= s then all_same = false end
    end
    test("Sigil changes all suits", all_same)

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

