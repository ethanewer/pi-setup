from numpy.distutils.core import setup
from numpy.distutils.extension import Extension

ext = Extension(
    name="grainflow",
    sources=["grainflow.pyx"],
    include_dirs=[__import__("numpy").get_include()],
    define_macros=[("NPY_NO_DEPRECATED_API", "NPY_1_7_API_VERSION")],
)

setup(
    name="grainflow",
    version="0.4.0",
    description="Larch DSP kit kernels",
    ext_modules=[ext],
)
