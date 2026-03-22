-- src/04_jokers.lua — Joker definitions (all)
-- Auto-split. Edit freely.

    if card.edition == 1 then t = t.."[F]" end
    if card.edition == 2 then t = t.."[H]" end
    if card.edition == 3 then t = t.."[P]" end
    return t
end

-- ============================================================================


--  SECTION 4 — JOKER DEFINITIONS
-- ============================================================================

Sim.JOKER_DEFS = {}
Sim._JOKER_BY_ID = {}

local function _reg_joker(key, name, rarity, cost, apply_fn)
    local def = { id = #Sim._JOKER_BY_ID + 1, key = key, name = name,
                  rarity = rarity, cost = cost, apply = apply_fn }
    Sim.JOKER_DEFS[key] = def
    Sim._JOKER_BY_ID[def.id] = def
    return def
end

_reg_joker("j_joker", "Joker", 1, 3, function(ctx, st, jk)
    if ctx.joker_main then return { mult_mod = 4 } end
end)

_reg_joker("j_greedy", "Greedy Joker", 1, 5, function(ctx, st, jk)
    if ctx.joker_main and ctx.scoring then
        for _, c in ipairs(ctx.scoring) do
            if c.suit == 4 then return { mult_mod = 3 } end  -- Diamonds
        end
    end
end)

_reg_joker("j_lusty", "Lusty Joker", 1, 5, function(ctx, st, jk)
    if ctx.joker_main and ctx.scoring then
        for _, c in ipairs(ctx.scoring) do
            if c.suit == 2 then return { mult_mod = 3 } end  -- Hearts
        end
    end
end)

_reg_joker("j_wrathful", "Wrathful Joker", 1, 5, function(ctx, st, jk)
    if ctx.joker_main and ctx.scoring then
        for _, c in ipairs(ctx.scoring) do
            if c.suit == 1 then return { mult_mod = 3 } end  -- Spades
        end
    end
end)

_reg_joker("j_gluttonous", "Gluttonous Joker", 1, 5, function(ctx, st, jk)
    if ctx.joker_main and ctx.scoring then
        for _, c in ipairs(ctx.scoring) do
            if c.suit == 3 then return { mult_mod = 3 } end  -- Clubs
        end
    end
end)

_reg_joker("j_the_duo", "The Duo", 3, 8, function(ctx, st, jk)
    if ctx.joker_main and ctx.all_hands and ctx.all_hands[11] then
        return { Xmult_mod = 2 }
    end
end)

_reg_joker("j_the_trio", "The Trio", 3, 8, function(ctx, st, jk)
    if ctx.joker_main and ctx.all_hands and ctx.all_hands[9] then
        return { Xmult_mod = 3 }
    end
end)

_reg_joker("j_blueprint", "Blueprint", 3, 10, function(ctx, st, jk)
    if ctx.blueprint then return end
    if not ctx.my_joker_index then return end
    local target = st.jokers[ctx.my_joker_index + 1]
    if not target or target == jk then return end
    local def = Sim._JOKER_BY_ID[target.id]
    if not def or not def.apply then return end
    local cc = {}
    for k,v in pairs(ctx) do cc[k] = v end
    cc.blueprint = true
    return def.apply(cc, st, target)
end)

_reg_joker("j_burnt_joker", "Burnt Joker", 3, 8, function(ctx, st, jk)
    if ctx.on_discard and ctx.is_first_discard then
        return { level_up = ctx.discarded_hand_type }
    end
end)

-- === New jokers (10 common/uncommon) ===

_reg_joker("j_stencil", "Joker Stencil", 2, 8, function(ctx, st, jk)
    if ctx.joker_main then
        local empty = st.joker_slots - #st.jokers
        if empty > 0 then return { Xmult_mod = 1 + empty } end
    end
end)

_reg_joker("j_banner", "Banner", 1, 5, function(ctx, st, jk)
    if ctx.joker_main then
        return { chip_mod = 30 * (st.discards_left or 0) }
    end
end)

_reg_joker("j_mystic_summit", "Mystic Summit", 1, 5, function(ctx, st, jk)
    if ctx.joker_main and (st.discards_left or 0) == 0 then
        return { mult_mod = 15 }
    end
end)

_reg_joker("j_misprint", "Misprint", 1, 4, function(ctx, st, jk)
    if ctx.joker_main then
        return { mult_mod = Sim.RNG.int(st.rng, 0, 23) }
    end
end)

_reg_joker("j_fibonacci", "Fibonacci", 2, 8, function(ctx, st, jk)
    if ctx.individual and ctx.other_card then
        local r = ctx.other_card.rank
        if r == 14 or r == 2 or r == 3 or r == 5 or r == 8 then
            return { mult = 8 }
        end
    end
end)

_reg_joker("j_scary_face", "Scary Face", 1, 4, function(ctx, st, jk)
    if ctx.individual and ctx.other_card then
        local r = ctx.other_card.rank
        if r == 11 or r == 12 or r == 13 then
            return { chips = 30 }
        end
    end
end)

_reg_joker("j_even_steven", "Even Steven", 1, 5, function(ctx, st, jk)
    if ctx.individual and ctx.other_card then
        local r = ctx.other_card.rank
        if r == 2 or r == 4 or r == 6 or r == 8 or r == 10 then
            return { mult = 4 }
        end
    end
end)

_reg_joker("j_odd_todd", "Odd Todd", 1, 5, function(ctx, st, jk)
    if ctx.individual and ctx.other_card then
        local r = ctx.other_card.rank
        if r == 3 or r == 5 or r == 7 or r == 9 or r == 14 then
            return { chips = 31 }
        end
    end
end)

_reg_joker("j_scholar", "Scholar", 1, 4, function(ctx, st, jk)
    if ctx.individual and ctx.other_card then
        if ctx.other_card.rank == 14 then
            return { chips = 20, mult = 4 }
        end
    end
end)

_reg_joker("j_sly", "Sly Joker", 1, 3, function(ctx, st, jk)
    if ctx.joker_main then
        return { chip_mod = 50 }
