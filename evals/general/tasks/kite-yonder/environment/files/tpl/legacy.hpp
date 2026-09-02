// Toppled Light Constant-Time series -- LEGACY reference header.
//
// This snapshot of the header uses relaxed-constexpr loop constructs that
// are only legal from C++14 onward, so it does NOT compile under strict
// C++11 (the shipped project's toolchain is g++ -std=c++11). Your job is to
// produce a fixed header /app/tpl/series.hpp (same public signature) that
// compiles under -std=c++11 while preserving the constexpr behaviour and the
// exact numeric recurrence defined below. See /app/tpl/notes.md.
#ifndef MSTR_SERIES_BROKEN_HPP
#define MSTR_SERIES_BROKEN_HPP

namespace mstr {

// recurrence:  S_0(x) = 0,  S_k(x) = x * S_{k-1}(x) + k   (k = 1..N)
// value:       mstr::series<N,T>(x)
template <int N, typename T>
constexpr T series(T x){
    T acc = T(0);
    for(int k = 1; k <= N; ++k) acc = acc * x + T(k);   // loop: C++17 constexpr only
    return acc;
}

} // namespace mstr

#endif