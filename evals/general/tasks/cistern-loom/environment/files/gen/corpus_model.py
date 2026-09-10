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