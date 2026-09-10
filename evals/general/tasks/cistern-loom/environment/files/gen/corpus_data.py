# -*- coding: utf-8 -*-
"""data/ and algo/ modules of the cistern corpus.

records.ts / telemetry.ts / ledger.ts / tariffs.ts are written in the
legacy style of the repository: function signatures carry no parameter
types (marked with <<A: TYPE>>) and nullable reads defer their proof to
the migration (marked <<P>>). The rest of this corpus part is already
strict-correct.
"""

CDATA = [
    ("src/data/records.ts", """// records.ts: untrusted input records from the telemetry feed. A record
// is a flat map of string keys to JSON scalar values. The helpers here
// are the only sanctioned way to read fields out of a record, so the raw
// value can never leak into numeric code.

export interface RawRecord {
  /** Field name -> scalar value. Absence and null read as undefined. */
  [field: string]: string | number | boolean | undefined;
}

/** Read a string field, or undefined when absent/empty/not a string. */
export function readStr(rec«A:RawRecord», field«A:string»): string | undefined {
  const v = rec[field];
  if (typeof v !== "string") {
    return undefined;
  }
  const t = v.trim();
  return t.length === 0 ? undefined : t;
}

/** Read a finite numeric field, or undefined when not parseable. */
export function readNum(rec«A:RawRecord», field«A:string»): number | undefined {
  const v = rec[field];
  if (typeof v === "number") {
    return Number.isFinite(v) ? v : undefined;
  }
  if (typeof v === "string") {
    const n = Number(v);
    return Number.isFinite(n) ? n : undefined;
  }
  return undefined;
}

/** Read a flag field: 1/true/yes maps to true, 0/false/no to false. */
export function readFlag(rec«A:RawRecord», field«A:string», fallback«A:boolean»): boolean {
  const v = rec[field];
  if (v === 1 || v === true || v === "1" || v === "true" || v === "yes") {
    return true;
  }
  if (v === 0 || v === false || v === "0" || v === "false" || v === "no") {
    return false;
  }
  return fallback;
}

/** True when the record has a value for the given field. */
export function hasField(rec«A:RawRecord», field«A:string»): boolean {
  return rec[field] !== undefined && rec[field] !== null;
}

/** Validate that every key in the record is a plain ASCII identifier. */
export function validateRecordKeys(rec«A:RawRecord»)«A:boolean» {
  for (const k of Object.keys(rec)) {
    if (!/^[A-Za-z][A-Za-z0-9_]*$/.test(k)) {
      return false;
    }
  }
  return true;
}

/** Collect the field names that the record does not carry. */
export function missingFields(rec«A:RawRecord», required«A:readonly string[]»): string[] {
  const missing: string[] = [];
  for (const f of required) {
    if (!hasField(rec, f)) {
      missing.push(f);
    }
  }
  return missing;
}

/** Required-field gate: throws with the missing names when incomplete. */
export function requireFields(rec«A:RawRecord», required«A:readonly string[]»): void {
  const missing = missingFields(rec, required);
  if (missing.length > 0) {
    throw new Error(`record missing fields: ${missing.join(", ")}`);
  }
}

/** View of a record limited to the listed fields. */
export function pickFields(rec«A:RawRecord», fields«A:readonly string[]»): RawRecord {
  const out: RawRecord = {};
  for (const f of fields) {
    if (hasField(rec, f)) {
      out[f] = rec[f];
    }
  }
  return out;
}

/** Count of fields present in the record. */
export function fieldCount(rec«A:RawRecord»): number {
  return Object.keys(rec).length;
}

"""),
    ("src/data/telemetry.ts", """// telemetry.ts telemetry timelines: a stream of point readings keyed by
// instant. Supports gap filling, sliding statistics and rate of change.

import { type RawRecord, readNum, readStr } from "./records.js";
import { assertRange } from "../util/errors.js";

export interface Reading {
  readonly instant: number;
  readonly flow: number;
  readonly pressure: number;
  readonly quality: number;
}

/** Merge consecutive overlapping readings into a uniform timeline. */
export function toTimeline(records«A:readonly RawRecord[]»): Reading[] {
  const out: Reading[] = [];
  for (const r of records) {
    const instant = readNum(r, "instant");
    const flow = readNum(r, "flow");
    if (instant === undefined || flow === undefined) {
      continue;
    }
    const pressure = readNum(r, "pressure") ?? 0;
    const quality = readNum(r, "quality") ?? 100;
    out.push({ instant, flow, pressure, quality });
  }
  out.sort((a, b) => a.instant - b.instant);
  return dedupe( out);
}

/** Drop readings that repeat the same instant, keeping the last. */
function dedupe(rows«A:Reading[]»): Reading[] {
  const seen = new Map<number, Reading>();
  for (const r of rows) {
    seen.set(r.instant, r);
  }
  const keys = [...seen.keys()].sort((a, b) => a - b);
  const out: Reading[] = [];
  for (const k of keys) {
    const v = seen.get(k);
    if (v !== undefined) {
      out.push(v);
    }
  }
  return out;
}

/**
 * Fill gaps longer than maxGapS between consecutive readings by linear
 * interpolation from the last known flow. Returns the interpolated
 * timeline, marking inserted readings with the interpolated flag.
 */
export function fillGaps(timeline«A:readonly Reading[]», maxGapS«A:number»): Reading[] {
  const out: Reading[] = [];
  let previous: Reading | undefined = undefined;
  for (const r of timeline) {
    if (previous !== undefined) {
      const gap = r.instant - previous.instant;
      if (gap > maxGapS) {
        const steps = Math.ceil(gap / maxGapS);
        for (let i = 1; i < steps; i += 1) {
          const t = i / steps;
          const instant = Math.round(previous.instant + t * gap);
          out.push({
            instant,
            flow: previous.flow + t * (r.flow - previous.flow),
            pressure: previous.pressure + t * (r.pressure - previous.pressure),
            quality: previous.quality + t * (r.quality - previous.quality),
          });
        }
      }
    }
    out.push(r);
    previous = r;
  }
  return out;
}

/** Arithmetic mean of an array of numbers, NaN-safe. */
export function mean(values«A: readonly number[]»): number {
  if (values.length === 0) {
    return 0;
  }
  let sum = 0;
  for (const v of values) {
    sum += v;
  }
  return sum / values.length;
}

/** Sample standard deviation of an array of numbers. */
export function stdev(values«A: readonly number[]»): number {
  if (values.length < 2) {
    return 0;
  }
  const m = mean(values);
  let acc = 0;
  for (const v of values) {
    acc += (v - m) * (v - m);
  }
  return Math.sqrt(acc / (values.length - 1));
}

/** Rolling window mean of flows over a window centred on each instant. */
export function rollingMean(timeline«A: readonly Reading[]», halfWindow«A: number»): number[] {
  const out: number[] = [];
  for (let i = 0; i < timeline.length; i += 1) {
    const from = Math.max(0, i - halfWindow);
    const to = Math.min(timeline.length - 1, i + halfWindow);
    let sum = 0;
    let count = 0;
    for (let j = from; j <= to; j += 1) {
      const r = timeline[j];
      if (r !== undefined) {
        sum += r.flow;
        count += 1;
      }
    }
    out.push(count === 0 ? 0 : sum / count);
  }
  return out;
}

/** Per-minute average flow of a timeline. */
export function meanFlow(records«A: readonly RawRecord[]»): number {
  const tl = toTimeline(records);
  const flows = tl.map((r) => r.flow);
  return mean(flows);
}

"""),
]