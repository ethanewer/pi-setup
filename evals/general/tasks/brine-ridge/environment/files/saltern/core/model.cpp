#include "model.hpp"

#include <cmath>
#include <functional>

namespace saltern {

double sigmoid(double z) {
    return 1.0 / (1.0 + std::exp(-z));
}

std::vector<double> predict(const Model& m, const Dataset& ds) {
    std::vector<double> out;
    out.reserve(ds.size());
    for (const Sample& s : ds) {
        out.push_back(sigmoid(m.w1 * s.x1 + m.w2 * s.x2 + m.b));
    }
    return out;
}

double bce_loss(const Model& m, const Dataset& ds) {
    const double n = static_cast<double>(ds.size());
    double acc = 0.0;
    for (const Sample& s : ds) {
        double p = sigmoid(m.w1 * s.x1 + m.w2 * s.x2 + m.b);
        if (p < 1e-12) p = 1e-12;
        if (p > 1.0 - 1e-12) p = 1.0 - 1e-12;
        const double y = s.y;
        acc += -(y * std::log(p) + (1.0 - y) * std::log(1.0 - p));
    }
    return acc / n;
}

void train(Model& m, const Dataset& ds, int epochs, double lr,
           const std::function<void(int, double)>& on_epoch) {
    const double n = static_cast<double>(ds.size());
    for (int t = 1; t <= epochs; ++t) {
        // gradients at the current weights (full batch, file order)
        double g1 = 0.0, g2 = 0.0, gb = 0.0;
        for (const Sample& s : ds) {
            const double p = sigmoid(m.w1 * s.x1 + m.w2 * s.x2 + m.b);
            const double e = p - s.y;
            g1 += e * s.x1;
            g2 += e * s.x2;
            gb += e;
        }
        g1 /= n; g2 /= n; gb /= n;
        m.w1 -= lr * g1;
        m.w2 -= lr * g2;
        m.b  -= lr * gb;
        if (on_epoch) on_epoch(t, bce_loss(m, ds));
    }
}

}
