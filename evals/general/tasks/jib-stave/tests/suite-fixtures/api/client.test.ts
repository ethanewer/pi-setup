import test from "node:test";
import assert from "node:assert/strict";
import { Client } from "../dist/index.js";
import { verify } from "@jibblin/core";

test("Client produces a verifiable access claim", () => {
  const c = new Client({ region: "eu", label: "billing" });
  const claim = c.assess(
    { region: "eu", volume: 100, latencyMs: 100, priorBans: 0 },
    1_700_000_000_000
  );
  assert.equal(claim.band, "low");
  assert.equal(claim.label, "billing");
  assert.ok(verify(claim.token));
  assert.equal(claim.ttlSeconds, 0);
});

test("describe unboxes the token", () => {
  const c = new Client({ region: "us", label: "edge" });
  const claim = c.assess(
    { region: "us", volume: 100, latencyMs: 100, priorBans: 0 },
    1_700_000_000_000
  );
  assert.match(c.describe(claim.token), /^edge -> access:assess:us/);
});

test("Client validates its label", () => {
  assert.throws(() => new Client({ region: "eu", label: "" }));
});
