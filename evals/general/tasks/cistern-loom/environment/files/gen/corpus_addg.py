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