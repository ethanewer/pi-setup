#pragma once
/*
 * flint numeric pack-sum utility — C++11-correct port.
 *
 * Public contract: for any pack of unsigned ints Size, `Sum<Size...>::value`
 * is an integer constant expression equal to the arithmetic sum of the pack
 * elements (Sum<>::value == 0). Compiled strictly under C++11 without any
 * post-C++11 construct (no relaxed-constexpr function bodies, no loops, no
 * local mutation in a constexpr context): the sum is formed by recursive
 * pack expansion, which is valid C++11 and keeps `value` constexpr-usable.
 */
#include <cstddef>

template<unsigned... V>
struct Sum;

template<>
struct Sum<> {
    static constexpr unsigned value = 0;
};

template<unsigned H, unsigned... V>
struct Sum<H, V...> {
    static constexpr unsigned value = H + Sum<V...>::value;
};
