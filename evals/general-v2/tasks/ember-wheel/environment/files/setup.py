from setuptools import setup, Extension

setup(
    name='snapvec',
    version='0.4.0',
    ext_modules=[Extension('snapvec', ['native.c'])],
)