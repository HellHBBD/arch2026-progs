# op1, op2, op3 and q_mul: hand-written RV32I.
#
# uint32_t op1_asm(uint32_t a, uint32_t b, int *n)   a0, a1, a2 -> a0
# uint32_t op2_asm(uint32_t a, uint32_t b)           a0, a1 -> a0
# uint32_t op3_asm(uint32_t a, uint32_t b)           a0, a1 -> a0
# int32_t  q_mul_asm(int32_t a, int32_t b)           a0, a1 -> a0
#
# RV32I and Zicsr only: no mul, div, rem, no floating point, no compressed
# instructions. q_mul forms a 64-bit product in a register pair. Tests:
# tests/tfixed.c.

    .text

    .globl  op1_asm
    .type   op1_asm, @function
    .align  2
op1_asm:
    # t0: pass count; t1: next carry. Unsigned shifts discard bit 32.
    li      t0, 0
    beqz    a1, .Lop1_done
.Lop1_loop:
    and     t1, a0, a1
    xor     a0, a0, a1
    slli    a1, t1, 1
    addi    t0, t0, 1
    bnez    a1, .Lop1_loop
.Lop1_done:
    sw      t0, 0(a2)
    ret
    .size   op1_asm, .-op1_asm

    .globl  op2_asm
    .type   op2_asm, @function
    .align  2
op2_asm:
    # No temporaries: subtraction wraps modulo 2^32.
    sub     a0, a0, a1
    ret
    .size   op2_asm, .-op2_asm

    .globl  op3_asm
    .type   op3_asm, @function
    .align  2
op3_asm:
    # t0: shared bits. The two terms cannot overflow their exact average.
    and     t0, a0, a1
    xor     a0, a0, a1
    srli    a0, a0, 1
    add     a0, a0, t0
    ret
    .size   op3_asm, .-op3_asm

    .globl  q_mul_asm
    .type   q_mul_asm, @function
    .align  2
q_mul_asm:
    # a3:a0: shifted unsigned multiplicand; a1: remaining multiplier.
    # a4:a2: product, seeded with signed correction and rounding bias.
    # t0, t1: sign/bit temporaries; t2: carry. Leaf, no stack or helpers.
    srai    t0, a0, 31
    and     t0, t0, a1
    srai    t1, a1, 31
    and     t1, t1, a0
    add     a4, t0, t1
    neg     a4, a4
    li      a2, 0x80000
    li      a3, 0
    beqz    a1, .Lq_round
.Lq_loop:
    andi    t0, a1, 1
    beqz    t0, .Lq_shift
    add     a2, a2, a0
    sltu    t2, a2, a0
    add     a4, a4, a3
    add     a4, a4, t2
.Lq_shift:
    srli    t2, a0, 31
    slli    a3, a3, 1
    or      a3, a3, t2
    slli    a0, a0, 1
    # Process the next multiplier bit before updating the loop condition.
    # This saves one multiplier shift and one loop branch per pair of bits.
    andi    t0, a1, 2
    beqz    t0, .Lq_shift_second
    add     a2, a2, a0
    sltu    t2, a2, a0
    add     a4, a4, a3
    add     a4, a4, t2
.Lq_shift_second:
    srli    t2, a0, 31
    slli    a3, a3, 1
    or      a3, a3, t2
    slli    a0, a0, 1
    srli    a1, a1, 2
    bnez    a1, .Lq_loop
.Lq_round:
    # The initial half-unit bias has participated in every carry propagation.
    srli    a2, a2, 20
    slli    a4, a4, 12
    or      a0, a2, a4
    ret
    .size   q_mul_asm, .-q_mul_asm
