#pragma once
// BLAS-like helpers (CPU training).
// In-place stable softmax over an array of length n; returns max-before-exp.
double softmax_clip(double* v, int n);