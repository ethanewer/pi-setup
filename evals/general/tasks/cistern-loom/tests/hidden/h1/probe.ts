// Hidden type-contract probe 1 for cistern-loom.
//
// This file is dropped into src/typetests/ by the verifier and compiled as
// part of the tree. It compiles ONLY against a real strict migration that
// kept the exported types exact: every pin below binds a concrete type,
// so a migration that loosened, widened, or routed through `any` / casts
// fails to compile and the whole verdict goes to 0.
//
// NOT a runtime test: nothing here is executed by the suite.

import { type Reading, toTimeline, mean } from "../data/telemetry.js";
import { type RawRecord } from "../data/records.js";
import { buildSegments, medianVolume, parseMeter, type Segment } from "../data/ledger.js";
import { priceForVolume, tariffFromRows, type Tariff } from "../data/tariffs.js";
import { extractSerial, extractZone } from "../legacy/extract.js";
import { type ReconcileOutput, reconcile } from "../service/reconcile.js";
import { CisterStore } from "../store/store.js";
import { type Cents, centsToEuros, eurosToCents } from "../util/money.js";

// 1. toTimeline must accept raw records and produce Readings.
const rawRecords: RawRecord[] = [
  { kind: "reading", instant: 0, flow: 10, pressure: 4, quality: 99 },
  { kind: "reading", instant: 600, flow: 20 },
];
const timeline: Reading[] = toTimeline(rawRecords);
const firstFlow: number = timeline[0]!.flow;
const avg: number = mean([firstFlow, 20]);

// 2. Ledger shapes must be exact: unit is string|null, not string|undefined.
const meter = parseMeter({ serial: "MTR-0001", district: "north" });
const unitKind: string | null = meter.unit;
const segments: Segment[] = buildSegments(
  [
    { instant: 0, register: 0 },
    { instant: 86400, register: 120 },
  ],
  2 * 86400,
);
const med: number = medianVolume(segments);

// 3. Tariff pricing must keep its exact numerics.
const tierRows: RawRecord[] = [
  { upTo: 10, price: 100 },
  { upTo: 50, price: 150 },
];
const t: Tariff = tariffFromRows("north", "summer", tierRows);
const price: number = priceForVolume(t, 25);

// 4. Legacy extractors return the exact unions.
const serial: string | undefined = extractSerial("see MTR-ab12 here");
const zone: string | undefined = extractZone("N1.S2 (waypoint)");

// 5. Money stays in integer cents.
const cents: Cents = eurosToCents(3.5);
const textual: string = centsToEuros(cents);

// 6. Orchestration keeps its aggregate shape.
const out: ReconcileOutput = reconcile({ name: "n", district: "north", season: "summer" }, rawRecords);
const consumed: number = out.consumed;
const leaked: boolean = out.leaked;

// 7. The store stays generic over its index extractors.
interface ProbeRow {
  readonly zone: string;
  readonly flow: number;
}
const extractors: ReadonlyMap<string, (r: ProbeRow) => string | null> = new Map([
  ["zone", (r) => r.zone],
]);
const store = new CisterStore<ProbeRow>(["zone"], extractors);
const doc: string = store.insert({ zone: "north", flow: 7 }).id;

// Silenced type-level consumers so the file is genuinely type-only work.
export const probe1Summary: string =
  `${timeline.length}:${segments.length}:${price}:${serial}:${zone}:${textual}:${consumed}:${leaked}:${doc}:${avg}:${med}:${unitKind === null ? "bare" : "metered"}:${firstFlow + cents}`;