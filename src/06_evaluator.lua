-- src/06_evaluator.lua — Poker hand evaluator

Sim.Eval = {}

local E = Sim.ENUMS
local STONE = E.ENHANCEMENT.STONE
local WILD = E.ENHANCEMENT.WILD

local function _cid(card) return card.enhancement == STONE and 0 or card.rank end

local function _x_same(num, hand)
    local counts = {}
    for i = 1, #hand do
        local id = _cid(hand[i])
        if id > 0 then
            counts[id] = counts[id] or {}
            counts[id][#counts[id]+1] = hand[i]
        end
    end
    local out = {}
    for rank = 14, 2, -1 do
        if counts[rank] and #counts[rank] == num then out[#out+1] = counts[rank] end
    end
    return out
end

local function _highest(hand)
    local best, bv = nil, -1
    local fallback = hand[1]
    for i = 1, #hand do
        local c = hand[i]
        if c.enhancement ~= STONE then
            local v = E.RANK_NOMINAL[c.rank] + c.rank * 0.01
            if v > bv then bv = v; best = c end
        end
    end
    return best and {best} or (fallback and {fallback} or {})
end

local function _is_wild(card) return card.enhancement == WILD end
local function _is_stone(card) return card.enhancement == STONE end

local function _flush(hand)
    if #hand ~= 5 then return {} end
    local suit = nil
    for i = 1, #hand do
        if _is_wild(hand[i]) then
        elseif _is_stone(hand[i]) then return {}
        else
            if not suit then suit = hand[i].suit
            elseif hand[i].suit ~= suit then return {} end
        end
    end
    return {hand}
end

local function _straight(hand)
    if #hand ~= 5 then return {} end
    local seen = {}
    for i = 1, #hand do
        local id = _cid(hand[i])
        if id > 1 and id < 15 then
            seen[id] = seen[id] or {}
            seen[id][#seen[id]+1] = hand[i]
        end
    end
    local br, bc = 0, {}
    local run, cards = 0, {}
    if seen[14] and seen[2] and seen[3] and seen[4] and seen[5] then
        br = 5
        for _, r in ipairs({14,2,3,4,5}) do
            for _, c in ipairs(seen[r]) do bc[#bc+1] = c end
        end
    end
    for r = 2, 14 do
        if seen[r] then
            run = run + 1
            for _, c in ipairs(seen[r]) do cards[#cards+1] = c end
            if run > br then br = run; bc = {} for _,c in ipairs(cards) do bc[#bc+1]=c end end
        else run = 0; cards = {} end
    end
    return br >= 5 and {bc} or {}
end

--- Returns: best_type, scoring_cards, all_hands_table
function Sim.Eval.get_hand(cards)
    if not cards or #cards == 0 then
        return E.HAND_TYPE.HIGH_CARD, {}, {}
    end
    local _5, _4, _3, _2 = _x_same(5,cards), _x_same(4,cards), _x_same(3,cards), _x_same(2,cards)
    local _fl, _st, _hi = _flush(cards), _straight(cards), _highest(cards)
    local HT = E.HAND_TYPE
    local best, best_sc, all = HT.HIGH_CARD, _hi, {}

    if #_5 > 0 and #_fl > 0 then
        all[HT.FLUSH_FIVE] = _5[1]
        if HT.FLUSH_FIVE < best then best = HT.FLUSH_FIVE; best_sc = _5[1] end
    end
    if #_3 > 0 and #_2 > 0 and #_fl > 0 then
        local fh = {}
        for _,c in ipairs(_3[1]) do fh[#fh+1]=c end
        for _,c in ipairs(_2[1]) do fh[#fh+1]=c end
        all[HT.FLUSH_HOUSE] = fh
        if HT.FLUSH_HOUSE < best then best = HT.FLUSH_HOUSE; best_sc = fh end
    end
    if #_5 > 0 then
        all[HT.FIVE_OF_A_KIND] = _5[1]
        if HT.FIVE_OF_A_KIND < best then best = HT.FIVE_OF_A_KIND; best_sc = _5[1] end
    end
    if #_fl > 0 and #_st > 0 then
        local set = {}
        for _,c in ipairs(_fl[1]) do set[c]=true end
        for _,c in ipairs(_st[1]) do set[c]=true end
        local sf = {}
        for c in pairs(set) do sf[#sf+1]=c end
        all[HT.STRAIGHT_FLUSH] = sf
        if HT.STRAIGHT_FLUSH < best then best = HT.STRAIGHT_FLUSH; best_sc = sf end
    end
    if #_4 > 0 then
        local sc = {}
        for _,c in ipairs(_4[1]) do sc[#sc+1]=c end
        all[HT.FOUR_OF_A_KIND] = sc
        if HT.FOUR_OF_A_KIND < best then best = HT.FOUR_OF_A_KIND; best_sc = sc end
        all[HT.THREE_OF_A_KIND] = {_4[1][1],_4[1][2],_4[1][3]}
        all[HT.PAIR] = {_4[1][1],_4[1][2]}
    end
    if #_3 > 0 and #_2 > 0 then
        local fh = {}
        for _,c in ipairs(_3[1]) do fh[#fh+1]=c end
        for _,c in ipairs(_2[1]) do fh[#fh+1]=c end
        all[HT.FULL_HOUSE] = fh
        if HT.FULL_HOUSE < best then best = HT.FULL_HOUSE; best_sc = fh end
        -- Do NOT cascade Three of a Kind or Pair from Full House (matches real game)
    end
    if #_fl > 0 then
        all[HT.FLUSH] = _fl[1]
        if HT.FLUSH < best then best = HT.FLUSH; best_sc = _fl[1] end
    end
    if #_st > 0 then
        all[HT.STRAIGHT] = _st[1]
        if HT.STRAIGHT < best then best = HT.STRAIGHT; best_sc = _st[1] end
    end
    if #_3 > 0 and not all[HT.FULL_HOUSE] then
        all[HT.THREE_OF_A_KIND] = _3[1]
        if HT.THREE_OF_A_KIND < best then best = HT.THREE_OF_A_KIND; best_sc = _3[1] end
        if not all[HT.PAIR] then all[HT.PAIR] = {_3[1][1],_3[1][2]} end
    end
    if #_2 >= 2 then
        local tp = {}
        for _,c in ipairs(_2[1]) do tp[#tp+1]=c end
        for _,c in ipairs(_2[2]) do tp[#tp+1]=c end

        all[HT.TWO_PAIR] = tp
        if HT.TWO_PAIR < best then best = HT.TWO_PAIR; best_sc = tp end
        if not all[HT.PAIR] then all[HT.PAIR] = _2[1] end
    end
    if #_2 > 0 then
        all[HT.PAIR] = _2[1]
        if HT.PAIR < best then best = HT.PAIR; best_sc = _2[1] end
    end
    all[HT.HIGH_CARD] = _hi
    return best, best_sc, all
end
