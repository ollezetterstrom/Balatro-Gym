"""
test_fidelity.py — Generate state-transition records for correctness testing.

Runs N random actions in the Lua engine, saves (state, action, next_state, reward)
tuples to a JSON file. When the Rust port is built, load this JSON and verify
the Rust engine produces identical output for every transition.

Usage:
    python test_fidelity.py [--steps 1000] [--output trajectories.json]

Requires: lupa (no gymnasium needed)
"""

import json
import argparse
import sys
from pathlib import Path


def load_lua_engine():
    """Load balatro_sim.lua via lupa and return the Sim table."""
    try:
        from lupa import LuaRuntime
    except ImportError:
        print("Error: lupa not installed. Run: pip install lupa")
        sys.exit(1)

    lua = LuaRuntime(unpack_returned_tuples=True)

    lua_path = Path(__file__).parent / "balatro_sim.lua"
    if not lua_path.exists():
        lua_path = Path("balatro_sim.lua")
    if not lua_path.exists():
        print("Error: balatro_sim.lua not found")
        sys.exit(1)

    with open(lua_path, "r") as f:
        return lua.execute(f.read())


def obs_to_list(lua_obs, dim=129):
    """Convert Lua observation table to Python list."""
    return [float(lua_obs[i + 1] or 0.0) for i in range(dim)]


def random_action(sim, state):
    """Pick a random legal action for the current phase."""
    E = sim.ENUMS
    rng = state.rng
    phase = state.phase

    if phase == E.PHASE.SELECTING_HAND:
        if state.hands_left <= 0 and not state.blind_beaten:
            return None  # terminal
        if state.blind_beaten:
            return (5, 3)  # advance
        if len(state.selection) == 0:
            # Select random cards
            mask = 0
            n = min(5, len(state.hand))
            for i in range(n):
                bit = sim.RNG.int(rng, 0, len(state.hand) - 1)
                mask |= 1 << bit
            return (1, mask) if mask > 0 else (1, 1)
        else:
            # Play or discard
            if sim.RNG.next(rng) < 0.7 or state.discards_left <= 0:
                return (2, 1)  # play
            else:
                return (2, 2)  # discard

    elif phase == E.PHASE.SHOP:
        r = sim.RNG.next(rng)
        if r < 0.3 and state.shop and state.shop.jokers[1]:
            return (3, 1)  # buy joker 1
        elif r < 0.5 and state.shop and state.shop.jokers[2]:
            return (3, 2)  # buy joker 2
        elif r < 0.6 and state.shop and state.shop.booster:
            return (3, 3)  # buy booster
        elif r < 0.7 and state.shop and state.shop.consumable:
            return (3, 4)  # buy consumable
        else:
            return (5, 0)  # end shop

    elif phase == E.PHASE.PACK_OPEN:
        if state.pack_cards:
            pick = sim.RNG.int(rng, 1, len(state.pack_cards))
            return (1, 1 << (pick - 1))
        return (5, 0)  # skip

    elif phase == E.PHASE.BLIND_SELECT:
        return (5, 1)  # fight

    return None  # terminal


def run_fidelity_test(n_steps=1000, seed_prefix="FIDELITY"):
    """Run n_steps random actions and record every transition."""
    sim = load_lua_engine()
    records = []

    for episode in range(max(1, n_steps // 50)):
        seed = f"{seed_prefix}_{episode}"
        lua_obs, _ = sim.Env.reset(seed)
        state = _reconstruct_state(sim, seed)

        step_in_ep = 0
        while step_in_ep < 60:
            action = random_action(sim, state)
            if action is None:
                break

            obs_before = obs_to_list(lua_obs)

            lua_obs, reward, done = sim.Env.step(state, action[0], action[1])

            obs_after = obs_to_list(lua_obs)

            records.append({
                "episode": episode,
                "step": step_in_ep,
                "seed": seed,
                "action_type": action[0],
                "action_value": action[1],
                "reward": float(reward),
                "done": bool(done),
                "phase_before": int(obs_before[83] * 2 + obs_before[84]),
                "phase_after": int(obs_after[83] * obs_after[84] + obs_after[85]),
                "chips_before": state.chips,
                "ante": state.ante,
            })

            step_in_ep += 1
            if done:
                break

    return records


def _reconstruct_state(sim, seed_str):
    """Same state reconstruction as the gym wrapper."""
    E = sim.ENUMS
    rng = sim.RNG.new(seed_str)
    state = sim.State.new({"rng": rng, "seed": seed_str})
    sim.Blind.init_ante(state)
    btype = sim.Blind.next_type(state)
    if btype:
        sim.Blind.setup(state, btype)
        state.phase = E.PHASE.SELECTING_HAND
    return state


def main():
    parser = argparse.ArgumentParser(description="Balatro fidelity tester")
    parser.add_argument("--steps", type=int, default=1000, help="Number of transitions")
    parser.add_argument("--output", type=str, default="trajectories.json", help="Output file")
    args = parser.parse_args()

    print(f"Running {args.steps} transitions...")
    records = run_fidelity_test(args.steps)

    with open(args.output, "w") as f:
        json.dump(records, f, indent=2)

    print(f"Saved {len(records)} records to {args.output}")
    print(f"Episodes: {max(r['episode'] for r in records) + 1 if records else 0}")
    print(f"Antes reached: {set(r['ante'] for r in records)}")


if __name__ == "__main__":
    main()
