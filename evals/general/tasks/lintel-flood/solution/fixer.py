#!/usr/bin/env python3
"""Repair the floodgate crate's combined-strategy integration.

This is the reference solver for lintel-flood. It is deliberately
generative rather than a verbatim patch:

  1. It reads the ACTUAL public verdict shapes defined by the sliding and
     bucket strategy modules (`src/sliding.rs`, `src/bucket.rs`) and checks
     them against the API this crate is documented to expose.
  2. It regenerates the combined-strategy module (`src/dual.rs`) from that
     verified API, implementing the contract documented in README.md:
       * a request is admitted only when BOTH strategies admit it;
       * on a denial the retry delay is the LARGER of the two strategies'
         individual retry delays, where a strategy that admits contributes
         zero.
  3. It proves the repair by running `cargo build --features sliding,bucket`
     and the full test suite under that combination.

The solver never reads the verifier's files. Its contract input is the
crate's own source and documentation.

Usage: fixer.py /app/floodgate
"""

import os
import re
import subprocess
import sys
from pathlib import Path

SLIDING_FIELDS = ("admit", "next_ok_ms")
BUCKET_FIELDS = ("granted", "ready_ms")


def read(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def public_fields(path: Path, struct_name: str) -> list[str]:
    """Return the `pub name:` fields of a struct declared in `path`."""
    src = read(path)
    m = re.search(
        r"pub\s+struct\s+%s\s*\{(?P<body>.*?)\}" % struct_name, src, re.S
    )
    if not m:
        raise SystemExit(f"cannot find struct {struct_name} in {path}")
    return re.findall(r"\bpub\s+(\w+)\s*:", m.group("body"))


def main() -> int:
    root = Path(sys.argv[1]) if len(sys.argv) > 1 else Path("/app/floodgate")
    root = root.resolve()
    if not (root / "Cargo.toml").is_file():
        print(f"no crate at {root}", file=sys.stderr)
        return 1

    sliding_src = root / "src" / "sliding.rs"
    bucket_src = root / "src" / "bucket.rs"
    dual_src = root / "src" / "dual.rs"

    sliding_fields = public_fields(sliding_src, "SlidingVerdict")
    bucket_fields = public_fields(bucket_src, "BucketVerdict")
    for required in SLIDING_FIELDS:
        if required not in sliding_fields:
            print(f"sliding API changed: missing field {required!r}", file=sys.stderr)
            return 1
    for required in BUCKET_FIELDS:
        if required not in bucket_fields:
            print(f"bucket API changed: missing field {required!r}", file=sys.stderr)
            return 1
    # The combined module must mirror the names it learned from the two
    # strategies so the generated code uses the real, current API.
    s_admit, s_retry = SLIDING_FIELDS
    b_granted, b_ready = BUCKET_FIELDS

    dual = f"""//! Combined sliding + bucket accounting strategy, compiled only when both the
//! `sliding` and `bucket` features are enabled.
//!
//! Contract (documented in README.md):
//!
//!   * The gate consults both strategies for the same request and admits it
//!     only when **both** admit.
//!   * On a denial, the retry delay is the **larger** of the two strategies'
//!     individual retry delays, where a strategy that admits contributes zero.
//!     This is the earliest instant at which a retry could plausibly succeed:
//!     the request remains blocked until the *last* of the two constraints
//!     releases.

use crate::bucket::BucketGate;
use crate::core::{{Config, Verdict}};
use crate::sliding::SlidingGate;

/// Combined gate. Keys are accounted by both strategies.
pub struct Dual {{
    sliding: SlidingGate,
    bucket: BucketGate,
}}

impl Dual {{
    pub fn make(cfg: &Config) -> Dual {{
        Dual {{
            sliding: SlidingGate::make(cfg),
            bucket: BucketGate::make(cfg),
        }}
    }}

    pub fn check(&mut self, key: &str, qty: u64, now_ms: u64) -> Verdict {{
        let s = self.sliding.check(key, qty, now_ms);
        let b = self.bucket.check(key, qty, now_ms);
        let s_wait = if s.{s_admit} {{ 0 }} else {{ s.{s_retry} }};
        let b_wait = if b.{b_granted} {{ 0 }} else {{ b.{b_ready} }};
        if s_wait == 0 && b_wait == 0 {{
            Verdict::Admit
        }} else if s_wait > b_wait {{
            Verdict::Defer {{ retry_after_ms: s_wait }}
        }} else {{
            Verdict::Defer {{ retry_after_ms: b_wait }}
        }}
    }}
}}
"""
    dual_src.write_text(dual, encoding="utf-8")

    # Prove the repair: the combined combination must build and test green.
    # Note: the subprocess must inherit the ambient environment (PATH above
    # all), or rustc cannot locate the `cc` linker.
    env = dict(os.environ)
    env["CARGO_NET_OFF"] = "true"
    build = subprocess.run(
        ["cargo", "build", "--features", "sliding,bucket"],
        cwd=str(root),
        env=env,
        capture_output=True,
        text=True,
    )
    if build.returncode != 0:
        print("cargo build --features sliding,bucket FAILED after repair:")
        print(build.stderr[-2000:])
        return 1
    test = subprocess.run(
        ["cargo", "test", "--features", "sliding,bucket"],
        cwd=str(root),
        env=env,
        capture_output=True,
        text=True,
    )
    if test.returncode != 0:
        print("cargo test --features sliding,bucket FAILED after repair:")
        print(test.stdout[-2000:])
        print(test.stderr[-2000:])
        return 1
    print("fixer: combined-strategy module regenerated; sliding,bucket green")
    return 0


if __name__ == "__main__":
    sys.exit(main())