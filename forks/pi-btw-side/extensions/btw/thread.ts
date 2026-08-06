import type { AssistantMessage, ImageContent, Message, Model } from "@earendil-works/pi-ai";
import {
	type AgentSession,
	buildSessionContext,
	convertToLlm,
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
import {
	estimateMessagesTokens,
	estimateMessageTokens,
	estimateTextTokens,
	fitInheritedMessages,
	lastAssistantText,
	neutralizeInheritedUsage,
	orphanToolResultIndices,
	sanitizeInheritedMessages,
	sideHistoryBudget,
	stripDynamicSystemPromptFooter,
} from "./context.js";
import { buildFirstSideMessage, buildSideDeveloperInstructions } from "./instructions.js";

export interface SideTurnHooks {
	/** A new assistant message began. The same object is then passed to onAssistant. */
	onAssistantStart?: (message: AssistantMessage) => void;
	/** Streaming update or completion of the current assistant message. */
	onAssistant?: (message: AssistantMessage) => void;
	/** A tool call started, with a label already formatted for display. */
	onToolStart?: (toolCallId: string, label: string) => void;
	onToolEnd?: (toolCallId: string, isError: boolean) => void;
}

export interface SideTurnResult {
	text: string;
	aborted: boolean;
	timedOut: boolean;
	durationMs: number;
	toolCalls: number;
	/** Inherited messages dropped to make room for this turn. */
	droppedMessages: number;
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

	/** Leading messages that came from the parent, and so may be dropped to make room. */
	private inheritedRemaining: number;

	private constructor(
		private readonly session: AgentSession,
		readonly model: Model<any>,
		readonly toolNames: string[],
		readonly inheritedMessages: number,
		/** Inherited messages discarded to fit the window, at fork time and since. */
		public droppedMessages: number,
		private readonly historyBudget: number,
	) {
		this.inheritedRemaining = inheritedMessages;
	}

	static async fork(ctx: ExtensionContext, config: BtwConfig): Promise<SideThread> {
		const model = resolveModel(ctx, config);
		if (!model) throw new Error("no model is selected");

		const cwd = ctx.cwd;
		const tools = toolsFor(config.toolset, cwd);
		const toolNames = tools.map((tool) => (tool as unknown as { name: string }).name).filter(Boolean);
		const runtime = runtimeOf(ctx.modelRegistry);
		const agentDir = getAgentDir();

		// The system prompt and tool schemas occupy the window too, and unlike history they
		// cannot be trimmed, so they come out of the budget before any message does.
		const systemPrompt = sideSystemPrompt(ctx);
		const appendedPrompt = buildSideDeveloperInstructions(toolNames);
		const overheadTokens =
			estimateTextTokens(systemPrompt) + estimateTextTokens(appendedPrompt) + estimateToolsTokens(tools);
		const historyBudget = sideHistoryBudget(model.contextWindow, overheadTokens);

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
			resourceLoader: sideResourceLoader(systemPrompt, appendedPrompt),
			...(runtime ? { modelRuntime: runtime as never } : {}),
		});

		// Order matters. Pairing first, so nothing downstream sees a dangling tool call;
		// then the parent's usage figures are cleared, because leaving them in makes the
		// size measurement describe the parent instead of the fork; only then is the
		// history measured and cut to fit.
		const paired = sanitizeInheritedMessages(inheritedMessagesOf(ctx));
		const fitted = fitInheritedMessages(neutralizeInheritedUsage(paired), historyBudget);
		if (fitted.messages.length > 0) {
			// Push rather than replace: the array identity is Pi's, and other parts of the
			// session hold a reference to it.
			(session.agent.state.messages as unknown as Message[]).push(...fitted.messages);
		}

		return new SideThread(session, model, toolNames, fitted.messages.length, fitted.dropped, historyBudget);
	}

	/**
	 * Make room before asking, by dropping the oldest inherited messages.
	 *
	 * Trimming once at fork time is not enough: every answer the side thread writes is
	 * added to its own context, so a long side conversation walks itself back into the
	 * starved-output state this whole mechanism exists to prevent. Only the inherited
	 * prefix is ever dropped — the side conversation's own turns are the conversation.
	 */
	private makeRoom(): number {
		const messages = this.session.agent.state.messages as unknown as Message[];
		if (this.inheritedRemaining <= 0) return 0;
		let total = estimateMessagesTokens(messages);
		if (total <= this.historyBudget) return 0;

		let drop = 0;
		while (drop < this.inheritedRemaining && total > this.historyBudget) {
			total -= estimateMessageTokens(messages[drop]);
			drop += 1;
		}
		if (drop === 0) return 0;
		messages.splice(0, drop);
		this.inheritedRemaining -= drop;

		// Cutting mid-turn can strand a tool result whose call has just gone. Splice from
		// the back so the earlier indices stay valid.
		const orphans = orphanToolResultIndices(messages);
		for (let i = orphans.length - 1; i >= 0; i--) {
			messages.splice(orphans[i], 1);
			if (orphans[i] < this.inheritedRemaining) this.inheritedRemaining -= 1;
		}

		const dropped = drop + orphans.length;
		this.droppedMessages += dropped;
		return dropped;
	}

	async ask(question: string, hooks: SideTurnHooks, timeoutMs: number, images?: ImageContent[]): Promise<SideTurnResult> {
		if (this.disposed) throw new Error("the side conversation was closed");
		if (this.running) throw new Error("the side conversation is still answering");

		this.running = true;
		const startedAt = Date.now();
		let toolCalls = 0;
		let timedOut = false;
		// Before `before` is captured, so the indices below refer to the trimmed array.
		const droppedForRoom = this.makeRoom();

		const unsubscribe = this.session.subscribe((event) => {
			try {
				if (event.type === "message_start" && event.message.role === "assistant") {
					hooks.onAssistantStart?.(event.message as AssistantMessage);
				} else if (
					(event.type === "message_update" || event.type === "message_end") &&
					event.message.role === "assistant"
				) {
					hooks.onAssistant?.(event.message as AssistantMessage);
				} else if (event.type === "tool_execution_start") {
					toolCalls += 1;
					hooks.onToolStart?.(event.toolCallId, formatToolCall(event.toolName, event.args));
				} else if (event.type === "tool_execution_end") {
					hooks.onToolEnd?.(event.toolCallId, Boolean(event.isError));
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
				droppedMessages: droppedForRoom,
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
		// Flatten to plain LLM messages, which matters for three separate reasons.
		//
		// Correctness: a `compactionSummary` keeps its text in `summary` and a `custom`
		// message's content can be a plain string. Pi's own token estimator handles
		// neither — it iterates `message.content` and throws — and clearing the inherited
		// usage below is precisely what stops its anchor from short-circuiting past them.
		// Seeding raw entries would turn an occasional crash into a guaranteed one.
		//
		// Honesty: convertToLlm produces exactly what the provider is sent, so measuring it
		// measures the real request rather than an internal representation of it.
		//
		// Display: the fork loads no extensions, so the renderers those custom entry types
		// belong to (monitor heartbeats and the like) do not exist inside it.
		return convertToLlm(context.messages as never) as unknown as Message[];
	} catch {
		// A context that cannot be built means a contextless side thread, not a failure.
		return [];
	}
}

/** The parent's system prompt, which is how the fork inherits AGENTS.md and project context. */
function sideSystemPrompt(ctx: ExtensionContext): string {
	try {
		return stripDynamicSystemPromptFooter(ctx.getSystemPrompt());
	} catch {
		return "";
	}
}

/** Tool schemas are sent on every request and count against the window like any prompt text. */
function estimateToolsTokens(tools: readonly ToolDefinition[]): number {
	if (tools.length === 0) return 0;
	try {
		return estimateTextTokens(JSON.stringify(tools) ?? "");
	} catch {
		return 0;
	}
}

/**
 * The side thread reuses the parent's system prompt — that is how it inherits AGENTS.md,
 * project context, and the user's own instructions, matching Codex's config fork — and
 * appends the side-conversation policy on top. No extensions, skills, or prompt templates
 * are loaded into it: they belong to the main thread.
 *
 * Both strings are passed in rather than built here, because fork() has to measure them
 * against the context window before the session exists.
 */
function sideResourceLoader(systemPrompt: string, appendedPrompt: string): ResourceLoader {
	const extensions = { extensions: [], errors: [], runtime: createExtensionRuntime() };
	const appended = [appendedPrompt];

	return {
		getExtensions: () => extensions as never,
		getSkills: () => ({ skills: [], diagnostics: [] }),
		getPrompts: () => ({ prompts: [], diagnostics: [] }),
		getThemes: () => ({ themes: [], diagnostics: [] }),
		getAgentsFiles: () => ({ agentsFiles: [] }),
		getSystemPrompt: () => (systemPrompt.length > 0 ? systemPrompt : undefined),
		// Added in Pi 0.83.0 for the startup context listing. The side thread's prompt is
		// assembled here rather than read from a file, so it has no source paths to report.
		getSystemPromptSource: () => undefined,
		getAppendSystemPrompt: () => appended,
		getAppendSystemPromptSources: () => [],
		extendResources: () => {},
		reload: async () => {},
	};
}
