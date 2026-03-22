-- balatro_sim.lua — Development loader
-- Loads all src/*.lua in order. For distribution: python build.py

local dir = debug.getinfo(1,"S").source:match("@?(.*/)") or "./"
package.path = dir.."src/?.lua;"..package.path

local Sim = dofile(dir..'src/00_header.lua')
dofile(dir..'src/01_enums.lua')
dofile(dir..'src/02_rng.lua')
dofile(dir..'src/03_cards.lua')
dofile(dir..'src/04_jokers.lua')
dofile(dir..'src/05_consumables.lua')
dofile(dir..'src/06_evaluator.lua')
dofile(dir..'src/07_engine.lua')
dofile(dir..'src/08_state.lua')
dofile(dir..'src/09_blinds.lua')
dofile(dir..'src/10_shop.lua')
dofile(dir..'src/11_observation.lua')
dofile(dir..'src/12_env.lua')
_SIM_RUN_TESTS = true
dofile(dir..'src/13_test.lua')  -- runs tests

return Sim
