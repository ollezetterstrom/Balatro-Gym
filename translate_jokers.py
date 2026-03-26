#!/usr/bin/env python3
"""
translate_jokers.py — Extract joker behaviors from real Balatro card.lua
and produce translated stubs for our _reg_joker format.

Usage:
    python translate_jokers.py --game-dir path/to/Balatro --dry-run
    python translate_jokers.py --game-dir path/to/Balatro --output joker_stubs.lua
"""

import re
import sys
import argparse
from pathlib import Path


def extract_blocks(lua_code: str) -> list[dict]:
    """Extract joker behavior blocks from Card:calculate_joker().

    Each block is a raw if-block for one joker, preserving the full
    condition and return logic.
    """
    lines = lua_code.split("\n")
    blocks = []

    # Find the function
    start = 0
    for i, line in enumerate(lines):
        if "function Card:calculate_joker" in line:
            start = i
            break

    i = start
    while i < len(lines):
        line = lines[i].strip()

        # Match: if self.ability.name == 'JokerName'
        m = re.match(r"""\s*if\s+self\.ability\.name\s*==\s*'([^']+)'\s*(?:and\s+(.*))?\s*then""", line)
        if not m:
            m = re.match(r"""\s*if\s+self\.ability\.name\s*==\s*"([^"]+)"\s*(?:and\s+(.*))?\s*then""", line)

        if m:
            name = m.group(1)
            extra_cond = m.group(2)
            block_start = i

            # Find the matching end for this if-block
            depth = 1
            j = i + 1
            while j < len(lines) and depth > 0:
                l = lines[j].strip()
                # Count if/elseif/for/while vs end
                if re.match(r'\b(if|for|while|elseif|else)\b', l) and not l.startswith("--"):
                    # Don't double-count 'elseif' — it's same level as 'if'
                    if l.startswith("if ") or l.startswith("for ") or l.startswith("while "):
                        depth += 1
                if l == "end" or l.startswith("end)"):
                    depth -= 1
                # Stop at next top-level if/elseif (sibling, not nested)
                if depth == 0:
                    break
                j += 1

            block_end = j + 1  # include the 'end'

            # Get the raw block text
            block_lines = lines[block_start:block_end]
            raw = "\n".join(block_lines)

            # Skip if block is too short (just a comment)
            content_lines = [l for l in block_lines[1:] if l.strip() and not l.strip().startswith("--")]
            if len(content_lines) <= 1:
                i += 1
                continue

            # Classify complexity
            has_event = "G.E_MANAGER" in raw
            has_creation = "create_card" in raw or "copy_card" in raw
            has_removal = "self:remove()" in raw or "juice_card" in raw
            has_ability_state = "self.ability." in raw and ("self.ability +=" in raw or "self.ability = self.ability" in raw or "self.ability.x_mult" in raw or "self.ability.mult" in raw)

            if has_event or has_creation:
                complexity = "complex"
            elif has_removal or has_ability_state:
                complexity = "moderate"
            else:
                complexity = "simple"

            blocks.append({
                "name": name,
                "raw": raw,
                "line": block_start + 1,
                "complexity": complexity,
                "extra_cond": extra_cond,
            })

        i += 1

    return blocks


def translate_block(block: dict) -> str:
    """Translate a raw game block to a comment stub for our format."""
    name = block["name"]
    key = f"j_{name.lower().replace(' ', '_').replace('-', '_')}"
    raw = block["raw"]
    line = block["line"]

    # Clean up the raw code to be readable
    cleaned = []
    for l in raw.split("\n"):
        l = l.rstrip()
        # Skip the opening if self.ability.name line
        if "self.ability.name" in l and "then" in l:
            continue
        # Skip bare 'end' lines (closing the if)
        if l.strip() == "end":
            continue
        # Add our comment prefix
        if l.strip():
            cleaned.append(f"    -- {l.strip()}")

    comment_block = "\n".join(cleaned)

    return comment_block


# Common joker patterns with our correct API mappings
SIMPLE_TRANSLATIONS = {
    "Joker": {
        "ctx": "joker_main",
        "code": "if ctx.joker_main then return { mult_mod = 4 } end",
    },
}


def try_generate_working_code(block: dict) -> str | None:
    """For jokers we already have working, return None (skip).
    For simple patterns, try to generate working code."""
    name = block["name"]
    raw = block["raw"]

    # Pattern: individual card + specific suit (any suit reference)
    suit_m = re.search(r':is_suit\([^)]*\)', raw)
    card_val_m = re.search(r'return\s*\{[^}]*mult\s*=\s*self\.ability\.extra', raw)
    chip_val_m = re.search(r'return\s*\{[^}]*chips\s*=\s*self\.ability\.extra', raw)
    xmult_val_m = re.search(r'return\s*\{[^}]*x_mult\s*=\s*([\d.]+)', raw)

    if "context.other_card" in raw and suit_m and "individual" in raw:
        # Determine which suit
        suit_ref = suit_m.group(0)
        suit_enum = "c.suit"  # default: any suit check
        if "G.GAME.current_round" in suit_ref:
            # Dynamic suit — uses our existing _is_suit helper pattern
            suit_enum = "c.suit"  # Will need joker-level suit state
        if card_val_m:
            return (
                f'    if ctx.individual and ctx.other_card and ctx.cardarea == "play" then\n'
                f"        -- Check suit with _is_suit(ctx.other_card, expected_suit)\n"
                f"        return {{ mult = jk._extra or 0 }}\n"
                f"    end"
            )
        elif chip_val_m:
            return (
                f'    if ctx.individual and ctx.other_card and ctx.cardarea == "play" then\n'
                f"        -- Check suit with _is_suit(ctx.other_card, expected_suit)\n"
                f"        return {{ chips = jk._extra or 0 }}\n"
                f"    end"
            )

    # Pattern: individual card + specific rank check
    rank_m = re.search(r':get_id\(\)\s*==\s*(\d+)', raw)
    if "context.other_card" in raw and rank_m and "individual" in raw:
        rank = rank_m.group(1)
        if card_val_m:
            return (
                f"    if ctx.individual and ctx.other_card and ctx.other_card.rank == {rank} then\n"
                f"        return {{ mult = jk._extra or 0 }}\n"
                f"    end"
            )
        elif chip_val_m:
            return (
                f"    if ctx.individual and ctx.other_card and ctx.other_card.rank == {rank} then\n"
                f"        return {{ chips = jk._extra or 0 }}\n"
                f"    end"
            )

    # Pattern: individual card + face card check
    if "context.other_card" in raw and ":is_face()" in raw and "individual" in raw:
        if card_val_m:
            return (
                "    if ctx.individual and ctx.other_card and ctx.other_card.rank >= 11 and ctx.other_card.rank <= 13 then\n"
                "        return { mult = jk._extra or 0 }\n"
                "    end"
            )
        elif chip_val_m:
            return (
                "    if ctx.individual and ctx.other_card and ctx.other_card.rank >= 11 and ctx.other_card.rank <= 13 then\n"
                "        return { chips = jk._extra or 0 }\n"
                "    end"
            )
        elif xmult_val_m:
            val = xmult_val_m.group(1)
            return (
                "    if ctx.individual and ctx.other_card and ctx.other_card.rank >= 11 and ctx.other_card.rank <= 13 then\n"
                f"        return {{ x_mult = {val} }}\n"
                "    end"
            )

    # Pattern: individual card + perma_bonus (Hiker)
    if "perma_bonus" in raw and "context.other_card" in raw and "individual" in raw:
        extra_m = re.search(r'perma_bonus.*?\+\s*self\.ability\.extra', raw)
        if extra_m:
            return (
                "    if ctx.individual and ctx.other_card then\n"
                "        ctx.other_card.perma_bonus = (ctx.other_card.perma_bonus or 0) + (jk._extra or 5)\n"
                "    end"
            )

    # Pattern: joker_main + hand type check (various formats)
    # Try context.poker_hands["Type"]
    hand_type_m = re.search(r'context\.poker_hands\[["\'](\w[\w\s]*\w)["\']\]', raw)
    # Try context.scoring_name == "Type"  
    if not hand_type_m:
        hand_type_m2 = re.search(r'context\.scoring_name\s*==\s*["\'](\w[\w\s]*\w)["\']', raw)
    else:
        hand_type_m2 = None

    ht_name = None
    if hand_type_m:
        ht_name = hand_type_m.group(1)
    elif hand_type_m2:
        ht_name = hand_type_m2.group(1)

    if ht_name and "joker_main" in raw:
        # Map game hand names to our enums
        ht_map = {
            "Pair": "PAIR", "Two Pair": "TWO_PAIR",
            "Three of a Kind": "THREE_OF_A_KIND", "Four of a Kind": "FOUR_OF_A_KIND",
            "Straight": "STRAIGHT", "Flush": "FLUSH",
            "Full House": "FULL_HOUSE", "Straight Flush": "STRAIGHT_FLUSH",
            "High Card": "HIGH_CARD", "Five of a Kind": "FIVE_OF_A_KIND",
            "Flush House": "FLUSH_HOUSE", "Flush Five": "FLUSH_FIVE",
        }
        enum = ht_map.get(ht_name, ht_name.upper().replace(" ", "_"))
        
        # Check for mult_mod, chip_mod, Xmult_mod in the raw return
        mult_val = re.search(r'mult_mod\s*=\s*(\d+)', raw)
        chip_val = re.search(r'chip_mod\s*=\s*(\d+)', raw)
        xmult_val = re.search(r'Xmult_mod\s*=\s*([\d.]+)', raw)
        
        if mult_val:
            return (
                f"    if ctx.joker_main and ctx.all_hands and ctx.all_hands[E.HAND_TYPE.{enum}] then\n"
                f"        return {{ mult_mod = {mult_val.group(1)} }}\n"
                f"    end"
            )
        elif chip_val:
            return (
                f"    if ctx.joker_main and ctx.all_hands and ctx.all_hands[E.HAND_TYPE.{enum}] then\n"
                f"        return {{ chip_mod = {chip_val.group(1)} }}\n"
                f"    end"
            )
        elif xmult_val:
            return (
                f"    if ctx.joker_main and ctx.all_hands and ctx.all_hands[E.HAND_TYPE.{enum}] then\n"
                f"        return {{ Xmult_mod = {xmult_val.group(1)} }}\n"
                f"    end"
            )

    # Pattern: joker_main + dollars
    if "joker_main" in raw and "dollars" in raw and "ease_dollars" in raw:
        dollars_m = re.search(r'ease_dollars\(self\.ability\.extra\)', raw)
        if dollars_m:
            return (
                "    if ctx.joker_main then return { dollars = jk._extra or 0 } end"
            )

    # Pattern: round_end + dollars (Golden Joker, Rocket, etc.)
    if "round_end" in raw or "end_of_round" in raw:
        dollars_m = re.search(r'dollars\s*=\s*(\d+)', raw)
        if dollars_m:
            return (
                f"    if ctx.round_end then return {{ dollars = {dollars_m.group(1)} }} end"
            )

    # Pattern: after_play (context.after) + chip_mod reduction (Ice Cream, Seltzer)
    if "context.after" in raw or "ctx.after_play" in raw:
        if "chip_mod" in raw or "chips" in raw:
            return (
                "    -- Decreases each hand played, destroyed when reaches 0\n"
                "    if ctx.after_play then return { chip_mod = -(jk._extra or 0) } end"
            )

    return None


def main():
    parser = argparse.ArgumentParser(description="Translate Balatro jokers")
    parser.add_argument("--game-dir", required=True)
    parser.add_argument("--output", default="joker_stubs.lua")
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--existing", default="src/04_jokers.lua",
                        help="Path to our existing joker file (to skip working ones)")
    args = parser.parse_args()

    game_dir = Path(args.game_dir)
    card_path = game_dir / "card.lua"
    with open(card_path, encoding="utf-8") as f:
        lua_code = f.read()

    # Load our existing jokers to know which ones work
    existing_keys = set()
    try:
        with open(args.existing, encoding="utf-8") as f:
            existing_code = f.read()
        # Count keys that have actual logic (not just comments)
        for m in re.finditer(r'Sim._reg_joker\("([^"]+)"', existing_code):
            existing_keys.add(m.group(1))
    except FileNotFoundError:
        pass

    blocks = extract_blocks(lua_code)
    print(f"Extracted {len(blocks)} joker blocks from card.lua")

    # Deduplicate by joker name (keep first occurrence)
    seen = {}
    unique = []
    for b in blocks:
        if b["name"] not in seen:
            seen[b["name"]] = b
            unique.append(b)
    blocks = unique
    print(f"Unique jokers: {len(blocks)}")

    # Categorize
    working = []
    translatable = []
    needs_stub = []
    complex_blocks = []

    for b in blocks:
        key = f"j_{b['name'].lower().replace(' ', '_').replace('-', '_')}"
        if key in existing_keys:
            # Check if our version has real logic or is a stub
            # Simple heuristic: skip known working ones
            working.append(b)
        elif b["complexity"] == "complex":
            complex_blocks.append(b)
        else:
            code = try_generate_working_code(b)
            if code:
                translatable.append((b, code))
            else:
                needs_stub.append(b)

    print(f"\nAlready working: {len(working)}")
    print(f"Can translate: {len(translatable)}")
    print(f"Need stub only: {len(needs_stub)}")
    print(f"Complex (manual): {len(complex_blocks)}")

    # Generate output
    output = []
    output.append("-- Auto-translated joker behaviors from Balatro card.lua")
    output.append("-- Review each one and integrate into src/04_jokers.lua")
    output.append("")

    if translatable:
        output.append("-- === Translatable jokers (review and copy) ===\n")
        for b, code in translatable:
            name = b["name"]
            key = f"j_{name.lower().replace(' ', '_').replace('-', '_')}"
            output.append(f'-- {key}: "{name}"')
            output.append(f'-- Source: card.lua line {b["line"]}')
            output.append(f'Sim._reg_joker("{key}", "{name}", 2, 5, function(ctx, st, jk)')
            output.append(code)
            output.append("end)\n")

    if needs_stub:
        output.append("-- === Need manual translation (raw game code as reference) ===\n")
        for b in needs_stub:
            name = b["name"]
            key = f"j_{name.lower().replace(' ', '_').replace('-', '_')}"
            comment = translate_block(b)
            output.append(f'-- {key}: "{name}"')
            output.append(f'-- Source: card.lua line {b["line"]}')
            output.append(f'-- Game code:')
            output.append(comment)
            output.append(f'Sim._reg_joker("{key}", "{name}", 2, 5, function(ctx, st, jk)')
            output.append(comment)
            output.append("end)\n")

    if complex_blocks:
        output.append("-- === Complex jokers (need significant manual work) ===\n")
        for b in complex_blocks:
            name = b["name"]
            key = f"j_{name.lower().replace(' ', '_').replace('-', '_')}"
            comment = translate_block(b)
            output.append(f'-- {key}: "{name}" (COMPLEX)')
            output.append(f'-- Source: card.lua line {b["line"]}')
            output.append(f'-- Game code:')
            output.append(comment)
            output.append("")

    result = "\n".join(output)

    if args.dry_run:
        print(f"\n--- Output preview ({len(result)} chars) ---")
        print(result[:5000])
        if len(result) > 5000:
            print(f"\n... ({len(result) - 5000} more chars)")
    else:
        with open(args.output, "w", encoding="utf-8") as f:
            f.write(result)
        print(f"\nWrote {len(output)} lines to {args.output}")


if __name__ == "__main__":
    main()
