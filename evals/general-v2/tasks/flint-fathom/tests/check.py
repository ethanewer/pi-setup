#!/usr/bin/env python3
"""Verifier for flint-fathom (executes-deliverable).

Re-executes the two real programs and byte-checks the emitted files:

  * /app/source.mp4 is a playable mp4 (180 frames); /app/fetch_media.sh is
    executable and performs a real HTTP re-download onto a fresh path.
  * /app/clip.mp4 is the 60-frame trailing tail, and running detection on it
    must reproduce /app/events.json exactly.
  * /app/detect_frames.py on three hidden jump clips returns the configured
    takeoff/landing indices (incl. null-on-never-landing and null-on-no-jump).
  * /app/extract_commands.py reproduces /app/commands.txt and returns the exact
    ordered one-per-line list on the fixture and a hidden transcript.

Exits 0 iff every check passes (tests/test.sh writes the reward). Uses only the
Python standard library plus image tooling from the container (opencv, ffmpeg).
"""
import json
import os
import subprocess
import sys
import time

import cv2

APP = "/app"
HIDDEN = "/tests/hidden"

CLIP_EXPECT = {"takeoff_frame": 30, "landing_frame": 51}
SOURCE_FRAMES = 180
CLIP_FRAMES = 60

HIDDEN_VIDEOS = {
    "v_a.mp4": {"takeoff_frame": 40, "landing_frame": 101},
    "v_b.mp4": {"takeoff_frame": 30, "landing_frame": None},
    "v_c.mp4": {"takeoff_frame": None, "landing_frame": None},
}

EXPECT_MAIN_CMDS = [
    "setrunway lane=3",
    "armTakeoff sensor=optic",
    "startFlight capture",
    "markTakeoff frame=auto",
    "markLanding frame=manual pos=700",
    "stopGathering keep=summary",
]

CHECKS = []


def check(name, ok, detail=""):
    CHECKS.append((name, bool(ok)))
    print(("PASS " if ok else "FAIL ") + name + ((" | " + detail) if detail else ""))


def frame_count(path):
    cap = cv2.VideoCapture(path)
    n = 0
    while True:
        ok, _ = cap.read()
        if not ok:
            break
        n += 1
    cap.release()
    return n


def lines(text):
    return [l for l in text.split("\n") if l.strip()]


def detect_on(video):
    try:
        subprocess.run(["python3", f"{APP}/detect_frames.py", video,
                        "/tmp/detect_out.json"], check=True, capture_output=True)
        with open("/tmp/detect_out.json") as fh:
            return json.load(fh)
    except Exception as e:
        return {"takeoff_frame": "ERR", "landing_frame": repr(e)}


def extract_on(transcript, outfile=None):
    args = ["python3", f"{APP}/extract_commands.py", transcript]
    if outfile:
        args.append(outfile)
    return subprocess.run(args, check=True, capture_output=True,
                          text=True).stdout


def main():
    src = f"{APP}/source.mp4"
    clip = f"{APP}/clip.mp4"

    # ---- top-level deliverables exist ----------------------------------
    for f in ["fetch_media.sh", "source.mp4", "clip.mp4", "detect_frames.py",
              "events.json", "extract_commands.py", "commands.txt"]:
        check(f"exist {f}", os.path.isfile(f"{APP}/{f}"))

    # ---- source + fetch -------------------------------------------------
    if os.path.isfile(src):
        check("source.mp4 playable 180 frames",
              frame_count(src) == SOURCE_FRAMES, f"frames={frame_count(src)}")

    fm = f"{APP}/fetch_media.sh"
    if os.path.isfile(fm):
        check("fetch_media.sh executable", os.access(fm, os.X_OK))
        proc = subprocess.Popen(
            ["python3", "-m", "http.server", "8788", "--bind", "127.0.0.1",
             "--directory", "/app/fixtures"],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        try:
            time.sleep(1.5)
            fresh = "/tmp/fresh_source.mp4"
            subprocess.run(
                ["bash", fm, "http://127.0.0.1:8788/media_source.mp4", fresh],
                check=True, capture_output=True)
            ok = os.path.isfile(fresh) and 1 < frame_count(fresh) <= SOURCE_FRAMES
            check("fetch_media.sh real HTTP re-download", ok)
        except Exception as e:
            check("fetch_media.sh real HTTP re-download", False, str(e))
        finally:
            proc.kill()

    # ---- detection ------------------------------------------------------
    try:
        code = open(f"{APP}/detect_frames.py").read()
        check("detect_frames.py decodes video",
              "VideoCapture" in code and "cv2" in code)
    except OSError:
        pass

    if os.path.isfile(clip):
        check("clip.mp4 trailing=60 frames",
              frame_count(clip) == CLIP_FRAMES, f"frames={frame_count(clip)}")

    if os.path.isfile(f"{APP}/events.json"):
        try:
            with open(f"{APP}/events.json") as fh:
                got = json.load(fh)
            check("events.json schema",
                  set(got) == {"takeoff_frame", "landing_frame"}, str(got))
            check("events.json == clip expected", got == CLIP_EXPECT, str(got))
        except Exception as e:
            check("events.json parse", False, str(e))

    check("detect re-run on clip == expected",
          detect_on(clip) == CLIP_EXPECT)
    for vid, want in HIDDEN_VIDEOS.items():
        vp = os.path.join(HIDDEN, vid)
        if os.path.isfile(vp):
            check(f"hidden {vid}", detect_on(vp) == want, str(detect_on(vp)))
        else:
            check(f"hidden {vid}", False, "missing")

    # ---- transcript -----------------------------------------------------
    ex = f"{APP}/extract_commands.py"
    if os.path.isfile(ex):
        prev = ""
        if os.path.isfile(f"{APP}/commands.txt"):
            prev = open(f"{APP}/commands.txt", encoding="utf-8").read()
        check("commands.txt one-per-line",
              bool(prev) and all(l != "" for l in prev.split("\n")[:-1]))
        check("commands.txt exact list", lines(prev) == EXPECT_MAIN_CMDS)
        check("main extract reproduces commands.txt",
              extract_on(f"{APP}/fixtures/transcript.txt") == prev)

        hsrc = os.path.join(HIDDEN, "h_transcript.txt")
        hwant = lines(open(os.path.join(HIDDEN, "h_commands_expected.txt"),
                           encoding="utf-8").read())
        check("hidden transcript extract",
              lines(extract_on(hsrc)) == hwant,
              str(lines(extract_on(hsrc))))


def extract_on(transcript):
    return extract(transcript)


def extract(transcript, outfile=None):
    return extract_via(f"{APP}/extract_commands.py", transcript, outfile)


def extract_via(exe, transcript, outfile=None):
    args = ["python3", exe, transcript]
    if outfile:
        args.append(outfile)
    return subprocess.run(args, check=True, capture_output=True, text=True).stdout


if __name__ == "__main__":
    try:
        main()
    except Exception as e:
        import traceback
        print("FAIL harness error")
        traceback.print_exc()
    failed = any(not ok for _, ok in CHECKS)
    print(f"TOTAL_CHECKS {len(CHECKS)} FAILED "
          f"{sum(1 for _, ok in CHECKS if not ok)}")
    sys.exit(1 if failed else 0)