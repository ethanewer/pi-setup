#!/usr/bin/env python3
"""Apply the minimal upstream fix to psutil.process_iter().

Upstream issue #2793: process_iter() wraps the per-process attribute prefetch
in `except NoSuchProcess: remove(pid)`. A process in the zombie state is
reported through ZombieProcess, which subclasses NoSuchProcess, so the
generic handler swallowed the zombie too: it was dropped from the internal
cache and never yielded, even though the process still exists and remains
queryable through psutil.Process(pid). The fix adds an explicit branch for
the zombie-process condition ahead of the generic one so the iterator yields
the zombie instead of forgetting it.
"""
from __future__ import annotations

import sys

OLD = """            except NoSuchProcess:
                remove(pid)"""

NEW = """            except ZombieProcess:
                if proc is not None:
                    yield proc  # zombie processes are still valid
            except NoSuchProcess:
                remove(pid)"""


def apply(path: str) -> None:
    with open(path, encoding="utf-8") as f:
        src = f.read()
    if NEW in src:
        print(f"{path}: fix already present")
        return
    assert OLD in src, "unexpected process_iter() structure in the tree"
    src = src.replace(OLD, NEW, 1)
    with open(path, "w", encoding="utf-8") as f:
        f.write(src)
    print(f"{path}: fix applied")


if __name__ == "__main__":
    apply(sys.argv[1])