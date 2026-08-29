"""Async filesystem test.

These tests import the *installed* `gale` package.  They only pass when:
  1. `gale` has been pip-installed in editable mode (`pip install -e /app/proj`),
     so the distribution metadata and the async entry point `gale.io.slurp_tree`
     are visible; and
  2. `gale.io.slurp_tree` has actually been implemented to read the whole tree.
"""
import asyncio
import importlib.metadata
import os
import tempfile


def test_gale_installed():
    dist = importlib.metadata.distribution("gale")
    assert dist.metadata["Name"].lower() == "gale"


def test_slurp_async_tree_from_installed_package():
    from gale.io import slurp_tree

    files = {
        "a.txt": "hello\n",
        "meta_b.txt": "world\n",
        "sub/c.txt": "deep\n",
    }
    with tempfile.TemporaryDirectory() as d:
        os.makedirs(os.path.join(d, "sub"))
        for rel, txt in files.items():
            with open(os.path.join(d, rel), "w") as fh:
                fh.write(txt)
        out = asyncio.run(slurp_tree(d))
    assert set(out) == set(files)
    for rel, txt in files.items():
        assert out[rel] == txt


def test_slurp_empty_tree():
    from gale.io import slurp_tree

    with tempfile.TemporaryDirectory() as d:
        out = asyncio.run(slurp_tree(d))
    assert out == {}