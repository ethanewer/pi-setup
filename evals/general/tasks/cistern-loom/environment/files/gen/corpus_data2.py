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