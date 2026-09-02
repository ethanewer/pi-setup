// flint C++11 constexpr Sum verifier.
// Compiled against the agent's /app/math/Sum.hpp strictly under C++11.
// Any post-C++11 construct (relaxed-constexpr function body, loop, mutation)
// or a wrong non-constant `value` fails to compile.
#include "/app/math/Sum.hpp"

// correctness of the arithmetic sum across many packs
static_assert(Sum<1, 2, 3>::value == 6, "basic");
static_assert(Sum<>::value == 0, "empty");
static_assert(Sum<9>::value == 9, "single");
static_assert(Sum<7, 7, 7, 7>::value == 28, "repeat");
static_assert(Sum<0, 0, 0, 0, 0, 0, 0, 0, 0>::value == 0, "zeros");
static_assert(Sum<10, 20, 30, 40, 50>::value == 150, "asc");
static_assert(Sum<5, 1, 9, 4, 6, 7, 3>::value == 35, "mixed");
static_assert(Sum<255>::value == 255, "one big");
static_assert(Sum<100, 200, 300, 400, 500, 600>::value == 2100, "six");
static_assert(Sum<1, 1, 1, 1, 1, 1, 1, 1, 1, 1>::value == 10, "ones");
static_assert(Sum<40, 2>::value == 42, "answer");
static_assert(Sum<123, 456, 789>::value == 1368, "larger");

// value must be a usable constant expression, not just a function
static const unsigned arr[Sum<3, 4>::value] = {};              // size 7
static_assert(sizeof(arr) == 7 * sizeof(unsigned), "array size constant");
template<unsigned S, unsigned E> struct RangeCheck {
    static constexpr bool ok = Sum<S, E>::value == (S + E);
};
static_assert(RangeCheck<11, 31>::ok == (11 + 31 == 42), "auth");

int main() { return 0; }