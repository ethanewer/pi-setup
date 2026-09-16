# -*- coding: utf-8 -*-
"""Second-wave modules: supply modelling, pressure regulation, forecast,
billing reports, audit trail, legacy compat, hydrants, fixtures and a
deterministic seeded RNG."""

CADD2 = [
    ("src/util/seed.ts", """// seed.ts: deterministic pseudo-random helpers used by the fixture
// builders and the forecast layer. The generator is a plain LCG so runs
// are byte-for-byte reproducible across platforms.

export class SeededRng {
  private state: number;

  constructor(seed: number) {
    this.state = Math.floor(seed) & 0x7fffffff;
    if (this.state === 0) {
      this.state = 0x13579bdf;
    }
  }

  /** Next integer in [0, 2**31). */
  next(): number {
    this.state = (this.state * 1103515245 + 12345) & 0x7fffffff;
    return this.state;
  }

  /** Next float in [0, 1). */
  unit(): number {
    return this.next() / 2147483648;
  }

  /** Next integer in [lo, hi] inclusive. */
  int(lo: number, hi: number): number {
    const width = hi - lo + 1;
    return lo + (this.next() % width);
  }

  /** Next float in [lo, hi). */
  range(lo: number, hi: number): number {
    return lo + this.unit() * (hi - lo);
  }

  /** True with the given probability. */
  chance(p: number): boolean {
    return this.unit() < p;
  }

  /** Pick one element from a non-empty list (falls back to the first). */
  pick<T>(pool: readonly T[]): T {
    const idx = this.int(0, pool.length - 1);
    const v = pool[idx];
    if (v !== undefined) {
      return v;
    }
    return pool[0]!;
  }
}

"""),
    ("src/util/buckets.ts", """// buckets.ts: deterministic bucket helpers for histograms and the
// seasonal aggregation used by the reports.

export interface Bucket {
  readonly low: number;
  readonly high: number;
}

/** Equal-width buckets covering [lo, hi] in `count` parts. */
export function equalWidth(lo: number, hi: number, count: number): Bucket[] {
  const out: Bucket[] = [];
  const width = (hi - lo) / count;
  for (let i = 0; i < count; i += 1) {
    out.push({ low: lo + i * width, high: lo + (i + 1) * width });
  }
  return out;
}

/** Bucket index of a value over equal-width buckets. */
export function bucketIndex(value: number, lo: number, hi: number, count: number): number {
  const width = (hi - lo) / count;
  const idx = Math.floor((value - lo) / width);
  if (idx < 0) {
    return 0;
  }
  if (idx >= count) {
    return count - 1;
  }
  return idx;
}

/** Histogram of values over equal-width buckets. */
export function histogram(values: readonly number[], lo: number, hi: number, count: number): number[] {
  const out = new Array<number>(count).fill(0);
  for (const v of values) {
    const idx = bucketIndex(v, lo, hi, count);
    out[idx] = (out[idx] ?? 0) + 1;
  }
  return out;
}

/** Sum the buckets of two histograms element-wise. */
export function addHistograms(a: readonly number[], b: readonly number[]): number[] {
  const n = Math.max(a.length, b.length);
  const out: number[] = [];
  for (let i = 0; i < n; i += 1) {
    out.push((a[i] ?? 0) + (b[i] ?? 0));
  }
  return out;
}

"""),
    ("src/model/supply.ts", """// supply.ts: treatment plant and raw-water supply model. Plants have
// a design capacity, current output and a degradation that grows with
// runtime; availability is the effective deliverable output.

export interface PlantSpec {
  readonly id: string;
  readonly designCapacity: number;
  readonly ageYears: number;
  readonly output: number;
}

/** Measured degradation factor given the plant age. */
export function degradation(ageYears: number): number {
  if (ageYears < 5) {
    return 1;
  }
  if (ageYears < 15) {
    return 0.95;
  }
  if (ageYears < 30) {
    return 0.87;
  }
  return 0.8;
}

export class Plant {
  readonly id: string;
  readonly design: number;
  readonly age: number;
  readonly output: number;

  constructor(spec: PlantSpec) {
    this.id = spec.id;
    this.design = spec.designCapacity;
    this.age = spec.ageYears;
    this.output = spec.output;
  }

  /** Effective deliverable output after ageing, capped by design. */
  available(): number {
    const effective = Math.min(this.design, this.output * degradation(this.age));
    return Math.max(0, effective);
  }

  /** Headroom above current deliverable output. */
  headroom(): number {
    return Math.max(0, this.available() - this.output);
  }

  /** Utilisation of the design capacity, 0..1. */
  utilisation(): number {
    if (this.design <= 0) {
      return 0;
    }
    return Math.min(1, this.output / this.design);
  }
}

export class SupplySystem {
  private readonly plants: Plant[];

  constructor(specs: readonly PlantSpec[]) {
    this.plants = specs.map((s) => new Plant(s));
  }

  /** Sum of available output over all plants. */
  totalAvailable(): number {
    let sum = 0;
    for (const p of this.plants) {
      sum += p.available();
    }
    return sum;
  }

  /** Plant with the largest available output. */
  leadPlant(): Plant | undefined {
    let best: Plant | undefined = undefined;
    for (const p of this.plants) {
      if (best === undefined || p.available() > best.available()) {
        best = p;
      }
    }
    return best;
  }

  size(): number {
    return this.plants.length;
  }
}

"""),
    ("src/algo/pressure.ts", """// pressure.ts: pressure-zone regulation. A regulator maintains the
// downstream pressure band by adjusting a valve setting; the controller
// is a deterministic fixed-step policy scored by the resulting pressures.

export interface RegSpec {
  readonly node: string;
  readonly setPoint: number;
  readonly band: number;
}

export interface RegSample {
  readonly instant: number;
  readonly node: string;
  readonly pressure: number;
  readonly valve: number;
}

/** Deviation of an observed pressure from the band. */
export function deviation(sample: RegSample, spec: RegSpec): number {
  const lo = spec.setPoint - spec.band;
  const hi = spec.setPoint + spec.band;
  if (sample.pressure < lo) {
    return lo - sample.pressure;
  }
  if (sample.pressure > hi) {
    return sample.pressure - hi;
  }
  return 0;
}

/** Next valve setting under the fixed-step policy. */
export function nextValve(current: number, deviationAmount: number, step: number): number {
  if (deviationAmount > 0) {
    return Math.min(1, current + step);
  }
  if (deviationAmount < 0) {
    return Math.max(0, current - step);
  }
  return current;
}

/** Simulate a regulator over a pressure series. */
export function regulate(
  spec: RegSpec,
  pressures: readonly number[],
  step: number,
  startValve = 0.5,
): RegSample[] {
  const out: RegSample[] = [];
  let valve = startValve;
  for (let i = 0; i < pressures.length; i += 1) {
    const p = pressures[i];
    if (p === undefined) {
      continue;
    }
    const sample: RegSample = { instant: i, node: spec.node, pressure: p, valve };
    const dev = deviation(sample, spec);
    valve = nextValve(valve, dev, step);
    out.push(sample);
  }
  return out;
}

/** Integral of absolute deviation over a regulation run. */
export function regulationScore(samples: readonly RegSample[], spec: RegSpec): number {
  let score = 0;
  for (const s of samples) {
    score += Math.abs(deviation(s, spec));
  }
  return score;
}

"""),
    ("src/algo/forecast.ts", """// forecast.ts: short-horizon demand forecast from past daily totals.
// The model is a moving baseline with a day-of-week adjustment; the
// forecast is the baseline plus the adjustment, floored at zero.

export interface DailyDemand {
  readonly day: number;
  readonly demand: number;
}

/** Baseline = trailing average of the last `window` days. */
export function baseline(days: readonly DailyDemand[], window: number): number {
  if (days.length === 0) {
    return 0;
  }
  const n = Math.min(window, days.length);
  let sum = 0;
  for (let i = days.length - n; i < days.length; i += 1) {
    const d = days[i];
    if (d !== undefined) {
      sum += d.demand;
    }
  }
  return sum / n;
}

/** Day-of-week adjustment relative to the baseline. */
export function dayAdjustment(days: readonly DailyDemand[], window: number, targetWeekday: number): number {
  const b = baseline(days, window);
  let sum = 0;
  let count = 0;
  for (const d of days) {
    if ((d.day % 7) === targetWeekday && d.demand >= 0) {
      sum += d.demand - b;
      count += 1;
    }
  }
  return count === 0 ? 0 : sum / count;
}

/** One-step forecast for a target weekday. */
export function forecastNext(days: readonly DailyDemand[], window: number, nextDay: number): number {
  const b = baseline(days, window);
  const adj = dayAdjustment(days, window, nextDay % 7);
  return Math.max(0, b + adj);
}

/** Mean absolute percentage error of a forecast trail. */
export function mape(actual: readonly number[], predicted: readonly number[]): number {
  let acc = 0;
  let count = 0;
  const n = Math.min(actual.length, predicted.length);
  for (let i = 0; i < n; i += 1) {
    const a = actual[i];
    const p = predicted[i];
    if (a === undefined || p === undefined || a === 0) {
      continue;
    }
    acc += Math.abs(a - p) / a;
    count += 1;
  }
  return count === 0 ? 0 : (acc / count) * 100;
}

"""),
    ("src/reports/billing.ts", """// billing.ts: invoice line assembly from segments and tariffs. Each
// segment becomes one line; totals are added as a trailing row in the
// same money format as the lines.

import { centsToEuros } from "../util/money.js";
import { type Segment } from "../data/ledger.js";
import { priceForVolume, type Tariff } from "../data/tariffs.js";

export interface InvoiceLine {
  readonly fromInstant: number;
  readonly toInstant: number;
  readonly volume: number;
  readonly amountCents: number;
}

/** Build invoice lines for one meter over its segments. */
export function invoiceLines(segments: readonly Segment[], tariff: Tariff): InvoiceLine[] {
  const out: InvoiceLine[] = [];
  for (const s of segments) {
    out.push({
      fromInstant: s.fromInstant,
      toInstant: s.toInstant,
      volume: s.consumption,
      amountCents: priceForVolume(tariff, s.consumption),
    });
  }
  return out;
}

/** Total amount over invoice lines. */
export function invoiceTotal(lines: readonly InvoiceLine[]): number {
  let sum = 0;
  for (const l of lines) {
    sum += l.amountCents;
  }
  return sum;
}

/** Render invoice lines as equals-format text rows. */
export function renderInvoice(lines: readonly InvoiceLine[], prefix: string): string {
  const rows: string[] = [];
  for (const l of lines) {
    rows.push(
      `${prefix};${l.fromInstant};${l.toInstant};${l.volume};${centsToEuros(l.amountCents)}`,
    );
  }
  rows.push(`${prefix};TOTAL;${centsToEuros(invoiceTotal(lines))}`);
  return rows.join("\\n");
}

"""),
    ("src/service/audit.ts", """// audit.ts: verification and integrity service. Records every mutation
// seen by the pipeline with a monotonic sequence and a signature derived
// from the record; the service also answers integrity queries.

import { type RawRecord } from "../data/records.js";

export interface AuditEntry {
  readonly seq: number;
  readonly kind: string;
  readonly key: string;
  readonly message: string;
}

/** FNV-1a digest of the record as a hex string. */
export function recordDigest(rec: RawRecord): string {
  let hash = 2166136261;
  const text = JSON.stringify(sortKeys(rec));
  for (let i = 0; i < text.length; i += 1) {
    hash ^= text.charCodeAt(i);
    hash = (hash * 16777619) & 0xffffffff;
  }
  const digits: string[] = [];
  for (let i = 0; i < 8; i += 1) {
    digits.push(((hash >> (i * 4)) & 0xf).toString(16));
  }
  return digits.join("");
}

function sortKeys(rec: RawRecord): RawRecord {
  const out: RawRecord = {};
  for (const k of Object.keys(rec).sort()) {
    out[k] = rec[k];
  }
  return out;
}

export class AuditLog {
  private readonly entries: AuditEntry[] = [];
  private seq = 1;

  /** Record one pipeline event. */
  note(kind: string, key: string, message: string): void {
    this.entries.push({ seq: this.seq, kind, key, message });
    this.seq += 1;
  }

  /** All entries in sequence order. */
  all(): readonly AuditEntry[] {
    return this.entries;
  }

  size(): number {
    return this.entries.length;
  }

  /** Entries of a given kind. */
  ofKind(kind: string): AuditEntry[] {
    return this.entries.filter((e) => e.kind === kind);
  }

  /** Sequence numbers are contiguous starting at 1. */
  contiguous(): boolean {
    for (let i = 0; i < this.entries.length; i += 1) {
      const e = this.entries[i];
      if (e === undefined || e.seq !== i + 1) {
        return false;
      }
    }
    return true;
  }
}

"""),
    ("src/legacy/compat.ts", """// compat.ts: compatibility adapters for pre-record callers. These
// wrappers convert legacy shapes to the modern record shape so old
// import scripts keep working unchanged.

import { type RawRecord } from "../data/records.js";
import { naturalSort } from "../util/natural.js";

export interface LegacyRow {
  readonly columns: readonly string[];
  readonly values: readonly string[];
}

/** Zip legacy columns/values into a raw record. */
export function rowToRecord(row: LegacyRow): RawRecord {
  const out: RawRecord = {};
  const n = Math.min(row.columns.length, row.values.length);
  for (let i = 0; i < n; i += 1) {
    const col = row.columns[i];
    const val = row.values[i];
    if (col !== undefined && val !== undefined) {
      out[col] = val;
    }
  }
  return out;
}

/** Sort column names naturally. */
export function sortedColumns(row: LegacyRow): string[] {
  return naturalSort([...row.columns]);
}

/** Simple projected view of a record. */
export function project(rec: RawRecord, keys: readonly string[]): RawRecord {
  const out: RawRecord = {};
  for (const k of keys) {
    const v = rec[k];
    if (v !== undefined) {
      out[k] = v;
    }
  }
  return out;
}

"""),
]