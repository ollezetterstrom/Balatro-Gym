#!/usr/bin/env python3
"""
build.py — Assemble src/*.lua modules into a standalone balatro_sim.lua.

Usage:
    python build.py           — Merge src/*.lua into balatro_sim.lua (default)
    python build.py merge     — Same as above
    python build.py check     — Verify all src files exist and load order is correct
"""

import sys
from pathlib import Path

ROOT = Path(__file__).parent
SRC = ROOT / "src"
MONOLITH = ROOT / "balatro_sim.lua"

# Load order matters — must match the dofile chain in balatro_sim.lua
MODULES = [
    "00_header.lua",
    "01_enums.lua",
    "02_rng.lua",
    "03_cards.lua",
    "04_jokers.lua",
    "05_consumables.lua",
    "06_evaluator.lua",
    "07_engine.lua",
    "08_state.lua",
    "09_blinds.lua",
    "10_shop.lua",
    "11_observation.lua",
    "12_env.lua",
    "13_test.lua",
]


def merge():
    """Merge src/*.lua into a standalone balatro_sim.lua."""
    if not SRC.exists():
        print("src/ not found. Nothing to merge.")
        sys.exit(1)

    chunks = []
    total_lines = 0
    for name in MODULES:
        fpath = SRC / name
        if not fpath.exists():
            print(f"  MISSING: {name}")
            sys.exit(1)
        with open(fpath) as fh:
            content = fh.read()
        # Strip the first line header comment (-- src/NN_name.lua — ...)
        lines = content.split("\n")
        if lines and lines[0].startswith("-- src/"):
            lines = lines[1:]
        stripped = "\n".join(lines)
        chunks.append(stripped)
        total_lines += stripped.count("\n") + 1

    header = """\
--[[
    balatro_sim.lua — Headless Balatro Simulation Engine v3

    Merged build from src/*.lua modules. Do not edit directly — edit src/ instead.
    To regenerate: python build.py merge

    Usage:
        lua balatro_sim.lua              — runs self-tests + random agent
        local Sim = dofile("balatro_sim.lua")  — use as library

    API:
        Sim.Env.reset(seed) → obs, info
        Sim.Env.step(state, action_type, action_value) → obs, reward, done, info
        Sim.Obs.encode(state) → flat float array (129 floats)
        Sim.Env.action_spec → { types, obs_dim }
]]

"""

    merged = header + "\n".join(chunks) + "\n"
    with open(MONOLITH, "w") as f:
        f.write(merged)

    print(f"Merged {len(chunks)} files → {MONOLITH.name} ({total_lines} lines)")


def check():
    """Verify all src files exist."""
    print("Checking src/ modules...\n")
    all_ok = True
    for name in MODULES:
        fpath = SRC / name
        if fpath.exists():
            with open(fpath) as fh:
                n = sum(1 for _ in fh)
            print(f"  [OK]   {name:30s} ({n} lines)")
        else:
            print(f"  [MISS] {name}")
            all_ok = False
    print()
    if all_ok:
        print(f"All {len(MODULES)} modules present.")
    else:
        print("Some modules missing!")
        sys.exit(1)


if __name__ == "__main__":
    cmd = sys.argv[1] if len(sys.argv) > 1 else "merge"
    {"merge": merge, "check": check}.get(cmd, lambda: print(f"Unknown: {cmd} (use: merge, check)"))()
