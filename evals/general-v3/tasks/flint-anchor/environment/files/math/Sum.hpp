#pragma once
/*
 * flint numeric pack-sum utility.
 *
 * Public contract: for any pack of unsigned ints Size, `Sum<Size...>::value`
 * MUST be an integer constant expression (usable in static_asserts, array
 * sizes, template arguments, ...) equal to the arithmetic sum of the pack
 * elements, e.g.  Sum<1,2,3>::value == 6  and  Sum<>::value == 0.
 *
 * The tree MUST compile strictly under C++11 (-std=c++11 -pedantic-errors)
 * while keeping `value` constexpr-usable with the correct sum in every case.
 */
#include <cstddef>

template<unsigned... V>
struct Sum {
    static constexpr unsigned value() {
        unsigned total = 0;
        for (unsigned x : {V...}) {
            total += x;
        }
        return total;
    }
    /* placeholder that must be replaced with a real compile-time sum */
    static constexpr unsigned value = 0;
};
