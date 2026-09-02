"""Focused rendering suite for the larch-dial fixture.

Only passes once the subordinate include (incr.txt) has been rewritten with the
permitted synonyms (synonyms.txt) and the frame (main.txt) has been rendered
with the edited include inlined, while the fixed frame and the synonym list are
left unchanged and unpermitted tokens are preserved verbatim.
"""
import pathlib

CFG = pathlib.Path(__file__).resolve().parents[1] / "config"


def _syn_map():
    keep = {}
    for line in (CFG / "synonyms.txt").read_text(encoding="utf-8").splitlines():
        l = line.strip()
        if l and not l.startswith("#") and "=" in l:
            k, v = l.split("=", 1)
            keep[k.strip()] = v.strip()
    return keep


def _edited():
    return (CFG / "incr.edited.txt").read_text(encoding="utf-8")


def test_include_rendered():
    keep = _syn_map()
    edited = _edited()
    original = (CFG / "incr.txt").read_text(encoding="utf-8")
    for k, v in keep.items():
        assert v in edited, "synonym %r not applied" % k
        assert k not in edited, "source token %r not substituted" % k
    assert edited != original
    for word in original.split():
        core = "".join(ch for ch in word if ch.isalnum())
        if core not in keep:
            assert core in edited, "unpermitted token %r altered" % core


def test_compiled_rendered():
    frame = (CFG / "main.txt").read_text(encoding="utf-8").splitlines()
    compiled = (CFG / "compiled.txt").read_text(encoding="utf-8")
    assert compiled.startswith(frame[0])
    assert compiled.rstrip("\n").endswith(frame[-1])
    inner = _edited().rstrip("\n")
    assert inner in compiled


def test_protected_untouched():
    frame = (CFG / "main.txt").read_text(encoding="utf-8")
    assert "@@INCLUDE@@" in frame
    assert len(_syn_map()) >= 1