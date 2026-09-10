// Hidden consumer h1 for the jibblin SDK: exercises the @jibblin/core and
// @jibblin/scale surfaces in depth (token kinds, base64url, crc, assessment
// unboxing). Compiled against the published packages through node_modules.
// This fixture is dropped into the workspace by the verifier only; it is not
// part of the shipped repo.
import {
  Token,
  TokenKind,
  issue,
  verify,
  crc32,
  encodeBase64Url,
  decodeBase64Url,
} from "@jibblin/core";
import {
  assess,
  reify,
  summarize,
  Assessment,
  AssessmentInput,
  RiskBand,
} from "@jibblin/scale";

const kinds: TokenKind[] = ["access", "refresh", "guest"];
const t: Token = issue("refresh", "svc/orders", 1_700_000_000_000);
if (!verify(t)) throw new Error("h1: verify failed");
if (!kinds.includes(t.kind)) throw new Error("h1: bad kind");

const round: string = decodeBase64Url(encodeBase64Url("k=v&a=1&sig=%2B%2F"));
if (round !== "k=v&a=1&sig=%2B%2F") throw new Error("h1: base64url mismatch");
const sum: number = crc32("h1-payload");
if (typeof sum !== "number" || sum <= 0) throw new Error("h1: crc32");

const input: AssessmentInput = {
  region: "ap-south",
  volume: 1200,
  latencyMs: 300,
  priorBans: 2,
};
const a: Assessment = assess(input, "access", 1_700_000_000_000);
const band: RiskBand = a.band;
if (a.token.kind !== "access") throw new Error("h1: assess kind");
const r = reify(a.token);
if (!r || r.region !== "ap-south") throw new Error("h1: reify failed");
const s: string = summarize(a.token);
if (!s.startsWith("[access] assess:ap-south")) throw new Error("h1: summarize");

console.log(`h1 consumer ok (band=${band})`);