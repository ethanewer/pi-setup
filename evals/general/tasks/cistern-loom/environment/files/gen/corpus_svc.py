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