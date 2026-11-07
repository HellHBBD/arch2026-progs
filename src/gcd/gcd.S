# gcd_u32_asm: binary GCD, hand-written RV32I.
#
# uint32_t gcd_u32_asm(uint32_t a, uint32_t b)   a in a0, b in a1, result in a0
#
# RV32I and Zicsr only: no mul, div, rem, no floating point, no compressed
# instructions. Tests: tests/tgcd.c.

    .text

    .globl  gcd_u32_asm
    .type   gcd_u32_asm, @function
    .align  2
gcd_u32_asm:
	bgeu	a1, a0, LBgtA
	mv		t0, a0
	mv		a0, a1
	mv		a1, t0

LBgtA:
	bnez	a0, LAnez
	mv		a0, a1
	ret
LAnez:
	addi	t0, x0, 1
	bne		a0, t0, LAneI
	li		a0, 1
	ret
LAneI:
	andi	t0, a0, 1
	andi	t1, a1, 1
	bnez	t0, LII
	bnez	t1, LI
LO:
	addi	sp, sp, -16
	sw		ra, 12(sp)
	srli	a0, a0, 1
	srli	a1, a1, 1
	call	gcd_u32_asm
	lw		ra, 12(sp)
	addi	sp, sp, 16
	slli	a0, a0, 1
	ret
LI:
	srli	a0, a0, 1
	j		gcd_u32_asm
LII:
	bnez	t1, LIII
	srli	a1, a1, 1
	j		gcd_u32_asm
LIII:
	sub		a1, a1, a0
	srli	a1, a1, 1
	j		gcd_u32_asm

    .size   gcd_u32_asm, .-gcd_u32_asm
