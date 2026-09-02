import os

from setuptools import Extension, setup

# The C core of swellkit is intentionally small and dependency-free; it is
# compiled by setuptools as part of "pip install /app/src".
setup(
    ext_modules=[
        Extension(
            "swellkit._core",
            sources=[os.path.join("swellkit", "_core.c")],
        )
    ]
)
