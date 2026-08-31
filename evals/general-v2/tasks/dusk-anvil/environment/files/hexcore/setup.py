from setuptools import setup, Extension
from Cython.Build import cythonize
import numpy

setup(
    name="hexcore",
    version="0.2.0",
    packages=["hexcore"],
    ext_modules=cythonize(
        [
            Extension(
                "hexcore._engine",
                sources=["hexcore/_engine.pyx", "hexcore/_arrays.c"],
                include_dirs=[numpy.get_include()],
                define_macros=[("NPY_NO_DEPRECATED_API", "NPY_1_7_API_VERSION")],
            )
        ],
        language_level=3,
    ),
)
