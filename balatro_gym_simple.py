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
    a = np.zeros(129, dtype=np.float32)
    for i in range(129):
        v = o[i + 1]; a[i] = float(v) if v is not None else 0.0
    return a


class BalatroSimpleEnv(gym.Env):

    def __init__(self):
        super().__init__()
        self.sim = _lua()           # Sim table
        self._rt = _RUNTIME         # LuaRuntime (for execute)
        self.E = self.sim.ENUMS
        self.observation_space = spaces.Box(0.0, 1.0, shape=(129,), dtype=np.float32)
        self.action_space = spaces.Discrete(ACTION_SIZE)
        self._s = None
        self._steps = 0

    def reset(self, *, seed=None, options=None):
        super().reset(seed=seed)
        s = str(int(seed) if seed is not None else 0)
        self._s = self._rt.execute(f"""
            local rng = Sim.RNG.new("{s}")
            local st = Sim.State.new({{rng=rng, seed="{s}",
                jokers={{ {{id=1, edition=0, eternal=false, uid=1}} }} }})
            Sim.Blind.init_ante(st)
            local bt = Sim.Blind.next_type(st)
            if bt then Sim.Blind.setup(st, bt); st.phase = 1 end
            return st
        """)
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
                self._rt.execute(f"""
                    local st = ...
                    for i = {n}, 1, -1 do
                        local c = table.remove(st.hand, i)
                        if c then st.discard[#st.discard+1] = c end
                    end
                    st.discards_left = st.discards_left - 1
                    Sim.State.draw(st)
                """, s)
        elif action < NUM_PLAY:
            combo = ALL_COMBOS[action]
            if all(i < len(s.hand) for i in combo):
                r = self._play(s, combo)
            else:
                r = -0.1

        done = s.phase in (E.PHASE.GAME_OVER, E.PHASE.WIN) or self._steps > 500
        return _obs(self.sim.Obs.encode(s)), r, done, False, {"ante": s.ante}

    def _play(self, state, combo):
        # Use Lua for hand manipulation (avoids Python↔Lua table issues)
        combo_str = ",".join(str(i + 1) for i in combo)  # 1-indexed for Lua
        result = self._rt.execute(f"""
            local st = ...
            local indices = {{ {combo_str} }}
            local played = {{}}
            for _, idx in ipairs(indices) do played[#played+1] = st.hand[idx] end

            local total, chips, mult, ht = Sim.Engine.calculate(st, played)

            st.total_chips = st.total_chips + total
            st.chips = st.chips + total
            st.hands_left = st.hands_left - 1
            st.hands_played = st.hands_played + 1

            for _, c in ipairs(played) do st.discard[#st.discard+1] = c end

            table.sort(indices, function(a,b) return a > b end)
            for _, idx in ipairs(indices) do table.remove(st.hand, idx) end

            Sim.State.draw(st)
            if st.chips >= st.blind_chips then st.blind_beaten = true end

            return total
        """, state)
        return max(0.01, float(np.log(max(1, result))) * 0.01 - 0.05 * state.hands_played)

    def _auto_shop(self, s):
        self._rt.execute("""
            local st = ...
            local shop = st.shop
            if shop then
                for si = 1, 2 do
                    local jk = shop.jokers[si]
                    if jk and st.dollars >= jk.cost and #st.jokers < st.joker_slots then
                        Sim.Shop.buy_joker(st, si); break
                    end
                end
                if shop.consumable and #st.consumables < st.consumable_slots then
                    Sim.Shop.buy_consumable(st)
                end
            end
            st.shop = nil
            local bt = Sim.Blind.next_type(st)
            if bt then Sim.Blind.setup(st, bt); st.phase = Sim.ENUMS.PHASE.SELECTING_HAND end
        """, s)

    def _advance(self, s):
        self._rt.execute("""
            local st = ...
            local E = Sim.ENUMS
            local names = {"Small","Big","Boss"}
            for i = 1, 3 do
                if names[i] == st.blind_type then Sim.Blind.mark_done(st, i); break end
            end
            local rd = Sim.Blind.reward(st.blind_type=="Small" and 1 or st.blind_type=="Big" and 2 or 3)
            st.dollars = st.dollars + rd + Sim.State.interest(st)
            for _, c in ipairs(st.hand) do st.discard[#st.discard+1] = c end
            st.hand = {}; st.selection = {}
            local nb = Sim.Blind.next_type(st)
            if not nb then
                st.ante = st.ante + 1
                if st.ante > 8 then st.phase = E.PHASE.WIN; return end
                Sim.Blind.init_ante(st)
                nb = Sim.Blind.next_type(st)
                -- auto shop
                local shop = st.shop
                if shop then
                    for si = 1, 2 do
                        local jk = shop.jokers[si]
                        if jk and st.dollars >= jk.cost and #st.jokers < st.joker_slots then
                            Sim.Shop.buy_joker(st, si); break
                        end
                    end
                    if shop.consumable and #st.consumables < st.consumable_slots then
                        Sim.Shop.buy_consumable(st)
                    end
                end
                st.shop = nil
            end
            Sim.Blind.setup(st, nb)
            st.phase = E.PHASE.SELECTING_HAND
        """, s)

    def render(self):
        if self._s:
            print(f"Ante {self._s.ante} | ${self._s.dollars} | "
                  f"{self._s.chips}/{self._s.blind_chips}")

    def close(self): self._s = None
