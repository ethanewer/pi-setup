# NOTE: legacy build helper. This uses the deprecated numpy.distutils entry
# point. Under the installed numpy 2.x it no longer exists, so building via
# this file fails. Port the build to a modern setuptools + Cython.Build.cythonize
# setup (see README.md) and rebuild, so the compiled 'pyros' extension builds
# against the current numpy and imports cleanly.
from numpy.distutils.core import setup, Extension

setup(
    name='pyros',
    version='2.0.0',
    ext_modules=[Extension('pyros', sources=['pyros.pyx'])],
)