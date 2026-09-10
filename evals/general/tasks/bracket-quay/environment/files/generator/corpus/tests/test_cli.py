"""CLI end-to-end tests."""

import os
import subprocess
import sys
from pathlib import Path

REPO_ROOT = str(Path(__file__).resolve().parents[1])


def run_cli(args, cwd):
    return subprocess.run(
        [sys.executable, "-m", "quaydoc.cli"] + args,
        cwd=cwd, capture_output=True, text=True,
        env={**os.environ, "PYTHONPATH": REPO_ROOT})


def write_tree(root, files):
    for rel, body in files.items():
        p = root / rel
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text(body, encoding="utf-8")


def test_version(tmp_path):
    result = run_cli(["--version"], str(tmp_path))
    assert result.returncode == 0
    assert "quaydoc" in result.stdout


def test_init_scaffolds(tmp_path):
    result = run_cli(["init", str(tmp_path / "new")], str(tmp_path))
    assert result.returncode == 0
    assert (tmp_path / "new" / "quaydoc.toml").exists()
    assert (tmp_path / "new" / "index.qd").exists()


def test_build_and_check_roundtrip(tmp_path):
    root = tmp_path / "docs"
    write_tree(root, {
        "index.qd": "---\ntitle: Home\n---\nhello **world**\n",
    })
    result = run_cli(["build", str(root), "-o", str(tmp_path / "site")],
                     str(tmp_path))
    assert result.returncode == 0, result.stderr
    assert (tmp_path / "site" / "index.html").exists()
    result = run_cli(["check", str(tmp_path / "site")], str(tmp_path))
    assert result.returncode == 0, result.stdout + result.stderr


def test_check_fails_on_broken_site(tmp_path):
    site = tmp_path / "site"
    site.mkdir()
    (site / "index.html").write_text(
        '<a href="#ghost">x</a>', encoding="utf-8")
    result = run_cli(["check", str(site)], str(tmp_path))
    assert result.returncode == 1


def test_list_command(tmp_path):
    root = tmp_path / "docs"
    write_tree(root, {"index.qd": "---\ntitle: Home\n---\nbody\n"})
    result = run_cli(["list", str(root), "--columns", "url,title"], str(tmp_path))
    assert result.returncode == 0
    assert "/" in result.stdout and "Home" in result.stdout


def test_stats_command(tmp_path):
    root = tmp_path / "docs"
    write_tree(root, {"index.qd": "---\ntitle: Home\n---\nword word\n"})
    result = run_cli(["stats", str(root)], str(tmp_path))
    assert result.returncode == 0
    assert "pages: 1" in result.stdout


def test_lint_command(tmp_path):
    root = tmp_path / "docs"
    write_tree(root, {"index.qd": "---\ntitle: Home\n---\nhello\n"})
    result = run_cli(["lint", str(root)], str(tmp_path))
    assert result.returncode in (0, 1)


def test_quality_command(tmp_path):
    root = tmp_path / "docs"
    write_tree(root, {"index.qd": "---\ntitle: Home\n---\nhello TODO\n"})
    result = run_cli(["quality", str(root)], str(tmp_path))
    assert result.returncode == 0


def test_search_command(tmp_path):
    root = tmp_path / "docs"
    write_tree(root, {"index.qd":
                      "---\ntitle: Widget guide\n---\nwidget assembly\n"})
    run_cli(["build", str(root), "-o", str(tmp_path / "site")], str(tmp_path))
    result = run_cli(["search", "widget", str(tmp_path / "site")], str(tmp_path))
    assert result.returncode == 0
    assert "widget" in result.stdout.lower()
