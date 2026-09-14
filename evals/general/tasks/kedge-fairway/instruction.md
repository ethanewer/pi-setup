# Zero-byte downloads are quietly recorded as successes

## Situation

`/app/src` is a shallow, pinned clone of the gallery-dl project
(`https://github.com/mikf/gallery-dl`), checked out at upstream commit
`80a402f2673d0c8b5e5204be06fab706ae89e76a`, and installed from that tree in
editable (development) mode, so the code you import is exactly the checked-out
Python source. Python 3.12 and pytest are installed. There is **no network**
at trial time: everything you need is already in the image; `pip` and
`git fetch` will not work. Loopback (`127.0.0.1`) works.

## The bug

When a download job hits a URL whose response has a **zero-byte body**
(`Content-Length: 0`), gallery-dl treats the download as a success: it writes
an empty file to disk, records the download as completed (for example in the
run's archive database), and prints no warning. Several such URLs in one batch
— broken mirrors, aborted transfers, directories served as files — end up
silently filling the output directory and the archive with empty files.

Expected behaviour: when a response carries a zero-byte body, the download
must be treated as **failed**. The downloader should warn, must not write the
file, and must not report success. Every other download must keep behaving
exactly as before.

## What you need to do

1. **Write your own failing reproduction first, before changing anything**:
   create `/app/reproduce.py`, a self-contained script that demonstrates the
   problem against the current checkout. The script must drive a real download
   of a zero-byte response through the checked-out downloader code — a local
   HTTP server on `127.0.0.1` started inside the script works; that is not a
   network access. Use it to watch the failure before you fix anything.

   Contract: `python3 /app/reproduce.py` must exit `0` exactly when the
   checkout's downloader correctly refuses the zero-byte download (a warning
   is emitted, no success is reported, no file is written), and must exit
   non-zero exactly when the downloader silently succeeds. It must terminate
   on its own, without user input, within 120 seconds.

2. **Fix the bug in the checked-out tree at `/app/src`** so that zero-byte
   responses are refused with a warning and are never written to disk and
   never reported as success, while all other downloads keep working.

3. Drive your work with the project's own test runner:

```
cd /app/src && python3 -m pytest test/test_downloader.py -q -p no:cacheprovider
```

## Constraints

- No network. Everything needed is installed already.
- The deliverables are the repaired `/app/src` checkout and `/app/reproduce.py`.
- Change only what the fix requires, in place. Do not rewrite history, add or
  fetch remotes, or change build files. Files under `/opt/golden`, `/tests`
  and `/solution` are harness-owned; do not touch them.
- Run your reproduction with `python3 /app/reproduce.py` from any directory;
  the verifier does the same.

## What the verifier checks

1. The tree is still at commit `80a402f2673d0c8b5e5204be06fab706ae89e76a`, the
   upstream fix is not reachable from the working clone, and the repair
   touches only the minimal source surface.
2. Your own reproduction is run against the pristine (unfixed) source and
   against your repaired tree: it must fail on the former and pass on the
   latter.
3. The project's own regression test for this bug — the full downloader test
   file as it exists in the upstream fix commit, extracted at image build time
   into `/opt/golden` — passes against your repaired tree.
4. The project's own downloader test suite in the checkout still passes,
   proving the fix broke nothing else.
5. Hidden cases over inputs the upstream test does not use pass: a zero-byte
   body served with an explicit content type and filename extension, and a
   zero-length response arriving through the 206 Partial Content branch.

Deliverables: the repaired `/app/src` tree and `/app/reproduce.py`.