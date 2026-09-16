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
