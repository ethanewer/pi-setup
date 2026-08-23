import { existsSync, readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { Text } from "@earendil-works/pi-tui";
import { batchHasSuccessfulCloseAll, getSuccessfulBatchCloseLifecycle } from "./lib/batch-lifecycle.js";
import { PROJECT_RULE_PROMPT, buildBrowserDefaultProfileGuideline, buildBrowserExecutablePathGuideline, buildToolPromptGuidelines, } from "./lib/playbook.js";
import { SessionPageState } from "./lib/session-page-state.js";
import { canUseHeadlessCompatibilityUserAgent, createEphemeralSessionSeed, createFreshSessionName, createImplicitSessionName, extractUpstreamCommandTokens, getImplicitSessionCloseTimeoutMs, getImplicitSessionIdleTimeoutMs, isRestorableManagedSessionName, restoreManagedSessionStateFromBranch, validateToolArgs, redactSensitiveText, isPlainTextInspectionArgs, } from "./lib/runtime.js";
import { extractExplicitNamespace, extractExplicitSessionName, getAgentBrowserSessionIdentityKey, isAgentBrowserSessionIdentityKeyInNamespace, isUpstreamEnvFlagEnabled, resolveAgentBrowserNamespace } from "./lib/argv-grammar.js";
import { parseArgvDescriptor } from "./lib/argv-descriptor.js";
import { needsManagedSession } from "./lib/command-policy.js";
import { cleanupManagedSessionRestoreConfig, ManagedSessionRestoreState } from "./lib/managed-session-restore.js";
import { isRecord } from "./lib/parsing.js";
import { runAgentBrowserProcess } from "./lib/process.js";
import { getAgentBrowserProcessEnvironment, withIsolatedAgentBrowserEnvironment } from "./lib/process-environment.js";
import { TARGET_AGENT_BROWSER_VERSION, TARGET_AGENT_BROWSER_VERSION_LABEL, getAgentBrowserVersionValidationError, parseAgentBrowserVersionOutput, } from "./lib/upstream-version.js";
import { buildPromptPolicy, getLatestUserPrompt, shouldAppendBrowserSystemPrompt } from "./lib/prompt-policy.js";
import { isCloseAllCommand, isCloseCommand } from "./lib/command-taxonomy.js";
import { hasLaunchScopedFlagToken } from "./lib/launch-scoped-flags.js";
import { cleanupSecureTempArtifacts } from "./lib/temp.js";
import { AGENT_BROWSER_PARAMS } from "./lib/input-modes/params.js";
import { AGENT_BROWSER_SCRIPT_DEFAULT_TIMEOUT_MS, AGENT_BROWSER_SCRIPT_NAMESPACE, createAgentBrowserScriptSessionName, isAgentBrowserScriptSessionName, runAgentBrowserScript, } from "./lib/input-modes/script.js";
import { parseAllowedDomainsPolicyFromArgs } from "./lib/navigation-policy.js";
import { closeManagedSession, getSessionContextKey, runAgentBrowserTool } from "./lib/orchestration/browser-run/index.js";
import { canonicalizeExplicitArtifactDestination, getExplicitArtifactDestination } from "./lib/orchestration/browser-run/artifact-paths.js";
import { findElectronLaunchRecordForSession, getActiveElectronRecords } from "./lib/orchestration/browser-run/session-state.js";
import { parseBatchCommandArgument, parseUserBatchStdin } from "./lib/orchestration/batch-stdin.js";
import { ELECTRON_POST_COMMAND_STATUS_SETTLE_MS, ELECTRON_PROFILE_ISOLATION_DETAILS, adoptOrphanedElectronLaunches, cleanupActiveElectronHostLaunches, handleElectronHostInput, restoreElectronLaunchRecordsFromBranch, } from "./lib/orchestration/electron-host/index.js";
import { getUpstreamProjectConfigIgnoredNotice, planUpstreamConfigPin } from "./lib/upstream-config-policy.js";
import { buildValidationFailureResult, resolveAgentBrowserInput } from "./lib/orchestration/input-plan.js";
import { applyAgentBrowserOutputPath, getAgentBrowserOutputPathValidationError, normalizeRequestedOutputPath } from "./lib/orchestration/output-file.js";
import { appendScriptSessionLease, buildScriptBrowserEnvelope, buildScriptToolResult, getScriptSessionLeasesFromBranch } from "./lib/orchestration/script-mode.js";
import { formatSessionArtifactRetentionSummary, getSessionArtifactManifestEntryKey, isPendingRecordingCommand, isSessionArtifactManifest, mergeSessionArtifactManifest, retirePendingRecordingManifestEntries } from "./lib/results/artifact-manifest.js";
import { appendUniqueAgentBrowserNextActions, applyNamespaceToNextActions, applySessionToNextActions, buildNextToolAction } from "./lib/results/next-actions.js";
import { canRegisterWebSearchTool, loadAgentBrowserConfigSync } from "./lib/config.js";
import { appendRecordingReservationTransition, applyRecordingArtifactsToReservations, restoreRecordingReservationStateFromBranch, retireRecordingReservation, } from "./lib/recording-reservations.js";
import { createAgentBrowserWebSearchTool } from "./lib/web-search.js";
import { isDirectAgentBrowserBashAllowed, isHarmlessAgentBrowserInspectionCommand, looksLikeDirectAgentBrowserBash, } from "./lib/bash-guard.js";
import { AgentBrowserResultComponent, buildAgentBrowserToolResultPatch, formatAgentBrowserRenderCall, formatAgentBrowserRenderResult, } from "./lib/pi-tool-rendering.js";
function isBashToolCallEvent(event) {
    if (!isRecord(event) || event.toolName !== "bash" || !isRecord(event.input))
        return false;
    return typeof event.input.command === "string";
}
function getArtifactCommandSteps(args, stdin) {
    const commandTokens = extractUpstreamCommandTokens(args);
    const batch = commandTokens[0] === "batch";
    if (!batch)
        return { batch, steps: commandTokens.length > 0 ? [commandTokens] : [] };
    const steps = [];
    for (const command of commandTokens.slice(1)) {
        if (command === "--bail")
            continue;
        const parsed = parseBatchCommandArgument(command);
        if (parsed.error || !parsed.step)
            return { batch, error: `Unsupported batch step ${steps.length + 1}: ${parsed.error ?? "command could not be parsed safely"}`, steps };
        steps.push(parsed.step);
    }
    // Upstream executes raw argument steps exclusively when any exist, so ignored
    // stdin must not add artifact/lifecycle steps or fail this preflight.
    if (steps.length > 0)
        return { batch, steps };
    const parsed = parseUserBatchStdin(stdin);
    return parsed.error ? { batch, error: parsed.error, steps } : { batch, steps: parsed.steps ?? [] };
}
function getArtifactPreflightValidationError(options) {
    const { batch, error, steps } = getArtifactCommandSteps(options.args, options.stdin);
    if (error)
        return error;
    const activeRecordingDestinations = new Set();
    const cleanupOnly = steps.length > 0 && steps.every((step) => {
        const [command, subcommand] = extractUpstreamCommandTokens(step);
        return isCloseCommand(command) || (command === "record" && subcommand === "stop");
    });
    for (const reservation of options.activeRecordingReservations ?? []) {
        try {
            activeRecordingDestinations.add(canonicalizeExplicitArtifactDestination(reservation.cwd, reservation.absolutePath));
        }
        catch (canonicalizationError) {
            if (!cleanupOnly)
                return canonicalizationError instanceof Error ? canonicalizationError.message : "An active recording destination could not be resolved safely.";
        }
    }
    let canonicalOutputPath;
    if (options.outputPath) {
        try {
            canonicalOutputPath = canonicalizeExplicitArtifactDestination(options.cwd, normalizeRequestedOutputPath(options.outputPath));
            if (activeRecordingDestinations.has(canonicalOutputPath)) {
                return `Unsupported outputPath: ${options.outputPath} is reserved by an active recording. Stop that recording first or use a distinct path.`;
            }
        }
        catch (canonicalizationError) {
            return canonicalizationError instanceof Error ? canonicalizationError.message : `outputPath ${options.outputPath} could not be resolved safely.`;
        }
    }
    const artifactDestinations = new Map();
    let sawBatchClose = false;
    for (const [index, step] of steps.entries()) {
        const commandStep = extractUpstreamCommandTokens(step);
        if (batch) {
            const stepValidationError = validateToolArgs(step);
            if (stepValidationError)
                return `Unsupported batch step ${index + 1}: ${stepValidationError}`;
            if (sawBatchClose && commandStep[0] === "record" && (commandStep[1] === "start" || commandStep[1] === "restart")) {
                return `Unsupported batch step ${index + 1}: record ${commandStep[1]} cannot follow close, quit, or exit in one upstream batch because upstream can report success without starting a recording. Split the close and recording into separate agent_browser calls.`;
            }
            if (isCloseCommand(commandStep[0]))
                sawBatchClose = true;
        }
        const artifactDestination = getExplicitArtifactDestination(commandStep);
        if (artifactDestination) {
            let canonicalDestination;
            try {
                canonicalDestination = canonicalizeExplicitArtifactDestination(options.cwd, artifactDestination);
            }
            catch (canonicalizationError) {
                return canonicalizationError instanceof Error ? canonicalizationError.message : `Artifact destination ${artifactDestination} could not be resolved safely.`;
            }
            if (canonicalOutputPath === canonicalDestination) {
                return `Unsupported outputPath: ${options.outputPath} resolves to the same destination as artifact path ${artifactDestination}. Use distinct paths so the tool-result JSON cannot overwrite the browser artifact.`;
            }
            if (activeRecordingDestinations.has(canonicalDestination)) {
                const prefix = batch ? `Unsupported batch artifact destination in step ${index + 1}` : "Unsupported artifact destination";
                return `${prefix}: ${artifactDestination} is reserved by an active recording. Stop that recording first or use a distinct path.`;
            }
            const priorStep = artifactDestinations.get(canonicalDestination);
            if (priorStep !== undefined) {
                return `Unsupported batch artifact destination in step ${index + 1}: ${artifactDestination} is already written by step ${priorStep + 1}. Use distinct paths or split the batch so each artifact can be verified independently.`;
            }
            artifactDestinations.set(canonicalDestination, index);
        }
        if (batch && commandStep[0] === "screenshot" && step.includes("--annotate")) {
            return [
                `Unsupported batch screenshot annotation in step ${index + 1}: put --annotate in top-level args, not inside the batch step.`,
                `Use: { "args": ["--annotate", "batch"], "stdin": "[[\\"screenshot\\",\\"/path/to/image.png\\"]]" }`,
            ].join("\n");
        }
    }
    return undefined;
}
function commandClosesAllSessions(args, stdin) {
    const parsed = getArtifactCommandSteps(args, stdin);
    return !parsed.error && parsed.steps.some((step) => isCloseAllCommand(extractUpstreamCommandTokens(step)));
}
function commandTouchesArtifactLifecycle(args, stdin, outputPath) {
    if (outputPath)
        return true;
    const parsed = getArtifactCommandSteps(args, stdin);
    if (parsed.error)
        return true;
    return parsed.steps.some((step) => {
        const commandStep = extractUpstreamCommandTokens(step);
        return getExplicitArtifactDestination(commandStep) !== undefined || commandStep[0] === "record" || commandStep[0] === "screenshot" || isCloseCommand(commandStep[0]);
    });
}
function isResultFileArtifact(artifact) {
    return isRecord(artifact)
        && typeof artifact.absolutePath === "string"
        && typeof artifact.kind === "string"
        && typeof artifact.path === "string";
}
function getResultFileArtifacts(result) {
    const details = isRecord(result.details) ? result.details : undefined;
    return Array.isArray(details?.artifacts) ? details.artifacts.filter(isResultFileArtifact) : [];
}
function reportsNoRecordingInProgress(value) {
    try {
        return /no recording in progress/i.test(JSON.stringify(value));
    }
    catch {
        return false;
    }
}
function batchStepReportsNoRecordingInProgress(step) {
    if (!isRecord(step) || step.success !== false)
        return false;
    const command = Array.isArray(step.command) && step.command.every((token) => typeof token === "string") ? extractUpstreamCommandTokens(step.command) : [];
    return command[0] === "record" && command[1] === "stop" && reportsNoRecordingInProgress(step);
}
function resultReportsNoRecordingInProgress(result) {
    if (result.isError !== true)
        return false;
    const details = isRecord(result.details) ? result.details : undefined;
    return details?.command === "record" && details.subcommand === "stop" && reportsNoRecordingInProgress(result.content);
}
function restoreArtifactManifestFromBranch(branch) {
    let restoredManifest;
    for (const entry of branch) {
        if (!isRecord(entry) || entry.type !== "message")
            continue;
        const message = isRecord(entry.message) ? entry.message : undefined;
        if (!message || message.toolName !== "agent_browser")
            continue;
        const details = isRecord(message.details) ? message.details : undefined;
        if (isSessionArtifactManifest(details?.artifactManifest) && (!restoredManifest || details.artifactManifest.updatedAtMs >= restoredManifest.updatedAtMs)) {
            restoredManifest = details.artifactManifest;
        }
    }
    return restoredManifest;
}
function getRecognizedCompatibilityWorkaround(value) {
    const workaround = isRecord(value) ? value : undefined;
    return (workaround?.id === "chatgpt-headless-user-agent" || workaround?.id === "cloudflare-headless-user-agent") && typeof workaround.reason === "string"
        ? { id: workaround.id, reason: workaround.reason }
        : undefined;
}
function restoreManagedSessionCompatibilityWorkaroundFromBranch(branch, sessionName, namespace) {
    let restored;
    const targetKey = getSessionContextKey(sessionName, namespace);
    for (const entry of branch) {
        if (!isRecord(entry) || entry.type !== "message")
            continue;
        const message = isRecord(entry.message) ? entry.message : undefined;
        if (!message || message.toolName !== "agent_browser")
            continue;
        const details = isRecord(message.details) ? message.details : undefined;
        if (!details)
            continue;
        if (getSessionContextKey(typeof details.sessionName === "string" ? details.sessionName : undefined, typeof details.namespace === "string" ? details.namespace : undefined) !== targetKey)
            continue;
        const recognizedWorkaround = getRecognizedCompatibilityWorkaround(details.compatibilityWorkaround);
        const succeeded = getSuccessfulToolResult(details, message);
        const outcome = getManagedSessionOutcome(details);
        const activeAfterFailure = recognizedWorkaround
            && outcome?.activeAfter === true
            && typeof outcome.currentSessionName === "string"
            && getSessionContextKey(outcome.currentSessionName, typeof outcome.currentSessionNamespace === "string" ? outcome.currentSessionNamespace : undefined) === targetKey
            && (outcome.status === "created" || outcome.status === "replaced" || outcome.status === "unchanged");
        if (!succeeded && !activeAfterFailure)
            continue;
        if (recognizedWorkaround) {
            restored = recognizedWorkaround;
        }
        else if (!canUseHeadlessCompatibilityUserAgent(getToolResultArgs(details))) {
            restored = undefined;
        }
    }
    return restored;
}
function restoreManagedSessionHeadedAutosaveDisabledFromBranch(branch, sessionName, namespace) {
    let restored = false;
    const targetKey = getSessionContextKey(sessionName, namespace);
    for (const entry of branch) {
        if (!isRecord(entry) || entry.type !== "message")
            continue;
        const message = isRecord(entry.message) ? entry.message : undefined;
        if (!message || message.toolName !== "agent_browser")
            continue;
        const details = isRecord(message.details) ? message.details : undefined;
        if (!details)
            continue;
        if (getSessionContextKey(typeof details.sessionName === "string" ? details.sessionName : undefined, typeof details.namespace === "string" ? details.namespace : undefined) !== targetKey)
            continue;
        const outcome = getManagedSessionOutcome(details);
        const activeAfterFailure = outcome?.activeAfter === true
            && typeof outcome.currentSessionName === "string"
            && getSessionContextKey(outcome.currentSessionName, typeof outcome.currentSessionNamespace === "string" ? outcome.currentSessionNamespace : undefined) === targetKey;
        if ((getSuccessfulToolResult(details, message) || activeAfterFailure) && typeof details.managedSessionHeadedAutosaveDisabled === "boolean") {
            restored = details.managedSessionHeadedAutosaveDisabled;
        }
    }
    return restored;
}
function restoreManagedSessionHeadedAutosaveIntervalFromBranch(branch, sessionName, namespace) {
    let restored;
    const targetKey = getSessionContextKey(sessionName, namespace);
    for (const entry of branch) {
        if (!isRecord(entry) || entry.type !== "message")
            continue;
        const message = isRecord(entry.message) ? entry.message : undefined;
        if (!message || message.toolName !== "agent_browser")
            continue;
        const details = isRecord(message.details) ? message.details : undefined;
        if (!details)
            continue;
        if (getSessionContextKey(typeof details.sessionName === "string" ? details.sessionName : undefined, typeof details.namespace === "string" ? details.namespace : undefined) !== targetKey)
            continue;
        const outcome = getManagedSessionOutcome(details);
        const activeAfterFailure = outcome?.activeAfter === true
            && typeof outcome.currentSessionName === "string"
            && getSessionContextKey(outcome.currentSessionName, typeof outcome.currentSessionNamespace === "string" ? outcome.currentSessionNamespace : undefined) === targetKey;
        if (!getSuccessfulToolResult(details, message) && !activeAfterFailure)
            continue;
        if (typeof details.managedSessionHeadedAutosaveInterval === "string")
            restored = details.managedSessionHeadedAutosaveInterval;
        else if (details.managedSessionHeadedAutosaveDisabled === true)
            restored = "0";
    }
    return restored;
}
function getToolResultArgs(details) {
    if (Array.isArray(details.args) && details.args.every((arg) => typeof arg === "string"))
        return details.args;
    if (Array.isArray(details.effectiveArgs) && details.effectiveArgs.every((arg) => typeof arg === "string"))
        return details.effectiveArgs;
    return [];
}
function detailsReportCloseAllApplied(details, succeeded) {
    const args = getToolResultArgs(details);
    return details.closeAllApplied === true
        || (succeeded && isCloseAllCommand(extractUpstreamCommandTokens(args)))
        || batchHasSuccessfulCloseAll(details.batchSteps);
}
function deleteIdentityKeysInNamespace(entries, namespace) {
    for (const key of entries.keys()) {
        if (isAgentBrowserSessionIdentityKeyInNamespace(key, namespace))
            entries.delete(key);
    }
}
function isAttachedBrowserInvocation(args, env = getAgentBrowserProcessEnvironment()) {
    const autoConnectEnv = env.AGENT_BROWSER_AUTO_CONNECT;
    return extractUpstreamCommandTokens(args)[0] === "connect"
        || hasLaunchScopedFlagToken(args, "--cdp")
        || hasLaunchScopedFlagToken(args, "--auto-connect")
        || env.AGENT_BROWSER_CDP !== undefined
        || isUpstreamEnvFlagEnabled(autoConnectEnv);
}
function restoreAttachedSessionKeysFromBranch(branch) {
    const attachedSessionKeys = new Set();
    for (const entry of branch) {
        if (!isRecord(entry) || entry.type !== "message")
            continue;
        const message = isRecord(entry.message) ? entry.message : undefined;
        if (!message || message.toolName !== "agent_browser")
            continue;
        const details = isRecord(message.details) ? message.details : undefined;
        if (!details)
            continue;
        const managedSessionOutcome = isRecord(details.managedSessionOutcome) ? details.managedSessionOutcome : undefined;
        const retainedFailedAttachment = details.attachedBrowserSession === true && managedSessionOutcome?.activeAfter === true;
        const succeeded = getSuccessfulToolResult(details, message);
        const batchCloseLifecycle = getSuccessfulBatchCloseLifecycle(details.batchSteps);
        const terminalBatchClose = batchCloseLifecycle?.endsClosed === true;
        const args = getToolResultArgs(details);
        const namespace = typeof details.namespace === "string" ? details.namespace : extractExplicitNamespace(args);
        const sessionName = typeof details.sessionName === "string" ? details.sessionName : extractExplicitSessionName(args);
        const electron = isRecord(details.electron) ? details.electron : undefined;
        const cleanup = isRecord(electron?.cleanup) ? electron.cleanup : undefined;
        for (const cleanupResult of Array.isArray(cleanup?.results) ? cleanup.results : []) {
            for (const identity of getCleanupResultClosedManagedSessionIdentities(cleanupResult, namespace)) {
                attachedSessionKeys.delete(getSessionContextKey(identity.sessionName, identity.namespace) ?? identity.sessionName);
            }
        }
        if (detailsReportCloseAllApplied(details, succeeded)) {
            deleteIdentityKeysInNamespace(attachedSessionKeys, namespace);
            if (sessionName && details.attachedBrowserSession === true && batchCloseLifecycle?.endsClosed === false) {
                attachedSessionKeys.add(getSessionContextKey(sessionName, namespace) ?? sessionName);
            }
            continue;
        }
        if (!succeeded && !retainedFailedAttachment && !terminalBatchClose)
            continue;
        if (!sessionName)
            continue;
        const sessionKey = getSessionContextKey(sessionName, namespace) ?? sessionName;
        if ((succeeded && isCloseCommand(extractUpstreamCommandTokens(args)[0])) || terminalBatchClose)
            attachedSessionKeys.delete(sessionKey);
        else if (details.attachedBrowserSession === true || isAttachedBrowserInvocation(args, {}))
            attachedSessionKeys.add(sessionKey);
    }
    return attachedSessionKeys;
}
function restoreAllowedDomainsBySessionFromBranch(branch) {
    const restoredPolicies = new Map();
    for (const entry of branch) {
        if (!isRecord(entry) || entry.type !== "message")
            continue;
        const message = isRecord(entry.message) ? entry.message : undefined;
        if (!message || message.toolName !== "agent_browser")
            continue;
        const details = isRecord(message.details) ? message.details : undefined;
        if (!details)
            continue;
        const succeeded = getSuccessfulToolResult(details, message);
        const batchCloseLifecycle = getSuccessfulBatchCloseLifecycle(details.batchSteps);
        const args = getToolResultArgs(details);
        const command = typeof details.command === "string" ? details.command : extractUpstreamCommandTokens(args)[0];
        const sessionName = typeof details.sessionName === "string" ? details.sessionName : undefined;
        const namespace = typeof details.namespace === "string" ? details.namespace : undefined;
        const sessionKey = getSessionContextKey(sessionName, namespace);
        const explicitSessionName = extractExplicitSessionName(args);
        if (detailsReportCloseAllApplied(details, succeeded))
            deleteIdentityKeysInNamespace(restoredPolicies, namespace);
        const outcome = getManagedSessionOutcome(details);
        const outcomeSucceeded = outcome?.succeeded === true;
        const outcomeStatus = typeof outcome?.status === "string" ? outcome.status : undefined;
        const outcomeCurrentSessionName = typeof outcome?.currentSessionName === "string" ? outcome.currentSessionName : undefined;
        const outcomeAttemptedSessionName = typeof outcome?.attemptedSessionName === "string" ? outcome.attemptedSessionName : undefined;
        if (outcomeSucceeded && outcomeStatus === "closed") {
            const closedSessionName = outcomeAttemptedSessionName ?? outcomeCurrentSessionName ?? sessionName;
            if (closedSessionName)
                restoredPolicies.delete(getSessionContextKey(closedSessionName, namespace) ?? closedSessionName);
        }
        if (outcomeSucceeded && outcomeStatus === "replaced") {
            const replacedSessionName = typeof outcome.replacedSessionName === "string" ? outcome.replacedSessionName : undefined;
            const replacedSessionNamespace = typeof outcome.replacedSessionNamespace === "string" ? outcome.replacedSessionNamespace : namespace;
            if (replacedSessionName)
                restoredPolicies.delete(getSessionContextKey(replacedSessionName, replacedSessionNamespace) ?? replacedSessionName);
        }
        if ((succeeded && isCloseCommand(command)) || batchCloseLifecycle) {
            const closedSessionName = explicitSessionName ?? sessionName ?? outcomeAttemptedSessionName ?? outcomeCurrentSessionName;
            if (closedSessionName)
                restoredPolicies.delete(getSessionContextKey(closedSessionName, namespace) ?? closedSessionName);
        }
        const electron = isRecord(details.electron) ? details.electron : undefined;
        const cleanup = isRecord(electron?.cleanup) ? electron.cleanup : undefined;
        const cleanupResults = Array.isArray(cleanup?.results) ? cleanup.results : [];
        for (const cleanupResult of cleanupResults) {
            for (const identity of getCleanupResultClosedManagedSessionIdentities(cleanupResult, namespace)) {
                restoredPolicies.delete(getSessionContextKey(identity.sessionName, identity.namespace) ?? identity.sessionName);
            }
        }
        const outcomeKeepsSessionCurrent = outcome?.activeAfter === true
            && (outcomeStatus === "created" || outcomeStatus === "replaced" || outcomeStatus === "unchanged")
            && outcomeCurrentSessionName === sessionName;
        const policy = (succeeded || outcomeKeepsSessionCurrent) && sessionKey && !isCloseCommand(command) && batchCloseLifecycle?.endsClosed !== true ? parseAllowedDomainsPolicyFromArgs(args) : undefined;
        if (policy && sessionKey)
            restoredPolicies.set(sessionKey, policy);
    }
    return restoredPolicies;
}
function trackOwnedManagedSession(sessions, sessionName, cwd, options = {}) {
    if (!sessionName)
        return;
    const key = getSessionContextKey(sessionName, options.namespace) ?? sessionName;
    const existing = sessions.get(key);
    const branchOwned = existing && !existing.branchOwned ? false : options.branchOwned === true;
    const compatibilityWorkaround = Object.hasOwn(options, "compatibilityWorkaround")
        ? options.compatibilityWorkaround
        : existing?.compatibilityWorkaround;
    const headedManagedAutosaveDisabled = options.headedManagedAutosaveDisabled ?? existing?.headedManagedAutosaveDisabled;
    const headedManagedAutosaveInterval = options.headedManagedAutosaveInterval ?? existing?.headedManagedAutosaveInterval;
    sessions.set(key, { branchOwned, compatibilityWorkaround, cwd, headedManagedAutosaveDisabled, headedManagedAutosaveInterval, namespace: options.namespace, sessionName });
}
function untrackOwnedManagedSession(sessions, sessionName, namespace) {
    if (!sessionName)
        return;
    if (sessionName.includes("\u0000"))
        sessions.delete(sessionName);
    else
        sessions.delete(getSessionContextKey(sessionName, namespace) ?? sessionName);
}
function untrackOwnedManagedSessionFromBranchClose(sessions, sessionName, activeBranchRank, closeBranchRank) {
    if (!sessionName || closeBranchRank === undefined)
        return;
    const ownedSession = sessions.get(sessionName);
    if (!ownedSession?.branchOwned)
        return;
    if (activeBranchRank !== undefined && closeBranchRank <= activeBranchRank)
        return;
    sessions.delete(sessionName);
}
function syncOwnedManagedSessionsFromResult(sessions, result, cwd) {
    const details = isRecord(result.details) ? result.details : undefined;
    const outcome = isRecord(details?.managedSessionOutcome) ? details.managedSessionOutcome : undefined;
    if (!outcome)
        return;
    const succeeded = outcome.succeeded === true;
    const status = typeof outcome.status === "string" ? outcome.status : undefined;
    const currentSessionName = typeof outcome.currentSessionName === "string" ? outcome.currentSessionName : undefined;
    const attemptedSessionName = typeof outcome.attemptedSessionName === "string" ? outcome.attemptedSessionName : undefined;
    const namespace = isRecord(details) && typeof details.namespace === "string" ? details.namespace : undefined;
    if (outcome.activeAfter === true && (status === "created" || status === "replaced" || status === "unchanged")) {
        trackOwnedManagedSession(sessions, currentSessionName, cwd, {
            compatibilityWorkaround: getRecognizedCompatibilityWorkaround(details?.compatibilityWorkaround),
            headedManagedAutosaveDisabled: details?.managedSessionHeadedAutosaveDisabled === true,
            headedManagedAutosaveInterval: typeof details?.managedSessionHeadedAutosaveInterval === "string" ? details.managedSessionHeadedAutosaveInterval : undefined,
            namespace,
        });
    }
    if (succeeded && status === "closed") {
        untrackOwnedManagedSession(sessions, attemptedSessionName ?? currentSessionName, namespace);
    }
}
function getTouchedElectronLaunchIds(sessionName, records, namespace) {
    const record = findElectronLaunchRecordForSession(sessionName, records, namespace);
    return record ? new Set([record.launchId]) : undefined;
}
function mergeActiveElectronLaunchRecords(target, source, options = {}) {
    for (const record of getActiveElectronRecords(source)) {
        const alreadyRuntimeOwned = target.has(record.launchId) && options.branchOwnedLaunchIds?.has(record.launchId) === false;
        target.set(record.launchId, record);
        if (options.branchOwnedLaunchIds) {
            if (alreadyRuntimeOwned) {
                // Already runtime-owned from a prior live result; keep it that way.
            }
            else if (options.markBranchOwned === true) {
                options.branchOwnedLaunchIds.add(record.launchId);
            }
            else if (options.touchedLaunchIds?.has(record.launchId)) {
                options.branchOwnedLaunchIds.delete(record.launchId);
            }
        }
    }
}
function removeInactiveOwnedElectronLaunchRecords(target, branchOwnedLaunchIds, source, activeBranchRanks, cleanupBranchRanks) {
    const activeLaunchIds = new Set(getActiveElectronRecords(source).map((record) => record.launchId));
    const launchIds = new Set([...source.keys(), ...cleanupBranchRanks.keys()]);
    for (const launchId of launchIds) {
        if (!target.has(launchId) || !branchOwnedLaunchIds.has(launchId))
            continue;
        const activeBranchRank = activeBranchRanks.get(launchId);
        const cleanupBranchRank = cleanupBranchRanks.get(launchId);
        const restoredInactiveRecord = source.has(launchId) && !activeLaunchIds.has(launchId);
        const cleanupIsLatest = cleanupBranchRank !== undefined && (activeBranchRank === undefined || cleanupBranchRank > activeBranchRank);
        if (!restoredInactiveRecord && !cleanupIsLatest)
            continue;
        target.delete(launchId);
        branchOwnedLaunchIds.delete(launchId);
    }
}
function mergeElectronLaunchRecordMaps(...maps) {
    const merged = new Map();
    for (const map of maps) {
        for (const [launchId, record] of map)
            merged.set(launchId, record);
    }
    return merged;
}
function replaceWithActiveElectronLaunchRecords(target, source, branchOwnedLaunchIds, cleanedLaunchIds) {
    target.clear();
    if (branchOwnedLaunchIds) {
        if (cleanedLaunchIds) {
            for (const launchId of cleanedLaunchIds)
                branchOwnedLaunchIds.delete(launchId);
        }
        else {
            branchOwnedLaunchIds.clear();
        }
    }
    mergeActiveElectronLaunchRecords(target, source, branchOwnedLaunchIds ? { branchOwnedLaunchIds } : {});
}
function shouldSerializeElectronHostInput(compiledElectron) {
    return compiledElectron?.action === "status" || compiledElectron?.action === "probe" || compiledElectron?.action === "cleanup";
}
function getElectronHostLaunchRecordsForInput(options) {
    if (options.compiledElectron?.action === "status" ||
        options.compiledElectron?.action === "cleanup" ||
        (options.compiledElectron?.action === "probe" && options.compiledElectron.launchId)) {
        return mergeElectronLaunchRecordMaps(options.branchRecords, options.ownedRecords);
    }
    return options.branchRecords;
}
function getCleanupResultClosedManagedSessionIdentities(result, fallbackNamespace) {
    if (!isRecord(result) || !Array.isArray(result.steps))
        return [];
    const identities = new Map();
    const record = isRecord(result.record) ? result.record : undefined;
    for (const step of result.steps) {
        if (!isRecord(step) || step.resource !== "managed-session")
            continue;
        if (step.state !== "removed" && step.state !== "already-gone")
            continue;
        const sessionName = typeof step.sessionName === "string"
            ? step.sessionName
            : typeof record?.sessionName === "string" ? record.sessionName : undefined;
        const namespace = typeof step.namespace === "string"
            ? step.namespace
            : typeof record?.namespace === "string" ? record.namespace : fallbackNamespace;
        if (sessionName)
            identities.set(getSessionContextKey(sessionName, namespace) ?? sessionName, { namespace, sessionName });
    }
    return [...identities.values()];
}
function getCleanupResultsClosedManagedSessionIdentities(cleanupResults, fallbackNamespace) {
    const identities = new Map();
    for (const result of cleanupResults) {
        for (const identity of getCleanupResultClosedManagedSessionIdentities(result, fallbackNamespace)) {
            identities.set(getSessionContextKey(identity.sessionName, identity.namespace) ?? identity.sessionName, identity);
        }
    }
    return [...identities.values()];
}
function isElectronLaunchRecord(value) {
    if (!isRecord(value))
        return false;
    return value.version === 1
        && value.launchedByWrapper === true
        && (value.namespace === undefined || typeof value.namespace === "string")
        && typeof value.launchId === "string"
        && typeof value.appName === "string"
        && typeof value.executablePath === "string"
        && typeof value.userDataDir === "string"
        && typeof value.port === "number"
        && typeof value.createdAtMs === "number";
}
function getCleanupResultsElectronRecords(cleanupResults) {
    return cleanupResults
        .map((result) => isRecord(result) ? result.record : undefined)
        .filter(isElectronLaunchRecord);
}
function mergeElectronCleanupRecords(target, cleanupResults) {
    for (const record of getCleanupResultsElectronRecords(cleanupResults)) {
        target.set(record.launchId, record);
    }
}
function getManagedSessionOutcome(details) {
    return isRecord(details.managedSessionOutcome) ? details.managedSessionOutcome : undefined;
}
function getSuccessfulToolResult(details, message) {
    const messageIsError = typeof message.isError === "boolean" ? message.isError : undefined;
    const exitCode = typeof details.exitCode === "number" ? details.exitCode : undefined;
    return messageIsError === undefined ? exitCode === undefined || exitCode === 0 : !messageIsError;
}
function setBranchRankForString(map, value, rank) {
    if (typeof value === "string" && value.length > 0)
        map.set(value, rank);
}
function setBranchManagedSessionActive(events, sessionName, namespace, rank) {
    if (typeof sessionName !== "string" || sessionName.length === 0)
        return;
    const key = getSessionContextKey(sessionName, namespace) ?? sessionName;
    events.managedSessionActiveIdentities.set(key, { namespace, sessionName });
    events.managedSessionActiveRanks.set(key, rank);
}
function collectBranchManagedResourceEvents(branch) {
    const events = {
        electronLaunchActiveRanks: new Map(),
        electronLaunchCleanupRanks: new Map(),
        managedSessionActiveIdentities: new Map(),
        managedSessionActiveRanks: new Map(),
        managedSessionCloseRanks: new Map(),
    };
    let eventRank = 0;
    for (const entry of branch) {
        if (!isRecord(entry) || entry.type !== "message")
            continue;
        const message = isRecord(entry.message) ? entry.message : undefined;
        if (!message || message.toolName !== "agent_browser")
            continue;
        const details = isRecord(message.details) ? message.details : undefined;
        if (!details)
            continue;
        eventRank += 1;
        const succeeded = getSuccessfulToolResult(details, message);
        const args = Array.isArray(details.args) && details.args.every((arg) => typeof arg === "string") ? details.args : [];
        const command = typeof details.command === "string" ? details.command : extractUpstreamCommandTokens(args)[0];
        const sessionName = typeof details.sessionName === "string" ? details.sessionName : undefined;
        const namespace = typeof details.namespace === "string" ? details.namespace : undefined;
        const sessionMode = details.sessionMode === "fresh" || details.sessionMode === "auto" ? details.sessionMode : undefined;
        const usedImplicitSession = details.usedImplicitSession === true;
        const explicitSessionName = extractExplicitSessionName(args);
        const batchCloseLifecycle = getSuccessfulBatchCloseLifecycle(details.batchSteps);
        const closeAllApplied = detailsReportCloseAllApplied(details, succeeded);
        const outcome = getManagedSessionOutcome(details);
        const outcomeSucceeded = outcome?.succeeded === true;
        const outcomeStatus = typeof outcome?.status === "string" ? outcome.status : undefined;
        const outcomeCurrentSessionName = typeof outcome?.currentSessionName === "string" ? outcome.currentSessionName : undefined;
        const outcomeAttemptedSessionName = typeof outcome?.attemptedSessionName === "string" ? outcome.attemptedSessionName : undefined;
        if (outcome?.activeAfter === true && (outcomeStatus === "created" || outcomeStatus === "replaced" || outcomeStatus === "unchanged")) {
            setBranchManagedSessionActive(events, outcomeCurrentSessionName, namespace, eventRank);
        }
        if (outcomeSucceeded && outcomeStatus === "closed") {
            setBranchRankForString(events.managedSessionCloseRanks, getSessionContextKey(outcomeAttemptedSessionName ?? outcomeCurrentSessionName ?? sessionName, namespace), eventRank);
        }
        if (outcome && outcomeStatus === "replaced" && outcome.replacedSessionClosed !== false) {
            const replacedSessionNamespace = typeof outcome.replacedSessionNamespace === "string" ? outcome.replacedSessionNamespace : namespace;
            setBranchRankForString(events.managedSessionCloseRanks, getSessionContextKey(typeof outcome.replacedSessionName === "string" ? outcome.replacedSessionName : undefined, replacedSessionNamespace), eventRank);
        }
        if (succeeded && !isCloseCommand(command) && sessionName && (usedImplicitSession || sessionMode === "fresh" || details.managedSessionHeadedAutosaveDisabled === true || typeof details.managedSessionHeadedAutosaveInterval === "string")) {
            setBranchManagedSessionActive(events, sessionName, namespace, eventRank);
        }
        if (succeeded && isCloseCommand(command)) {
            setBranchRankForString(events.managedSessionCloseRanks, getSessionContextKey(explicitSessionName ?? sessionName ?? outcomeAttemptedSessionName ?? outcomeCurrentSessionName, namespace), eventRank);
        }
        if (closeAllApplied) {
            const retainedSessionKey = batchCloseLifecycle?.endsClosed === false ? getSessionContextKey(sessionName, namespace) : undefined;
            for (const sessionKey of events.managedSessionActiveIdentities.keys()) {
                if (sessionKey !== retainedSessionKey && isAgentBrowserSessionIdentityKeyInNamespace(sessionKey, namespace)) {
                    events.managedSessionCloseRanks.set(sessionKey, eventRank);
                }
            }
        }
        const electron = isRecord(details.electron) ? details.electron : undefined;
        const launch = electron && isElectronLaunchRecord(electron.launch) ? electron.launch : undefined;
        if (launch && getActiveElectronRecords(new Map([[launch.launchId, launch]])).length > 0) {
            events.electronLaunchActiveRanks.set(launch.launchId, eventRank);
        }
        const cleanup = isRecord(electron?.cleanup) ? electron.cleanup : undefined;
        const cleanupRecords = Array.isArray(cleanup?.records) ? cleanup.records : [];
        for (const cleanupRecord of cleanupRecords) {
            if (isElectronLaunchRecord(cleanupRecord))
                events.electronLaunchCleanupRanks.set(cleanupRecord.launchId, eventRank);
        }
        const cleanupResults = Array.isArray(cleanup?.results) ? cleanup.results : [];
        for (const cleanupResult of cleanupResults) {
            if (isRecord(cleanupResult) && isElectronLaunchRecord(cleanupResult.record)) {
                events.electronLaunchCleanupRanks.set(cleanupResult.record.launchId, eventRank);
            }
            for (const identity of getCleanupResultClosedManagedSessionIdentities(cleanupResult, namespace)) {
                events.managedSessionCloseRanks.set(getSessionContextKey(identity.sessionName, identity.namespace) ?? identity.sessionName, eventRank);
            }
        }
    }
    return events;
}
function getCleanupResultsPreservedUserDataDirs(cleanupResults) {
    const userDataDirs = new Set();
    for (const result of cleanupResults) {
        if (!isRecord(result) || !Array.isArray(result.steps) || !isElectronLaunchRecord(result.record))
            continue;
        const userDataDirStep = result.steps.find((step) => isRecord(step) && step.resource === "user-data-dir");
        if (!isRecord(userDataDirStep))
            continue;
        if (userDataDirStep.state === "skipped" || userDataDirStep.state === "failed")
            userDataDirs.add(result.record.userDataDir);
    }
    return [...userDataDirs];
}
function syncElectronCleanupManagedSessions(sessions, cleanupResults, fallbackNamespace) {
    for (const identity of getCleanupResultsClosedManagedSessionIdentities(cleanupResults, fallbackNamespace)) {
        untrackOwnedManagedSession(sessions, identity.sessionName, identity.namespace);
    }
}
async function closeOwnedManagedSessionsExcept(sessions, restoreState, keepSessionName, timeoutMs, attachedSessionKeys, keepNamespace, onClosed) {
    const keepKey = getSessionContextKey(keepSessionName, keepNamespace);
    for (const [key, owner] of [...sessions]) {
        if (key === keepKey)
            continue;
        const error = await closeManagedSession({ cwd: owner.cwd, headedManagedAutosaveInterval: owner.headedManagedAutosaveInterval, namespace: owner.namespace, preserveAttachedBrowserSession: attachedSessionKeys.has(key), restoreState, sessionName: owner.sessionName, timeoutMs });
        if (!error) {
            sessions.delete(key);
            onClosed?.(owner);
        }
    }
}
async function closeOwnedManagedSessions(sessions, restoreState, timeoutMs, attachedSessionKeys, onClosed) {
    await closeOwnedManagedSessionsExcept(sessions, restoreState, undefined, timeoutMs, attachedSessionKeys, undefined, onClosed);
}
function getOffBranchOwnedElectronLaunchRecords(ownedRecords, branchRecords) {
    const activeBranchLaunchIds = new Set(getActiveElectronRecords(branchRecords).map((record) => record.launchId));
    const offBranchRecords = new Map();
    for (const record of getActiveElectronRecords(ownedRecords)) {
        if (!activeBranchLaunchIds.has(record.launchId))
            offBranchRecords.set(record.launchId, record);
    }
    return offBranchRecords;
}
function shouldSerializeBrowserCommand(options) {
    if (!options.explicitSessionName)
        return true;
    if (options.explicitSessionName === options.managedSessionName)
        return true;
    if (options.ownedManagedSessions.has(getSessionContextKey(options.explicitSessionName, options.explicitNamespace) ?? options.explicitSessionName))
        return true;
    return getActiveElectronRecords(options.ownedElectronLaunchRecords).some((record) => record.sessionName === options.explicitSessionName);
}
// Serializes managed-session read/modify/write work so overlapping tool calls cannot promote stale state or close an in-use session.
class AsyncExecutionQueue {
    tail = Promise.resolve();
    run(work) {
        const previous = this.tail;
        let release;
        this.tail = new Promise((resolve) => {
            release = resolve;
        });
        return (async () => {
            await previous;
            try {
                return await work();
            }
            finally {
                release();
            }
        })();
    }
}
function readPackageJson(packageJsonPath) {
    try {
        const parsed = JSON.parse(readFileSync(packageJsonPath, "utf8"));
        return isRecord(parsed) ? parsed : undefined;
    }
    catch {
        return undefined;
    }
}
export class KeyedAsyncExecutionQueue {
    barriers = new Map();
    entries = new Map();
    async run(key, namespace, work) {
        const entry = this.entries.get(key) ?? { queue: new AsyncExecutionQueue(), users: 0 };
        const barrier = this.barriers.get(getAgentBrowserSessionIdentityKey("", namespace)) ?? Promise.resolve();
        entry.users += 1;
        this.entries.set(key, entry);
        try {
            return await entry.queue.run(async () => {
                await barrier;
                return await work();
            });
        }
        finally {
            entry.users -= 1;
            if (entry.users === 0 && this.entries.get(key) === entry)
                this.entries.delete(key);
        }
    }
    async runExclusive(namespace, work) {
        const namespaceKey = getAgentBrowserSessionIdentityKey("", namespace);
        const previous = this.barriers.get(namespaceKey) ?? Promise.resolve();
        let release;
        const blocked = new Promise((resolve) => {
            release = resolve;
        });
        const barrier = previous.then(() => blocked);
        this.barriers.set(namespaceKey, barrier);
        const drains = [...this.entries]
            .filter(([key]) => isAgentBrowserSessionIdentityKeyInNamespace(key, namespace))
            .map(([, { queue }]) => queue.run(async () => undefined));
        await previous;
        await Promise.all(drains);
        try {
            return await work();
        }
        finally {
            release();
            if (this.barriers.get(namespaceKey) === barrier)
                this.barriers.delete(namespaceKey);
        }
    }
}
function mergeBrowserRunMap(current, initial, updated) {
    if (updated === initial)
        return current;
    const merged = new Map(current);
    for (const [key, value] of updated) {
        if (!initial.has(key) || initial.get(key) !== value)
            merged.set(key, value);
    }
    for (const key of initial.keys()) {
        if (!updated.has(key))
            merged.delete(key);
    }
    return merged;
}
export function mergeBrowserRunArtifactManifest(current, initial, updated) {
    if (!updated || updated === initial)
        return current;
    if (current === initial)
        return updated;
    const initialEntries = new Map((initial?.entries ?? []).map((entry) => [getSessionArtifactManifestEntryKey(entry), entry]));
    const changedEntries = updated.entries
        .map((entry, index) => ({ entry, index }))
        .filter(({ entry }) => initialEntries.get(getSessionArtifactManifestEntryKey(entry)) !== entry)
        .sort((left, right) => left.entry.createdAtMs - right.entry.createdAtMs
        || Number(isPendingRecordingCommand(left.entry.command, left.entry.subcommand, left.entry.kind)) - Number(isPendingRecordingCommand(right.entry.command, right.entry.subcommand, right.entry.kind))
        || left.index - right.index)
        .map(({ entry }) => entry);
    return changedEntries.length === 0
        ? current
        : mergeSessionArtifactManifest({
            base: current,
            entries: changedEntries,
            nowMs: Math.max(Date.now(), (current?.updatedAtMs ?? 0) + 1, updated.updatedAtMs),
        });
}
function findPackageRoot(startDir) {
    let currentDir = startDir;
    while (true) {
        const packageJsonPath = join(currentDir, "package.json");
        if (existsSync(packageJsonPath)) {
            // An unrelated malformed package.json above the install dir must not fail extension load.
            const packageJson = readPackageJson(packageJsonPath);
            if (packageJson?.name === "pi-agent-browser-native")
                return currentDir;
        }
        const parentDir = dirname(currentDir);
        if (parentDir === currentDir)
            return startDir;
        currentDir = parentDir;
    }
}
function getInstalledDocsPaths() {
    const packageRoot = findPackageRoot(dirname(fileURLToPath(import.meta.url)));
    return {
        readmePath: join(packageRoot, "README.md"),
        commandReferencePath: join(packageRoot, "docs", "COMMAND_REFERENCE.md"),
        toolContractPath: join(packageRoot, "docs", "TOOL_CONTRACT.md"),
    };
}
const PROJECT_CONFIG_TRUST_ENV = "PI_AGENT_BROWSER_TRUST_PROJECT_CONFIG";
function hasArgvFlag(argv, longFlag, shortFlag) {
    return argv.includes(longFlag) || argv.includes(shortFlag);
}
function isTruthyEnvValue(value) {
    const normalized = value?.trim().toLowerCase();
    return normalized === "1" || normalized === "true" || normalized === "yes";
}
function shouldIncludeProjectConfig(ctx, argv = process.argv, env = process.env) {
    if (hasArgvFlag(argv, "--no-approve", "-na"))
        return false;
    if (typeof ctx?.isProjectTrusted === "function")
        return ctx.isProjectTrusted() === true;
    // Project config can name a browser executable and credential sources, so an unknown trust state is untrusted.
    return isTruthyEnvValue(env[PROJECT_CONFIG_TRUST_ENV]);
}
export default function agentBrowserExtension(pi) {
    const ephemeralSessionSeed = createEphemeralSessionSeed();
    const agentBrowserConfig = loadAgentBrowserConfigSync({
        cwd: process.cwd(),
        includeProjectConfig: false,
    });
    const webSearchToolAvailable = canRegisterWebSearchTool(agentBrowserConfig);
    const toolPromptGuidelines = buildToolPromptGuidelines({
        browserDefaultProfile: agentBrowserConfig.trustedBrowserDefaultProfile,
        browserExecutablePath: agentBrowserConfig.trustedBrowserExecutablePath,
        browserExecutablePathScope: agentBrowserConfig.trustedBrowserExecutablePathScope,
        includeWebSearch: webSearchToolAvailable,
        docs: getInstalledDocsPaths(),
    });
    const implicitSessionIdleTimeoutMs = String(getImplicitSessionIdleTimeoutMs());
    const implicitSessionCloseTimeoutMs = getImplicitSessionCloseTimeoutMs();
    let webSearchToolRegistered = false;
    let managedSessionActive = false;
    let managedSessionBaseName = createImplicitSessionName(undefined, process.cwd(), ephemeralSessionSeed);
    let managedSessionCompatibilityWorkaround;
    let managedSessionHeadedAutosaveDisabled = false;
    let managedSessionHeadedAutosaveInterval;
    let managedSessionName = managedSessionBaseName;
    let managedSessionCwd = process.cwd();
    let managedSessionNamespace;
    let freshSessionOrdinal = 0;
    let sessionPageState = new SessionPageState();
    let traceOwners = new Map();
    let artifactManifest;
    let activeRecordingReservations = new Map();
    let recordingSessionTombstones = new Map();
    let recordingSessionTombstonesToPersist = new Map();
    let allowedDomainsBySession = new Map();
    let attachedSessionKeys = new Set();
    let networkRoutesBySession = new Map();
    let electronLaunchRecords = new Map();
    let ownedElectronLaunchRecords = new Map();
    let branchOwnedElectronLaunchIds = new Set();
    let electronChildProcesses = new Map();
    const managedSessionRestoreState = new ManagedSessionRestoreState();
    const ownedManagedSessions = new Map();
    const managedSessionExecutionQueue = new AsyncExecutionQueue();
    const artifactExecutionQueue = new AsyncExecutionQueue();
    const callerOwnedSessionExecutionQueues = new KeyedAsyncExecutionQueue();
    const activeScriptControllers = new Set();
    const activeScriptExecutions = new Set();
    let branchRestoreGeneration = 0;
    let branchStateGeneration = 0;
    const validatedUpstreamPathKeys = new Set();
    const appendRecordingTransitions = (transitions) => {
        for (const transition of transitions) {
            const key = getAgentBrowserSessionIdentityKey(transition.reservation.sessionName, transition.reservation.namespace);
            if (transition.state === "active") {
                recordingSessionTombstones.delete(key);
                recordingSessionTombstonesToPersist.delete(key);
            }
            else {
                recordingSessionTombstones.set(key, transition.reservation);
            }
            try {
                appendRecordingReservationTransition(pi, transition);
                recordingSessionTombstonesToPersist.delete(key);
            }
            catch {
                if (transition.state === "closed")
                    recordingSessionTombstonesToPersist.set(key, transition.reservation);
            }
        }
    };
    const appendActiveRecordingCleanupAction = (result, reservation) => {
        if (result.isError !== true)
            return result;
        const details = isRecord(result.details) ? result.details : {};
        const nextActions = Array.isArray(details.nextActions) ? [...details.nextActions] : [];
        if (nextActions.some((action) => action.id === "stop-pending-recording"))
            return result;
        const stopActions = applyNamespaceToNextActions(applySessionToNextActions([
            buildNextToolAction({
                args: ["record", "stop"],
                id: "stop-pending-recording",
                reason: "Stop the active recording so the requested video can be finalized and verified on disk.",
                safety: "The file remains pending until record stop succeeds; verify details.artifactVerification afterward.",
            }),
        ], reservation.sessionName), reservation.namespace);
        appendUniqueAgentBrowserNextActions(nextActions, stopActions);
        const cleanupNotice = "An active recording remains open. Use the exact stop-pending-recording payload in details.nextActions before leaving this session.";
        let noticeAppended = false;
        const content = result.content.map((item) => {
            if (noticeAppended || item.type !== "text")
                return item;
            noticeAppended = true;
            return { ...item, text: `${item.text}\n\n${cleanupNotice}` };
        });
        if (!noticeAppended)
            content.push({ type: "text", text: cleanupNotice });
        return { ...result, content, details: { ...details, nextActions } };
    };
    const retireRecordingSession = (sessionName, namespace, retireManifest = true) => {
        const reservation = retireRecordingReservation(activeRecordingReservations, sessionName, namespace);
        const previousManifest = artifactManifest;
        if (retireManifest && artifactManifest)
            artifactManifest = retirePendingRecordingManifestEntries(artifactManifest, sessionName, namespace);
        if (!reservation && artifactManifest === previousManifest)
            return;
        const terminalReservation = reservation ?? { absolutePath: "", cwd: managedSessionCwd, namespace, path: "", sessionName };
        const terminalKey = getAgentBrowserSessionIdentityKey(sessionName, namespace);
        recordingSessionTombstones.set(terminalKey, terminalReservation);
        try {
            appendRecordingReservationTransition(pi, {
                reservation: terminalReservation,
                state: "closed",
            });
            recordingSessionTombstonesToPersist.delete(terminalKey);
        }
        catch {
            recordingSessionTombstonesToPersist.set(terminalKey, terminalReservation);
        }
    };
    const syncRecordingReservationsFromResult = (result) => {
        const handledClosedSessionKeys = new Set();
        const details = isRecord(result.details) ? result.details : undefined;
        const batchSteps = Array.isArray(details?.batchSteps) ? details.batchSteps : undefined;
        const resultSessionName = typeof details?.sessionName === "string" ? details.sessionName : undefined;
        const resultNamespace = typeof details?.namespace === "string" ? details.namespace : undefined;
        if (!batchSteps) {
            appendRecordingTransitions(applyRecordingArtifactsToReservations(activeRecordingReservations, getResultFileArtifacts(result)));
            return handledClosedSessionKeys;
        }
        let sessionClosed = false;
        for (const step of batchSteps) {
            if (!isRecord(step))
                continue;
            const command = Array.isArray(step.command) && step.command.every((token) => typeof token === "string") ? step.command : undefined;
            const commandTokens = command ? extractUpstreamCommandTokens(command) : [];
            const commandName = commandTokens[0];
            if (resultSessionName && batchStepReportsNoRecordingInProgress(step)) {
                const sessionKey = getAgentBrowserSessionIdentityKey(resultSessionName, resultNamespace);
                retireRecordingSession(resultSessionName, resultNamespace, false);
                handledClosedSessionKeys.add(sessionKey);
                continue;
            }
            if (step.success === true && commandName && isCloseCommand(commandName) && resultSessionName) {
                const sessionKey = getAgentBrowserSessionIdentityKey(resultSessionName, resultNamespace);
                retireRecordingSession(resultSessionName, resultNamespace, false);
                handledClosedSessionKeys.add(sessionKey);
                sessionClosed = true;
                continue;
            }
            if (sessionClosed && commandName === "record")
                continue;
            if (step.success === true && sessionClosed)
                sessionClosed = false;
            const artifacts = Array.isArray(step.artifacts) ? step.artifacts.filter(isResultFileArtifact) : [];
            appendRecordingTransitions(applyRecordingArtifactsToReservations(activeRecordingReservations, artifacts));
        }
        for (const sessionKey of handledClosedSessionKeys) {
            if (!activeRecordingReservations.has(sessionKey) && artifactManifest && resultSessionName) {
                artifactManifest = retirePendingRecordingManifestEntries(artifactManifest, resultSessionName, resultNamespace);
            }
        }
        return handledClosedSessionKeys;
    };
    const validateUpstreamVersion = async (cwd, signal) => {
        const processEnvironment = getAgentBrowserProcessEnvironment();
        const pathKey = `${cwd}\0${processEnvironment.PATH ?? processEnvironment.Path ?? ""}`;
        if (validatedUpstreamPathKeys.has(pathKey))
            return undefined;
        const probe = await runAgentBrowserProcess({ args: ["--version"], cwd, signal, timeoutMs: 5_000 });
        if (probe.spawnError?.code === "ENOENT" || probe.exitCode === 127 || probe.aborted)
            return undefined;
        let error;
        let observedVersion;
        if (probe.spawnError || probe.exitCode !== 0) {
            const detail = redactSensitiveText(probe.spawnError?.message ?? (probe.stderr.trim() || `exit ${probe.exitCode}`));
            error = `agent-browser --version could not be validated (${detail}). Run pi-agent-browser-doctor before browser-backed calls.`;
        }
        else {
            observedVersion = parseAgentBrowserVersionOutput(probe.stdout);
            error = getAgentBrowserVersionValidationError(probe.stdout);
        }
        if (!error) {
            validatedUpstreamPathKeys.add(pathKey);
            return undefined;
        }
        return {
            content: [{ type: "text", text: error }],
            details: {
                expectedVersion: TARGET_AGENT_BROWSER_VERSION,
                failureCategory: "validation-error",
                observedVersion,
                resultCategory: "failure",
                versionValidation: { expected: TARGET_AGENT_BROWSER_VERSION_LABEL, observed: observedVersion },
            },
            isError: true,
        };
    };
    const clearSessionScopedBrowserState = (sessionName, namespace) => {
        const key = getSessionContextKey(sessionName, namespace) ?? sessionName;
        allowedDomainsBySession = new Map(allowedDomainsBySession);
        allowedDomainsBySession.delete(key);
        attachedSessionKeys.delete(key);
        networkRoutesBySession = new Map(networkRoutesBySession);
        networkRoutesBySession.delete(key);
        traceOwners.delete(key);
        sessionPageState.clearSession(key);
    };
    const closeScriptSessionLeaseWithinQueue = async (sessionName, cwd) => {
        const closeError = await withIsolatedAgentBrowserEnvironment(() => closeManagedSession({
            cwd,
            namespace: AGENT_BROWSER_SCRIPT_NAMESPACE,
            restoreState: managedSessionRestoreState,
            sessionName,
            timeoutMs: implicitSessionCloseTimeoutMs,
        }));
        if (closeError) {
            try {
                appendScriptSessionLease(pi, sessionName, "failed");
            }
            catch { }
            return redactSensitiveText(closeError);
        }
        try {
            appendScriptSessionLease(pi, sessionName, "closed");
        }
        catch {
            managedSessionRestoreState.disable(sessionName);
            return "The isolated session closed, but its durable cleanup record could not be saved.";
        }
        untrackOwnedManagedSession(ownedManagedSessions, sessionName, AGENT_BROWSER_SCRIPT_NAMESPACE);
        managedSessionRestoreState.clear(sessionName, AGENT_BROWSER_SCRIPT_NAMESPACE);
        retireRecordingSession(sessionName, AGENT_BROWSER_SCRIPT_NAMESPACE);
        clearSessionScopedBrowserState(sessionName, AGENT_BROWSER_SCRIPT_NAMESPACE);
        return undefined;
    };
    const recoverScriptSessionLeasesWithinQueue = async (ctx) => {
        const pendingSessionNames = new Set([...ownedManagedSessions.values()]
            .map((session) => session.sessionName)
            .filter(isAgentBrowserScriptSessionName));
        for (const lease of getScriptSessionLeasesFromBranch(ctx.sessionManager.getBranch()).values()) {
            if (lease.cleanup !== "closed")
                pendingSessionNames.add(lease.sessionName);
        }
        for (const sessionName of pendingSessionNames) {
            trackOwnedManagedSession(ownedManagedSessions, sessionName, ctx.cwd, { branchOwned: true, namespace: AGENT_BROWSER_SCRIPT_NAMESPACE });
            managedSessionRestoreState.disable(sessionName, AGENT_BROWSER_SCRIPT_NAMESPACE);
            await closeScriptSessionLeaseWithinQueue(sessionName, ctx.cwd);
        }
    };
    const restoreBranchBackedState = (ctx, options) => {
        branchRestoreGeneration += 1;
        branchStateGeneration += 1;
        const previousManagedSessionActive = managedSessionActive;
        const previousManagedSessionName = managedSessionName;
        const previousFreshSessionOrdinal = freshSessionOrdinal;
        const previousAttachedSessionKeys = attachedSessionKeys;
        managedSessionBaseName = createImplicitSessionName(ctx.sessionManager.getSessionId(), ctx.cwd, ephemeralSessionSeed);
        const branch = ctx.sessionManager.getBranch();
        const branchResourceEvents = collectBranchManagedResourceEvents(branch);
        const restoredState = restoreManagedSessionStateFromBranch(branch, managedSessionBaseName);
        managedSessionRestoreState.replace(restoredState.managedSessionRestoreDisabledIdentities, {
            preserveDaemonRestoreKeys: !options.resetRuntimeOwnership,
        });
        managedSessionActive = restoredState.active;
        const restoredFreshSessionOrdinal = options.resetRuntimeOwnership
            ? restoredState.freshSessionOrdinal
            : Math.max(previousFreshSessionOrdinal, restoredState.freshSessionOrdinal);
        const shouldReservePostCloseSession = !restoredState.active && restoredState.closedSessionName === restoredState.sessionName;
        const alreadyReservedPostCloseSession = shouldReservePostCloseSession
            && !options.resetRuntimeOwnership
            && !previousManagedSessionActive
            && previousFreshSessionOrdinal > restoredState.freshSessionOrdinal
            && previousFreshSessionOrdinal === restoredFreshSessionOrdinal
            && previousManagedSessionName === createFreshSessionName(managedSessionBaseName, ephemeralSessionSeed, restoredFreshSessionOrdinal);
        const nextFreshSessionOrdinal = shouldReservePostCloseSession && !alreadyReservedPostCloseSession
            ? restoredFreshSessionOrdinal + 1
            : restoredFreshSessionOrdinal;
        managedSessionName = shouldReservePostCloseSession
            ? alreadyReservedPostCloseSession
                ? previousManagedSessionName
                : createFreshSessionName(managedSessionBaseName, ephemeralSessionSeed, nextFreshSessionOrdinal)
            : restoredState.sessionName;
        managedSessionNamespace = shouldReservePostCloseSession ? undefined : restoredState.namespace;
        managedSessionCompatibilityWorkaround = managedSessionActive
            ? restoreManagedSessionCompatibilityWorkaroundFromBranch(branch, managedSessionName, managedSessionNamespace)
            : undefined;
        managedSessionHeadedAutosaveDisabled = managedSessionActive
            && restoreManagedSessionHeadedAutosaveDisabledFromBranch(branch, managedSessionName, managedSessionNamespace);
        managedSessionHeadedAutosaveInterval = managedSessionActive
            ? restoreManagedSessionHeadedAutosaveIntervalFromBranch(branch, managedSessionName, managedSessionNamespace)
            : undefined;
        managedSessionCwd = ctx.cwd;
        freshSessionOrdinal = nextFreshSessionOrdinal;
        sessionPageState = SessionPageState.fromBranch(branch);
        traceOwners = new Map();
        artifactManifest = restoreArtifactManifestFromBranch(branch);
        const restoredRecordingState = restoreRecordingReservationStateFromBranch(branch);
        for (const [key, reservation] of recordingSessionTombstones) {
            if (restoredRecordingState.terminal.has(key))
                recordingSessionTombstonesToPersist.delete(key);
            else
                recordingSessionTombstonesToPersist.set(key, reservation);
        }
        for (const [key, reservation] of restoredRecordingState.terminal) {
            if (!activeRecordingReservations.has(key))
                recordingSessionTombstones.set(key, reservation);
        }
        for (const key of recordingSessionTombstones.keys())
            restoredRecordingState.active.delete(key);
        for (const [key, reservation] of activeRecordingReservations)
            restoredRecordingState.active.set(key, reservation);
        activeRecordingReservations = restoredRecordingState.active;
        allowedDomainsBySession = restoreAllowedDomainsBySessionFromBranch(branch);
        attachedSessionKeys = restoreAttachedSessionKeysFromBranch(branch);
        networkRoutesBySession = new Map();
        electronLaunchRecords = restoreElectronLaunchRecordsFromBranch(branch);
        for (const record of getActiveElectronRecords(electronLaunchRecords)) {
            if (record.sessionName)
                attachedSessionKeys.add(getSessionContextKey(record.sessionName, record.namespace) ?? record.sessionName);
        }
        if (options.resetRuntimeOwnership) {
            ownedManagedSessions.clear();
            ownedElectronLaunchRecords = new Map();
            branchOwnedElectronLaunchIds = new Set();
        }
        else {
            for (const [sessionName, closeRank] of branchResourceEvents.managedSessionCloseRanks) {
                untrackOwnedManagedSessionFromBranchClose(ownedManagedSessions, sessionName, branchResourceEvents.managedSessionActiveRanks.get(sessionName), closeRank);
            }
            removeInactiveOwnedElectronLaunchRecords(ownedElectronLaunchRecords, branchOwnedElectronLaunchIds, electronLaunchRecords, branchResourceEvents.electronLaunchActiveRanks, branchResourceEvents.electronLaunchCleanupRanks);
        }
        for (const [sessionKey, identity] of branchResourceEvents.managedSessionActiveIdentities) {
            const activeRank = branchResourceEvents.managedSessionActiveRanks.get(sessionKey);
            const closeRank = branchResourceEvents.managedSessionCloseRanks.get(sessionKey);
            if (activeRank === undefined || (closeRank !== undefined && closeRank >= activeRank))
                continue;
            if (!isRestorableManagedSessionName(identity.sessionName, managedSessionBaseName))
                continue;
            trackOwnedManagedSession(ownedManagedSessions, identity.sessionName, ctx.cwd, {
                branchOwned: true,
                compatibilityWorkaround: restoreManagedSessionCompatibilityWorkaroundFromBranch(branch, identity.sessionName, identity.namespace),
                headedManagedAutosaveDisabled: restoreManagedSessionHeadedAutosaveDisabledFromBranch(branch, identity.sessionName, identity.namespace),
                headedManagedAutosaveInterval: restoreManagedSessionHeadedAutosaveIntervalFromBranch(branch, identity.sessionName, identity.namespace),
                namespace: identity.namespace,
            });
        }
        if (restoredState.active) {
            trackOwnedManagedSession(ownedManagedSessions, restoredState.sessionName, ctx.cwd, {
                branchOwned: true,
                compatibilityWorkaround: managedSessionCompatibilityWorkaround,
                headedManagedAutosaveDisabled: managedSessionHeadedAutosaveDisabled,
                headedManagedAutosaveInterval: managedSessionHeadedAutosaveInterval,
                namespace: restoredState.namespace,
            });
        }
        for (const record of getActiveElectronRecords(electronLaunchRecords)) {
            if (!record.sessionName || !isRestorableManagedSessionName(record.sessionName, managedSessionBaseName))
                continue;
            const sessionKey = getSessionContextKey(record.sessionName) ?? record.sessionName;
            const activeRank = branchResourceEvents.managedSessionActiveRanks.get(sessionKey);
            const closeRank = branchResourceEvents.managedSessionCloseRanks.get(sessionKey);
            if (activeRank === undefined || (closeRank !== undefined && closeRank >= activeRank))
                continue;
            trackOwnedManagedSession(ownedManagedSessions, record.sessionName, ctx.cwd, {
                branchOwned: true,
                headedManagedAutosaveDisabled: restoreManagedSessionHeadedAutosaveDisabledFromBranch(branch, record.sessionName),
                headedManagedAutosaveInterval: restoreManagedSessionHeadedAutosaveIntervalFromBranch(branch, record.sessionName),
            });
        }
        mergeActiveElectronLaunchRecords(ownedElectronLaunchRecords, electronLaunchRecords, {
            branchOwnedLaunchIds: branchOwnedElectronLaunchIds,
            markBranchOwned: true,
        });
        if (!options.resetRuntimeOwnership) {
            for (const sessionKey of previousAttachedSessionKeys) {
                if (ownedManagedSessions.has(sessionKey))
                    attachedSessionKeys.add(sessionKey);
            }
            for (const record of ownedElectronLaunchRecords.values()) {
                const sessionKey = getSessionContextKey(record.sessionName);
                if (sessionKey && previousAttachedSessionKeys.has(sessionKey))
                    attachedSessionKeys.add(sessionKey);
            }
        }
    };
    const registerWebSearchToolIfAvailable = (configState) => {
        if (webSearchToolRegistered || !canRegisterWebSearchTool(configState))
            return;
        pi.registerTool(createAgentBrowserWebSearchTool(configState, {
            loadConfigState(ctx) {
                return loadAgentBrowserConfigSync({
                    cwd: ctx.cwd,
                    includeProjectConfig: shouldIncludeProjectConfig(ctx),
                });
            },
        }));
        webSearchToolRegistered = true;
    };
    pi.on("session_start", async (_event, ctx) => {
        restoreBranchBackedState(ctx, { resetRuntimeOwnership: true });
        electronChildProcesses = new Map();
        // Launches still visible on this branch stay live; only profiles left by a process that is gone are reaped.
        void adoptOrphanedElectronLaunches({
            preserveLaunchIds: new Set(getActiveElectronRecords(electronLaunchRecords).map((record) => record.launchId)),
            timeoutMs: implicitSessionCloseTimeoutMs,
        }).catch(() => undefined);
        registerWebSearchToolIfAvailable(loadAgentBrowserConfigSync({
            cwd: ctx.cwd,
            includeProjectConfig: shouldIncludeProjectConfig(ctx),
        }));
        await artifactExecutionQueue.run(() => managedSessionExecutionQueue.run(() => recoverScriptSessionLeasesWithinQueue(ctx)));
    });
    pi.on("session_tree", async (_event, ctx) => {
        for (const controller of activeScriptControllers)
            controller.abort();
        await Promise.allSettled([...activeScriptExecutions]);
        await artifactExecutionQueue.run(() => managedSessionExecutionQueue.run(async () => {
            restoreBranchBackedState(ctx, { resetRuntimeOwnership: false });
            await recoverScriptSessionLeasesWithinQueue(ctx);
        }));
    });
    pi.on("session_shutdown", async (event, ctx) => {
        for (const controller of activeScriptControllers)
            controller.abort();
        await Promise.allSettled([...activeScriptExecutions]);
        branchRestoreGeneration += 1;
        branchStateGeneration += 1;
        let preservedElectronProfileDirs = [];
        await artifactExecutionQueue.run(() => managedSessionExecutionQueue.run(async () => {
            const shutdownCwd = ctx?.cwd ?? managedSessionCwd;
            const quitting = event?.reason === "quit";
            preservedElectronProfileDirs = quitting
                ? []
                : getActiveElectronRecords(electronLaunchRecords).map((record) => record.userDataDir);
            const electronRecordsToCleanup = quitting
                ? ownedElectronLaunchRecords
                : getOffBranchOwnedElectronLaunchRecords(ownedElectronLaunchRecords, electronLaunchRecords);
            const electronCleanupResults = await cleanupActiveElectronHostLaunches({
                attachedSessionKeys,
                cwd: shutdownCwd,
                electronChildProcesses,
                electronLaunchRecords: electronRecordsToCleanup,
                managedSessionRestoreState,
                ownedManagedSessions,
                timeoutMs: implicitSessionCloseTimeoutMs,
            });
            preservedElectronProfileDirs = [...new Set([
                    ...preservedElectronProfileDirs,
                    ...getCleanupResultsPreservedUserDataDirs(electronCleanupResults),
                ])];
            syncElectronCleanupManagedSessions(ownedManagedSessions, electronCleanupResults);
            for (const identity of getCleanupResultsClosedManagedSessionIdentities(electronCleanupResults))
                retireRecordingSession(identity.sessionName, identity.namespace);
            if (quitting) {
                await closeOwnedManagedSessions(ownedManagedSessions, managedSessionRestoreState, implicitSessionCloseTimeoutMs, attachedSessionKeys, (owner) => retireRecordingSession(owner.sessionName, owner.namespace));
            }
            else {
                await closeOwnedManagedSessionsExcept(ownedManagedSessions, managedSessionRestoreState, managedSessionActive ? managedSessionName : undefined, implicitSessionCloseTimeoutMs, attachedSessionKeys, managedSessionActive ? managedSessionNamespace : undefined, (owner) => retireRecordingSession(owner.sessionName, owner.namespace));
            }
        }));
        managedSessionActive = false;
        managedSessionCompatibilityWorkaround = undefined;
        managedSessionHeadedAutosaveDisabled = false;
        managedSessionHeadedAutosaveInterval = undefined;
        managedSessionNamespace = undefined;
        for (const reservation of recordingSessionTombstonesToPersist.values()) {
            try {
                appendRecordingReservationTransition(pi, { reservation, state: "closed" });
            }
            catch { }
        }
        for (const reservation of activeRecordingReservations.values()) {
            try {
                appendRecordingReservationTransition(pi, { reservation, state: "active" });
            }
            catch { }
        }
        sessionPageState.reset();
        traceOwners = new Map();
        artifactManifest = undefined;
        activeRecordingReservations = new Map();
        recordingSessionTombstones = new Map();
        recordingSessionTombstonesToPersist = new Map();
        allowedDomainsBySession = new Map();
        attachedSessionKeys = new Set();
        networkRoutesBySession = new Map();
        electronLaunchRecords = new Map();
        ownedElectronLaunchRecords = new Map();
        branchOwnedElectronLaunchIds = new Set();
        electronChildProcesses = new Map();
        ownedManagedSessions.clear();
        cleanupManagedSessionRestoreConfig();
        await cleanupSecureTempArtifacts({ preservePaths: preservedElectronProfileDirs });
    });
    pi.on("before_agent_start", async (event, ctx) => {
        if (!shouldAppendBrowserSystemPrompt(event.prompt)) {
            return undefined;
        }
        const runtimeConfig = loadAgentBrowserConfigSync({
            cwd: ctx.cwd,
            includeProjectConfig: shouldIncludeProjectConfig(ctx),
        });
        // Upstream's own `./agent-browser.json` is dropped rather than applied in an untrusted repo, so say so
        // instead of leaving the model to wonder why a project file it can read has no effect.
        const upstreamProjectConfigPin = planUpstreamConfigPin({ cwd: ctx.cwd });
        const browserGuidance = [
            upstreamProjectConfigPin.kind === "pin"
                ? getUpstreamProjectConfigIgnoredNotice(upstreamProjectConfigPin)
                : undefined,
            runtimeConfig.browserExecutablePathScope === "project"
                ? buildBrowserExecutablePathGuideline(runtimeConfig.browserExecutablePath, "project")
                : undefined,
            runtimeConfig.browserDefaultProfileScope === "project"
                ? buildBrowserDefaultProfileGuideline(runtimeConfig.browserDefaultProfile)
                : undefined,
        ].filter((line) => typeof line === "string" && line.length > 0);
        const runtimeConfigPrompt = browserGuidance.length > 0
            ? `\n\nProject agent_browser config guidance:\n${browserGuidance.map((line) => `- ${line}`).join("\n")}`
            : "";
        return {
            systemPrompt: `${event.systemPrompt}\n\n${PROJECT_RULE_PROMPT}${runtimeConfigPrompt}`,
        };
    });
    pi.on("tool_call", async (event, ctx) => {
        const promptPolicy = buildPromptPolicy(getLatestUserPrompt(ctx.sessionManager.getBranch()));
        if (isBashToolCallEvent(event) &&
            !promptPolicy.allowLegacyAgentBrowserBash &&
            looksLikeDirectAgentBrowserBash(event.input.command) &&
            !isHarmlessAgentBrowserInspectionCommand(event.input.command) &&
            !(await isDirectAgentBrowserBashAllowed(ctx.cwd))) {
            return {
                block: true,
                reason: "Use the native agent_browser tool instead of bash for agent-browser in this environment. Direct bash launches stay available when the user starts pi with PI_AGENT_BROWSER_ALLOW_DIRECT_BASH=1.",
            };
        }
    });
    pi.on("tool_result", async (event) => buildAgentBrowserToolResultPatch(event));
    const agentBrowserTool = {
        name: "agent_browser",
        label: "Agent Browser",
        description: "Browse and interact with websites using agent-browser. Use this for web research, reading live docs, opening pages, taking snapshots or screenshots, clicking links, filling forms, extracting page content, and authenticated/profile-based browser work. Input choice: `script` for one-shot JavaScript orchestration; default `args` for open → snapshot -i → click/fill @refs; `semanticAction` for stable role/text/label targets; `job` or `qa` for multi-step checks; `electron` only for desktop apps; experimental `sourceLookup` / `networkSourceLookup` for candidates only.",
        promptSnippet: "Browse websites, read live docs, click and fill pages, extract browser content, take screenshots, and automate real web workflows.",
        promptGuidelines: toolPromptGuidelines,
        parameters: AGENT_BROWSER_PARAMS,
        renderCall(args, theme, context) {
            const text = context.lastComponent instanceof Text ? context.lastComponent : new Text("", 0, 0);
            text.setText(formatAgentBrowserRenderCall(args, theme, context.expanded));
            return text;
        },
        renderResult(result, options, theme, context) {
            const component = context.lastComponent instanceof AgentBrowserResultComponent
                ? context.lastComponent
                : new AgentBrowserResultComponent();
            component.setState(formatAgentBrowserRenderResult(result, options, theme, context.isError), options.expanded, theme);
            return component;
        },
        async execute(toolCallId, params, signal, onUpdate, ctx) {
            const promptPolicy = buildPromptPolicy(getLatestUserPrompt(ctx.sessionManager.getBranch()));
            const outputPath = isRecord(params) && typeof params.outputPath === "string" ? params.outputPath : undefined;
            const resolvedInput = resolveAgentBrowserInput({
                getBatchPreflightValidationError: (args, stdin) => getArtifactPreflightValidationError({ args, cwd: ctx.cwd, outputPath, stdin }),
                managedSessionActive,
                params,
            });
            if (resolvedInput.status === "invalid") {
                return buildValidationFailureResult(resolvedInput);
            }
            const outputPathValidationError = getAgentBrowserOutputPathValidationError(outputPath, ctx.cwd);
            if (outputPathValidationError) {
                return buildValidationFailureResult({ attemptedKind: resolvedInput.kind, kind: "invalid", redactedArgs: resolvedInput.redactedArgs, status: "invalid", toolArgs: resolvedInput.toolArgs, toolStdin: resolvedInput.toolStdin, validationError: outputPathValidationError });
            }
            const applyUnserializedOutputPath = async (result, preserveTextContent = false) => {
                if (!outputPath || result.isError === true || (isRecord(result.details) && result.details.resultCategory === "failure"))
                    return result;
                return artifactExecutionQueue.run(async () => {
                    const reservationError = getArtifactPreflightValidationError({
                        activeRecordingReservations: activeRecordingReservations.values(),
                        args: [],
                        cwd: ctx.cwd,
                        outputPath,
                    });
                    if (reservationError) {
                        return buildValidationFailureResult({ attemptedKind: resolvedInput.kind, kind: "invalid", redactedArgs: resolvedInput.redactedArgs, status: "invalid", toolArgs: resolvedInput.toolArgs, toolStdin: resolvedInput.toolStdin, validationError: reservationError });
                    }
                    return applyAgentBrowserOutputPath({ cwd: ctx.cwd, outputPath, preserveTextContent, result });
                });
            };
            const versionCheckCommand = extractUpstreamCommandTokens(resolvedInput.toolArgs)[0];
            const electronHostOnlyAction = resolvedInput.kind === "electron" && ["cleanup", "list", "status"].includes(resolvedInput.compiledElectron.action);
            const browserBackedVersionCheck = needsManagedSession(parseArgvDescriptor(resolvedInput.toolArgs));
            if (!electronHostOnlyAction && browserBackedVersionCheck && !isPlainTextInspectionArgs(resolvedInput.toolArgs) && !isCloseCommand(versionCheckCommand) && signal?.aborted !== true) {
                const versionFailure = resolvedInput.kind === "script"
                    ? await withIsolatedAgentBrowserEnvironment(() => validateUpstreamVersion(ctx.cwd, signal))
                    : await validateUpstreamVersion(ctx.cwd, signal);
                if (versionFailure)
                    return applyAgentBrowserOutputPath({ cwd: ctx.cwd, outputPath, result: versionFailure });
            }
            if (resolvedInput.kind === "script") {
                if (!ctx.sessionManager.getSessionFile()) {
                    return buildValidationFailureResult({
                        attemptedKind: "script",
                        kind: "invalid",
                        redactedArgs: [],
                        status: "invalid",
                        toolArgs: [],
                        validationError: "script requires a persisted Pi session so its isolated browser-session cleanup lease survives restart; relaunch Pi without --no-session.",
                    });
                }
                const sessionName = createAgentBrowserScriptSessionName();
                const innerResults = [];
                const scriptTimeoutMs = params.timeoutMs ?? AGENT_BROWSER_SCRIPT_DEFAULT_TIMEOUT_MS;
                const deadline = Date.now() + scriptTimeoutMs;
                let leased = false;
                let cleanupError;
                let run = {
                    callCount: 0,
                    emitCount: 0,
                    error: "Script sandbox execution failed.",
                    failureCategory: "upstream-error",
                    ok: false,
                    rejectedCallCount: 0,
                    steps: [],
                };
                const scriptController = new AbortController();
                const abortScript = () => scriptController.abort();
                signal?.addEventListener("abort", abortScript, { once: true });
                if (signal?.aborted)
                    scriptController.abort();
                activeScriptControllers.add(scriptController);
                let finishScriptExecution;
                const scriptExecution = new Promise((resolve) => {
                    finishScriptExecution = resolve;
                });
                activeScriptExecutions.add(scriptExecution);
                try {
                    const pendingRun = runAgentBrowserScript({
                        beforeFirstCall() {
                            appendScriptSessionLease(pi, sessionName, "active");
                            trackOwnedManagedSession(ownedManagedSessions, sessionName, ctx.cwd, { namespace: AGENT_BROWSER_SCRIPT_NAMESPACE });
                            managedSessionRestoreState.disable(sessionName, AGENT_BROWSER_SCRIPT_NAMESPACE);
                            leased = true;
                        },
                        code: resolvedInput.compiledScript.code,
                        dispatch: async (innerParams, innerSignal) => {
                            const remainingMs = Math.max(1, deadline - Date.now());
                            const innerTimeoutMs = Math.min(innerParams.timeoutMs ?? remainingMs, remainingMs);
                            const innerResult = await withIsolatedAgentBrowserEnvironment(() => agentBrowserTool.execute(`${toolCallId}:script:${innerResults.length + 1}`, {
                                args: ["--namespace", AGENT_BROWSER_SCRIPT_NAMESPACE, "--session", sessionName, ...innerParams.args],
                                stdin: innerParams.stdin,
                                timeoutMs: innerTimeoutMs,
                            }, innerSignal, undefined, ctx));
                            innerResults.push(innerResult);
                            return await buildScriptBrowserEnvelope(innerResult, innerParams.args, sessionName);
                        },
                        signal: scriptController.signal,
                        timeoutMs: scriptTimeoutMs,
                    });
                    run = await pendingRun;
                }
                catch { }
                finally {
                    activeScriptControllers.delete(scriptController);
                    signal?.removeEventListener("abort", abortScript);
                    if (leased) {
                        try {
                            cleanupError = await artifactExecutionQueue.run(() => managedSessionExecutionQueue.run(() => closeScriptSessionLeaseWithinQueue(sessionName, ctx.cwd)));
                        }
                        catch {
                            cleanupError = "The isolated script session cleanup operation failed.";
                            try {
                                appendScriptSessionLease(pi, sessionName, "failed");
                            }
                            catch { }
                        }
                    }
                    activeScriptExecutions.delete(scriptExecution);
                    finishScriptExecution();
                }
                let scriptResult = buildScriptToolResult({ cleanupError, innerResults, run, sessionName: leased ? sessionName : undefined });
                if (artifactManifest) {
                    scriptResult = {
                        ...scriptResult,
                        details: {
                            ...(isRecord(scriptResult.details) ? scriptResult.details : {}),
                            artifactManifest,
                            artifactRetentionSummary: formatSessionArtifactRetentionSummary(artifactManifest),
                        },
                    };
                }
                return applyUnserializedOutputPath(scriptResult);
            }
            const { toolArgs } = resolvedInput;
            const compiledElectron = resolvedInput.kind === "electron" ? resolvedInput.compiledElectron : undefined;
            const redactedCompiledElectron = resolvedInput.kind === "electron" ? resolvedInput.redactedCompiledElectron : undefined;
            const runElectronHostInput = async () => {
                const electronHostLaunchRecords = getElectronHostLaunchRecordsForInput({
                    branchRecords: electronLaunchRecords,
                    compiledElectron,
                    ownedRecords: ownedElectronLaunchRecords,
                });
                let electronHostResult = await handleElectronHostInput({
                    attachedSessionKeys,
                    compiledElectron,
                    cwd: ctx.cwd,
                    electronChildProcesses,
                    electronLaunchRecords: electronHostLaunchRecords,
                    implicitSessionCloseTimeoutMs,
                    managedSessionActive,
                    managedSessionName,
                    managedSessionNamespace,
                    managedSessionRestoreState,
                    ownedManagedSessions,
                    redactedCompiledElectron,
                    sessionPageState,
                    signal,
                });
                if (electronHostResult && compiledElectron?.action === "cleanup") {
                    branchStateGeneration += 1;
                    const cleanupRecords = isRecord(electronHostResult.details)
                        && isRecord(electronHostResult.details.electron)
                        && isRecord(electronHostResult.details.electron.cleanup)
                        && Array.isArray(electronHostResult.details.electron.cleanup.results)
                        ? electronHostResult.details.electron.cleanup.results
                        : [];
                    const cleanedLaunchIds = new Set();
                    for (const cleanupResult of cleanupRecords) {
                        if (isRecord(cleanupResult) && isElectronLaunchRecord(cleanupResult.record)) {
                            cleanedLaunchIds.add(cleanupResult.record.launchId);
                        }
                    }
                    replaceWithActiveElectronLaunchRecords(ownedElectronLaunchRecords, electronHostLaunchRecords, branchOwnedElectronLaunchIds, cleanedLaunchIds);
                    mergeElectronCleanupRecords(electronLaunchRecords, cleanupRecords);
                    const cleanupNamespace = isRecord(electronHostResult.details) && typeof electronHostResult.details.namespace === "string"
                        ? electronHostResult.details.namespace
                        : undefined;
                    const closedSessionIdentities = getCleanupResultsClosedManagedSessionIdentities(cleanupRecords, cleanupNamespace);
                    syncElectronCleanupManagedSessions(ownedManagedSessions, cleanupRecords, cleanupNamespace);
                    for (const identity of closedSessionIdentities) {
                        retireRecordingSession(identity.sessionName, identity.namespace);
                        const closedSessionKey = getSessionContextKey(identity.sessionName, identity.namespace) ?? identity.sessionName;
                        clearSessionScopedBrowserState(closedSessionKey);
                        if (closedSessionKey === (getSessionContextKey(managedSessionName, managedSessionNamespace) ?? managedSessionName)) {
                            managedSessionActive = false;
                            managedSessionCompatibilityWorkaround = undefined;
                            managedSessionHeadedAutosaveDisabled = false;
                            managedSessionHeadedAutosaveInterval = undefined;
                            managedSessionNamespace = undefined;
                            freshSessionOrdinal += 1;
                            managedSessionName = createFreshSessionName(managedSessionBaseName, ephemeralSessionSeed, freshSessionOrdinal);
                        }
                    }
                    if (artifactManifest) {
                        electronHostResult = {
                            ...electronHostResult,
                            details: {
                                ...(isRecord(electronHostResult.details) ? electronHostResult.details : {}),
                                artifactManifest,
                                artifactRetentionSummary: formatSessionArtifactRetentionSummary(artifactManifest),
                            },
                        };
                    }
                }
                return electronHostResult;
            };
            const runSerializedElectronHostInput = () => shouldSerializeElectronHostInput(compiledElectron)
                ? managedSessionExecutionQueue.run(runElectronHostInput)
                : runElectronHostInput();
            const electronHostResult = compiledElectron?.action === "cleanup"
                ? await artifactExecutionQueue.run(async () => {
                    const reservationError = outputPath ? getArtifactPreflightValidationError({
                        activeRecordingReservations: activeRecordingReservations.values(),
                        args: [],
                        cwd: ctx.cwd,
                        outputPath,
                    }) : undefined;
                    if (reservationError) {
                        return buildValidationFailureResult({ attemptedKind: resolvedInput.kind, kind: "invalid", redactedArgs: resolvedInput.redactedArgs, status: "invalid", toolArgs: resolvedInput.toolArgs, toolStdin: resolvedInput.toolStdin, validationError: reservationError });
                    }
                    const result = await runSerializedElectronHostInput();
                    return result ? applyAgentBrowserOutputPath({ cwd: ctx.cwd, outputPath, result }) : result;
                })
                : await runSerializedElectronHostInput();
            if (electronHostResult) {
                return compiledElectron?.action === "cleanup" ? electronHostResult : applyUnserializedOutputPath(electronHostResult);
            }
            const explicitSessionName = extractExplicitSessionName(toolArgs);
            const explicitNamespace = extractExplicitNamespace(toolArgs);
            const serializeBrowserCommand = shouldSerializeBrowserCommand({
                explicitNamespace,
                explicitSessionName,
                managedSessionName,
                ownedElectronLaunchRecords,
                ownedManagedSessions,
            });
            const callerOwnedSessionNamespace = explicitSessionName
                ? resolveAgentBrowserNamespace(toolArgs, getAgentBrowserProcessEnvironment().AGENT_BROWSER_NAMESPACE)
                : undefined;
            const callerOwnedSessionQueueKey = !serializeBrowserCommand && explicitSessionName
                ? getSessionContextKey(explicitSessionName, callerOwnedSessionNamespace) ?? explicitSessionName
                : undefined;
            const runBrowserCommand = async () => {
                const branchRestoreGenerationAtStart = branchRestoreGeneration;
                const generationAtStart = branchStateGeneration;
                const sessionPageStateUpdate = sessionPageState.beginUpdate();
                const browserRunState = {
                    allowedDomainsBySession,
                    artifactManifest,
                    attachedSessionKeys,
                    closedManagedSessionNames: new Set(),
                    electronChildProcesses,
                    electronLaunchRecords,
                    ephemeralSessionSeed,
                    freshSessionOrdinal,
                    managedSessionActive,
                    managedSessionBaseName,
                    managedSessionCompatibilityWorkaround,
                    managedSessionHeadedAutosaveDisabled,
                    managedSessionHeadedAutosaveInterval,
                    managedSessionCwd,
                    managedSessionName,
                    managedSessionNamespace,
                    managedSessionRestoreState,
                    networkRoutesBySession,
                    ownedManagedSessions,
                    sessionPageState,
                    traceOwners,
                };
                const initialAllowedDomainsBySession = browserRunState.allowedDomainsBySession;
                const initialArtifactManifest = browserRunState.artifactManifest;
                const initialNetworkRoutesBySession = browserRunState.networkRoutesBySession;
                const attachedSessionRequested = isAttachedBrowserInvocation(toolArgs)
                    || (resolvedInput.kind === "electron" && resolvedInput.compiledElectron.action === "launch");
                const allocatesFreshManagedSession = explicitSessionName === undefined
                    && (params.sessionMode === "fresh" || (resolvedInput.kind === "electron" && resolvedInput.compiledElectron.action === "launch"));
                const reusableSessionKey = allocatesFreshManagedSession
                    ? undefined
                    : callerOwnedSessionQueueKey ?? getSessionContextKey(browserRunState.managedSessionName, browserRunState.managedSessionNamespace);
                const attachedSessionKnown = reusableSessionKey !== undefined && attachedSessionKeys.has(reusableSessionKey);
                let result = await runAgentBrowserTool({
                    ctx,
                    cwd: ctx.cwd,
                    electronPostCommandStatusSettleMs: ELECTRON_POST_COMMAND_STATUS_SETTLE_MS,
                    electronProfileIsolationDetails: ELECTRON_PROFILE_ISOLATION_DETAILS,
                    implicitSessionCloseTimeoutMs,
                    implicitSessionIdleTimeoutMs,
                    input: resolvedInput,
                    onUpdate,
                    params,
                    establishAttachedBrowserSession: attachedSessionRequested && !attachedSessionKnown,
                    preserveAttachedBrowserSession: attachedSessionRequested || attachedSessionKnown,
                    promptPolicy,
                    sessionPageStateUpdate,
                    signal,
                    state: browserRunState,
                });
                const branchRestoreStillCurrent = branchRestoreGenerationAtStart === branchRestoreGeneration;
                const resultDetails = isRecord(result.details) ? result.details : undefined;
                const resultSessionName = typeof resultDetails?.sessionName === "string"
                    ? resultDetails.sessionName
                    : extractExplicitSessionName(toolArgs);
                const resultNamespace = typeof resultDetails?.namespace === "string"
                    ? resultDetails.namespace
                    : resolveAgentBrowserNamespace(toolArgs, getAgentBrowserProcessEnvironment().AGENT_BROWSER_NAMESPACE);
                if (branchRestoreStillCurrent) {
                    const resultBatchCloseLifecycle = getSuccessfulBatchCloseLifecycle(resultDetails?.batchSteps);
                    const resultSessionKey = getSessionContextKey(resultSessionName, resultNamespace) ?? resultSessionName;
                    const managedSessionOutcome = isRecord(resultDetails?.managedSessionOutcome) ? resultDetails.managedSessionOutcome : undefined;
                    const closeAllApplied = resultDetails?.closeAllApplied === true;
                    const attachedSessionRemainsActive = result.isError !== true
                        || ((attachedSessionRequested || attachedSessionKnown) && managedSessionOutcome?.activeAfter === true);
                    const closesAttachedSession = (result.isError !== true && isCloseCommand(extractUpstreamCommandTokens(toolArgs)[0]))
                        || resultBatchCloseLifecycle?.endsClosed === true;
                    if (closeAllApplied) {
                        deleteIdentityKeysInNamespace(attachedSessionKeys, resultNamespace);
                        if (resultSessionKey && attachedSessionRemainsActive && (attachedSessionRequested || attachedSessionKnown) && resultBatchCloseLifecycle?.endsClosed === false) {
                            attachedSessionKeys.add(resultSessionKey);
                            result = { ...result, details: { ...(resultDetails ?? {}), attachedBrowserSession: true } };
                        }
                    }
                    else if (resultSessionKey && closesAttachedSession)
                        attachedSessionKeys.delete(resultSessionKey);
                    else if (resultSessionKey && attachedSessionRemainsActive && (attachedSessionRequested || attachedSessionKnown)) {
                        attachedSessionKeys.add(resultSessionKey);
                        result = { ...result, details: { ...(resultDetails ?? {}), attachedBrowserSession: true } };
                    }
                }
                if (branchRestoreStillCurrent) {
                    allowedDomainsBySession = mergeBrowserRunMap(allowedDomainsBySession, initialAllowedDomainsBySession, browserRunState.allowedDomainsBySession);
                    networkRoutesBySession = mergeBrowserRunMap(networkRoutesBySession, initialNetworkRoutesBySession, browserRunState.networkRoutesBySession);
                    artifactManifest = mergeBrowserRunArtifactManifest(artifactManifest, initialArtifactManifest, browserRunState.artifactManifest);
                    const handledBatchCloseKeys = syncRecordingReservationsFromResult(result);
                    if (resultDetails?.closeAllApplied === true) {
                        for (const [sessionKey, reservation] of [...activeRecordingReservations]) {
                            if (isAgentBrowserSessionIdentityKeyInNamespace(sessionKey, resultNamespace)) {
                                retireRecordingSession(reservation.sessionName, reservation.namespace);
                            }
                        }
                    }
                    for (const closedSessionKey of browserRunState.closedManagedSessionNames) {
                        if (handledBatchCloseKeys.has(closedSessionKey))
                            continue;
                        const reservation = activeRecordingReservations.get(closedSessionKey);
                        if (reservation)
                            retireRecordingSession(reservation.sessionName, reservation.namespace);
                    }
                    if (resultSessionName && resultReportsNoRecordingInProgress(result)) {
                        retireRecordingSession(resultSessionName, resultNamespace);
                    }
                    if (resultSessionName) {
                        const reservation = activeRecordingReservations.get(getAgentBrowserSessionIdentityKey(resultSessionName, resultNamespace));
                        if (reservation)
                            result = appendActiveRecordingCleanupAction(result, reservation);
                    }
                    if (artifactManifest) {
                        result = {
                            ...result,
                            details: {
                                ...(isRecord(result.details) ? result.details : {}),
                                artifactManifest,
                                artifactRetentionSummary: formatSessionArtifactRetentionSummary(artifactManifest),
                            },
                        };
                    }
                }
                const branchStateStillCurrent = generationAtStart === branchStateGeneration;
                if (serializeBrowserCommand || branchStateStillCurrent) {
                    freshSessionOrdinal = Math.max(freshSessionOrdinal, browserRunState.freshSessionOrdinal);
                    managedSessionActive = browserRunState.managedSessionActive;
                    managedSessionCompatibilityWorkaround = browserRunState.managedSessionCompatibilityWorkaround;
                    managedSessionHeadedAutosaveDisabled = browserRunState.managedSessionHeadedAutosaveDisabled === true;
                    managedSessionHeadedAutosaveInterval = browserRunState.managedSessionHeadedAutosaveInterval;
                    managedSessionCwd = browserRunState.managedSessionCwd;
                    managedSessionName = browserRunState.managedSessionName;
                    managedSessionNamespace = browserRunState.managedSessionNamespace;
                    for (const closedSessionName of browserRunState.closedManagedSessionNames) {
                        untrackOwnedManagedSession(ownedManagedSessions, closedSessionName);
                    }
                    syncOwnedManagedSessionsFromResult(ownedManagedSessions, result, browserRunState.managedSessionCwd);
                    mergeActiveElectronLaunchRecords(ownedElectronLaunchRecords, electronLaunchRecords, {
                        branchOwnedLaunchIds: branchOwnedElectronLaunchIds,
                        touchedLaunchIds: !result.isError
                            ? getTouchedElectronLaunchIds(explicitSessionName ?? browserRunState.managedSessionName, electronLaunchRecords, explicitSessionName ? resolveAgentBrowserNamespace(toolArgs, getAgentBrowserProcessEnvironment().AGENT_BROWSER_NAMESPACE) : browserRunState.managedSessionNamespace)
                            : undefined,
                    });
                    if (serializeBrowserCommand)
                        branchStateGeneration += 1;
                }
                return applyAgentBrowserOutputPath({ cwd: ctx.cwd, outputPath, preserveTextContent: Array.isArray(params.args) && params.args.includes("--json"), result });
            };
            const closesAllSessions = commandClosesAllSessions(toolArgs, resolvedInput.toolStdin);
            const closeAllNamespace = closesAllSessions
                ? resolveAgentBrowserNamespace(toolArgs, getAgentBrowserProcessEnvironment().AGENT_BROWSER_NAMESPACE)
                : undefined;
            const runWithinSessionQueue = () => {
                if (closesAllSessions)
                    return managedSessionExecutionQueue.run(() => callerOwnedSessionExecutionQueues.runExclusive(closeAllNamespace, runBrowserCommand));
                if (serializeBrowserCommand)
                    return managedSessionExecutionQueue.run(runBrowserCommand);
                return callerOwnedSessionQueueKey
                    ? callerOwnedSessionExecutionQueues.run(callerOwnedSessionQueueKey, callerOwnedSessionNamespace, runBrowserCommand)
                    : runBrowserCommand();
            };
            if (!commandTouchesArtifactLifecycle(toolArgs, resolvedInput.toolStdin, outputPath))
                return runWithinSessionQueue();
            return artifactExecutionQueue.run(async () => {
                const artifactValidationError = getArtifactPreflightValidationError({
                    activeRecordingReservations: activeRecordingReservations.values(),
                    args: toolArgs,
                    cwd: ctx.cwd,
                    outputPath,
                    stdin: resolvedInput.toolStdin,
                });
                if (!artifactValidationError)
                    return runWithinSessionQueue();
                return applyAgentBrowserOutputPath({
                    cwd: ctx.cwd,
                    outputPath,
                    result: buildValidationFailureResult({
                        attemptedKind: resolvedInput.kind,
                        kind: "invalid",
                        redactedArgs: resolvedInput.redactedArgs,
                        status: "invalid",
                        toolArgs: resolvedInput.toolArgs,
                        toolStdin: resolvedInput.toolStdin,
                        validationError: artifactValidationError,
                    }),
                });
            });
        },
    };
    pi.registerTool(agentBrowserTool);
    registerWebSearchToolIfAvailable(agentBrowserConfig);
}
