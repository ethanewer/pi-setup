# Delivered LEGACY build helper for the `hailshot` package.
#
# This employs the long-removed `numpy.distutils` entry point, which does not
# exist in the numpy 2.x that the default interpreter has installed.  Building
# with this helper therefore fails on the default interpreter.  You must port
# the build to a modern `setuptools` + `Cython.Build.cythonize` configuration
# and then install the edited tree so `import hailshot` works.
from numpy.distutils.core import setup, Extension

setup(
    name="hailshot",
    version="0.0.2-pre",
    packages=["hailshot"],
    ext_modules=[
        Extension("hailshot._native", sources=["hailshot/_native.pyx"]),
    ],
)