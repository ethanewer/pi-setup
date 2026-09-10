// Downstream smoke fixture for the jibblin SDK.
// Compiled against the *published* packages exactly like a real consumer:
// resolution goes through node_modules and each package's exports/types
// entrypoints, never through workspace paths.
import { Client } from "@jibblin/api";
import { Token, issue, verify, ageSeconds } from "@jibblin/core";
import { assess, Assessment } from "@jibblin/scale";

const token: Token = issue("access", "alice", 1_700_000_000_000);
if (!verify(token)) throw new Error("verify failed");
const age: number = ageSeconds(token, 1_700_000_000_100);
if (age !== 0) throw new Error("age mismatch");

const client = new Client({ region: "eu", label: "checkout" });
const claim = client.assess(
  { region: "eu", volume: 5, latencyMs: 20, priorBans: 0 },
  1_700_000_000_000
);
const band: Assessment["band"] = claim.band;
if (band !== "low") throw new Error("unexpected band");
if (claim.token.kind !== "access") throw new Error("unexpected kind");

const direct = assess({ region: "us", volume: 1, latencyMs: 1, priorBans: 0 }, "guest");
const subject: string = direct.token.subject;
if (!subject.startsWith("assess:")) throw new Error("bad token");

console.log(`consumer ok: ${client.describe(claim.token)}`);
