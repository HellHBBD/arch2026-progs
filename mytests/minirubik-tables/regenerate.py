#!/usr/bin/env python3
"""Build host generators and reproduce tables; never read production payloads."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shlex
import struct
import subprocess
import sys

BUNDLE = Path(__file__).resolve().parent
# Logical name, HW1 symbol, raw filename, entry width, bytes, verified SHA-256.
TABLES = (
    ("permutation_turn", "cube_permutation_turn", "permutation_turn.le16.bin", 2, 30240, "54867f73c3db2d6a5a504e766a00fcbaa70f1f6f875913a1eaa547bd23548f37"),
    ("orientation_turn", "cube_orientation_turn", "orientation_turn.le16.bin", 2, 4374, "d4944ff16d4ec9b13b223a20666d78ac30a132e096eabc26607fe761ce051951"),
    ("distance_p", "cube_permutation_distance", "distance_p.u8.bin", 1, 5040, "6e33ed7c65e20b7bb88d92573cc17e1c147251e55a8769ae751fdbf573cf8561"),
    ("distance_q", "cube_orientation_distance", "distance_q.u8.bin", 1, 729, "7965c45cac412da2012e492e42017d439bf1ba0b485fed92c3a3835400eec0fb"),
    ("permutation_subset", "cube_permutation_subset", "permutation_subset.u8.bin", 1, 5040, "d17fde3d75866b4b1ebf70c824925c2ccdd6dbf9ca682f14f77aace3b2343ed7"),
    ("mixed_distance", "cube_mixed_distance", "mixed_distance.packed.bin", 1, 12758, "5fe56f9fe199b716ac79199a48b8765c47b9943f58e88dc838f55e73df589ab6"),
    ("identity_rows", None, "identity_rows.le16.bin", 2, 10080, "c5bf94bffc049a0efc4ee288042ffabe304844fc05bee17763f64d0a5d4d2c98"),
    ("identity_distance", None, "identity_distance.packed.bin", 1, 15309, "68e2ea5501334f3c0cb5bb7e6d661e2452dd826f271f2ed511053455e1b3a58e"),
)


def require(condition, message):
    if not condition:
        raise ValueError(message)


def sha(data):
    return hashlib.sha256(data).hexdigest()


def write_new(path, data):
    with path.open("xb") as output:
        output.write(data)


def text_bytes(lines):
    return ("\n".join(lines) + "\n").encode("ascii")


def parse_hw1(text):
    result = {}
    for name, symbol, filename, width, size, digest in TABLES[:6]:
        match = re.search(r"^" + re.escape(symbol) + r":\n(.*?)^\.size " + re.escape(symbol) + r",", text, re.M | re.S)
        require(match is not None, "missing HW1 symbol: " + symbol)
        values = []
        directive = ".2byte" if width == 2 else ".byte"
        for line in match.group(1).splitlines():
            line = line.strip()
            require(line.startswith(directive + " "), "unexpected HW1 initializer: " + line)
            values.extend(int(value) for value in line[len(directive):].split(","))
        raw = struct.pack("<" + ("H" if width == 2 else "B") * len(values), *values)
        require(len(raw) == size and sha(raw) == digest, "HW1 payload mismatch: " + name)
        result[name] = raw
    return result


def format_includes(data):
    """Retain the exact R3b, R4b, R5c, and A1 formatting conventions."""
    hashes = {row[0]: row[5] for row in TABLES}
    lines = [
        "/* Generated from the HW1 quarter-turn tables verified in R3a.",
        " * Face-major rows: R, B, D. Raw uint16_t payload: 34,614 bytes.",
        " * SHA-256 of little-endian entries:",
        " * P: " + hashes["permutation_turn"],
        " * Q: " + hashes["orientation_turn"], " */", "", "/* clang-format off */",
    ]
    for name, count in (("permutation_turn", 5040), ("orientation_turn", 729)):
        values = struct.unpack("<" + "H" * (3 * count), data[name])
        lines.append(f"static const uint16_t {name}[3][{count}] = {{")
        for face, label in enumerate(("R", "B", "D")):
            lines.append(f"    {{ /* {label} */")
            row = values[face * count:(face + 1) * count]
            for start in range(0, count, 10):
                lines.append("        " + ", ".join(map(str, row[start:start + 10])) + ",")
            lines.append("    },")
        lines.extend(["};", ""])
    lines.append("/* clang-format on */")
    result = {"rubik_turns.inc": text_bytes(lines)}
    lines = [
        "/* Basic HTM distance tables generated and independently verified in R4a.",
        " * Ascending P/Q coordinate order. Raw uint8_t payload: 5,769 bytes.",
        " * SHA-256 of entries:", " * P: " + hashes["distance_p"],
        " * Q: " + hashes["distance_q"], " */", "", "/* clang-format off */",
    ]
    for name, count in (("distance_p", 5040), ("distance_q", 729)):
        lines.append(f"static const uint8_t {name}[{count}] = {{")
        for start in range(0, count, 20):
            lines.append("    " + ", ".join(map(str, data[name][start:start + 20])) + ",")
        lines.extend(["};", ""])
    lines.append("/* clang-format on */")
    result["rubik_distances.inc"] = text_bytes(lines)
    lines = [
        "/* HW1 mixed PDB, regenerated and independently verified in R5c.",
        " * Track occupied positions of cubies {0,1,2}, together with full Q.",
        " * Subsets follow ascending three-bit mask order; index = subset * 729 + Q.",
        " * Even indices use low nibbles; odd indices use high nibbles.",
        " * SHA-256 of the raw byte arrays:",
        " * Projection: " + hashes["permutation_subset"],
        " * Packed PDB: " + hashes["mixed_distance"], " */", "", "/* clang-format off */",
    ]
    for name in ("permutation_subset", "mixed_distance"):
        raw = data[name]
        lines.append(f"static const uint8_t {name}[{len(raw)}] = {{")
        for start in range(0, len(raw), 16):
            lines.append("    " + ", ".join(map(str, raw[start:start + 16])) + ",")
        lines.extend(["};", ""])
    lines.append("/* clang-format on */")
    result["rubik_mixed.inc"] = text_bytes(lines)
    lines = ["# Verified MiniRubik query tables; face-major transition rows are R/B/D.",
             "# Generated literals only: no host paths or external binary includes.",
             '.section .rodata.rubik_asm, "a", @progbits']
    for name, _, _, width, _, digest in TABLES[:6]:
        raw = data[name]
        label = "rubik_asm_" + name
        if width == 2:
            lines.append(".balign 2")
        lines.extend([f"# Raw little-endian SHA-256: {digest}", f".local {label}",
                      f".type {label}, @object", label + ":"])
        values = raw if width == 1 else struct.unpack("<" + "H" * (len(raw) // 2), raw)
        directive = ".byte" if width == 1 else ".2byte"
        for start in range(0, len(values), 12):
            lines.append("    " + directive + " " + ", ".join(map(str, values[start:start + 12])))
        lines.extend([f".size {label}, .-{label}", ""])
    lines.extend([
        "# Six row pointers: constant-cost face selection without multiplication.",
        ".balign 4", ".local rubik_asm_row_bases", ".type rubik_asm_row_bases, @object",
        "rubik_asm_row_bases:",
        "    .4byte rubik_asm_permutation_turn, rubik_asm_orientation_turn",
        "    .4byte rubik_asm_permutation_turn + 10080, rubik_asm_orientation_turn + 1458",
        "    .4byte rubik_asm_permutation_turn + 20160, rubik_asm_orientation_turn + 2916",
        ".size rubik_asm_row_bases, .-rubik_asm_row_bases",
    ])
    result["rubik_asm_tables.inc"] = text_bytes(lines)
    # Explicit bytes retain the raw LE encoding regardless of host byte order.
    # Alignment, symbols, sizes, and section placement stay in the wrapper.
    for name in ("identity_rows", "identity_distance"):
        raw = data[name]
        lines = [f"# Generated {name}: {len(raw)} raw bytes.",
                 "# Raw little-endian SHA-256: " + hashes[name]]
        for start in range(0, len(raw), 16):
            lines.append("    .byte " + ", ".join(map(str, raw[start:start + 16])))
        result["rubik_" + name + ".inc"] = text_bytes(lines)
    return result


def run(command, cwd):
    result = subprocess.run(command, cwd=cwd, env={**os.environ, "LC_ALL": "C"},
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=60)
    if result.stderr:
        sys.stderr.write(result.stderr.decode("utf-8", errors="replace"))
    require(result.returncode == 0, "command failed: " + shlex.join(command))
    return result.stdout


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", type=Path, required=True, help="new or empty directory outside Git checkouts")
    parser.add_argument("--cc", default=os.environ.get("CC", "cc"))
    parser.add_argument("--cxx", default=os.environ.get("CXX", "c++"))
    args = parser.parse_args()
    out = args.out.expanduser().resolve()
    require(not out.is_relative_to(BUNDLE), "output must be outside the bundle")
    require(not any((p / ".git").exists() for p in (out, *out.parents)), "output must be outside Git checkouts")
    require(not out.exists() or (out.is_dir() and not any(out.iterdir())), "output directory must be new or empty")
    out.mkdir(exist_ok=True)
    build, rawdir = out / ".build", out / "raw"
    build.mkdir()
    rawdir.mkdir()
    flags = ["-O2", "-Wall", "-Wextra", "-Wpedantic"]
    cc, cxx = shlex.split(args.cc), shlex.split(args.cxx)
    require(cc and cxx, "compiler command must not be empty")
    run(cc + ["-std=c99", *flags, str(BUNDLE / "hw1_solver.c"), "-o", str(build / "hw1_solver")], build)
    run(cxx + ["-std=c++17", *flags, str(BUNDLE / "identity_tables.cpp"), "-o", str(build / "identity_tables")], build)
    hw1 = run([str(build / "hw1_solver"), "--emit-tables"], build)
    write_new(build / "hw1-tables.S", hw1)
    data = parse_hw1(hw1.decode("ascii"))
    for name, _, filename, _, _, _ in TABLES[:6]:
        write_new(rawdir / filename, data[name])
    print(run([str(build / "identity_tables"), "--out", str(rawdir)], build).decode("ascii").strip())
    for name, _, filename, _, size, digest in TABLES[6:]:
        data[name] = (rawdir / filename).read_bytes()
        require(len(data[name]) == size and sha(data[name]) == digest, "identity payload mismatch: " + name)
    artifacts = format_includes(data)
    for filename, raw in artifacts.items():
        write_new(out / filename, raw)
    manifest = {
        "format_version": 2,
        "raw_tables": {name: {"file": "raw/" + filename, "bytes": len(data[name]), "sha256": sha(data[name])}
                       for name, _, filename, _, _, _ in TABLES},
        "production_artifacts": {name: {"bytes": len(raw), "sha256": sha(raw)} for name, raw in artifacts.items()},
        "bundle_sources": {p.name: sha(p.read_bytes()) for p in sorted(BUNDLE.iterdir()) if p.is_file()},
        "compiler_commands": {"c": cc, "cxx": cxx},
        "compiler_flags": {"c": ["-std=c99", *flags], "cxx": ["-std=c++17", *flags]},
    }
    write_new(out / "generation-manifest.json", (json.dumps(manifest, indent=2, sort_keys=True) + "\n").encode("ascii"))
    print("PASS regenerated logical_tables=8 production_artifacts=6")
    print("Output:", out)


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, subprocess.SubprocessError) as error:
        print("regenerate:", error, file=sys.stderr)
        sys.exit(1)
