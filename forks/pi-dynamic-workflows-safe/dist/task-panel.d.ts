/**
 * Background-run UX, mirroring Claude Code:
 *  - A live task panel below the input lists in-progress runs while you keep working.
 *    It is informational; run /workflows to open the full navigator.
 *  - When a background run finishes, its result is delivered back into the
 *    conversation so the paused task continues with the outcome.
 */
import { type ExtensionAPI, type ExtensionUIContext, type Theme } from "@earendil-works/pi-coding-agent";
import type { ManagedRun, WorkflowManager } from "./workflow-manager.js";
import type { WorkflowStorage } from "./workflow-saved.js";
import type { WorkflowSettings } from "./workflow-settings.js";
export interface TaskPanelOptions {
    storage?: WorkflowStorage;
    cwd?: string;
    /**
     * Live settings loader. When provided, the panel reads it fresh (with a short
     * TTL cache) on each render so `/workflows-progress` takes effect without a
     * restart. Omitted in tests / minimal hosts → always compact.
     */
    loadSettings?: () => WorkflowSettings;
}
export declare function fenceUntrusted(text: string): string;
export declare function deliverText(run: ManagedRun, opts?: {
    resultPath?: string;
    maxChars?: number;
}): string;
/**
 * Session-routed background result delivery.
 *
 * Root cause (#147): pi-coding-agent's ExtensionRunner.bindCore() writes
 * `runtime.sendMessage` on a shared runtime object (last-bindCore-wins). Calling
 * `pi.sendMessage` at completion time therefore delivers into whichever session
 * was constructed last — not the session that started the workflow. #143 only
 * covered same-manager session *replacement*; parallel sibling sessions steal
 * the route without any shutdown on the origin.
 *
 * Fix: process-wide endpoint registry keyed by sessionId. Each session_start
 * registers a session-stable send captured from the *host* AgentSession's
 * sendCustomMessage (returns a real Promise — unlike actions.sendMessage
 * which is void and swallows rejects). Completions resolve `run.sessionId`,
 * persist a pending marker first, then deliver only via that session's
 * endpoint. Clear the marker only after the send Promise settles successfully.
 * Missing/suspended endpoint or non-thenable send → leave pending (fail
 * closed). Never fall back to shared `pi.sendMessage` / runtime.sendMessage,
 * and never ACK on a durable append (that writes history without triggerTurn).
 */
type DeliverySend = (message: {
    customType: string;
    content: string;
    display: boolean;
}, options: {
    triggerTurn: boolean;
    deliverAs: "followUp";
}) => unknown;
/**
 * Register or refresh the delivery endpoint for a pi session. Requires a
 * session-stable thenable send (stolen host AgentSession.sendCustomMessage, or
 * test DI). Never falls back to shared pi.sendMessage. A durable
 * appendCustomMessageEntry is not an ACK (no triggerTurn).
 *
 * Call from session_start AFTER Pi bindCore. Unsuspends and flushes disk pending
 * for this sessionId only.
 */
export declare function bindSessionDelivery(sessionId: string, _pi: ExtensionAPI, opts?: {
    loadSettings?: () => WorkflowSettings;
    manager?: WorkflowManager;
    /**
     * Optional explicit thenable send (tests / DI). Wins over the process-wide
     * steal map when provided.
     */
    stableSend?: DeliverySend;
    /**
     * Optional sessionManager. getSessionId is identity only — append is not
     * an ACK channel.
     */
    sessionManager?: {
        getSessionId?: () => string;
        appendCustomMessageEntry?: (customType: string, content: string | unknown[], display: boolean, details?: unknown) => string;
    };
}): void;
/**
 * Suspend delivery for a session. Completions only mark disk pending until
 * {@link bindSessionDelivery} / {@link resumeSessionDelivery} runs again.
 */
export declare function suspendSessionDelivery(sessionId: string | undefined): void;
/**
 * Drop endpoint + stolen send for a session that will not come back (quit /
 * discard, or the *old* id after a successful replacement bind). Releases the
 * AgentSession closure retained by the steal map (#109).
 */
export declare function dropSessionDelivery(sessionId: string | undefined): void;
/**
 * Unsuspend and flush one session's pending deliveries (disk). Prefer
 * {@link bindSessionDelivery} on session_start (also refreshes send).
 */
export declare function resumeSessionDelivery(sessionId: string | undefined, manager?: WorkflowManager): void;
/**
 * Stop live sends for the manager's currently bound session. In-flight
 * completions only leave disk pending until the next bind/resume.
 *
 * Call from session_shutdown BEFORE handoff or discard so a completion that
 * races the teardown cannot deliver into the outgoing session (#143).
 */
export declare function suspendResultDelivery(manager: WorkflowManager): void;
/**
 * Unsuspend and flush queued deliveries for the manager's bound session.
 * Must run only after Pi has finished bindCore (i.e. from session_start).
 * Prefer {@link bindSessionDelivery} which also captures a fresh stable send.
 */
export declare function resumeResultDelivery(manager: WorkflowManager): void;
/**
 * When a background run finishes (or fails), deliver its result back into the
 * *originating* conversation AND continue the turn so the assistant can act on
 * it — without blocking the user meanwhile:
 *
 *  - Delivery is routed by `run.sessionId` through the process-wide endpoint
 *    registry (never "latest pi wins").
 *  - `triggerTurn: true` starts a fresh turn when the agent is idle.
 *  - `deliverAs: "followUp"` queues behind an in-flight turn — never interrupts.
 *  - Durable pending marker clears only after verified delivery ACK.
 *
 * Set up once per manager; idempotent via an internal guard. Across session
 * replacement the manager (and these listeners) survive via the handoff path;
 * each new generation calls {@link bindSessionDelivery} on session_start.
 */
export declare function installResultDelivery(_pi: ExtensionAPI, manager: WorkflowManager, opts?: {
    loadSettings?: () => WorkflowSettings;
}): void;
/** @internal test helper — reset process-wide delivery registries between cases. */
export declare function _resetDeliveryRegistriesForTests(): void;
/** @internal test helper — register a thenable session-stable send (steal map). */
export declare function _registerBoundSessionSendForTests(sessionId: string, send: DeliverySend): void;
/** @internal test helper — whether the steal map holds a send for this session. */
export declare function _hasBoundSessionSendForTests(sessionId: string): boolean;
/** @internal test helper — inspect endpoint suspended flag. */
export declare function _getSessionDeliveryEndpointForTests(sessionId: string): {
    suspended: boolean;
    generation: number;
    hasSend: boolean;
    hasAppend: boolean;
} | undefined;
export declare function renderPanel(manager: WorkflowManager, theme: Theme, width?: number): string[];
/** Record a token-total sample for `runId` at time `now` (ms). */
export declare function sampleTokens(runId: string, total: number, now: number): void;
/** Tokens/second over the rolling window; 0 when too few samples or totals plateau. */
export declare function tokensPerSecond(runId: string): number;
/** Forget a run's samples (call when it finishes) so the map can't grow unbounded. */
export declare function clearTokenSamples(runId: string): void;
/** Normalize the configured per-phase agent cap to a sane integer (default 8). */
export declare function clampMaxAgents(value: number | undefined): number;
/**
 * Detailed variant of {@link renderPanel}: per-run header with aggregate tokens,
 * cost, and a live token/s rate, followed by per-phase progress and per-agent rows
 * (capped at `maxAgents` per phase). `now` is injected for testability.
 */
export declare function renderPanelDetailed(manager: WorkflowManager, theme: Theme, width: number | undefined, maxAgents: number, now: number): string[];
/**
 * Install the live "workflows running" panel below the editor. Re-rendered on
 * every manager event. Informational only — the user opens the navigator with
 * /workflows. Safe to call on every session_start: the widget is (re)registered
 * for the current UI, while the manager subscriptions are installed once.
 * (`_pi` is kept for signature stability.)
 */
export declare function installTaskPanel(_pi: ExtensionAPI, manager: WorkflowManager, ui: ExtensionUIContext, opts?: TaskPanelOptions): void;
export {};
