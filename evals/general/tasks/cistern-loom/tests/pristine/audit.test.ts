// audit.test.ts - audit log and digests.

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

