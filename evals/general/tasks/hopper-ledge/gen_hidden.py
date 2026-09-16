#!/usr/bin/env python3
"""Generate the three hidden fixture repositories for hopper-ledge.

Each fixture is an org repository in the same shape as the visible one
(app package, pytest suite with a repo-hygiene test, build + artifact-gate
scripts, vendored dependency, ci pipeline for the shared runner) but with
DIFFERENT concrete details: job names, artifact directories, cache paths,
lockfile names, vendored libraries and pipeline topology (2 and 3 jobs).
The pipeline configs are correct; a fixed shared runner passes them, a
repair that is specific to the visible repository (hardcoded names, paths,
or a rigged test suite) does not.

Run at authoring time only; the emitted directories are committed.
Usage: python3 gen_hidden.py <tests-dir>
"""

import hashlib
import json
import os
import subprocess
import sys
from pathlib import Path

HIDDEN = Path(sys.argv[1] if len(sys.argv) > 1 else "tests/hidden")

PYTEST_UNIT = (
    '{"step": "run", "name": "unit",\n'
    '         "cmd": "python3 -m pytest -p no:cacheprovider -q tests/",\n'
    '         "if": "always",\n'
    '         "env": {"PYTHONDONTWRITEBYTECODE": "1"}}'
)


def pipeline(jobs_text):
    body = "\n".join("    " + line for line in jobs_text.splitlines())
    return '{\n  "ci_version": 1,\n  "jobs": {\n%s\n  }\n}\n' % body


def job_block(name, steps):
    inner = ",\n".join("      %s" % s for s in steps)
    return '"%s": {\n      "steps": [\n%s\n      ]\n    }' % (name, inner)


def restore(name, key, path):
    return ('{"step": "restore_cache", "key": "%s", "path": "%s",'
            ' "if": "always"}' % (key, path))


def run(name, cmd, gate="always"):
    return '{"step": "run", "name": "%s", "cmd": "%s", "if": "%s"}' % (
        name, cmd, gate)


def upload(path):
    return '{"step": "upload_artifacts", "path": "%s", "if": "always"}' % path


def download(frm):
    return ('{"step": "download_artifacts", "from": "%s",'
            ' "if": "always"}' % frm)


def emit(repo: Path, files: dict):
    for rel, text in files.items():
        p = repo / rel
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text(text)


def hygiene_test(generated_set, extra_layout=()):
    lines = [
        '"""Repo hygiene: the checkout must stay free of generated output."""',
        "from pathlib import Path",
        "",
        "ROOT = Path(__file__).resolve().parents[1]",
        "GENERATED = set(%s)" % sorted(generated_set),
        "",
        "",
        "def test_no_generated_output_at_checkout_root():",
        "    present = {p.name for p in ROOT.iterdir() if p.is_dir()}",
        "    leaked = sorted(GENERATED & present)",
        "    assert not leaked, (",
        '        "generated build/dependency output left in the checkout: %s"',
        "        % leaked",
        "    )",
        "",
        "",
        "def test_expected_top_level_layout():",
    ]
    for item in extra_layout:
        lines.append('    assert (ROOT / "%s").is_dir()' % item)
    lines += [
        '    assert not (ROOT / "out").exists()',
        '    assert not (ROOT / ".deps").exists()',
        "",
    ]
    return "\n".join(lines)


def generic_build(build_code, install_sh, dep_name, dep_version, cache_dir,
                  whl, meta_name, meta_pkg, meta_ver, meta_extra):
    return {
        "scripts/build.py": build_code,
        "scripts/check_artifact.py": None,  # set per fixture
        "ci/install.sh": install_sh,
        "ci/%s" % dep_name: dep_version + "\n",
    }


def suite_manifest(repo: Path, tests_passed: int):
    files = {}
    for p in sorted((repo / "tests").rglob("*.py")):
        files[p.relative_to(repo).as_posix()] = hashlib.sha256(
            p.read_bytes()).hexdigest()
    return {"tests_passed": tests_passed, "test_files": files}


# ============================================================================
# wigeon: sound-scaling utilities. Jobs: compile -> verify.
# artifact dir "out/", cache dir ".cache_deps", lock "ci/constraints.lock".
# ============================================================================
WIGEON_CORE = '''"""Signal-scaling utilities for the wigeon telemetry service."""
import math


def db_to_gain(db):
    """Convert a decibel value to a linear gain factor."""
    return 10.0 ** (db / 20.0)


def gain_to_db(gain):
    """Convert a linear gain factor to decibels."""
    if gain <= 0:
        raise ValueError("gain must be positive")
    return 20.0 * math.log10(gain)


def clip(value, lo, hi):
    """Clamp value into [lo, hi]."""
    if hi < lo:
        raise ValueError("hi must be >= lo")
    return max(lo, min(hi, value))


def compress(peak, ceiling):
    """Compression ratio that maps PEAK down to CEILING when needed."""
    if peak <= 0 or ceiling <= 0:
        raise ValueError("levels must be positive")
    if peak <= ceiling:
        return 1.0
    return ceiling / peak


def integrate(samples):
    """RMS level of a list of equally spaced samples."""
    if not samples:
        return 0.0
    return math.sqrt(sum(s * s for s in samples) / len(samples))
'''

WIGEON_INIT = '''"""wigeon: sound scaling utilities for telemetry."""
from .core import db_to_gain, gain_to_db, clip, compress, integrate

__all__ = ["db_to_gain", "gain_to_db", "clip", "compress", "integrate"]
__version__ = "2.1.0"
'''

WIGEON_TESTS = '''"""Unit tests for the wigeon signal-scaling module."""
import math

import pytest

from wigeon import clip, compress, db_to_gain, gain_to_db, integrate


def test_db_to_gain_zero_is_unity():
    assert db_to_gain(0.0) == pytest.approx(1.0)


def test_db_to_gain_positive():
    assert db_to_gain(20.0) == pytest.approx(10.0)


def test_db_to_gain_negative():
    assert db_to_gain(-20.0) == pytest.approx(0.1)


def test_gain_to_db_round_trip():
    for gain in (0.5, 1.0, 2.0, 8.0):
        assert db_to_gain(gain_to_db(gain)) == pytest.approx(gain)


def test_gain_to_db_nonpositive_raises():
    with pytest.raises(ValueError):
        gain_to_db(0.0)
    with pytest.raises(ValueError):
        gain_to_db(-3.0)


def test_clip_within_range_unchanged():
    assert clip(0.5, 0.0, 1.0) == 0.5


def test_clip_above_ceiling():
    assert clip(1.5, 0.0, 1.0) == 1.0


def test_clip_below_floor():
    assert clip(-0.5, 0.0, 1.0) == 0.0


def test_clip_inverted_bounds_raises():
    with pytest.raises(ValueError):
        clip(0.5, 1.0, 0.0)


def test_compress_below_ceiling_is_unity():
    assert compress(0.5, 1.0) == 1.0


def test_compress_above_ceiling():
    assert compress(8.0, 2.0) == pytest.approx(0.25)


def test_compress_nonpositive_raises():
    with pytest.raises(ValueError):
        compress(0.0, 1.0)
    with pytest.raises(ValueError):
        compress(1.0, -1.0)


def test_integrate_empty_is_zero():
    assert integrate([]) == 0.0


def test_integrate_rms():
    assert integrate([1.0, -1.0, 1.0, -1.0]) == pytest.approx(1.0)
    assert integrate([3.0, 4.0]) == pytest.approx(3.5355339)
'''

MARK = 0
WIGEON_BUILD = '''#!/usr/bin/env python3
"""Assemble the wigeon wheel and sidecar artifacts into out/."""
import hashlib
import json
import os
import sys
import zipfile
from pathlib import Path

sys.path.insert(0, os.path.join(os.getcwd(), ".cache_deps"))
import sndlib  # noqa: E402  (vendored dependency from the install step)

ROOT = Path.cwd()
APP = ROOT / "wigeon"
OUT = ROOT / "out"


def sources_digest():
    h = hashlib.sha256()
    for f in sorted(APP.rglob("*.py")):
        h.update(f.relative_to(ROOT).as_posix().encode())
        h.update(f.read_bytes())
    return h.hexdigest()


def main():
    assert sndlib.tag() == "vendored-0.9.0", "dependency mismatch"
    OUT.mkdir(exist_ok=True)
    wheel = OUT / "wigeon.whl"
    with zipfile.ZipFile(wheel, "w", zipfile.ZIP_DEFLATED) as zf:
        for f in sorted(APP.rglob("*.py")):
            zf.write(f, f.relative_to(APP).as_posix())
        zf.writestr("VERSION", "2.1.0\\n")
    (OUT / "sources.sha256").write_text(sources_digest() + "\\n")
    (OUT / "metadata.json").write_text(json.dumps({
        "package": "wigeon",
        "version": "2.1.0",
        "wheel": "wigeon.whl",
        "sndlib": sndlib.tag(),
    }, indent=2))
    print("built out/wigeon.whl (digest %s)" % sources_digest()[:12])


if __name__ == "__main__":
    main()
'''

WIGEON_CHECK = '''#!/usr/bin/env python3
"""Consumer-side artifact gate for the wigeon pipeline."""
import hashlib
import json
import zipfile
from pathlib import Path

ROOT = Path.cwd()


def sources_digest():
    h = hashlib.sha256()
    for f in sorted((ROOT / "wigeon").rglob("*.py")):
        h.update(f.relative_to(ROOT).as_posix().encode())
        h.update(f.read_bytes())
    return h.hexdigest()


def main():
    for required in ("metadata.json", "wigeon.whl", "sources.sha256"):
        if not (ROOT / required).is_file():
            raise SystemExit("missing artifact file: %s" % required)
    meta = json.loads((ROOT / "metadata.json").read_text())
    assert meta["package"] == "wigeon", meta
    with zipfile.ZipFile(ROOT / "wigeon.whl") as zf:
        names = set(zf.namelist())
    expected = {"__init__.py", "core.py", "VERSION"}
    missing = sorted(expected - names)
    if missing:
        raise SystemExit("wheel missing members: %s" % missing)
    got = (ROOT / "sources.sha256").read_text().strip()
    want = sources_digest()
    if got != want:
        raise SystemExit("sources digest mismatch: %s != %s" % (got, want))
    print("artifact ok: wheel ok digest=%s" % want[:12])


if __name__ == "__main__":
    main()
'''

WIGEON_INSTALL = """#!/usr/bin/env bash
# Install the wigeon vendored dependency into .cache_deps (cache-miss only).
set -euo pipefail
mkdir -p .cache_deps
rm -rf .cache_deps/sndlib
cp -r ci/vendor/sndlib .cache_deps/sndlib
printf 'sndlib==0.9.0\\n' > .cache_deps/DEPENDENCIES
echo "vendored dependencies installed (sndlib 0.9.0)"
"""

WIGEON_SND_INIT = '''"""Vendored sndlib dependency (org internal)."""
from .core import tag  # noqa: F401

__version__ = "0.9.0"
'''

WIGEON_SND_CORE = '''"""sndlib: audio-level helpers the wigeon build relies on."""


def tag():
    """Stable identity of this vendored dependency snapshot."""
    return "vendored-0.9.0"


def dbfs_to_linear(dbfs):
    """Map a dBFS reading in [-inf, 0] to a linear level in [0, 1]."""
    if dbfs >= 0:
        return 1.0
    return 10.0 ** (dbfs / 20.0)
'''

WIGEON_HYGIENE = hygiene_test(
    {"out", ".cache_deps", "dist", ".deps", "build", "release",
     "artifacts", ".vendor"},
    extra_layout=("wigeon", "ci", "tests"),
)

wigeon_pipeline = pipeline(",\n".join([
    job_block("compile", [
        restore("restore_cache", "deps-{{hash:ci/constraints.lock}}",
                ".cache_deps"),
        run("install", "bash ci/install.sh", "cache_miss"),
        run("build", "python3 scripts/build.py"),
        upload("out/"),
    ]),
    job_block("verify", [
        download("compile"),
        run("verify_artifact", "python3 scripts/check_artifact.py"),
        PYTEST_UNIT,
    ]),
]))

# ============================================================================
# curlew: grid encoding. Jobs: build -> package -> verify (artifact chain).
# artifact dirs "dist/" and "release/", cache ".vendor", lock "ci/vendor.lock".
# ============================================================================
CURLEW_CORE = '''"""Geohash-style grid encoding for the curlew fleet tracker.

Cells are compact 32-char alphabet strings; latitude/longitude bits are
interleaved starting with longitude, which keeps nearby points in nearby
cells regardless of hemisphere.
"""

_BASE32 = "0123456789bcdefghjkmnpqrstuvwxyz"


def encode(lat, lon, precision=6):
    """Encode (lat, lon) into a grid cell string of PRECISION chars."""
    if not (-90.0 <= lat <= 90.0 and -180.0 <= lon <= 180.0):
        raise ValueError("coordinates out of range")
    lat_min, lat_max = -90.0, 90.0
    lon_min, lon_max = -180.0, 180.0
    out = []
    bits, chunk, lat_turn = 0, 0, False
    while len(out) < precision:
        if not lat_turn:
            mid = (lon_min + lon_max) / 2.0
            if lon >= mid:
                chunk = (chunk << 1) | 1
                lon_min = mid
            else:
                chunk <<= 1
                lon_max = mid
        else:
            mid = (lat_min + lat_max) / 2.0
            if lat >= mid:
                chunk = (chunk << 1) | 1
                lat_min = mid
            else:
                chunk <<= 1
                lat_max = mid
        lat_turn = not lat_turn
        bits += 1
        if bits % 5 == 0:
            out.append(_BASE32[chunk])
            bits, chunk = 0, 0
    return "".join(out)


def neighbouring(cell):
    """The alphabet-adjacent cells for a valid cell string."""
    if not cell or any(c not in _BASE32 for c in cell):
        raise ValueError("invalid cell string")
    return set(cell[:-1] + c for c in _BASE32 if c != cell[-1])
'''

CURLEW_INIT = '''"""curlew: grid cell encoding for the fleet tracker."""
from .core import encode, neighbouring

__all__ = ["encode", "neighbouring"]
__version__ = "0.3.4"
'''

CURLEW_TESTS = '''"""Unit tests for the curlew grid encoding module."""
import pytest

from curlew import encode, neighbouring

ALPHABET = "0123456789bcdefghjkmnpqrstuvwxyz"


def test_encode_length():
    for precision in (1, 3, 6, 10):
        assert len(encode(0.0, 0.0, precision)) == precision


def test_encode_charset():
    code = encode(12.34, -56.78, 8)
    assert all(c in ALPHABET for c in code)


def test_encode_is_deterministic():
    assert encode(41.9, 2.6, 6) == encode(41.9, 2.6, 6)


def test_encode_out_of_range_raises():
    with pytest.raises(ValueError):
        encode(91.0, 0.0)
    with pytest.raises(ValueError):
        encode(0.0, -181.0)


def test_encode_nearby_points_share_prefix():
    a = encode(0.0, 0.0, 6)
    b = encode(0.0002, 0.0002, 6)
    assert a[:5] == b[:5]


def test_encode_opposite_hemispheres_differ_early():
    north = encode(89.9, 179.9, 6)
    south = encode(-89.9, -179.9, 6)
    assert north != south
    assert north[0] != south[0]


def test_encode_integer_coordinates():
    assert encode(52.0, 13.0, 1) in ALPHABET


def test_neighbouring_rejects_missing_char():
    with pytest.raises(ValueError):
        neighbouring("")


def test_neighbouring_rejects_bad_char():
    with pytest.raises(ValueError):
        neighbouring("aX9000")


def test_neighbouring_returns_distinct_neighbours():
    cell = encode(1.0, 1.0, 3)
    nbrs = neighbouring(cell)
    assert len(nbrs) == len(ALPHABET) - 1
    assert cell not in nbrs
'''

CURLEW_BUILD = '''#!/usr/bin/env python3
"""Assemble the curlew wheel and sidecar artifacts into dist/."""
import hashlib
import json
import os
import sys
import zipfile
from pathlib import Path

sys.path.insert(0, os.path.join(os.getcwd(), ".vendor"))
import gridlib  # noqa: E402  (vendored dependency from the install step)

ROOT = Path.cwd()
LIB = ROOT / "curlew"
DIST = ROOT / "dist"


def sources_digest():
    h = hashlib.sha256()
    for f in sorted(LIB.rglob("*.py")):
        h.update(f.relative_to(ROOT).as_posix().encode())
        h.update(f.read_bytes())
    return h.hexdigest()


def main():
    assert gridlib.tag() == "vendored-0.4.1", "dependency mismatch"
    DIST.mkdir(exist_ok=True)
    wheel = DIST / "window.whl"
    with zipfile.ZipFile(wheel, "w", zipfile.ZIP_DEFLATED) as zf:
        for f in sorted(LIB.rglob("*.py")):
            zf.write(f, f.relative_to(LIB).as_posix())
        zf.writestr("VERSION", "0.3.4\\n")
    (DIST / "checksums.txt").write_text("sha256 " + sources_digest() + "\\n")
    (DIST / "meta.json").write_text(json.dumps({
        "package": "curlew", "version": "0.3.4", "wheel": "window.whl",
        "gridlib": gridlib.tag(),
    }, indent=2))
    print("built dist/window.whl (digest %s)" % sources_digest()[:12])


if __name__ == "__main__":
    main()
'''

CURLEW_PACKAGE = '''#!/usr/bin/env python3
"""Bundle the build artifact into a release archive for consumers."""
import json
import zipfile
from pathlib import Path

ROOT = Path.cwd()


def main():
    for name in ("window.whl", "meta.json", "checksums.txt"):
        if not (ROOT / name).is_file():
            raise SystemExit("missing build artifact: %s" % name)
    release = ROOT / "release"
    release.mkdir(exist_ok=True)
    with zipfile.ZipFile(release / "bundle.zip", "w",
                         zipfile.ZIP_DEFLATED) as zf:
        zf.write(ROOT / "window.whl", "window.whl")
        zf.write(ROOT / "meta.json", "meta.json")
    (release / "manifest.json").write_text(json.dumps({
        "bundle": "bundle.zip", "stages": ["build", "package"],
    }, indent=2))
    print("packaged release/bundle.zip")


if __name__ == "__main__":
    main()
'''

CURLEW_CHECK = '''#!/usr/bin/env python3
"""Consumer-side artifact gate for the curlew pipeline."""
import json
import zipfile
from pathlib import Path

ROOT = Path.cwd()


def main():
    for name in ("bundle.zip", "manifest.json"):
        if not (ROOT / name).is_file():
            raise SystemExit("missing artifact file: %s" % name)
    manifest = json.loads((ROOT / "manifest.json").read_text())
    assert manifest["bundle"] == "bundle.zip", manifest
    assert manifest["stages"] == ["build", "package"], manifest
    with zipfile.ZipFile(ROOT / "bundle.zip") as zf:
        names = set(zf.namelist())
    expected = {"window.whl", "meta.json"}
    missing = sorted(expected - names)
    if missing:
        raise SystemExit("bundle missing members: %s" % missing)
    print("artifact ok: bundle=%s" % sorted(names))


if __name__ == "__main__":
    main()
'''

CURLEW_INSTALL = """#!/usr/bin/env bash
# Install the curlew vendored dependency into .vendor (cache-miss only).
set -euo pipefail
mkdir -p .vendor
rm -rf .vendor/gridlib
cp -r ci/vendor/gridlib .vendor/gridlib
printf 'gridlib==0.4.1\\n' > .vendor/DEPENDENCIES
echo "vendored dependencies installed (gridlib 0.4.1)"
"""

CURLEW_GRID_INIT = '''"""Vendored gridlib dependency (org internal)."""
from .core import tag  # noqa: F401

__version__ = "0.4.1"
'''

CURLEW_GRID_CORE = '''"""gridlib: grid helpers the curlew build relies on."""


def tag():
    """Stable identity of this vendored dependency snapshot."""
    return "vendored-0.4.1"


def cell_bytes(cell):
    """UTF-8 bytes of a cell string (cheap sanity helper)."""
    return cell.encode("utf-8")
'''

CURLEW_HYGIENE = hygiene_test(
    {"dist", ".vendor", "release", "out", ".cache_deps", "build",
     "artifacts", ".deps"},
    extra_layout=("curlew", "ci", "tests"),
)

curlew_pipeline = pipeline(",\n".join([
    job_block("build", [
        restore("restore_cache", "vendor-{{hash:ci/vendor.lock}}", ".vendor"),
        run("install", "bash ci/install.sh", "cache_miss"),
        run("build", "python3 scripts/build.py"),
        upload("dist/"),
    ]),
    job_block("package", [
        download("build"),
        run("package", "python3 scripts/package.py"),
        upload("release/"),
    ]),
    job_block("verify", [
        download("package"),
        run("verify_artifact", "python3 scripts/check_artifact.py"),
        PYTEST_UNIT,
    ]),
]))

# ============================================================================
# avocet: statistical summaries. Jobs: build -> test.
# artifact dir "artifacts/", cache ".deps", lock "ci/requirements.lock".
# ============================================================================
AVOCET_CORE = '''"""Statistical summary helpers for the avocet probes."""
import math


def mean(seq):
    if not seq:
        raise ValueError("sequence is empty")
    return sum(seq) / len(seq)


def median(seq):
    if not seq:
        raise ValueError("sequence is empty")
    ordered = sorted(seq)
    n = len(ordered)
    mid = n // 2
    if n % 2:
        return ordered[mid]
    return (ordered[mid - 1] + ordered[mid]) / 2.0


def pct(seq, p):
    """Nearest-rank percentile (0 < p <= 100)."""
    if not seq:
        raise ValueError("sequence is empty")
    if not (0 < p <= 100):
        raise ValueError("percentile must be in (0, 100]")
    ordered = sorted(seq)
    rank = math.ceil(p / 100.0 * len(ordered))
    return ordered[rank - 1]


def bandwidth(size_bytes, seconds):
    """Effective throughput in bytes/second."""
    if size_bytes < 0 or seconds <= 0:
        raise ValueError("invalid size or duration")
    return size_bytes / seconds


def jitter(latencies):
    """Standard deviation of a latency sample set."""
    if len(latencies) < 2:
        raise ValueError("need at least two samples")
    avg = mean(latencies)
    return math.sqrt(sum((x - avg) ** 2 for x in latencies) /
                     (len(latencies) - 1))
'''

AVOCET_INIT = '''"""avocet: probe statistics for the observability service."""
from .core import mean, median, pct, bandwidth, jitter

__all__ = ["mean", "median", "pct", "bandwidth", "jitter"]
__version__ = "0.7.2"
'''

AVOCET_TESTS = '''"""Unit tests for the avocet statistics module."""
import math

import pytest

from avocet import bandwidth, jitter, mean, median, pct


def test_mean_of_samples():
    assert mean([1, 2, 3, 4]) == pytest.approx(2.5)


def test_mean_empty_raises():
    with pytest.raises(ValueError):
        mean([])


def test_median_odd_count():
    assert median([3, 1, 2]) == 2


def test_median_even_count():
    assert median([4, 1, 2, 3]) == pytest.approx(2.5)


def test_median_empty_raises():
    with pytest.raises(ValueError):
        median([])


def test_pct_nearest_rank():
    seq = [9, 1, 5, 7, 3]
    assert pct(seq, 50) == 5
    assert pct(seq, 100) == 9


def test_pct_invalid_raises():
    with pytest.raises(ValueError):
        pct([1, 2], 0)
    with pytest.raises(ValueError):
        pct([1, 2], 101)


def test_bandwidth_basic():
    assert bandwidth(1000, 0.5) == pytest.approx(2000.0)


def test_bandwidth_invalid_raises():
    with pytest.raises(ValueError):
        bandwidth(10, 0)


def test_jitter_single_sample_raises():
    with pytest.raises(ValueError):
        jitter([1])


def test_jitter_constant_series():
    assert jitter([5, 5, 5, 5]) == pytest.approx(0.0)


def test_jitter_positive():
    assert jitter([1, 2, 3, 4, 5]) == pytest.approx(math.sqrt(2.5))
'''

AVOCET_BUILD = '''#!/usr/bin/env python3
"""Assemble the avocet wheel and sidecar artifacts into artifacts/."""
import hashlib
import json
import os
import sys
import zipfile
from pathlib import Path

sys.path.insert(0, os.path.join(os.getcwd(), ".deps"))
import statlib  # noqa: E402  (vendored dependency from the install step)

ROOT = Path.cwd()
PKG = ROOT / "avocet"
OUT = ROOT / "artifacts"


def sources_digest():
    h = hashlib.sha256()
    for f in sorted(PKG.rglob("*.py")):
        h.update(f.relative_to(ROOT).as_posix().encode())
        h.update(f.read_bytes())
    return h.hexdigest()


def main():
    assert statlib.tag() == "vendored-2.0.0", "dependency mismatch"
    OUT.mkdir(exist_ok=True)
    wheel = OUT / "avocet.whl"
    with zipfile.ZipFile(wheel, "w", zipfile.ZIP_DEFLATED) as zf:
        for f in sorted(PKG.rglob("*.py")):
            zf.write(f, f.relative_to(PKG).as_posix())
        zf.writestr("VERSION", "0.7.2\\n")
    (OUT / "sources.sha256").write_text(sources_digest() + "\\n")
    (OUT / "metadata.json").write_text(json.dumps({
        "package": "avocet", "version": "0.7.2", "wheel": "avocet.whl",
        "statlib": statlib.tag(),
    }, indent=2))
    print("built artifacts/avocet.whl (digest %s)" % sources_digest()[:12])


if __name__ == "__main__":
    main()
'''

AVOCET_CHECK = '''#!/usr/bin/env python3
"""Consumer-side artifact gate for the avocet pipeline."""
import hashlib
import json
import zipfile
from pathlib import Path

ROOT = Path.cwd()


def sources_digest():
    h = hashlib.sha256()
    for f in sorted((ROOT / "avocet").rglob("*.py")):
        h.update(f.relative_to(ROOT).as_posix().encode())
        h.update(f.read_bytes())
    return h.hexdigest()


def main():
    for required in ("metadata.json", "avocet.whl", "sources.sha256"):
        if not (ROOT / required).is_file():
            raise SystemExit("missing artifact file: %s" % required)
    meta = json.loads((ROOT / "metadata.json").read_text())
    assert meta["package"] == "avocet", meta
    assert meta["statlib"] == "vendored-2.0.0", meta
    with zipfile.ZipFile(ROOT / "avocet.whl") as zf:
        names = set(zf.namelist())
    expected = {"__init__.py", "core.py", "VERSION"}
    missing = sorted(expected - names)
    if missing:
        raise SystemExit("wheel missing members: %s" % missing)
    got = (ROOT / "sources.sha256").read_text().strip()
    want = sources_digest()
    if got != want:
        raise SystemExit("sources digest mismatch: %s != %s" % (got, want))
    print("artifact ok: wheel ok digest=%s" % want[:12])


if __name__ == "__main__":
    main()
'''

AVOCET_INSTALL = """#!/usr/bin/env bash
# Install the avocet vendored dependency into .deps (cache-miss only).
set -euo pipefail
mkdir -p .deps
rm -rf .deps/statlib
cp -r ci/vendor/statlib .deps/statlib
printf 'statlib==2.0.0\\n' > .deps/DEPENDENCIES
echo "vendored dependencies installed (statlib 2.0.0)"
"""

AVOCET_STAT_INIT = '''"""Vendored statlib dependency (org internal)."""
from .core import tag  # noqa: F401

__version__ = "2.0.0"
'''

AVOCET_STAT_CORE = '''"""statlib: summary helpers the avocet build relies on."""


def tag():
    """Stable identity of this vendored dependency snapshot."""
    return "vendored-2.0.0"


def variance(seq):
    """Sample variance, or None for degenerate input."""
    if len(seq) < 2:
        return None
    avg = sum(seq) / len(seq)
    return sum((x - avg) ** 2 for x in seq) / (len(seq) - 1)
'''

AVOCET_HYGIENE = hygiene_test(
    {"artifacts", ".deps", "dist", ".vendor", "out", "release", "build",
     ".cache_deps"},
    extra_layout=("avocet", "ci", "tests"),
)

avocet_pipeline = pipeline(",\n".join([
    job_block("build", [
        restore("restore_cache", "cache-{{hash:ci/requirements.lock}}",
                ".deps"),
        run("install", "bash ci/install.sh", "cache_miss"),
        run("build", "python3 scripts/build.py"),
        upload("artifacts/"),
    ]),
    job_block("test", [
        download("build"),
        run("verify_artifact", "python3 scripts/check_artifact.py"),
        PYTEST_UNIT,
    ]),
]))


def run_pytest(repo: Path):
    env = dict(os.environ)
    env["PYTHONDONTWRITEBYTECODE"] = "1"
    r = subprocess.run(
        ["python3", "-m", "pytest", "-p", "no:cacheprovider", "-q", "tests/"],
        cwd=str(repo), capture_output=True, text=True, env=env)
    if r.returncode != 0:
        raise SystemExit("fixture tests not green: %s\n%s" % (repo, r.stdout))
    import re
    m = re.search(r"(\d+) passed", r.stdout)
    return int(m.group(1)) if m else 0


FIXTURES = {
    "wigeon": {
        "README.md": "# wigeon\n\nSound-scaling utilities. CI: `ci/pipeline.json` via the shared team runner.\n",
        "wigeon/__init__.py": WIGEON_INIT,
        "wigeon/core.py": WIGEON_CORE,
        "tests/test_core.py": WIGEON_TESTS,
        "tests/test_repo_hygiene.py": WIGEON_HYGIENE,
        "ci/pipeline.json": wigeon_pipeline,
        "ci/install.sh": WIGEON_INSTALL,
        "ci/constraints.lock": "sndlib==0.9.0\n",
        "ci/vendor/sndlib/__init__.py": WIGEON_SND_INIT,
        "ci/vendor/sndlib/core.py": WIGEON_SND_CORE,
        "scripts/build.py": WIGEON_BUILD,
        "scripts/check_artifact.py": WIGEON_CHECK,
    },
    "curlew": {
        "README.md": "# curlew\n\nFleet-tracker grid encoding. CI: `ci/pipeline.json` via the shared team runner.\n",
        "curlew/__init__.py": CURLEW_INIT,
        "curlew/core.py": CURLEW_CORE,
        "tests/test_core.py": CURLEW_TESTS,
        "tests/test_repo_hygiene.py": CURLEW_HYGIENE,
        "ci/pipeline.json": curlew_pipeline,
        "ci/install.sh": CURLEW_INSTALL,
        "ci/vendor.lock": "gridlib==0.4.1\n",
        "ci/vendor/gridlib/__init__.py": CURLEW_GRID_INIT,
        "ci/vendor/gridlib/core.py": CURLEW_GRID_CORE,
        "scripts/build.py": CURLEW_BUILD,
        "scripts/package.py": CURLEW_PACKAGE,
        "scripts/check_artifact.py": CURLEW_CHECK,
    },
    "avocet": {
        "README.md": "# avocet\n\nProbe statistics. CI: `ci/pipeline.json` via the shared team runner.\n",
        "avocet/__init__.py": AVOCET_INIT,
        "avocet/core.py": AVOCET_CORE,
        "tests/test_core.py": AVOCET_TESTS,
        "tests/test_repo_hygiene.py": AVOCET_HYGIENE,
        "ci/pipeline.json": avocet_pipeline,
        "ci/install.sh": AVOCET_INSTALL,
        "ci/requirements.lock": "statlib==2.0.0\n",
        "ci/vendor/statlib/__init__.py": AVOCET_STAT_INIT,
        "ci/vendor/statlib/core.py": AVOCET_STAT_CORE,
        "scripts/build.py": AVOCET_BUILD,
        "scripts/check_artifact.py": AVOCET_CHECK,
    },
}

for name, files in FIXTURES.items():
    repo = HIDDEN / name / "repo"
    if repo.exists():
        import shutil
        shutil.rmtree(repo)
    emit(repo, files)
    passed = run_pytest(repo)
    for leftover in repo.rglob("__pycache__"):
        shutil.rmtree(leftover, ignore_errors=True)
    manifest = suite_manifest(repo, passed)
    (HIDDEN / name / "suite_manifest.json").write_text(
        json.dumps(manifest, indent=2, sort_keys=True) + "\n")
    print("%s: %d tests pass, manifest written" % (name, passed))