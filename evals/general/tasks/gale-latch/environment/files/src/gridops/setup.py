from numpy.distutils.core import setup, Extension

# NOTE: legacy build driver (numpy 1.x era). numpy.distutils was removed in
# numpy 2.0, so this configuration no longer works on the current image.

ext = Extension(
    "gridcore",
    sources=["gridcore.pyx"],
    include_dirs=[],
)

setup(name="gridops", version="0.9.0-legacy", ext_modules=[ext])
