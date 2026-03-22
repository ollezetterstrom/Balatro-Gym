-- src/03_cards.lua — Card constructor, deck, chips
-- Auto-split. Edit freely.

--  SECTION 3 — CARD CONSTRUCTOR
-- ============================================================================

Sim.Card = {}
function Sim.Card.new(rank, suit, enh, ed, seal, pb)
    return { rank=rank, suit=suit, enhancement=enh or 0, edition=ed or 0,
             seal=seal or 0, perma_bonus=pb or 0 }
end
function Sim.Card.new_deck()
    local d = {}
    for s = 1, 4 do for r = 2, 14 do d[#d+1] = Sim.Card.new(r, s) end end
    return d
end
function Sim.Card.chips(card)
    if card.enhancement == 6 then return 50 + card.perma_bonus end  -- Stone
    return Sim.ENUMS.RANK_NOMINAL[card.rank] + card.perma_bonus
end
function Sim.Card.str(card)
    local E = Sim.ENUMS
    local t = (E.RANK_SYM[card.rank] or "?") .. (E.SUIT_SYM[card.suit] or "?")
    if card.enhancement == 1 then t = t.."+30" end
    if card.enhancement == 4 then t = t.."x2" end
    if card.enhancement == 6 then t = t.."." end


    if card.edition == 1 then t = t.."[F]" end
    if card.edition == 2 then t = t.."[H]" end
    if card.edition == 3 then t = t.."[P]" end
    return t
end

-- ============================================================================


