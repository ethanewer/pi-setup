#!/bin/bash
# Verifier for raven-orchid ("Gryphon Relay" media-ingest + scientific-array
# pipeline).  Checks the visible-case deliverables, re-executes every
# deliverable program on fresh runs and on 4 hidden scenarios, and writes
# REWARD (0/1) to /logs/verifier/reward.txt.
set -u

mkdir -p /logs/verifier
reward=0
# Crash-proof: always leave a reward file behind, whatever happens.
trap 'echo "${reward:-0}" > /logs/verifier/reward.txt' EXIT

python3 - <<'PY'
import collections
import functools
import hashlib
import http.server
import json
import os
import re
import shutil
import signal
import socket
import subprocess
import sys
import threading
import time
import urllib.parse

import numpy as np
import tifffile

failures = []


def fail(msg):
    failures.append(msg)


# ---------------------------------------------------------------------------
# Pristine hashes of supplied visible fixtures (no-modify rule).
# ---------------------------------------------------------------------------
PINS = {
    "sources.txt": "982157f0413ad321c4d71e1983a68e4be99f9de48cecc260e4fe00866ac65a43",
    "serve_media.py": "41ce9f8406070458e9472b121d15a50d61aae6e1a044932e8c722ef135695757",
    "spectra_visible/settings.txt": "d509abb3550a8e720b11f44c7221097336869dfad1c3eb01e98c2e051c148901",
    "spectra_visible/magnitudes.npy": "841509329b7c7baf04b939dfc1adf1d501510156300900d17d73f5e2042bca10",
    "anim_visible/anim-spec.json": "0ec7bba2ddb0485eb083139fc808ae95360e550a3d1b978cdc7c3108b116dac6",
    "media_src/videos/relay-intro.mp4": "fe6690254147f030067566beb2843bc2ca1f393cf532e93af21fb0566b23810d",
    "media_src/videos/tower-report.mp4": "3d0f9cd25bc339b8e4cb4e274e661b2478163b7ee2f67c031f0c376288e0a378",
    "media_src/images/aurora.jpg": "beae3c922db5741a7ab4861ec33ecca6484adfb14e91aa6b15a8b79d495d728c",
    "media_src/images/harbor.png": "c930ab5fbe1d8f7840b7ef5838bb733fa29dc36ecfc0620e5771f94134cbdc6e",
    "media_src/audio/beacon.mp3": "044c87dfb16516efda39938390954ac98821a6161f1a409d31db0437c0b17b81",
    "tif_visible/frame-a.tif": "90620cc8356162a18649cb143e0c67b68cba59c073481229dcfee278060301be",
    "tif_visible/frame-b.tif": "80d84480070fc3edbeddc95e3e01858b01270fbcd2cd5ba2962d6fa978c87128",
    "tif_visible/frame-c.tif": "b2dd8c1627d50b3dc752b66e178a742e16848474afc03276c56e66beece2aecc",
}

DELIVERABLES = [
    "/app/ingest.py",
    "/app/stack.py",
    "/app/peaks.py",
    "/app/animation.py",
    "/app/media/manifest.json",
    "/app/transcript-raw.txt",
    "/app/transcript.txt",
    "/app/stack-shape.txt",
    "/app/peaks.csv",
    "/app/animation.json",
]

VISIBLE_PHRASES = [
    "the map says go left at two hundred meters",
    "please upload the red report by noon",
]


def sha(path):
    with open(path, "rb") as fh:
        return hashlib.sha256(fh.read()).hexdigest()


# ---------------------------------------------------------------------------
# no-modify + deliverable presence
# ---------------------------------------------------------------------------
for rel, pin in PINS.items():
    p = os.path.join("/app", rel)
    if not os.path.isfile(p):
        fail("no-modify: fixture %s missing" % rel)
    else:
        try:
            if sha(p) != pin:
                fail("no-modify: fixture %s was modified" % rel)
        except Exception as e:
            fail("no-modify: fixture %s unreadable (%s)" % (rel, e))

for d in DELIVERABLES:
    if not os.path.isfile(d):
        fail("deliverable missing: %s" % d)


# ---------------------------------------------------------------------------
# helpers
# ---------------------------------------------------------------------------
VIDEO_EXT = {".mp4", ".mov", ".m4v", ".webm", ".avi", ".mkv"}
IMAGE_EXT = {".jpg", ".jpeg", ".png", ".gif", ".webp", ".bmp"}
AUDIO_EXT = {".mp3", ".wav", ".m4a", ".aac", ".ogg", ".flac"}


def classify(rel):
    ext = os.path.splitext(os.path.basename(urllib.parse.urlparse(rel).path))[1].lower()
    if ext in VIDEO_EXT:
        return "video"
    if ext in IMAGE_EXT:
        return "image"
    if ext in AUDIO_EXT:
        return "audio"
    return "other"


def _kill_tcp_listener(port):
    # Fallback when fuser is unavailable: scan /proc/net/tcp for the LISTEN
    # socket bound to `port` and SIGKILL the process that owns it.
    try:
        with open("/proc/net/tcp", "r") as fh:
            lines = fh.readlines()[1:]
        for line in lines:
            parts = line.split()
            if len(parts) < 10 or parts[3] != "0A":  # 0A == LISTEN
                continue
            local = parts[1]
            if ":" not in local:
                continue
            if int(local.rsplit(":", 1)[1], 16) != port:
                continue
            inode = parts[9]
            for pid_dir in os.listdir("/proc"):
                if not pid_dir.isdigit():
                    continue
                fd_dir = os.path.join("/proc", pid_dir, "fd")
                try:
                    for fd in os.listdir(fd_dir):
                        try:
                            tgt = os.readlink(os.path.join(fd_dir, fd))
                        except OSError:
                            continue
                        if tgt == "socket:[%s]" % inode:
                            try:
                                os.kill(int(pid_dir), signal.SIGKILL)
                            except OSError:
                                pass
                            return
                except OSError:
                    continue
    except Exception:
        pass


def _free_port(port):
    # Kill any lingering listener (e.g. the agent's own media server) so the
    # canned verifier server can bind deterministically; ignore failures.
    # fuser ships with psmisc (installed in the image).
    try:
        subprocess.run(["fuser", "-k", "-n", "tcp", str(port)],
                       capture_output=True, timeout=5)
    except Exception:
        _kill_tcp_listener(port)
    time.sleep(0.3)


def start_server(directory, port):
    _free_port(port)
    handler = functools.partial(CannedHandler, directory=directory)
    httpd = None
    for _ in range(5):
        try:
            httpd = http.server.ThreadingHTTPServer(("127.0.0.1", port), handler)
            break
        except OSError:
            _free_port(port)
            time.sleep(0.5)
    if httpd is None:
        fail("cannot bind HTTP server on 127.0.0.1:%d after retries" % port)
        return None
    t = threading.Thread(target=httpd.serve_forever, daemon=True)
    t.start()
    for _ in range(80):
        try:
            s = socket.create_connection(("127.0.0.1", port), timeout=0.2)
            s.close()
            break
        except OSError:
            time.sleep(0.1)
    return httpd


def stop_server(httpd):
    try:
        httpd.shutdown()
        httpd.server_close()
    except Exception:
        pass


def run_ingest(urls_file, outdir, raw, clean):
    for p in (outdir, raw, clean):
        if os.path.isdir(p):
            shutil.rmtree(p)
        elif os.path.isfile(p):
            os.unlink(p)
    if not os.path.isfile("/app/ingest.py"):
        return None
    return subprocess.run(
        [sys.executable, "/app/ingest.py", urls_file, outdir, raw, clean],
        capture_output=True, text=True, timeout=240,
    )


def trans_dice(got, want):
    def toks(s):
        s = re.sub(r"[^a-z0-9 ]", " ", s.lower())
        return [t for t in re.split(r"\s+", s) if t]
    a = collections.Counter(toks(got))
    b = collections.Counter(toks(want))
    denom = sum(a.values()) + sum(b.values())
    if denom == 0:
        return 1.0
    return 2.0 * sum((a & b).values()) / denom


def normalize_clean(text):
    out = []
    for line in text.splitlines():
        s = re.sub(r"[^a-z0-9 ]", " ", line.lower())
        s = re.sub(r" +", " ", s).strip()
        out.append(s)
    return "\n".join(out)


def check_norm_consistency(raw_path, clean_path, label):
    """The cleaned file must equal the documented normalization of the raw
    transcript (the C-72ed normalization contract), and both must agree on
    line structure."""
    try:
        with open(raw_path, "r", encoding="utf-8") as fh:
            raw = fh.read()
        with open(clean_path, "r", encoding="utf-8") as fh:
            clean = fh.read()
    except Exception as e:
        fail("%s: cannot read transcript files (%s)" % (label, e))
        return
    if clean != normalize_clean(raw):
        fail("%s: transcript.txt is not the documented normalization of raw" % label)


def check_transcript(clean_path, expected_lines, label):
    try:
        with open(clean_path, "r", encoding="utf-8") as fh:
            lines = fh.read().split("\n")
    except Exception as e:
        fail("%s: cannot read transcript (%s)" % (label, e))
        return
    if lines and lines[-1] == "":
        lines.pop()
    if not expected_lines:
        if any(l.strip() for l in lines):
            fail("%s: expected empty transcript, got %r" % (label, lines))
        return
    if len(lines) != len(expected_lines):
        fail("%s: transcript line count %d != expected %d" % (label, len(lines), len(expected_lines)))
        return
    for i, (gl, el) in enumerate(zip(lines, expected_lines)):
        d = trans_dice(gl, el)
        if d < 0.7:
            fail("%s: transcript line %d similarity %.2f too low: %r vs %r"
                 % (label, i, d, gl, el))


def check_manifest_case(media_dir, urls, status_map, port, manifest_path, label):
    if not os.path.isfile(manifest_path):
        fail("%s: manifest missing" % label)
        return
    full = ["http://127.0.0.1:%d/%s" % (port, u) for u in urls]
    try:
        with open(manifest_path, "r") as fh:
            m = json.load(fh)
    except Exception as e:
        fail("%s: manifest unreadable (%s)" % (label, e))
        return
    entries = m.get("entries")
    if not isinstance(entries, list):
        fail("%s: manifest has no entries list" % label)
        return
    if len(entries) != len(full):
        fail("%s: manifest entry count %d != %d URLs" % (label, len(entries), len(full)))
        return
    expected = []
    for u, rel in zip(full, urls):
        exp_status = status_map.get(rel, 200)
        ext = os.path.splitext(os.path.basename(urllib.parse.urlparse(rel).path))[1].lower()
        exp_file = hashlib.sha256(u.encode("utf-8")).hexdigest() + ext if exp_status == 200 else ""
        expected.append((u, classify(rel), exp_status, exp_file))
    out_parent = os.path.dirname(manifest_path)
    for idx, (got, (u, kind, exp_status, exp_file)) in enumerate(zip(entries, expected)):
        rel_url = urllib.parse.urlparse(u).path.lstrip("/")
        if got.get("url") != u:
            fail("%s: entry url %r != %r" % (label, got.get("url"), u))
        if got.get("kind") != kind:
            fail("%s: entry kind %r != %r for %s" % (label, got.get("kind"), kind, u))
        if got.get("status") != exp_status:
            fail("%s: entry status %r != %r for %s" % (label, got.get("status"), exp_status, u))
        if got.get("file") != exp_file:
            fail("%s: entry file %r != %r for %s" % (label, got.get("file"), exp_file, u))
        if got.get("url_sha256") != hashlib.sha256(u.encode("utf-8")).hexdigest():
            fail("%s: url_sha256 mismatch for %s" % (label, u))
        if exp_status == 200:
            src = os.path.join(media_dir, *rel_url.split("/"))
            want_bsha = hashlib.sha256(open(src, "rb").read()).hexdigest()
            if got.get("bytes_sha256") != want_bsha:
                fail("%s: bytes_sha256 mismatch for %s" % (label, u))
            saved = os.path.join(out_parent, got.get("file", ""))
            if not os.path.isfile(saved):
                fail("%s: saved file missing %s" % (label, got.get("file")))
            elif hashlib.sha256(open(saved, "rb").read()).hexdigest() != want_bsha:
                fail("%s: saved file content differs for %s" % (label, u))
        else:
            if got.get("bytes_sha256", "") != "":
                fail("%s: bytes_sha256 not empty despite failed fetch for %s" % (label, u))
            fname = got.get("file", "")
            saved = os.path.join(out_parent, fname) if fname else None
            if saved and os.path.exists(saved):
                fail("%s: file saved despite failed fetch for %s" % (label, u))


# ---- stack ----
def ref_stack(tif_dir):
    names = sorted(n for n in os.listdir(tif_dir)
                   if n.lower().endswith((".tif", ".tiff")))
    arrs = []
    for n in names:
        a = np.asarray(tifffile.imread(os.path.join(tif_dir, n)))
        if a.ndim == 3:
            a = a[0]
        arrs.append(a)
    if not arrs:
        return "EMPTY", None
    if len({tuple(a.shape) for a in arrs}) != 1:
        return "INCOMPATIBLE", None
    stack = arrs[0] if len(arrs) == 1 else np.stack(arrs, axis=0)
    return ",".join(str(d) for d in stack.shape), stack


def run_stack(tif_dir, out_txt, out_npy, label):
    if not os.path.isfile("/app/stack.py"):
        fail("%s: /app/stack.py missing" % label)
        return
    r = subprocess.run(
        [sys.executable, "/app/stack.py", tif_dir, out_txt, out_npy],
        capture_output=True, text=True, timeout=120,
    )
    if r.returncode != 0:
        fail("%s: stack.py failed" % label)
        return
    if not os.path.isfile(out_txt):
        fail("%s: stack.py exited 0 but wrote no shape file" % label)
        return
    exp_shape, exp_arr = ref_stack(tif_dir)
    try:
        got = open(out_txt).read().strip()
    except Exception as e:
        fail("%s: stack shape file unreadable (%s)" % (label, e))
        return
    if got != exp_shape:
        fail("%s: stack shape %r != expected %r" % (label, got, exp_shape))
        return
    if exp_arr is not None:
        if not os.path.isfile(out_npy):
            fail("%s: stack.py exited 0 but wrote no .npy" % label)
            return
        try:
            saved = np.load(out_npy)
        except Exception as e:
            fail("%s: stack .npy unreadable (%s)" % (label, e))
            return
        if saved.shape != exp_arr.shape or not np.array_equal(saved, exp_arr):
            fail("%s: stacking produced wrong values" % label)


# ---- peaks ----
def ref_peaks(mag_path, k):
    try:
        a = np.load(mag_path, allow_pickle=False)
    except Exception:
        return "ERROR"
    if a.ndim == 1:
        a = a.reshape(1, -1)
    if a.ndim != 2:
        return "ERROR"
    if a.shape[1] == 0 or k <= 0:
        return [[i] for i in range(a.shape[0])]
    rows = []
    for i in range(a.shape[0]):
        row = np.asarray(a[i])
        # Degenerate frame (any non-finite value) yields no bins.
        if not np.all(np.isfinite(row)):
            rows.append([i])
            continue
        order = np.argsort(-row, kind="stable")
        rows.append([i] + [int(b) for b in order[:min(k, a.shape[1])]])
    return rows


def parse_peaks(path):
    if not os.path.isfile(path):
        return None
    rows = []
    with open(path) as fh:
        lines = [l.rstrip("\n") for l in fh]
    if not lines or lines[0].strip() != "frame,bins":
        return None
    for l in lines[1:]:
        if not l:
            continue
        rows.append([int(x) for x in l.split(",")])
    return rows


def run_peaks(mag, k, out, label):
    if not os.path.isfile("/app/peaks.py"):
        fail("%s: /app/peaks.py missing" % label)
        return
    r = subprocess.run(
        [sys.executable, "/app/peaks.py", mag, str(k), out],
        capture_output=True, text=True, timeout=120,
    )
    if r.returncode != 0:
        fail("%s: peaks.py failed" % label)
        return
    if not os.path.isfile(out):
        fail("%s: peaks.py exited 0 but wrote no CSV" % label)
        return
    ref = ref_peaks(mag, k)
    if ref == "ERROR":
        try:
            got_err = open(out).read().strip()
        except Exception as e:
            fail("%s: peaks output unreadable (%s)" % (label, e))
            return
        if got_err != "ERROR":
            fail("%s: expected ERROR output for unreadable array" % label)
        return
    got = parse_peaks(out)
    if got is None:
        fail("%s: peaks output lacks 'frame,bins' header" % label)
        return
    if got != ref:
        fail("%s: peaks rows mismatch\n got=%s\n ref=%s" % (label, got, ref))


# ---- animation ----
def run_anim(spec, out, label):
    if not os.path.isfile("/app/animation.py"):
        fail("%s: /app/animation.py missing" % label)
        return
    r = subprocess.run(
        [sys.executable, "/app/animation.py", spec, out],
        capture_output=True, text=True, timeout=120,
    )
    if r.returncode != 0:
        fail("%s: animation.py failed" % label)
        return
    if not os.path.isfile(out):
        fail("%s: animation.py exited 0 but wrote no output" % label)
        return
    try:
        with open(spec) as fh:
            sp = json.load(fh)
        timelines = sp["timelines"]
        valid = isinstance(timelines, list)
    except Exception:
        valid = False
    try:
        with open(out) as fh:
            go = json.load(fh)
    except Exception:
        fail("%s: animation output is not valid JSON" % label)
        return
    if not valid:
        if go.get("error") != "INVALID_SPEC" or go.get("timelines") != []:
            fail("%s: invalid spec not handled (got %r)" % (label, go))
        return
    gt = go.get("timelines")
    if not isinstance(gt, list):
        fail("%s: output has no timelines list" % label)
        return
    if len(gt) != len(timelines):
        fail("%s: timeline count %d != declared %d" % (label, len(gt), len(timelines)))
        return
    if gt and go.get("source") != "gryphon-anim":
        fail("%s: output source %r != 'gryphon-anim'" % (label, go.get("source")))
    for i, (tl, g) in enumerate(zip(timelines, gt)):
        if not isinstance(g, dict):
            fail("%s: timeline record %d is not an object" % (label, i))
            continue
        if isinstance(tl, dict):
            name = str(tl.get("name", "?"))
            v = tl.get("keyframe_count", 0)
            if isinstance(v, bool) or not isinstance(v, (int, float)):
                cnt = 0
            elif isinstance(v, float) and not v.is_integer():
                cnt = 0
            else:
                cnt = int(v)
            if cnt < 0:
                cnt = 0
        else:
            name, cnt = "?", 0
        if g.get("name") != name:
            fail("%s: timeline %d name %r != %r" % (label, i, g.get("name"), name))
        if g.get("declared_count") != cnt:
            fail("%s: timeline %d declared_count %r != %d"
                 % (label, i, g.get("declared_count"), cnt))
        kf = g.get("keyframes")
        if not isinstance(kf, dict):
            fail("%s: timeline %d has no keyframes" % (label, i))
            continue
        lens = {}
        for field in ("time", "translation", "rotation", "scale"):
            if field not in kf or not isinstance(kf[field], list):
                fail("%s: timeline %d missing %s" % (label, i, field))
                lens[field] = -1
            else:
                lens[field] = len(kf[field])
        if any(v != cnt for v in lens.values()):
            fail("%s: timeline %d array lengths %s != declared count %d"
                 % (label, i, lens, cnt))
        t = kf.get("time") or []
        try:
            incr_ok = all(isinstance(x, (int, float)) for x in t) and \
                all(t[j] < t[j + 1] for j in range(len(t) - 1))
        except Exception:
            incr_ok = False
        if not incr_ok:
            fail("%s: timeline %d time array is not strictly increasing" % (label, i))
        for field in ("translation", "scale"):
            for row in kf.get(field) or []:
                if not isinstance(row, list) or len(row) != 3:
                    fail("%s: timeline %d %s row not length 3" % (label, i, field))
                else:
                    for x in row:
                        if not isinstance(x, (int, float)):
                            fail("%s: timeline %d %s has non-numeric value" % (label, i, field))
        for x in kf.get("rotation") or []:
            if not isinstance(x, (int, float)):
                fail("%s: timeline %d rotation has non-numeric value" % (label, i))


class CannedHandler(http.server.SimpleHTTPRequestHandler):
    def log_message(self, *args):
        pass


# ---------------------------------------------------------------------------
# 1. Visible-case: re-execute every deliverable and compare against the ship.
# ---------------------------------------------------------------------------
os.makedirs("/tmp/raven_vis", exist_ok=True)
httpd = start_server("/app/media_src", 8787)
if httpd is None:
    fail("visible: could not start media server on 8787")
else:
    try:
        r = run_ingest("/app/sources.txt", "/tmp/raven_vis_media", "/tmp/raven_vis_raw.txt", "/tmp/raven_vis_clean.txt")
        if r is None:
            fail("visible: /app/ingest.py missing")
        elif r.returncode != 0:
            fail("visible ingest re-run failed: %s" % r.stderr[-400:])
        else:
            fresh_manifest = "/tmp/raven_vis_media/manifest.json"
            if not os.path.isfile("/app/media/manifest.json"):
                fail("visible: deliverable missing /app/media/manifest.json")
            elif not os.path.isfile(fresh_manifest):
                fail("visible: fresh re-run produced no manifest.json")
            else:
                with open("/app/media/manifest.json") as fh:
                    shipped = json.load(fh)
                with open(fresh_manifest) as fh:
                    fresh = json.load(fh)
                if shipped != fresh:
                    fail("visible: /app/media/manifest.json differs from fresh re-run")
            if os.path.isfile("/app/transcript-raw.txt"):
                if not os.path.isfile("/tmp/raven_vis_raw.txt"):
                    fail("visible: fresh re-run produced no raw transcript")
                elif open("/app/transcript-raw.txt").read() != open("/tmp/raven_vis_raw.txt").read():
                    fail("visible: /app/transcript-raw.txt differs from fresh re-run")
            if os.path.isfile("/app/transcript.txt"):
                if not os.path.isfile("/tmp/raven_vis_clean.txt"):
                    fail("visible: fresh re-run produced no clean transcript")
                elif open("/app/transcript.txt").read() != open("/tmp/raven_vis_clean.txt").read():
                    fail("visible: /app/transcript.txt differs from fresh re-run")
            src_urls = []
            for line in open("/app/sources.txt"):
                line = line.strip()
                if line:
                    src_urls.append(urllib.parse.urlparse(line).path.lstrip("/"))
            check_manifest_case("/app/media_src", src_urls, {}, 8787, "/app/media/manifest.json", "visible-manifest")
            if os.path.isfile("/app/transcript.txt") and os.path.isfile("/app/transcript-raw.txt"):
                check_transcript("/app/transcript.txt", VISIBLE_PHRASES, "visible-transcript")
                check_norm_consistency("/app/transcript-raw.txt", "/app/transcript.txt", "visible-transcript")
            else:
                fail("visible: transcript deliverables missing")
    finally:
        stop_server(httpd)

run_stack("/app/tif_visible", "/tmp/raven_vis_shape.txt", "/tmp/raven_vis_stack.npy", "visible-stack")
exp_shape, _ = ref_stack("/app/tif_visible")
if os.path.isfile("/app/stack-shape.txt") and open("/app/stack-shape.txt").read().strip() != exp_shape:
    fail("visible: /app/stack-shape.txt mismatch (got %r, want %r)"
         % (open("/app/stack-shape.txt").read().strip(), exp_shape))

vis_k = None
with open("/app/spectra_visible/settings.txt") as fh:
    for line in fh:
        line = line.strip()
        if line.startswith("k="):
            vis_k = int(line[2:])
if vis_k is None:
    fail("visible: settings.txt has no k=")
else:
    run_peaks("/app/spectra_visible/magnitudes.npy", vis_k, "/tmp/raven_vis_peaks.csv", "visible-peaks")
if not os.path.isfile("/app/peaks.csv"):
    fail("visible: deliverable missing /app/peaks.csv")
elif not os.path.isfile("/tmp/raven_vis_peaks.csv"):
    fail("visible-peaks: fresh re-run produced no /tmp/raven_vis_peaks.csv")
else:
    with open("/app/peaks.csv") as fh:
        a = fh.read().rstrip()
    with open("/tmp/raven_vis_peaks.csv") as fh:
        b = fh.read().rstrip()
    if a != b:
        fail("visible: /app/peaks.csv differs from fresh re-run")

run_anim("/app/anim_visible/anim-spec.json", "/tmp/raven_vis_anim.json", "visible-anim")
try:
    with open("/app/animation.json") as fh:
        sa = json.load(fh)
    with open("/tmp/raven_vis_anim.json") as fh:
        sb = json.load(fh)
    if sa != sb:
        fail("visible: /app/animation.json differs from fresh re-run")
except Exception as e:
    fail("visible: animation.json unreadable (%s)" % e)

# ---------------------------------------------------------------------------
# 2. Hidden scenarios.
# ---------------------------------------------------------------------------
hidden = "/tests/hidden"
if not os.path.isdir(hidden):
    fail("no hidden cases directory")
else:
    cases = sorted(os.listdir(hidden))
    if len(cases) < 2:
        fail("too few hidden cases")
    for ci, c in enumerate(cases):
        base = os.path.join(hidden, c)
        if not os.path.isdir(base):
            continue
        exp_path = os.path.join(base, "expected.json")
        if not os.path.isfile(exp_path):
            fail("hidden %s: missing expected.json" % c)
            continue
        with open(exp_path) as fh:
            exp = json.load(fh)
        label = "hidden-%s" % c

        media_dir = os.path.join(base, "media")
        if os.path.isdir(media_dir):
            port = 8830 + ci
            httpd = start_server(media_dir, port)
            if httpd is None:
                fail("%s: could not start media server on %d" % (label, port))
            else:
                try:
                    urls = exp.get("urls", [])
                    full = ["http://127.0.0.1:%d/%s" % (port, u) for u in urls]
                    blob = "\n".join(full)
                    if exp.get("blank_line") and len(full) > 0:
                        blob = full[0] + "\n\n" + "\n".join(full[1:])
                    urls_file = "/tmp/raven_%s_urls.txt" % c
                    with open(urls_file, "w") as fh:
                        fh.write(blob + "\n")
                    outdir = "/tmp/raven_%s_media" % c
                    raw = "/tmp/raven_%s_raw.txt" % c
                    clean = "/tmp/raven_%s_clean.txt" % c
                    r = run_ingest(urls_file, outdir, raw, clean)
                    if r is None:
                        fail("%s: /app/ingest.py missing" % label)
                    elif r.returncode != 0:
                        fail("%s: ingest.py failed: %s" % (label, r.stderr[-400:]))
                    else:
                        manifest_path = os.path.join(outdir, "manifest.json")
                        if not os.path.isfile(manifest_path):
                            fail("%s: ingest produced no manifest.json" % label)
                        else:
                            check_manifest_case(media_dir, urls, exp.get("status", {}), port,
                                                manifest_path, label)
                        if os.path.isfile(clean) and os.path.isfile(raw):
                            check_transcript(clean, exp.get("transcript", []), label)
                            check_norm_consistency(raw, clean, label)
                        else:
                            fail("%s: ingest produced no transcript files" % label)
                finally:
                    stop_server(httpd)

        tif_dir = os.path.join(base, "tifs")
        if os.path.isdir(tif_dir):
            run_stack(tif_dir, "/tmp/raven_%s_shape.txt" % c, "/tmp/raven_%s_stack.npy" % c, label)

        mag = os.path.join(base, "magnitudes.npy")
        if os.path.isfile(mag):
            run_peaks(mag, exp.get("k", 3), "/tmp/raven_%s_peaks.csv" % c, label)

        spec = os.path.join(base, "anim-spec.json")
        if os.path.isfile(spec):
            run_anim(spec, "/tmp/raven_%s_anim.json" % c, label)

print("verify failures: %d" % len(failures))
for f in failures:
    print(" - %s" % f)
sys.exit(1 if failures else 0)
PY

rc=$?
if [ "$rc" -eq 0 ]; then reward=1; fi
echo "$reward" > /logs/verifier/reward.txt
exit 0
