#!/usr/bin/env bash
set -euo pipefail

cat > /app/treewalk.cpp <<'CPP_END'
#include <filesystem>
#include <iostream>
#include <cstdint>

namespace fs = std::filesystem;

int main(int argc, char** argv) {
    fs::path root = argc > 1 ? fs::path(argv[1]) : fs::path("/app/data");
    std::uintmax_t total = 0;
    for (const auto& entry : fs::recursive_directory_iterator(root)) {
        if (entry.is_regular_file()) {
            total += entry.file_size();
            std::cout << entry.path().filename().string() << ":" << entry.file_size() << "\n";
        }
    }
    std::cout << "total=" << total << "\n";
    return 0;
}
CPP_END

g++ -std=c++17 -O2 -o /app/treewalk /app/treewalk.cpp
/app/treewalk /app/data | tail -1 | grep -q '^total=14$'