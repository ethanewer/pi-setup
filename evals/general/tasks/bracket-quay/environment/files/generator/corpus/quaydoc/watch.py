"""Polling source watcher for live rebuilds.

A real filesystem event watcher would need OS-specific bindings; quaydoc
polls mtimes on a short interval instead, which is dependency-free and works
on every platform the CLI runs on.
"""

from __future__ import annotations

import os
import time

from quaydoc import finder


class Watcher:
    """Watches a documentation root and reports changed source files."""

    def __init__(self, root, config, interval=1.0):
        self.root = root
        self.config = config
        self.interval = interval
        self._mtime = {}

    def snapshot(self):
        mtime = {}
        for full, _ in finder.iter_candidates(self.root, self.config):
            try:
                mtime[full] = os.stat(full).st_mtime
            except OSError:
                continue
        self._mtime = mtime
        return mtime

    def poll_once(self):
        """Return the list of changed paths since the last snapshot."""
        current = self.snapshot()
        changed = []
        missing = set(self._mtime) - set(current)
        changed.extend(missing)
        for path, stamp in current.items():
            if path not in self._mtime or self._mtime[path] != stamp:
                changed.append(path)
        self._mtime = current
        return changed

    def run(self, on_change):
        """Poll forever, calling ``on_change(changed_paths)`` on changes."""
        self.snapshot()
        try:
            while True:
                changed = self.poll_once()
                if changed:
                    on_change(changed)
                time.sleep(self.interval)
        except KeyboardInterrupt:
            pass
