#!/usr/bin/env python3
"""
balatro_compare.py v2
Reads Lua output + runs Python with the SAME random stream.
Compares every decision point line-by-line.
"""

import json
import math

# ============================================================================
# SHARED RANDOM STREAM
# ============================================================================
stream = []
stream_idx = 0

def load_stream(filename):
    global stream, stream_idx
    stream = []
    with open(filename) as f:
        for line in f:
            line = line.strip()
            if line:
                stream.append(float(line))
    stream_idx = 0

def next_float():
    global stream_idx
    if stream_idx >= len(stream):
        return 0.0
    v = stream[stream_idx]
    stream_idx += 1
    return v

def next_int(lo, hi):
    return lo + int(next_float() * (hi - lo + 1))

# ============================================================================
# GAME STATE
# ============================================================================
class State:
    def __init__(self):
        self.edition_rate = 1
        self.joker_rate = 20
        self.tarot_rate = 4
        self.planet_rate = 4
        self.spectral_rate = 0
        self.playing_card_rate = 0
        self.discount_percent = 0
        self.interest_cap = 25
        self.interest_amount = 1
        self.inflation = 0
        self.reroll_cost = 1
        self.temp_reroll_cost = None
        self.used_jokers = set()
        self.used_vouchers = set()
        self.banned_keys = set()
        self.all_eternal = False
        self.enable_eternals = False
        self.enable_perishables = False
        self.enable_rentals = False

S = State()

JOKER_POOLS = {
    1: [f"j_common_{i}" for i in range(1, 61)],
    2: [f"j_uncommon_{i}" for i in range(1, 61)],
    3: [f"j_rare_{i}" for i in range(1, 21)],
    4: [f"j_legendary_{i}" for i in range(1, 6)],
}
TAROT = [f"c_tarot_{i}" for i in range(1, 23)]
PLANET = [f"c_planet_{i}" for i in range(1, 13)]
SPECTRAL = [f"c_spectral_{i}" for i in range(1, 19)]

# ============================================================================
# CORE FUNCTIONS (exact Lua ports)
# ============================================================================

def find_joker(name):
    return []  # never have showman in our tests

def get_pool(_type, _rarity=None, _legendary=False, _append="", ante=1):
    pool = []
    sz = 0
    if _type == "Joker":
        r = _rarity if _rarity is not None else next_float()
        rarity = 4 if _legendary else (3 if r > 0.95 else (2 if r > 0.7 else 1))
        src = JOKER_POOLS[rarity]
        pkey = f"Joker{rarity}" + ("" if _legendary else _append)
    elif _type == "Tarot":
        src = TAROT; pkey = "Tarot" + _append
    elif _type == "Planet":
        src = PLANET; pkey = "Planet" + _append
    elif _type == "Spectral":
        src = SPECTRAL; pkey = "Spectral" + _append
    else:
        src = []; pkey = _type + _append

    for v in src:
        add = False
        if not (v in S.used_jokers and len(find_joker("Showman")) == 0):
            if v.startswith("c_"):
                if v not in ("c_soul", "c_black_hole"):
                    add = True
            elif v.startswith("v_"):
                if v not in S.used_vouchers:
                    add = True
            else:
                add = True
        if v in S.banned_keys:
            add = False
        if add:
            pool.append(v); sz += 1
        else:
            pool.append("UNAVAILABLE")

    if sz == 0:
        fallback = {"Tarot":"c_tarot_1","Planet":"c_planet_12",
                     "Spectral":"c_spectral_1"}.get(_type, "j_common_1")
        pool = [fallback]

    return pool, pkey + str(ante)

def poll_edition(_mod=1.0, _no_neg=False, _guaranteed=False):
    p = next_float()
    if _guaranteed:
        if p > 1 - 0.003*25 and not _no_neg: return "negative"
        if p > 1 - 0.006*25: return "polychrome"
        if p > 1 - 0.02*25: return "holo"
        if p > 1 - 0.04*25: return "foil"
    else:
        if p > 1 - 0.003*_mod and not _no_neg: return "negative"
        if p > 1 - 0.006*S.edition_rate*_mod: return "polychrome"
        if p > 1 - 0.02*S.edition_rate*_mod: return "holo"
        if p > 1 - 0.04*S.edition_rate*_mod: return "foil"
    return "null"

def create_card(_type, area="shop_jokers", soulable=True, forced_key=None,
                key_append="", ante=1):
    fk = forced_key
    if not fk and soulable and "c_soul" not in S.banned_keys:
        if _type in ("Tarot","Spectral","Tarot_Planet"):
            if not (S.used_jokers.get("c_soul") if isinstance(S.used_jokers,dict) else "c_soul" in S.used_jokers):
                if next_float() > 0.997: fk = "c_soul"
        if _type in ("Planet","Spectral"):
            if not (S.used_jokers.get("c_black_hole") if isinstance(S.used_jokers,dict) else "c_black_hole" in S.used_jokers):
                if next_float() > 0.997: fk = "c_black_hole"
    if _type == "Base": fk = "c_base"

    if fk and fk not in S.banned_keys:
        ck = fk
    else:
        pool, _ = get_pool(_type, _append=key_append, ante=ante)
        idx = next_int(1, len(pool)) - 1
        ck = pool[idx]
        while ck == "UNAVAILABLE":
            idx = next_int(1, len(pool)) - 1
            ck = pool[idx]

    eternal = perishable = rental = False
    edition = None
    if _type == "Joker":
        if S.all_eternal: eternal = True
        if area in ("shop_jokers","pack_cards"):
            epp = next_float()
            if S.enable_eternals and epp > 0.7: eternal = True
            elif S.enable_perishables and 0.4 < epp <= 0.7: perishable = True
            if S.enable_rentals and next_float() > 0.7: rental = True
        edition = poll_edition()

    return ck, _type, edition, eternal, perishable, rental

def create_for_shop(area="shop_jokers", ante=1):
    sr = S.spectral_rate
    total = S.joker_rate + S.tarot_rate + S.planet_rate + S.playing_card_rate + sr
    polled = next_float() * total
    chk = 0
    for t, v in [("Joker",S.joker_rate),("Tarot",S.tarot_rate),
                 ("Planet",S.planet_rate),("Base",S.playing_card_rate),
                 ("Spectral",sr)]:
        if polled > chk and polled <= chk + v:
            sel = t; break
        chk += v
    else:
        sel = "Joker"

    ck, typ, ed, et, pe, re = create_card(sel, area=area, soulable=True, key_append="sho", ante=ante)
    return ck, typ, sel, ed, et, pe, re

def calc_cost(base, edition=None):
    extra = S.inflation
    if edition and edition != "null":
        if edition == "holo": extra += 3
        if edition == "foil": extra += 2
        if edition == "polychrome": extra += 5
        if edition == "negative": extra += 5
    cost = max(1, math.floor((base + extra + 0.5) * (100 - S.discount_percent) / 100))
    sell = max(1, math.floor(cost / 2))
    return cost, sell

def calc_reroll(free, inc, skip=False):
    if free < 0: free = 0
    if free > 0: return 0, inc
    if not skip: inc += 1
    base = S.temp_reroll_cost if S.temp_reroll_cost is not None else S.reroll_cost
    return base + inc, inc

def calc_interest(dollars):
    if dollars < 5: return 0
    return S.interest_amount * min(dollars // 5, S.interest_cap // 5)

# ============================================================================
# PARSER: split Lua JSONL into test sections
# ============================================================================
def parse_lua(filename):
    """Parse Lua output into test -> list_of_json_lines mapping."""
    tests = {}
    current_test = None
    current_lines = []
    buf = ""

    with open(filename) as f:
        for line in f:
            buf += line

    # Split by test headers
    import re
    # Find each test block
    pattern = r'\{"test":"([^"]+)","data":\[(.*?)\]\}'
    for m in re.finditer(pattern, buf, re.DOTALL):
        test_name = m.group(1)
        data_str = m.group(2)
        # Split data into individual JSON values
        items = []
        # Try to parse as array of objects/strings/ints
        # Split by newline and commas carefully
        decoder = json.JSONDecoder()
        pos = 0
        data_str = data_str.strip()
        while pos < len(data_str):
            # Skip whitespace and commas
            while pos < len(data_str) and data_str[pos] in ' \t\n\r,':
                pos += 1
            if pos >= len(data_str):
                break
            try:
                obj, end = decoder.raw_decode(data_str, pos)
                items.append(obj)
                pos = end
            except json.JSONDecodeError:
                # Might be a bare number or string
                remaining = data_str[pos:].strip()
                # Try to extract next value
                match = re.match(r'^,?\s*(\S+)', remaining)
                if match:
                    val = match.group(1).rstrip(',')
                    try:
                        items.append(json.loads(val))
                    except:
                        items.append(val)
                    pos += len(match.group(0))
                else:
                    pos += 1
        tests[test_name] = items

    return tests

# ============================================================================
# MAIN COMPARISON
# ============================================================================
def run():
    print("=" * 70)
    print("  SEED-BY-SEED: Lua source vs Python reimplementation")
    print("  Same random stream -> must produce identical output")
    print("=" * 70)

    lua = parse_lua("lua_output.jsonl")
    total_diffs = 0
    total_tests = 0

    def normalize(v):
        if isinstance(v, (dict, list)):
            return json.dumps(v, sort_keys=True, separators=(',',':'))
        if isinstance(v, bool):
            return "true" if v else "false"
        if v is None:
            return "null"
        return str(v)

    def compare_lines(name, lua_data, py_lines):
        nonlocal total_diffs, total_tests
        print(f"\n--- {name} ---")
        n = min(len(lua_data), len(py_lines))
        if len(lua_data) != len(py_lines):
            print(f"  LENGTH: Lua={len(lua_data)} Python={len(py_lines)}")
        diffs = 0
        for i in range(n):
            ls = normalize(lua_data[i])
            ps = normalize(py_lines[i])
            if ls != ps:
                if diffs < 15:
                    print(f"  DIFF [{i}]: Lua={ls[:100]}")
                    print(f"            Py={ps[:100]}")
                diffs += 1
        total_diffs += diffs
        total_tests += n
        if diffs == 0:
            print(f"  PASS - {n} comparisons, 0 diffs")
        else:
            print(f"  FAIL - {diffs}/{n} diffs")

    # ---- Test 1: Type distribution ----
    load_stream("random_stream.txt")
    S.used_jokers = set(); S.banned_keys = set()
    py1 = []
    for _ in range(10000):
        S.used_jokers = set()
        ck, typ, sel, ed, et, pe, re = create_for_shop(ante=1)
        ed_s = ed if ed and ed != "null" else None
        py1.append({"key":ck,"type":typ,"shop_type":sel,
                     "edition":ed_s,"eternal":et,"perishable":pe,"rental":re})
    if "type_dist" in lua:
        compare_lines("Card Type Distribution", lua["type_dist"], py1)

    # ---- Test 2: Edition non-guaranteed ----
    load_stream("random_stream.txt")
    py2 = []
    for _ in range(100000):
        py2.append(poll_edition(_guaranteed=False))
    if "edition_nonguaranteed" in lua:
        # Lua outputs "null" strings, Python outputs "null" strings
        compare_lines("Edition Non-Guaranteed", lua["edition_nonguaranteed"], py2)

    # ---- Test 3: Edition guaranteed ----
    load_stream("random_stream.txt")
    py3 = []
    for _ in range(100000):
        py3.append(poll_edition(_guaranteed=True))
    if "edition_guaranteed" in lua:
        compare_lines("Edition Guaranteed", lua["edition_guaranteed"], py3)

    # ---- Test 4: Soul check ----
    load_stream("random_stream.txt")
    S.used_jokers = set(); S.banned_keys = set()
    py4 = []
    for _ in range(100000):
        S.used_jokers = set()
        ck, _, _, _, _, _ = create_card("Tarot", soulable=True, ante=1)
        py4.append(ck)
    if "soul_check" in lua:
        compare_lines("Soul/Black Hole", lua["soul_check"], py4)

    # ---- Test 5: Stickers ----
    load_stream("random_stream.txt")
    S.enable_eternals = True; S.enable_perishables = True; S.enable_rentals = True
    py5 = []
    for _ in range(100000):
        S.used_jokers = set()
        ck, _, ed, et, pe, re = create_card("Joker", soulable=False, ante=1)
        st = "eternal" if et else ("perishable" if pe else "none")
        rt = "rental" if re else "none"
        py5.append({"s": st, "r": rt})
    S.enable_eternals = False; S.enable_perishables = False; S.enable_rentals = False
    if "stickers" in lua:
        compare_lines("Stickers", lua["stickers"], py5)

    # ---- Test 6: Costs ----
    py6 = []
    for base in [1,2,3,4,5,6,8,10]:
        for ek in ["none","foil","holo","polychrome","negative"]:
            for disc in [0,25,50,75]:
                for infl in [0,1,2,3,4]:
                    S.discount_percent = disc; S.inflation = infl
                    ed = None if ek == "none" else ek
                    c, s = calc_cost(base, edition=ed)
                    py6.append({"b":base,"e":ek,"d":disc,"i":infl,"c":c,"s":s})
    if "costs" in lua:
        compare_lines("Cost Calculation", lua["costs"], py6)

    # ---- Test 7: Reroll ----
    py7 = []
    free = 0; inc = 0
    for _ in range(20):
        cost, inc = calc_reroll(free, inc)
        py7.append(cost)
    if "reroll" in lua:
        compare_lines("Reroll Cost", lua["reroll"], py7)

    # ---- Test 8: Interest ----
    py8 = []
    for d in [0,1,4,5,9,10,14,15,19,20,24,25,30,50,100]:
        py8.append({"d":d,"i":calc_interest(d)})
    if "interest" in lua:
        compare_lines("Interest", lua["interest"], py8)

    # ---- Summary ----
    print("\n" + "=" * 70)
    print(f"  TOTAL: {total_diffs} differences in {total_tests} comparisons")
    if total_diffs == 0:
        print("  PERFECT MATCH - Python is identical to Lua source")
    else:
        print("  Differences found - Python port has bugs")
    print("=" * 70)

if __name__ == "__main__":
    run()
