#!/usr/bin/env python3
"""
build.py — Split balatro_sim.lua into src/*.lua modules, or reassemble them.

Usage:
    python build.py split     — Split monolith into src/*.lua
    python build.py merge     — Merge src/*.lua into balatro_sim.lua
    python build.py           — Same as merge (default)
"""

import sys
from pathlib import Path

ROOT = Path(__file__).parent
SRC = ROOT / "src"
MONOLITH = ROOT / "balatro_sim.lua"

# (filename, start_line_1indexed, end_line_1inclusive, description)
# Hard-coded from SECTION comments. Run `grep -n "SECTION" balatro_sim.lua` to update.
MODULES = [
    ("00_header",      1,    34,  "Header + Sim = {}"),
    ("01_enums",       35,   113, "Enums, HAND_BASE, DEFAULTS"),
    ("02_rng",         114,  147, "Deterministic LCG"),
    ("03_cards",       148,  181, "Card constructor, deck, chips"),
    ("04_jokers",      182,  349, "Joker definitions (all)"),
    ("05_consumables", 350,  444, "Consumables, pool, advanced jokers"),
    ("06_evaluator",   445,  604, "Poker hand evaluator"),
    ("07_engine",      605,  692, "Scoring engine"),
    ("08_state",       693,  775, "Game state, draw, discard, joker ops"),
    ("09_blinds",      776,  895, "Blind system, boss blinds"),
    ("10_shop",        896,  1011,"Shop, economy, packs"),
    ("11_observation", 1012, 1157,"Observation encoder"),
    ("12_env",         1158, 1532,"Gymnasium env (reset/step/handlers)"),
    ("13_test",        1533, 1762,"Self-tests, random agent, return Sim"),
]


def split():
    """Split balatro_sim.lua into src/*.lua files."""
    SRC.mkdir(exist_ok=True)

    with open(MONOLITH, "r") as f:
        all_lines = f.readlines()

    for name, start, end, desc in MODULES:
        # Convert to 0-indexed, end is inclusive
        chunk = all_lines[start - 1 : end]
        header = f"-- src/{name}.lua — {desc}\n-- Auto-split. Edit freely.\n\n"
        outpath = SRC / f"{name}.lua"
        with open(outpath, "w") as f:
            f.write(header + "".join(chunk))
        print(f"  {name}.lua  ({len(chunk)} lines)")

    # Write loader
    lines = [
        "-- balatro_sim.lua — Development loader",
        "-- Loads all src/*.lua in order. For distribution: python build.py",
        "",
        'local dir = debug.getinfo(1,"S").source:match("@?(.*/)") or "./"',
        'package.path = dir.."src/?.lua;"..package.path',
        "",
    ]
    for name, _, _, _ in MODULES:
        if name == "00_header":
            lines.append(f"local Sim = dofile(dir..'src/{name}.lua')")
        elif name == "13_test":
            lines.append(f"dofile(dir..'src/{name}.lua')  -- runs tests")
        else:
            lines.append(f"dofile(dir..'src/{name}.lua')")
    lines.append("")
    lines.append("return Sim")
    lines.append("")

    with open(ROOT / "balatro_sim_dev.lua", "w") as f:
        f.write("\n".join(lines))
    print(f"\n  balatro_sim_dev.lua (loader)")

    print(f"\nSplit {len(MODULES)} modules into src/")


def merge():
    """Merge src/*.lua back into balatro_sim.lua."""
    if not SRC.exists():
        print("src/ not found. Run: python build.py split")
        sys.exit(1)

    files = sorted(SRC.glob("*.lua"))
    chunks = []
    for f in files:
        with open(f) as fh:
            content = fh.read()
        # Strip auto-split header
        lines = content.split("\n")
        skip = 0
        for line in lines:
            if line.startswith("-- src/") or line.startswith("-- Auto-split"):
                skip += 1
            else:
                break
        chunks.append("\n".join(lines[skip:]))

    merged = "\n".join(chunks)
    with open(MONOLITH, "w") as f:
        f.write(merged)

    print(f"Merged {len(files)} files → {MONOLITH.name} ({len(merged.split(chr(10)))} lines)")


if __name__ == "__main__":
    cmd = sys.argv[1] if len(sys.argv) > 1 else "merge"
    {"split": split, "merge": merge}.get(cmd, lambda: print(f"Unknown: {cmd}"))()
