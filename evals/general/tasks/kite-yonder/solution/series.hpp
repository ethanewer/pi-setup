/* Fixed /app/tpl/series.hpp: compiles under C++11 as constexpr and agrees
 * with the recurrence documented in /app/tpl/notes.md. */
#pragma once
namespace mstr {
template <int N> struct Series {
    template <typename T> static constexpr T value(T x) {
        return x * Series<N - 1>::value(x) + T(N);
    }
};
template <> struct Series<0> {
    template <typename T> static constexpr T value(T x) { return T(0); }
};
template <int N, typename T> constexpr T series(T x) {
    return Series<N>::value(x);
}
} // namespace mstr