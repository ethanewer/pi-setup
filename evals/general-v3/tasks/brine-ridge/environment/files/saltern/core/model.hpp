#pragma once
#include <functional>
#include <string>
#include <vector>

#include "data.hpp"

namespace saltern {

struct Model {
    double w1 = 0.0;
    double w2 = 0.0;
    double b = 0.0;
};

double sigmoid(double z);

// Probabilities p_i = sigmoid(w1*x1 + w2*x2 + b) for every sample, in order.
std::vector<double> predict(const Model& m, const Dataset& ds);

// Mean binary cross-entropy with probabilities clamped to [1e-12, 1-1e-12].
double bce_loss(const Model& m, const Dataset& ds);

// Full-batch gradient descent. After each update the new mean BCE loss is
// reported via on_epoch(epoch_index, loss) (epoch_index is 1-based).
// Training order is deterministic: one weight update per epoch using the
// summed gradients over the whole dataset in file order.
void train(Model& m, const Dataset& ds, int epochs, double lr,
           const std::function<void(int, double)>& on_epoch);

}
