"""Source discovery tests."""

from quaydoc import finder
from quaydoc.config import load_config


def write_docs(tmp_path, files):
    for rel, body in files.items():
        path = tmp_path / rel
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(body, encoding="utf-8")


def test_finds_qd_and_md(tmp_path):
    write_docs(tmp_path, {"a.qd": "x", "b.md": "y", "c.txt": "z"})
    found = finder.find_docs(str(tmp_path), load_config(str(tmp_path)))
    assert len(found) == 2


def test_skips_hidden_dirs(tmp_path):
    write_docs(tmp_path, {".secret/h.qd": "x", "ok.qd": "y"})
    found = finder.find_docs(str(tmp_path), load_config(str(tmp_path)))
    assert len(found) == 1


def test_skips_output_dir(tmp_path):
    write_docs(tmp_path, {"ok.qd": "y"})
    (tmp_path / "site").mkdir()
    (tmp_path / "site" / "built.qd").write_text("nope", encoding="utf-8")
    found = finder.find_docs(str(tmp_path), load_config(str(tmp_path)))
    assert len(found) == 1


def test_ignore_patterns(tmp_path):
    write_docs(tmp_path, {"keep.qd": "y", "draft.qd": "n"})
    (tmp_path / ".quayignore").write_text("draft.qd\n", encoding="utf-8")
    config = load_config(str(tmp_path))
    assert ["draft.qd"] == finder.load_ignore_patterns(str(tmp_path))
    found = finder.find_docs(str(tmp_path), config)
    assert all("draft" not in str(f) for f in found)


def test_iter_candidates_yields_rels(tmp_path):
    write_docs(tmp_path, {"a/qd.qd": "x"})
    pairs = list(finder.iter_candidates(str(tmp_path),
                                        load_config(str(tmp_path))))
    assert pairs[0][1] == "a/qd.qd"
