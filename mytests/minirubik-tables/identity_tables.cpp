// Table-only extraction of the verified A6d identity-PDB study.
// All checks are unconditional: -DNDEBUG does not remove generation or checks.
#include <algorithm>
#include <array>
#include <cstdint>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <numeric>
#include <stdexcept>
#include <string>
#include <vector>

namespace
{
constexpr int NP = 5040, NQ = 729, PAIRS = 42, NI = PAIRS * NQ;
using Seven = std::array<int, 7>;
using Moves = std::array<int, 9>;
// A6d source-position -> destination-position cycles and source-position
// twists.
constexpr std::array<Seven, 3> dest{{{{3, 0, 2, 4, 1, 5, 6}},
                                     {{0, 1, 2, 6, 3, 4, 5}},
                                     {{0, 4, 1, 3, 5, 2, 6}}}};
constexpr std::array<Seven, 3> twist{{{{2, 1, 0, 1, 2, 0, 0}},
                                      {{0, 0, 0, 2, 1, 2, 1}},
                                      {{0, 0, 0, 0, 0, 0, 0}}}};

void require(bool condition, const std::string &message)
{
    if (!condition)
        throw std::runtime_error(message);
}

void turn(Seven &p, Seven &o, int face)
{
    const Seven pp = p, oo = o;
    for (int i = 0; i < 7; ++i) {
        p[dest[face][i]] = pp[i];
        o[dest[face][i]] = (oo[i] + twist[face][i]) % 3;
    }
}

int prank(const Seven &p)
{
    int rank = 0;
    for (int i = 0; i < 7; ++i) {
        rank *= 7 - i;
        rank += static_cast<int>(
            std::count_if(p.begin() + i + 1, p.end(),
                          [&](int value) { return value < p[i]; }));
    }
    return rank;
}

int qrank(const Seven &o)
{
    return std::accumulate(
        o.begin(), o.begin() + 6, 0,
        [](int rank, int value) { return rank * 3 + value; });
}

Seven qunrank(int q)
{
    Seven o{};
    int sum = 0;
    for (int i = 5; i >= 0; --i) {
        o[i] = q % 3;
        q /= 3;
        sum += o[i];
    }
    o[6] = (3 - sum % 3) % 3;
    return o;
}

int enc(int x, int y)
{
    require(x != y, "ordered positions must differ");
    return x * 6 + y - (y > x);
}

void write_new(const std::filesystem::path &path,
               const std::vector<std::uint8_t> &bytes)
{
    require(
        !std::filesystem::exists(path) &&
            !std::filesystem::is_symlink(std::filesystem::symlink_status(path)),
        "refusing to overwrite " + path.string());
    std::ofstream file(path, std::ios::binary);
    require(file.is_open(), "cannot create " + path.string());
    file.write(reinterpret_cast<const char *>(bytes.data()),
               static_cast<std::streamsize>(bytes.size()));
    file.close();
    require(!file.fail(), "write failed: " + path.string());
}

void generate(const std::filesystem::path &out)
{
    require(std::filesystem::is_directory(out), "output directory must exist");
    std::vector<Seven> permutations;
    Seven p{0, 1, 2, 3, 4, 5, 6};
    do {
        require(prank(p) == static_cast<int>(permutations.size()),
                "P ordering");
        permutations.push_back(p);
    } while (std::next_permutation(p.begin(), p.end()));
    require(permutations.size() == NP, "P count");

    std::vector<Moves> pt(NP), qt(NQ), at(PAIRS);
    for (int i = 0; i < NP; ++i)
        for (int f = 0; f < 3; ++f) {
            Seven pp = permutations[i], o{};
            for (int k = 0; k < 3; ++k) {
                turn(pp, o, f);
                pt[i][f * 3 + k] = prank(pp);
            }
        }
    for (int q = 0; q < NQ; ++q)
        for (int f = 0; f < 3; ++f) {
            Seven pp{0, 1, 2, 3, 4, 5, 6}, o = qunrank(q);
            for (int k = 0; k < 3; ++k) {
                turn(pp, o, f);
                qt[q][f * 3 + k] = qrank(o);
            }
        }
    for (int c = 0; c < PAIRS; ++c) {
        const int x = c / 6, y = c % 6 + (c % 6 >= x);
        require(enc(x, y) == c, "ordered-position decoding");
        for (int f = 0; f < 3; ++f) {
            int xx = x, yy = y;
            for (int k = 0; k < 3; ++k) {
                xx = dest[f][xx];
                yy = dest[f][yy];
                at[c][f * 3 + k] = enc(xx, yy);
            }
        }
    }
    // Selected identities 1 and 4 are zero-based cubies 0 and 3.
    std::vector<std::uint8_t> projection(NP);
    for (int i = 0; i < NP; ++i) {
        const int x = static_cast<int>(
            std::find(permutations[i].begin(), permutations[i].end(), 0) -
            permutations[i].begin());
        const int y = static_cast<int>(
            std::find(permutations[i].begin(), permutations[i].end(), 3) -
            permutations[i].begin());
        projection[i] = static_cast<std::uint8_t>(enc(x, y));
    }
    for (int i = 0; i < NP; ++i)
        for (int m = 0; m < 9; ++m)
            require(projection[pt[i][m]] == at[projection[i]][m],
                    "projection transition");

    std::vector<std::uint8_t> distance(NI, 255);
    std::vector<int> queue(NI);
    int tail = 1;
    const int goal = enc(0, 3) * NQ;
    queue[0] = goal;
    distance[goal] = 0;
    for (int head = 0; head < tail; ++head) {
        const int v = queue[head], c = v / NQ, q = v % NQ;
        for (int m = 0; m < 9; ++m) {
            const int w = at[c][m] * NQ + qt[q][m];
            if (distance[w] == 255) {
                require(tail < NI, "BFS queue overflow");
                distance[w] = static_cast<std::uint8_t>(distance[v] + 1);
                queue[tail++] = w;
            }
        }
    }
    require(
        tail == NI && *std::max_element(distance.begin(), distance.end()) == 8,
        "identity BFS reachability/distance bound");
    for (int v = 0; v < NI; ++v) {
        bool descent = v == goal;
        for (int m = 0; m < 9; ++m) {
            const int w = at[v / NQ][m] * NQ + qt[v % NQ][m];
            const int delta = static_cast<int>(distance[v]) - distance[w];
            require(delta >= -1 && delta <= 1, "distance edge consistency");
            descent = descent || delta == 1;
        }
        require(descent && distance[v] < 15, "distance descent/nibble bound");
    }
    std::vector<std::uint8_t> packed(NI / 2), rows;
    rows.reserve(NP * 2);
    for (int i = 0; i < NI; ++i)
        packed[i / 2] |=
            static_cast<std::uint8_t>(distance[i] << (4 * (i % 2)));
    for (const auto c : projection) {
        const unsigned row = static_cast<unsigned>(c) * NQ;
        require(row <= 29889, "row offset range");
        rows.push_back(static_cast<std::uint8_t>(row & 255U));
        rows.push_back(static_cast<std::uint8_t>(row >> 8));
    }
    write_new(out / "identity_rows.le16.bin", rows);
    write_new(out / "identity_distance.packed.bin", packed);
    std::cout << "PASS identity_states=" << tail << " projection_entries=" << NP
              << " maximum_distance=8\n";
}
}  // namespace

int main(int argc, char **argv)
{
    try {
        require(argc == 3 && std::string(argv[1]) == "--out",
                "usage: identity_tables --out OUTPUT_DIRECTORY");
        generate(argv[2]);
        return 0;
    } catch (const std::exception &error) {
        std::cerr << "identity_tables: " << error.what() << '\n';
        return 1;
    }
}
