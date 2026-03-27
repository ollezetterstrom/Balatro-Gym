-- src/15_tags.lua — Tags system (24 tags from real Balatro)
--
-- Tags are gained when blinds are skipped. Each tag has a trigger type
-- that determines when it activates. All 24 tags implemented with
-- exact configs from game.lua P_TAGS.

Sim.Tag = {}
Sim.Tag.DEFS = {}

--- Register a tag definition.
function Sim.Tag.reg(key, name, trigger_type, config, min_ante)
    Sim.Tag.DEFS[key] = {
        key = key, name = name, type = trigger_type,
        config = config or {}, min_ante = min_ante,
    }
end

-- === Tag definitions (from game.lua P_TAGS) ===

Sim.Tag.reg("tag_uncommon",   "Uncommon Tag",      "store_joker_create", {rarity = 2}, nil)
Sim.Tag.reg("tag_rare",       "Rare Tag",           "store_joker_create", {rarity = 3}, nil)
Sim.Tag.reg("tag_negative",   "Negative Tag",       "store_joker_modify", {edition = 4}, 2)
Sim.Tag.reg("tag_foil",       "Foil Tag",           "store_joker_modify", {edition = 1}, nil)
Sim.Tag.reg("tag_holo",       "Holographic Tag",    "store_joker_modify", {edition = 2}, nil)
Sim.Tag.reg("tag_polychrome", "Polychrome Tag",     "store_joker_modify", {edition = 3}, nil)
Sim.Tag.reg("tag_investment", "Investment Tag",     "eval",               {dollars = 25}, nil)
Sim.Tag.reg("tag_voucher",    "Voucher Tag",        "voucher_add",        {}, nil)
Sim.Tag.reg("tag_boss",       "Boss Tag",           "new_blind_choice",   {}, nil)
Sim.Tag.reg("tag_standard",   "Standard Tag",       "new_blind_choice",   {}, 2)
Sim.Tag.reg("tag_charm",      "Charm Tag",          "new_blind_choice",   {}, nil)
Sim.Tag.reg("tag_meteor",     "Meteor Tag",         "new_blind_choice",   {}, 2)
Sim.Tag.reg("tag_buffoon",    "Buffoon Tag",        "new_blind_choice",   {}, 2)
Sim.Tag.reg("tag_handy",      "Handy Tag",          "immediate",          {dollars_per_hand = 1}, 2)
Sim.Tag.reg("tag_garbage",    "Garbage Tag",        "immediate",          {dollars_per_discard = 1}, 2)
Sim.Tag.reg("tag_ethereal",   "Ethereal Tag",       "new_blind_choice",   {}, 2)
Sim.Tag.reg("tag_coupon",     "Coupon Tag",         "shop_final_pass",    {}, nil)
Sim.Tag.reg("tag_double",     "Double Tag",         "tag_add",            {}, nil)
Sim.Tag.reg("tag_juggle",     "Juggle Tag",         "round_start_bonus",  {h_size = 3}, nil)
Sim.Tag.reg("tag_d_six",      "D6 Tag",             "shop_start",         {}, nil)
Sim.Tag.reg("tag_top_up",     "Top-up Tag",         "immediate",          {spawn_jokers = 2}, 2)
Sim.Tag.reg("tag_skip",       "Skip Tag",           "immediate",          {skip_bonus = 5}, nil)
Sim.Tag.reg("tag_orbital",    "Orbital Tag",        "immediate",          {levels = 3}, 2)
Sim.Tag.reg("tag_economy",    "Economy Tag",        "immediate",          {max = 40}, nil)

--- Add a tag to the state. Returns true if added.
function Sim.Tag.add(state, tag_key)
    if not Sim.Tag.DEFS[tag_key] then return false end
    state.tags = state.tags or {}
    local tag = { key = tag_key, triggered = false, config = Sim.Tag.DEFS[tag_key].config }
    state.tags[#state.tags + 1] = tag

    -- Fire immediate tags right away
    local def = Sim.Tag.DEFS[tag_key]
    if def.type == "immediate" then
        Sim.Tag.apply_immediate(state, tag, def)
    end

    -- Double Tag: when any tag is gained, copy it
    for _, existing in ipairs(state.tags) do
        if existing ~= tag and existing.key == "tag_double" and not existing.triggered then
            if tag_key ~= "tag_double" then
                existing.triggered = true
                Sim.Tag.add(state, tag_key)
            end
        end
    end

    return true
end

--- Apply an immediate tag effect.
function Sim.Tag.apply_immediate(state, tag, def)
    if tag.triggered then return end
    local cfg = def.config or {}

    if def.key == "tag_handy" then
        local earned = (state.total_hands_played or 0) * (cfg.dollars_per_hand or 1)
        state.dollars = state.dollars + earned
    elseif def.key == "tag_garbage" then
        local earned = (state.total_unused_discards or 0) * (cfg.dollars_per_discard or 1)
        state.dollars = state.dollars + earned
    elseif def.key == "tag_skip" then
        local earned = (state.skips or 0) * (cfg.skip_bonus or 5)
        state.dollars = state.dollars + earned
    elseif def.key == "tag_economy" then
        local max = cfg.max or 40
        local earned = math.min(max, math.max(0, state.dollars))
        state.dollars = state.dollars + earned
    elseif def.key == "tag_top_up" then
        local count = cfg.spawn_jokers or 2
        for i = 1, count do
            if #state.jokers < state.joker_slots then
                local jk = Sim.CardFactory.create("Joker", state, state.rng, 1)  -- Common only
                if jk then
                    local jdef = Sim._JOKER_BY_ID[jk.id]
                    if jdef then Sim.State.add_joker(state, jdef) end
                end
            end
        end
    elseif def.key == "tag_orbital" then
        -- Level up most played hand by 3
        local best_hand = nil
        local best_count = 0
        for ht, count in pairs(state.hand_type_counts or {}) do
            if type(ht) == "number" and count > best_count then
                best_count = count
                best_hand = ht
            end
        end
        if best_hand then
            state.hand_levels[best_hand] = (state.hand_levels[best_hand] or 1) + (cfg.levels or 3)
            Sim.State.level_up(state, best_hand)
        end
    end

    tag.triggered = true
end

--- Apply tags for a context (eval, new_blind_choice, store_joker_create, etc.)
--- Returns effects that should be applied.
function Sim.Tag.apply(state, context_type, context)
    if not state.tags then return {} end
    local effects = {}

    for _, tag in ipairs(state.tags) do
        if not tag.triggered then
            local def = Sim.Tag.DEFS[tag.key]
            if def and def.type == context_type then
                if context_type == "eval" then
                    -- Investment Tag: +$25 after defeating boss
                    if tag.key == "tag_investment" and context and context.was_boss then
                        state.dollars = state.dollars + (tag.config.dollars or 25)
                        tag.triggered = true
                    end
                elseif context_type == "new_blind_choice" then
                    -- Pack tags: open a free pack
                    if tag.key == "tag_charm" then
                        effects[#effects + 1] = { type = "free_pack", pack = "arcana_mega" }
                        tag.triggered = true
                    elseif tag.key == "tag_meteor" then
                        effects[#effects + 1] = { type = "free_pack", pack = "celestial_mega" }
                        tag.triggered = true
                    elseif tag.key == "tag_standard" then
                        effects[#effects + 1] = { type = "free_pack", pack = "standard_mega" }
                        tag.triggered = true
                    elseif tag.key == "tag_buffoon" then
                        effects[#effects + 1] = { type = "free_pack", pack = "buffoon_mega" }
                        tag.triggered = true
                    elseif tag.key == "tag_ethereal" then
                        effects[#effects + 1] = { type = "free_pack", pack = "spectral_normal" }
                        tag.triggered = true
                    elseif tag.key == "tag_boss" then
                        effects[#effects + 1] = { type = "reroll_boss" }
                        tag.triggered = true
                    end
                elseif context_type == "store_joker_create" then
                    -- Uncommon/Rare Tag: create free joker
                    if tag.key == "tag_uncommon" then
                        local jk = Sim.CardFactory.create("Joker", state, state.rng, 2)
                        if jk then
                            effects[#effects + 1] = { type = "free_joker", joker = jk }
                        end
                        tag.triggered = true
                    elseif tag.key == "tag_rare" then
                        local pool = Sim.CardFactory.get_joker_pool(state, 3)
                        if #pool > 0 then
                            local jk = Sim.CardFactory.create("Joker", state, state.rng, 3)
                            if jk then
                                effects[#effects + 1] = { type = "free_joker", joker = jk }
                            end
                        end
                        tag.triggered = true
                    end
                elseif context_type == "store_joker_modify" then
                    -- Edition tags: apply edition to first uneditioned joker
                    if tag.key == "tag_foil" or tag.key == "tag_holo" or
                       tag.key == "tag_polychrome" or tag.key == "tag_negative" then
                        if context and context.joker then
                            local jk = context.joker
                            if jk.edition == 0 then
                                jk.edition = tag.config.edition or 0
                                effects[#effects + 1] = { type = "edition_applied", edition = jk.edition }
                            end
                        end
                        tag.triggered = true
                    end
                elseif context_type == "shop_start" then
                    -- D6 Tag: first reroll free
                    if tag.key == "tag_d_six" then
                        state._reroll_cost = 0
                        tag.triggered = true
                    end
                elseif context_type == "shop_final_pass" then
                    -- Coupon Tag: all items free
                    if tag.key == "tag_coupon" then
                        effects[#effects + 1] = { type = "all_free" }
                        tag.triggered = true
                    end
                elseif context_type == "round_start_bonus" then
                    -- Juggle Tag: +3 hand size this round
                    if tag.key == "tag_juggle" then
                        local h = tag.config.h_size or 3
                        state.hand_limit = (state.hand_limit or 8) + h
                        state._juggle_bonus = (state._juggle_bonus or 0) + h
                        tag.triggered = true
                    end
                elseif context_type == "voucher_add" then
                    -- Voucher Tag: extra voucher in shop
                    if tag.key == "tag_voucher" then
                        effects[#effects + 1] = { type = "extra_voucher" }
                        tag.triggered = true
                    end
                end
            end
        end
    end

    return effects
end

--- Pick a random tag that's available at the given ante.
function Sim.Tag.pick(state)
    local available = {}
    local ante = state.ante or 1
    local owned = {}
    for _, tag in ipairs(state.tags or {}) do
        owned[tag.key] = true
    end
    for key, def in pairs(Sim.Tag.DEFS) do
        if not owned[key] then
            if not def.min_ante or ante >= def.min_ante then
                available[#available + 1] = key
            end
        end
    end
    if #available == 0 then return nil end
    return available[Sim.RNG.int(state.rng, 1, #available)]
end
