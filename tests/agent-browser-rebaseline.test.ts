import { expect, test } from "bun:test";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { GLOBAL_BOOLEAN_FLAGS_WITH_OPTIONAL_VALUES, GLOBAL_VALUE_FLAGS } from "../forks/pi-agent-browser-native-safe/dist/extensions/agent-browser/lib/argv-grammar.js";
import {
	LAUNCH_SCOPED_FLAGS,
	MANAGED_RESTORE_INCOMPATIBLE_BOOLEAN_ENVS,
	MANAGED_RESTORE_INCOMPATIBLE_ENVS,
	MANAGED_RESTORE_INCOMPATIBLE_FLAGS,
} from "../forks/pi-agent-browser-native-safe/dist/extensions/agent-browser/lib/launch-scoped-flags.js";
import { getManagedSessionStateAccessValidationError } from "../forks/pi-agent-browser-native-safe/dist/extensions/agent-browser/lib/managed-session-state-policy.js";

const forkRoot = join(import.meta.dir, "..", "forks", "pi-agent-browser-native-safe");

test("agent-browser 0.35 custom CA controls are parsed and isolated from managed restore", () => {
	expect(GLOBAL_VALUE_FLAGS).toContain("--ca-cert");
	expect(GLOBAL_BOOLEAN_FLAGS_WITH_OPTIONAL_VALUES.has("--no-ca-cert")).toBe(true);
	expect(LAUNCH_SCOPED_FLAGS).toContain("--ca-cert");
	expect(LAUNCH_SCOPED_FLAGS).toContain("--no-ca-cert");
	expect(MANAGED_RESTORE_INCOMPATIBLE_FLAGS).toContain("--ca-cert");
	expect(MANAGED_RESTORE_INCOMPATIBLE_FLAGS).toContain("--no-ca-cert");
	expect(MANAGED_RESTORE_INCOMPATIBLE_ENVS).toContain("AGENT_BROWSER_CA_CERT");
	expect(MANAGED_RESTORE_INCOMPATIBLE_BOOLEAN_ENVS).toContain("AGENT_BROWSER_CLEAR_CA_CERT");
});

test("custom CA paths cannot read protected agent-browser state", () => {
	const fromArg = getManagedSessionStateAccessValidationError({
		args: ["--ca-cert", "/home/test/.agent-browser/state/secret.pem", "open", "https://example.com"],
		cwd: "/tmp",
		parentEnv: {},
		trustedPinnedEmptyConfig: true,
	});
	const fromEnv = getManagedSessionStateAccessValidationError({
		args: ["open", "https://example.com"],
		cwd: "/tmp",
		parentEnv: { AGENT_BROWSER_CA_CERT: "/home/test/.agent-browser/state/secret.pem" },
		trustedPinnedEmptyConfig: true,
	});
	expect(fromArg).toContain(".agent-browser storage is blocked");
	expect(fromEnv).toContain(".agent-browser storage is blocked");
});

test("remote attachment is blocked for wrapper-managed sessions, including inside a batch", () => {
	for (const args of [
		["connect", "wss://remote.example/devtools/browser/test"],
		["batch", "connect wss://remote.example/devtools/browser/test"],
	]) {
		const error = getManagedSessionStateAccessValidationError({
			args,
			blockBrowserAttachment: true,
			cwd: "/tmp",
			parentEnv: {},
			trustedPinnedEmptyConfig: true,
		});
		expect(error).toContain("wrapper-managed browser session");
	}
});

test("capability baseline targets agent-browser 0.35 and its protected Vercel skill", () => {
	const target = readFileSync(join(forkRoot, "scripts", "agent-browser-target.mjs"), "utf8");
	const baseline = readFileSync(join(forkRoot, "scripts", "agent-browser-capability-baseline.mjs"), "utf8");
	expect(target).toContain('TARGET_AGENT_BROWSER_VERSION = "0.35.0"');
	expect(baseline).toContain('upstreamPackageVersion: "0.35.0"');
	expect(baseline).toContain("protected-vercel-deployments");
	expect(baseline).toContain("--ca-cert <path>");
	expect(baseline).toContain("AGENT_BROWSER_CLEAR_CA_CERT");
});
