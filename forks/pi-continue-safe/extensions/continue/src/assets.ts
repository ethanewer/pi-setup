import { existsSync, readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import type { HistoryScenario, HistoryPromptAssets, LoadedPromptAsset, PromptOverridePolicy } from "./types.ts";
import { resolveAgentDir } from "./agent-dir.ts";

const PACKAGE_ROOT = join(dirname(fileURLToPath(import.meta.url)), "..", "..", "..");
const PACKAGE_ASSETS_ROOT = join(PACKAGE_ROOT, "assets");

function packageAsset(relativePath: string): string {
	return join(PACKAGE_ASSETS_ROOT, relativePath);
}

function globalOverrideRoot(): string {
	return join(resolveAgentDir(), "extensions", "pi-continue", "prompts");
}

function projectOverrideRoot(projectRoot: string): string {
	return join(projectRoot, ".pi", "extensions", "pi-continue", "prompts");
}

function candidateRoots(projectRoot: string, policy: PromptOverridePolicy, projectTrusted: boolean): string[] {
	switch (policy) {
		case "package-default":
			return [PACKAGE_ASSETS_ROOT];
		case "global-override":
			return [globalOverrideRoot(), PACKAGE_ASSETS_ROOT];
		case "project-override":
			return projectTrusted
				? [projectOverrideRoot(projectRoot), globalOverrideRoot(), PACKAGE_ASSETS_ROOT]
				: [globalOverrideRoot(), PACKAGE_ASSETS_ROOT];
	}
}

/** Load a prompt asset, honoring trusted-project and global overrides before package defaults. */
export function loadPromptAsset(projectRoot: string, policy: PromptOverridePolicy, relativePath: string, projectTrusted = false): LoadedPromptAsset {
	for (const root of candidateRoots(projectRoot, policy, projectTrusted)) {
		const candidate = join(root, relativePath);
		if (existsSync(candidate)) {
			return {
				content: readFileSync(candidate, "utf8"),
				sourcePath: candidate,
			};
		}
	}
	const fallback = packageAsset(relativePath);
	return {
		content: readFileSync(fallback, "utf8"),
		sourcePath: fallback,
	};
}

/** Resolve the full asset set for the history pass. */
export function loadHistoryPromptAssets(
	projectRoot: string,
	policy: PromptOverridePolicy,
	scenario: HistoryScenario,
	projectTrusted = false,
): HistoryPromptAssets {
	return {
		system: loadPromptAsset(projectRoot, policy, `system/history_${scenario}.md`, projectTrusted),
		baseUser: loadPromptAsset(projectRoot, policy, "user/continuation_base.md", projectTrusted),
		scenarioUser: loadPromptAsset(projectRoot, policy, `user/history_${scenario}.md`, projectTrusted),
	};
}
