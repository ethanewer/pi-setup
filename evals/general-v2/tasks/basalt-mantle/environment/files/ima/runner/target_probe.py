#!/usr/bin/env python3
"""Benign reference script for the profiler runner (pure python loop)."""
import math


def main():
    total = 0.0
    for i in range(200):
        total += math.sqrt(i + math.sin(i * 0.5))
    return total


if __name__ == '__main__':
    print(round(main(), 3))