# -*- coding: utf-8 -*-
"""util/ and model/ additions: period arithmetic, sorting helpers,
drain state, quality standards, district presets."""

CADD = [
    ("src/util/period.ts", """// period.ts: calendar arithmetic over the day/frequency model the
// reports use. Days are integers; an instant is day * 86400 + seconds.

export interface DaySpan {
  readonly startDay: number;
  readonly endDay: number;
}

/** Seconds of an ISO-style daily clock. */
export function secondsOfDay(hours: number, minutes = 0, seconds = 0): number {
  return hours * 3600 + minutes * 60 + seconds;
}

/** Whole days covered by a half-open instant span. */
export function daysBetween(a: number, b: number): number {
  return Math.max(0, Math.ceil((b - a) / 86400));
}

/** Day number containing the instant. */
export function dayOf(instant: number): number {
  return Math.floor(instant / 86400);
}

/** Instant at the start of a day. */
export function startOfDay(day: number): number {
  return day * 86400;
}

/** Instant at the end of a day (exclusive). */
export function endOfDay(day: number): number {
  return (day + 1) * 86400;
}

/** Split a day into evening/morning/night buckets. */
export function dayBucket(instant: number): "morning" | "noon" | "evening" | "night" {
  const s = instant % 86400;
  if (s < 6 * 3600) {
    return "night";
  }
  if (s < 12 * 3600) {
    return "morning";
  }
  if (s < 18 * 3600) {
    return "noon";
  }
  return "evening";
}

/** Round an instant down to a period boundary. */
export function periodStart(instant: number, periodSeconds: number): number {
  return Math.floor(instant / periodSeconds) * periodSeconds;
}

/** True when the instant is inside the darkest night window. */
export function isNightly(instant: number, startSecond: number, endSecond: number): boolean {
  const s = instant % 86400;
  return s >= startSecond || s < endSecond;
}

"""),
    ("src/util/natural.ts", """// natural.ts: natural-order comparison for identifiers that embed
// numbers ("R12" before "R2" for humans). Used by the report sorters.

/** Split a token into numeric and alphabetic runs. */
function runs(s: string): Array<string | number> {
  const out: Array<string | number> = [];
  let cur = "";
  let numeric = false;
  for (const ch of s) {
    const isDigit = ch >= "0" && ch <= "9";
    if (cur.length === 0) {
      cur = ch;
      numeric = isDigit;
      continue;
    }
    if (isDigit === numeric) {
      cur += ch;
      continue;
    }
    out.push(numeric ? Number(cur) : cur.toLowerCase());
    cur = ch;
    numeric = isDigit;
  }
  if (cur.length > 0) {
    out.push(numeric ? Number(cur) : cur.toLowerCase());
  }
  return out;
}

/** Compare two strings naturally, returning -1, 0, +1. */
export function naturalCompare(a: string, b: string): number {
  const ra = runs(a);
  const rb = runs(b);
  const n = Math.max(ra.length, rb.length);
  for (let i = 0; i < n; i += 1) {
    const x = ra[i];
    const y = rb[i];
    if (x === undefined && y === undefined) {
      return 0;
    }
    if (x === undefined) {
      return -1;
    }
    if (y === undefined) {
      return 1;
    }
    if (typeof x === "number" && typeof y === "number") {
      if (x !== y) {
        return x < y ? -1 : 1;
      }
      continue;
    }
    const sx = String(x);
    const sy = String(y);
    if (sx !== sy) {
      return sx < sy ? -1 : 1;
    }
  }
  return 0;
}

/** Sort a list of strings in natural order. */
export function naturalSort(values: readonly string[]): string[] {
  return [...values].sort(naturalCompare);
}

"""),
    ("src/data/profiles.ts", """// profiles.ts: hourly demand profiles. A profile assigns a flow factor
// to every hour of the day; zones multiply their baseline demand by the
// factor of the current hour. Deterministic and table-driven.

import { type DemandCurve } from "../model/config.js";

/** Factor of an hour (0..23) for a given curve. */
export function hourFactor(curve: DemandCurve, hour: number): number {
  const table = profileTable(curve);
  const idx = Math.min(23, Math.max(0, Math.floor(hour)));
  const f = table[idx];
  return f === undefined ? 0 : f;
}

/** Whole-day profile table for a curve. */
export function profileTable(curve: DemandCurve): number[] {
  switch (curve) {
    case "flat":
      return flatTable();
    case "rising":
      return risingTable();
    case "nightlow":
      return nightlowTable();
  }
}

function flatTable(): number[] {
  const out: number[] = [];
  for (let h = 0; h < 24; h += 1) {
    out.push(1.0);
  }
  return out;
}

function risingTable(): number[] {
  const out: number[] = [];
  for (let h = 0; h < 24; h += 1) {
    out.push(0.5 + (h / 23) * 1.1);
  }
  return out;
}

function nightlowTable(): number[] {
  const out: number[] = [];
  for (let h = 0; h < 24; h += 1) {
    const night = (h < 4 || h >= 23) ? 0.15 : h < 7 ? 0.35 : 1.0 + (h - 8) * 0.08;
    out.push(night);
  }
  return out;
}

/** Average factor of a curve over a whole day (used for sanity checks). */
export function averageFactor(curve: DemandCurve): number {
  const table = profileTable(curve);
  let sum = 0;
  for (const f of table) {
    sum += f;
  }
  return sum / table.length;
}

"""),
    ("src/data/presets.ts", '''// presets.ts: named configuration presets for districts. Kept as
// tables so a full run can be described in one expression.

export interface Preset {
  readonly name: string;
  readonly district: string;
  readonly season: string;
  readonly startDay: number;
  readonly horizonDays: number;
  readonly demandCurve: string;
  readonly tariffTag: string;
}

/** Registry of known presets in canonical order. */
export function presetRegistry(): Preset[] {
  const rows: Preset[] = [];
  rows.push({ name: "north-spring", district: "north", season: "spring", startDay: 80, horizonDays: 61, demandCurve: "flat", tariffTag: "N-SPR" });
  rows.push({ name: "north-summer", district: "north", season: "summer", startDay: 141, horizonDays: 61, demandCurve: "rising", tariffTag: "N-SUM" });
  rows.push({ name: "north-autumn", district: "north", season: "autumn", startDay: 202, horizonDays: 61, demandCurve: "nightlow", tariffTag: "N-AUT" });
  rows.push({ name: "north-winter", district: "north", season: "winter", startDay: 263, horizonDays: 61, demandCurve: "flat", tariffTag: "N-WIN" });
  rows.push({ name: "south-spring", district: "south", season: "spring", startDay: 80, horizonDays: 61, demandCurve: "nightlow", tariffTag: "S-SPR" });
  rows.push({ name: "south-summer", district: "south", season: "summer", startDay: 141, horizonDays: 61, demandCurve: "rising", tariffTag: "S-SUM" });
  rows.push({ name: "south-autumn", district: "south", season: "autumn", startDay: 202, horizonDays: 61, demandCurve: "flat", tariffTag: "S-AUT" });
  rows.push({ name: "south-winter", district: "south", season: "winter", startDay: 263, horizonDays: 61, demandCurve: "nightlow", tariffTag: "S-WIN" });
  rows.push({ name: "east-spring", district: "east", season: "spring", startDay: 80, horizonDays: 91, demandCurve: "flat", tariffTag: "E-SPR" });
  rows.push({ name: "east-summer", district: "east", season: "summer", startDay: 171, horizonDays: 91, demandCurve: "rising", tariffTag: "E-SUM" });
  rows.push({ name: "east-autumn", district: "east", season: "autumn", startDay: 262, horizonDays: 91, demandCurve: "nightlow", tariffTag: "E-AUT" });
  rows.push({ name: "east-winter", district: "east", season: "winter", startDay: 353, horizonDays: 91, demandCurve: "flat", tariffTag: "E-WIN" });
  return rows;
}

/** Look up a preset by name. */
export function findPreset(name: string): Preset | undefined {
  for (const p of presetRegistry()) {
    if (p.name === name) {
      return p;
    }
  }
  return undefined;
}

/** Preset names in natural order. */
export function presetNames(): string[] {
  return presetRegistry().map((p) => p.name);
}

'''),
]