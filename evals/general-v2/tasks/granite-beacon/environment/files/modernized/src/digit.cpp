#include "digit.h"
#include <cctype>
#include <string>

std::string trim(const std::string &s) {
    const std::string w = " \t\r\n";
    std::string::size_type a = s.find_first_not_of(w);
    if (a == std::string::npos) return std::string();
    std::string::size_type b = s.find_last_not_of(w);
    return s.substr(a, b - a + 1);
}

int digit_sum(const std::string &v) {
    std::string::size_type i = 0;
    while (i < v.size() && std::isspace(static_cast<unsigned char>(v[i]))) ++i;
    if (i < v.size() && v[i] == '-') ++i;
    int sum = 0;
    bool any = false;
    while (i < v.size() && std::isdigit(static_cast<unsigned char>(v[i]))) {
        sum += v[i] - '0';
        any = true;
        ++i;
    }
    return any ? sum : -1;
}