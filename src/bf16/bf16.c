#include "bf16.h"
#include <stdint.h>

uint16_t bf16_from_f32(uint32_t f32bits)
{
    uint16_t H = f32bits >> 16;
    if ((f32bits >> 23 & 0xFF) == 0xFF)
        return H;
    uint16_t bias = 0x7FFF + (H & 1u);
    return (f32bits + bias) >> 16;
}

uint16_t bf16_mul(uint16_t a, uint16_t b)
{
    uint8_t sa = a >> 15 & 1u;
    uint8_t sb = b >> 15 & 1u;
    uint8_t ea = a >> 7 & 0xFF;
    uint8_t eb = b >> 7 & 0xFF;
    uint8_t fa = a & 0x7F;
    uint8_t fb = b & 0x7F;

    uint8_t sign = sa ^ sb;
    // a is NaN, return a
    if (ea == 0xFF && fa)
        return a;
    // a is Inf
    if (ea == 0xFF && fa == 0) {
        // b is Zero, return 0x7FC0
        if (eb == 0 && fb == 0)
            return 0x7FC0;
        // b isn't Zero, return Inf
        else
            // 111 1111 1000 0000
            return sign << 15 | 0x7F80;
    }
    // b the same as a
    if (eb == 0xFF && fb)
        return b;
    if (eb == 0xFF && fb == 0) {
        if (ea == 0 && fa == 0)
            return 0x7FC0;
        else
            return sign << 15 | 0x7F80;
    }
    // any Zero, return Zero
    if ((ea == 0 && fa == 0) || (eb == 0 && fb == 0))
        return sign << 15;
    /* Normalize each nonzero operand to an 8-bit significand. Subnormal
     * exponents can become negative, so keep the arithmetic signed.
     */
    int exp_a = ea ? ea : 1;
    int exp_b = eb ? eb : 1;
    uint32_t ma = ea ? fa | 0x80u : fa;
    uint32_t mb = eb ? fb | 0x80u : fb;
    while (ma < 0x80u) {
        ma <<= 1;
        exp_a--;
    }
    while (mb < 0x80u) {
        mb <<= 1;
        exp_b--;
    }
    int exponent = exp_a + exp_b - 127;
    uint32_t product = ma * mb;
    if (product & 0x8000u) {
        product >>= 1;
        exponent++;
    }
    uint32_t fraction = (product >> 7) & 0x7Fu;
    if (exponent >= 255)
        return (sign << 15) | 0x7F80u;
    if (exponent <= 0) {
        /* The assignment shifts the fraction WITHOUT the hidden one. */
        if (exponent < -6)
            return sign << 15;
        return (sign << 15) | (fraction >> (1 - exponent));
    }
    return (sign << 15) | ((uint32_t) exponent << 7) | fraction;
}

uint16_t bf16_sqrt(uint16_t a)
{
    uint32_t exponent = (a >> 7) & 0xFFu;
    uint32_t fraction = a & 0x7Fu;
    if (exponent == 255 && fraction)
        return a;
    if ((a & 0x7FFFu) == 0)
        return 0;
    if (a & 0x8000u)
        return 0x7FC0;
    if (exponent == 255)
        return a;
    if (exponent == 0)
        return 0;

    int e = (int) exponent - 127;
    uint32_t m = 0x80u | fraction;
    if (e % 2 != 0) {
        m <<= 1;
        e--;
    }
    uint32_t low = 90, high = 256, root = 0;
    while (low <= high) {
        uint32_t mid = (low + high) >> 1;
        if (((mid * mid) >> 7) <= m) {
            root = mid;
            low = mid + 1;
        } else {
            high = mid - 1;
        }
    }
    /* Here 128 <= m <= 510, so 128 <= root <= 255. The result
     * exponent is in [64, 190]: no further renormalization is needed.
     */
    return ((uint32_t) (e / 2 + 127) << 7) | (root & 0x7Fu);
}
