// CPU-only saltern trainer.
//
//   saltern_cpu --data <csv> --epochs <N> --lr <F> --out <model.json>
//
// Trains the logistic model with full-batch gradient descent (deterministic:
// zero-initialized weights, one update per epoch, dataset in file order) and
// writes the final model as JSON. One "epoch=<t> loss=<...>" line per epoch
// goes to stdout.
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>

#include "model.hpp"

namespace {

double arg_double(const char* s, const char* what) {
    char* end = nullptr;
    const double v = std::strtod(s, &end);
    if (end == s || *end != '\0') {
        std::fprintf(stderr, "saltern_cpu: bad %s '%s'\n", what, s);
        std::exit(2);
    }
    return v;
}

long arg_long(const char* s, const char* what) {
    char* end = nullptr;
    const long v = std::strtol(s, &end, 10);
    if (end == s || *end != '\0') {
        std::fprintf(stderr, "saltern_cpu: bad %s '%s'\n", what, s);
        std::exit(2);
    }
    return v;
}

}  // namespace

int main(int argc, char** argv) {
    std::string data_path, out_path;
    long epochs = 200;
    double lr = 0.5;

    for (int i = 1; i < argc; ++i) {
        const std::string a = argv[i];
        if (a == "--data" && i + 1 < argc) data_path = argv[++i];
        else if (a == "--out" && i + 1 < argc) out_path = argv[++i];
        else if (a == "--epochs" && i + 1 < argc) epochs = arg_long(argv[++i], "--epochs");
        else if (a == "--lr" && i + 1 < argc) lr = arg_double(argv[++i], "--lr");
        else {
            std::fprintf(stderr,
                         "usage: saltern_cpu --data <csv> --epochs <N> --lr <F> --out <json>\n");
            return 2;
        }
    }
    if (data_path.empty() || out_path.empty()) {
        std::fprintf(stderr, "saltern_cpu: --data and --out are required\n");
        return 2;
    }

    const saltern::Dataset ds = saltern::load_csv(data_path);
    saltern::Model m;  // zeros
    saltern::train(m, ds, static_cast<int>(epochs), lr,
                   [](int t, double loss) {
                       std::printf("epoch=%d loss=%.6f\n", t, loss);
                   });
    const double final_loss = saltern::bce_loss(m, ds);

    FILE* out = std::fopen(out_path.c_str(), "w");
    if (out == nullptr) {
        std::fprintf(stderr, "saltern_cpu: cannot write %s\n", out_path.c_str());
        return 2;
    }
    std::fprintf(out, "{\n");
    std::fprintf(out, "  \"epochs\": %ld,\n", epochs);
    std::fprintf(out, "  \"lr\": %.6f,\n", lr);
    std::fprintf(out, "  \"w1\": %.6f,\n", m.w1);
    std::fprintf(out, "  \"w2\": %.6f,\n", m.w2);
    std::fprintf(out, "  \"b\": %.6f,\n", m.b);
    std::fprintf(out, "  \"final_loss\": %.6f\n", final_loss);
    std::fprintf(out, "}\n");
    std::fclose(out);
    return 0;
}
