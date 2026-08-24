# Legacy Cython build written for numpy 1.x / setuptools 40.
from numpy.distutils.core import setup, Extension

exts = [
    Extension("legacy_vec._core", ["legacy_vec/_core.pyx"],
              include_dirs=[], extra_compile_args=["-O2"]),
    Extension("legacy_vec._filters", ["legacy_vec/_filters.pyx"],
              include_dirs=[], extra_compile_args=["-O2"]),
]
setup(name="legacy_vec", version="1.0.0", packages=["legacy_vec"], ext_modules=exts)