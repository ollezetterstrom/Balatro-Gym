-- src/07_engine.lua — Scoring engine
-- Auto-split. Edit freely.

--  SECTION 6 — SCORING ENGINE
-- ============================================================================

Sim.Engine = {}

local function _score_card_effects(state, c, insc, debuffed, chips, mult)
    if not insc or debuffed then return chips, mult end

    -- Base card chips (not for Stone)
    if c.enhancement ~= 6 then chips = chips + Sim.Card.chips(c) end

    -- Enhancement effects (scoring)
    if c.enhancement == 1 then       -- Bonus: +30 chips
        chips = chips + 30
    elseif c.enhancement == 2 then   -- Mult: +4 mult
        mult = mult + 4
    elseif c.enhancement == 4 then   -- Glass: ×2 mult
        mult = mult * 2
    elseif c.enhancement == 6 then   -- Stone: +50 chips
        chips = chips + 50
    elseif c.enhancement == 8 then   -- Lucky: 1/5 +20 mult, 1/15 +$20
        if state.rng and Sim.RNG.next(state.rng) < 0.2 then
            mult = mult + 20
        end
        if state.rng and Sim.RNG.next(state.rng) < (1/15) then
            state.dollars = state.dollars + 20
        end
    end

    -- Edition effects
    if c.edition == 1 then chips = chips + 50        -- Foil
    elseif c.edition == 2 then mult = mult + 10      -- Holo
    elseif c.edition == 3 then mult = mult * 1.5 end -- Poly

    return chips, mult
end

function Sim.Engine.calculate(state, played)
    local E = Sim.ENUMS
    local hand_type, scoring, all_hands = Sim.Eval.get_hand(played)

    local base = Sim.HAND_BASE[hand_type]
    local level = state.hand_levels[hand_type] or 1
    local chips = base[2] + base[4] * (level - 1)
    local mult  = base[1] + base[3] * (level - 1)

    local is_sc = {}
    for i = 1, #scoring do is_sc[scoring[i]] = true end

    for i = 1, #played do
        local c = played[i]
        local insc = is_sc[c]
        local debuffed = Sim.Blind.is_card_debuffed(state, c)

        chips, mult = _score_card_effects(state, c, insc, debuffed, chips, mult)

        -- Red seal: re-trigger scoring effects
        if insc and not debuffed and c.seal == 2 then
            chips, mult = _score_card_effects(state, c, insc, debuffed, chips, mult)
        end

        -- Gold seal: +3 money when scored
        if insc and not debuffed and c.seal == 1 then
            state.dollars = state.dollars + 3
        end

        -- Individual card joker effects (scoring cards only)
        if insc and not debuffed and state.jokers then
            for ji = 1, #state.jokers do
                local jk = state.jokers[ji]
                local def = Sim._JOKER_BY_ID[jk.id]
                if def and def.apply then
                    local ctx = {
                        individual = true, cardarea = "play",
                        other_card = c, scoring_hand = scoring,
                        my_joker_index = ji,
                    }
                    local fx = def.apply(ctx, state, jk)
                    if fx then
                        if fx.chips then chips = chips + fx.chips end
                        if fx.mult then mult = mult + fx.mult end
                        if fx.x_mult then mult = mult * fx.x_mult end
                    end
                end
            end
        end
    end

    if state.jokers then
        for ji = 1, #state.jokers do
            local jk = state.jokers[ji]
            local def = Sim._JOKER_BY_ID[jk.id]
            if def and def.apply then
                local ctx = {
                    joker_main = true, hand_type = hand_type,
                    all_hands = all_hands, poker_hands = all_hands,
                    scoring = scoring, all_played = played,
                    my_joker_index = ji,
                }
                local fx = def.apply(ctx, state, jk)
                if fx then
                    if fx.chip_mod then chips = chips + fx.chip_mod end
                    if fx.mult_mod then mult = mult + fx.mult_mod end
                    if fx.Xmult_mod then mult = mult * fx.Xmult_mod end
                end
            end
            if jk.edition == 1 then chips = chips + 50
            elseif jk.edition == 2 then mult = mult + 10
            elseif jk.edition == 3 then mult = mult * 1.5 end
        end
    end

    -- Held-in-hand effects: cards remaining in hand after play
    for i = 1, #state.hand do
        local c = state.hand[i]
        local debuffed = Sim.Blind.is_card_debuffed(state, c)
        if not debuffed then
            local reps = 1
            -- Red seal on held card: re-trigger held-in-hand effects
            if c.seal == 2 then reps = 2 end
            for r = 1, reps do
                if c.enhancement == 5 then   -- Steel: ×1.5 mult
                    mult = mult * 1.5
                elseif c.enhancement == 7 then -- Gold: +3 money
                    state.dollars = state.dollars + 3
                end
                -- Joker effects on held cards
                if state.jokers then
                    for ji = 1, #state.jokers do
                        local jk = state.jokers[ji]
                        local def = Sim._JOKER_BY_ID[jk.id]
                        if def and def.apply then
                            local ctx = {
                                held = true, cardarea = "hand",
                                other_card = c, my_joker_index = ji,
                            }
                            local fx = def.apply(ctx, state, jk)
                            if fx then
                                if fx.x_mult then mult = mult * fx.x_mult end
                                if fx.mult then mult = mult + fx.mult end
                                if fx.chips then chips = chips + fx.chips end
                            end
                        end
                    end
                end
            end
        end
    end

    -- Sock and Buskin: re-trigger individual effects for face cards
    local has_sock = false
    if state.jokers then
        for ji = 1, #state.jokers do
            local jdef = Sim._JOKER_BY_ID[state.jokers[ji].id]
            if jdef and jdef.key == "j_sock_and_buskin" then has_sock = true; break end
        end
    end
    if has_sock then
        for i = 1, #played do
            local c = played[i]
            local insc = is_sc[c]
            local debuffed = Sim.Blind.is_card_debuffed(state, c)
            if insc and not debuffed and c.rank >= 11 and c.rank <= 13 then
                -- Re-trigger individual card joker effects for face cards
                if state.jokers then
                    for ji = 1, #state.jokers do
                        local jk = state.jokers[ji]
                        local def = Sim._JOKER_BY_ID[jk.id]
                        if def and def.apply then
                            local ctx = {
                                individual = true, cardarea = "play",
                                other_card = c, scoring_hand = scoring,
                                my_joker_index = ji,
                            }
                            local fx = def.apply(ctx, state, jk)
                            if fx then
                                if fx.chips then chips = chips + fx.chips end
                                if fx.mult then mult = mult + fx.mult end
                                if fx.x_mult then mult = mult * fx.x_mult end
                            end
                        end
                    end
                end
            end
        end
    end

    return math.floor(chips * mult), chips, mult, hand_type, scoring, all_hands
end

-- ============================================================================


