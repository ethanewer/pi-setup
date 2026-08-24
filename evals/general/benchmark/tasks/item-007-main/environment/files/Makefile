CXX ?= g++
CXXFLAGS = -std=c++17 -O2 -I src
all: train
train: src/main.cpp src/tiny_proto.cpp src/tiny_blas.cpp src/tiny_proto.h src/tiny_blas.h
	$(CXX) $(CXXFLAGS) src/main.cpp src/tiny_proto.cpp src/tiny_blas.cpp -o train
clean:
	rm -f train run/train.log
