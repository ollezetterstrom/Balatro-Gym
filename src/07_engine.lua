-- src/07_engine.lua — Scoring engine
-- Auto-split. Edit freely.

--  SECTION 6 — SCORING ENGINE
-- ============================================================================

Sim.Engine = {}

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

        if insc and not debuffed and c.enhancement ~= 6 then chips = chips + Sim.Card.chips(c) end
        if insc and not debuffed then
            if c.enhancement == 1 then chips = chips + 30        -- Bonus
            elseif c.enhancement == 2 then mult = mult + 4       -- Mult
            elseif c.enhancement == 6 then chips = chips + 50    -- Stone
            elseif c.enhancement == 4 then mult = mult * 2 end   -- Glass
        end
        if insc and not debuffed then
            if c.edition == 1 then chips = chips + 50            -- Foil
            elseif c.edition == 2 then mult = mult + 10          -- Holo
            elseif c.edition == 3 then mult = mult * 1.5 end     -- Poly
        end

        -- Individual card joker effects (Hiker, etc.)
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

    return math.floor(chips * mult), chips, mult, hand_type, scoring, all_hands
end

-- ============================================================================


