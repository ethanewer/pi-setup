#!/usr/bin/env python3
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import sys
import click

HEX64 = re.compile(r"^[0-9a-f]{64}$")


class State:
    def __init__(self, root):
        self.root = Path(root).resolve()


def err(path, code, detail):
    return {"path": str(path), "code": code, "detail": str(detail)}


def canonical_path(value):
    if not isinstance(value, str) or not value or "\x00" in value:
        return False
    if "\\" in value or value.startswith("/"):
        return False
    p = PurePosixPath(value)
    return str(p) == value and all(part not in (".", "..", "") for part in p.parts)


def load_json(path):
    try:
        with open(path, "r", encoding="utf-8") as f:
            return json.load(f), None
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as exc:
        return None, str(exc)


def validate_policy(value, errors):
    if value is None:
        return {}
    if not isinstance(value, dict):
        errors.append(err("policy", "INVALID_POLICY", "policy must be an object"))
        return {}
    allowed = {"allowed_extensions", "max_bytes", "required_paths", "forbidden_paths"}
    for key in value:
        if key not in allowed:
            errors.append(err("policy", "INVALID_POLICY", f"unknown key {key!r}"))
    out = {}
    exts = value.get("allowed_extensions")
    if exts is not None:
        if not isinstance(exts, list) or any(not isinstance(x, str) or not x for x in exts) or len(set(exts)) != len(exts):
            errors.append(err("policy", "INVALID_POLICY", "allowed_extensions must be unique non-empty strings"))
        else:
            out["allowed_extensions"] = set(exts)
    maximum = value.get("max_bytes")
    if maximum is not None:
        if isinstance(maximum, bool) or not isinstance(maximum, int) or maximum < 0:
            errors.append(err("policy", "INVALID_POLICY", "max_bytes must be a non-negative integer"))
        else:
            out["max_bytes"] = maximum
    for key in ("required_paths", "forbidden_paths"):
        paths = value.get(key)
        if paths is not None:
            if not isinstance(paths, list) or any(not canonical_path(x) for x in paths) or len(set(paths)) != len(paths):
                errors.append(err("policy", "INVALID_POLICY", f"{key} must contain unique canonical relative paths"))
            else:
                out[key] = set(paths)
    return out


def report_json(ok, checked, errors):
    errors = sorted(errors, key=lambda x: (x["path"], x["code"], x["detail"]))
    return {"ok": not errors, "checked": checked, "errors": errors}


def emit(report, fmt, output):
    if fmt == "json":
        body = json.dumps(report, indent=2, sort_keys=True) + "\n"
    else:
        lines = ["OK" if report["ok"] else "FAIL", f"checked: {report['checked']}"]
        lines.extend(f"{e['path']}: {e['code']} {e['detail']}" for e in report["errors"])
        body = "\n".join(lines) + "\n"
    if str(output) == "-":
        click.echo(body, nl=False)
    else:
        try:
            Path(output).write_text(body, encoding="utf-8")
        except OSError as exc:
            raise click.ClickException(f"cannot write output: {exc}")


@click.group()
@click.pass_context
def cli(ctx):
    """Audit release manifests against local files."""
    ctx.obj = State(Path("."))


@cli.command()
@click.argument("manifest", type=click.Path(exists=True, dir_okay=False, path_type=Path))
@click.option("--root", type=click.Path(exists=True, file_okay=False, path_type=Path), default=Path("."), show_default=True)
@click.option("--policy", type=click.Path(exists=True, dir_okay=False, path_type=Path))
@click.option("--format", "fmt", type=click.Choice(["json", "text"]), default="json", show_default=True)
@click.option("--output", type=click.Path(path_type=Path), default="-", show_default=True)
@click.pass_obj
def audit(state, manifest, root, policy, fmt, output):
    """Check MANIFEST records and policy against files below ROOT."""
    state.root = root.resolve()
    root = state.root
    manifest_resolved = manifest.resolve()
    output_resolved = None if str(output) == "-" else output.resolve()
    forbidden_outputs = {manifest_resolved}
    if policy:
        forbidden_outputs.add(policy.resolve())
    errors = []
    raw, problem = load_json(manifest)
    if problem:
        errors.append(err("manifest", "INVALID_MANIFEST", problem))
        emit(report_json(False, 0, errors), fmt, output)
        raise click.exceptions.Exit(2)
    if not isinstance(raw, dict) or set(raw) != {"files"} or not isinstance(raw["files"], list):
        errors.append(err("manifest", "INVALID_MANIFEST", "expected an object with only a files list"))
        emit(report_json(False, 0, errors), fmt, output)
        raise click.exceptions.Exit(2)

    records = raw["files"]
    checked = len(records)
    if output_resolved is not None and output_resolved in forbidden_outputs:
        raise click.ClickException("output must not overwrite the manifest or policy")
    paths = []
    for i, record in enumerate(records):
        label = f"record[{i}]"
        if not isinstance(record, dict) or set(record) != {"path", "bytes", "sha256"}:
            errors.append(err(label, "INVALID_MANIFEST", "record must contain exactly path, bytes, and sha256"))
            continue
        path = record["path"]
        paths.append(path if isinstance(path, str) else label)
        if not canonical_path(path):
            errors.append(err(path if isinstance(path, str) else label, "PATH_TRAVERSAL", "path is not a canonical relative POSIX path"))
            continue
        if isinstance(record["bytes"], bool) or not isinstance(record["bytes"], int) or record["bytes"] < 0:
            errors.append(err(path, "INVALID_MANIFEST", "bytes must be a non-negative integer"))
        if not isinstance(record["sha256"], str) or not HEX64.fullmatch(record["sha256"]):
            errors.append(err(path, "INVALID_MANIFEST", "sha256 must be lowercase hexadecimal"))
    seen = set()
    for path in paths:
        if path in seen:
            errors.append(err(path, "DUPLICATE_PATH", "path occurs more than once"))
        seen.add(path)

    policy_value, problem = load_json(policy) if policy else ({}, None)
    if problem:
        errors.append(err("policy", "INVALID_POLICY", problem))
        policy_value = {}
    rules = validate_policy(policy_value, errors)
    for required in rules.get("required_paths", set()) - seen:
        errors.append(err(required, "REQUIRED_MISSING", "required path is absent from manifest"))
    for forbidden in rules.get("forbidden_paths", set()) & seen:
        errors.append(err(forbidden, "PATH_FORBIDDEN", "path is forbidden by policy"))

    for record in records:
        if not isinstance(record, dict) or set(record) != {"path", "bytes", "sha256"} or not canonical_path(record.get("path")):
            continue
        path = record["path"]
        if output_resolved is not None and output_resolved == (root / path).resolve(strict=False):
            raise click.ClickException("output must not overwrite an audited input")
        candidate = root / Path(*PurePosixPath(path).parts)
        resolved = candidate.resolve(strict=False)
        try:
            resolved.relative_to(root)
        except ValueError:
            errors.append(err(path, "SYMLINK_ESCAPE", "resolved path is outside root"))
            continue
        if not candidate.exists():
            errors.append(err(path, "MISSING_FILE", "file does not exist"))
            continue
        if candidate.is_symlink() and not resolved.is_relative_to(root):
            errors.append(err(path, "SYMLINK_ESCAPE", "symlink target is outside root"))
            continue
        if not candidate.is_file():
            errors.append(err(path, "NOT_REGULAR", "path is not a regular file"))
            continue
        if "allowed_extensions" in rules and Path(path).suffix not in rules["allowed_extensions"]:
            errors.append(err(path, "EXTENSION_FORBIDDEN", "file extension is not allowed"))
        try:
            data = candidate.read_bytes()
        except OSError as exc:
            errors.append(err(path, "READ_ERROR", str(exc)))
            continue
        if len(data) != record["bytes"]:
            errors.append(err(path, "BYTE_MISMATCH", f"expected {record['bytes']} bytes, got {len(data)}"))
        if hashlib.sha256(data).hexdigest() != record["sha256"]:
            errors.append(err(path, "HASH_MISMATCH", "SHA-256 digest differs"))
        if "max_bytes" in rules and len(data) > rules["max_bytes"]:
            errors.append(err(path, "SIZE_LIMIT", f"file exceeds {rules['max_bytes']} bytes"))
    result = report_json(not errors, checked, errors)
    emit(result, fmt, output)
    if not result["ok"]:
        raise click.exceptions.Exit(2)


if __name__ == "__main__":
    cli()
