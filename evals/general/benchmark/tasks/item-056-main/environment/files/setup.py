from setuptools import setup, Extension

setup(
    name="native",
    version="1.0",
    description="fast portfolio risk/return (item-56)",
    ext_modules=[
        Extension("native", ["native.c"]),
    ],
)