FROM bench-base:python-3.12

WORKDIR /app

RUN mkdir -p /app/model && \
    cat > /app/model/deploy.prototxt <<'PROTO_END'
name: "CaffeNet"
input: "data"
input_shape {
  dim: 1
  dim: 3
  dim: 227
  dim: 227
}
layer {
  name: "conv1"
  type: "Convolution"
  bottom: "data"
  top: "conv1"
  convolution_param {
    num_output: 96
    kernel_size: 11
    stride: 4
  }
}
layer {
  name: "relu1"
  type: "ReLU"
  bottom: "conv1"
  top: "conv1"
}
layer {
  name: "pool1"
  type: "Pooling"
  bottom: "conv1"
  top: "pool1"
  pooling_param {
    pool: MAX
    kernel_size: 3
    stride: 2
  }
}
layer {
  name: "fc8"
  type: "InnerProduct"
  bottom: "pool1"
  top: "fc8"
  inner_product_param {
    num_output: 1000
  }
}
layer {
  name: "prob"
  type: "Softmax"
  bottom: "fc8"
  top: "prob"
}
layer {
  name: "accuracy"
  type: "Accuracy"
  bottom: "prob"
  bottom: "label"
  top: "accuracy"
}
PROTO_END