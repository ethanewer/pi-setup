#include "imgproc.h"
#include <cmath>

void imgproc_normalize(std::vector<double>& vec, int d) {
    if (d <= 0) return;
    double mean = 0.0;
    for (int i = 0; i < d; i++) mean += vec[i];
    mean /= (double)d;
    double ss = 0.0;
    for (int i = 0; i < d; i++) {
        vec[i] -= mean;
        ss += vec[i] * vec[i];
    }
    double std = ss > 0 ? std::sqrt(ss / (double)d) : 1.0;
    double inv = std > 0 ? 1.0 / std : 1.0;
    for (int i = 0; i < d; i++) vec[i] *= inv;
}