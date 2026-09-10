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