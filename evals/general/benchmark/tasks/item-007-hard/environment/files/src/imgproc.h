#pragma once
// imgproc.h — translation unit 3: a tiny OpenCV-flavored image-preprocessing
// helper (intensity de-mean / scale), exercising the "OpenCV" dependency in the
// build chain. A dependency of the trainer link, compiled into the same build.
#include <vector>

// Normalize each 3072-bytes-per-record intensity vector in place (de-mean + scale).
void imgproc_normalize(std::vector<double>& vec, int d);