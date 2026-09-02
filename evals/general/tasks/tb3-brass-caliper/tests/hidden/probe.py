#!/usr/bin/env python3
"""tb3-brass-caliper hidden probe.

Executes the deliverables:
  - imports the deliverable /app/cadmodel.py;
  - independently recomputes the documented contract for the visible spec
    (/app/specs/spacer_spec.json) and for every hidden spec in
    /tests/hidden/specs.json;
  - compares validate_spec under three limits variants, the geometry
    functions, and build_report against the agent's module;
  - re-checks the deliverable /app/spacer_report.json against the
    verifier's own recompute.

The reference implementation below is written from the documented
conventions only (angles, overlap handling, rounding, sort order) and is
independent of the agent's module. Exits 1 on any mismatch.
"""
import json
import math
import sys

FAILURES = []


def fail(msg):
    FAILURES.append(msg)


# --------------------------------------------------------------------------
# Independent reference implementation (documented conventions only).
# --------------------------------------------------------------------------
LIMITS_DEFAULT = {"min_wall_margin": 2.0, "min_hole_gap": 1.5, "min_bore_gap": 2.5}
LIMITS_SLACK = {"min_wall_margin": 1.0, "min_hole_gap": 0.5, "min_bore_gap": 1.0}
LIMITS_TIGHT = {"min_wall_margin": 3.0, "min_hole_gap": 8.0, "min_bore_gap": 5.0}
LIMITS_VARIANTS = [LIMITS_DEFAULT, LIMITS_SLACK, LIMITS_TIGHT]

NUMERIC_FIELDS = ["bore_d", "flange_d", "thickness",
                  "bolt_circle_d", "bolt_hole_d", "density"]
FIELD_TAG = {"bore_d": "BORE_D", "flange_d": "FLANGE_D",
             "thickness": "THICKNESS", "bolt_circle_d": "BOLT_CIRCLE_D",
             "bolt_hole_d": "BOLT_HOLE_D", "density": "DENSITY"}


def ref_is_real(v):
    return (isinstance(v, (int, float)) and not isinstance(v, bool)
            and math.isfinite(float(v)))


def ref_wellformed(spec):
    if not isinstance(spec, dict):
        return False
    for k in NUMERIC_FIELDS:
        if not ref_is_real(spec.get(k)) or spec[k] <= 0:
            return False
    n = spec.get("bolt_count")
    return isinstance(n, int) and not isinstance(n, bool) and n >= 1


def ref_centers(spec):
    r = spec["bolt_circle_d"] / 2.0
    n = spec["bolt_count"]
    return [(r * math.cos(2.0 * math.pi * i / n),
             r * math.sin(2.0 * math.pi * i / n))
            for i in range(n)]


def ref_clearance(spec):
    n = spec["bolt_count"]
    c = ref_centers(spec)
    cands = []
    if n >= 2:
        for i in range(n):
            x1, y1 = c[i]
            x2, y2 = c[(i + 1) % n]
            cands.append(math.hypot(x1 - x2, y1 - y2) - spec["bolt_hole_d"])
    cands.append(spec["bolt_circle_d"] / 2.0
                 - spec["bore_d"] / 2.0 - spec["bolt_hole_d"] / 2.0)
    cands.append(spec["flange_d"] / 2.0
                 - spec["bolt_circle_d"] / 2.0 - spec["bolt_hole_d"] / 2.0)
    return min(cands)


def ref_area(spec):
    return ((math.pi / 4.0)
            * (spec["flange_d"] ** 2 - spec["bore_d"] ** 2
               - spec["bolt_count"] * spec["bolt_hole_d"] ** 2))


def ref_volume(spec):
    return spec["thickness"] * ref_area(spec)


def ref_mass(spec):
    return ref_volume(spec) * spec["density"] / 1000.0


def ref_validate(spec, limits):
    codes = set()
    for k in NUMERIC_FIELDS:
        if k not in spec or not ref_is_real(spec[k]):
            codes.add("INVALID_" + FIELD_TAG[k])
        elif spec[k] <= 0:
            codes.add("NONPOSITIVE_" + FIELD_TAG[k])
    n = spec.get("bolt_count")
    if "bolt_count" not in spec or not isinstance(n, int) or isinstance(n, bool) or n < 1:
        codes.add("BOLT_COUNT_INVALID")
    if ref_wellformed(spec):
        bd, fd = spec["bore_d"], spec["flange_d"]
        bcd, bhd = spec["bolt_circle_d"], spec["bolt_hole_d"]
        if bcd <= bd:
            codes.add("BORE_NOT_INSIDE_BOLT_CIRCLE")
        if bcd + bhd > fd:
            codes.add("HOLE_OUTSIDE_FLANGE")
        if (bcd - bd - bhd) / 2.0 < limits["min_bore_gap"]:
            codes.add("HOLE_TOO_CLOSE_TO_BORE")
        if (fd - bcd - bhd) / 2.0 < limits["min_wall_margin"]:
            codes.add("HOLE_TOO_CLOSE_TO_FLANGE_EDGE")
        if n >= 2:
            c = ref_centers(spec)
            min_gap = min(math.hypot(c[i][0] - c[(i + 1) % n][0],
                                     c[i][1] - c[(i + 1) % n][1]) - bhd
                          for i in range(n))
            if min_gap < limits["min_hole_gap"]:
                codes.add("ADJACENT_HOLES_TOO_CLOSE")
    return sorted(codes)


def ref_report(spec, limits):
    codes = ref_validate(spec, limits)
    return {
        "spec": dict(spec),
        "limits": dict(limits),
        "bolt_hole_centers": [[round(x, 4), round(y, 4)]
                              for x, y in ref_centers(spec)],
        "min_edge_clearance_mm": round(ref_clearance(spec), 4),
        "annular_area_mm2": round(ref_area(spec), 4),
        "solid_volume_mm3": round(ref_volume(spec), 4),
        "mass_g": round(ref_mass(spec), 4),
        "violations": codes,
        "valid": not codes,
    }


# --------------------------------------------------------------------------
# Comparison helpers (tolerant of last-ulp implementation drift, strict on
# the documented 4-decimal rounding and on the code/schema texts).
# --------------------------------------------------------------------------
def close(a, b, tol=1e-9):
    return abs(a - b) <= tol * max(1.0, abs(b))


def num_ok(a, b):
    return close(a, b) and round(a, 4) == round(b, 4)


def report_ok(got, want):
    """Field-wise comparison of two report dicts."""
    if not isinstance(got, dict):
        return False
    if set(got.keys()) != set(want.keys()):
        return False
    for key, wv in want.items():
        if key not in got:
            return False
        gv = got[key]
        if key == "spec" or key == "limits":
            if gv != wv:
                return False
        elif key == "bolt_hole_centers":
            if not isinstance(gv, list) or len(gv) != len(wv):
                return False
            for ga, wa in zip(gv, wv):
                if (not isinstance(ga, (list, tuple)) or len(ga) != 2
                        or not num_ok(ga[0], wa[0]) or not num_ok(ga[1], wa[1])):
                    return False
        elif key == "violations":
            if gv != wv:
                return False
        elif key == "valid":
            if gv != wv:
                return False
        else:
            if not num_ok(gv, wv):
                return False
    return True


def main():
    # --- 1. Visible spec fixture must be pristine (byte compare). ---------
    try:
        with open("/opt/pristine/spacer_spec.json", "rb") as fh:
            pristine = fh.read()
        with open("/app/specs/spacer_spec.json", "rb") as fh:
            current = fh.read()
        if current != pristine:
            fail("visible spec fixture /app/specs/spacer_spec.json was modified")
    except OSError as exc:
        fail("cannot compare visible spec fixture: %s" % exc)

    # --- 2. Import the deliverable module. --------------------------------
    sys.path.insert(0, "/app")
    try:
        import cadmodel as agent
    except Exception as exc:
        fail("cannot import deliverable /app/cadmodel.py: %r" % exc)
        agent = None

    with open("/app/specs/spacer_spec.json") as fh:
        visible = json.load(fh)
    ref_vis = ref_report(visible, LIMITS_DEFAULT)

    # --- 3. /app/spacer_report.json must equal the verifier's recompute of
    #        the visible spec. ---------------------------------------------
    try:
        with open("/app/spacer_report.json") as fh:
            got_vis = json.load(fh)
        if not report_ok(got_vis, ref_vis):
            fail("deliverable /app/spacer_report.json does not match the "
                 "verifier's recompute of /app/specs/spacer_spec.json")
    except OSError as exc:
        fail("cannot read deliverable /app/spacer_report.json: %s" % exc)
    except ValueError as exc:
        fail("deliverable /app/spacer_report.json is not valid JSON: %s" % exc)

    if agent is None:
        return 1

    # --- 4. Visible spec through the module functions. --------------------
    try:
        if not report_ok(agent.build_report(visible, LIMITS_DEFAULT), ref_vis):
            fail("module build_report mismatch on the visible spec")
    except Exception as exc:
        fail("module build_report on visible spec raised: %r" % exc)
    for fn, ref_fn in (("bolt_hole_centers", ref_centers),
                       ("min_edge_clearance", ref_clearance),
                       ("annular_area", ref_area),
                       ("solid_volume", ref_volume),
                       ("mass_grams", ref_mass)):
        try:
            got = getattr(agent, fn)(visible)
        except Exception as exc:
            fail("module %s on visible spec raised: %r" % (fn, exc))
            continue
        want = ref_fn(visible)
        if fn == "bolt_hole_centers":
            if (not isinstance(got, list) or len(got) != len(want)
                    or any(not isinstance(p, (list, tuple)) or len(p) != 2
                           or not num_ok(p[0], q[0]) or not num_ok(p[1], q[1])
                           for p, q in zip(got, want))):
                fail("module bolt_hole_centers mismatch on visible spec")
        elif not num_ok(got, want):
            fail("module %s mismatch on visible spec: got %r want %r"
                 % (fn, got, want))
    try:
        if agent.validate_spec(visible, LIMITS_DEFAULT) != ref_validate(visible, LIMITS_DEFAULT):
            fail("module validate_spec mismatch on visible spec")
    except Exception as exc:
        fail("module validate_spec on visible spec raised: %r" % exc)

    # --- 5. Hidden specs. -------------------------------------------------
    with open("/tests/hidden/specs.json") as fh:
        hidden = json.load(fh)
    if not isinstance(hidden, list) or not hidden:
        fail("no hidden specs present")

    for idx, spec in enumerate(hidden):
        label = "hidden[%d]" % idx
        for j, lim in enumerate(LIMITS_VARIANTS):
            want = ref_validate(spec, lim)
            try:
                got = agent.validate_spec(spec, lim)
            except Exception as exc:
                fail("%s validate_spec limits[%d] raised: %r" % (label, j, exc))
                continue
            if got != want:
                fail("%s validate_spec limits[%d] mismatch: got %r want %r"
                     % (label, j, got, want))
        if not ref_wellformed(spec):
            # malformed spec: validate_spec compared above; build_report must
            # refuse to compute geometry
            try:
                agent.build_report(spec, LIMITS_DEFAULT)
                fail("%s build_report should raise ValueError on a malformed "
                     "spec" % label)
            except ValueError:
                pass
            except Exception as exc:
                fail("%s build_report raised the wrong exception type: %r"
                     % (label, exc))
            continue

        try:
            got_c = agent.bolt_hole_centers(spec)
            want_c = ref_centers(spec)
            if (not isinstance(got_c, list) or len(got_c) != len(want_c)
                    or any(not isinstance(p, (list, tuple)) or len(p) != 2
                           or not num_ok(p[0], q[0]) or not num_ok(p[1], q[1])
                           for p, q in zip(got_c, want_c))):
                fail("%s bolt_hole_centers mismatch" % label)
        except Exception as exc:
            fail("%s bolt_hole_centers raised: %r" % (label, exc))

        for fn, ref_fn in (("min_edge_clearance", ref_clearance),
                           ("annular_area", ref_area),
                           ("solid_volume", ref_volume),
                           ("mass_grams", ref_mass)):
            try:
                got = getattr(agent, fn)(spec)
            except Exception as exc:
                fail("%s %s raised: %r" % (label, fn, exc))
                continue
            want = ref_fn(spec)
            if not num_ok(got, want):
                fail("%s %s mismatch: got %r want %r" % (label, fn, got, want))

        for j, lim in enumerate((LIMITS_DEFAULT, LIMITS_TIGHT)):
            try:
                got_r = agent.build_report(spec, lim)
            except Exception as exc:
                fail("%s build_report limits[%d] raised: %r" % (label, j, exc))
                continue
            if not report_ok(got_r, ref_report(spec, lim)):
                fail("%s build_report limits[%d] mismatch" % (label, j))

    return 1 if FAILURES else 0


if __name__ == "__main__":
    rc = main()
    if FAILURES:
        print("verify failures (%d):" % len(FAILURES))
        for f in FAILURES:
            print("  -", f)
    else:
        print("all checks passed")
    sys.exit(rc)