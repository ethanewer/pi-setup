#!/usr/bin/env python3
"""Veldt workspace fixture generator (runs at image build time).

Assembles /app/workspace from the static templates under /app/tpl/workspace,
fills in the CRC lookup tables (the only generated source content), builds a
git history one logical commit at a time, and then proves the workspace is
green by running `cargo build --workspace` and `cargo test --workspace`
before generating the example capture with the freshly built CLI.

Everything below is deterministic: the same template tree on the same machine
produces the same workspace, the same history, and the same example capture.
"""

import os
import shutil
import subprocess
import sys

TPL = os.environ.get("VELDT_TPL", "/app/tpl/workspace")
WS = os.environ.get("VELDT_WS", "/app/workspace")

GIT = ["git", "-c", "user.name=build", "-c", "user.email=build@localhost"]


def crc16_table() -> list:
    # XMODEM polynomial 0x1021, left-shift table construction
    out = []
    for i in range(256):
        crc = i << 8
        for _ in range(8):
            if crc & 0x8000:
                crc = ((crc << 1) ^ 0x1021) & 0xFFFF
            else:
                crc = (crc << 1) & 0xFFFF
        out.append(crc)
    return out


def crc32_table() -> list:
    # reflected ISO-HDLC polynomial 0xEDB88320, right-shift construction
    out = []
    for i in range(256):
        crc = i
        for _ in range(8):
            if crc & 1:
                crc = ((crc >> 1) ^ 0xEDB88320) & 0xFFFFFFFF
            else:
                crc = (crc >> 1) & 0xFFFFFFFF
        out.append(crc)
    return out


def render_crc(src: str, ws: str) -> None:
    path = os.path.join(ws, "crates/veldt-core/src/crc.rs")
    text = open(path).read()
    assert "@@CRC16_TABLE@@" in text and "@@CRC32_TABLE@@" in text
    lines16 = []
    lines32 = []
    t16 = crc16_table()
    t32 = crc32_table()
    for i in range(0, 256, 8):
        lines16.append("    " + ", ".join("0x%04X" % v for v in t16[i:i + 8]) + ",")
        lines32.append("    " + ", ".join("0x%08X" % v for v in t32[i:i + 8]) + ",")
    text = text.replace("@@CRC16_TABLE@@", "\n".join(lines16))
    text = text.replace("@@CRC32_TABLE@@", "\n".join(lines32))
    open(path, "w").write(text)


def run(cmd, cwd=None, check=True):
    proc = subprocess.run(cmd, cwd=cwd, capture_output=True, text=True)
    if check and proc.returncode != 0:
        sys.stderr.write("command failed: %s\n" % " ".join(cmd))
        sys.stderr.write(proc.stderr[-4000:])
        sys.exit(1)
    return proc


def git(args, cwd):
    run(GIT + args, cwd=cwd)


def commit(message, paths, cwd):
    git(["reset", "-q"], cwd)
    for p in paths:
        git(["add", "-f", "--", p], cwd)
    git(["commit", "-q", "-m", message], cwd)


def main() -> None:
    if os.path.exists(WS):
        shutil.rmtree(WS)
    shutil.copytree(TPL, WS)
    render_crc("", WS)

    os.chdir(WS)
    git(["init", "-q", "-b", "main"], WS)
    commit("chore: scaffold the veldt workspace (manifest, license, gitignore)",
           ["Cargo.toml", "LICENSE", ".gitignore"], WS)

    commit("feat(core): byte buffers, cursor, varints, checksums",
           ["crates/veldt-core/src/error.rs",
            "crates/veldt-core/src/bytes.rs",
            "crates/veldt-core/src/varint.rs",
            "crates/veldt-core/src/crc.rs"], WS)

    commit("feat(core): frame kinds and the frame codec",
           ["crates/veldt-core/src/kinds.rs",
            "crates/veldt-core/src/frame.rs",
            "crates/veldt-core/src/lib.rs",
            "crates/veldt-core/Cargo.toml"], WS)

    commit("test(core): buffers, varints, checksums, frames",
           ["crates/veldt-core/tests"], WS)

    commit("feat(measure): unit taxonomy, SI prefixes, quantities",
           ["crates/veldt-measure/src/unit.rs",
            "crates/veldt-measure/src/prefix.rs",
            "crates/veldt-measure/src/quantity.rs",
            "crates/veldt-measure/Cargo.toml"], WS)

    commit("feat(measure): intervals, series, formatting",
           ["crates/veldt-measure/src/interval.rs",
            "crates/veldt-measure/src/series.rs",
            "crates/veldt-measure/src/format.rs",
            "crates/veldt-measure/src/lib.rs"], WS)

    commit("test(measure): conversion vectors and statistics",
           ["crates/veldt-measure/tests"], WS)

    commit("feat(transport): byte sources and sinks",
           ["crates/veldt-transport/src/source.rs",
            "crates/veldt-transport/src/sink.rs",
            "crates/veldt-transport/Cargo.toml"], WS)

    commit("feat(transport): frame reader, writer, sessions",
           ["crates/veldt-transport/src/reader.rs",
            "crates/veldt-transport/src/writer.rs",
            "crates/veldt-transport/src/session.rs",
            "crates/veldt-transport/src/lib.rs"], WS)

    commit("test(transport): round trips, truncation, gaps, sessions",
           ["crates/veldt-transport/tests"], WS)

    commit("feat(cli): argument parsing and capture synthesis",
           ["crates/veldt-cli/src/args.rs",
            "crates/veldt-cli/src/capture.rs",
            "crates/veldt-cli/src/lib.rs",
            "crates/veldt-cli/Cargo.toml"], WS)

    commit("feat(cli): cat, replay, summarize, units, hash",
           ["crates/veldt-cli/src/main.rs",
            "crates/veldt-cli/tests"], WS)

    commit("docs: architecture, frame format, ops runbook, demo station",
           ["docs/ARCHITECTURE.md",
            "docs/FRAME_FORMAT.md",
            "docs/OPS_RUNBOOK.md",
            "README.md",
            "example/stations"], WS)

    commit("docs: integration contract for the resume capability",
           ["docs/INTEGRATION.md"], WS)

    # ---- prove the workspace is green before the agent arrives ----
    run(["cargo", "build", "--workspace", "--offline"], cwd=WS)
    run(["cargo", "test", "--workspace", "--offline"], cwd=WS)

    # ---- generate the example capture with the fresh CLI ----
    run(["./target/debug/veldt", "capture", "example/capture.bin",
         "--seed", "11", "--frames", "40", "--samples", "24"], cwd=WS)
    commit("chore(example): regenerate the demo capture and lockfile",
           ["Cargo.lock", "example/capture.bin"], WS)

    log = run(["git", "log", "--oneline"], cwd=WS).stdout
    sys.stderr.write(log)
    print("workspace assembled at %s with %d commits" %
          (WS, len(log.strip().splitlines())))


if __name__ == "__main__":
    main()