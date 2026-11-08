# A6d verified identity PDB: tracked cubies 0 and 3, all nine HTM moves.
# Ordered-position code c = 6*x + y - (y > x); entry index = 729*c + Q.
# Literal text includes require no host generator or binary input at build time.
.section .rodata.rubik_asm, "a", @progbits
.balign 2
.local rubik_asm_identity_rows
.type rubik_asm_identity_rows, @object
rubik_asm_identity_rows:
    # 5,040 little-endian u16 row offsets, maximum 29,889.
    # SHA-256: c5bf94bffc049a0efc4ee288042ffabe304844fc05bee17763f64d0a5d4d2c98
    .include "src/rubik/rubik_identity_rows.inc"
.size rubik_asm_identity_rows, .-rubik_asm_identity_rows

.local rubik_asm_identity_distance
.type rubik_asm_identity_distance, @object
rubik_asm_identity_distance:
    # 30,618 distances, maximum 8. Even entries occupy the low nibble.
    # SHA-256: 68e2ea5501334f3c0cb5bb7e6d661e2452dd826f271f2ed511053455e1b3a58e
    .include "src/rubik/rubik_identity_distance.inc"
.size rubik_asm_identity_distance, .-rubik_asm_identity_distance
