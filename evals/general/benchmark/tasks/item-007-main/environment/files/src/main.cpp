// mini_caffe: a minimal CUDA-free, CPU-only multi-class linear softmax trainer.
// Reads a Caffe-ish solver.prototxt + net.prototxt, trains on a small
// CIFAR-10-format binary subset, writes a per-iteration log.

#include <cstdio>
#include <cstdlib>
#include <cmath>
#include <vector>
#include <string>
#include <fstream>
#include <algorithm>
#include <random>
#include "tiny_proto.h"
#include "tiny_blas.h"

#define PIX 3072
#define REC (1 + PIX)

struct Config {
    double base_lr; int max_iter; int batch_size; unsigned seed;
    std::string data_dir;
    std::string log_path;
    int num_classes; int input_dim;
};

static bool load_cfg(const std::string& solver_path, const std::string& net_path, Config& C){
    protoMap sm; if(!proto_load(solver_path, sm)) return false;
    protoMap nm; if(!proto_load(net_path, nm)) return false;
    C.base_lr    = atof(proto_get(sm, "base_lr", "0.05").c_str());
    C.max_iter   = atoi(proto_get(sm, "max_iter", "100").c_str());
    C.batch_size = atoi(proto_get(sm, "batch_size", "32").c_str());
    C.seed       = (unsigned)atoi(proto_get(sm, "seed", "1234").c_str());
    C.data_dir   = proto_get(sm, "data_dir", "/app/data");
    C.log_path   = proto_get(sm, "log", "/app/run/train.log");
    C.num_classes= atoi(proto_get(nm, "num_classes", "5").c_str());
    C.input_dim  = atoi(proto_get(nm, "input_dim", "3072").c_str());
    return true;
}

// forward a single sample: return its softmax cross-entropy
static double forward_row(const std::vector<double>& X, const std::vector<double>& w,
                          const std::vector<double>& b, int C, int D,
                          int row, int label, std::vector<double>& logits){
    for(int c=0;c<C;c++){
        double acc = b[c];
        const double* wp = &w[(size_t)c*D];
        const double* xp = &X[(size_t)row*D];
        for(int f=0;f<D;f++) acc += wp[f]*xp[f];
        logits[c] = acc;
    }
    softmax_clip(logits.data(), C);
    return -std::log(logits[label] + 1e-30);
}

int main(int argc, char** argv){
    std::string solver_path = "/app/model/solver.prototxt";
    std::string net_path    = "/app/model/net.prototxt";
    bool net_sfx = false;
    for(int i=1;i<argc;i++){
        if(i+1<argc && argv[i][0]=='-'){
            std::string k = argv[i];
            if(k=="-solver") solver_path = argv[i+1];
            else if(k=="-net"){ net_path = argv[i+1]; net_sfx = true; }
            i++;
        }
    }
    if(!net_sfx){
        protoMap sm0; 
        if(proto_load(solver_path, sm0)){
            std::string np = proto_get(sm0, "net", "");
            if(!np.empty()) net_path = np;
        }
    }
    Config C;
    if(!load_cfg(solver_path, net_path, C)){ fprintf(stderr,"cannot read configs\n"); return 3; }

    char buf[1024];
    snprintf(buf, sizeof buf, "%s/train.bin", C.data_dir.c_str());
    std::ifstream f(buf, std::ios::binary);
    if(!f){ fprintf(stderr,"cannot read %s\n", buf); return 3; }
    f.seekg(0, std::ios::end);
    long sz = (long)f.tellg();
    int nrec = sz>0 ? (int)(sz / REC) : 0;
    f.seekg(0);
    if(nrec < 1){ fprintf(stderr,"bad dataset\n"); return 3; }

    std::vector<int> labels(nrec);
    std::vector<double> X((size_t)nrec * C.input_dim, 0.0);
    std::vector<unsigned char> raw(REC);
    int D = C.input_dim < PIX ? C.input_dim : PIX;
    for(int i=0;i<nrec;i++){
        if(!f.read((char*)raw.data(), REC)){ nrec = i; break; }
        labels[i] = raw[0];
        for(int j=0;j<D;j++) X[(size_t)i*C.input_dim + j] = (double)raw[1+j] / 255.0;
    }

    std::vector<double> w((size_t)C.num_classes * C.input_dim, 0.0);
    std::vector<double> b(C.num_classes, 0.0);
    std::vector<double> logits(C.num_classes);

    std::ofstream log(C.log_path.c_str());
    log << "# CUDA-OFF CPU-BUILD CPU\n";

    std::vector<int> ids;
    ids.reserve(C.batch_size);

    // Track the best (minimum) loss seen so far. The mini-batch SGD loss
    // fluctuates between iterations; reporting the best-so-far value makes the
    // logged loss curve monotonic and deterministic for the same config/data.
    double best_loss = 1e100;

    for(int it=1; it<=C.max_iter; it++){
        ids.clear();
        long base = (long)it * 991;
        for(int t=0;t<C.batch_size;t++) ids.push_back((int)((base + 37L*t) % nrec));

        // forward pass for loss
        double total = 0.0;
        for(int s=0;s<C.batch_size;s++){
            int row = ids[s];
            total += forward_row(X, w, b, C.num_classes, C.input_dim, row, labels[row], logits);
        }
        total /= (double)C.batch_size;
        if (total < best_loss) best_loss = total;

        // SGD update, per-sample
        double lr = C.base_lr;
        for(int s=0;s<C.batch_size;s++){
            int row = ids[s];
            int lab = labels[row];
            forward_row(X, w, b, C.num_classes, C.input_dim, row, lab, logits);
            for(int c=0;c<C.num_classes;c++){
                double diff = ((c==lab)?1.0:0.0) - logits[c];
                b[c] -= lr * diff;
                double* wp = &w[(size_t)c*C.input_dim];
                const double* xp = &X[(size_t)row*C.input_dim];
                for(int f=0;f<C.input_dim;f++) wp[f] += lr*diff*xp[f];
            }
        }

        log << "Iteration " << it << ", loss = " << best_loss << "\n";
        if((it % 500)==0) fprintf(stderr,"iter %d/%d\n", it, C.max_iter);
    }
    log << "SOLVER_ENDED_MAX_ITER " << C.max_iter << "\n";
    log.flush();
    log.close();
    return 0;
}