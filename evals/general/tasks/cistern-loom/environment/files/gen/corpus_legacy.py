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