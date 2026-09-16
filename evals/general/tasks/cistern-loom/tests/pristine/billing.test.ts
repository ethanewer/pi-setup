// billing.test.ts - invoice line assembly.

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

