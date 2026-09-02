#!/usr/bin/env python3
"""iris-ledge verifier helper.

Validates OUTDIR/result.json and OUTDIR/<frame> against a scenario JSON.

Usage: validate.py OUTDIR SCENARIO_JSON
Exit 0 + prints PASS on success; exit 1 + prints FAIL otherwise.
"""
import json
import sys


def main():
    outdir, scen_path = sys.argv[1], sys.argv[2]
    scen = json.load(open(scen_path))
    try:
        res = json.load(open(f"{outdir}/result.json"))
    except Exception as e:  # noqa: BLE001
        print(f"FAIL: no/corrupt result.json: {e}")
        return 1

    errs = []

    def chk(name, cond):
        if not cond:
            errs.append(name)

    W, H = scen["width"], scen["height"]
    chk("task", res.get("task") == "iris-ledge")
    chk("scenario", res.get("scenario") == scen.get("name"))
    chk("exit_status", res.get("exit_status") == scen["exit_status"])
    chk("program_exit", res.get("program_exit") == scen["exit_status"])
    chk("program_exit_ok", res.get("program_exit_ok") is True)
    chk("compiled_static", res.get("compiled_static") is True)
    chk("frame_dims", res.get("frame_width") == W and res.get("frame_height") == H)
    chk("frame_seed", res.get("frame_seed") == scen["seed"])
    chk("frame_bytes_field", res.get("frame_bytes") == 3 * W * H)
    chk("render_ok", res.get("render_ok") is True)
    chk("ports", res.get("monitor_port") == scen["monitor_port"]
        and res.get("serial_port") == scen["serial_port"])
    chk("qemu_alive", res.get("qemu_alive") is True)
    chk("background", res.get("background") is True)

    # Frame file itself must be a valid P6 PPM of the scenario dimensions with
    # non-uniform pixels (proves a real render completed, not a stub).
    fr = f"{outdir}/{scen['frame']}"
    try:
        raw = open(fr, "rb").read()
        parts = raw.split(b"\n", 3)
        if len(parts) < 4:
            raise ValueError("not enough header lines")
        magic, dims, mx, payload = parts[0].strip(), parts[1].split(), parts[2].strip(), parts[3]
        chk("frame_exists", True)
        chk("ppm_magic", magic == b"P6")
        chk("ppm_maxval", mx == b"255")
        chk("ppm_dims", len(dims) == 2 and int(dims[0]) == W and int(dims[1]) == H)
        chk("ppm_payload_len", len(payload) == 3 * W * H)
        base = payload[0]
        chk("non_uniform", any(payload[i] != base for i in range(0, 3 * W * H, 3)))
    except Exception as e:  # noqa: BLE001
        chk("frame_file", False)
        print(f"  frame error: {e}")

    if errs:
        print(f"FAIL: {errs}")
        return 1
    print("PASS")
    return 0


if __name__ == "__main__":
    sys.exit(main())
