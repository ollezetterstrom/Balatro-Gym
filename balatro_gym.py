"""
balatro_gym.py — Gymnasium wrapper for balatro_sim.lua

Requires: lupa, gymnasium, numpy
Install:  pip install -r requirements.txt

Usage:
    import gymnasium as gym
    import balatro_gym

    env = gym.make("BalatroGym-v0")
    obs, info = env.reset(seed=42)
    obs, reward, done, trunc, info = env.step((1, 31))  # select 5 cards
"""

from __future__ import annotations
from pathlib import Path

import gymnasium as gym
import numpy as np
from gymnasium import spaces

# ---------------------------------------------------------------------------
# Lazy lupa import (so the module can be inspected without lupa installed)
# ---------------------------------------------------------------------------

_LUA_RUNTIME = None
_LUA_SIM = None


def _get_lua():
    """Load the Lua engine once, return the Sim table."""
    global _LUA_RUNTIME, _LUA_SIM
    if _LUA_SIM is not None:
        return _LUA_SIM

    from lupa import LuaRuntime

    _LUA_RUNTIME = LuaRuntime(unpack_returned_tuples=True)

    # Find balatro_sim.lua next to this file
    lua_path = Path(__file__).parent / "balatro_sim.lua"
    if not lua_path.exists():
        lua_path = Path("balatro_sim.lua")
    if not lua_path.exists():
        raise FileNotFoundError(
            f"Cannot find balatro_sim.lua. Place it next to {__file__} or in cwd."
        )

    with open(lua_path, "r") as f:
        lua_code = f.read()

    _LUA_SIM = _LUA_RUNTIME.execute(lua_code)
    return _LUA_SIM


# ---------------------------------------------------------------------------
# Lua <-> Python conversion helpers
# ---------------------------------------------------------------------------


def _lua_table_to_list(table, length=None):
    """Convert a Lua 1-indexed table to a Python list."""
    if table is None:
        return []
    if length is None:
        try:
            length = len(table)
        except TypeError:
            length = 0
    return [table[i + 1] for i in range(length)]


def _obs_to_numpy(lua_obs, dim=129):
    """Convert Lua observation table to numpy float32 array."""
    arr = np.zeros(dim, dtype=np.float32)
    for i in range(dim):
        val = lua_obs[i + 1]  # Lua tables are 1-indexed
        arr[i] = float(val) if val is not None else 0.0
    return arr


# ---------------------------------------------------------------------------
# Environment
# ---------------------------------------------------------------------------


class BalatroEnv(gym.Env):
    """
    Gymnasium environment wrapping the Balatro Lua simulation engine.

    Observation:
        Box(129,) — flat float32 vector encoding hand, jokers, game state.

    Action:
        MultiDiscrete([6, 65536])
        - action[0]: action type (1-6)
        - action[1]: action value (0-65535)

    Reward:
        log(chips) on play, -0.05 per hand played, +10 blind beaten,
        +50 ante up, +200 win, -100 game over.
    """

    metadata = {"render_modes": ["human"]}

    def __init__(self, *, render_mode=None, seed=None):
        super().__init__()
        self.render_mode = render_mode

        self.sim = _get_lua()
        self.lua_env = self.sim.Env

        # Observation bound: hand_levels log encoding can reach ~1.3 at level 100
        self.observation_space = spaces.Box(
            low=0.0, high=2.0, shape=(129,), dtype=np.float32
        )
        self.action_space = spaces.MultiDiscrete([7, 65536])

        self._lua_state = None
        self._seed = seed

    def reset(self, *, seed=None, options=None):
        if seed is not None:
            seed = int(seed)
        super().reset(seed=seed)

        lua_seed = str(seed if seed is not None else self._seed or 42)
        lua_obs, lua_info = self.lua_env.reset(lua_seed)

        self._lua_state = self._build_state(lua_seed)

        obs = _obs_to_numpy(lua_obs)
        info = {"seed": lua_seed, "ante": 1}
        return obs, info

    def _build_state(self, seed_str):
        """Build state in Lua by calling the engine's reset/init sequence."""
        runtime = _LUA_RUNTIME
        # Pass seed as argument to avoid f-string injection
        return runtime.execute(
            """
            local seed_str = ...
            local rng = Sim.RNG.new(seed_str)
            local state = Sim.State.new({rng = rng, seed = seed_str})
            Sim.Blind.init_ante(state)
            local btype = Sim.Blind.next_type(state)
            if btype then
                Sim.Blind.setup(state, btype)
                state.phase = Sim.ENUMS.PHASE.SELECTING_HAND
            end
            return state
            """,
            seed_str,
        )

    def step(self, action):
        if self._lua_state is None:
            raise RuntimeError("Call reset() before step()")

        action_type = int(action[0])
        action_value = int(action[1])

        try:
            lua_obs, reward, done = self.lua_env.step(
                self._lua_state, action_type, action_value
            )
        except Exception as e:
            # Return terminal state on Lua errors to avoid crashing training
            obs = _obs_to_numpy({})
            return obs, -100.0, True, False, {"error": str(e)}

        obs = _obs_to_numpy(lua_obs)
        truncated = False
        info = {
            "phase": self._lua_state.phase,
            "ante": self._lua_state.ante,
            "chips": self._lua_state.chips,
            "dollars": self._lua_state.dollars,
        }

        return obs, float(reward), bool(done), truncated, info

    def render(self):
        if self.render_mode != "human":
            return
        if self._lua_state is None:
            return
        print(f"Ante {self._lua_state.ante} | "
              f"${self._lua_state.dollars} | "
              f"Chips: {self._lua_state.chips}/{self._lua_state.blind_chips} | "
              f"Hands: {self._lua_state.hands_left} | "
              f"Discards: {self._lua_state.discards_left}")

    def close(self):
        self._lua_state = None


# ---------------------------------------------------------------------------
# Gym registration
# ---------------------------------------------------------------------------

try:
    gym.register(
        id="BalatroGym-v0",
        entry_point="balatro_gym:BalatroEnv",
    )
except gym.error.Error:
    pass  # Already registered


# ---------------------------------------------------------------------------
# CLI quick-test
# ---------------------------------------------------------------------------

if __name__ == "__main__":
    print("Balatro-Gym Python Bridge")
    print("=" * 40)

    env = BalatroEnv()
    obs, info = env.reset(seed=42)
    print(f"Observation shape: {obs.shape}")
    print(f"Info: {info}")

    for step in range(5):
        action = env.action_space.sample()
        obs, reward, done, trunc, info = env.step(action)
        print(f"Step {step+1}: type={action[0]} value={action[1]} "
              f"reward={reward:.2f} done={done}")
        if done:
            break

    env.close()
    print("Done.")
