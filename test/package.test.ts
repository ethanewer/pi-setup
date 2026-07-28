/**
 * Package-manifest regression tests: modules resolved from the pi host at
 * runtime (extension imports typebox and @earendil-works/pi-tui directly)
 * must be declared as '*' peerDependencies so installers surface a conflict
 * instead of silently bundling a second copy.
 */

import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";

const HOST_PROVIDED = ["@earendil-works/pi-coding-agent", "@earendil-works/pi-tui", "typebox"];

test("host-provided modules are declared as '*' peerDependencies", () => {
  const pkg = JSON.parse(
    readFileSync(new URL("../package.json", import.meta.url), "utf8"),
  ) as { peerDependencies?: Record<string, string> };
  for (const name of HOST_PROVIDED) {
    assert.equal(pkg.peerDependencies?.[name], "*", `${name} must be a '*' peerDependency`);
  }
});
