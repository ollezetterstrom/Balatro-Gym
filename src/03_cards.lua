-- src/03_cards.lua — Card constructor, deck, chips

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
    if card.enhancement == Sim.ENUMS.ENHANCEMENT.STONE then return 50 + card.perma_bonus end
    return Sim.ENUMS.RANK_NOMINAL[card.rank] + card.perma_bonus
end
function Sim.Card.str(card)
    local E = Sim.ENUMS
    local t = (E.RANK_SYM[card.rank] or "?") .. (E.SUIT_SYM[card.suit] or "?")
    if card.enhancement == E.ENHANCEMENT.BONUS then t = t.."+30" end
    if card.enhancement == E.ENHANCEMENT.GLASS then t = t.."x2" end
    if card.enhancement == E.ENHANCEMENT.STONE then t = t.."." end
    if card.edition == E.EDITION.FOIL then t = t.."[F]" end
    if card.edition == E.EDITION.HOLO then t = t.."[H]" end
    if card.edition == E.EDITION.POLYCHROME then t = t.."[P]" end
    return t
end
