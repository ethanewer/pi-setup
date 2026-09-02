#pragma once
#include <string>
#include <vector>

namespace saltern {

struct Sample {
    double x1;
    double x2;
    double y;
};

using Dataset = std::vector<Sample>;

// Loads a plain CSV of lines "x1,x2,y" (double,double,int).
// Blank lines and lines starting with '#' are skipped.
Dataset load_csv(const std::string& path);

}
