--[[
    balatro_sim.lua — Headless Balatro Simulation Engine v3

    Loader: imports all src/*.lua modules in order.
    For a merged single-file build: python build.py merge

    Usage:
        lua balatro_sim.lua              — print engine info
        lua validate.lua                 — run scoring validation (49 tests)
        local Sim = dofile("balatro_sim.lua")  — use as library

    API:
        Sim.Env.reset(seed) → obs, info
        Sim.Env.step(state, action_type, action_value) → obs, reward, done, info
        Sim.Obs.encode(state) → flat float array (129 floats)
        Sim.Env.action_spec → { types, obs_dim }
]]

local dir = debug.getinfo(1, "S").source:match("@?(.*[/\\])") or "./"
package.path = dir .. "src/?.lua;" .. package.path

local Sim = dofile(dir .. "src/00_header.lua")
dofile(dir .. "src/01_enums.lua")
dofile(dir .. "src/02_rng.lua")
dofile(dir .. "src/03_cards.lua")
dofile(dir .. "src/04_jokers.lua")
dofile(dir .. "src/05_consumables.lua")
dofile(dir .. "src/06_evaluator.lua")
dofile(dir .. "src/07_engine.lua")
dofile(dir .. "src/08_state.lua")
dofile(dir .. "src/09_blinds.lua")
dofile(dir .. "src/10_shop.lua")
dofile(dir .. "src/11_observation.lua")
dofile(dir .. "src/12_env.lua")

if _SIM_RUN_TESTS then
    dofile(dir .. "src/13_test.lua")
end

return Sim
