// Hidden type-contract probe 2 for cistern-loom.
//
// The verifier drops this file into src/typetests/ and compiles the whole
// tree with the hardening flags on. Where probe1 pins exact exported
// types, this probe exercises the hardening regime itself: element access
// must be proven, optional properties must be read precisely, and the
// public surface must expose the exact unions the reports rely on.

import { type RawRecord, readNum, readStr, readFlag } from "../data/records.js";
import { parseCsv, parseEquals, type ParsedTable } from "../legacy/parsers.js";
import { type Reading, fillGaps } from "../data/telemetry.js";
import { type Cents, sumCents } from "../util/money.js";

// 1. Reading helpers keep their exact unions.
const n: number | undefined = readNum({ flow: "12.5" }, "flow");
const s: string | undefined = readStr({ serial: " M1 " }, "serial");
const flag: boolean = readFlag({ auto: "1" }, "auto", false);

// 2. CSV parsing keeps its shapes (ragged columns never crash the type).
const table: ParsedTable = parseCsv("a,b,c\n1,2,3\n");
const headers: readonly string[] = table.headers;
const firstHeader: string | undefined = headers[0];
const firstRow: RawRecord | undefined = table.rows[0];
const firstCell: string | number | boolean | undefined = firstRow === undefined ? undefined : firstRow[firstHeader ?? "a"];

// 3. Equals-parsing produces raw records.
const meta: RawRecord = parseEquals("zone=N2\npressure=4.2\n");

// 4. Gap filling must be provably safe element access under the hardening.
const tl: Reading[] = fillGaps(
  [
    { instant: 0, flow: 1, pressure: 3, quality: 90 },
    { instant: 4000, flow: 2, pressure: 2.8, quality: 90 },
  ],
  1000,
);
const lastFlow: number = tl[tl.length - 1]!.flow;

// 5. Money helpers keep exact integer semantics.
const total: Cents = sumCents([1, 2, 3]);

// The probe is type-only: it computes a summary string but never asserts.
export const probe2Summary: string =
  `${n}:${s}:${flag}:${table.rows.length}:${firstCell}:${meta.zone ?? "?"}:${lastFlow}:${total}`;