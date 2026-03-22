-- src/00_header.lua — Header + Sim = {}
-- Auto-split. Edit freely.



--[[
    balatro_sim.lua — Headless Balatro Simulation Engine v3

    Pure-Lua, zero-graphics simulation of Balatro for AI training.
    Deterministic RNG, stateless scoring, synchronous execution.

    Usage:
        lua balatro_sim.lua              — runs self-tests + random agent
        local Sim = dofile("balatro_sim.lua")  — use as library

    API:
        Sim.Env.reset(seed) → obs, info
        Sim.Env.step(state, action_type, action_value) → obs, reward, done, info
        Sim.Obs.encode(state) → flat float array (129 floats)
        Sim.Env.action_spec → { types, obs_dim }

    Observation layout (124 floats):
        [0..47]   8 hand card slots × 6 features
        [48..62]  5 joker slots × 3 features
        [63..92]  30 global features (chips%, $, hands, discards, ante, levels, phase...)
        [93..100] 2 consumable slots × 2 features + misc
        [101..130] 5 pack card slots × 6 features (during PACK_OPEN phase)
        [131..124] shop flags, counts, spare
]]

Sim = Sim or {}



-- ============================================================================


