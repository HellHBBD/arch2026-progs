#include "fixed.h"

uint32_t op1(uint32_t a, uint32_t b, int *n)
{
    int passes = 0;
    while (b) {
        uint32_t carry = (a & b) << 1;
        a ^= b;
        b = carry;
        passes++;
    }
    *n = passes;
    return a;
}

uint32_t op2(uint32_t a, uint32_t b)
{
    return a - b;
}

uint32_t op3(uint32_t a, uint32_t b)
{
    /* a + b = 2 * (a & b) + (a ^ b), without forming the sum. */
    return (a & b) + ((a ^ b) >> 1);
}

int32_t q_mul(int32_t a, int32_t b)
{
    /* Four 16-bit partial products avoid the unavailable __muldi3 helper.
     * Correct the unsigned product's high word for each negative operand;
     * all accumulation is modulo 2^64, including INT32_MIN inputs.
     */
    uint32_t ua = (uint32_t) a, ub = (uint32_t) b;
    uint32_t al = ua & 0xffff, ah = ua >> 16;
    uint32_t bl = ub & 0xffff, bh = ub >> 16;
    uint64_t product = (uint64_t) (al * bl) + ((uint64_t) (al * bh) << 16) +
                       ((uint64_t) (ah * bl) << 16) +
                       ((uint64_t) (ah * bh) << 32);
    if (a < 0)
        product -= (uint64_t) ub << 32;
    if (b < 0)
        product -= (uint64_t) ua << 32;
    /* Logical and arithmetic shifts have identical low 32 result bits here.
     * GCC's conversion to int32_t keeps these bits, as the contract requires.
     */
    uint64_t rounded = product + (UINT64_C(1) << (Q - 1));
    return (int32_t) (uint32_t) (rounded >> Q);
}
