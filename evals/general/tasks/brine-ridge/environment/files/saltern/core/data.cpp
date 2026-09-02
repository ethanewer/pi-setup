#include "data.hpp"

#include <cstdlib>
#include <cstdio>

namespace saltern {

Dataset load_csv(const std::string& path) {
    FILE* f = std::fopen(path.c_str(), "r");
    if (f == nullptr) {
        std::fprintf(stderr, "saltern: cannot open dataset %s\n", path.c_str());
        std::exit(2);
    }
    Dataset ds;
    char line[256];
    while (std::fgets(line, sizeof line, f) != nullptr) {
        std::string s(line);
        // strip trailing newline/CR
        while (!s.empty() && (s.back() == '\n' || s.back() == '\r')) s.pop_back();
        if (s.empty()) continue;
        if (s[0] == '#') continue;
        char* end = nullptr;
        const double x1 = std::strtod(s.c_str(), &end);
        if (end == s.c_str() || *end != ',') continue;
        const char* p = end + 1;
        const double x2 = std::strtod(p, &end);
        if (end == p || *end != ',') continue;
        p = end + 1;
        const long y = std::strtol(p, &end, 10);
        if (end == p) continue;
        ds.push_back(Sample{x1, x2, static_cast<double>(y)});
    }
    std::fclose(f);
    if (ds.empty()) {
        std::fprintf(stderr, "saltern: dataset %s loaded no samples\n", path.c_str());
        std::exit(2);
    }
    return ds;
}

}
