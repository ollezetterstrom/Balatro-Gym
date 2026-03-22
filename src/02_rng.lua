-- src/02_rng.lua — Deterministic LCG
-- Auto-split. Edit freely.

}

-- ============================================================================


--  SECTION 2 — DETERMINISTIC RNG (LCG)
-- ============================================================================

Sim.RNG = {}
function Sim.RNG.hash(s)
    local h = 0
    for i = 1, #s do
        h = (h + string.byte(s, i)) * 2654435761 % 4294967296
        h = ((h >> 16) ~ h) * 2246822519 % 4294967296
        h = ((h >> 13) ~ h) * 3266489917 % 4294967296
        h = (h >> 16) ~ h
    end
    return h % 4294967296
end
function Sim.RNG.new(seed) return { state = Sim.RNG.hash(seed) } end
function Sim.RNG.next(r)
    r.state = (r.state * 1664525 + 1013904223) % 4294967296
    return r.state / 4294967296
end
function Sim.RNG.int(r, lo, hi) return lo + math.floor(Sim.RNG.next(r) * (hi - lo + 1)) end
function Sim.RNG.shuffle(r, t)
    for i = #t, 2, -1 do
        local j = 1 + math.floor(Sim.RNG.next(r) * i)
        t[i], t[j] = t[j], t[i]
    end
