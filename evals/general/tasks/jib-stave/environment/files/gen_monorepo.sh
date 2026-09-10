#!/usr/bin/env bash
# gen_monorepo.sh - build the jibblin SDK monorepo fixture into TARGET.
#
# Reproducible fixture generator for the jib-stave task. It:
#   1. writes the complete monorepo (3 npm-workspace packages + consumer) as real
#      source: token primitives, an assessment layer, a public client facade,
#      and downstream consumers, all self-authored,
#   2. builds a plausible git history commit by commit,
#   3. installs dependencies (network available at image build time) and proves
#      the suite is green before the skew is applied: build, tests, consumer
#      compile,
#   4. then applies the deliberate dependency/version skew that the task is
#      about and commits it as a single unverified "release" commit,
#   5. leaves the tree pristine apart from the skew (no dist output committed).
#
# Usage: gen_monorepo.sh TARGET_DIR
set -euo pipefail

TARGET=${1:?usage: gen_monorepo.sh TARGET_DIR}
# npm is already on PATH in the base image (node 22.23.2); pin it explicitly.
NPM_BIN=$(command -v npm)
TSC="$TARGET/node_modules/.bin/tsc"

rm -rf "$TARGET"
mkdir -p "$TARGET"
cd "$TARGET"

# --------------------------------------------------------------------------
# 1. root scaffold
# --------------------------------------------------------------------------
cat > package.json <<'EOF'
{
  "name": "jibblin-sdk-monorepo",
  "version": "2.1.0",
  "private": true,
  "description": "jibblin SDK - workspace monorepo (core primitives, scale layer, public api)",
  "workspaces": [
    "packages/*"
  ],
  "scripts": {
    "build": "tsc -b tsconfig.build.json",
    "build:ws": "npm run build -ws",
    "test": "npm run test -ws",
    "clean": "npm run clean -ws"
  },
  "devDependencies": {
    "@types/node": "20.17.30",
    "typescript": "5.5.4"
  },
  "license": "MIT"
}
EOF

cat > tsconfig.base.json <<'EOF'
{
  "compilerOptions": {
    "target": "ES2022",
    "module": "Node16",
    "moduleResolution": "Node16",
    "strict": true,
    "declaration": true,
    "esModuleInterop": true,
    "forceConsistentCasingInFileNames": true,
    "skipLibCheck": true,
    "sourceMap": false,
    "declarationMap": false
  }
}
EOF

cat > tsconfig.build.json <<'EOF'
{
  "files": [],
  "references": [
    { "path": "./packages/core" },
    { "path": "./packages/scale" },
    { "path": "./packages/api" }
  ]
}
EOF

cat > .gitignore <<'EOF'
node_modules/
dist/
*.tsbuildinfo
.consumers/
EOF

cat > README.md <<'EOF'
# jibblin SDK monorepo

Three-package npm workspace shipping the jibblin SDK, currently on the **2.1.0**
release line:

- `@jibblin/core` - token primitives: `Token` records, `issue`, `verify`,
  `ageSeconds`, base64url encoding, and a CRC-32 checksum helper.
- `@jibblin/scale` - assessment layer: `assess`, `reify`, `summarize`; the
  risk-band model for inbound traffic.
- `@jibblin/api` - public facade: `Client`, `ClientOptions`, `Claim`.

## Layout

```
packages/core    token primitives (no workspace deps)
packages/scale   depends on @jibblin/core
packages/api     depends on @jibblin/core and @jibblin/scale
consumer/        downstream smoke fixture compiling against the published packages
```

## Build

```
npm ci            # install from the committed lockfile
npm run build     # tsc -b over all three packages (one build, one output)
npm test          # per-package node --test suites
```

`tsc` build uses project references, so `npm run build -ws` succeeds regardless
of workspace order. The `consumer/` fixture type-checks against the *published*
packages (through their `exports`/`types` entrypoints), not against sources.
EOF

git init -q
git add package.json tsconfig.base.json tsconfig.build.json .gitignore README.md
git commit -qm "chore: scaffold npm-workspace monorepo (tsc project references)"

# --------------------------------------------------------------------------
# 2. @jibblin/core
# --------------------------------------------------------------------------
mkdir -p packages/core/src packages/core/test
cat > packages/core/package.json <<'EOF'
{
  "name": "@jibblin/core",
  "version": "2.1.0",
  "description": "token and checksum primitives for the jibblin sdk",
  "main": "dist/index.js",
  "types": "dist/index.d.ts",
  "exports": {
    ".": {
      "types": "./dist/index.d.ts",
      "require": "./dist/index.js",
      "import": "./dist/index.js"
    }
  },
  "scripts": {
    "build": "tsc -b tsconfig.json",
    "test": "node --test",
    "clean": "rm -rf dist tsconfig.tsbuildinfo"
  },
  "license": "MIT"
}
EOF

cat > packages/core/tsconfig.json <<'EOF'
{
  "extends": "../../tsconfig.base.json",
  "compilerOptions": {
    "outDir": "dist",
    "rootDir": "src",
    "composite": true
  },
  "include": ["src"]
}
EOF

cat > packages/core/src/index.ts <<'EOF'
/**
 * @jibblin/core - token primitives for the jibblin SDK.
 *
 * A Token is a signed-field record: kind, subject, issue time, a nonce, and a
 * CRC-32 checksum over the other fields. Consumers verify integrity with
 * `verify`; nothing here depends on another workspace package.
 */

export type TokenKind = "access" | "refresh" | "guest";

export interface Token {
  kind: TokenKind;
  subject: string;
  issuedAt: number;
  nonce: string;
  checksum: number;
}

const CRC_TABLE = (() => {
  const t = new Array<number>(256);
  for (let i = 0; i < 256; i++) {
    let c = i;
    for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
    t[i] = c >>> 0;
  }
  return t;
})();

/** CRC-32 (ISO 3309 / zlib polynomial), exported for use by other packages. */
export function crc32(data: string): number {
  let c = 0xffffffff;
  for (let i = 0; i < data.length; i++) {
    c = CRC_TABLE[(c ^ data.charCodeAt(i)) & 0xff] ^ (c >>> 8);
  }
  return (c ^ 0xffffffff) >>> 0;
}

/** Encode a string as base64url (no padding). */
export function encodeBase64Url(plain: string): string {
  const t = Buffer.from(plain, "utf8").toString("base64");
  return t.replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

/** Decode a base64url string (padding optional). */
export function decodeBase64Url(encoded: string): string {
  const pad =
    encoded.length % 4 === 0 ? "" : "=".repeat(4 - (encoded.length % 4));
  return Buffer.from(
    (encoded + pad).replace(/-/g, "+").replace(/_/g, "/"),
    "base64"
  ).toString("utf8");
}

/** Issue a token for `subject` at time `now` (ms epoch). */
export function issue(
  kind: TokenKind,
  subject: string,
  now: number = Date.now()
): Token {
  const nonce = encodeBase64Url(`${now.toString(16)}:${subject}:${kind}`);
  return {
    kind,
    subject,
    issuedAt: now,
    nonce,
    checksum: crc32(`${kind}\u0000${subject}\u0000${now}\u0000${nonce}`),
  };
}

/** Integrity check: checksum must match the token's own fields. */
export function verify(token: Token): boolean {
  if (!token || typeof token !== "object") return false;
  const expected = crc32(
    `${token.kind}\u0000${token.subject}\u0000${token.issuedAt}\u0000${token.nonce}`
  );
  return (
    token.checksum === expected && typeof token.issuedAt === "number"
  );
}

/** Whole seconds since issue, floored at zero. */
export function ageSeconds(token: Token, now: number = Date.now()): number {
  return Math.max(0, Math.floor((now - token.issuedAt) / 1000));
}
EOF

cat > packages/core/test/token.test.ts <<'EOF'
import test from "node:test";
import assert from "node:assert/strict";
import {
  issue,
  verify,
  ageSeconds,
  crc32,
  decodeBase64Url,
  encodeBase64Url,
} from "../dist/index.js";

test("issue+verify round trip", () => {
  const t = issue("access", "alice", 1_700_000_000_000);
  assert.equal(t.kind, "access");
  assert.equal(t.subject, "alice");
  assert.ok(verify(t));
});

test("tampered checksum fails", () => {
  const t = issue("refresh", "bob", 1_700_000_000_000);
  t.checksum = t.checksum ^ 0xffff;
  assert.equal(verify(t), false);
});

test("ageSeconds is bounded below", () => {
  const t = issue("guest", "nobody", 1_700_000_000_000);
  assert.equal(ageSeconds(t, 1_700_000_000_000 - 5000), 0);
});

test("base64url round trip", () => {
  const s = "hello +=/ world";
  assert.equal(decodeBase64Url(encodeBase64Url(s)), s);
});

test("crc32 is stable", () => {
  assert.equal(crc32("jibblin"), 0xb0742717);
});
EOF

git add packages/core
git commit -qm "feat(core): token primitives with crc32 checksums"

# --------------------------------------------------------------------------
# 3. @jibblin/scale
# --------------------------------------------------------------------------
mkdir -p packages/scale/src packages/scale/test
cat > packages/scale/package.json <<'EOF'
{
  "name": "@jibblin/scale",
  "version": "2.1.0",
  "description": "assessment and rating layer over @jibblin/core tokens",
  "main": "dist/index.js",
  "types": "dist/index.d.ts",
  "exports": {
    ".": {
      "types": "./dist/index.d.ts",
      "require": "./dist/index.js",
      "import": "./dist/index.js"
    }
  },
  "dependencies": {
    "@jibblin/core": "^2.1.0"
  },
  "scripts": {
    "build": "tsc -b tsconfig.json",
    "test": "node --test",
    "clean": "rm -rf dist tsconfig.tsbuildinfo"
  },
  "license": "MIT"
}
EOF

cat > packages/scale/tsconfig.json <<'EOF'
{
  "extends": "../../tsconfig.base.json",
  "compilerOptions": {
    "outDir": "dist",
    "rootDir": "src",
    "composite": true,
    "paths": {
      "@jibblin/core": ["../core/src/index.ts"]
    }
  },
  "include": ["src"],
  "references": [{ "path": "../core" }]
}
EOF

cat > packages/scale/src/index.ts <<'EOF'
/**
 * @jibblin/scale - assessment layer.
 *
 * Turns raw request telemetry into a risk-band verdict plus an issued Token,
 * and can reify/unbox tokens it previously issued.
 */
import {
  Token,
  TokenKind,
  issue,
  verify,
  decodeBase64Url,
} from "@jibblin/core";

export type RiskBand = "low" | "elevated" | "high" | "blocked";

export interface AssessmentInput {
  region: string;
  volume: number;
  latencyMs: number;
  priorBans: number;
}

export interface Assessment {
  band: RiskBand;
  score: number;
  token: Token;
  reasons: string[];
}

/** Score an AssessmentInput into a band + token. EU traffic gets a discount. */
export function assess(
  input: AssessmentInput,
  kind: TokenKind = "guest",
  now: number = Date.now()
): Assessment {
  const reasons: string[] = [];
  let score = 50;

  if (input.region === "eu") score -= 15;
  if (input.volume > 10_000) {
    score += 15;
    reasons.push("high-volume-shape");
  }
  if (input.latencyMs > 900) {
    score += 10;
    reasons.push("slow-path");
  }
  if (input.priorBans > 0) {
    score += 5 * Math.min(input.priorBans, 5);
    reasons.push("prior-bans");
  }

  const band: RiskBand =
    score >= 80 ? "blocked" : score >= 65 ? "high" : score >= 40 ? "elevated" : "low";

  return {
    band,
    score: Math.min(100, Math.max(0, score)),
    token: issue(kind, `assess:${input.region}`, now),
    reasons,
  };
}

/** Recover the AssessmentInput a token was issued for (null if not ours). */
export function reify(token: Token): AssessmentInput | null {
  if (!verify(token)) return null;
  const marker = "assess:";
  if (!token.subject.startsWith(marker)) return null;
  const region = token.subject.slice(marker.length).toLowerCase();
  return { region, volume: 0, latencyMs: 0, priorBans: 0 };
}

/** Human-readable one-liner for a token. */
export function summarize(token: Token): string {
  const payload = decodeBase64Url(token.nonce);
  return `[${token.kind}] ${token.subject} issued ${payload}`;
}
EOF

cat > packages/scale/test/assess.test.ts <<'EOF'
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
EOF

git add packages/scale
git commit -qm "feat(scale): assessment layer over core tokens"

# --------------------------------------------------------------------------
# 4. @jibblin/api
# --------------------------------------------------------------------------
mkdir -p packages/api/src packages/api/test
cat > packages/api/package.json <<'EOF'
{
  "name": "@jibblin/api",
  "version": "2.1.0",
  "description": "public facade of the jibblin sdk",
  "main": "dist/index.js",
  "types": "dist/index.d.ts",
  "exports": {
    ".": {
      "types": "./dist/index.d.ts",
      "require": "./dist/index.js",
      "import": "./dist/index.js"
    }
  },
  "dependencies": {
    "@jibblin/core": "^2.1.0",
    "@jibblin/scale": "^2.1.0"
  },
  "scripts": {
    "build": "tsc -b tsconfig.json",
    "test": "node --test",
    "clean": "rm -rf dist tsconfig.tsbuildinfo"
  },
  "license": "MIT"
}
EOF

cat > packages/api/tsconfig.json <<'EOF'
{
  "extends": "../../tsconfig.base.json",
  "compilerOptions": {
    "outDir": "dist",
    "rootDir": "src",
    "composite": true,
    "paths": {
      "@jibblin/core": ["../core/src/index.ts"],
      "@jibblin/scale": ["../scale/src/index.ts"]
    }
  },
  "include": ["src"],
  "references": [{ "path": "../core" }, { "path": "../scale" }]
}
EOF

cat > packages/api/src/index.ts <<'EOF'
/**
 * @jibblin/api - the public face of the jibblin SDK.
 *
 * Wraps @jibblin/scale in a labelled Client so downstream services can assess
 * traffic, keep a claim (band + token + ttl), and describe tokens.
 */
import { Token, ageSeconds, decodeBase64Url } from "@jibblin/core";
import {
  Assessment,
  AssessmentInput,
  assess,
  RiskBand,
} from "@jibblin/scale";

export interface ClientOptions {
  region: string;
  label: string;
}

export interface Claim {
  token: Token;
  band: RiskBand;
  score: number;
  label: string;
  ttlSeconds: number;
}

export class Client {
  private readonly options: ClientOptions;

  constructor(options: ClientOptions) {
    if (!options || typeof options.label !== "string" || options.label.length === 0) {
      throw new Error("Client requires a non-empty label");
    }
    this.options = { ...options };
  }

  /** Assess traffic and return a labelled claim with a verifiable token. */
  public assess(input: AssessmentInput, now: number = Date.now()): Claim {
    const a: Assessment = assess(input, "access", now);
    return {
      token: a.token,
      band: a.band,
      score: a.score,
      label: this.options.label,
      ttlSeconds: ageSeconds(a.token, now),
    };
  }

  /** Render a token as a labelled one-liner (unboxes the nonce). */
  public describe(token: Token): string {
    return `${this.options.label} -> ${token.kind}:${token.subject} nonce=${decodeBase64Url(token.nonce)}`;
  }

  public get region(): string {
    return this.options.region;
  }
}
EOF

cat > packages/api/test/client.test.ts <<'EOF'
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
EOF

git add packages/api
git commit -qm "feat(api): public client facade over core and scale"

# --------------------------------------------------------------------------
# 5. visible consumer fixture (downstream smoke project)
# --------------------------------------------------------------------------
mkdir -p consumer
cat > consumer/tsconfig.json <<'EOF'
{
  "compilerOptions": {
    "module": "Node16",
    "moduleResolution": "Node16",
    "target": "ES2022",
    "strict": true,
    "noEmit": true,
    "skipLibCheck": false,
    "types": ["node"]
  },
  "include": ["consumer.ts"]
}
EOF

cat > consumer/consumer.ts <<'EOF'
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
EOF

git add consumer
git commit -qm "chore(consumer): downstream smoke fixture against published packages"

# --------------------------------------------------------------------------
# 6. install + prove the green state
# --------------------------------------------------------------------------
"$NPM_BIN" install --no-audit --no-fund --loglevel=error
git add package-lock.json
git commit -qm "chore: lockfile for the 2.1.0 release line"

npm run build -ws
npm test -ws
"$TSC" -p "$TARGET/consumer/tsconfig.json"

# --------------------------------------------------------------------------
# 7. apply the deliberate dependency/version skew
# --------------------------------------------------------------------------
python3 - <<'PY'
import json
from pathlib import Path

root = Path(".")

# (a) scale's own version slips to the old 1.2.0 line; sibling api still
#     vas referenced it directly, so the workspace "installs" but the release
#     line metadata is inconsistent with the lockfile and with core.
scale = json.loads((root / "packages/scale/package.json").read_text())
scale["version"] = "1.2.0"
(root / "packages/scale/package.json").write_text(json.dumps(scale, indent=2) + "\n")

# (b) api pins its sibling to that stale line.
api = json.loads((root / "packages/api/package.json").read_text())
api["dependencies"]["@jibblin/scale"] = "1.2.0"
(root / "packages/api/package.json").write_text(json.dumps(api, indent=2) + "\n")

# (c) core's published entrypoints are pointed at a stale packaged snapshot
#     (lib/) from the 1.4 era instead of the build output, so consumers that
#     resolve the *published* package see declarations that do not match the
#     current source.
core = json.loads((root / "packages/core/package.json").read_text())
core["main"] = "lib/index.js"
core["types"] = "lib/index.d.ts"
core["exports"] = {
    ".": {
        "types": "./lib/index.d.ts",
        "require": "./lib/index.js",
        "import": "./lib/index.js",
    }
}
(root / "packages/core/package.json").write_text(json.dumps(core, indent=2) + "\n")
PY

mkdir -p packages/core/lib
cat > packages/core/lib/index.d.ts <<'EOF'
/**
 * @jibblin/core 1.4.0 - packaged declaration snapshot.
 *
 * DO NOT EDIT: this is a published snapshot checked out of the release
 * cache. Rebuild the package and republish to refresh it.
 */
export type TokenKind = "access" | "refresh" | "guest";

/**
 * 1.4-era tokens were opaque strings; the 1.4 snapshot predates structured
 * Token records and checksums.
 */
export type Token = string;

export declare function mint(kind: TokenKind, subject: string): Token;
export declare function validate(token: Token): boolean;
export declare function ttl(token: Token): number;
export declare function crc32(data: string): number;
EOF

cat > packages/core/lib/index.js <<'EOF'
"use strict";
/**
 * @jibblin/core 1.4.0 - packaged build snapshot.
 *
 * DO NOT EDIT: this is a published snapshot checked out of the release
 * cache. Rebuild the package and republish to refresh it.
 */
Object.defineProperty(exports, "__esModule", { value: true });
exports.crc32 = crc32;
exports.ttl = ttl;
exports.validate = validate;
exports.mint = mint;

var TTL_SECONDS = 3600;

function crc32(data) {
  var c = 0xffffffff;
  for (var i = 0; i < data.length; i++) {
    c = ((c ^ data.charCodeAt(i)) & 0xffffffff) >>> 0;
  }
  return (c ^ 0xffffffff) >>> 0;
}

function mint(kind, subject) {
  var now = Date.now();
  return kind + ":" + subject + ":" + now.toString(16) + ":" + crc32(subject).toString(16);
}

function validate(token) {
  return typeof token === "string" && token.length > 0;
}

function ttl(token) {
  return typeof token === "string" ? TTL_SECONDS : 0;
}
EOF

git add -A
git commit -qm "release: publish from 1.4 snapshot artifacts"

# leave the worktree clean of build output: the acceptance sequence must
# produce it from source
rm -rf packages/*/dist packages/*/tsconfig.tsbuildinfo

echo "jibblin monorepo generated at $TARGET"
git -C "$TARGET" log --oneline | head -12