#!/usr/bin/env python3
"""Gale-Jetty parallel wrapper: reuse the sequential iteration constant.

The extraction engine must obtain ITERATIONS from the companion sequential
module through this module (import), never restate the number inline.
"""
from compute_seq import ITERATIONS

__all__ = ["ITERATIONS"]
