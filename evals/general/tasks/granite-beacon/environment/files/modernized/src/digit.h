#ifndef CHORON_DIGIT_H
#define CHORON_DIGIT_H

#include <string>

// Trim whitespace from both ends of `s`.
std::string trim(const std::string &s);

// Sum the decimal digits of the value that starts `v`: skip leading
// whitespace and an optional '-', then sum the maximal run of digits.
// Returns -1 when no digit is present.
int digit_sum(const std::string &v);

#endif // CHORON_DIGIT_H