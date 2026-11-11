# BFloat16 routines: hand-written RV32I.
#
# uint16_t bf16_from_f32_asm(uint32_t f32bits)   a0 -> a0
# uint16_t bf16_mul_asm(uint16_t a, uint16_t b)  a0, a1 -> a0
# uint16_t bf16_sqrt_asm(uint16_t a)             a0 -> a0
#
# RV32I and Zicsr only: no mul, div, rem, no floating point, no compressed
# instructions. Tests: tests/tbf16.c.

    .text

    .globl  bf16_from_f32_asm
    .type   bf16_from_f32_asm, @function
    .align  2
bf16_from_f32_asm:
	srli	t0, a0, 16
	srli	t1, a0, 23
	andi	t1, t1, 0xFF
	li		t2, 0xFF
	bne		t1, t2, Lnormal
	mv		a0, t0
	ret
Lnormal:
	andi	t0, t0, 1
	addi	t0, t0, -1
	lui		t1, 0x8
	add		t0, t0, t1
	add		a0, a0, t0
	srli	a0, a0, 16
	ret
    .size   bf16_from_f32_asm, .-bf16_from_f32_asm

    .globl  bf16_mul_asm
    .type   bf16_mul_asm, @function
    .align  2
bf16_mul_asm:
    # Leaf: t0 = result sign, t1/t2 = signed exponents, t3/t4 =
    # significands, a2 = product; t5/t6 are scratch. No stack is used.
    xor     t0, a0, a1
    srli    t0, t0, 15
    slli    t0, t0, 15
    srli    t1, a0, 7
    andi    t1, t1, 255
    srli    t2, a1, 7
    andi    t2, t2, 255
    andi    t3, a0, 127
    andi    t4, a1, 127
    li      t6, 255
    beq     t1, t6, .Lmul_special_a
    beq     t2, t6, .Lmul_special_b
    or      t5, t1, t3
    beqz    t5, .Lmul_zero
    or      t5, t2, t4
    beqz    t5, .Lmul_zero
    # Normalization never increases a stored exponent (even for a
    # subnormal). A sum below 120 cannot reach result exponent -6,
    # even after the product's possible +1 renormalization.
    add     t5, t1, t2
    li      t6, 120
    bltu    t5, t6, .Lmul_zero
    # A sum >= 382 implies two normals and exponent >= 255 already.
    li      t6, 382
    bgeu    t5, t6, .Lmul_inf
    bnez    t1, .Lmul_normal_a
    li      t1, 1
.Lmul_normalize_a:
    slli    t3, t3, 1
    addi    t1, t1, -1
    sltiu   t5, t3, 128
    bnez    t5, .Lmul_normalize_a
    j       .Lmul_prepare_b
.Lmul_normal_a:
    ori     t3, t3, 128
.Lmul_prepare_b:
    bnez    t2, .Lmul_normal_b
    li      t2, 1
.Lmul_normalize_b:
    slli    t4, t4, 1
    addi    t2, t2, -1
    sltiu   t5, t4, 128
    bnez    t5, .Lmul_normalize_b
    j       .Lmul_product
.Lmul_normal_b:
    ori     t4, t4, 128
.Lmul_product:
    add     t1, t1, t2
    addi    t1, t1, -127
    # The normalized multiplier's bit 7 is always one. Account for it
    # directly, then visit only its fraction bits (possibly none).
    slli    a2, t3, 7
    andi    t4, t4, 127
    beqz    t4, .Lmul_product_done
.Lmul_bits:
    andi    t5, t4, 1
    beqz    t5, .Lmul_next_bit
    add     a2, a2, t3
.Lmul_next_bit:
    slli    t3, t3, 1
    srli    t4, t4, 1
    bnez    t4, .Lmul_bits
.Lmul_product_done:
    srli    t5, a2, 15
    beqz    t5, .Lmul_fraction
    srli    a2, a2, 1
    addi    t1, t1, 1
.Lmul_fraction:
    srli    a0, a2, 7
    andi    a0, a0, 127
    li      t6, 255
    bge     t1, t6, .Lmul_inf
    blez    t1, .Lmul_underflow
    slli    t1, t1, 7
    or      a0, a0, t1
    or      a0, a0, t0
    ret
.Lmul_underflow:
    li      t5, -6
    blt     t1, t5, .Lmul_zero
    li      t5, 1
    sub     t5, t5, t1
    # Contract: shift the fraction alone, without restoring the hidden one.
    srl     a0, a0, t5
    or      a0, a0, t0
    ret
.Lmul_special_a:
    bnez    t3, .Lmul_return
    or      t5, t2, t4
    beqz    t5, .Lmul_nan
    j       .Lmul_inf
.Lmul_special_b:
    bnez    t4, .Lmul_nan_b
    or      t5, t1, t3
    beqz    t5, .Lmul_nan
.Lmul_inf:
    li      a0, 0x7f80
    or      a0, a0, t0
    ret
.Lmul_nan_b:
    mv      a0, a1
    ret
.Lmul_nan:
    li      a0, 0x7fc0
    ret
.Lmul_zero:
    mv      a0, t0
.Lmul_return:
    ret
    .size   bf16_mul_asm, .-bf16_mul_asm

    .globl  bf16_sqrt_asm
    .type   bf16_sqrt_asm, @function
    .align  2
bf16_sqrt_asm:
    # Leaf: t0 = packed output exponent, t1 = remainder, t2 = bit-pair
    # weight, t3 = trial, t4 = partial root. No stack or multiply is used.
    srli    t0, a0, 7
    andi    t0, t0, 255
    andi    t1, a0, 127
    li      t2, 255
    beq     t0, t2, .Lsqrt_special
    slli    t2, a0, 17
    beqz    t2, .Lsqrt_zero
    srli    t2, a0, 15
    bnez    t2, .Lsqrt_nan
    beqz    t0, .Lsqrt_zero
    ori     t1, t1, 128
    andi    t2, t0, 1
    bnez    t2, .Lsqrt_even_exponent
    slli    t1, t1, 1
.Lsqrt_even_exponent:
    # floor((E - 127)/2) + 127 == (E + 127) >> 1, for 1 <= E <= 254.
    addi    t0, t0, 127
    srli    t0, t0, 1
    slli    t0, t0, 7
    # floor(r*r/128) <= m iff r*r <= 128*m + 127. Compute that
    # radicand's exact integer square root, one base-4 digit at a time.
    slli    t1, t1, 7
    ori     t1, t1, 127
    # The radicand is in [16511, 65407], so its first base-4 digit
    # always accepts 0x4000. Start after that guaranteed step.
    li      t4, 0x4000
    sub     t1, t1, t4
    li      t2, 0x1000
.Lsqrt_digit:
    add     t3, t4, t2
    srli    t4, t4, 1
    bltu    t1, t3, .Lsqrt_next_digit
    sub     t1, t1, t3
    add     t4, t4, t2
.Lsqrt_next_digit:
    srli    t2, t2, 2
    bnez    t2, .Lsqrt_digit
.Lsqrt_pack:
    # For positive normals the root is already in [128, 255].
    andi    a0, t4, 127
    or      a0, a0, t0
    ret
.Lsqrt_special:
    bnez    t1, .Lsqrt_return
    srli    t2, a0, 15
    beqz    t2, .Lsqrt_return
.Lsqrt_nan:
    li      a0, 0x7fc0
    ret
.Lsqrt_zero:
    li      a0, 0
.Lsqrt_return:
    ret
    .size   bf16_sqrt_asm, .-bf16_sqrt_asm
