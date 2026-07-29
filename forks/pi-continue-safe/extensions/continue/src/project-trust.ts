import { existsSync } from "node:fs";
import { join } from "node:path";
import type { ExtensionContext } from "@earendil-works/pi-coding-agent";
import { flushInputWarnings, queueInputWarning } from "./input-warnings.ts";

// Project-scoped inputs that only a trusted project may contribute: scoped package
// config, prompt overrides, and the Pi settings that move the handoff trigger.
const PROJECT_SCOPED_INPUTS = [
	join(".pi", "extensions", "pi-continue.json"),
	join(".pi", "extensions", "pi-continue", "prompts"),
	join(".pi", "settings.json"),
];

const PROJECT_TRUST_ENV = "PI_CONTINUE_TRUST_PROJECT_CONFIG";
const UNTRUSTED_PROJECT_WARNING = "pi-continue ignored project-scoped settings, Pi settings, and prompt overrides because this project is not trusted.";
const UNKNOWN_TRUST_WARNING = `pi-continue ignored project-scoped settings, Pi settings, and prompt overrides because this Pi version reports no project trust decision. Set ${PROJECT_TRUST_ENV}=1 to honor them anyway.`;

const checkedProjectRoots = new Set<string>();

function hasProjectScopedInputs(projectRoot: string): boolean {
	return PROJECT_SCOPED_INPUTS.some((relativePath) => existsSync(join(projectRoot, relativePath)));
}

function hostReportsTrust(ctx: ExtensionContext): boolean {
	return typeof ctx.isProjectTrusted === "function";
}

function isTruthyEnvValue(value: string | undefined): boolean {
	const normalized = value?.trim().toLowerCase();
	return normalized === "1" || normalized === "true" || normalized === "yes";
}

/** Resolve whether project-scoped config, Pi settings, and prompt overrides may be honored. */
export function isProjectScopeTrusted(ctx: ExtensionContext, projectRoot: string): boolean {
	// Project scope can supply the summarizer's prompts and repoint its model, so a host that
	// reports no trust decision at all is treated as untrusted until the operator says otherwise.
	const hostDecides = hostReportsTrust(ctx);
	const trusted = hostDecides ? ctx.isProjectTrusted() : isTruthyEnvValue(process.env[PROJECT_TRUST_ENV]);
	if (!trusted && !checkedProjectRoots.has(projectRoot)) {
		checkedProjectRoots.add(projectRoot);
		if (hasProjectScopedInputs(projectRoot)) {
			queueInputWarning(
				`untrusted-project:${projectRoot}`,
				hostDecides ? UNTRUSTED_PROJECT_WARNING : UNKNOWN_TRUST_WARNING,
			);
		}
	}
	flushInputWarnings(ctx);
	return trusted;
}
