-- src/00_header.lua — Header + Sim = {}

--[[
    balatro_sim.lua — Headless Balatro Simulation Engine v3

    Pure-Lua, zero-graphics simulation of Balatro for AI training.
    Deterministic RNG, stateless scoring, synchronous execution.

    Usage:
        lua validate.lua                     — run scoring validation (49 tests)
        lua -e "_SIM_RUN_TESTS=true" balatro_sim.lua  — run self-tests + random agent
        local Sim = dofile("balatro_sim.lua")  — use as library

    API:
        Sim.Env.reset(seed) → obs, info
        Sim.Env.step(state, action_type, action_value) → obs, reward, done, info
        Sim.Obs.encode(state) → flat float array (129 floats)
        Sim.Env.action_spec → { types, obs_dim }

    Observation layout (129 floats, 1-indexed Lua):
        [1..48]    8 hand card slots × 6 features (rank, suit, enh, edition, seal, has_card)
        [49..63]   5 joker slots × 3 features (id, edition, has_joker)
        [64..71]   8 global features (chips%, $, hands_left, discards_left, ante, round, blind_beaten, deck%)
        [72..83]   12 hand levels (log-scaled, capped at 1.0)
        [84..86]   Phase one-hot (SELECTING_HAND, SHOP, PACK_OPEN)
        [87]       Selection count / 8
        [88..91]   2 consumable slots × 2 features (id, has_consumable)
        [92]       Pack open flag
        [93..122]  5 pack card slots × 6 features
        [123..126] Shop items present (joker1, joker2, booster, consumable)
        [127]      Joker count / 5
        [128]      Consumable count / 2
        [129]      Spare (currently round_dollars or 0)
]]

Sim = Sim or {}
return Sim
