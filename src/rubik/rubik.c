#include "rubik.h"

#include "rubik_distances.inc"
#include "rubik_mixed.inc"
#include "rubik_turns.inc"

typedef struct {
    uint8_t p[7];
    uint8_t o[7];
} rubik_state_t;

typedef struct {
    uint16_t p;
    uint16_t q;
} rubik_coordinates_t;

enum {
    RUBIK_MAX_DEPTH = 11,
    RUBIK_MOVE_COUNT = 9,
    RUBIK_NOT_FOUND = -1,
};

static const char move_tokens[RUBIK_MOVE_COUNT][3] = {
    "R", "R2", "R'", "B", "B2", "B'", "D", "D2", "D'",
};

typedef struct {
    uint16_t p;
    uint16_t q;
    uint8_t previous_face;
    uint8_t next_move;
} rubik_frame_t;

/* Requires p < 5040 and q < 729. A move may improve both coordinates, so
 * take the maximum of their lower bounds rather than adding them.
 */
static inline uint8_t basic_heuristic(uint16_t p, uint16_t q)
{
    uint8_t dp = distance_p[p];
    uint8_t dq = distance_q[q];
    return dp > dq ? dp : dq;
}

/* Couple the tracked occupied-position subset with the full orientation. */
static inline uint8_t mixed_heuristic(uint16_t p, uint16_t q)
{
    unsigned index = (unsigned) permutation_subset[p] * 729U + q;
    unsigned shift = (index & 1U) * 4U;
    return (uint8_t) ((mixed_distance[index >> 1] >> shift) & 0x0fU);
}

/* Each projection is admissible; retain the basic bound when it is stronger. */
static inline uint8_t search_heuristic(uint16_t p, uint16_t q)
{
    uint8_t basic = basic_heuristic(p, q);
    uint8_t mixed = mixed_heuristic(p, q);
    return basic > mixed ? basic : mixed;
}

/* Requires p < 5040, q < 729, face < 3; face order is R, B, D. */
static inline rubik_coordinates_t quarter_turn_coordinates(uint16_t p,
                                                           uint16_t q,
                                                           unsigned face)
{
    return (rubik_coordinates_t) {permutation_turn[face][p],
                                  orientation_turn[face][q]};
}

/* One HW1 DFS iteration: no outer IDA* bound loop. Requires valid P/Q and
 * an 11-byte path buffer. Returns a solution length or RUBIK_NOT_FOUND;
 * path contents are meaningful only on success. Bounds above 11 are rejected.
 */
static inline int bounded_dfs(uint16_t p,
                              uint16_t q,
                              unsigned bound,
                              uint8_t path[RUBIK_MAX_DEPTH])
{
    if (bound > RUBIK_MAX_DEPTH || search_heuristic(p, q) > bound)
        return RUBIK_NOT_FOUND;

    rubik_frame_t frames[RUBIK_MAX_DEPTH + 1];
    unsigned depth = 0;
    /* Sentinel face 3 permits every face at the root. */
    frames[0] = (rubik_frame_t) {p, q, 3, 0};
    for (;;) {
        rubik_frame_t *frame = &frames[depth];
        /* A goal at exactly the bound must be accepted. */
        if (frame->p == 0 && frame->q == 0)
            return (int) depth;
        if (depth == bound || frame->next_move == RUBIK_MOVE_COUNT) {
            if (depth == 0)
                return RUBIK_NOT_FOUND;
            depth--;
            continue;
        }

        /* Advance before descent: backtracking resumes with the next move. */
        uint8_t move = frame->next_move++;
        uint8_t face = move >= 6 ? 2 : move >= 3 ? 1 : 0;
        if (face == frame->previous_face)
            continue;
        unsigned turns = move - 3U * face + 1U;
        rubik_coordinates_t next = {frame->p, frame->q};
        for (unsigned turn = 0; turn < turns; turn++)
            next = quarter_turn_coordinates(next.p, next.q, face);
        if (depth + 1U + search_heuristic(next.p, next.q) > bound)
            continue;

        /* depth < bound <= 11: path[0..10] and frames[1..11] fit. */
        path[depth] = move;
        depth++;
        frames[depth] = (rubik_frame_t) {next.p, next.q, face, 0};
    }
}

/* The first successful bound is optimal because the initial heuristic is
 * admissible and each smaller bound has been exhausted.
 */
static inline int ida_search(uint16_t p,
                             uint16_t q,
                             uint8_t path[RUBIK_MAX_DEPTH])
{
    for (unsigned bound = search_heuristic(p, q); bound <= RUBIK_MAX_DEPTH;
         bound++) {
        int length = bounded_dfs(p, q, bound, path);
        if (length != RUBIK_NOT_FOUND)
            return length;
    }
    return RUBIK_NOT_FOUND;
}

/* Rank an already validated state using the HW1 coordinate convention. */
static rubik_coordinates_t rank_coordinates(const rubik_state_t *state)
{
    unsigned p = 0;
    unsigned q = 0;
    for (unsigned i = 0; i < 7; i++) {
        unsigned smaller = 0;
        for (unsigned j = i + 1; j < 7; j++) {
            if (state->p[i] > state->p[j])
                smaller++;
        }
        p = p * (7 - i) + smaller;
    }
    /* The orientation-sum invariant determines the seventh orientation. */
    for (unsigned i = 0; i < 6; i++)
        q = 3 * q + state->o[i];
    return (rubik_coordinates_t) {(uint16_t) p, (uint16_t) q};
}

int rubik_solve(const char *state, char *out, size_t cap)
{
    unsigned seen = 0;
    unsigned sum = 0;
    rubik_state_t cubies;

    /* Read in order: a short string fails at its NUL before any later read. */
    for (unsigned i = 0; i < 7; i++) {
        unsigned char c = (unsigned char) state[i];
        if (c < '1' || c > '7')
            return -1;
        unsigned digit = c - '1';
        unsigned bit = 1u << digit;
        if (seen & bit)
            return -1;
        seen |= bit;
        cubies.p[i] = (uint8_t) digit;
    }
    for (unsigned i = 7; i < RUBIK_STATE_LEN; i++) {
        unsigned char c = (unsigned char) state[i];
        if (c < '1' || c > '3')
            return -1;
        unsigned digit = c - '1';
        sum += digit;
        cubies.o[i - 7] = (uint8_t) digit;
    }
    if (state[RUBIK_STATE_LEN] != '\0')
        return -1;

    /* The sum is at most 14; bounded subtraction avoids a divide helper. */
    while (sum >= 3)
        sum -= 3;
    if (sum != 0)
        return -1;

    /* Every valid result needs a NUL; validation must precede this error. */
    if (cap == 0)
        return -2;

    rubik_coordinates_t coordinates = rank_coordinates(&cubies);
    uint8_t path[RUBIK_MAX_DEPTH];
    int length = ida_search(coordinates.p, coordinates.q, path);
    if (length == RUBIK_NOT_FOUND)
        return -1; /* Unreachable for valid states: the HTM diameter is 11. */

    /* Count the complete output before writing any of its tokens. */
    size_t needed = 1;
    for (int i = 0; i < length; i++) {
        if (i != 0)
            needed++;
        needed += 1 + (move_tokens[path[i]][1] != '\0');
    }
    if (cap < needed) {
        out[0] = '\0';
        return -2;
    }

    size_t position = 0;
    for (int i = 0; i < length; i++) {
        if (i != 0)
            out[position++] = ' ';
        const char *token = move_tokens[path[i]];
        out[position++] = token[0];
        if (token[1] != '\0')
            out[position++] = token[1];
    }
    out[position] = '\0';
    return length;
}
