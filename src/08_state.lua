-- src/08_state.lua — Game state, draw, discard, joker ops
-- Auto-split. Edit freely.

--  SECTION 7 — GAME STATE
-- ============================================================================

Sim.State = {}
D = { hands=4, discards=4, hand_size=8, joker_slots=5, cons_slots=2, start_money=4 }

function Sim.State.new(opts)
    opts = opts or {}
    local deck = opts.deck or Sim.Card.new_deck()
    local rng = opts.rng or Sim.RNG.new(opts.seed or "BALATRO")
    if not opts.deck then Sim.RNG.shuffle(rng, deck) end
    local hl = {}
    for i = 1, 12 do hl[i] = 1 end
    return {
        deck=deck, hand={}, discard={}, hand_limit=opts.hand_size or D.hand_size,
        jokers=opts.jokers or {}, joker_slots=D.joker_slots,
        consumables=opts.consumables or {}, consumable_slots=D.cons_slots,
        phase=opts.phase or Sim.ENUMS.PHASE.BLIND_SELECT,
        dollars=opts.dollars or D.start_money,
        ante=opts.ante or 1, round=0,
        hands_left=D.hands, discards_left=D.discards, hands_played=0,
        blind_type="none", blind_chips=300, blind_beaten=false,
        selection={}, hand_levels=hl,
        chips=0, total_chips=0,
        deck_count=52,
        pack_cards=nil, last_consumable=nil,
        rng=rng, _joker_n=0, _cons_n=0,
    }
end

function Sim.State.draw(state)
    if #state.hand >= state.hand_limit then return state end
    local n = math.min(state.hand_limit - #state.hand, #state.deck)
    for i = 1, n do state.hand[#state.hand+1] = table.remove(state.deck, 1) end
    return state
end

function Sim.State.rebuild_deck(state)
    local all = {}
    for _,c in ipairs(state.deck) do all[#all+1]=c end
    for _,c in ipairs(state.hand) do all[#all+1]=c end
    for _,c in ipairs(state.discard) do all[#all+1]=c end
    Sim.RNG.shuffle(state.rng, all)
    state.deck = all; state.hand = {}; state.discard = {}
    state.deck_count = #all
    return state
end

function Sim.State.interest(state)
    return math.min(math.floor(state.dollars / 5), 5)
end

function Sim.State.level_up(state, ht, amt)
    amt = amt or 1
    state.hand_levels[ht] = (state.hand_levels[ht] or 1) + amt
    return state
end

function Sim.State.add_joker(state, joker_def)
    if #state.jokers >= state.joker_slots then return false end
    state._joker_n = state._joker_n + 1
    state.jokers[#state.jokers+1] = {


        id = joker_def.id, edition = 0, eternal = false,
        uid = state._joker_n,
    }
    return true
end

function Sim.State.remove_joker(state, uid)
    for i = #state.jokers, 1, -1 do
        if state.jokers[i].uid == uid then
            table.remove(state.jokers, i)
            return true
        end
    end
    return false
end

-- ============================================================================


