# Legacy Cython extension build (written circa 2016 - numpy 1.x / setuptools 40).
# This build path was obsoleted by modern numpy (& setuptools).
from numpy.distutils.core import setup, Extension

setup(
    name="legacy_vec",
    version="1.0.0",
    packages=["legacy_vec"],
    ext_modules=[
        Extension("legacy_vec._core",
                  ["legacy_vec/_core.pyx"],
                  include_dirs=[],
                  extra_compile_args=["-O2"])
    ],
)