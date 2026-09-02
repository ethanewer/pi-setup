#!/usr/bin/env python3
"""Reference MNIST-style classifier for the benchmark model.

Usage:  python3 reference.py <image.raw>

Reads a 784-byte raw grayscale image (28x28, values 0-255), runs the exact
model and prints the predicted digit (0-9) on stdout.
"""
import json
import os
import sys


def load_model():
    if os.path.exists("/app/model_pytorch.json"):
        d = json.load(open("/app/model_pytorch.json"))
        W1 = d["fc1.weight"]  # [32][784] (out,in), PyTorch convention
        B1 = d["fc1.bias"]
        W2 = d["fc2.weight"]  # [10][32]  (out,in)
        B2 = d["fc2.bias"]

        def w1(i, k):
            return W1[i][k]

        def w2(j, i):
            return W2[j][i]
    else:
        d = json.load(open("/app/model.json"))
        W1 = d["w1"]  # [784][32]
        B1 = d["b1"]
        W2 = d["w2"]  # [32][10]
        B2 = d["b2"]

        def w1(i, k):
            return W1[k][i]

        def w2(j, i):
            return W2[i][j]
    return B1, B2, w1, w2


def predict(img):
    B1, B2, w1, w2 = load_model()
    x = [v / 255.0 for v in img]
    H = len(B1)
    h = [max(sum(x[k] * w1(i, k) for k in range(784)) + B1[i], 0.0) for i in range(H)]
    y = [sum(h[i] * w2(j, i) for i in range(H)) + B2[j] for j in range(10)]
    return y.index(max(y))


def main():
    data = open(sys.argv[1], "rb").read()[:784]
    print(predict(data))


if __name__ == "__main__":
    main()