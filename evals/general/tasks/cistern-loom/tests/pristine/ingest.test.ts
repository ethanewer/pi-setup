// ingest.test.ts - validation pipeline.

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

