# -*- coding: utf-8 -*-
"""vitest suite for the cistern corpus, split across three parts.

CTESTS aggregates TT + TT2 + TT3 into one list for the assembler.
"""

from corpus_tests_a import TT  # noqa: E402
from corpus_tests_b import TT2  # noqa: E402
from corpus_matrix import TMATRIX  # noqa: E402
from corpus_matrix2 import TMATRIX2  # noqa: E402

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
