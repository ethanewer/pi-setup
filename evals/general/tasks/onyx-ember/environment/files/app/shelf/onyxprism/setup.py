import os
from setuptools import setup, find_packages
from Cython.Build import cythonize

here = os.path.abspath(os.path.dirname(__file__))

setup(
    name="onyxprism",
    version="2.1.0",
    description="Onyx Prism primary-disk digest toolkit",
    packages=find_packages(where=here),
    package_dir={"": here},
    ext_modules=cythonize("onyxprism/_fast.pyx", language_level=3),
    include_dirs=[here],
    zip_safe=False,
)