# -*- coding: utf-8 -*-
"""Generated-data modules: the district defaults table (large, built by
loops at render time), the hydrant registry and seed builders."""

DISTRICTS = ["north", "south", "east", "west", "central", "harbour", "upland", "marina", "delta", "corner", "ridge", "vale", "steppe", "fringe", "hillside", "ravine"]
SEASONS = ["spring", "summer", "autumn", "winter"]
CLASSES = ["residential", "commercial", "industrial", "agricultural", "institutional"]


def _defaults_rows():
    rows = []
    prio = 0
    for d in DISTRICTS:
        for s in SEASONS:
            for cls in CLASSES:
                prio += 1
                nominal = 40 + (prio % 9) * 5
                minp = 2.0 + (prio % 4) * 0.25
                maxp = minp + 1.5 + (prio % 3) * 0.5
                tag = "%s-%s" % (d[0:1].upper(), s[0:3].upper())
                rows.append(
                    "  { district: %r, zone: %r, sector: %r, cls: %r, priority: %d, "
                    "nominal: %d, minPressure: %.2f, maxPressure: %.2f, tariffTag: %r },"
                    % (d, "%s-%s" % (d, cls[0:3]), s, cls, prio, nominal, minp, maxp, tag)
                )
    return rows


DEFAULTS_TS = """// district-defaults.ts: canonical operating defaults per district,
// season and customer class. The table is the reference the reports and
// the regulation layer both consult; entries are sorted by priority.

export interface DistrictDefault {
  readonly district: string;
  readonly zone: string;
  readonly sector: string;
  readonly cls: string;
  readonly priority: number;
  readonly nominal: number;
  readonly minPressure: number;
  readonly maxPressure: number;
  readonly tariffTag: string;
}

/** Full operating-defaults table, ordered by priority. */
export const DISTRICT_DEFAULTS: readonly DistrictDefault[] = [
%s
];

/** Look up the first default matching district and class. */
export function findDefault(\n  district: string,
  cls: string,
): DistrictDefault | undefined {
  for (const d of DISTRICT_DEFAULTS) {
    if (d.district === district && d.cls === cls) {
      return d;
    }
  }
  return undefined;
}

/** Distinct district names in the table. */
export function defaultDistricts(): string[] {
  const seen: string[] = [];
  for (const d of DISTRICT_DEFAULTS) {
    if (seen.indexOf(d.district) < 0) {
      seen.push(d.district);
    }
  }
  return seen;
}

/** Count of rows for a district. */
export function countForDistrict(district: string): number {
  let n = 0;
  for (const d of DISTRICT_DEFAULTS) {
    if (d.district === district) {
      n += 1;
    }
  }
  return n;
}

/** Sorted priority list of the districts that carry maximum nominal. */
export function topDistricts(limit: number): string[] {
  const copy = [...DISTRICT_DEFAULTS];
  copy.sort((a, b) => b.nominal - a.nominal || a.district.localeCompare(b.district));
  const out: string[] = [];
  for (const d of copy) {
    if (out.length >= limit) {
      break;
    }
    if (out.indexOf(d.district) < 0) {
      out.push(d.district);
    }
  }
  return out;
}

"""

CADD3 = [
    ("src/data/district-defaults.ts", DEFAULTS_TS % ("\n".join(_defaults_rows()))),
]


def hydrants_rows():
    rows = []
    for d in DISTRICTS:
        for i in range(1, 20):
            serial = "%s-%03d" % (d, i)
            pressure = 3.0 + ((i * 7 + len(d)) % 30) / 10.0
            flow = 900 + ((i * 13 + len(d)) % 20) * 60
            state = "ok" if i % 11 != 5 else "flagged"
            rows.append(
                "  { serial: %r, district: %r, pressureBar: %.2f, flowLpm: %d, state: %r },"
                % (serial, d, pressure, flow, state)
            )
    return rows


HYDRANTS_TS = """// hydrants.ts: district hydrant register. Used by maintenance planning;
// the state field is one of ok|flagged|closed.

export interface Hydrant {
  readonly serial: string;
  readonly district: string;
  readonly pressureBar: number;
  readonly flowLpm: number;
  readonly state: string;
}

/** Full hydrant register. */
export const HYDRANTS: readonly Hydrant[] = [
%s
];

/** Hydrants with a non-ok state. */
export function flaggedHydrants(): Hydrant[] {
  return HYDRANTS.filter((h) => h.state !== "ok");
}

/** Average pressure over the district's hydrants. */
export function districtPressure(district: string): number {
  let sum = 0;
  let n = 0;
  for (const h of HYDRANTS) {
    if (h.district === district) {
      sum += h.pressureBar;
      n += 1;
    }
  }
  return n === 0 ? 0 : sum / n;
}

/** Total rated flow of the district's hydrants in litres/minute. */
export function districtFlow(district: string): number {
  let sum = 0;
  for (const h of HYDRANTS) {
    if (h.district === district) {
      sum += h.flowLpm;
    }
  }
  return sum;
}

"""

CADD3 += [
    ("src/data/hydrants.ts", HYDRANTS_TS % ("\n".join(hydrants_rows()))),
]


def fixtures_rows():
    rows = []
    for i in range(1, 65):
        serial = "MTR-%04d" % i
        district = DISTRICTS[i % len(DISTRICTS)]
        rows.append(
            '{ serial: %r, district: %r, unit: null, installedDay: %d },'
            % (serial, district, 1 + (i * 3) % 60)
        )
    return rows


FIXTURES_TS = """// fixtures.ts: canonical seed meters used by the report fixtures. The
// seeds are stable across runs so report snapshots compare cleanly.

import { type Meter } from "./ledger.js";

/** The canonical seed meter set. */
export const SEED_METERS: readonly Meter[] = [
%s
];

/** Seed meter with the given serial, or undefined. */
export function seedMeter(serial: string): Meter | undefined {
  for (const m of SEED_METERS) {
    if (m.serial === serial) {
      return m;
    }
  }
  return undefined;
}

/** Distinct districts over the seed meters. */
export function seedDistricts(): string[] {
  const out: string[] = [];
  for (const m of SEED_METERS) {
    if (out.indexOf(m.district) < 0) {
      out.push(m.district);
    }
  }
  return out;
}

"""

CADD3 += [
    ("src/data/fixtures.ts", FIXTURES_TS % ("\n".join(fixtures_rows()))),
]