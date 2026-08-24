#!/usr/bin/env bash
set -euo pipefail

cat > /app/stats.cpp <<'CPP_END'
#include <iostream>
#include <vector>
#include <iomanip>

int main() {
    std::vector<int> nums;
    int v;
    while (std::cin >> v) {
        nums.push_back(v);
    }
    long sum = 0;
    for (int n : nums) {
        sum += n;
    }
    std::cout << "sum=" << sum << "\n";
    std::cout << "count=" << nums.size() << "\n";
    std::cout << "avg=" << std::fixed << std::setprecision(1)
              << (static_cast<double>(sum) / nums.size()) << "\n";
    return 0;
}
CPP_END

g++ -O2 -o /app/stats /app/stats.cpp
/app/stats < /app/data.txt