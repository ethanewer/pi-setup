#!/bin/bash
# Oracle for tb3-brass-caliper: write the cadmodel geometry engine module and
# generate the visible spacer report from /app/specs/spacer_spec.json using
# the documented default limits. Never reads /tests.
set -eu

cat > /app/cadmodel.py <<'PY'
"""tb3-brass-caliper — parametric spacer/flange geometry engine (pure math).

Models a family of annular spacer flanges: a circular flange disk of diameter
`flange_d`, a central bore of diameter `bore_d` on the axis (origin), and
`bolt_count` bolt holes of diameter `bolt_hole_d` drilled on a bolt circle of
diameter `bolt_circle_d`. All linear dimensions are millimetres; `density`
is in g/cm^3.

A *spec* is a dict with exactly seven keys:
    bore_d, flange_d, thickness, bolt_count (int >= 1), bolt_circle_d,
    bolt_hole_d, density.

Geometry functions return full-precision floats and require a well-formed
numeric spec (every numeric key present, a finite positive real, and
bolt_count a positive int); otherwise they raise ValueError. Only
build_report applies the documented 4-decimal rounding (round(x, 4)).
"""

import math

NUMERIC_KEYS = ("bore_d", "flange_d", "thickness",
                "bolt_circle_d", "bolt_hole_d", "density")
FIELD_TAG = {"bore_d": "BORE_D", "flange_d": "FLANGE_D",
             "thickness": "THICKNESS", "bolt_circle_d": "BOLT_CIRCLE_D",
             "bolt_hole_d": "BOLT_HOLE_D", "density": "DENSITY"}
REQUIRED_LIMITS = ("min_wall_margin", "min_hole_gap", "min_bore_gap")


def _is_real(value):
    return (isinstance(value, (int, float)) and not isinstance(value, bool)
            and math.isfinite(float(value)))


def _is_count(value):
    return (isinstance(value, int) and not isinstance(value, bool)
            and value >= 1)


def _wellformed(spec):
    if not isinstance(spec, dict):
        return False
    for key in NUMERIC_KEYS:
        value = spec.get(key)
        if not _is_real(value) or value <= 0:
            return False
    return "bolt_count" in spec and _is_count(spec["bolt_count"])


def _check_geometry_fields(spec):
    if not isinstance(spec, dict):
        raise ValueError("cadmodel: spec must be a dict")
    for key in NUMERIC_KEYS:
        value = spec.get(key)
        if not _is_real(value) or value <= 0:
            raise ValueError("cadmodel: invalid spec field %r" % key)
    if not _is_count(spec.get("bolt_count")):
        raise ValueError("cadmodel: invalid spec field 'bolt_count'")


def bolt_hole_centers(spec):
    """List of bolt-hole center coordinates as (x, y) float tuples, in
    order i = 0 .. bolt_count-1.

    Hole i sits at angle 2*pi*i/bolt_count measured counter-clockwise from
    the +X axis (bore axis at the origin), at radius bolt_circle_d/2, so
    hole 0 is at (bolt_circle_d/2, 0.0).
    """
    _check_geometry_fields(spec)
    radius = spec["bolt_circle_d"] / 2.0
    count = spec["bolt_count"]
    return [(radius * math.cos(2.0 * math.pi * i / count),
             radius * math.sin(2.0 * math.pi * i / count))
            for i in range(count)]


def min_edge_clearance(spec):
    """Minimum edge clearance in mm (may be negative).

    Candidates, in mm:
      1. for each adjacent pair (i, (i+1) mod bolt_count), only when
         bolt_count >= 2: Euclidean distance between the two hole centers
         minus bolt_hole_d;
      2. bore edge: bolt_circle_d/2 - bore_d/2 - bolt_hole_d/2;
      3. flange edge: flange_d/2 - bolt_circle_d/2 - bolt_hole_d/2.
    Returns the minimum of the candidates.
    """
    _check_geometry_fields(spec)
    count = spec["bolt_count"]
    centers = bolt_hole_centers(spec)
    candidates = []
    if count >= 2:
        for i in range(count):
            x1, y1 = centers[i]
            x2, y2 = centers[(i + 1) % count]
            candidates.append(math.hypot(x1 - x2, y1 - y2) - spec["bolt_hole_d"])
    candidates.append(spec["bolt_circle_d"] / 2.0
                      - spec["bore_d"] / 2.0 - spec["bolt_hole_d"] / 2.0)
    candidates.append(spec["flange_d"] / 2.0
                      - spec["bolt_circle_d"] / 2.0 - spec["bolt_hole_d"] / 2.0)
    return min(candidates)


def annular_area(spec):
    """Annular cross-section area excluding bolt holes, mm^2:
    (math.pi/4) * (flange_d**2 - bore_d**2
                   - bolt_count * bolt_hole_d**2).

    Overlap convention: every bolt hole is subtracted at its full nominal
    circle even where it overlaps the bore or a neighbouring hole; nothing
    is clipped to the flange; no union/overlap correction is applied.
    """
    _check_geometry_fields(spec)
    return ((math.pi / 4.0)
            * (spec["flange_d"] ** 2 - spec["bore_d"] ** 2
               - spec["bolt_count"] * spec["bolt_hole_d"] ** 2))


def solid_volume(spec):
    """Solid volume in mm^3 = thickness * annular_area(spec).

    Overlap convention: bolt holes are straight through-holes spanning the
    full thickness, subtracted in full; no overlap correction.
    """
    _check_geometry_fields(spec)
    return spec["thickness"] * annular_area(spec)


def mass_grams(spec):
    """Mass in grams = solid_volume(spec) * density / 1000.0.

    density is g/cm^3 while volumes are mm^3; 1 cm^3 == 1000 mm^3.
    """
    _check_geometry_fields(spec)
    return solid_volume(spec) * spec["density"] / 1000.0


def _checked_limits(limits):
    if not isinstance(limits, dict):
        raise ValueError("cadmodel: limits must be a dict")
    checked = {}
    for key in REQUIRED_LIMITS:
        if key not in limits:
            raise ValueError("cadmodel: limits missing key %r" % key)
        value = limits[key]
        if not _is_real(value) or value < 0.0:
            raise ValueError("cadmodel: invalid limits value for %r" % key)
        checked[key] = float(value)
    return checked


def validate_spec(spec, limits):
    """Sorted, deduplicated list of design-rule violation codes for `spec`
    under `limits` (dict keyed min_wall_margin, min_hole_gap, min_bore_gap;
    extra keys ignored). Raises ValueError for a non-dict spec or for
    limits that miss or mistype a required margin.

    Field codes: INVALID_<FIELD> for a missing/non-numeric (or non-finite)
    numeric field; NONPOSITIVE_<FIELD> when it is <= 0; BOLT_COUNT_INVALID
    when bolt_count is missing, not an int, a bool, or < 1.

    Geometry codes (evaluated only when every numeric field is a finite
    positive real and bolt_count is a positive int):

      BORE_NOT_INSIDE_BOLT_CIRCLE    bolt_circle_d <= bore_d
      HOLE_OUTSIDE_FLANGE            bolt_circle_d + bolt_hole_d > flange_d
      HOLE_TOO_CLOSE_TO_BORE         (bolt_circle_d - bore_d - bolt_hole_d)/2
                                     < min_bore_gap
      HOLE_TOO_CLOSE_TO_FLANGE_EDGE  (flange_d - bolt_circle_d - bolt_hole_d)/2
                                     < min_wall_margin
      ADJACENT_HOLES_TOO_CLOSE       bolt_count >= 2 and some adjacent pair
                                     center distance - bolt_hole_d
                                     < min_hole_gap
    """
    if not isinstance(spec, dict):
        raise ValueError("cadmodel: spec must be a dict")
    _checked_limits(limits)
    codes = set()
    for key in NUMERIC_KEYS:
        tag = FIELD_TAG[key]
        if key not in spec or not _is_real(spec[key]):
            codes.add("INVALID_" + tag)
        elif spec[key] <= 0:
            codes.add("NONPOSITIVE_" + tag)
    if not _is_count(spec.get("bolt_count")):
        codes.add("BOLT_COUNT_INVALID")
    if _wellformed(spec):
        bore_d = spec["bore_d"]
        flange_d = spec["flange_d"]
        bolt_circle_d = spec["bolt_circle_d"]
        bolt_hole_d = spec["bolt_hole_d"]
        count = spec["bolt_count"]
        if bolt_circle_d <= bore_d:
            codes.add("BORE_NOT_INSIDE_BOLT_CIRCLE")
        if bolt_circle_d + bolt_hole_d > flange_d:
            codes.add("HOLE_OUTSIDE_FLANGE")
        if (bolt_circle_d - bore_d - bolt_hole_d) / 2.0 < limits["min_bore_gap"]:
            codes.add("HOLE_TOO_CLOSE_TO_BORE")
        if (flange_d - bolt_circle_d - bolt_hole_d) / 2.0 < limits["min_wall_margin"]:
            codes.add("HOLE_TOO_CLOSE_TO_FLANGE_EDGE")
        if count >= 2:
            centers = bolt_hole_centers(spec)
            for i in range(count):
                x1, y1 = centers[i]
                x2, y2 = centers[(i + 1) % count]
                if math.hypot(x1 - x2, y1 - y2) - bolt_hole_d < limits["min_hole_gap"]:
                    codes.add("ADJACENT_HOLES_TOO_CLOSE")
                    break
    return sorted(codes)


def build_report(spec, limits):
    """Full report dict for `spec` under `limits`. Raises ValueError on a
    malformed (not well-formed numeric) spec, exactly like the geometry
    functions. Schema:

    {
      "spec": {...},                       # seven fields echoed verbatim
      "limits": {...},                     # checked margin values
      "bolt_hole_centers": [[x, y], ...],  # each coordinate round(x, 4)
      "min_edge_clearance_mm": float,      # round(_, 4)
      "annular_area_mm2": float,           # round(_, 4)
      "solid_volume_mm3": float,           # round(_, 4)
      "mass_g": float,                     # round(_, 4)
      "violations": [...],                 # sorted violation codes
      "valid": bool                        # violations empty
    }
    """
    codes = validate_spec(spec, limits)
    return {
        "spec": dict(spec),
        "limits": _checked_limits(limits),
        "bolt_hole_centers": [[round(x, 4), round(y, 4)]
                              for x, y in bolt_hole_centers(spec)],
        "min_edge_clearance_mm": round(min_edge_clearance(spec), 4),
        "annular_area_mm2": round(annular_area(spec), 4),
        "solid_volume_mm3": round(solid_volume(spec), 4),
        "mass_g": round(mass_grams(spec), 4),
        "violations": codes,
        "valid": not codes,
    }
PY

python3 - <<'PY'
import json
import sys

sys.path.insert(0, "/app")
import cadmodel

with open("/app/specs/spacer_spec.json") as fh:
    spec = json.load(fh)

limits = {"min_wall_margin": 2.0, "min_hole_gap": 1.5, "min_bore_gap": 2.5}
report = cadmodel.build_report(spec, limits)
with open("/app/spacer_report.json", "w") as fh:
    json.dump(report, fh, indent=2)
    fh.write("\n")

print("oracle: wrote /app/cadmodel.py and /app/spacer_report.json")
print("visible violations:", report["violations"], "valid:", report["valid"])
PY

ls -l /app/cadmodel.py /app/spacer_report.json