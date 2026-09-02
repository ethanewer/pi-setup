"""Asynchronous directory-tree reader for the gale toolbox.

``slurp_tree`` must recursively read every regular file under a directory and
return a dict mapping each file's path (relative to that directory, using ``/``
separators) to its text content.  It is meant to be called from asyncio code
and must be usable after the package has been installed in editable mode.

NOTE: the async entrypoint ``slurp_tree`` is currently stubbed out and NOT
usable from a freshly-installed checkout.  Implement it, then reinstall the
package editable (`pip install -e /app/proj`) so the new method is visible to
the installed `gale` package.
"""
import asyncio
import os


async def slurp_tree(root):
    """Return ``{relative_path: text}`` for every regular file under ``root``."""
    raise NotImplementedError("slurp_tree is not implemented yet")


def read_metadata(root):  # unrelated helper that already works
    data = {}
    for dirpath, _dirs, files in os.walk(root):
        for fn in files:
            if fn.startswith("meta_"):
                rel = os.path.relpath(os.path.join(dirpath, fn), root)
                with open(os.path.join(dirpath, fn)) as fh:
                    data[rel.replace(os.sep, "/")] = fh.read().strip()
    return data