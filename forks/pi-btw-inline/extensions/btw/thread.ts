import type { ImageContent, Message, Model } from "@earendil-works/pi-ai";
import {
	type AgentSession,
	buildSessionContext,
	createAgentSession,
	createCodingTools,
	createExtensionRuntime,
	createReadOnlyTools,
	type ExtensionContext,
	getAgentDir,
	type ModelRegistry,
	type ResourceLoader,
	SessionManager,
	SettingsManager,
	type ToolDefinition,
} from "@earendil-works/pi-coding-agent";

import type { BtwConfig } from "./config.js";
import { assistantText, lastAssistantText, sanitizeInheritedMessages, stripDynamicSystemPromptFooter } from "./context.js";
import { buildFirstSideMessage, buildSideDeveloperInstructions } from "./instructions.js";

export interface SideTurnHooks {
	/** Full assistant text so far, called on every streaming update. */
	onText?: (text: string) => void;
	/** A tool the side thread is running, already formatted for display. */
	onTool?: (label: string) => void;
}

export interface SideTurnResult {
	text: string;
	aborted: boolean;
	timedOut: boolean;
	durationMs: number;
	toolCalls: number;
}

/** Pi's own runtime is not exported; the workflows fork reads the same private field.
 * Missing it only costs extension-registered providers, so it is optional by design. */
function runtimeOf(registry: ModelRegistry): unknown {
	return (registry as unknown as { runtime?: unknown }).runtime;
}

function toolsFor(toolset: BtwConfig["toolset"], cwd: string): ToolDefinition[] {
	if (toolset === "none") return [];
	// Both sets are built explicitly rather than by allowlisting Pi's built-ins, so the
	// side thread's tool surface is exactly this list no matter what the parent had.
	const tools = toolset === "full" ? createCodingTools(cwd) : createReadOnlyTools(cwd);
	return tools as unknown as ToolDefinition[];
}

function formatToolCall(name: string, args: unknown): string {
	const record = (args ?? {}) as Record<string, unknown>;
	const first = (keys: string[]): string | undefined => {
		for (const key of keys) {
			const value = record[key];
			if (typeof value === "string" && value.length > 0) return value;
		}
		return undefined;
	};
	const detail =
		name === "bash"
			? first(["command"])
			: name === "grep"
				? first(["pattern"])
				: first(["file_path", "path", "pattern", "query"]);
	if (!detail) return name;
	const trimmed = detail.length > 60 ? `${detail.slice(0, 57)}...` : detail;
	return `${name} ${trimmed}`;
}

/**
 * One ephemeral fork of the main conversation.
 *
 * The fork is in-memory only (SessionManager.inMemory), so nothing it says is written to
 * the session file and nothing it says re-enters the main thread's context. That is the
 * defining property of Codex's /side, and it is the reason this class owns its own
 * AgentSession rather than borrowing the host's.
 */
export class SideThread {
	private started = false;
	private running = false;
	private disposed = false;

	private constructor(
		private readonly session: AgentSession,
		readonly model: Model<any>,
		readonly toolNames: string[],
		readonly inheritedMessages: number,
	) {}

	static async fork(ctx: ExtensionContext, config: BtwConfig): Promise<SideThread> {
		const model = resolveModel(ctx, config);
		if (!model) throw new Error("no model is selected");

		const cwd = ctx.cwd;
		const tools = toolsFor(config.toolset, cwd);
		const toolNames = tools.map((tool) => (tool as unknown as { name: string }).name).filter(Boolean);
		const runtime = runtimeOf(ctx.modelRegistry);
		const agentDir = getAgentDir();

		const { session } = await createAgentSession({
			cwd,
			agentDir,
			model,
			thinkingLevel: (config.thinkingLevel ?? ctx.thinkingLevel) as never,
			// Ephemeral by construction: an in-memory manager has no session file to write.
			sessionManager: SessionManager.inMemory(),
			// The real settings manager, so provider defaults and auth resolve the same way
			// they do for the main thread.
			settingsManager: SettingsManager.create(cwd, agentDir),
			// Built-ins off, custom tools on: the list from toolsFor() is the whole surface.
			noTools: "builtin",
			customTools: tools,
			resourceLoader: sideResourceLoader(ctx, toolNames),
			...(runtime ? { modelRuntime: runtime as never } : {}),
		});

		const inherited = sanitizeInheritedMessages(inheritedMessagesOf(ctx));
		if (inherited.length > 0) {
			// Push rather than replace: the array identity is Pi's, and other parts of the
			// session hold a reference to it.
			(session.agent.state.messages as unknown as Message[]).push(...inherited);
		}

		return new SideThread(session, model, toolNames, inherited.length);
	}

	async ask(question: string, hooks: SideTurnHooks, timeoutMs: number, images?: ImageContent[]): Promise<SideTurnResult> {
		if (this.disposed) throw new Error("the side conversation was closed");
		if (this.running) throw new Error("the side conversation is still answering");

		this.running = true;
		const startedAt = Date.now();
		let toolCalls = 0;
		let timedOut = false;

		const unsubscribe = this.session.subscribe((event) => {
			try {
				if (event.type === "message_update" && event.message.role === "assistant") {
					hooks.onText?.(assistantText(event.message));
				} else if (event.type === "tool_execution_start") {
					toolCalls += 1;
					hooks.onTool?.(formatToolCall(event.toolName, event.args));
				}
			} catch {
				// Display is never allowed to break the turn.
			}
		});

		const timer =
			timeoutMs > 0
				? setTimeout(() => {
						timedOut = true;
						void this.session.abort();
					}, timeoutMs)
				: undefined;

		// Only messages produced from here on belong to this turn. Scanning the whole
		// history instead would report the previous answer as this one whenever a turn is
		// aborted or comes back empty.
		const before = (this.session.messages as unknown as Message[]).length;

		try {
			const text = this.started ? question : buildFirstSideMessage(question);
			this.started = true;
			await this.session.prompt(text, {
				expandPromptTemplates: false,
				...(images && images.length > 0 ? { images } : {}),
			});
			const produced = (this.session.messages as unknown as Message[]).slice(before);
			return {
				text: lastAssistantText(produced),
				aborted: timedOut || wasAborted(produced),
				timedOut,
				durationMs: Date.now() - startedAt,
				toolCalls,
			};
		} finally {
			if (timer) clearTimeout(timer);
			unsubscribe();
			this.running = false;
		}
	}

	async abort(): Promise<void> {
		try {
			await this.session.abort();
		} catch {
			// Aborting a session that is already idle is not an error worth surfacing.
		}
	}

	async dispose(): Promise<void> {
		if (this.disposed) return;
		this.disposed = true;
		await this.abort();
		try {
			this.session.dispose();
		} catch {
			// Teardown is best-effort; a failure here must not leave the command handler
			// throwing into Pi's event loop.
		}
	}
}

/** True when the turn ended in an abort — a timeout, /btw:end, or shutdown. */
function wasAborted(produced: readonly Message[]): boolean {
	for (let i = produced.length - 1; i >= 0; i--) {
		const message = produced[i];
		if (message.role === "assistant") return message.stopReason === "aborted";
	}
	// No assistant message at all means the turn never got that far.
	return produced.length === 0;
}

function resolveModel(ctx: ExtensionContext, config: BtwConfig): Model<any> | undefined {
	if (config.model) {
		const found = ctx.modelRegistry.find(config.model.provider, config.model.id);
		if (found) return found;
		// Configured-but-missing falls back to the main model rather than failing: a stale
		// entry in the config file should not cost the user the command.
	}
	return ctx.model;
}

function inheritedMessagesOf(ctx: ExtensionContext): Message[] {
	try {
		// The standalone builder, not a SessionManager method: extensions see a
		// ReadonlySessionManager, which exposes the entries but not the conversion.
		// buildSessionContext applies compaction, so a compacted parent hands over its
		// summary rather than the messages the summary replaced.
		const context = buildSessionContext(ctx.sessionManager.getEntries(), ctx.sessionManager.getLeafId());
		return context.messages as unknown as Message[];
	} catch {
		// A context that cannot be built means a contextless side thread, not a failure.
		return [];
	}
}

/**
 * The side thread reuses the parent's system prompt — that is how it inherits AGENTS.md,
 * project context, and the user's own instructions, matching Codex's config fork — and
 * appends the side-conversation policy on top. No extensions, skills, or prompt templates
 * are loaded into it: they belong to the main thread.
 */
function sideResourceLoader(ctx: ExtensionContext, toolNames: readonly string[]): ResourceLoader {
	const extensions = { extensions: [], errors: [], runtime: createExtensionRuntime() };
	let systemPrompt = "";
	try {
		systemPrompt = stripDynamicSystemPromptFooter(ctx.getSystemPrompt());
	} catch {
		systemPrompt = "";
	}
	const appended = [buildSideDeveloperInstructions(toolNames)];

	return {
		getExtensions: () => extensions as never,
		getSkills: () => ({ skills: [], diagnostics: [] }),
		getPrompts: () => ({ prompts: [], diagnostics: [] }),
		getThemes: () => ({ themes: [], diagnostics: [] }),
		getAgentsFiles: () => ({ agentsFiles: [] }),
		getSystemPrompt: () => (systemPrompt.length > 0 ? systemPrompt : undefined),
		getAppendSystemPrompt: () => appended,
		extendResources: () => {},
		reload: async () => {},
	};
}
