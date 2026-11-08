# Reproducible MiniRubik tables

This optional host-side bundle reproduces the frozen solver's precomputed query
tables. Tables replace ranking, move simulation, and BFS in the target search loop.
The production build uses the tables in `src/rubik/`; it never invokes this bundle.
The official source-copy/build rules do not compile files under `mytests/`.

## Provenance and dependencies

`hw1_solver.c` is a clang-format-20-formatted derivative of the original HW1 solver,
preserving its `--emit-tables` interface. Two redundant parity conditions were
removed because the fixed mixed domain has 25,515 (odd) states. The packed-output
canonicalization and padding validation still execute; generation algorithms and
table contents are unchanged. The original HW1 file is not modified. Generator
failures use unconditional return-value checks, not assertions.
`identity_tables.cpp` extracts the verified A6d generation algorithm for cubies 1
and 4, omitting the old profiling/search experiments. All of its checks remain
enabled with `NDEBUG`. Row offsets are serialized explicitly as little-endian.
Its ranking uses `std::count_if` for smaller successors and `std::accumulate` for
the same left-to-right base-three fold, satisfying static analysis without changing
rank ordering. Both generator sources follow the repository's clang-format 20 style.

`regenerate.py` retains the R3b/R4b/R5c/A1 initializer formatting. `verify.py` reuses
the independent R3a explicit-cubie cycles and R4a/R5c/A6d BFS verification methods.
It does not use generator transition arrays to construct its reference graphs.

Dependencies: a C99 host compiler (`cc`), a C++17 host compiler (`c++`), and
Python 3.9 or newer with its standard library. No RISC-V compiler, emulator,
third-party Python modules, historical evidence, or network access is needed.

## Regenerate and verify

From the repository root, choose new or empty output directories outside any Git
checkout. Existing nonempty directories are refused; production tables are never
read as generator inputs or copied as a fallback.

```sh
python3 mytests/minirubik-tables/regenerate.py --out ../minirubik-generated-a
python3 mytests/minirubik-tables/regenerate.py --out ../minirubik-generated-b
python3 mytests/minirubik-tables/verify.py --generated ../minirubik-generated-a --repo .
python3 mytests/minirubik-tables/verify.py --generated ../minirubik-generated-b --repo .
```

Use the local resource guard when required by your execution environment. Host
compilers are invoked with `-O2 -Wall -Wextra -Wpedantic` and the required language
standard. Override compiler commands with `--cc`/`--cxx` or `CC`/`CXX`.
Compilation and generator subprocesses each have a finite 60-second timeout.
Checks in the Python entry points also remain enabled under `python3 -O`.

Each output contains `raw/` (eight logical payloads), `.build/` (host executables
and the original HW1 Assembly export), six production artifacts, and
`generation-manifest.json` (sizes, fingerprints, source fingerprints, and flags).
Only the six production artifacts are intended to match `src/rubik/`.
The handwritten `rubik_identity.inc` inclusion wrapper is not generated. It retains
the section, alignment, local symbols, and sizes, and includes the two identity
literal files. Those files contain only comments and `.byte` directives: row bytes
are explicitly little-endian, with no added alignment or padding. Production builds
need no `.bin` files. Raw binary payloads remain external intermediate outputs.

Expected final verification line:

```text
PASS production_artifacts=6 logical_payloads=8 sizes_sha256_bytes_text=identical
```

Preceding lines report independent transition, basic BFS, mixed BFS, identity BFS,
projection, consistency-edge, and little-endian checks. A mismatch, missing input,
compiler/generator failure, or invalid output location produces an error and a
nonzero exit status. A failed generation may leave partial diagnostic output;
use another fresh directory rather than overwriting it.

The HW1 derivative can emit one existing GCC `-Wsign-compare` warning in its bounded
unranking loop. That loop is unchanged; warnings are enabled and not hidden.
The identity generator has no corresponding warning. Host executable bytes and
warning wording may vary between compilers; the canonical table bytes must not.

## Formats and fingerprints

All raw filenames below are under the generated `raw/` directory. Transition
tables have R/B/D face-major rows and unsigned 16-bit little-endian entries.
P is lexicographic permutation rank (5,040 states); Q is the first six twists in
base three (729 states), with the seventh determined by the twist-sum invariant.
All nine HTM moves have unit cost, including half turns and inverse turns.

| Logical table / raw filename | Bytes | Production destination |
|---|---:|---|
| `permutation_turn.le16.bin` | 30,240 | `rubik_turns.inc`, `rubik_asm_tables.inc` |
| `orientation_turn.le16.bin` | 4,374 | same |
| `distance_p.u8.bin` | 5,040 | `rubik_distances.inc`, `rubik_asm_tables.inc` |
| `distance_q.u8.bin` | 729 | same |
| `permutation_subset.u8.bin` | 5,040 | `rubik_mixed.inc`, `rubik_asm_tables.inc` |
| `mixed_distance.packed.bin` | 12,758 | same |
| `identity_rows.le16.bin` | 10,080 | `rubik_identity_rows.inc` |
| `identity_distance.packed.bin` | 15,309 | `rubik_identity_distance.inc` |

The mixed abstraction tracks positions occupied by zero-based cubies `{0,1,2}`
without their internal order, together with full Q. Its 35 subsets use ascending
three-bit-mask order; `index = 729*subset + Q` gives 25,515 distances.

The identity abstraction tracks the distinct positions `x,y` of zero-based cubies
`0,3` (human identities 1,4), together with full Q. Ordered-position code
`c = 6*x + y - (y > x)` gives 42 possibilities and 30,618 distances.
The row table stores `729*c` for every P, with maximum 29,889. The abstract goal
is `c=2,Q=0`, not abstract index zero.

Both PDBs have maximum distance eight and store even entries in low nibbles and
odd entries in high nibbles. The mixed PDB's unused final high nibble is zero.
The independent verifier reconstructs both graphs and checks every distance,
projection, edge consistency, descending neighbor, nibble, and LE row encoding.

### Raw payload SHA-256

```text
permutation_turn.le16.bin
54867f73c3db2d6a5a504e766a00fcbaa70f1f6f875913a1eaa547bd23548f37
orientation_turn.le16.bin
d4944ff16d4ec9b13b223a20666d78ac30a132e096eabc26607fe761ce051951
distance_p.u8.bin
6e33ed7c65e20b7bb88d92573cc17e1c147251e55a8769ae751fdbf573cf8561
distance_q.u8.bin
7965c45cac412da2012e492e42017d439bf1ba0b485fed92c3a3835400eec0fb
permutation_subset.u8.bin
d17fde3d75866b4b1ebf70c824925c2ccdd6dbf9ca682f14f77aace3b2343ed7
mixed_distance.packed.bin
5fe56f9fe199b716ac79199a48b8765c47b9943f58e88dc838f55e73df589ab6
identity_rows.le16.bin
c5bf94bffc049a0efc4ee288042ffabe304844fc05bee17763f64d0a5d4d2c98
identity_distance.packed.bin
68e2ea5501334f3c0cb5bb7e6d661e2452dd826f271f2ed511053455e1b3a58e
```

### Production artifact sizes and SHA-256

| File | Bytes | SHA-256 |
|---|---:|---|
| `rubik_turns.inc` | 112,437 | `13e255230827f269f15e55ebded17f10b6819a5b700c16c8e5897d73c6e0a6e2` |
| `rubik_distances.inc` | 18,912 | `5fc0f60d39cd7aea159a1569ecd88c9b3bda4f9b618c73b8b5965015db4f650d` |
| `rubik_mixed.inc` | 84,178 | `3af4beec7d05b9525cea83b4b3a1bd53cfa85474dcd96d3c3d470b225655d1cc` |
| `rubik_asm_tables.inc` | 228,681 | `7db4af7f9498edc2bf02b243d38985a75910b9353d7e27896bddb737fa2b6e76` |
| `rubik_identity_rows.inc` | 49,248 | `6b1dcd4ff84d6247277414f83aad5ed6a5027b788828628cba663b6453176bf6` |
| `rubik_identity_distance.inc` | 82,005 | `60b58ad3a07bfc192204267848594ec70c5ac7d5071fdeb50775787f9dbd7c57` |

The identity include sizes above describe ASCII source. Their assembled payloads
remain exactly 10,080 and 15,309 bytes, with the raw SHA-256 values listed above.
The verifier independently parses the literal directives and compares their bytes
with the regenerated raw payloads before reconstructing the abstract graphs.

Host executable bytes are compiler/platform dependent; table bytes and include
formatting are canonical. This verifier exhaustively checks the small projected
graphs; it does not repeat the full-cube solver timing sweep or official grading.
