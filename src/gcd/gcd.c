#include "gcd.h"

uint32_t gcd_u32(uint32_t a, uint32_t b)
{
    if (a > b)
        return gcd_u32(b, a);
    switch (a) {
    case 0:
        return b;
    case 1:
        return 1;
    }
    if (a & 1u) {
        if (b & 1u) {
            return gcd_u32(a, (b - a) >> 1);
        }
        return gcd_u32(a, b >> 1);
    } else {
        if (b & 1u) {
            return gcd_u32(a >> 1, b);
        }
        return gcd_u32(a >> 1, b >> 1) << 1;
    }
}
