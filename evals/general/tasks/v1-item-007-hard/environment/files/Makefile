CXX ?= g++
CXXFLAGS = -std=c++17 -O2 -I src

# ---- Caffe-style multi-stage dependency build ----
# Like building protobuf/BLAS/OpenCV before the trainer itself, the support
# units below are each compiled separately into objects, then the trainer is
# linked against the compiled dependencies (a long, several-unit build).
all: train

# stage 1: compile the support dependencies into object files
objs: src/tiny_proto.cpp src/tiny_blas.cpp src/imgproc.cpp \
      src/tiny_proto.h src/tiny_blas.h src/imgproc.h
	$(CXX) $(CXXFLAGS) -c src/tiny_proto.cpp -o tiny_proto.o
	$(CXX) $(CXXFLAGS) -c src/tiny_blas.cpp -o tiny_blas.o
	$(CXX) $(CXXFLAGS) -c src/imgproc.cpp -o imgproc.o

# stage 2: link the trainer against the compiled dependencies
train: objs src/main.cpp src/tiny_proto.h src/tiny_blas.h src/imgproc.h
	$(CXX) $(CXXFLAGS) src/main.cpp tiny_proto.o tiny_blas.o imgproc.o -o train

clean:
	rm -f train tiny_proto.o tiny_blas.o imgproc.o run/train.log