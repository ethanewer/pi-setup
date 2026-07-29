/**
 * Workflow-specific error types.
 */

/** Dependency-neutral diagnostic payload retained by capability contract failures. */
export interface CapabilityErrorDiagnostic {
  code: string;
  severity: "error" | "warning" | "information";
  subject: string;
  message: string;
}

/** Dependency-neutral skill-loading payload retained by generation failures. */
export interface ModelGenerationSkillLoadingEvidence {
  discovered: boolean;
  loaded: boolean;
  toolCalls: Array<{ tool: string; path?: string }>;
}

/** Dependency-neutral provider-usage payload retained by generation failures. */
export interface ModelGenerationTokenUsage {
  input: number;
  output: number;
  total: number;
  cost: number;
  cacheRead: number;
  cacheWrite: number;
}

/** Stable runtime and persistence failure codes exposed to callers and UI surfaces. */
export enum WorkflowErrorCode {
  /** Agent exceeded timeout. */
  AGENT_TIMEOUT = "AGENT_TIMEOUT",
  /** Workflow was aborted by user. */
  WORKFLOW_ABORTED = "WORKFLOW_ABORTED",
  /** Agent limit exceeded. */
  AGENT_LIMIT_EXCEEDED = "AGENT_LIMIT_EXCEEDED",
  /** Token budget exhausted. */
  TOKEN_BUDGET_EXHAUSTED = "TOKEN_BUDGET_EXHAUSTED",
  /**
   * The provider's subscription/usage/quota/rate limit was hit. Distinct from the
   * user's self-imposed TOKEN_BUDGET_EXHAUSTED: a provider limit refills on its own,
   * so the run is checkpointed (paused) and replayed by resume() rather than failed.
   */
  PROVIDER_USAGE_LIMIT = "PROVIDER_USAGE_LIMIT",
  /** Script validation failed. */
  SCRIPT_VALIDATION_ERROR = "SCRIPT_VALIDATION_ERROR",
  /** A schema agent never produced valid structured_output (after repair + extraction). */
  SCHEMA_NONCOMPLIANCE = "SCHEMA_NONCOMPLIANCE",
  /** A non-schema agent completed without any assistant text output. */
  AGENT_EMPTY_OUTPUT = "AGENT_EMPTY_OUTPUT",
  /** Agent execution failed. */
  AGENT_EXECUTION_ERROR = "AGENT_EXECUTION_ERROR",
  /** Run state persistence failed. */
  PERSISTENCE_ERROR = "PERSISTENCE_ERROR",
  /** Unknown error. */
  UNKNOWN = "UNKNOWN",
}

/**
 * Property that marks a value as one of THIS package's WorkflowErrors across a
 * boundary where `instanceof` cannot hold — the `vm` realm a workflow script
 * runs in rebuilds host failures as realm-native Errors (see workflow.ts). It is
 * the brand adoptForeignWorkflowError trusts; a matching `code` alone is not
 * enough, since any error object can carry one.
 */
export const WORKFLOW_ERROR_BRAND = "__piWorkflowError";

/** Classified workflow failure with recoverability and optional agent/provider context. */
export class WorkflowError extends Error {
  readonly code: WorkflowErrorCode;
  readonly recoverable: boolean;
  readonly agentLabel?: string;
  readonly details?: unknown;
  /** For PROVIDER_USAGE_LIMIT: the provider's human reset hint, e.g. "Resets in ~3h" (verbatim). */
  readonly resetHint?: string;

  constructor(
    message: string,
    code: WorkflowErrorCode,
    options: { recoverable?: boolean; agentLabel?: string; details?: unknown; resetHint?: string } = {},
  ) {
    super(message);
    this.name = "WorkflowError";
    // Non-enumerable so it never lands in a JSON/structured copy of the error
    // by accident; it is stamped deliberately where it has to travel.
    Object.defineProperty(this, WORKFLOW_ERROR_BRAND, { value: true, enumerable: false });
    this.code = code;
    this.recoverable = options.recoverable ?? false;
    this.agentLabel = options.agentLabel;
    this.details = options.details;
    this.resetHint = options.resetHint;
  }
}

/** Contract failure that retains every definition or assembly diagnostic. */
export class WorkflowCapabilityContractError extends Error {
  readonly diagnostics: readonly CapabilityErrorDiagnostic[];

  constructor(message: string, diagnostics: readonly CapabilityErrorDiagnostic[]) {
    super(message);
    this.name = "WorkflowCapabilityContractError";
    this.diagnostics = diagnostics;
  }
}

/** Generation failure that retains loading and token evidence for diagnosis. */
export class ModelGenerationError extends Error {
  readonly skillLoadingEvidence: ModelGenerationSkillLoadingEvidence;
  readonly tokenUsage: ModelGenerationTokenUsage;

  constructor(
    message: string,
    skillLoadingEvidence: ModelGenerationSkillLoadingEvidence,
    tokenUsage: ModelGenerationTokenUsage,
  ) {
    super(message);
    this.name = "ModelGenerationError";
    this.skillLoadingEvidence = skillLoadingEvidence;
    this.tokenUsage = tokenUsage;
  }
}

/** Narrow an unknown failure to WorkflowError. */
export function isWorkflowError(error: unknown): error is WorkflowError {
  return error instanceof WorkflowError;
}

/** Report whether an unknown failure is a provider usage-limit checkpoint condition. */
export function isProviderUsageLimit(error: unknown): error is WorkflowError {
  return isWorkflowError(error) && error.code === WorkflowErrorCode.PROVIDER_USAGE_LIMIT;
}

/**
 * Detect a provider subscription/usage/quota/rate-limit exhaustion from free-form
 * error text, and extract the provider's human reset hint when present.
 *
 * The pi SDK does NOT throw these — it records them as an assistant message with
 * stopReason "error" and an errorMessage like "Codex usage limit reached (plus
 * plan). Resets in ~3h.". Callers reading message metadata MUST gate on
 * stopReason === "error" before trusting this, so a task whose own output merely
 * mentions "rate limit" is never misclassified. Patterns mirror the SDK's own
 * non-retryable-limit table. Deliberately excludes transient overloaded/5xx
 * errors, which stay recoverable and keep retrying.
 */
export function classifyProviderLimit(text: string | undefined): { matched: boolean; resetHint?: string } {
  if (!text) return { matched: false };
  const matched =
    /usage limit|limit reached|insufficient[_\s]?quota|quota exceeded|exceeded your current quota|out of budget|available balance|\bquota\b|rate.?limit|too many requests|\b429\b|GoUsageLimitError|FreeUsageLimitError|\bbilling\b/i.test(
      text,
    );
  if (!matched) return { matched: false };
  const reset = text.match(/resets?\s+(?:in|at)\s+[^.\n]+/i);
  return { matched: true, resetHint: reset?.[0]?.trim() };
}

/** Recognize abort-like Error messages without assuming a provider-specific class. */
export function isAbortError(error: unknown): boolean {
  if (!(error instanceof Error)) return false;
  return /\babort(?:ed)?\b/i.test(error.message);
}

/** Recognize timeout-like errors by name or message. */
export function isTimeoutError(error: unknown): boolean {
  if (!(error instanceof Error)) return false;
  return /\btimeout\b/i.test(error.message) || error.name === "TimeoutError";
}

/**
 * Rebuild a WorkflowError from a structurally-equivalent error raised in another
 * realm — a workflow script's `vm` realm re-throwing what a runtime binding
 * failed with. Such an error is a realm-native Error carrying the classification
 * as plain properties (see workflow.ts's realm bootstrap), so neither
 * `instanceof WorkflowError` nor `instanceof Error` holds for it here, and
 * without this a token-budget or agent-limit failure would be reclassified as a
 * generic recoverable one. Returns undefined for anything that isn't one.
 *
 * Only a BRANDED error (WORKFLOW_ERROR_BRAND, stamped on the way out through the
 * realm) is taken at its word about `recoverable`. A `code` matching one of the
 * enum values is not proof of origin — any library's error may carry, say,
 * `code: "PROVIDER_USAGE_LIMIT"` — and recoverable:false is the classification
 * that halts a whole run, so an unbranded error is adopted as recoverable
 * instead: its code still classifies it, but it cannot claim to be fatal.
 */
export function adoptForeignWorkflowError(error: unknown): WorkflowError | undefined {
  if (!error || typeof error !== "object") return undefined;
  const source = error as {
    message?: unknown;
    code?: unknown;
    recoverable?: unknown;
    agentLabel?: unknown;
    resetHint?: unknown;
  };
  if (typeof source.message !== "string" || typeof source.code !== "string") return undefined;
  if (!Object.values(WorkflowErrorCode).includes(source.code as WorkflowErrorCode)) return undefined;
  const branded = (error as Record<string, unknown>)[WORKFLOW_ERROR_BRAND] === true;
  return new WorkflowError(source.message, source.code as WorkflowErrorCode, {
    recoverable: branded && typeof source.recoverable === "boolean" ? source.recoverable : true,
    agentLabel: typeof source.agentLabel === "string" ? source.agentLabel : undefined,
    resetHint: typeof source.resetHint === "string" ? source.resetHint : undefined,
  });
}

/** Whether `error` carries this package's brand (see WORKFLOW_ERROR_BRAND). */
function isBrandedWorkflowError(error: unknown): boolean {
  return !!error && typeof error === "object" && (error as Record<string, unknown>)[WORKFLOW_ERROR_BRAND] === true;
}

/**
 * Wrap an unknown error into a WorkflowError with appropriate classification.
 */
export function wrapError(error: unknown, context?: { agentLabel?: string }): WorkflowError {
  if (isWorkflowError(error)) return error;
  // A branded cross-realm WorkflowError is already classified — adopt it before
  // the heuristics below can re-derive a different answer from its message.
  if (isBrandedWorkflowError(error)) {
    const branded = adoptForeignWorkflowError(error);
    if (branded) return branded;
  }

  if (isAbortError(error)) {
    return new WorkflowError(
      error instanceof Error ? error.message : "Workflow was aborted",
      WorkflowErrorCode.WORKFLOW_ABORTED,
      { recoverable: true },
    );
  }

  if (isTimeoutError(error)) {
    return new WorkflowError(
      error instanceof Error ? error.message : "Agent timed out",
      WorkflowErrorCode.AGENT_TIMEOUT,
      { recoverable: true, agentLabel: context?.agentLabel },
    );
  }

  // Defense-in-depth: today the SDK buries provider usage/quota limits in an
  // assistant message (detected in agent.ts), but a future SDK might throw them.
  // Classify a thrown limit here too — recoverable:false so the run checkpoints
  // (paused) instead of being retried into the same wall or silently nulled.
  if (error instanceof Error) {
    const limit = classifyProviderLimit(error.message);
    if (limit.matched) {
      return new WorkflowError(error.message, WorkflowErrorCode.PROVIDER_USAGE_LIMIT, {
        recoverable: false,
        agentLabel: context?.agentLabel,
        resetHint: limit.resetHint,
      });
    }
  }

  // Nothing above matched. An unbranded error carrying a workflow code (a realm
  // error from a release whose bootstrap didn't brand yet, or a clone that lost
  // the non-enumerable brand) still keeps that code — but as recoverable, since
  // it cannot be trusted to declare a whole run fatal.
  const foreign = adoptForeignWorkflowError(error);
  if (foreign) return foreign;

  return new WorkflowError(
    error instanceof Error ? error.message : String(error),
    WorkflowErrorCode.AGENT_EXECUTION_ERROR,
    { recoverable: true, agentLabel: context?.agentLabel, details: error },
  );
}
