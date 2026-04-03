-- src/17_tags.lua — Tag system (EXACT port of real game's tag.lua)
--
-- Real game source: tag.lua (full file)
-- 10 trigger types: eval, immediate, new_blind_choice, voucher_add, tag_add,
--   round_start_bonus, store_joker_create, shop_start, store_joker_modify, shop_final_pass

Sim.Tag = {}

-- Tag registry
Sim.Tag.DEFS = Sim.Tag.DEFS or {}

function Sim.Tag.reg(key, name, trigger_type, config, min_ante)
    Sim.Tag.DEFS[key] = {
        key = key,
        name = name,
        config = config or {},
        min_ante = min_ante,
    }
end

-- ========================================================================= --
-- TAG DEFINITIONS (from real game's game.lua P_TAGS)
-- ========================================================================= --

-- Immediate tags
Sim.Tag.reg("tag_handy", "Handy Tag", "immediate", { dollars_per_hand = 1 })
Sim.Tag.reg("tag_garbage", "Garbage Tag", "immediate", { dollars_per_discard = 1 })
Sim.Tag.reg("tag_top_up", "Top-up Tag", "immediate", { spawn_jokers = 2 })
Sim.Tag.reg("tag_skip", "Skip Tag", "immediate", { skip_bonus = 3 })
Sim.Tag.reg("tag_economy", "Economy Tag", "immediate", { max = 20 })
Sim.Tag.reg("tag_orbital", "Orbital Tag", "immediate", { levels = 3 })

-- New blind choice tags
Sim.Tag.reg("tag_charm", "Charm Tag", "new_blind_choice", { pack = "p_arcana_mega" })
Sim.Tag.reg("tag_meteor", "Meteor Tag", "new_blind_choice", { pack = "p_celestial_mega" })
Sim.Tag.reg("tag_ethereal", "Ethereal Tag", "new_blind_choice", { pack = "p_spectral_normal" })
Sim.Tag.reg("tag_standard", "Standard Tag", "new_blind_choice", { pack = "p_standard_mega" })
Sim.Tag.reg("tag_buffoon", "Buffoon Tag", "new_blind_choice", { pack = "p_buffoon_mega" })
Sim.Tag.reg("tag_boss", "Boss Tag", "new_blind_choice", { reroll_boss = true })

-- Eval tags
Sim.Tag.reg("tag_investment", "Investment Tag", "eval", { dollars = 25 })

-- Voucher add tags
Sim.Tag.reg("tag_voucher", "Voucher Tag", "voucher_add", {})

-- Tag add tags
Sim.Tag.reg("tag_double", "Double Tag", "tag_add", {})

-- Round start bonus tags
Sim.Tag.reg("tag_juggle", "Juggle Tag", "round_start_bonus", { h_size = 1 })

-- Store joker create tags
Sim.Tag.reg("tag_rare", "Rare Tag", "store_joker_create", { rarity = 3 })
Sim.Tag.reg("tag_uncommon", "Uncommon Tag", "store_joker_create", { rarity = 2 })

-- Shop start tags
Sim.Tag.reg("tag_d6", "D6 Tag", "shop_start", { free_rerolls = true })

-- Store joker modify tags
Sim.Tag.reg("tag_foil", "Foil Tag", "store_joker_modify", { edition = "foil" })
Sim.Tag.reg("tag_holo", "Holographic Tag", "store_joker_modify", { edition = "holo" })
Sim.Tag.reg("tag_polychrome", "Polychrome Tag", "store_joker_modify", { edition = "polychrome" })
Sim.Tag.reg("tag_negative", "Negative Tag", "store_joker_modify", { edition = "negative" })

-- Shop final pass tags
Sim.Tag.reg("tag_coupon", "Coupon Tag", "shop_final_pass", { free_shop = true })

-- ========================================================================= --
-- TAG SYSTEM
-- ========================================================================= --

--- Add a tag to the game state
function Sim.Tag.add(state, key)
    if not state._tags then state._tags = {} end
    local def = Sim.Tag.DEFS[key]
    if not def then return nil end

    state._tag_id = (state._tag_id or 0) + 1
    local tag = {
        key = key,
        name = def.name,
        config = def.config,
        id = state._tag_id,
        triggered = false,
        ability = {},
    }

    -- Orbital tag needs hand selection
    if key == "tag_orbital" then
        local hands = {"High Card","Pair","Two Pair","Three of a Kind","Straight",
            "Flush","Full House","Four of a Kind","Straight Flush","Five of a Kind",
            "Flush House","Flush Five"}
        tag.ability.orbital_hand = hands[Sim.RNG.int(state.rng, 1, #hands)]
    end

    state._tags[#state._tags + 1] = tag
    return tag
end

--- Process tags for a given trigger type
function Sim.Tag.trigger(state, context)
    if not state._tags or #state._tags == 0 then return end

    local triggered_tags = {}
    for i = #state._tags, 1, -1 do
        local tag = state._tags[i]
        if not tag.triggered and tag.config and tag.config.type == context.type then
            local result = Sim.Tag._apply(state, tag, context)
            if result then
                tag.triggered = true
                triggered_tags[#triggered_tags + 1] = { tag = tag, result = result }
                -- Remove triggered tag from game
                table.remove(state._tags, i)
            end
        end
    end
    return triggered_tags
end

--- Apply a tag's effect based on its type
function Sim.Tag._apply(state, tag, context)
    local name = tag.name
    local cfg = tag.config

    -- eval: Investment Tag
    if context.type == "eval" then
        if name == "Investment Tag" then
            state.dollars = state.dollars + (cfg.dollars or 25)
            return { dollars = cfg.dollars }
        end

    -- immediate: Top-up, Skip, Garbage, Handy, Economy, Orbital
    elseif context.type == "immediate" then
        if name == "Top-up Tag" then
            local count = math.min(cfg.spawn_jokers or 2, state.joker_slots - #state.jokers)
            for j = 1, count do
                local pool = Sim.CardFactory.get_current_pool(state, 'Joker', 1)
                if pool and #pool > 0 then
                    local jkey = Sim.RNG.pick(state.rng, pool)
                    local def = Sim.JOKER_DEFS[jkey]
                    if def then
                        Sim.State.add_joker(state, def)
                    end
                end
            end
            return { spawned = count }
        end

        if name == "Handy Tag" then
            local dollars = (state.hands_played or 0) * (cfg.dollars_per_hand or 1)
            state.dollars = state.dollars + dollars
            return { dollars = dollars }
        end

        if name == "Garbage Tag" then
            local dollars = (state._unused_discards or 0) * (cfg.dollars_per_discard or 1)
            state.dollars = state.dollars + dollars
            return { dollars = dollars }
        end

        if name == "Skip Tag" then
            local dollars = (state._blinds_skipped or 0) * (cfg.skip_bonus or 3)
            state.dollars = state.dollars + dollars
            return { dollars = dollars }
        end

        if name == "Economy Tag" then
            local dollars = math.min(cfg.max or 20, math.max(0, state.dollars))
            state.dollars = state.dollars + dollars
            return { dollars = dollars }
        end

        if name == "Orbital Tag" then
            local hand = tag.ability.orbital_hand or "High Card"
            local ht = Sim._HAND_NAME_TO_ENUM[hand] or 1
            Sim.State.level_up(state, ht, cfg.levels or 3)
            return { leveled = hand, levels = cfg.levels }
        end

    -- new_blind_choice: Charm, Meteor, Ethereal, Standard, Buffoon, Boss
    elseif context.type == "new_blind_choice" then
        if name == "Charm Tag" then
            -- Give Arcana mega pack
            state._tag_pack = "arcana_mega"
            return { pack = "arcana_mega" }
        end
        if name == "Meteor Tag" then
            state._tag_pack = "celestial_mega"
            return { pack = "celestial_mega" }
        end
        if name == "Ethereal Tag" then
            state._tag_pack = "spectral_normal"
            return { pack = "spectral_normal" }
        end
        if name == "Standard Tag" then
            state._tag_pack = "standard_mega"
            return { pack = "standard_mega" }
        end
        if name == "Buffoon Tag" then
            state._tag_pack = "buffoon_mega"
            return { pack = "buffoon_mega" }
        end
        if name == "Boss Tag" then
            -- Reroll boss blind
            state._reroll_boss = true
            return { reroll_boss = true }
        end

    -- voucher_add: Voucher Tag
    elseif context.type == "voucher_add" then
        if name == "Voucher Tag" then
            -- Add next voucher to shop
            state._voucher_tag = true
            return { voucher_added = true }
        end

    -- tag_add: Double Tag
    elseif context.type == "tag_add" then
        if name == "Double Tag" and context.tag and context.tag.key ~= "tag_double" then
            Sim.Tag.add(state, context.tag.key)
            return { duplicated = context.tag.key }
        end

    -- round_start_bonus: Juggle Tag
    elseif context.type == "round_start_bonus" then
        if name == "Juggle Tag" then
            state.hand_limit = state.hand_limit + (cfg.h_size or 1)
            state._temp_handsize = (state._temp_handsize or 0) + (cfg.h_size or 1)
            return { hand_size = cfg.h_size }
        end

    -- store_joker_create: Rare, Uncommon
    elseif context.type == "store_joker_create" then
        if name == "Rare Tag" then
            local pool = Sim.CardFactory.get_current_pool(state, 'Joker', 3)
            if pool and #pool > 0 then
                local jkey = Sim.RNG.pick(state.rng, pool)
                return { joker_key = jkey, rarity = 3, couponed = true }
            end
        end
        if name == "Uncommon Tag" then
            local pool = Sim.CardFactory.get_current_pool(state, 'Joker', 2)
            if pool and #pool > 0 then
                local jkey = Sim.RNG.pick(state.rng, pool)
                return { joker_key = jkey, rarity = 2, couponed = true }
            end
        end

    -- shop_start: D6 Tag
    elseif context.type == "shop_start" then
        if name == "D6 Tag" and not state._shop_d6ed then
            state._shop_d6ed = true
            state._temp_reroll_cost = 0
            return { free_rerolls = true }
        end

    -- store_joker_modify: Foil, Holo, Polychrome, Negative
    elseif context.type == "store_joker_modify" then
        if name == "Foil Tag" then
            return { edition = "foil", couponed = true }
        end
        if name == "Holographic Tag" then
            return { edition = "holo", couponed = true }
        end
        if name == "Polychrome Tag" then
            return { edition = "polychrome", couponed = true }
        end
        if name == "Negative Tag" then
            return { edition = "negative", couponed = true }
        end

    -- shop_final_pass: Coupon Tag
    elseif context.type == "shop_final_pass" then
        if name == "Coupon Tag" and not state._shop_free then
            state._shop_free = true
            return { shop_free = true }
        end
    end

    return nil
end
