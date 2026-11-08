# rubik_solve_asm: optimal 2x2x2 cube solver, hand-written RV32I.
#
# int rubik_solve_asm(const char *state, char *out, size_t cap)
#                                   a0 = state, a1 = out, a2 = cap; result in a0
#
# RV32I and Zicsr only: no mul, div, rem, no floating point, no compressed
# instructions, no heap, no recursion. Tests: tests/trubik.c.

    .option push
    .option norvc
    .option norelax
    .text

    .globl  rubik_solve_asm
    .type   rubik_solve_asm, @function
    .align  2
rubik_solve_asm:
    # Fixed private storage: parsed state at 0..13, path at 16..26.
    # s0=out, s1=cap, s2=length, s3=token table; saved registers at 44..63.
    addi    sp, sp, -64
    sw      ra, 60(sp)
    sw      s0, 56(sp)
    sw      s1, 52(sp)
    sw      s2, 48(sp)
    sw      s3, 44(sp)
    mv      s0, a1
    mv      s1, a2
    mv      a1, sp
    jal     ra, rubik_asm_parse_state
    bnez    a0, .Lrubik_public_invalid
    # Validate first: invalid input takes precedence even when cap == 0.
    beqz    s1, .Lrubik_public_small
    mv      a0, sp
    jal     ra, rubik_asm_rank_state
    addi    a2, sp, 16
    jal     ra, rubik_asm_ida_search
    bltz    a0, .Lrubik_public_invalid
    mv      s2, a0
    la      s3, rubik_asm_move_tokens
    # Count the entire output, including spaces and NUL, before any write.
    li      t0, 1
    li      t1, 0
.Lrubik_public_count:
    bgeu    t1, s2, .Lrubik_public_capacity
    addi    t2, sp, 16
    add     t2, t2, t1
    lbu     t2, 0(t2)
    slli    t3, t2, 1
    add     t2, t3, t2
    add     t2, s3, t2
    lbu     t3, 1(t2)
    snez    t3, t3
    addi    t0, t0, 1
    add     t0, t0, t3
    beqz    t1, .Lrubik_public_count_next
    addi    t0, t0, 1
.Lrubik_public_count_next:
    addi    t1, t1, 1
    j       .Lrubik_public_count
.Lrubik_public_capacity:
    bltu    s1, t0, .Lrubik_public_small
    li      t0, 0
    mv      t1, s0
.Lrubik_public_emit:
    bgeu    t0, s2, .Lrubik_public_terminated
    beqz    t0, .Lrubik_public_token
    li      t2, 32
    sb      t2, 0(t1)
    addi    t1, t1, 1
.Lrubik_public_token:
    addi    t2, sp, 16
    add     t2, t2, t0
    lbu     t2, 0(t2)
    slli    t3, t2, 1
    add     t2, t3, t2
    add     t2, s3, t2
    lbu     t3, 0(t2)
    sb      t3, 0(t1)
    addi    t1, t1, 1
    lbu     t3, 1(t2)
    beqz    t3, .Lrubik_public_emit_next
    sb      t3, 0(t1)
    addi    t1, t1, 1
.Lrubik_public_emit_next:
    addi    t0, t0, 1
    j       .Lrubik_public_emit
.Lrubik_public_terminated:
    sb      zero, 0(t1)
    mv      a0, s2
    j       .Lrubik_public_restore
.Lrubik_public_small:
    beqz    s1, .Lrubik_public_no_clear
    sb      zero, 0(s0)
.Lrubik_public_no_clear:
    li      a0, -2
    j       .Lrubik_public_restore
.Lrubik_public_invalid:
    li      a0, -1
.Lrubik_public_restore:
    lw      ra, 60(sp)
    lw      s0, 56(sp)
    lw      s1, 52(sp)
    lw      s2, 48(sp)
    lw      s3, 44(sp)
    addi    sp, sp, 64
    ret
    .size   rubik_solve_asm, .-rubik_solve_asm

# Private A1 kernels. Inputs must be valid coordinates and face/index values.
# All are leaves: preserve sp, ra, gp, tp and s0-s11; allocate no stack.
# None calls the C implementation or reads implementation-external symbols.

# (a0=P, a1=Q, a2=face 0:R/1:B/2:D) -> (a0=P', a1=Q').
# Clobbers t0-t2. The row pointers avoid a face-dependent arithmetic loop.
    .local  rubik_asm_quarter_turn
    .type   rubik_asm_quarter_turn, @function
    .align  2
rubik_asm_quarter_turn:
    slli    t0, a2, 3
    la      t1, rubik_asm_row_bases
    add     t0, t1, t0
    lw      t1, 0(t0)
    lw      t2, 4(t0)
    slli    t0, a0, 1
    add     t0, t1, t0
    lhu     a0, 0(t0)
    slli    t0, a1, 1
    add     t0, t2, t0
    lhu     a1, 0(t0)
    ret
    .size   rubik_asm_quarter_turn, .-rubik_asm_quarter_turn

# (a0=P < 5040) -> a0=subset 0..34. Preserves a1; clobbers t0.
    .local  rubik_asm_project
    .type   rubik_asm_project, @function
    .align  2
rubik_asm_project:
    la      t0, rubik_asm_permutation_subset
    add     t0, t0, a0
    lbu     a0, 0(t0)
    ret
    .size   rubik_asm_project, .-rubik_asm_project

# (a0=mixed index < 25515) -> a0=distance. Preserves a1; clobbers t0-t1.
    .local  rubik_asm_packed_distance
    .type   rubik_asm_packed_distance, @function
    .align  2
rubik_asm_packed_distance:
    andi    t0, a0, 1
    slli    t0, t0, 2
    srli    a0, a0, 1
    la      t1, rubik_asm_mixed_distance
    add     t1, t1, a0
    lbu     a0, 0(t1)
    srl     a0, a0, t0
    andi    a0, a0, 15
    ret
    .size   rubik_asm_packed_distance, .-rubik_asm_packed_distance

# (a0=P, a1=Q) -> a0=max(dP,dQ,dMixed,dIdentity). Preserves a1; clobbers t0-t6.
    .local  rubik_asm_heuristic
    .type   rubik_asm_heuristic, @function
    .align  2
rubik_asm_heuristic:
    la      t0, rubik_asm_distance_p
    add     t0, t0, a0
    lbu     t1, 0(t0)
    la      t0, rubik_asm_distance_q
    add     t0, t0, a1
    lbu     t2, 0(t0)
    bgeu    t1, t2, .Lrubik_asm_basic
    mv      t1, t2
.Lrubik_asm_basic:
    la      t0, rubik_asm_permutation_subset
    add     t0, t0, a0
    lbu     t3, 0(t0)
    # 5*s, then 81*s, then 729*s: six fixed-cost RV32I instructions.
    slli    t4, t3, 2
    add     t4, t4, t3
    slli    t5, t4, 4
    add     t4, t5, t3
    slli    t5, t4, 3
    add     t4, t5, t4
    add     t4, t4, a1
    andi    t5, t4, 1
    slli    t5, t5, 2
    srli    t4, t4, 1
    la      t6, rubik_asm_mixed_distance
    add     t6, t6, t4
    lbu     t3, 0(t6)
    srl     t3, t3, t5
    andi    t3, t3, 15
    bgeu    t1, t3, .Lrubik_asm_result
    mv      t1, t3
.Lrubik_asm_result:
    # Ordered positions of cubies 0 and 3: projection[P] = 729*pair_code.
    la      t0, rubik_asm_identity_rows
    slli    t3, a0, 1
    add     t0, t0, t3
    lhu     t3, 0(t0)
    add     t3, t3, a1
    andi    t4, t3, 1
    slli    t4, t4, 2
    srli    t3, t3, 1
    la      t5, rubik_asm_identity_distance
    add     t5, t5, t3
    lbu     t3, 0(t5)
    srl     t3, t3, t4
    andi    t3, t3, 15
    bgeu    t1, t3, .Lrubik_asm_identity_result
    mv      t1, t3
.Lrubik_asm_identity_result:
    mv      a0, t1
    ret
    .size   rubik_asm_heuristic, .-rubik_asm_heuristic

# A6b cached-base variant: identical heuristic, with bases supplied by DFS.
# (a0=P, a1=Q) -> a0=max(dP,dQ,dMixed,dIdentity). Preserves a1; clobbers t0-t6.
# Requires s7=dP base, s8=dQ base, s9=subset base, s10=mixed base.
# These private context registers are read-only here and preserved by A1.
    .local  rubik_asm_heuristic_cached
    .type   rubik_asm_heuristic_cached, @function
    .align  2
rubik_asm_heuristic_cached:
    add     t0, s7, a0
    lbu     t1, 0(t0)
    add     t0, s8, a1
    lbu     t2, 0(t0)
    bgeu    t1, t2, .Lrubik_cached_basic
    mv      t1, t2
.Lrubik_cached_basic:
    add     t0, s9, a0
    lbu     t3, 0(t0)
    slli    t4, t3, 2
    add     t4, t4, t3
    slli    t5, t4, 4
    add     t4, t5, t3
    slli    t5, t4, 3
    add     t4, t5, t4
    add     t4, t4, a1
    andi    t5, t4, 1
    slli    t5, t5, 2
    srli    t4, t4, 1
    add     t6, s10, t4
    lbu     t3, 0(t6)
    srl     t3, t3, t5
    andi    t3, t3, 15
    bgeu    t1, t3, .Lrubik_cached_result
    mv      t1, t3
.Lrubik_cached_result:
    # New bases use temporaries; the existing s7-s10 context stays unchanged.
    la      t0, rubik_asm_identity_rows
    slli    t3, a0, 1
    add     t0, t0, t3
    lhu     t3, 0(t0)
    add     t3, t3, a1
    andi    t4, t3, 1
    slli    t4, t4, 2
    srli    t3, t3, 1
    la      t5, rubik_asm_identity_distance
    add     t5, t5, t3
    lbu     t3, 0(t5)
    srl     t3, t3, t4
    andi    t3, t3, 15
    bgeu    t1, t3, .Lrubik_cached_identity_result
    mv      t1, t3
.Lrubik_cached_identity_result:
    mv      a0, t1
    ret
    .size   rubik_asm_heuristic_cached, .-rubik_asm_heuristic_cached

# Private A2: one bounded iteration, with no outer IDA* loop.
# (a0=P, a1=Q, a2=bound, a3=11-byte path) -> a0=length, or -1 NOT_FOUND.
# Requires P<5040, Q<729 and writable private path storage. Bounds >11 are
# rejected without touching path. Path contents are meaningful on success only.
# s0=bound, s1=depth, s2=current frame, s3=path, s4=move, s5=face,
# s6=power index 0..2; s7-s10=heuristic table bases, initialized once per call.
# Next-frame P/Q cache the last sibling, including a heuristically pruned one.
# Stack: frames[12] at sp+4..75; reserved guard slots at 0..3 and 76..79;
# saved s7..s0 at 80..111, ra at 112..115, s8-s10 at 116..127 (former padding).
    .local  rubik_asm_bounded_dfs
    .type   rubik_asm_bounded_dfs, @function
    .align  2
rubik_asm_bounded_dfs:
    li      t0, 11
    bltu    t0, a2, .Lrubik_bound_rejected
    addi    sp, sp, -128
    sw      ra, 112(sp)
    sw      s0, 108(sp)
    sw      s1, 104(sp)
    sw      s2, 100(sp)
    sw      s3, 96(sp)
    sw      s4, 92(sp)
    sw      s5, 88(sp)
    sw      s6, 84(sp)
    sw      s7, 80(sp)
    sw      s8, 116(sp)
    sw      s9, 120(sp)
    sw      s10, 124(sp)
    mv      s0, a2
    li      s1, 0
    addi    s2, sp, 4
    mv      s3, a3
    la      s7, rubik_asm_distance_p
    la      s8, rubik_asm_distance_q
    la      s9, rubik_asm_permutation_subset
    la      s10, rubik_asm_mixed_distance
    sh      a0, 0(s2)
    sh      a1, 2(s2)
    li      t0, 3
    sb      t0, 4(s2)
    sb      zero, 5(s2)
    jal     ra, rubik_asm_heuristic_cached
    bltu    s0, a0, .Lrubik_bound_not_found

.Lrubik_bound_frame:
    lhu     t0, 0(s2)
    lhu     t1, 2(s2)
    or      t0, t0, t1
    beqz    t0, .Lrubik_bound_solved
    # Check the goal before rejecting a frame at exactly the bound.
    beq     s1, s0, .Lrubik_bound_backtrack
    lbu     s4, 5(s2)
    li      t0, 9
    bgeu    s4, t0, .Lrubik_bound_backtrack
    li      s5, 0
    mv      s6, s4
    li      t0, 3
    bltu    s4, t0, .Lrubik_bound_decoded
    li      s5, 1
    addi    s6, s4, -3
    li      t0, 6
    bltu    s4, t0, .Lrubik_bound_decoded
    li      s5, 2
    addi    s6, s4, -6
.Lrubik_bound_decoded:
    lbu     t0, 4(s2)
    beq     s5, t0, .Lrubik_bound_skip_face
    # Allowed candidates advance the parent before heuristic pruning/descent.
    addi    t0, s4, 1
    sb      t0, 5(s2)
    # The first power starts at the parent; later powers advance the cache.
    # A child's own P/Q stay immutable while it explores subsequent frames.
    beqz    s6, .Lrubik_bound_parent
    lhu     a0, 6(s2)
    lhu     a1, 8(s2)
    j       .Lrubik_bound_turn
.Lrubik_bound_parent:
    lhu     a0, 0(s2)
    lhu     a1, 2(s2)
.Lrubik_bound_turn:
    mv      a2, s5
    jal     ra, rubik_asm_quarter_turn
    # depth < bound <= 11, so the next frame exists. Cache before pruning:
    # R2/R' (and B/D siblings) must still advance a rejected candidate.
    sh      a0, 6(s2)
    sh      a1, 8(s2)
    jal     ra, rubik_asm_heuristic_cached
    addi    t0, s1, 1
    add     t0, t0, a0
    bltu    s0, t0, .Lrubik_bound_frame
    # depth < bound <= 11: path[0..10] and frames[1..11] fit.
    add     t0, s3, s1
    sb      s4, 0(t0)
    addi    s2, s2, 6
    # P/Q were initialized before the heuristic; reset only child metadata.
    sb      s5, 4(s2)
    sb      zero, 5(s2)
    addi    s1, s1, 1
    j       .Lrubik_bound_frame

.Lrubik_bound_skip_face:
    # A forbidden face is first encountered at power 0: none of its siblings
    # can descend. Skip all three; the next face reloads the parent P/Q.
    addi    t0, s4, 3
    sb      t0, 5(s2)
    j       .Lrubik_bound_frame

.Lrubik_bound_backtrack:
    beqz    s1, .Lrubik_bound_not_found
    addi    s1, s1, -1
    addi    s2, s2, -6
    j       .Lrubik_bound_frame
.Lrubik_bound_solved:
    mv      a0, s1
    j       .Lrubik_bound_restore
.Lrubik_bound_not_found:
    li      a0, -1
.Lrubik_bound_restore:
    lw      ra, 112(sp)
    lw      s0, 108(sp)
    lw      s1, 104(sp)
    lw      s2, 100(sp)
    lw      s3, 96(sp)
    lw      s4, 92(sp)
    lw      s5, 88(sp)
    lw      s6, 84(sp)
    lw      s7, 80(sp)
    lw      s8, 116(sp)
    lw      s9, 120(sp)
    lw      s10, 124(sp)
    addi    sp, sp, 128
    ret
.Lrubik_bound_rejected:
    li      a0, -1
    ret
    .size   rubik_asm_bounded_dfs, .-rubik_asm_bounded_dfs

# Private A3: complete IDA* search over already validated coordinates.
# (a0=P, a1=Q, a2=11-byte path) -> a0=optimal length, or -1 NOT_FOUND.
# Requires P<5040, Q<729 and writable private path storage. Only path[0..a0)
# is meaningful on success; a zero-length result is success, not NOT_FOUND.
# s0=original P, s1=original Q, s2=path, s3=bound. Each A2 call initializes
# its own root frame/cursor; no search state is carried between iterations.
# Stack: 32 bytes here plus A2's fixed 128 bytes, independent of bound/depth.
    .local  rubik_asm_ida_search
    .type   rubik_asm_ida_search, @function
    .align  2
rubik_asm_ida_search:
    addi    sp, sp, -32
    sw      ra, 28(sp)
    sw      s0, 24(sp)
    sw      s1, 20(sp)
    sw      s2, 16(sp)
    sw      s3, 12(sp)
    mv      s0, a0
    mv      s1, a1
    mv      s2, a2
    jal     ra, rubik_asm_heuristic
    mv      s3, a0
.Lrubik_ida_bound:
    li      t0, 11
    bltu    t0, s3, .Lrubik_ida_not_found
    mv      a0, s0
    mv      a1, s1
    mv      a2, s3
    mv      a3, s2
    jal     ra, rubik_asm_bounded_dfs
    bgez    a0, .Lrubik_ida_restore
    addi    s3, s3, 1
    j       .Lrubik_ida_bound
.Lrubik_ida_not_found:
    li      a0, -1
.Lrubik_ida_restore:
    lw      ra, 28(sp)
    lw      s0, 24(sp)
    lw      s1, 20(sp)
    lw      s2, 16(sp)
    lw      s3, 12(sp)
    addi    sp, sp, 32
    ret
    .size   rubik_asm_ida_search, .-rubik_asm_ida_search

# Private A4: HW1 parser, with invalid status adapted to this API's -1.
# (a0=input, a1=14-byte private state) -> a0=0 valid, or -1 invalid.
# State holds seven cubies then seven orientations, all zero-based. Partial
# private state on failure is unused. Reads sequentially through input[14];
# an earlier NUL fails its range check before any subsequent input read.
# Leaf: clobbers a0,t0-t6; preserves a1,sp,ra,gp,tp and s0-s11.
    .local  rubik_asm_parse_state
    .type   rubik_asm_parse_state, @function
    .align  2
rubik_asm_parse_state:
    mv      t0, a0
    mv      t1, a1
    li      t2, 7
    li      t3, 0
.Lrubik_parse_permutation:
    lbu     t4, 0(t0)
    addi    t4, t4, -49
    li      t5, 7
    bgeu    t4, t5, .Lrubik_parse_invalid
    li      t5, 1
    sll     t5, t5, t4
    and     t6, t3, t5
    bnez    t6, .Lrubik_parse_invalid
    or      t3, t3, t5
    sb      t4, 0(t1)
    addi    t0, t0, 1
    addi    t1, t1, 1
    addi    t2, t2, -1
    bnez    t2, .Lrubik_parse_permutation
    # Seven unique values in 0..6 already form a complete permutation.
    li      t2, 7
    li      t3, 0
.Lrubik_parse_orientation:
    lbu     t4, 0(t0)
    addi    t4, t4, -49
    li      t5, 3
    bgeu    t4, t5, .Lrubik_parse_invalid
    sb      t4, 0(t1)
    add     t3, t3, t4
    addi    t0, t0, 1
    addi    t1, t1, 1
    addi    t2, t2, -1
    bnez    t2, .Lrubik_parse_orientation
    lbu     t4, 0(t0)
    bnez    t4, .Lrubik_parse_invalid
    li      t5, 3
.Lrubik_parse_modulo:
    bltu    t3, t5, .Lrubik_parse_remainder
    addi    t3, t3, -3
    j       .Lrubik_parse_modulo
.Lrubik_parse_remainder:
    bnez    t3, .Lrubik_parse_invalid
    li      a0, 0
    ret
.Lrubik_parse_invalid:
    li      a0, -1
    ret
    .size   rubik_asm_parse_state, .-rubik_asm_parse_state

# Private A4: verified HW1 lexicographic permutation/base-3 orientation rank.
# (a0=validated 14-byte private state) -> (a0=P, a1=Q).
# Leaf: clobbers a0-a2,t0-t6; preserves sp,ra,gp,tp and s0-s11.
    .local  rubik_asm_rank_state
    .type   rubik_asm_rank_state, @function
    .align  2
rubik_asm_rank_state:
    mv      t0, a0
    li      t1, 0
    li      t2, 0
.Lrubik_rank_position:
    add     a2, t0, t2
    lbu     t5, 0(a2)
    addi    t3, t2, 1
    li      t4, 0
.Lrubik_rank_right:
    li      t6, 7
    bgeu    t3, t6, .Lrubik_rank_counted
    add     a2, t0, t3
    lbu     t6, 0(a2)
    bgeu    t6, t5, .Lrubik_rank_next_right
    addi    t4, t4, 1
.Lrubik_rank_next_right:
    addi    t3, t3, 1
    j       .Lrubik_rank_right
.Lrubik_rank_counted:
    # P = old_P * (7-i) + number of smaller cubies to the right.
    li      t3, 7
    sub     t3, t3, t2
    mv      a2, t1
    li      t1, 0
.Lrubik_rank_multiply:
    add     t1, t1, a2
    addi    t3, t3, -1
    bnez    t3, .Lrubik_rank_multiply
    add     t1, t1, t4
    addi    t2, t2, 1
    li      t3, 7
    bltu    t2, t3, .Lrubik_rank_position
    addi    t0, t0, 7
    li      a1, 0
    li      t2, 6
.Lrubik_rank_twist:
    lbu     t3, 0(t0)
    slli    t4, a1, 1
    add     a1, t4, a1
    add     a1, a1, t3
    addi    t0, t0, 1
    addi    t2, t2, -1
    bnez    t2, .Lrubik_rank_twist
    mv      a0, t1
    ret
    .size   rubik_asm_rank_state, .-rubik_asm_rank_state

    .section .rodata.rubik_asm, "a", @progbits
    .local  rubik_asm_move_tokens
    .type   rubik_asm_move_tokens, @object
rubik_asm_move_tokens:
    .byte   82, 0, 0, 82, 50, 0, 82, 39, 0
    .byte   66, 0, 0, 66, 50, 0, 66, 39, 0
    .byte   68, 0, 0, 68, 50, 0, 68, 39, 0
    .size   rubik_asm_move_tokens, .-rubik_asm_move_tokens

    .include "src/rubik/rubik_asm_tables.inc"
    .include "src/rubik/rubik_identity.inc"
    .option pop
