#!/usr/bin/env python3
"""Build the fastport C extension in place so `import fastport` works."""
import os, sys
os.chdir(os.path.dirname(os.path.abspath(__file__)))
sys.argv = ["setup.py", "build_ext", "--inplace"]
try:
    from setuptools import setup  # noqa: ensures setuptools imported
except Exception:
    pass
exec(open("setup.py").read())