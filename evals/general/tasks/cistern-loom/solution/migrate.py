# cistern-loom oracle migration script (generated; do not hand-edit).

# ================= module: %s =================

# -*- coding: utf-8 -*-
"""Marker renderer for the cistern corpus.

The corpus is authored once, in STRICT-correct form ("what a fully migrated
repository looks like"), and rendered in two modes:

  * strict - the marker text is kept: parameter and return annotations are
             present and non-null proofs appear as `!`.
  * loose  - the same runtime code with the type evidence stripped: an
             unannotated parameter becomes implicitly any under a non-strict
             tsconfig, and a proof site drops its `!`. Compiles under the
             shipped non-strict tsconfig; fails a strict compile exactly
             where a real migration has to re-add the evidence.

Markers understood by render():

  «A: TYPE»   placed right after an identifier or `)`: yields `: TYPE` in
              strict mode and an empty string in loose mode. Used for
              parameter and return annotations. Whitespace around the type
              is trimmed.
  «P»         placed right after an expression: yields `!` in strict mode
              and an empty string in loose mode. Used for non-null proofs.

Everything else is literal and identical in both modes. The shipped loose
repository contains no `any`, no `@ts-` comments and no casts: it only
lacks strictness evidence, which is the point of the migration.
"""

import re

_ANN = re.compile("\xabA:(.*?)\xbb")
_PROOF = "\xabP\xbb"


def render(text, strict):
    if strict:
        out = _ANN.sub(lambda m: ": " + m.group(1).strip(), text)
        out = out.replace(_PROOF, "!")
    else:
        out = _ANN.sub("", text)
        out = out.replace(_PROOF, "")
    return out

# ================= module: %s =================

# -*- coding: utf-8 -*-
"""util modules of the cistern corpus (strict-mode correct by default)."""

CUT = [
    ("src/util/errors.ts", """/**
 * errors.ts - typed failure model for the cistern library.
 *
 * Every routine that can fail reports a CisError carrying a stable code
 * grouped by layer: U util, C config, D data, R reports, S service. A
 * short token and a human message travel with the error.
 */

export type ErrorCode =
  | "U-INTERNAL"
  | "U-INVARIANT"
  | "U-RANGE"
  | "C-UNKNOWN-KEY"
  | "C-BAD-TYPE"
  | "C-OUT-OF-BOUNDS"
  | "D-EMPTY"
  | "D-MALFORMED"
  | "D-COLLISION"
  | "D-NO-VALUE"
  | "R-EMPTY-ROW"
  | "S-NOT-CONVERGED"
  | "S-DIVIDED-BY-ZERO";

/** Error carrying a stable code and an operator-facing message. */
export class CisError extends Error {
  readonly code: ErrorCode;
  readonly detail: string;

  constructor(code: ErrorCode, message: string, detail = "") {
    super(message);
    this.name = "CisError";
    this.code = code;
    this.detail = detail;
  }

  /** One-line human summary including the detail payload when present. */
  summarize(): string {
    return `${this.code}: ${this.message}` + (this.detail ? ` (${this.detail})` : "");
  }
}

/** Shape of a failed invariant. */
export interface InvariantFailure {
  readonly label: string;
  readonly left: string;
  readonly right: string;
}

/** Throw a U-INVARIANT error when the condition does not hold. */
export function invariant(condition: boolean, label: string, left = "", right = ""): void {
  if (!condition) {
    const fail: InvariantFailure = { label, left, right };
    throw new CisError(
      "U-INVARIANT",
      `invariant failed: ${fail.label}`,
      `${fail.left} != ${fail.right}`,
    );
  }
}

/** Range check on a quantity; throws U-RANGE when out of bounds. */
export function assertRange(value: number, min: number, max: number, what: string): void {
  if (!Number.isFinite(value)) {
    throw new CisError("U-RANGE", `${what} must be finite, got ${value}`);
  }
  if (value < min || value > max) {
    throw new CisError("U-RANGE", `${what} out of range [${min}, ${max}]: ${value}`);
  }
}

/** Finiteness check with a human label. */
export function requireFinite(value: number, what: string): void {
  if (!Number.isFinite(value)) {
    throw new CisError("U-RANGE", `${what} is not a finite number`);
  }
}

/** Standard unknown-key failure helper. */
export function unknownKey(kind: string, key: string): CisError {
  return new CisError("C-UNKNOWN-KEY", `${kind} key not found: \`${key}\``);
}

"""),
    ("src/util/money.ts", """// money.ts - integer-cent money. Tariffs, billing and all reports pass
// through this module, so rounding is defined in exactly one place: sums
// accumulate in whole cents and a single half-even rounding happens at the
// boundary the report wants.

export type Cents = number;

export const CENTS_PER_EURO = 100;

/** Round a real value to the nearest integer, ties toward even. */
export function roundHalfEven(value: number): number {
  const floored = Math.floor(value);
  const frac = value - floored;
  if (frac > 0.5) {
    return floored + 1;
  }
  if (frac < 0.5) {
    return floored;
  }
  return floored % 2 === 0 ? floored : floored + 1;
}

/** Convert a euro amount expressed as a decimal number into cents. */
export function eurosToCents(euros: number): Cents {
  return roundHalfEven(euros * CENTS_PER_EURO);
}

/** Convert cents into a two-decimal euro string, signed when negative. */
export function centsToEuros(cents: Cents): string {
  const sign = cents < 0 ? "-" : "";
  const abs = Math.abs(cents);
  const whole = Math.floor(abs / CENTS_PER_EURO);
  const frac = abs % CENTS_PER_EURO;
  return `${sign}${whole}.${String(frac).padStart(2, "0")}`;
}

/** Sum a list of cent amounts exactly. */
export function sumCents(values: readonly Cents[]): Cents {
  let total = 0;
  for (const v of values) {
    total += v;
  }
  return total;
}

/** Scale cents by a decimal factor with half-even rounding. */
export function scaleCents(cents: Cents, factor: number): Cents {
  return roundHalfEven(cents * factor);
}

/** Apply a surcharge in the given percent (5 => +5%) to cents. */
export function surcharge(cents: Cents, percent: number): Cents {
  return roundHalfEven(cents * (1 + percent / 100));
}

/** Clamp a cent amount into the [0, limit] band. */
export function clampCents(cents: Cents, limit: Cents): Cents {
  if (cents < 0) {
    return 0;
  }
  if (cents > limit) {
    return limit;
  }
  return cents;
}

/** True when the amount is within half a cent of zero. */
export function isZero(cents: Cents): boolean {
  return Math.abs(cents) < 1;
}

/** True when the first amount is strictly larger than the second. */
export function exceeds(amount: Cents, limit: Cents): boolean {
  return amount > limit;
}

"""),
    ("src/util/keys.ts", """// keys.ts: canonical compound keys for pools, meters and tariff tables.
// A canonical key is a fixed concatenation of components joined by colons,
// so sorting and dictionary lookup see one plain string.

export interface KeyParts {
  readonly prefix: string;
  readonly parts: readonly string[];
}

/** Join a prefix and any number of parts into a canonical key. */
export function makeKey(prefix: string, ...parts: readonly string[]): string {
  return [prefix, ...parts].join(":");
}

/** Split a canonical key back into prefix and components. */
export function splitKey(key: string): KeyParts {
  const pieces = key.split(":");
  return { prefix: pieces[0] ?? "", parts: pieces.slice(1) };
}

/** Canonical key for a zone/sector pair. */
export function zoneKey(zone: string, sector: string): string {
  return makeKey("z", zone, sector);
}

/** Canonical key for a meter endpoint. */
export function meterKey(district: string, serial: string): string {
  return makeKey("m", district, serial);
}

/** Canonical key for a tariff table. */
export function tariffKey(district: string, season: string): string {
  return makeKey("t", district, season);
}

/** Lexicographic comparison returning -1, 0 or +1. */
export function compareKeys(a: string, b: string): number {
  if (a < b) {
    return -1;
  }
  if (a > b) {
    return 1;
  }
  return 0;
}

/** Guard that a key starts with one of the accepted prefixes. */
export function assertKeyPrefix(key: string, prefixes: readonly string[]): void {
  const first = key.split(":")[0] ?? "";
  if (prefixes.indexOf(first) < 0) {
    throw new Error(`unexpected key prefix '${first}' in '${key}'`);
  }
}

"""),
    ("src/util/math.ts", """// math.ts: small deterministic numeric helpers used by the hydraulics and
// leak layers. All computations stay in IEEE doubles; float results feed
// only reporting, never money.

/** Linear interpolation between a and b at position t. */
export function lerp(a: number, b: number, t: number): number {
  return a + (b - a) * t;
}

/** Clamp a value into a closed interval. */
export function clamp(value: number, lo: number, hi: number): number {
  if (value < lo) {
    return lo;
  }
  if (value > hi) {
    return hi;
  }
  return value;
}

/** Trim a value to a fixed number of decimals. */
export function trimDecimals(value: number, digits: number): number {
  const f = Math.pow(10, digits);
  return Math.round(value * f) / f;
}

/** Deterministic pseudo-random in [0,1) from a seed word. */
export function seededUnit(seed: number): number {
  let x = Math.abs(Math.floor(seed)) + 1;
  x = (x * 9301 + 49297) % 233280;
  return x / 233280;
}

/** Sign of a number: -1, 0 or 1. */
export function signOf(value: number): number {
  return value < 0 ? -1 : value > 0 ? 1 : 0;
}

/** Absolute difference of two numbers. */
export function delta(a: number, b: number): number {
  return Math.abs(a - b);
}

/** Relative difference, 0 when both are zero. */
export function relativeError(actual: number, expected: number): number {
  if (expected === 0) {
    return actual === 0 ? 0 : Infinity;
  }
  return Math.abs(actual - expected) / Math.abs(expected);
}

"""),
]

# ================= module: %s =================

# -*- coding: utf-8 -*-
"""model/ and store/ modules of the cistern corpus (strict-mode correct)."""

CMODEL = [
    ("src/model/config.ts", """// config.ts: run configuration of a cistern run. Raw configuration
// arrives as untrusted key/value records; this layer validates, defaults
// and freezes it.

export interface RegionConfig {
  /** Any key from the raw config record. */
  [key: string]: string | number | boolean | undefined;
}

export type DemandCurve = "flat" | "rising" | "nightlow";

export interface FrozenConfig {
  readonly name: string;
  readonly district: string;
  readonly season: string;
  readonly startDay: number;
  readonly horizonDays: number;
  readonly demandCurve: DemandCurve;
  readonly tariffActive: boolean;
  readonly demandActive: boolean;
  readonly tariffLookup: string;
  readonly reportDir: string;
}

export interface ConfigIssue {
  readonly field: string;
  readonly message: string;
}

const ALLOWED_CURVES: readonly DemandCurve[] = ["flat", "rising", "nightlow"];

/**
 * Freeze a raw config record into a validated immutable config. Returns
 * ok:true plus the config, or ok:false plus the collected issues.
 */
export function freezeConfig(raw: RegionConfig): {
  ok: boolean;
  config: FrozenConfig | null;
  issues: ConfigIssue[];
} {
  const issues: ConfigIssue[] = [];
  const name = toStr(raw.name, "name", issues);
  const district = toStr(raw.district, "district", issues);
  const season = toStr(raw.season, "season", issues);
  const horizon = toInt(raw.horizonDays, 30, issues);
  const startDay = toInt(raw.startDay, 1, issues) ?? 1;
  if (name === null) {
    issues.push({ field: "name", message: "missing required field" });
  }
  if (district === null) {
    issues.push({ field: "district", message: "missing required field" });
  }
  if (season === null) {
    issues.push({ field: "season", message: "missing required field" });
  }

  let curve: DemandCurve = "flat";
  const curveRaw = toStr(raw.demandCurve, "demandCurve", issues);
  if (curveRaw !== null && (ALLOWED_CURVES as readonly string[]).includes(curveRaw)) {
    curve = curveRaw as DemandCurve;
  } else if (curveRaw !== null) {
    issues.push({ field: "demandCurve", message: `unknown demand curve ${curveRaw}` });
  }

  const tariffLookup = toStr(raw.tariffLookup, "tariffLookup", issues) ?? "default";
  const reportDir = toStr(raw.reportDir, "reportDir", issues) ?? "/tmp/reports";
  const tariffActive = toBool(raw.tariffActive, true, issues);
  const demandActive = toBool(raw.demandActive, false, issues);

  if (horizon === null || name === null || district === null || season === null) {
    if (horizon === null) {
      issues.push({ field: "horizonDays", message: "must be a valid integer" });
    }
    return { ok: false, config: null, issues };
  }
  if (horizon < 1 || horizon > 366) {
    issues.push({ field: "horizonDays", message: "must be 1..366" });
    return { ok: false, config: null, issues };
  }
  if (issues.length > 0) {
    return { ok: false, config: null, issues };
  }

  const config: FrozenConfig = {
    name,
    district,
    season,
    startDay,
    horizonDays: horizon,
    demandCurve: curve,
    tariffActive,
    demandActive,
    tariffLookup,
    reportDir,
  };
  return { ok: true, config, issues };
}

/** Read a string field (null when absent or empty). */
function toStr(
  value: string | number | boolean | undefined,
  field: string,
  issues: ConfigIssue[],
): string | null {
  if (value === undefined || value === null) {
    return null;
  }
  if (typeof value !== "string") {
    issues.push({ field, message: "expected a string" });
    return null;
  }
  return value.length === 0 ? null : value;
}

/** Read an integer field with a fallback for absence. */
function toInt(
  value: string | number | boolean | undefined,
  fallback: number,
  issues: ConfigIssue[],
): number | null {
  if (value === undefined || value === null) {
    return fallback;
  }
  let n: number;
  if (typeof value === "number") {
    n = value;
  } else if (typeof value === "string") {
    n = Number(value);
  } else {
    issues.push({ field: "int", message: "expected a number" });
    return null;
  }
  if (!Number.isInteger(n)) {
    issues.push({ field: "int", message: `expected an integer, got ${n}` });
    return null;
  }
  return n;
}

/** Read a boolean flag with a fallback for absence. */
function toBool(
  value: string | number | boolean | undefined,
  fallback: boolean,
  issues: ConfigIssue[],
): boolean {
  if (value === undefined || value === null) {
    return fallback;
  }
  if (typeof value === "boolean") {
    return value;
  }
  if (value === 1 || value === "1" || value === "true" || value === "yes") {
    return true;
  }
  if (value === 0 || value === "0" || value === "false" || value === "no") {
    return false;
  }
  issues.push({ field: "flag", message: "expected a boolean" });
  return fallback;
}

/** Total number of days the horizon covers. */
export function horizonSpan(config: FrozenConfig): number {
  return config.horizonDays;
}

"""),
    ("src/model/network.ts", """// network.ts: connectivity model of a water district. Nodes are
// reservoirs, tanks, junctions or pumps; links carry flow. The model is
// built from validated records and is immutable once built.

import { invariant } from "../util/errors.js";

export type NodeKind = "reservoir" | "tank" | "junction" | "pump";

export interface GeoPoint {
  readonly lon: number;
  readonly lat: number;
}

export interface NodeSpec {
  readonly id: string;
  readonly kind: NodeKind;
  readonly label: string;
  readonly capacity: number;
  readonly level: number;
  readonly point: GeoPoint | null;
}

export interface LinkSpec {
  readonly from: string;
  readonly to: string;
  readonly lengthM: number;
  readonly diameterMm: number;
  readonly roughness: number;
}

export class NodeEnt {
  readonly id: string;
  readonly kind: NodeKind;
  readonly label: string;
  readonly capacity: number;
  readonly level: number;
  readonly point: GeoPoint | null;

  constructor(spec: NodeSpec) {
    this.id = spec.id;
    this.kind = spec.kind;
    this.label = spec.label;
    this.capacity = spec.capacity;
    this.level = spec.level;
    this.point = spec.point;
  }

  /** Volume this node can still accept before hitting capacity. */
  headroom(): number {
    return Math.max(0, this.capacity - this.level);
  }

  /** Fraction of capacity currently used, clamped to 0..1. */
  fillRatio(): number {
    if (this.capacity <= 0) {
      return 0;
    }
    return Math.min(1, this.level / this.capacity);
  }

  /** Depth from the absolute datum, mirror of level. */
  depthBelow(): number {
    return Math.max(0, this.capacity - this.level);
  }
}

export class Link {
  readonly from: string;
  readonly to: string;
  readonly lengthM: number;
  readonly diameterMm: number;
  readonly roughness: number;

  constructor(spec: LinkSpec) {
    this.from = spec.from;
    this.to = spec.to;
    this.lengthM = spec.lengthM;
    this.diameterMm = spec.diameterMm;
    this.roughness = spec.roughness;
  }

  /** Hazen-Williams conductance used by the flow solver. */
  conductance(): number {
    const d = this.diameterMm / 1000;
    return (0.2785 * this.roughness * Math.pow(d, 2.87)) / Math.pow(this.lengthM, 0.54);
  }
}

export class Network {
  private readonly nodes = new Map<string, NodeEnt>();
  private readonly links = new Map<string, Link>();
  private readonly outEdges = new Map<string, string[]>();

  constructor(nodeSpecs: readonly NodeSpec[], linkSpecs: readonly LinkSpec[]) {
    for (const s of nodeSpecs) {
      this.nodes.set(s.id, new NodeEnt(s));
    }
    for (const l of linkSpecs) {
      const key = linkKey(l.from, l.to);
      this.links.set(key, new Link(l));
      const bucket = this.outEdges.get(l.from) ?? [];
      bucket.push(key);
      this.outEdges.set(l.from, bucket);
    }
    invariant(this.nodes.size === nodeSpecs.length, "unique node ids", String(nodeSpecs.length), String(this.nodes.size));
  }

  node(id: string): NodeEnt {
    const n = this.nodes.get(id);
    if (n === undefined) {
      throw new Error(`no node ${id}`);
    }
    return n;
  }

  hasNode(id: string): boolean {
    return this.nodes.has(id);
  }

  link(a: string, b: string): Link {
    const l = this.links.get(linkKey(a, b));
    if (l === undefined) {
      throw new Error(`no link ${a} -> ${b}`);
    }
    return l;
  }

  nodeCount(): number {
    return this.nodes.size;
  }

  linkCount(): number {
    return this.links.size;
  }

  /** Out-neighbour ids of a node in insertion order. */
  neighbours(id: string): string[] {
    const out = this.outEdges.get(id) ?? [];
    return out.map((k) => {
      const parts = k.split("->");
      return parts[1] ?? parts[0] ?? "";
    });
  }

  /** All node ids sorted by capacity descending, then id. */
  sortedNodeIds(): string[] {
    const ids = [...this.nodes.keys()];
    ids.sort((a, b) => {
      const ca = this.node(a).capacity;
      const cb = this.node(b).capacity;
      return cb - ca || a.localeCompare(b);
    });
    return ids;
  }
}

/** Compact identifier of a directed link. */
export function linkKey(a: string, b: string): string {
  return `${a}->${b}`;
}

/** Great-circle distance between two points in kilometres. */
export function distanceKm(a: GeoPoint, b: GeoPoint): number {
  const r = 6371;
  const dLat = ((b.lat - a.lat) * Math.PI) / 180;
  const dLon = ((b.lon - a.lon) * Math.PI) / 180;
  const lat1 = (a.lat * Math.PI) / 180;
  const lat2 = (b.lat * Math.PI) / 180;
  const h =
    Math.sin(dLat / 2) ** 2 + Math.cos(lat1) * Math.cos(lat2) * Math.sin(dLon / 2) ** 2;
  return 2 * r * Math.asin(Math.min(1, Math.sqrt(h)));
}

"""),
    ("src/model/zone.ts", """// zone.ts: hierarchical zones over a network and the registry that keeps
// them. Every ledger record is labelled by exactly one zone/sector key.

import { zoneKey, meterKey } from "../util/keys.js";

export interface ZoneSpec {
  readonly zone: string;
  readonly sector: string;
  readonly priority: number;
  readonly baselineDemand: number;
}

export class Zone {
  readonly zone: string;
  readonly sector: string;
  readonly priority: number;
  readonly baselineDemand: number;

  constructor(spec: ZoneSpec) {
    this.zone = spec.zone;
    this.sector = spec.sector;
    this.priority = spec.priority;
    this.baselineDemand = spec.baselineDemand;
  }

  /** Canonical zone key. */
  get key(): string {
    return zoneKey(this.zone, this.sector);
  }

  /** Meter label for a serial inside this zone. */
  meterLabel(serial: string): string {
    return meterKey(this.zone, serial);
  }
}

export class ZoneRegistry {
  private readonly zones = new Map<string, Zone>();

  constructor(specs: readonly ZoneSpec[]) {
    for (const s of specs) {
      this.zones.set(zoneKey(s.zone, s.sector), new Zone(s));
    }
  }

  get(key: string): Zone {
    const z = this.zones.get(key);
    if (z === undefined) {
      throw new Error(`unknown zone key ${key}`);
    }
    return z;
  }

  has(key: string): boolean {
    return this.zones.has(key);
  }

  size(): number {
    return this.zones.size;
  }

  /** Zone keys sorted. */
  keysSorted(): string[] {
    return [...this.zones.keys()].sort();
  }

  /** Total baseline demand over all zones. */
  totalDemand(): number {
    let sum = 0;
    for (const z of this.zones.values()) {
      sum += z.baselineDemand;
    }
    return sum;
  }
}

"""),
    ("src/store/store.ts", """// store.ts: in-memory document store with monotonic ids and typed
// secondary index lookups. The data layer hosts readings and ledgers here
// before the aggregation passes.

import { CisError } from "../util/errors.js";

export interface StoredDoc<T> {
  readonly id: string;
  readonly value: T;
}

/** Key extractor for the indexes of a store. */
export type IndexFn<T> = (doc: T) => string | null;

export class CisterStore<T> {
  private readonly byId = new Map<string, StoredDoc<T>>();
  private readonly byIndex = new Map<string, Map<string, string[]>>();
  private seq = 0;

  constructor(
    private readonly indexNames: readonly string[],
    private readonly extractors: ReadonlyMap<string, IndexFn<T>>,
  ) {
    for (const name of indexNames) {
      this.byIndex.set(name, new Map());
    }
  }

  private nextId(): string {
    const id = `rec-${this.seq}`;
    this.seq += 1;
    return id;
  }

  /** Insert a document, updating every index. */
  insert(doc: T): StoredDoc<T> {
    const id = this.nextId();
    const stored: StoredDoc<T> = { id, value: doc };
    this.byId.set(id, stored);
    for (const name of this.indexNames) {
      const fn = this.extractors.get(name);
      if (fn === undefined) {
        continue;
      }
      const key = fn(doc);
      if (key === null) {
        continue;
      }
      const bucket = this.byIndex.get(name)?.get(key) ?? [];
      bucket.push(id);
      this.byIndex.get(name)?.set(key, bucket);
    }
    return stored;
  }

  /** Document value by id, undefined when absent. */
  get(id: string): T | undefined {
    return this.byId.get(id)?.value;
  }

  has(id: string): boolean {
    return this.byId.has(id);
  }

  /** Ids under an index key (empty when key absent). */
  locate(name: string, key: string): string[] {
    const m = this.byIndex.get(name);
    if (m === undefined) {
      throw new CisError("C-UNKNOWN-KEY", `unknown index ${name}`);
    }
    return (m.get(key) ?? []).slice();
  }

  /** Raw entries in insertion order. */
  all(): StoredDoc<T>[] {
    return [...this.byId.values()];
  }

  size(): number {
    return this.byId.size;
  }
}

"""),
]

# ================= module: %s =================

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

# ================= module: %s =================

# -*- coding: utf-8 -*-
"""Second part of the data/algo corpus: ledger, tariffs, hydraulics,
leak detection and demand balancing. The ledger and tariff modules keep
the legacy (loose) style; the algorithm layer is strict-correct from the
first line.
"""

CDATA2 = [
    ("src/data/ledger.ts", """// ledger.ts: meter ledgers. Registers accumulate at distinct instants;
// the ledger derives billed consumption segments from register deltas,
// splitting long spans into two periods and skipping resets.

import { type RawRecord, readNum, readStr } from "./records.js";

export interface Meter {
  readonly serial: string;
  readonly district: string;
  readonly unit: string | null;
  readonly installedDay: number;
}

export interface Register {
  readonly instant: number;
  readonly register: number;
}

export interface Segment {
  readonly fromInstant: number;
  readonly toInstant: number;
  readonly consumption: number;
}

/** Parse a meter record into a meter entity. */
export function parseMeter(rec«A:RawRecord»): Meter {
  const serial = readStr(rec, "serial");
  const district = readStr(rec, "district");
  if (serial === undefined || district === undefined) {
    throw new Error("meter record requires serial and district");
  }
  return {
    serial,
    district,
    unit: readStr(rec, "unit") ?? null,
    installedDay: readNum(rec, "installedDay") ?? 1,
  };
}

/**
 * Build billing segments from chronological register readings. A register
 * decrease is treated as a meter reset (no consumption attributed). A span
 * longer than maxGapInstants is reported as two half segments.
 */
export function buildSegments(
  registers«A:readonly Register[]»,
  maxGapInstants«A:number»,
): Segment[] {
  const out: Segment[] = [];
  for (let i = 1; i < registers.length; i += 1) {
    const prev = registers[i - 1];
    const cur = registers[i];
    if (prev === undefined || cur === undefined) {
      continue;
    }
    const delta = cur.register - prev.register;
    if (delta < 0) {
      continue;
    }
    if (cur.instant - prev.instant <= maxGapInstants) {
      out.push({ fromInstant: prev.instant, toInstant: cur.instant, consumption: delta });
      continue;
    }
    const half = Math.round(delta / 2);
    const mid = Math.round((prev.instant + cur.instant) / 2);
    out.push({ fromInstant: prev.instant, toInstant: mid, consumption: half });
    out.push({ fromInstant: mid, toInstant: cur.instant, consumption: delta - half });
  }
  return out;
}

/** Sum of consumption over segments. */
export function totalVolume(segments«A:readonly Segment[]»): number {
  let sum = 0;
  for (const s of segments) {
    sum += s.consumption;
  }
  return sum;
}

/** Median segment consumption. */
export function medianVolume(segments«A:readonly Segment[]»): number {
  const vols: number[] = [];
  for (const s of segments) {
    vols.push(s.consumption);
  }
  vols.sort((a, b) => a - b);
  const n = vols.length;
  if (n === 0) {
    return 0;
  }
  const mid = Math.floor(n / 2);
  const m = vols[mid];
  if (m === undefined) {
    return 0;
  }
  if (n % 2 === 1) {
    return m;
  }
  const lo = vols[mid - 1];
  return lo === undefined ? m : (m + lo) / 2;
}

/** Serial of the meter with the largest total billed volume. */
export function busiestMeter(
  meters«A:readonly Meter[]»,
  segmentsByMeter«A:ReadonlyMap<string, readonly Segment[]>»,
): string | undefined {
  let bestSerial: string | undefined = undefined;
  let bestVolume = -1;
  for (const m of meters) {
    const segs = segmentsByMeter.get(m.serial);
    if (segs === undefined) {
      continue;
    }
    let vol = 0;
    for (const s of segs) {
      vol += s.consumption;
    }
    if (vol > bestVolume) {
      bestVolume = vol;
      bestSerial = m.serial;
    }
  }
  return bestSerial;
}

/** Number of segments crossing a single boundary instant. */
export function crossingCount(segments«A:readonly Segment[]», boundary«A:number»): number {
  let count = 0;
  for (const s of segments) {
    if (s.fromInstant < boundary && s.toInstant >= boundary) {
      count += 1;
    }
  }
  return count;
}

/** Largest single-segment consumption. */
export function peakSegment(segments«A:readonly Segment[]»): number {
  let peak = 0;
  for (const s of segments) {
    if (s.consumption > peak) {
      peak = s.consumption;
    }
  }
  return peak;
}

"""),
    ("src/data/tariffs.ts", """// tariffs.ts: tiered tariffs priced in cents per cubic metre. Volume is
// priced across the tiers in order; a flat override exists for volumes
// beyond the top tier boundary.

import { type RawRecord, readNum } from "./records.js";

export interface TariffTier {
  readonly upTo: number;
  readonly priceCentsPerM3: number;
}

export interface Tariff {
  readonly district: string;
  readonly season: string;
  readonly tiers: readonly TariffTier[];
}

/** Build a tariff table from raw tier rows, sorted by ceiling. */
export function tariffFromRows(district«A:string», season«A:string», rows«A:readonly RawRecord[]»): Tariff {
  const tiers: TariffTier[] = [];
  for (const r of rows) {
    const upTo = readNum(r, "upTo");
    const price = readNum(r, "price");
    if (upTo === undefined || price === undefined) {
      continue;
    }
    tiers.push({ upTo, priceCentsPerM3: price });
  }
  tiers.sort((a, b) => a.upTo - b.upTo);
  return { district, season, tiers };
}

/** Total price in cents for a whole volume under this tariff. */
export function priceForVolume(tiff«A:Tariff», volume«A:number»): number {
  let cents = 0;
  let remaining = Math.max(0, volume);
  let prevUpper = 0;
  let lastPrice = 0;
  for (const tier of tiff.tiers) {
    lastPrice = tier.priceCentsPerM3;
    if (remaining <= 0) {
      break;
    }
    const upTo = Math.max(prevUpper, tier.upTo);
    const width = Math.min(remaining, upTo - prevUpper);
    if (width > 0) {
      cents += width * tier.priceCentsPerM3;
      remaining -= width;
    }
    prevUpper = upTo;
  }
  if (remaining > 0) {
    cents += remaining * lastPrice;
  }
  return Math.round(cents);
}

/** True when the volume reaches above the top tier ceiling. */
export function reachesTopTier(tiff«A:Tariff», volume«A:number»): boolean {
  const last = tiff.tiers[tiff.tiers.length - 1];
  return last !== undefined && volume > last.upTo;
}

/** Average price per m3 in cents for a whole volume. */
export function averagePrice(tiff«A:Tariff», volume«A:number»): number {
  if (volume <= 0) {
    return 0;
  }
  return priceForVolume(tiff, volume) / volume;
}

/** First tariff matching district and season, if any. */
export function lookupTariff(
  tables«A:readonly Tariff[]»,
  district«A:string»,
  season«A:string»,
): Tariff | undefined {
  for (const t of tables) {
    if (t.district === district && t.season === season) {
      return t;
    }
  }
  return undefined;
}

"""),
    ("src/algo/hydraulics.ts", """// hydraulics.ts: steady-state flow balance of a district. Supply and
// demand are balanced node by node with a fixed number of relaxation
// passes; the solver is deterministic and converges fast on the
// well-conditioned fixture networks.

import { type Network, type NodeEnt, linkKey } from "../model/network.js";

export interface FlowState {
  readonly flows: ReadonlyMap<string, number>;
  readonly nodeLevels: ReadonlyMap<string, number>;
  readonly iterations: number;
  readonly converged: boolean;
}

/**
 * Balance a network against per-node demand. Returns the flow on every
 * link and the resulting node levels. Demand must equal supply overall;
 * the solver redistributes surplus into headroom.
 */
export function solveBalance(
  network: Network,
  demands: ReadonlyMap<string, number>,
  maxIterations = 60,
): FlowState {
  const flows = new Map<string, number>();
  const nodeLevels = new Map<string, number>();
  for (const id of network.sortedNodeIds()) {
    nodeLevels.set(id, 0);
  }

  const ids = network.sortedNodeIds();
  for (let iter = 0; iter < maxIterations; iter += 1) {
    for (const id of ids) {
      const demand = demands.get(id) ?? 0;
      const nodeLevel = nodeLevels.get(id) ?? 0;
      const neighbours = network.neighbours(id);
      let inflow = 0;
      for (const nb of neighbours) {
        const key = linkKey(nb, id);
        const inbound = flows.get(key);
        if (inbound !== undefined) {
          inflow += inbound;
        }
      }
      let outflow = demand;
      const surplus = inflow - outflow;
      if (surplus !== 0) {
        const level = nodeLevel + surplus / Math.max(1, neighbours.length + 1);
        nodeLevels.set(id, level);
      }
      const toty = Math.abs(inflow - outflow) + outflow;

      for (const nb of neighbours) {
        const key = linkKey(id, nb);
        const conductance = network.link(id, nb).conductance();
        const cur = flows.get(key) ?? 0;
        const share = outflow * (conductance / (1 + conductance + toty * 0.0001));
        flows.set(key, cur + (share - cur) * 0.5);
      }
    }
  }

  const converged = ids.every((id) => Math.abs(demands.get(id) ?? 0) < 1e6);
  return { flows, nodeLevels, iterations: maxIterations, converged };
}

/** Pressure estimate at a node from its level and a datum. */
export function pressureAt(level: number, datum: number): number {
  return Math.max(0, level - datum) * 0.098;
}

/** Sum of outflows from a flow state for the given node. */
export function nodeOutflow(state: FlowState, id: string, network: Network): number {
  let sum = 0;
  for (const nb of network.neighbours(id)) {
    const f = state.flows.get(linkKey(id, nb));
    if (f !== undefined) {
      sum += f;
    }
  }
  return sum;
}

"""),
    ("src/algo/leak.ts", """// leak.ts: night-flow based leak detection. The minimum nightly flow of
// each area is tracked over a window; a sustained rise above the band
// trips an alarm for the area.

export interface LeakSample {
  readonly instant: number;
  readonly area: string;
  readonly nightFlow: number;
}

export interface LeakReport {
  readonly area: string;
  readonly baseline: number;
  readonly latest: number;
  readonly ratio: number;
  readonly alerted: boolean;
}

const NIGHT_ALARM_RATIO = 1.35;

/** Baseline nightly flow of an area from its samples. */
export function baselineNightFlow(samples: readonly LeakSample[]): number {
  const flows: number[] = [];
  for (const s of samples) {
    flows.push(s.nightFlow);
  }
  flows.sort((a, b) => a - b);
  const n = flows.length;
  if (n === 0) {
    return 0;
  }
  const lo = Math.floor(n * 0.25);
  const hi = Math.floor(n * 0.5);
  const loV = flows[lo];
  const hiV = flows[hi];
  if (loV === undefined || hiV === undefined) {
    return 0;
  }
  return (loV + hiV) / 2;
}

/** Latest flow, baseline and alert state for one area. */
export function evaluateArea(samples: readonly LeakSample[], area: string): LeakReport {
  const latest = latestFlow(samples, area);
  const baseline = baselineNightFlow(samples.filter((s) => s.area === area));
  const ratio = baseline <= 0 ? 1 : latest / baseline;
  return {
    area,
    baseline,
    latest,
    ratio,
    alerted: ratio >= NIGHT_ALARM_RATIO,
  };
}

/** Night flow of the most recent sample for an area, 0 when absent. */
function latestFlow(samples: readonly LeakSample[], area: string): number {
  let worstInstant = -1;
  let flow = 0;
  for (const s of samples) {
    if (s.area === area && s.instant > worstInstant) {
      worstInstant = s.instant;
      flow = s.nightFlow;
    }
  }
  return flow;
}

export function alertedAreas(reports: readonly LeakReport[]): string[] {
  return reports.filter((r) => r.alerted).map((r) => r.area);
}

"""),
]

# ================= module: %s =================

# -*- coding: utf-8 -*-
"""reports/ modules of the cistern corpus (legacy loose style)."""

CREPORTS = [
    ("src/reports/rows.ts", """// rows.ts: text table rendering shared by the report writers. Columns
// align to their widest cell; separators use Unicode box characters so
// generated artefacts diff cleanly across platforms.

export interface Column {
  readonly title: string;
  readonly align: "left" | "right";
}

export interface Cell {
  readonly text: string;
}

export type Row = readonly Cell[];

/** Build an aligned text table from a title row and data rows. */
export function renderTable(columns«A:readonly Column[]», rows«A: readonly Row[]»)«A:string» {
  const widths: number[] = [];
  for (let c = 0; c < columns.length; c += 1) {
    const col = columns[c];
    if (col === undefined) {
      continue;
    }
    let w = col.title.length;
    for (const r of rows) {
      const cell = r[c];
      const len = cell === undefined ? 0 : cell.text.length;
      if (len > w) {
        w = len;
      }
    }
    widths[c] = w;
  }
  const header = columns.map((col, c) => pad(col.title, widths[c] ?? 0, "right")).join(" | ");
  const line = widths.map((w) => "-".repeat(w)).join("-+-");
  const body = rows.map((r) => renderRow(r, columns, widths)).join("\\n");
  return [header, line, body].join("\\n");
}

function renderRow(r: readonly Cell[], columns: readonly Column[], widths: readonly number[]): string {
  return columns
    .map((col, c) => {
      const cell = r[c];
      const text = cell === undefined ? "" : cell.text;
      return pad(text, widths[c] ?? 0, col.align);
    })
    .join(" | ");
}

/** Pad to width with the given alignment. */
export function pad(text«A:string», width«A:number», align«A:"left" | "right"»)«A:string» {
  if (text.length >= width) {
    return text;
  }
  const fill = " ".repeat(width - text.length);
  return align === "right" ? fill + text : text + fill;
}

/** Format a number with thousands separators. */
export function format(n«A:number»)«A:string» {
  const neg = n < 0;
  const digits = Math.abs(n).toString();
  const parts: string[] = [];
  for (let i = digits.length; i > 0; i -= 3) {
    parts.unshift(digits.slice(Math.max(0, i - 3), i));
  }
  return (neg ? "-" : "") + parts.join(",");
}

/** Row of a report section with a section label. */
export interface Section {
  readonly title: string;
  readonly rows: readonly Row[];
}

"""),
]

# ================= module: %s =================

# -*- coding: utf-8 -*-
"""reports/ + service/ + legacy/ + version/ + index modules of the corpus.
"""

CSVC = [
    ("src/reports/zonal.ts", """// zonal.ts: per-zone summary reports assembled from ledgers and
// telemetry, together with the text table writer that renders them.

import { type Segment } from "../data/ledger.js";
import { type RawRecord, readStr, readNum, readFlag } from "../data/records.js";
import { type Column, format } from "./rows.js";

export interface ZoneSummary {
  readonly zone: string;
  readonly meterCount: number;
  readonly consumption: number;
  readonly revenueCents: number;
  readonly leakageRatio: number;
}

/** Summarise a zone from its meter segments and pricing inputs. */
export function summarizeZone(
  zone: string,
  segmentsByMeter: ReadonlyMap<string, readonly Segment[]>,
  priceCents: number,
  nightFlow: number,
  meterCounts: ReadonlyMap<string, number>,
): ZoneSummary {
  let consumption = 0;
  let revenue = 0;
  for (const segs of segmentsByMeter.values()) {
    for (const s of segs) {
      consumption += s.consumption;
      revenue += s.consumption * priceCents;
    }
  }
  let meterTotal = 0;
  for (const count of meterCounts.values()) {
    meterTotal += count;
  }
  return {
    zone: zone.length === 0 ? "ALL" : zone,
    meterCount: meterTotal,
    consumption,
    revenueCents: Math.round(revenue),
    leakageRatio: nightFlow,
  };
}

/** Column descriptors shared by zone reports. */
export function zoneColumns(): Column[] {
  return [
    { title: "ZONE", align: "left" },
    { title: "METERS", align: "right" },
    { title: "VOLUME", align: "right" },
    { title: "REVENUE", align: "right" },
    { title: "LEAK", align: "right" },
  ];
}

/** One text row of a zone summary. */
export function zoneRow(summary: ZoneSummary): string[] {
  return [
    summary.zone,
    format(summary.meterCount),
    format(summary.consumption),
    format(summary.revenueCents),
    String(summary.leakageRatio),
  ];
}

/** Sort zones by total consumption descending. */
export function rankZones(summaries: readonly ZoneSummary[]): ZoneSummary[] {
  return [...summaries].sort(
    (a, b) => b.consumption - a.consumption || a.zone.localeCompare(b.zone),
  );
}

/** Build zone summaries from one raw record per zone. */
export function summariesFromRows(rows: readonly RawRecord[]): ZoneSummary[] {
  const out: ZoneSummary[] = [];
  for (const r of rows) {
    const zone = readStr(r, "zone");
    const consumption = readNum(r, "consumption");
    const revenue = readNum(r, "revenue");
    if (zone === undefined || consumption === undefined || revenue === undefined) {
      continue;
    }
    out.push({
      zone,
      meterCount: readNum(r, "meters") ?? 0,
      consumption,
      revenueCents: Math.round(revenue),
      leakageRatio: readNum(r, "leak") ?? 0,
    });
  }
  return out;
}

/** True when a summary exceeds a reporting threshold on leakage. */
export function flagged(summary: ZoneSummary, leakCap: number): boolean {
  return summary.leakageRatio > leakCap;
}

"""),
    ("src/service/ingest.ts", """// ingest.ts: validating telemetry ingest. Each line becomes a raw
// record; the ingestor checks the key grammar and the required fields
// before accepting the line into the store.

import { type RawRecord } from "../data/records.js";

export type IngestOutcome = "accepted" | "rejected" | "deferred";

export interface IngestResult {
  readonly outcome: IngestOutcome;
  readonly reason: string;
}

export interface Ingestor {
  readonly name: string;
  readonly indexBy: string;
  readonly required: readonly string[];
}

export interface IngestSink {
  accept(rec: RawRecord): void;
  defer(rec: RawRecord): void;
}

/** Validate one raw record against the ingestor's contract. */
export function ingestRecord(pool: Ingestor, rec: RawRecord, sink: IngestSink): IngestResult {
  if (!validateKeys(rec)) {
    return { outcome: "rejected", reason: "record keys fail the grammar" };
  }
  const missing = collectMissing(pool.required, rec);
  if (missing.length > 0) {
    sink.defer(rec);
    return { outcome: "deferred", reason: `missing ${missing.join(",")}` };
  }
  const idx = rec[pool.indexBy];
  if (typeof idx !== "string") {
    return { outcome: "rejected", reason: "index field is not a string" };
  }
  sink.accept(rec);
  return { outcome: "accepted", reason: "" };
}

/** Every record key must match the tidy identifier grammar. */
function validateKeys(rec: RawRecord): boolean {
  for (const k of Object.keys(rec)) {
    if (!/^[A-Za-z][A-Za-z0-9_]*$/.test(k)) {
      return false;
    }
  }
  return true;
}

/** Fields required by the pool that the record does not carry. */
function collectMissing(required: readonly string[], rec: RawRecord): string[] {
  const out: string[] = [];
  for (const r of required) {
    if (rec[r] === undefined) {
      out.push(r);
    }
  }
  return out;
}

"""),
    ("src/service/reconcile.ts", """// reconcile.ts — the end-to-end pipeline of the library. Raw
// configuration plus telemetry records become a report in one pass:
// freeze config, build the network, ingest meters and readings, run the
// balance and print the report text.

import { freezeConfig } from "../model/config.js";
import { ZoneRegistry } from "../model/zone.js";
import { type RawRecord, readStr, readNum } from "../data/records.js";

export interface ReconcileOutput {
  readonly report: string;
  readonly zoneCount: number;
  readonly meterCount: number;
  readonly consumed: number;
  readonly leaked: boolean;
}

/** Telemetry line-kind classification for the ingest loop. */
function classifyKind(kind: unknown): "meter" | "reading" | "other" {
  if (kind === "meter") {
    return "meter";
  }
  if (kind === "reading") {
    return "reading";
  }
  return "other";
}

/**
 * Run the pipeline over raw configuration and telemetry records in the
 * canonical ordering: config, network, ingest, balance, report.
 */
export function reconcile(
  rawConfig: RawRecord,
  metrics: Iterable<RawRecord>,
): ReconcileOutput {
  const frozen = freezeConfig(rawConfig);
  if (!frozen.ok || frozen.config === null) {
    throw new Error("cannot reconcile with an invalid configuration");
  }
  const cfg = frozen.config;
  const zones = new ZoneRegistry([]);
  let meterCount = 0;
  let consumed = 0;
  let leaked = false;
  for (const rec of metrics) {
    const kind = classifyKind(rec["kind"]);
    if (kind === "meter") {
      const serial = readStr(rec, "serial");
      if (serial !== undefined) {
        meterCount += 1;
      }
      continue;
    }
    if (kind !== "reading") {
      continue;
    }
    const zone = readStr(rec, "zone");
    const flow = readNum(rec, "flow");
    if (zone === undefined || flow === undefined) {
      continue;
    }
    consumed += flow;
    if (flow > 3 * cfg.horizonDays) {
      leaked = true;
    }
  }
  const report = renderText(cfg.name, zones.size(), meterCount, consumed, leaked);
  return { report, zoneCount: zones.size(), meterCount, consumed, leaked };
}

/** Compose the final report text. */
export function renderText(
  name: string,
  zoneCount: number,
  meterCount: number,
  consumed: number,
  leaked: boolean,
): string {
  const lines: string[] = [];
  lines.push(`report=${name}`);
  lines.push(`zones=${zoneCount}`);
  lines.push(`meters=${meterCount}`);
  lines.push(`consumed=${consumed}`);
  lines.push(`leaked=${leaked ? "yes" : "no"}`);
  return lines.join("\\n");
}

"""),
]

# ================= module: %s =================

# -*- coding: utf-8 -*-
"""legacy/, version.ts and index.ts modules — written in the loose legacy
style except version/index which are strict-correct.
"""

CLEGACY = [
    ("src/legacy/parsers.ts", """// parsers.ts: legacy flat-file parsers kept for import compatibility.
// The modern pipeline prefers the records layer; these parsers tolerate
// ragged columns and unknown headers.

import { type RawRecord } from "../data/records.js";

export interface ParsedTable {
  readonly headers: string[];
  readonly rows: readonly RawRecord[];
}

/** Parse comma-separated lines with optional quoted fields. */
export function parseCsv(text: string): ParsedTable {
  const lines = text.split("\\n");
  const headerLine = lines[0];
  if (headerLine === undefined) {
    return { headers: [], rows: [] };
  }
  const headers = splitLine(headerLine);
  const rows: RawRecord[] = [];
  for (let i = 1; i < lines.length; i += 1) {
    const line = lines[i];
    if (line === undefined || line.trim().length === 0) {
      continue;
    }
    const cells = splitLine(line);
    const rec: RawRecord = {};
    for (let c = 0; c < headers.length; c += 1) {
      const header = headers[c];
      if (header === undefined) {
        continue;
      }
      const cell = cells[c];
      if (cell !== undefined) {
        rec[header] = cell;
      }
    }
    rows.push(rec);
  }
  return { headers, rows };
}

/** Split a CSV line honouring double-quoted spans. */
function splitLine(line: string): string[] {
  const out: string[] = [];
  let cur = "";
  let quoted = false;
  for (let i = 0; i < line.length; i += 1) {
    const ch = line[i];
    if (ch === undefined) {
      break;
    }
    if (ch === '"') {
      quoted = !quoted;
      continue;
    }
    if (ch === "," && !quoted) {
      out.push(cur);
      cur = "";
      continue;
    }
    cur += ch;
  }
  out.push(cur);
  return out;
}

/** Parse "key=value" lines into records (leet style metadata files). */
export function parseEquals(text: string): RawRecord {
  const out: RawRecord = {};
  for (const line of text.split("\\n")) {
    const idx = line.indexOf("=");
    if (idx <= 0) {
      continue;
    }
    const key = line.slice(0, idx).trim();
    if (key.length === 0) {
      continue;
    }
    const value = line.slice(idx + 1).trim();
    out[key] = value.length > 0 ? value : undefined;
  }
  return out;
}

/** Number of non-empty data rows in a table. */
export function dataRowCount(table: ParsedTable): number {
  return table.rows.filter((r) => Object.keys(r).length > 0).length;
}

"""),
    ("src/legacy/extract.ts", """// extract.ts: heuristics for pulling structure out of loose text —
// meter serials, zone identifiers and timing tokens. Used by the import
// path that predates the validated record pipeline.

/** Extract a meter serial from free-form text, if recognisable. */
export function extractSerial(fragment: string): string | undefined {
  const m = /(?:MTR|M|mtr)[-_]([A-Z0-9]{4,6})/i.exec(fragment);
  if (m === null) {
    return undefined;
  }
  return "MTR-" + m[1]«P».toUpperCase();
}

/** Extract a zone/sector pair from a label like "N1.S2 (waypoint)". */
export function extractZone(label: string): string | undefined {
  const m = /^([A-Z]\\d+)(?:\\.([A-Z]\\d+))?/.exec(label);
  if (m === null) {
    return undefined;
  }
  const zone = m[1];
  const sector = m[2];
  if (sector === undefined) {
    return zone;
  }
  return `${zone}.${sector}`;
}

/** Split an ISO timestamp into day and second-of-day. */
export function splitTs(timestamp: string): { day: number; seconds: number } {
  const m = /^(\\d{4})-(\\d{2})-(\\d{2})T(\\d{2}):(\\d{2}):(\\d{2})/.exec(timestamp);
  if (m === null) {
    return { day: 0, seconds: 0 };
  }
  const day = Number(m[3]) + 31 * Number(m[2]) + 366 * Number(m[1]);
  const seconds = Number(m[5]) * 60 + Number(m[6]);
  return { day, seconds };
}

/** Serialise a summary as equals lines. */
export function typedefs(pairs: readonly [string, string | number][]): string {
  const out: string[] = [];
  for (const [k, v] of pairs) {
    out.push(`${k}=${v}`);
  }
  return out.join("\\n");
}

"""),
    ("src/version.ts", """// version.ts — library identity and the feature flag surface.

export const VERSION = "1.4.2";

export interface FeatureFlags {
  readonly strictLedgers: boolean;
  readonly telemGapFill: boolean;
}

export function currentFlags(): FeatureFlags {
  return { strictLedgers: true, telemGapFill: true };
}

"""),
    ("src/index.ts", """// cistern — a water-distribution modelling and billing library.
//
// Public surface of the library. Barrel files re-export only named
// symbols so consumers cannot see private helpers.

export { CisError, invariant, assertRange, unknownKey } from "./util/errors.js";
export { VERSION, currentFlags } from "./version.js";

export { freezeConfig, horizonSpan } from "./model/config.js";
export { Network, NodeEnt, distanceKm, linkKey } from "./model/network.js";
export { Zone, ZoneRegistry } from "./model/zone.js";
export { CisterStore } from "./store/store.js";

export { readStr, readNum, readFlag, hasField } from "./data/records.js";
export { toTimeline, fillGaps, mean, stdev, rollingMean, meanFlow } from "./data/telemetry.js";
export { parseMeter, buildSegments, totalVolume, medianVolume, crossingCount, peakSegment } from "./data/ledger.js";
export { tariffFromRows, priceForVolume, reachesTopTier, averagePrice, lookupTariff } from "./data/tariffs.js";

export { solveBalance, pressureAt } from "./algo/hydraulics.js";
export { cluster, distance, center } from "./algo/cluster.js";
export { blend, compliant, bestShare } from "./algo/mix.js";
export { hopDistances, reachable, eccentricity } from "./algo/shortest.js";
export { corrections, rainFactor, applyCorrections } from "./data/weather.js";
export { dailyLines, detailTotal } from "./reports/detail.js";
export { evaluateArea, baselineNightFlow, alertedAreas } from "./algo/leak.js";

export { renderTable, format, pad } from "./reports/rows.js";
export { summarizeZone, rankZones, summariesFromRows, flagged } from "./reports/zonal.js";
export { ingestRecord } from "./service/ingest.js";
export { reconcile, renderText } from "./service/reconcile.js";
export { parseCsv, parseEquals, dataRowCount } from "./legacy/parsers.js";
export { extractSerial, extractZone, splitTs } from "./legacy/extract.js";

"""),
]

# ================= module: %s =================

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

# ================= module: %s =================

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

# ================= module: %s =================

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

# ================= module: %s =================

# -*- coding: utf-8 -*-
"""Third wave: zone clustering, water-quality blending, detail reports
and the supplementary matrix tests."""

CADDF = [
    ("src/algo/cluster.ts", """// cluster.ts: zone clustering over average flows. Zones that behave
// alike for a season are grouped into a cluster; the clustering is
// agglomerative with a deterministic merge order, so results are stable
// across runs.

export interface FlowPoint {
  readonly zone: string;
  readonly flows: readonly number[];
}

export interface Cluster {
  readonly members: string[];
  readonly center: readonly number[];
}

/** Euclidean distance between two flow vectors. */
export function distance(a: readonly number[], b: readonly number[]): number {
  const n = Math.max(a.length, b.length);
  let acc = 0;
  for (let i = 0; i < n; i += 1) {
    const d = (a[i] ?? 0) - (b[i] ?? 0);
    acc += d * d;
  }
  return Math.sqrt(acc);
}

/** Mean vector of a set of flow vectors. */
export function center(points: readonly (readonly number[])[]): number[] {
  if (points.length === 0) {
    return [];
  }
  const n = points[0]?.length ?? 0;
  const out: number[] = [];
  for (let i = 0; i < n; i += 1) {
    let sum = 0;
    for (const p of points) {
      sum += p[i] ?? 0;
    }
    out.push(sum / points.length);
  }
  return out;
}

/** Two-way merge of index pairs with the smallest distance first. */
export function mergeOrder(clusters: readonly number[][]): [number, number][] {
  const pairs: [number, number][] = [];
  for (let i = 0; i < clusters.length; i += 1) {
    for (let j = i + 1; j < clusters.length; j += 1) {
      pairs.push([i, j]);
    }
  }
  pairs.sort((a, b) => {
    const a0 = a[0] ?? 0;
    const a1 = a[1] ?? 0;
    const b0 = b[0] ?? 0;
    const b1 = b[1] ?? 0;
    const da = clusters[a0]?.[a1] ?? Infinity;
    const db = clusters[b0]?.[b1] ?? Infinity;
    return da - db;
  });
  return pairs;
}

/** Agglomerative clustering of flow points down to k clusters. */
export function cluster(points: readonly FlowPoint[], k: number): Cluster[] {
  const clusters = points.map((p) => ({ members: [p.zone], center: p.flows }));
  const n = clusters.length;
  if (k <= 0 || k >= n) {
    return clusters;
  }
  let dist = buildMatrix(clusters);
  while (clusters.length > k) {
    const [i, j] = nearestPair(dist);
    if (i === j) {
      break;
    }
    const merged = clusters[i]!;
    for (const m of clusters[j]?.members ?? []) {
      merged.members.push(m);
    }
    const centers = merged.members
      .map((zone) => points.find((p) => p.zone === zone)?.flows ?? [])
      .filter((c) => c.length > 0);
    merged.center = center(centers);
    clusters.splice(j, 1);
    dist = buildMatrix(clusters);
  }
  return clusters;
}

function buildMatrix(clusters: readonly { members: string[]; center: readonly number[] }[]): number[][] {
  const m: number[][] = [];
  for (const a of clusters) {
    m.push(clusters.map((b) => distance(a.center, b.center)));
  }
  return m;
}

/** Index pair of the smallest non-diagonal distance. */
function nearestPair(dist: readonly (readonly number[])[]): [number, number] {
  let best: [number, number] = [0, 1];
  let bestD = Infinity;
  for (let i = 0; i < dist.length; i += 1) {
    for (let j = i + 1; j < dist.length; j += 1) {
      const d = dist[i]?.[j] ?? Infinity;
      if (d < bestD) {
        bestD = d;
        best = [i, j];
      }
    }
  }
  return best;
}

/** Flatten cluster memberships into a zone -> cluster index map. */
export function labelsOf(clusters: readonly Cluster[]): Map<string, number> {
  const out = new Map<string, number>();
  clusters.forEach((c, idx) => {
    for (const m of c.members) {
      out.set(m, idx);
    }
  });
  return out;
}

"""),
    ("src/algo/mix.ts", """// mix.ts: water-quality blending at a node fed by two sources. The
// blended quality index is the flow-weighted harmonic-style mix used by
// the utility's compliance checks. Deterministic and bounded.

export interface Source {
  readonly id: string;
  readonly flow: number;
  readonly quality: number;
}

export interface BlendResult {
  readonly quality: number;
  readonly minQuality: number;
  readonly maxQuality: number;
}

/** Flow-weighted blended quality of two or more sources. */
export function blend(sources: readonly Source[]): BlendResult {
  let totalFlow = 0;
  for (const s of sources) {
    totalFlow += s.flow;
  }
  if (totalFlow <= 0) {
    return { quality: 0, minQuality: 0, maxQuality: 0 };
  }
  let sum = 0;
  let minQ = Infinity;
  let maxQ = -Infinity;
  for (const s of sources) {
    sum += s.flow * s.quality;
    if (s.quality < minQ) {
      minQ = s.quality;
    }
    if (s.quality > maxQ) {
      maxQ = s.quality;
    }
  }
  return { quality: sum / totalFlow, minQuality: minQ, maxQuality: maxQ };
}

/** Compliance flag against a minimum quality standard. */
export function compliant(result: BlendResult, standard: number): boolean {
  return result.quality >= standard && result.minQuality >= standard * 0.9;
}

/** Proportion of flow coming from the best source. */
export function bestShare(sources: readonly Source[]): number {
  let bestQ = -Infinity;
  let bestFlow = 0;
  for (const s of sources) {
    if (s.quality > bestQ) {
      bestQ = s.quality;
      bestFlow = s.flow;
    }
  }
  return bestFlow;
}

"""),
    ("src/reports/detail.ts", """// detail.ts: daily detail reports: one block of equals-format rows per
// meter per day, ending with a separator line. Byte-identical output for
// identical inputs.

import { type Segment } from "../data/ledger.js";
import { type Meter } from "../data/ledger.js";

export interface DailyLine {
  readonly meter: string;
  readonly day: number;
  readonly volume: number;
}

/** Aggregate segments into per-meter, per-day lines. */
export function dailyLines(segmentsByMeter: ReadonlyMap<string, readonly Segment[]>): DailyLine[] {
  const out: DailyLine[] = [];
  for (const [serial, segs] of segmentsByMeter) {
    for (const s of segs) {
      out.push({
        meter: serial,
        day: dayOfInstant(s.fromInstant),
        volume: s.consumption,
      });
    }
  }
  out.sort((a, b) => a.day - b.day || a.meter.localeCompare(b.meter));
  return out;
}

/** Day number containing an instant. */
export function dayOfInstant(instant: number): number {
  return Math.floor(instant / 86400);
}

/** Render daily detail lines for one meter. */
export function renderDetails(meter: Meter, lines: readonly DailyLine[]): string {
  const rows: string[] = [];
  for (const l of lines) {
    if (l.meter === meter.serial) {
      rows.push(`${l.day}:${l.volume}`);
    }
  }
  rows.push(`---${meter.serial}`);
  return rows.join("\\n");
}

/** Total volume across all daily lines. */
export function detailTotal(lines: readonly DailyLine[]): number {
  let sum = 0;
  for (const l of lines) {
    sum += l.volume;
  }
  return sum;
}

"""),
]

# ================= module: %s =================

# -*- coding: utf-8 -*-
"""Fourth wave: shortest-path analysis and rainfall/demand weather
correction, plus relaxed extreme-district default tables."""

CADDG = [
    ("src/algo/shortest.ts", """// shortest.ts: breadth-first shortest paths over the district network.
// Distances are hop counts; the layer also reports the diameter of the
// reachable component containing a seed node.

import { type Network } from "../model/network.js";

export interface PathResult {
  readonly distances: ReadonlyMap<string, number>;
  readonly reachable: readonly string[];
  readonly diameter: number;
}

/** Hop distances from a source over the network. */
export function hopDistances(network: Network, source: string): PathResult {
  const distances = new Map<string, number>();
  const queue: string[] = [source];
  distances.set(source, 0);
  let head = 0;
  while (head < queue.length) {
    const node = queue[head]!;
    head += 1;
    const d = distances.get(node) ?? 0;
    for (const nb of network.neighbours(node)) {
      if (!distances.has(nb)) {
        distances.set(nb, d + 1);
        queue.push(nb);
      }
    }
  }
  const reachable = [...distances.keys()];
  let diameter = 0;
  for (const v of distances.values()) {
    if (v > diameter) {
      diameter = v;
    }
  }
  return { distances, reachable, diameter };
}

/** True when `to` is reachable from `from`. */
export function reachable(network: Network, from: string, to: string): boolean {
  return hopDistances(network, from).distances.has(to);
}

/** Eccentricity of a node: the maximum hop distance from it. */
export function eccentricity(network: Network, source: string): number {
  return hopDistances(network, source).diameter;
}

/** All nodes within `maxHops` of every seed. */
export function commonArea(network: Network, seeds: readonly string[], maxHops: number): string[] {
  if (seeds.length === 0) {
    return [];
  }
  const first = seeds[0] ?? "";
  const keep = new Set(hopDistances(network, first).distances.keys());
  for (let i = 1; i < seeds.length; i += 1) {
    const seed = seeds[i];
    if (seed === undefined) {
      continue;
    }
    const d = hopDistances(network, seed).distances;
    for (const node of keep) {
      const hop = d.get(node);
      if (hop === undefined || hop > maxHops) {
        keep.delete(node);
      }
    }
  }
  return [...keep].sort();
}

"""),
    ("src/data/weather.ts", """// weather.ts: rainfall observations and the demand correction they
// imply. Wet days pull garden demand down; the correction is a smooth
// clamp so reports remain deterministic.

export interface RainfallDay {
  readonly day: number;
  readonly mm: number;
}

export interface DemandCorrection {
  readonly day: number;
  readonly factor: number;
}

/** Rain factor for a single day, 1 at dry, lower when wet. */
export function rainFactor(mm: number): number {
  if (mm <= 0) {
    return 1;
  }
  return Math.max(0.55, 1 - mm / 40);
}

/** Correction series over a horizon for a rainfall table. */
export function corrections(rain: readonly RainfallDay[], horizonDays: number): DemandCorrection[] {
  const out: DemandCorrection[] = [];
  const byDay = new Map<number, number>();
  for (const r of rain) {
    byDay.set(r.day, r.mm);
  }
  for (let d = 0; d < horizonDays; d += 1) {
    const mm = byDay.get(d) ?? 0;
    out.push({ day: d, factor: rainFactor(mm) });
  }
  return out;
}

/** Total rain in the table. */
export function totalRain(rain: readonly RainfallDay[]): number {
  let sum = 0;
  for (const r of rain) {
    sum += r.mm;
  }
  return sum;
}

/** Fraction of wet days (>= 1mm) in the table. */
export function wetShare(rain: readonly RainfallDay[]): number {
  if (rain.length === 0) {
    return 0;
  }
  let wet = 0;
  for (const r of rain) {
    if (r.mm >= 1) {
      wet += 1;
    }
  }
  return wet / rain.length;
}

/** Apply corrections to a demand series, rounding to 3 decimals. */
export function applyCorrections(demands: readonly number[], corr: readonly DemandCorrection[]): number[] {
  const byDay = new Map<number, number>();
  for (const c of corr) {
    byDay.set(c.day, c.factor);
  }
  const out: number[] = [];
  for (let i = 0; i < demands.length; i += 1) {
    const base = demands[i] ?? 0;
    const factor = byDay.get(i) ?? 1;
    out.push(Math.round(base * factor * 1000) / 1000);
  }
  return out;
}

"""),
]

# ================= module: %s =================

# -*- coding: utf-8 -*-
"""vitest suite part 1: util, config, network, zone, store."""

TT = [
    ("tests/util.test.ts", '''// util.test.ts - money, keys, maths, natural order, periods, buckets.

import { describe, expect, it } from "vitest";
import {
  centsToEuros,
  eurosToCents,
  sumCents,
  scaleCents,
  surcharge,
  clampCents,
  isZero,
} from "../src/util/money.js";
import { makeKey, splitKey, zoneKey, meterKey, tariffKey, compareKeys } from "../src/util/keys.js";
import { lerp, clamp, trimDecimals, seededUnit, signOf, delta, relativeError } from "../src/util/math.js";
import { naturalCompare, naturalSort } from "../src/util/natural.js";
import { secondsOfDay, daysBetween, dayOf, dayBucket, periodStart, isNightly } from "../src/util/period.js";
import { equalWidth, bucketIndex, histogram, addHistograms } from "../src/util/buckets.js";
import { SeededRng } from "../src/util/seed.js";

describe("money", () => {
  it("converts euros to cents with half-even rounding", () => {
    expect(eurosToCents(1)).toBe(100);
    expect(eurosToCents(1.234)).toBe(123);
    expect(eurosToCents(1.235)).toBe(124);
    expect(eurosToCents(-0.5)).toBe(-50);
  });

  it("formats cents as euro strings", () => {
    expect(centsToEuros(0)).toBe("0.00");
    expect(centsToEuros(1234)).toBe("12.34");
    expect(centsToEuros(-5)).toBe("-0.05");
  });

  it("sums cents exactly", () => {
    expect(sumCents([1, 2, 3])).toBe(6);
    expect(sumCents([])).toBe(0);
  });

  it("scales and applies surcharges deterministically", () => {
    expect(scaleCents(100, 0.5)).toBe(50);
    expect(surcharge(100, 5)).toBe(105);
    expect(clampCents(150, 100)).toBe(100);
    expect(clampCents(-2, 100)).toBe(0);
    expect(isZero(0)).toBe(true);
    expect(isZero(1)).toBe(false);
  });
});

describe("keys", () => {
  it("builds and splits canonical keys", () => {
    const k = makeKey("z", "north", "res");
    expect(splitKey(k)).toEqual({ prefix: "z", parts: ["north", "res"] });
  });

  it("provides convenience constructors", () => {
    expect(zoneKey("n", "s1")).toBe("z:n:s1");
    expect(meterKey("d", "x")).toBe("m:d:x");
    expect(tariffKey("d", "winter")).toBe("t:d:winter");
  });

  it("compares keys lexicographically", () => {
    expect(compareKeys("a", "b")).toBe(-1);
    expect(compareKeys("b", "a")).toBe(1);
    expect(compareKeys("a", "a")).toBe(0);
  });
});

describe("math helpers", () => {
  it("interpolates and clamps", () => {
    expect(lerp(0, 10, 0.5)).toBe(5);
    expect(clamp(7, 0, 5)).toBe(5);
    expect(trimDecimals(1.23456, 2)).toBe(1.23);
  });

  it("seeded unit is deterministic and in range", () => {
    const a = seededUnit(7);
    const b = seededUnit(7);
    expect(a).toBe(b);
    expect(a >= 0 && a < 1).toBe(true);
  });

  it("computes signs, deltas and relative errors", () => {
    expect(signOf(-3)).toBe(-1);
    expect(delta(4, 6)).toBe(2);
    expect(relativeError(0, 0)).toBe(0);
    expect(relativeError(5, 5)).toBe(0);
    expect(relativeError(3, 1)).toBe(2);
  });
});

describe("natural order", () => {
  it("orders embedded numbers numerically", () => {
    expect(naturalCompare("R2", "R10")).toBe(-1);
    expect(naturalCompare("R10", "R2")).toBe(1);
    expect(naturalCompare("R2", "R2")).toBe(0);
  });

  it("sorts mixed ids", () => {
    const ids = ["R10", "R2", "R1b", "R1a", "R1"];
    const sorted = naturalSort(ids);
    expect(sorted).toEqual(["R1", "R1a", "R1b", "R2", "R10"]);
  });
});

describe("period arithmetic", () => {
  it("splits instants into days and buckets", () => {
    expect(secondsOfDay(1, 30)).toBe(5400);
    expect(daysBetween(0, 86400)).toBe(1);
    expect(dayOf(86400 * 2 + 5)).toBe(2);
    expect(dayBucket(10 * 3600)).toBe("morning");
    expect(dayBucket(20 * 3600)).toBe("evening");
    expect(dayBucket(2 * 3600)).toBe("night");
  });

  it("rounds to period starts and detects nightly windows", () => {
    expect(periodStart(3665, 3600)).toBe(3600);
    expect(isNightly(2 * 3600, 22 * 3600, 6 * 3600)).toBe(true);
    expect(isNightly(23 * 3600, 22 * 3600, 6 * 3600)).toBe(true);
    expect(isNightly(10 * 3600, 22 * 3600, 6 * 3600)).toBe(false);
  });
});

describe("buckets and rng", () => {
  it("builds equal-width buckets and histograms", () => {
    const buckets = equalWidth(0, 10, 5);
    expect(buckets.length).toBe(5);
    expect(bucketIndex(9.9, 0, 10, 5)).toBe(4);
    expect(bucketIndex(-1, 0, 10, 5)).toBe(0);
    expect(histogram([1, 1, 9], 0, 10, 5)).toEqual([2, 0, 0, 0, 1]);
    expect(addHistograms([1, 2], [3, 4, 5])).toEqual([4, 6, 5]);
  });

  it("seeded rng is reproducible", () => {
    const a = new SeededRng(42);
    const b = new SeededRng(42);
    expect(a.next()).toBe(b.next());
    expect(a.unit()).toBe(b.unit());
    expect(a.int(1, 6) >= 1 && a.int(1, 6) <= 6).toBe(true);
  });
});

'''),
    ("tests/config.test.ts", '''// config.test.ts - freezeConfig validation matrix.

import { describe, expect, it } from "vitest";
import { freezeConfig, horizonSpan, type FrozenConfig } from "../src/model/config.js";

describe("freezeConfig", () => {
  it("breaks without the required fields", () => {
    const { ok, issues } = freezeConfig({ name: "x" });
    expect(ok).toBe(false);
    expect(issues.length).toBeGreaterThan(0);
  });

  it.each([
    ["valid minimal", { name: "n", district: "north", season: "summer" }, true],
    ["with horizon", { name: "n", district: "north", season: "winter", horizonDays: 90 }, true],
    ["bad horizon", { name: "n", district: "north", season: "winter", horizonDays: 0 }, false],
    ["huge horizon", { name: "n", district: "north", season: "winter", horizonDays: 400 }, false],
    ["non-number horizon", { name: "n", district: "north", season: "winter", horizonDays: "x" }, false],
    ["bad curve", { name: "n", district: "north", season: "winter", demandCurve: "sine" }, false],
    ["float horizon", { name: "n", district: "north", season: "winter", horizonDays: 2.5 }, false],
  ])("handles: %s", (_label: string, raw: Record<string, string | number | boolean>, wantOk: boolean) => {
    const { ok } = freezeConfig(raw);
    expect(ok).toBe(wantOk);
  });

  it("applies defaults for absent optional fields", () => {
    const { ok, config } = freezeConfig({ name: "n", district: "north", season: "winter" });
    expect(ok).toBe(true);
    expect(config?.horizonDays).toBe(30);
    expect(config?.demandCurve).toBe("flat");
    expect(config?.tariffActive).toBe(true);
    expect(config?.demandActive).toBe(false);
    expect(config?.tariffLookup).toBe("default");
  });

  it("respects explicit flags and start day", () => {
    const { ok, config } = freezeConfig({
      name: "n",
      district: "north",
      season: "winter",
      demandActive: "yes",
      tariffActive: "no",
      startDay: 5,
    });
    expect(ok).toBe(true);
    expect(config?.demandActive).toBe(true);
    expect(config?.tariffActive).toBe(false);
    expect(config?.startDay).toBe(5);
    expect(horizonSpan(config as FrozenConfig)).toBe(30);
  });

  it("parses numeric strings as ints", () => {
    const { ok, config } = freezeConfig({
      name: "n",
      district: "east",
      season: "spring",
      horizonDays: "45",
    });
    expect(ok).toBe(true);
    expect(config?.horizonDays).toBe(45);
  });
});

'''),
    ("tests/network.test.ts", '''// network.test.ts - graph construction, traversal, distances.

import { describe, expect, it } from "vitest";
import { Network, distanceKm, linkKey, type NodeSpec, type LinkSpec } from "../src/model/network.js";

function sample(): { nodes: NodeSpec[]; links: LinkSpec[] } {
  const nodes: NodeSpec[] = [
    { id: "r1", kind: "reservoir", label: "Reservoir A", capacity: 1000, level: 800, point: { lon: 1, lat: 1 } },
    { id: "t1", kind: "tank", label: "Tank B", capacity: 500, level: 300, point: { lon: 2, lat: 2 } },
    { id: "j1", kind: "junction", label: "Junction C", capacity: 50, level: 10, point: { lon: 3, lat: 3 } },
    { id: "p1", kind: "pump", label: "Pump D", capacity: 80, level: 20, point: null },
  ];
  const links: LinkSpec[] = [
    { from: "r1", to: "t1", lengthM: 1000, diameterMm: 300, roughness: 110 },
    { from: "t1", to: "j1", lengthM: 800, diameterMm: 200, roughness: 100 },
    { from: "p1", to: "t1", lengthM: 400, diameterMm: 250, roughness: 120 },
  ];
  return { nodes, links };
}

describe("Network", () => {
  it("counts nodes and links", () => {
    const { nodes, links } = sample();
    const net = new Network(nodes, links);
    expect(net.nodeCount()).toBe(4);
    expect(net.linkCount()).toBe(3);
  });

  it("rejects duplicate node ids", () => {
    const { nodes, links } = sample();
    const dup = [...nodes, { ...nodes[0]! }];
    expect(() => new Network(dup as NodeSpec[], links)).toThrow();
  });

  it("resolves nodes and links", () => {
    const { nodes, links } = sample();
    const net = new Network(nodes, links);
    expect(net.hasNode("r1")).toBe(true);
    expect(net.hasNode("zz")).toBe(false);
    expect(net.node("r1").fillRatio()).toBeCloseTo(0.8);
    expect(net.node("r1").headroom()).toBe(200);
    expect(() => net.node("zz")).toThrow();
    expect(net.link("r1", "t1").from).toBe("r1");
    expect(() => net.link("r1", "j1")).toThrow();
  });

  it("lists neighbours in insertion order", () => {
    const { nodes, links } = sample();
    const net = new Network(nodes, links);
    expect(net.neighbours("t1")).toEqual(["j1"]);
    expect(net.neighbours("r1")).toEqual(["t1"]);
    expect(net.neighbours("j1")).toEqual([]);
  });

  it("sorts node ids by capacity", () => {
    const { nodes, links } = sample();
    const net = new Network(nodes, links);
    expect(net.sortedNodeIds()[0]).toBe("r1");
  });
});

describe("geometry", () => {
  it("computes the link key deterministically", () => {
    expect(linkKey("a", "b")).toBe("a->b");
  });

  it("approximates haversine distance", () => {
    const d = distanceKm({ lon: 0, lat: 0 }, { lon: 0, lat: 1 });
    expect(d).toBeCloseTo(111.19, 1);
  });
});

'''),
    ("tests/zone.test.ts", '''// zone.test.ts - zone registry semantics.

import { describe, expect, it } from "vitest";
import { ZoneRegistry, type ZoneSpec } from "../src/model/zone.js";

const SPECS: ZoneSpec[] = [
  { zone: "north", sector: "a", priority: 1, baselineDemand: 100 },
  { zone: "north", sector: "b", priority: 2, baselineDemand: 150 },
  { zone: "south", sector: "a", priority: 1, baselineDemand: 80 },
];

describe("ZoneRegistry", () => {
  it("registers and resolves zones", () => {
    const reg = new ZoneRegistry(SPECS);
    expect(reg.size()).toBe(3);
    expect(reg.has("z:north:a")).toBe(true);
    expect(reg.has("z:west:a")).toBe(false);
    expect(reg.get("z:north:a").priority).toBe(1);
    expect(() => reg.get("z:missing:a")).toThrow();
  });

  it("sorts keys and totals demand", () => {
    const reg = new ZoneRegistry(SPECS);
    expect(reg.keysSorted()).toEqual(["z:north:a", "z:north:b", "z:south:a"]);
    expect(reg.totalDemand()).toBe(330);
  });
});

'''),
    ("tests/store.test.ts", '''// store.test.ts - in-memory indexed store.

import { describe, expect, it } from "vitest";
import { CisterStore } from "../src/store/store.js";

interface Row {
  readonly zone: string;
  readonly meter: string;
  readonly flow: number;
}

const rowIndex: ReadonlyMap<string, (r: Row) => string | null> = new Map([
  ["zone", (r) => r.zone],
  ["meter", (r) => r.meter],
]);

function store(): CisterStore<Row> {
  return new CisterStore(["zone", "meter"], rowIndex);
}

describe("CisterStore", () => {
  it("inserts and fetches with monotonic ids", () => {
    const s = store();
    const doc = s.insert({ zone: "north", meter: "m1", flow: 12 });
    expect(doc.id).toBe("rec-0");
    expect(s.has(doc.id)).toBe(true);
    expect(s.get(doc.id)?.meter).toBe("m1");
  });

  it("indexes by multiple keys", () => {
    const s = store();
    const a = s.insert({ zone: "north", meter: "m1", flow: 1 });
    const b = s.insert({ zone: "north", meter: "m2", flow: 2 });
    expect(s.locate("zone", "north").sort()).toEqual([a.id, b.id].sort());
    expect(s.locate("meter", "m2")).toEqual([b.id]);
    expect(s.locate("meter", "nope")).toEqual([]);
  });

  it("rejects unknown indexes", () => {
    const s = store();
    expect(() => s.locate("bogus", "x")).toThrow();
  });

  it("reports size", () => {
    const s = store();
    s.insert({ zone: "north", meter: "m1", flow: 1 });
    expect(s.size()).toBe(1);
  });
});

'''),
]

# ================= module: %s =================

# -*- coding: utf-8 -*-
"""vitest suite part 2: records, telemetry, ledger, tariffs, hydraulics,
leak, forecast, pressure and reports."""

TT2 = [
    ("tests/records.test.ts", '''// records.test.ts - raw record readers.

import { describe, expect, it } from "vitest";
import {
  readStr,
  readNum,
  readFlag,
  hasField,
  validateRecordKeys,
  missingFields,
  requireFields,
  pickFields,
  fieldCount,
  type RawRecord,
} from "../src/data/records.js";

describe("record readers", () => {
  it("reads strings", () => {
    expect(readStr({ a: " x " }, "a")).toBe("x");
    expect(readStr({ a: "" }, "a")).toBe(undefined);
    expect(readStr({ a: 5 }, "a")).toBe(undefined);
    expect(readStr({}, "a")).toBe(undefined);
  });

  it("reads numbers", () => {
    expect(readNum({ a: 2.5 }, "a")).toBe(2.5);
    expect(readNum({ a: "3.5" }, "a")).toBe(3.5);
    expect(readNum({ a: "nan" }, "a")).toBe(undefined);
    expect(readNum({ a: Infinity }, "a")).toBe(undefined);
  });

  it("reads flags", () => {
    expect(readFlag({ a: 1 }, "a", false)).toBe(true);
    expect(readFlag({ a: "yes" }, "a", false)).toBe(true);
    expect(readFlag({ a: "no" }, "a", true)).toBe(false);
    expect(readFlag({}, "a", true)).toBe(true);
    expect(readFlag({ a: "maybe" }, "a", false)).toBe(false);
  });

  it("tests presence and key grammar", () => {
    expect(hasField({ a: undefined }, "a")).toBe(false);
    expect(hasField({ a: 0 }, "a")).toBe(true);
    expect(validateRecordKeys({ good_1: 1 })).toBe(true);
    expect(validateRecordKeys({ "bad-key": 1 })).toBe(false);
  });

  it("reports and requires fields", () => {
    const rec: RawRecord = { a: 1 };
    expect(missingFields(rec, ["a", "b"])).toEqual(["b"]);
    requireFields({ a: 1, b: 2 }, ["a", "b"]);
    expect(() => requireFields(rec, ["a", "b"])).toThrow();
  });

  it("picks fields and counts them", () => {
    const rec: RawRecord = { a: 1, b: "x", c: 2 };
    expect(pickFields(rec, ["a", "c"])).toEqual({ a: 1, c: 2 });
    expect(fieldCount(rec)).toBe(3);
    expect(fieldCount({})).toBe(0);
  });
});

'''),
    ("tests/telemetry.test.ts", '''// telemetry.test.ts - timelines, gap filling, statistics.

import { describe, expect, it } from "vitest";
import { toTimeline, fillGaps, mean, stdev, rollingMean, meanFlow, type Reading } from "../src/data/telemetry.js";
import { type RawRecord } from "../src/data/records.js";

function recs(): RawRecord[] {
  return [
    { kind: "reading", instant: 0, flow: 10, pressure: 4, quality: 99 },
    { kind: "reading", instant: 3600, flow: 20 },
    { kind: "reading", instant: 7200, flow: 30, pressure: 3.5 },
    { kind: "other", instant: 9999 },
  ];
}

describe("telemetry", () => {
  it("builds and dedupes timelines", () => {
    const tl = toTimeline(recs());
    expect(tl.length).toBe(3);
    expect(tl[0]?.pressure).toBe(4);
    expect(tl[1]?.pressure).toBe(0);
  });

  it("fills long gaps with interpolation", () => {
    const tl = toTimeline(recs());
    const filled = fillGaps(tl, 1000);
    expect(filled.length).toBeGreaterThan(tl.length);
    expect(filled[0]?.flow).toBe(10);
  });

  it("computes statistics", () => {
    expect(mean([2, 4, 6])).toBe(4);
    expect(mean([])).toBe(0);
    expect(stdev([2, 4, 6])).toBeCloseTo(2, 10);
    expect(stdev([1])).toBe(0);
  });

  it("computes a rolling mean", () => {
    const tl: Reading[] = [
      { instant: 0, flow: 10, pressure: 1, quality: 1 },
      { instant: 1, flow: 20, pressure: 1, quality: 1 },
      { instant: 2, flow: 30, pressure: 1, quality: 1 },
    ];
    expect(rollingMean(tl, 1)).toEqual([15, 20, 25]);
  });

  it("mean flow over raw records", () => {
    expect(meanFlow(recs())).toBe(20);
  });
});

'''),
    ("tests/ledger.test.ts", '''// ledger.test.ts - register segments, volumes, meters.

import { describe, expect, it } from "vitest";
import {
  parseMeter,
  buildSegments,
  totalVolume,
  medianVolume,
  crossingCount,
  peakSegment,
  busiestMeter,
  type Register,
  type Segment,
} from "../src/data/ledger.js";

const READS: readonly Register[] = [
  { instant: 0, register: 0 },
  { instant: 86400, register: 100 },
  { instant: 172800, register: 250 },
  { instant: 259200, register: 250 }, // reset
  { instant: 345600, register: 40 },
];

describe("ledger", () => {
  it("parses meter records", () => {
    const m = parseMeter({ serial: "M1", district: "north", unit: "litre" });
    expect(m.serial).toBe("M1");
    expect(m.unit).toBe("litre");
    expect(m.installedDay).toBe(1);
    const fallback = parseMeter({ serial: "M2", district: "south" });
    expect(fallback.unit).toBe(null);
  });

  it("builds segments handling resets", () => {
    const segs = buildSegments(READS, 172800);
    expect(segs.length).toBe(3);
  });

  it("totals volume across segments", () => {
    const segs = buildSegments(READS, 172800);
    expect(totalVolume(segs)).toBe(250);
  });

  it("splits long spans", () => {
    const wide: Register[] = [
      { instant: 0, register: 0 },
      { instant: 86400 * 10, register: 400 },
    ];
    const segs = buildSegments(wide, 86400);
    expect(segs.length).toBe(2);
    expect(totalVolume(segs)).toBe(400);
  });

  it("median and peaks", () => {
    const segs = buildSegments(READS, 172800);
    expect(medianVolume(segs)).toBeGreaterThan(0);
    expect(peakSegment(segs)).toBe(150);
    expect(crossingCount(segs, 86400)).toBe(1);
  });

  it("finds the busiest meter", () => {
    const meters = [
      { serial: "a", district: "north", unit: null, installedDay: 1 },
      { serial: "b", district: "north", unit: null, installedDay: 1 },
    ];
    const segments = new Map<string, readonly Segment[]>([
      ["a", buildSegments(READS, 172800)],
    ]);
    expect(busiestMeter(meters, segments)).toBe("a");
  });
});

'''),
    ("tests/tariffs.test.ts", '''// tariffs.test.ts - tiered pricing.

import { describe, expect, it } from "vitest";
import {
  tariffFromRows,
  priceForVolume,
  reachesTopTier,
  averagePrice,
  lookupTariff,
  type Tariff,
} from "../src/data/tariffs.js";
import { type RawRecord } from "../src/data/records.js";

const ROWS: RawRecord[] = [
  { upTo: 10, price: 100 },
  { upTo: 20, price: 150 },
  { upTo: 0, price: 0 },
  { upTo: 50, price: 200 },
];

describe("tariffs", () => {
  it("builds sorted tables", () => {
    const t = tariffFromRows("north", "summer", ROWS);
    expect(t.tiers.length).toBe(4);
  });

  it("prices volumes by tier", () => {
    const t = tariffFromRows("north", "summer", ROWS);
    expect(priceForVolume(t, 5)).toBe(500);
    expect(priceForVolume(t, 15)).toBe(1750);
    expect(priceForVolume(t, 25)).toBe(3500);
    expect(priceForVolume(t, 0)).toBe(0);
  });

  it("clips boundaries and computes averages", () => {
    const t = tariffFromRows("north", "summer", ROWS);
    expect(reachesTopTier(t, 100)).toBe(true);
    expect(reachesTopTier(t, 5)).toBe(false);
    expect(averagePrice(t, 10)).toBe(100);
  });

  it("looks tariffs up by district and season", () => {
    const tables: Tariff[] = [tariffFromRows("north", "summer", ROWS)];
    expect(lookupTariff(tables, "north", "summer")?.tiers.length).toBe(4);
    expect(lookupTariff(tables, "north", "winter")).toBe(undefined);
  });
});

'''),
]


TT2 += [
    ("tests/hydraulics.test.ts", '''// hydraulics.test.ts - flow balance and pressure.

import { describe, expect, it } from "vitest";
import { Network, type NodeSpec, type LinkSpec } from "../src/model/network.js";
import { solveBalance, pressureAt, nodeOutflow } from "../src/algo/hydraulics.js";

function smallNet(): Network {
  const nodes: NodeSpec[] = [
    { id: "r", kind: "reservoir", label: "R", capacity: 1000, level: 900, point: null },
    { id: "j", kind: "junction", label: "J", capacity: 100, level: 0, point: null },
  ];
  const links: LinkSpec[] = [{ from: "r", to: "j", lengthM: 500, diameterMm: 200, roughness: 110 }];
  return new Network(nodes, links);
}

describe("hydraulics", () => {
  it("produces a deterministic flow state", () => {
    const net = smallNet();
    const demands = new Map([["j", 25]]);
    const state = solveBalance(net, demands, 40);
    expect(state.iterations).toBe(40);
    expect(state.converged).toBe(true);
    expect(nodeOutflow(state, "r", net)).toBeGreaterThanOrEqual(0);
  });

  it("estimates pressure from level", () => {
    expect(pressureAt(100, 0)).toBeCloseTo(9.8, 1);
    expect(pressureAt(10, 100)).toBe(0);
  });
});

'''),
    ("tests/leak.test.ts", '''// leak.test.ts - night-flow leak detection.

import { describe, expect, it } from "vitest";
import { baselineNightFlow, evaluateArea, alertedAreas, type LeakSample } from "../src/algo/leak.js";

const SAMPLES: LeakSample[] = [
  { instant: 1, area: "north", nightFlow: 10 },
  { instant: 2, area: "north", nightFlow: 12 },
  { instant: 3, area: "north", nightFlow: 11 },
  { instant: 4, area: "north", nightFlow: 40 },
  { instant: 5, area: "south", nightFlow: 8 },
];

describe("leak detection", () => {
  it("baselines from the lower middle of samples", () => {
    const base = baselineNightFlow(SAMPLES.filter((s) => s.area === "north"));
    expect(base).toBeCloseTo(11.5, 6);
  });

  it("flags sustained rises", () => {
    const rep = evaluateArea(SAMPLES, "north");
    expect(rep.area).toBe("north");
    expect(rep.latest).toBe(40);
    expect(rep.alerted).toBe(true);
    expect(rep.ratio).toBeGreaterThan(1.3);
  });

  it("does not flag quiet areas", () => {
    const rep = evaluateArea(SAMPLES, "south");
    expect(rep.alerted).toBe(false);
  });

  it("collects alerted areas", () => {
    const reps = [evaluateArea(SAMPLES, "north"), evaluateArea(SAMPLES, "south")];
    expect(alertedAreas(reps)).toEqual(["north"]);
  });
});

'''),
    ("tests/forecast.test.ts", '''// forecast.test.ts - demand forecast and error metrics.

import { describe, expect, it } from "vitest";
import { baseline, dayAdjustment, forecastNext, mape, type DailyDemand } from "../src/algo/forecast.js";

function week(): DailyDemand[] {
  const out: DailyDemand[] = [];
  for (let d = 0; d < 14; d += 1) {
    out.push({ day: d, demand: 100 + (d % 3) * 10 });
  }
  return out;
}

describe("forecast", () => {
  it("computes a trailing baseline", () => {
    expect(baseline(week(), 7)).toBeCloseTo(110, 6);
    expect(baseline([], 7)).toBe(0);
  });

  it("adjusts by weekday", () => {
    const days: DailyDemand[] = [
      { day: 0, demand: 100 },
      { day: 1, demand: 110 },
      { day: 2, demand: 120 },
      { day: 7, demand: 100 },
      { day: 8, demand: 110 },
      { day: 9, demand: 120 },
    ];
    expect(baseline(days, 6)).toBeCloseTo(110, 6);
    expect(dayAdjustment(days, 6, 0)).toBeCloseTo(-10, 6);
  });

  it("forecasts forward", () => {
    const f = forecastNext(week(), 7, 14);
    expect(f).toBeGreaterThanOrEqual(0);
  });

  it("scores mean absolute percentage error", () => {
    expect(mape([100, 100], [90, 110])).toBe(10);
    expect(mape([], [])).toBe(0);
  });
});

'''),
    ("tests/pressure.test.ts", '''// pressure.test.ts - pressure regulation policy.

import { describe, expect, it } from "vitest";
import { deviation, nextValve, regulate, regulationScore, type RegSpec } from "../src/algo/pressure.js";

const SPEC: RegSpec = { node: "n1", setPoint: 4, band: 0.5 };

describe("pressure regulation", () => {
  it("measures deviation from the band", () => {
    expect(deviation({ instant: 0, node: "n1", pressure: 4, valve: 0.5 }, SPEC)).toBe(0);
    expect(deviation({ instant: 0, node: "n1", pressure: 5, valve: 0.5 }, SPEC)).toBe(0.5);
    expect(deviation({ instant: 0, node: "n1", pressure: 2, valve: 0.5 }, SPEC)).toBe(1.5);
  });

  it("moves the valve against the deviation", () => {
    expect(nextValve(0.5, 0.2, 0.1)).toBe(0.6);
    expect(nextValve(0.5, -0.2, 0.1)).toBe(0.4);
    expect(nextValve(0.95, 1, 0.1)).toBe(1);
    expect(nextValve(0.05, -1, 0.1)).toBe(0);
  });

  it("regulates a series within bounds", () => {
    const samples = regulate(SPEC, [3.5, 4.5, 5.5, 3.0], 0.1);
    expect(samples.length).toBe(4);
    expect(regulationScore(samples, SPEC)).toBeGreaterThan(0);
  });
});

'''),
    ("tests/reports.test.ts", '''// reports.test.ts - table rendering and zone summaries.

import { describe, expect, it } from "vitest";
import { renderTable, format, pad, type Column, type Row } from "../src/reports/rows.js";
import {
  summarizeZone,
  rankZones,
  summariesFromRows,
  flagged,
  zoneColumns,
  zoneRow,
  type ZoneSummary,
} from "../src/reports/zonal.js";
import { type RawRecord } from "../src/data/records.js";
import { type Segment } from "../src/data/ledger.js";

describe("table rendering", () => {
  it("pads cells to alignment", () => {
    expect(pad("x", 3, "right")).toBe("  x");
    expect(pad("x", 3, "left")).toBe("x  ");
  });

  it("groups digits", () => {
    expect(format(1234)).toBe("1,234");
    expect(format(-999)).toBe("-999");
  });

  it("renders a deterministic table", () => {
    const cols: Column[] = [
      { title: "ID", align: "left" },
      { title: "N", align: "right" },
    ];
    const rows: Row[] = [[{ text: "a" }, { text: "1" }]];
    const table = renderTable(cols, rows);
    expect(table).toContain("ID");
    expect(table).toContain("a");
  });
});

describe("zone summaries", () => {
  it("summarizes meters and revenue", () => {
    const segments = new Map<string, readonly Segment[]>();
    const s = summarizeZone("north", segments, 10, 0.5, new Map([["m1", 3]]));
    expect(s.zone).toBe("north");
    expect(s.meterCount).toBe(3);
    expect(s.leakageRatio).toBe(0.5);
  });

  it("ranks zones descending", () => {
    const a: ZoneSummary = { zone: "a", meterCount: 1, consumption: 10, revenueCents: 1, leakageRatio: 0 };
    const b: ZoneSummary = { zone: "b", meterCount: 1, consumption: 20, revenueCents: 2, leakageRatio: 0 };
    expect(rankZones([a, b])[0]?.zone).toBe("b");
  });

  it("reads summaries from rows and flags leaks", () => {
    const rows: RawRecord[] = [{ zone: "north", consumption: 10, revenue: 5, meters: 2 }];
    const list = summariesFromRows(rows);
    expect(list.length).toBe(1);
    expect(list[0]?.consumption).toBe(10);
    expect(flagged(list[0]!, 0.5)).toBe(false);
    expect(zoneColumns().length).toBe(5);
    expect(zoneRow(list[0]!).length).toBe(5);
  });
});

'''),
]

# ================= module: %s =================

# -*- coding: utf-8 -*-
"""Large matrix tests for the extra modules: clustering, blending,
detail reports, district tables and profile curves."""

TMATRIX = [
    ("tests/matrix.test.ts", '''// matrix.test.ts - data-driven contract matrix over the added modules.

import { describe, expect, it } from "vitest";
import { center, distance, cluster, mergeOrder, type FlowPoint } from "../src/algo/cluster.js";
import { blend, compliant, bestShare, type Source } from "../src/algo/mix.js";
import { dailyLines, renderDetails, detailTotal, dayOfInstant } from "../src/reports/detail.js";
import { type Segment } from "../src/data/ledger.js";
import { hourFactor, averageFactor, profileTable } from "../src/data/profiles.js";
import { DISTRICT_DEFAULTS } from "../src/data/district-defaults.js";
import { priceForVolume, tariffFromRows } from "../src/data/tariffs.js";
import { type RawRecord } from "../src/data/records.js";

describe("clustering", () => {
  const points: FlowPoint[] = [
    { zone: "a", flows: [1, 1, 1] },
    { zone: "b", flows: [1, 2, 1] },
    { zone: "c", flows: [9, 9, 9] },
    { zone: "d", flows: [8, 9, 8] },
  ];

  it("computes distances and centers", () => {
    expect(distance([0, 0], [3, 4])).toBe(5);
    expect(center([[1, 2], [3, 4]])).toEqual([2, 3]);
    expect(center([])).toEqual([]);
  });

  it("clusters similar zones together", () => {
    const out = cluster(points, 2);
    expect(out.length).toBe(2);
    const a = out[0]?.members ?? [];
    const b = out[1]?.members ?? [];
    expect([...a, ...b].sort()).toEqual(["a", "b", "c", "d"]);
  });

  it("returns single-zone clusters when k is large", () => {
    expect(cluster(points, 5).length).toBe(4);
  });

  it("emits a merge order", () => {
    const m: number[][] = [
      [0, 1, 5],
      [1, 0, 5],
      [5, 5, 0],
    ];
    expect(mergeOrder(m).length).toBe(3);
  });
});

describe("blending", () => {
  const srcs: Source[] = [
    { id: "s1", flow: 100, quality: 80 },
    { id: "s2", flow: 300, quality: 60 },
  ];

  it("blends by flow weight", () => {
    const r = blend(srcs);
    expect(r.quality).toBeCloseTo(65, 6);
    expect(r.minQuality).toBe(60);
    expect(r.maxQuality).toBe(80);
  });

  it("handles empty and zero-flow sets", () => {
    expect(blend([]).quality).toBe(0);
    const r = blend([{ id: "x", flow: 0, quality: 50 }]);
    expect(r.quality).toBe(0);
  });

  it("evaluates compliance and best share", () => {
    expect(compliant(blend(srcs), 60)).toBe(true);
    expect(compliant(blend(srcs), 70)).toBe(false);
    expect(bestShare(srcs)).toBe(100);
  });
});

describe("detail reports", () => {
  const segs = new Map<string, readonly Segment[]>([
    ["m1", [
      { fromInstant: 0, toInstant: 86400, consumption: 10 },
      { fromInstant: 86400, toInstant: 172800, consumption: 5 },
    ]],
    ["m2", [{ fromInstant: 0, toInstant: 86400, consumption: 3 }]],
  ]);

  it("aggregates daily lines", () => {
    const lines = dailyLines(segs);
    expect(lines.length).toBe(3);
    expect(detailTotal(lines)).toBe(18);
    expect(dayOfInstant(90000)).toBe(1);
  });

  it("renders per-meter detail blocks", () => {
    const lines = dailyLines(segs);
    const text = renderDetails({ serial: "m1", district: "north", unit: null, installedDay: 1 }, lines);
    expect(text).toContain("---m1");
  });
});

describe("profiles", () => {
  it("serves deterministic curves", () => {
    expect(profileTable("flat").length).toBe(24);
    expect(hourFactor("flat", 5)).toBe(1);
    expect(hourFactor("nightlow", 0)).toBeLessThan(hourFactor("nightlow", 12));
    expect(averageFactor("flat")).toBe(1);
  });
});

describe("district table matrix", () => {
  it("holds every pricing tier combination", () => {
    const expected = 16 * 4 * 5;
    expect(DISTRICT_DEFAULTS.length).toBe(expected);
  });

  it("prices a large volume across the whole tier matrix", () => {
    const rows: RawRecord[] = [
      { upTo: 10, price: 100 },
      { upTo: 10, price: 50 },
      { upTo: 0, price: 0 },
    ];
    const t = tariffFromRows("x", "y", rows);
    expect(priceForVolume(t, 10)).toBe(1000);
  });
});

'''),
]

# ================= module: %s =================

# -*- coding: utf-8 -*-
"""Matrix tests part 2: shortest paths, weather corrections and the
extended district tables."""

TMATRIX2 = [
    ("tests/matrix2.test.ts", '''// matrix2.test.ts - path analysis, weather correction, tables.

import { describe, expect, it } from "vitest";
import { Network, type NodeSpec, type LinkSpec } from "../src/model/network.js";
import { hopDistances, reachable, eccentricity, commonArea } from "../src/algo/shortest.js";
import { corrections, rainFactor, wetShare, totalRain, applyCorrections, type RainfallDay } from "../src/data/weather.js";
import { DISTRICT_DEFAULTS, countForDistrict, defaultDistricts } from "../src/data/district-defaults.js";
import { HYDRANTS, districtFlow } from "../src/data/hydrants.js";

function line(): Network {
  const nodes: NodeSpec[] = [
    { id: "a", kind: "junction", label: "a", capacity: 1, level: 0, point: null },
    { id: "b", kind: "junction", label: "b", capacity: 1, level: 0, point: null },
    { id: "c", kind: "junction", label: "c", capacity: 1, level: 0, point: null },
    { id: "d", kind: "junction", label: "d", capacity: 1, level: 0, point: null },
  ];
  const links: LinkSpec[] = [
    { from: "a", to: "b", lengthM: 100, diameterMm: 100, roughness: 100 },
    { from: "b", to: "a", lengthM: 100, diameterMm: 100, roughness: 100 },
    { from: "b", to: "c", lengthM: 100, diameterMm: 100, roughness: 100 },
    { from: "c", to: "b", lengthM: 100, diameterMm: 100, roughness: 100 },
    { from: "c", to: "d", lengthM: 100, diameterMm: 100, roughness: 100 },
    { from: "d", to: "c", lengthM: 100, diameterMm: 100, roughness: 100 },
  ];
  return new Network(nodes, links);
}

describe("shortest paths", () => {
  it("computes hop distances along a path", () => {
    const net = line();
    const r = hopDistances(net, "a");
    expect(r.distances.get("a")).toBe(0);
    expect(r.distances.get("c")).toBe(2);
    expect(r.diameter).toBe(3);
  });

  it("reports reachability and eccentricity", () => {
    const net = line();
    expect(reachable(net, "a", "d")).toBe(true);
    expect(reachable(net, "d", "a")).toBe(true);
    expect(eccentricity(net, "b")).toBe(2);
  });

  it("computes the common area of seeds", () => {
    const net = line();
    expect(commonArea(net, ["a", "d"], 3)).toEqual(["a", "b", "c", "d"]);
    expect(commonArea(net, [], 2)).toEqual([]);
  });
});

describe("weather corrections", () => {
  const rain: RainfallDay[] = [
    { day: 0, mm: 0 },
    { day: 1, mm: 10 },
    { day: 2, mm: 80 },
  ];

  it("maps rain to factors", () => {
    expect(rainFactor(0)).toBe(1);
    expect(rainFactor(10)).toBeCloseTo(0.75, 6);
    expect(rainFactor(200)).toBe(0.55);
  });

  it("builds correction series and aggregates", () => {
    const corr = corrections(rain, 3);
    expect(corr.length).toBe(3);
    expect(corr[0]?.factor).toBe(1);
    expect(totalRain(rain)).toBeCloseTo(90, 6);
    expect(wetShare(rain)).toBeCloseTo(2 / 3, 6);
    expect(wetShare([])).toBe(0);
  });

  it("applies corrections to a demand series", () => {
    const corr = corrections(rain, 3);
    const out = applyCorrections([100, 100, 100], corr);
    expect(out[0]).toBe(100);
    expect(out[1]).toBe(75);
    expect(out[2]).toBe(55);
  });
});

describe("extended tables", () => {
  it("covers fourteen districts", () => {
    expect(defaultDistricts().length).toBe(16);
    expect(countForDistrict("north")).toBe(20);
    expect(DISTRICT_DEFAULTS.length).toBeGreaterThan(300);
  });

  it("keeps district hydrant totals positive", () => {
    for (const d of defaultDistricts()) {
      expect(districtFlow(d)).toBeGreaterThan(0);
    }
    expect(HYDRANTS.length).toBeGreaterThan(150);
  });
});

'''),
]

# ================= module: %s =================

# -*- coding: utf-8 -*-
"""vitest suite for the cistern corpus, split across three parts.

CTESTS aggregates TT + TT2 + TT3 into one list for the assembler.
"""


TT3 = [
    ("tests/billing.test.ts", '''// billing.test.ts - invoice line assembly.

import { describe, expect, it } from "vitest";
import { invoiceLines, invoiceTotal, renderInvoice } from "../src/reports/billing.js";
import { tariffFromRows, type Tariff } from "../src/data/tariffs.js";
import { type RawRecord } from "../src/data/records.js";
import { type Segment } from "../src/data/ledger.js";

function tariff(): Tariff {
  return tariffFromRows("north", "summer", [
    { upTo: 10, price: 100 },
    { upTo: 1000, price: 150 },
  ] as RawRecord[]);
}

describe("billing", () => {
  it("builds one invoice line per segment", () => {
    const segs: Segment[] = [
      { fromInstant: 0, toInstant: 1, consumption: 5 },
      { fromInstant: 1, toInstant: 2, consumption: 20 },
    ];
    const lines = invoiceLines(segs, tariff());
    expect(lines.length).toBe(2);
    expect(lines[0]?.amountCents).toBe(500);
    expect(lines[1]?.amountCents).toBe(2500);
  });

  it("totals and renders invoices", () => {
    const segs: Segment[] = [{ fromInstant: 0, toInstant: 1, consumption: 5 }];
    const lines = invoiceLines(segs, tariff());
    expect(invoiceTotal(lines)).toBe(500);
    const text = renderInvoice(lines, "N");
    expect(text).toContain("5.00");
    expect(text).toContain("TOTAL");
  });
});

'''),
    ("tests/audit.test.ts", '''// audit.test.ts - audit log and digests.

import { describe, expect, it } from "vitest";
import { AuditLog, recordDigest } from "../src/service/audit.js";
import { type RawRecord } from "../src/data/records.js";

describe("audit", () => {
  it("records events in sequence", () => {
    const log = new AuditLog();
    log.note("read", "m1", "accepted");
    log.note("read", "m2", "accepted");
    expect(log.size()).toBe(2);
    expect(log.all()[0]?.seq).toBe(1);
    expect(log.contiguous()).toBe(true);
  });

  it("filters by kind", () => {
    const log = new AuditLog();
    log.note("read", "m1", "a");
    log.note("warn", "m1", "b");
    expect(log.ofKind("warn").length).toBe(1);
  });

  it("digests records deterministically", () => {
    const rec: RawRecord = { kind: "reading", flow: 12 };
    expect(recordDigest(rec)).toBe(recordDigest({ flow: 12, kind: "reading" }));
    expect(recordDigest(rec).length).toBe(8);
  });
});

'''),
    ("tests/ingest.test.ts", '''// ingest.test.ts - validation pipeline.

import { describe, expect, it } from "vitest";
import { ingestRecord, type Ingestor, type IngestSink, type IngestResult } from "../src/service/ingest.js";
import { type RawRecord } from "../src/data/records.js";

const POOL: Ingestor = { name: "meter", indexBy: "serial", required: ["serial", "district"] };

function sink(): IngestSink & { accepted: RawRecord[]; deferred: RawRecord[] } {
  const accepted: RawRecord[] = [];
  const deferred: RawRecord[] = [];
  return {
    accepted,
    deferred,
    accept(rec) {
      accepted.push(rec);
    },
    defer(rec) {
      deferred.push(rec);
    },
  };
}

describe("ingestRecord", () => {
  it("accepts valid records", () => {
    const s = sink();
    const r = ingestRecord(POOL, { serial: "m1", district: "north" }, s);
    expect(r.outcome).toBe("accepted");
    expect(s.accepted.length).toBe(1);
  });

  it("rejects malformed keys", () => {
    const s = sink();
    const r = ingestRecord(POOL, { "bad-key": 1, serial: "m1", district: "north" }, s);
    expect(r.outcome).toBe("rejected");
  });

  it("defers records with missing fields", () => {
    const s = sink();
    const r = ingestRecord(POOL, { serial: "m1" }, s);
    expect(r.outcome).toBe("deferred");
    expect(s.deferred.length).toBe(1);
  });

  it("rejects a missing index even when complete otherwise", () => {
    const s = sink();
    const pool: Ingestor = { name: "m", indexBy: "zone", required: [] };
    const r = ingestRecord(pool, { zone: 12 }, s);
    expect(r.outcome).toBe("rejected");
  });
});

'''),
    ("tests/reconcile.test.ts", '''// reconcile.test.ts - end-to-end pipeline.

import { describe, expect, it } from "vitest";
import { reconcile, renderText, type ReconcileOutput } from "../src/service/reconcile.js";
import { type RawRecord } from "../src/data/records.js";

describe("reconcile", () => {
  it("rejects invalid config", () => {
    const out = () =>
      reconcile({ name: "n" } as RawRecord, [{ kind: "reading", zone: "north", flow: 1 }]);
    expect(out).toThrow();
  });

  it("counts meters and sums consumption", () => {
    const config: RawRecord = { name: "n", district: "north", season: "summer" };
    const recs: RawRecord[] = [
      { kind: "meter", serial: "m1" },
      { kind: "meter", serial: "m2" },
      { kind: "reading", zone: "north", flow: 10 },
      { kind: "reading", zone: "north", flow: 5 },
    ];
    const out = reconcile(config, recs);
    expect(out.meterCount).toBe(2);
    expect(out.consumed).toBe(15);
    expect(out.leaked).toBe(false);
  });

  it("flags exceptional flows as leaks", () => {
    const config: RawRecord = { name: "n", district: "north", season: "summer", startDay: 30 };
    const recs: RawRecord[] = [{ kind: "reading", zone: "north", flow: 1000 }];
    const out = reconcile(config, recs);
    expect(out.consumed).toBe(1000);
    expect(out.leaked).toBe(true);
  });

  it("renders report text deterministically", () => {
    const text = renderText("run-a", 2, 3, 15, false);
    expect(text).toContain("report=run-a");
    expect(text).toContain("meters=3");
    const output: ReconcileOutput = { report: text, zoneCount: 2, meterCount: 3, consumed: 15, leaked: false };
    expect(output.report).toBe(text);
  });
});

'''),
    ("tests/legacy.test.ts", '''// legacy.test.ts - flat-file importers and extractors.

import { describe, expect, it } from "vitest";
import { parseCsv, parseEquals, dataRowCount } from "../src/legacy/parsers.js";
import { extractSerial, extractZone, splitTs } from "../src/legacy/extract.js";
import { rowToRecord, sortedColumns, project, type LegacyRow } from "../src/legacy/compat.js";
import { naturalSort } from "../src/util/natural.js";

describe("legacy parsers", () => {
  it("parses CSV with quoted fields", () => {
    const table = parseCsv("a,b\\nc,1\\n\\"d,2\\",3\\n");
    expect(table.headers).toEqual(["a", "b"]);
    expect(table.rows.length).toBe(2);
    expect(dataRowCount(table)).toBe(2);
  });

  it("parses key=value text", () => {
    const rec = parseEquals("zone=N1\\nauto=  yes  \\n# comment\\n");
    expect(rec.zone).toBe("N1");
    expect(rec.auto).toBe("yes");
  });

  it("extracts serials and zones", () => {
    expect(extractSerial("serial MTR-ab12 here")).toBe("MTR-AB12");
    expect(extractSerial("none")).toBe(undefined);
    expect(extractZone("N1.S2 (waypoint)")).toBe("N1.S2");
    expect(extractZone("N3")).toBe("N3");
  });

  it("splits timestamps", () => {
    const t = splitTs("2026-03-02T04:05:06");
    expect(t.day).toBe(366 * 2026 + 31 * 3 + 2);
    expect(t.seconds).toBe(306);
    expect(splitTs("garbage").day).toBe(0);
  });
});

describe("legacy compat", () => {
  it("converts rows to records", () => {
    const row: LegacyRow = { columns: ["a", "b"], values: ["1", "2"] };
    expect(rowToRecord(row)).toEqual({ a: "1", b: "2" });
    expect(sortedColumns(row)).toEqual(["a", "b"]);
  });

  it("projects records", () => {
    expect(project({ a: 1, b: 2 }, ["a"])).toEqual({ a: 1 });
    expect(naturalSort(["x10", "x2"])).toEqual(["x2", "x10"]);
  });
});

'''),
    ("tests/presets.test.ts", '''// presets.test.ts - district defaults, hydrants, presets, fixtures.

import { describe, expect, it } from "vitest";
import { presetRegistry, findPreset, presetNames } from "../src/data/presets.js";
import {
  DISTRICT_DEFAULTS,
  findDefault,
  defaultDistricts,
  countForDistrict,
  topDistricts,
} from "../src/data/district-defaults.js";
import { HYDRANTS, flaggedHydrants, districtPressure, districtFlow } from "../src/data/hydrants.js";
import { SEED_METERS, seedMeter, seedDistricts } from "../src/data/fixtures.js";

describe("presets", () => {
  it("knows the preset registry", () => {
    expect(presetRegistry().length).toBeGreaterThan(8);
    expect(findPreset("north-summer")?.district).toBe("north");
    expect(findPreset("missing")).toBe(undefined);
    expect(presetNames().length).toBe(presetRegistry().length);
  });
});

describe("district defaults", () => {
  it("carries a large consistent table", () => {
    expect(DISTRICT_DEFAULTS.length).toBeGreaterThan(150);
    expect(defaultDistricts().length).toBeGreaterThanOrEqual(8);
    expect(countForDistrict("north")).toBe(20);
  });

  it("resolves defaults by district and class", () => {
    const d = findDefault("north", "residential");
    expect(d?.zone).toBe("north-res");
    expect(d?.minPressure).toBeGreaterThan(0);
    expect(findDefault("mars", "residential")).toBe(undefined);
  });

  it("orders top districts by nominal", () => {
    const top = topDistricts(3);
    expect(top.length).toBeLessThanOrEqual(3);
  });
});

describe("hydrants", () => {
  it("holds the register and flags issues", () => {
    expect(HYDRANTS.length).toBeGreaterThan(100);
    expect(flaggedHydrants().length).toBeGreaterThan(0);
  });

  it("computes district aggregates", () => {
    expect(districtPressure("north")).toBeGreaterThan(0);
    expect(districtFlow("north")).toBeGreaterThan(0);
    expect(districtPressure("nope")).toBe(0);
  });
});

describe("fixtures", () => {
  it("serves seed meters", () => {
    expect(SEED_METERS.length).toBe(64);
    expect(seedMeter("MTR-0001")?.district).toBe("south");
    expect(seedMeter("missing")).toBe(undefined);
    expect(seedDistricts().length).toBeGreaterThanOrEqual(4);
  });
});

'''),
]

CTESTS = TT + TT2 + TT3 + TMATRIX + TMATRIX2

CTESTS = TT + TT2 + TT3 + TMATRIX + TMATRIX2
import os
import sys
import json

PKG = {
    "name": "cistern",
    "version": "1.4.2",
    "description": "water-distribution modelling, ledgers and billing (TypeScript)",
    "type": "module",
    "engines": {"node": ">=18"},
    "scripts": {"typecheck": "tsc --noEmit -p tsconfig.json", "test": "vitest run"},
    "devDependencies": {"typescript": "5.9.3", "vitest": "3.2.4", "vite": "7.2.2"},
}

VITEST_CFG = """import { defineConfig } from "vitest/config";

export default defineConfig({
  test: {
    include: ["tests/**/*.test.ts"],
    environment: "node",
  },
});
"""

README = """# cistern

A TypeScript library for water-distribution network modelling and billing:
telemetry ingestion, meter ledgers, tiered tariffs, flow balancing, nightly
leak detection and text reports.

## Commands

    npm run typecheck   # tsc --noEmit -p tsconfig.json
    npm test            # vitest run
"""

GITIGNORE = """node_modules/
coverage/
*.log
"""


def strict_config():
    """The fully hardened strict tsconfig the migration commits to."""
    import json as _json

    cfg = {
        "compilerOptions": {
            "target": "ES2022",
            "module": "ESNext",
            "moduleResolution": "bundler",
            "lib": ["ES2022"],
            "strict": True,
            "strictNullChecks": True,
            "noImplicitAny": True,
            "noUncheckedIndexedAccess": True,
            "exactOptionalPropertyTypes": True,
            "noImplicitOverride": True,
            "esModuleInterop": True,
            "forceConsistentCasingInFileNames": True,
            "skipLibCheck": True,
            "noEmit": True,
            "isolatedModules": True,
            "useDefineForClassFields": True,
            "types": [],
            "noUnusedLocals": False,
            "noUnusedParameters": False,
        },
        "include": ["src", "tests"],
    }
    return _json.dumps(cfg, indent=2)


def main() -> int:
    out = sys.argv[1] if len(sys.argv) > 1 else "/app/cistern"
    files = (
        CUT + CMODEL + CDATA + CDATA2 + CREPORTS + CSVC + CLEGACY
        + CADD + CADD2 + CADD3 + CADDF + CADDG + CTESTS
    )
    for rel, text in files:
        path = os.path.join(out, rel)
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "w", encoding="utf-8") as fh:
            fh.write(render(text, True))

    import json as _json

    with open(os.path.join(out, "package.json"), "w", encoding="utf-8") as fh:
        fh.write(_json.dumps(PKG, indent=2) + "\n")
    with open(os.path.join(out, "tsconfig.json"), "w", encoding="utf-8") as fh:
        fh.write(strict_config() + "\n")
    with open(os.path.join(out, "vitest.config.ts"), "w", encoding="utf-8") as fh:
        fh.write(VITEST_CFG)
    with open(os.path.join(out, "README.md"), "w", encoding="utf-8") as fh:
        fh.write(README)
    with open(os.path.join(out, ".gitignore"), "w", encoding="utf-8") as fh:
        fh.write(GITIGNORE)
    print("cistern migrated to strict mode at %s" % out)
    return 0


if __name__ == "__main__":
    sys.exit(main())
