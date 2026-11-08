#!/usr/bin/env python3
"""Independently verify generated tables and compare intended production files."""
import argparse
from collections import deque
import hashlib
import importlib.util
import itertools
from pathlib import Path
import re
import struct
import sys

# Import metadata only; no generator algorithm is used by the cubie oracle.
sys.dont_write_bytecode = True
spec = importlib.util.spec_from_file_location("table_metadata", Path(__file__).with_name("regenerate.py"))
metadata = importlib.util.module_from_spec(spec)
spec.loader.exec_module(metadata)


def require(condition, message):
    if not condition:
        raise ValueError(message)


def move(face, p, o):
    """R3a independent explicit cubie cycles, not generator source/dest arrays."""
    pp, oo = list(p), list(o)
    if face == 0:
        pp[0], pp[1], pp[4], pp[3] = p[1], p[4], p[3], p[0]
        oo[0], oo[1], oo[4], oo[3] = ((o[1] + 1) % 3, (o[4] + 2) % 3, (o[3] + 1) % 3, (o[0] + 2) % 3)
    elif face == 1:
        pp[3], pp[4], pp[5], pp[6] = p[4], p[5], p[6], p[3]
        oo[3], oo[4], oo[5], oo[6] = ((o[4] + 1) % 3, (o[5] + 2) % 3, (o[6] + 1) % 3, (o[3] + 2) % 3)
    elif face == 2:
        pp[1], pp[2], pp[5], pp[4] = p[2], p[5], p[4], p[1]
        oo[1], oo[2], oo[5], oo[4] = o[2], o[5], o[4], o[1]
    else:
        raise ValueError("invalid face")
    return tuple(pp), tuple(oo)


def qrank(o):
    return sum(value * weight for value, weight in zip(o[:6], (243, 81, 27, 9, 3, 1)))


def bfs(root, successors):
    distances = {root: 0}
    queue = deque([root])
    while queue:
        current = queue.popleft()
        for child in successors(current):
            if child not in distances:
                distances[child] = distances[current] + 1
                queue.append(child)
    return distances


def unpack(raw, count):
    require(len(raw) == (count + 1) // 2, "packed byte count")
    if count % 2:
        require(raw[-1] >> 4 == 0, "unused high nibble must be zero")
    values = bytes((raw[i // 2] >> (4 * (i % 2))) & 15 for i in range(count))
    require(max(values) == 8 and values.count(0) == 1, "PDB distance range/unique goal")
    repacked = bytes(values[i] | ((values[i + 1] if i + 1 < count else 0) << 4) for i in range(0, count, 2))
    require(repacked == raw, "packed-nibble canonical order")
    return values


def asm_payload(text, name, width):
    label = "rubik_asm_" + name
    match = re.search(r"^" + label + r":\n(.*?)^\.size " + label + r",", text, re.M | re.S)
    require(match is not None, "missing Assembly table " + name)
    values = []
    directive = ".2byte" if width == 2 else ".byte"
    for line in match.group(1).splitlines():
        line = line.strip()
        require(line.startswith(directive + " "), "Assembly initializer " + name)
        values.extend(int(x.strip()) for x in line[len(directive):].split(","))
    return struct.pack("<" + ("H" if width == 2 else "B") * len(values), *values)


def c_payload(text, name, width):
    match = re.search(r"\b" + name + r"\[[^=]+?=\s*\{(.*?)\};", text, re.S)
    require(match is not None, "missing C table " + name)
    body = re.sub(r"/\*.*?\*/", "", match.group(1), flags=re.S)
    values = [int(x) for x in re.findall(r"\d+", body)]
    return struct.pack("<" + ("H" if width == 2 else "B") * len(values), *values)


def literal_bytes(text):
    values = []
    for line in text.splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        require(line.startswith(".byte "), "identity include must contain only literal bytes")
        values.extend(int(value.strip()) for value in line[len(".byte "):].split(","))
    return bytes(values)


def independent(data):
    permutations = list(itertools.permutations(range(7)))
    ranks = {p: i for i, p in enumerate(permutations)}
    orientations = [o + ((-sum(o)) % 3,) for o in itertools.product(range(3), repeat=6)]
    identity, zero = permutations[0], orientations[0]
    require([qrank(o) for o in orientations] == list(range(729)), "independent Q ordering")
    pt = struct.unpack("<15120H", data["permutation_turn"])
    qt = struct.unpack("<2187H", data["orientation_turn"])
    for face in range(3):
        for i, p in enumerate(permutations):
            require(pt[face * 5040 + i] == ranks[move(face, p, zero)[0]], "P transition")
        for q, o in enumerate(orientations):
            require(qt[face * 729 + q] == qrank(move(face, identity, o)[1]), "Q transition")
        for rows, count in ((pt, 5040), (qt, 729)):
            row = rows[face * count:(face + 1) * count]
            require(sorted(row) == list(range(count)), "transition bijection")
            require(all(row[row[row[row[i]]]] == i for i in range(count)), "four-turn identity")
    print("PASS independent transitions=17307 bijective_rows=6 four_turn_identities=17307")

    def p_successors(p):
        for face in range(3):
            pp = p
            for _ in range(3):
                pp, _ = move(face, pp, zero)
                yield pp

    def q_successors(o):
        for face in range(3):
            oo = o
            for _ in range(3):
                _, oo = move(face, identity, oo)
                yield oo

    pd, qd = bfs(identity, p_successors), bfs(zero, q_successors)
    require(len(pd) == 5040 and len(qd) == 729, "basic BFS reachability")
    require(bytes(pd[p] for p in permutations) == data["distance_p"], "independent P BFS")
    require(bytes(qd[o] for o in orientations) == data["distance_q"], "independent Q BFS")
    print("PASS independent basic_BFS=5769")

    masks = sorted(sum(1 << i for i in positions) for positions in itertools.combinations(range(7), 3))
    maskrank = {mask: i for i, mask in enumerate(masks)}

    def occupied(p):
        return sum(1 << i for i, cubie in enumerate(p) if cubie in (0, 1, 2))

    projection = bytes(maskrank[occupied(p)] for p in permutations)
    require(projection == data["permutation_subset"], "independent subset projection")
    representatives = {}
    for p in permutations:
        representatives.setdefault(occupied(p), p)

    def mixed_successors(state):
        mask, o = state
        for face in range(3):
            pp, oo = representatives[mask], o
            for _ in range(3):
                pp, oo = move(face, pp, oo)
                yield occupied(pp), oo

    mixed = bfs((occupied(identity), zero), mixed_successors)
    require(len(mixed) == 25515, "mixed BFS reachability")
    raw = unpack(data["mixed_distance"], 25515)
    require(raw == bytes(mixed[mask, o] for mask in masks for o in orientations), "independent mixed BFS")
    edges = 0
    for state, distance in mixed.items():
        descent = distance == 0
        for child in mixed_successors(state):
            delta = distance - mixed[child]
            require(-1 <= delta <= 1, "mixed consistency")
            descent |= delta == 1
            edges += 1
        require(descent, "mixed descending neighbor")
    print(f"PASS independent mixed_BFS=25515 projection=5040 consistency_edges={edges}")

    positions = list(itertools.permutations(range(7), 2))
    posrank = {pair: i for i, pair in enumerate(positions)}
    pair_projection = [posrank[p.index(0), p.index(3)] for p in permutations]
    expected_rows = struct.pack("<5040H", *(729 * c for c in pair_projection))
    require(expected_rows == data["identity_rows"], "portable LE ordered-pair projection")
    rows = struct.unpack("<5040H", data["identity_rows"])
    require(min(rows) == 0 and max(rows) == 29889 and all(v % 729 == 0 for v in rows), "identity row bounds")

    def pair_successors(state):
        x, y, o = state
        for face in range(3):
            pp = [2] * 7
            pp[x], pp[y] = 0, 1
            pp, oo = tuple(pp), o
            for _ in range(3):
                pp, oo = move(face, pp, oo)
                yield pp.index(0), pp.index(1), oo

    pair = bfs((0, 3, zero), pair_successors)
    require(len(pair) == 30618, "identity BFS reachability")
    raw = unpack(data["identity_distance"], 30618)
    require(raw == bytes(pair[x, y, o] for x, y in positions for o in orientations), "independent identity BFS")
    edges = 0
    for state, distance in pair.items():
        descent = distance == 0
        for child in pair_successors(state):
            delta = distance - pair[child]
            require(-1 <= delta <= 1, "identity consistency")
            descent |= delta == 1
            edges += 1
        require(descent, "identity descending neighbor")
    print(f"PASS independent identity_BFS=30618 projection=5040 consistency_edges={edges} little_endian_rows=5040")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--generated", type=Path, required=True)
    parser.add_argument("--repo", type=Path, required=True)
    args = parser.parse_args()
    generated, production = args.generated.resolve(), args.repo.resolve() / "src/rubik"
    data = {}
    for name, _, filename, _, size, expected in metadata.TABLES:
        raw = (generated / "raw" / filename).read_bytes()
        require(len(raw) == size, "raw size: " + name)
        require(hashlib.sha256(raw).hexdigest() == expected, "raw SHA-256: " + name)
        data[name] = raw
    artifacts = ("rubik_turns.inc", "rubik_distances.inc", "rubik_mixed.inc", "rubik_asm_tables.inc",
                 "rubik_identity_rows.inc", "rubik_identity_distance.inc")
    for name in artifacts:
        actual, expected = (generated / name).read_bytes(), (production / name).read_bytes()
        require(len(actual) == len(expected), "production size: " + name)
        require(hashlib.sha256(actual).digest() == hashlib.sha256(expected).digest(), "production SHA-256: " + name)
        require(actual == expected, "production byte equality: " + name)
        if name.endswith(".inc"):
            require(actual.decode("ascii") == expected.decode("ascii"), "include text equality: " + name)
    asm = (generated / "rubik_asm_tables.inc").read_text(encoding="ascii")
    for name, _, _, width, _, _ in metadata.TABLES[:6]:
        require(asm_payload(asm, name, width) == data[name], "Assembly/raw payload mismatch: " + name)
        cfile = "rubik_turns.inc" if name.endswith("_turn") else "rubik_distances.inc" if name in ("distance_p", "distance_q") else "rubik_mixed.inc"
        require(c_payload((generated / cfile).read_text(encoding="ascii"), name, width) == data[name], "C/raw payload mismatch: " + name)
    for name in ("identity_rows", "identity_distance"):
        filename = "rubik_" + name + ".inc"
        require(literal_bytes((generated / filename).read_text(encoding="ascii")) == data[name],
                "identity text/raw mismatch: " + name)
    independent(data)
    print("PASS production_artifacts=6 logical_payloads=8 sizes_sha256_bytes_text=identical")


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, KeyError, struct.error) as error:
        print("verify:", error, file=sys.stderr)
        sys.exit(1)
