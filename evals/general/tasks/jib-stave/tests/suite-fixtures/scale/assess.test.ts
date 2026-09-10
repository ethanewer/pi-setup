import test from "node:test";
import assert from "node:assert/strict";
import { assess, reify, summarize } from "../dist/index.js";
import { verify } from "@jibblin/core";

test("eu low-volume traffic is low risk", () => {
  const a = assess(
    { region: "eu", volume: 100, latencyMs: 100, priorBans: 0 },
    "access",
    1_700_000_000_000
  );
  assert.equal(a.band, "low");
  assert.ok(verify(a.token));
  assert.equal(a.token.kind, "access");
});

test("blocked band appears for extreme inputs", () => {
  const a = assess(
    { region: "us", volume: 50_000, latencyMs: 2000, priorBans: 9 },
    "access",
    1_700_000_000_000
  );
  assert.equal(a.band, "blocked");
  assert.ok(a.reasons.includes("high-volume-shape"));
});

test("reify only accepts assess tokens", () => {
  const a = assess({ region: "ap-south", volume: 1, latencyMs: 1, priorBans: 0 });
  const r = reify(a.token);
  assert.ok(r);
  assert.equal(r.region, "ap-south");
});

test("summarize unboxes the nonce payload", () => {
  const a = assess(
    { region: "eu", volume: 1, latencyMs: 1, priorBans: 0 },
    "guest",
    1_700_000_000_000
  );
  assert.match(summarize(a.token), /assess:eu/);
});
