"""Hidden case 2: the derived name is used as a single path component when it
is joined onto a download directory, and the join never escapes the directory.

The upstream test joins with plain single-component names; these cases drive
the SAME helpers/join that pip's download and download-dir lookup paths use
(_get_http_response_filename / Downloader._download and _check_download_dir in
the fixed tree) with names that come straight out of Link.filename for
double-encoded URLs, assert the result stays inside the directory, and check
the netloc fallback for traversal-shaped paths.
"""
from __future__ import annotations

import os

import pytest

from pip._internal.models.link import Link, as_path_component, join_within_directory

NAMES = [
    "pkg-2.0%2Brc1.whl",
    "sp%2520ace.whl",
    "x%2Fy-0.1.tar.gz",
    "a%23b.zip",
    "v1%2Fpkg-0.1.tar.gz",
]


@pytest.mark.parametrize("name", NAMES)
def test_join_within_directory_stays_inside(name: str) -> None:
    directory = os.path.join("tmp", "downloads")
    joined = join_within_directory(directory, as_path_component(name))
    # The name is the FINAL element only: joining may never reintroduce a
    # separator or escape the directory.
    assert joined == os.path.join(directory, name)
    assert os.path.dirname(joined) == directory
    assert os.path.basename(joined) == name


def test_download_name_is_a_literal_single_component_on_disk(tmp_path) -> None:
    # The exact bytes pip derives decide the on-disk path: the once-decoded
    # name holding the literal "%2F" is the single file inside the directory,
    # and no nested "a/b.whl" path exists anywhere under it.
    link = Link("https://example.com/a%252Fb.whl")
    target = join_within_directory(str(tmp_path), link.filename)
    assert os.path.dirname(target) == str(tmp_path)
    assert os.path.basename(target) == "a%2Fb.whl"
    with open(target, "w", encoding="utf-8") as fh:
        fh.write("x")
    assert os.path.isfile(os.path.join(str(tmp_path), "a%2Fb.whl"))
    assert not os.path.exists(os.path.join(str(tmp_path), "a", "b.whl"))


@pytest.mark.parametrize(
    "url",
    [
        # Traversal-shaped paths with no usable file name fall back to the
        # netloc, dropping any auth.
        "https://example.com/%2e%2e",
        "https://example.com/./",
        "https://example.com/a/%2e%2e/",
        "https://example.com/%2e%2e%2f",
        # A doubly-encoded name on an authenticated host still yields the
        # single once-decoded component, with no auth leakage.
        "https://user:pass@example.com/a%252Fb.whl",
    ],
)
def test_traversal_shaped_paths_yield_safe_names(url: str) -> None:
    name = Link(url).filename
    assert os.path.basename(name) == name
    assert name not in ("", ".", "..")
    assert "pass@" not in name and "user:" not in name
    if "%2e" in url.lower():
        assert name == "example.com"