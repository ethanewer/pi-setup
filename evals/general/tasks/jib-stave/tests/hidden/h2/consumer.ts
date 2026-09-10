// Hidden consumer h2 for the jibblin SDK: drives the @jibblin/api facade
// (Client/ClientOptions/Claim) and the structured Token records it returns,
// plus direct core usage. Compiled against the published packages through
// node_modules. Dropped into the workspace by the verifier only.
import { Client, ClientOptions, Claim } from "@jibblin/api";
import { Token, issue, ageSeconds } from "@jibblin/core";

const opts: ClientOptions = { region: "us", label: "edge" };
const client = new Client(opts);

const claim: Claim = client.assess(
  { region: "us", volume: 8000, latencyMs: 400, priorBans: 1 },
  1_700_000_000_000
);

const issued: Token = issue("guest", "anon", 1_700_000_000_000);
const ttl: number = claim.ttlSeconds;
const token: Token = claim.token;

if (claim.label !== "edge") throw new Error("h2: label");
if (claim.band === "high" || claim.band === "blocked") throw new Error("h2: band");
if (token.kind === "guest") throw new Error("h2: kind");
if (token.issuedAt !== 1_700_000_000_000) throw new Error("h2: issuedAt");
if (ttl !== 0) throw new Error("h2: ttl");
if (typeof issued.nonce !== "string" || issued.nonce.length === 0) {
  throw new Error("h2: nonce");
}
if (ageSeconds(issued, 1_700_000_000_000 + 5_000) !== 5) {
  throw new Error("h2: ageSeconds");
}

console.log(`h2 consumer ok (region=${client.region})`);