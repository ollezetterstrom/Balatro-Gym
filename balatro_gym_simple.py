"""
balatro_gym_simple.py — Simplified Gymnasium env for Balatro training.

247 Discrete actions: 246 card combinations + 1 discard.
Auto-handles shop/blinds. Agent only decides WHAT to play.
"""

from __future__ import annotations
from pathlib import Path
from itertools import combinations

import gymnasium as gym
import numpy as np
from gymnasium import spaces

# Pre-compute all card combos (1-5 cards from 8 positions)
ALL_COMBOS = [c for r in range(1, 6) for c in combinations(range(8), r)]
NUM_PLAY = len(ALL_COMBOS)   # 246
DISCARD_ACT = NUM_PLAY       # 246
ACTION_SIZE = NUM_PLAY + 1   # 247

_SIM = None
_RUNTIME = None
def _lua():
    global _SIM, _RUNTIME
    if _SIM is None:
        from lupa import LuaRuntime
        _RUNTIME = LuaRuntime(unpack_returned_tuples=True)
        p = Path(__file__).parent / "balatro_sim.lua"
        if not p.exists(): p = Path("balatro_sim.lua")
        with open(p) as f:
            _SIM = _RUNTIME.execute(f.read())
    return _SIM

def _obs(o):
    a = np.zeros(180, dtype=np.float32)
    for i in range(180):
        v = o[i + 1]; a[i] = float(v) if v is not None else 0.0
    return a


class BalatroSimpleEnv(gym.Env):

    def __init__(self):
        super().__init__()
        self.sim = _lua()
        self._rt = _RUNTIME
        self.E = self.sim.ENUMS
        self.observation_space = spaces.Box(0.0, 2.0, shape=(180,), dtype=np.float32)
        self.action_space = spaces.Discrete(ACTION_SIZE)
        self._s = None
        self._steps = 0
        self._max_steps = 500

    def reset(self, *, seed=None, options=None):
        super().reset(seed=seed)
        s = str(int(seed) if seed is not None else 0)
        self._s = self._rt.execute(
            """
            local seed_str = ...
            local rng = Sim.RNG.new(seed_str)
            local st = Sim.State.new({rng=rng, seed=seed_str,
                jokers={ {id=1, edition=0, eternal=false, uid=1}} })
            Sim.Blind.init_ante(st)
            local bt = Sim.Blind.next_type(st)
            if bt then Sim.Blind.setup(st, bt); st.phase = 1 end
            return st
            """,
            s,
        )
        self._steps = 0
        return _obs(self.sim.Obs.encode(self._s)), {"ante": 1}

    def step(self, action):
        self._steps += 1
        s = self._s
        E = self.E
        r = 0.0

        # Auto-handle meta phases
        while s.phase in (E.PHASE.SHOP, E.PHASE.PACK_OPEN, E.PHASE.BLIND_SELECT):
            if s.phase == E.PHASE.SHOP:
                self._auto_shop(s)
            elif s.phase == E.PHASE.PACK_OPEN:
                if s.pack_cards and len(s.pack_cards) > 0:
                    self.sim.Shop.select_pack(s, 1)
                else:
                    self.sim.Shop.skip_pack(s)
            elif s.phase == E.PHASE.BLIND_SELECT:
                bt = self.sim.Blind.next_type(s)
                if bt: self.sim.Blind.setup(s, bt); s.phase = E.PHASE.SELECTING_HAND

        # Terminal
        if s.phase in (E.PHASE.GAME_OVER, E.PHASE.WIN):
            return _obs(self.sim.Obs.encode(s)), (200.0 if s.phase == E.PHASE.WIN else -100.0), True, False, {}

        # Auto-advance if blind beaten
        if s.blind_beaten:
            self._advance(s)
            return _obs(self.sim.Obs.encode(s)), 10.0, False, False, {"ante": s.ante}

        # Out of hands
        if s.hands_left <= 0:
            return _obs(self.sim.Obs.encode(s)), -100.0, True, False, {}

        # Playing phase
        if action == DISCARD_ACT:
            if s.discards_left > 0 and len(s.hand) >= 1:
                n = min(5, len(s.hand))
                self.sim.discard_first_n(s, n)
        elif action < NUM_PLAY:
            combo = ALL_COMBOS[action]
            if all(i < len(s.hand) for i in combo):
                r = self._play(s, combo)
            else:
                r = -0.1

        done = s.phase in (E.PHASE.GAME_OVER, E.PHASE.WIN) or self._steps > self._max_steps
        return _obs(self.sim.Obs.encode(s)), r, done, False, {"ante": s.ante}

    def _play(self, state, combo):
        combo_indices = [str(i + 1) for i in combo]  # 1-indexed for Lua
        indices_str = ",".join(combo_indices)
        result = self._rt.execute(
            "local st, s = ... "
            "local indices = {} "
            "for w in s:gmatch('%d+') do indices[#indices+1] = tonumber(w) end "
            "return Sim.play_cards_by_indices(st, indices)",
            state, indices_str,
        )
        return max(0.01, float(np.log(max(1, result))) * 0.01 - 0.05 * state.hands_played)

    def _auto_shop(self, s):
        self.sim.auto_shop(s)

    def _advance(self, s):
        self.sim.advance_simple(s)

    def render(self):
        if self._s:
            print(f"Ante {self._s.ante} | ${self._s.dollars} | "
                  f"{self._s.chips}/{self._s.blind_chips}")

    def close(self): self._s = None
