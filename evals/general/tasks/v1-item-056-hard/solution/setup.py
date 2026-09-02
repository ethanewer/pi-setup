from setuptools import setup, Extension

setup(
    name="fastport",
    version="1.0.0",
    description="native C extension for portfolio risk/return",
    ext_modules=[
        Extension("fastport", sources=["fast_port.c"])
    ],
)