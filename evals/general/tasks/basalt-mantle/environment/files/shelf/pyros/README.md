pyros
=====

A tiny Cython extension that exercises the numeric numpy 2.x build path.

The bundled `setup.py` still uses the legacy `numpy.distutils` entry point,
which was removed in numpy 2.x. To make this buildable you must port it to a
modern setuptools + `Cython.Build.cythonize` configuration, then compile and
install the extension so that

    python3 -c "import pyros; print(pyros.ring(3))"

works with the installed numpy. Keep the compiled artifact such that the
module imports without re-running the build afterwards.