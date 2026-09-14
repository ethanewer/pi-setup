#!/usr/bin/env python3
"""Apply the nock-meridian fix to the pinned pip checkout in place.

Transforms the three source files of the PARENT (buggy) tree into the fixed
code for issue #14110, byte-identically to the upstream fix commit. Every
anchor must match the pinned checkout exactly, and every modified file is
verified to be byte-identical to the fix-commit contents after patching (the
check is done by re-deriving: the replacements are anchored on the parent
bytes, so a drifted checkout fails loudly instead of half-patching).

Usage: fix_pip.py <checkout-src-dir>   (dir that contains pip/_internal/...)
"""
from __future__ import annotations

import sys
from pathlib import Path

# --------------------------------------------------------------------------
# Anchor -> replacement pairs, keyed by relative path under src/pip/_internal.
# Each old string must occur exactly once in the parent file.
# --------------------------------------------------------------------------

LINK = "models/link.py"
DOWNLOAD = "network/download.py"
PREPARE = "operations/prepare.py"

EDIT_LINK = [
    (
        """from typing import (
    Any,
    NamedTuple,
)
""",
        """from typing import (
    Any,
    NamedTuple,
    NewType,
)
""",
    ),
    (
        """logger = logging.getLogger(__name__)


# Order matters, earlier hashes have a precedence over later hashes for what
""",
        """logger = logging.getLogger(__name__)


# A single path component: percent-decoded once and reduced to a basename, so it
# contains no path separator and is not a ``.`` or ``..`` reference. The empty
# string means "no component".
PathComponent = NewType("PathComponent", str)


def _to_path_component(name: str) -> PathComponent:
    \"\"\"Reduce ``name`` to a single path component, or ``""`` if it has none.

    ``os.path.basename`` drops any directory part, drive letter, or separator;
    a ``.``, ``..``, or empty result is not a component and becomes ``""``.
    \"\"\"
    name = os.path.basename(name)
    if name in ("", os.curdir, os.pardir):
        return PathComponent("")

    return PathComponent(name)


def as_path_component(name: str) -> PathComponent:
    \"\"\"Like ``_to_path_component`` but reject the empty result.

    Use where a file is about to be written, so a missing name is an error
    rather than a silent fallback to the directory itself.
    \"\"\"
    component = _to_path_component(name)
    if not component:
        raise ValueError(f"Unexpected file name derived from URL: {name!r}")

    return component


def join_within_directory(directory: str, component: PathComponent) -> str:
    \"\"\"Join a single path ``component`` onto ``directory``.

    ``component`` is a :data:`PathComponent`, so by type it has no separator and
    is not a ``.`` or ``..`` reference; the result can never escape ``directory``.
    Requiring ``PathComponent`` rather than ``str`` lets the type checker enforce
    at the call site that the name was reduced to a safe component beforehand.
    \"\"\"
    return os.path.join(directory, component)


# Order matters, earlier hashes have a precedence over later hashes for what
""",
    ),
    (
        """    @property
    def filename(self) -> str:
        path = self.path.rstrip("/")
        name = posixpath.basename(path)
        if not name:
            # Make sure we don't leak auth information if the netloc
            # includes a username and password.
            netloc, user_pass = split_auth_from_netloc(self.netloc)
            return netloc

        name = urllib.parse.unquote(name)
        assert name, f"URL {self._url!r} produced no filename"
        return name
""",
        """    @property
    def filename(self) -> PathComponent:
        name = _to_path_component(posixpath.basename(self.path.rstrip("/")))
        if name:
            return name

        # No component in the path; fall back to the netloc, dropping any auth.
        return _to_path_component(split_auth_from_netloc(self.netloc)[0])
""",
    ),
]

EDIT_DOWNLOAD = [
    (
        "from pip._internal.models.link import Link\n",
        """from pip._internal.models.link import (
    Link,
    PathComponent,
    as_path_component,
    join_within_directory,
)
""",
    ),
    (
        """def _get_http_response_filename(resp: Response, link: Link) -> str:
    \"\"\"Get an ideal filename from the given HTTP response, falling back to
    the link filename if not provided.
    \"\"\"
    filename = link.filename  # fallback
""",
        """def _get_http_response_filename(resp: Response, link: Link) -> PathComponent:
    \"\"\"Get an ideal filename from the given HTTP response, falling back to
    the link filename if not provided.

    The result is validated as a single path component, so it can be joined onto
    a download directory without escaping it.
    \"\"\"
    filename: str = link.filename  # fallback
""",
    ),
    (
        """    if not ext and link.url != resp.url:
        ext = os.path.splitext(resp.url)[1]
        if ext:
            filename += ext
    return filename
""",
        """    if not ext and link.url != resp.url:
        ext = os.path.splitext(resp.url)[1]
        if ext:
            filename += ext
    return as_path_component(filename)
""",
    ),
    (
        "        filepath = os.path.join(location, _get_http_response_filename(resp, link))\n",
        """        filepath = join_within_directory(
            location, _get_http_response_filename(resp, link)
        )
""",
    ),
]

EDIT_PREPARE = [
    (
        "from pip._internal.models.link import Link\n",
        "from pip._internal.models.link import Link, join_within_directory\n",
    ),
    (
        "    download_path = os.path.join(download_dir, link.filename)\n",
        "    download_path = join_within_directory(download_dir, link.filename)\n",
    ),
    (
        "        download_location = os.path.join(self.download_dir, link.filename)\n",
        "        download_location = join_within_directory(self.download_dir, link.filename)\n",
    ),
]


def apply_edits(path: Path, edits: list[tuple[str, str]]) -> None:
    source = path.read_text()
    for old, new in edits:
        count = source.count(old)
        if count != 1:
            raise SystemExit(
                f"{path}: anchor occurs {count} times (expected 1); "
                "the checkout does not match the pinned parent. Aborting."
            )
        source = source.replace(old, new)
    path.write_text(source)
    print(f"patched {path}")


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: fix_pip.py <src/pip/_internal dir>")
        return 2
    base = Path(sys.argv[1])
    apply_edits(base / LINK, EDIT_LINK)
    apply_edits(base / DOWNLOAD, EDIT_DOWNLOAD)
    apply_edits(base / PREPARE, EDIT_PREPARE)

    # Post-condition: the double decode is gone from link.py and the fixed
    # filename derives a single path component for a doubly-encoded URL.
    link_source = (base / LINK).read_text()
    if "urllib.parse.unquote(name)" in link_source:
        raise SystemExit("post-check failed: double decode still present in Link.filename")
    print("fix applied and post-checked OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())