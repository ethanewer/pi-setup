#include "tiny_blas.h"
#include <cmath>

double softmax_clip(double* v, int n){
    double m = v[0];
    for(int i=1;i<n;i++) if(v[i] > m) m = v[i];
    double s = 0.0;
    for(int i=0;i<n;i++){ v[i] = std::exp(v[i] - m); s += v[i]; }
    double inv = 1.0 / s;
    for(int i=0;i<n;i++) v[i] *= inv;
    return m;
}