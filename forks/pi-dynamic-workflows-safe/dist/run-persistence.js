/**
 * Workflow run state persistence for pause/resume support.
 */
import { hostname, uptime } from "node:os";
import { join } from "node:path";
import { ensureDir as ensureDirFs, listJsonFilesSafe, PRIVATE_FILE_MODE, readJsonWithBackupRecovery, resolvePersistenceFs, unlinkIfExistsSafe, writeJsonAtomicWithBackup, } from "./fs-persistence.js";
import { workflowProjectPaths } from "./workflow-paths.js";
/**
 * Retention policy for terminal (completed/failed/aborted) runs kept on
 * disk. Bounded so a long-lived project directory can't accumulate an
 * unbounded number of run files (each polled/listed on every list() call).
 * A run in "running" or "paused" status is NEVER counted against this cap
 * or evicted by it — only genuinely finished runs age out, oldest (by
 * updatedAt) first, once the terminal-run count exceeds the cap. 300 is
 * generous enough to cover weeks of typical usage while keeping list()'s
 * per-call directory scan bounded.
 */
export const DEFAULT_MAX_TERMINAL_RUNS_ON_DISK = 300;
const TERMINAL_RUN_STATUSES = new Set(["completed", "failed", "aborted"]);
/**
 * How long a run lock written by ANOTHER host may go unrefreshed before it is
 * treated as dead and reclaimed. Nothing here can inspect a foreign process, so
 * time is the only bound available — and a bound there must be: without one, a
 * lock left behind by a machine that has since been renamed, or by a peer
 * sharing a synced run store, would hold the run forever and no resume, auto-
 * resume or startup reconciliation could ever touch it again. The holder
 * refreshes its heartbeat on every persist (see LOCK_HEARTBEAT_INTERVAL_MS), so
 * a window this wide is only reached by a run that stopped reporting progress
 * entirely.
 */
export const DEFAULT_FOREIGN_LOCK_STALE_MS = 30 * 60_000;
/** Floor on foreignLockStaleMs: below this a busy holder could be reclaimed. */
const MIN_FOREIGN_LOCK_STALE_MS = 60_000;
/**
 * How often the lease holder rewrites its own lock with a fresh heartbeat.
 * Bounded so the hot path (a progress persist every few hundred ms, plus every
 * list() the task panel makes) does not turn into a lock write each time.
 */
const LOCK_HEARTBEAT_INTERVAL_MS = 30_000;
/**
 * `list()` does a full readdirSync + per-file readFileSync + JSON.parse of the
 * entire lifetime run history. It is called on essentially every progress tick
 * (task-panel re-render → WorkflowManager.listRuns()/listAllRuns()), so an
 * unbounded number of ticks each re-walked and re-parsed every run file on
 * disk. Cache the computed list for a short TTL — long enough to absorb a
 * burst of same-tick reads, short enough that a read from a DIFFERENT process
 * (or a mutation this instance doesn't own) still shows up quickly. Mirrors
 * the ~1s settings-read TTL cache in task-panel.ts.
 */
const LIST_CACHE_TTL_MS = 300;
/**
 * Run ids name files: `${runsDir}/${runId}.json` and its lock/backup sidecars.
 * They are generated (generateRunId, plus a workflow-name slug) but they also
 * arrive from outside — the `workflow` tool's `resumeFromRunId` and
 * `workflow_control`'s `runId` are model-supplied — so a separator or `..` in
 * one would let a read, a write, or a delete leave the run store entirely.
 */
const RUN_ID_PATTERN = /^[A-Za-z0-9][A-Za-z0-9._-]{0,199}$/;
/** Whether `runId` is safe to turn into a path inside a run store. */
export function isSafeRunId(runId) {
    return typeof runId === "string" && RUN_ID_PATTERN.test(runId) && !runId.includes("..");
}
const RUN_STATUSES = new Set(["pending", "running", "paused", "completed", "failed", "aborted"]);
const AGENT_STATUSES = new Set(["queued", "running", "done", "error", "skipped"]);
const isPlainObject = (value) => typeof value === "object" && value !== null && !Array.isArray(value);
const isText = (value) => typeof value === "string";
const isFiniteNumber = (value) => typeof value === "number" && Number.isFinite(value);
const isBool = (value) => typeof value === "boolean";
const isTextArray = (value) => Array.isArray(value) && value.every(isText);
/**
 * Copy `key` from `source` to `target` when present, or record why it can't be
 * trusted. Absent is always fine — every optional field predates some release.
 */
const takeField = (target, source, key, accepts, problems) => {
    const value = source[key];
    if (value === undefined)
        return;
    if (!accepts(value)) {
        problems.push(key);
        return;
    }
    target[key] = value;
};
/**
 * Project a parsed run file onto PersistedRunState, field by field.
 *
 * Run records are read from the global store AND from a project-local store
 * (`<cwd>/.pi/workflows/runs`, see WorkflowProjectPaths.legacyRunsDir), and a
 * project-local store is part of whatever repository happens to be checked
 * out. Since a record's `script` is what resume() executes, a run file is
 * untrusted input, not this module's own output: unknown fields are dropped,
 * a known field of the wrong type rejects the whole record, and provenance
 * (`sourcePath`/`sourceStore`) is assigned by the caller, never believed from
 * the file. Returns the reason on rejection so the caller can say so loudly.
 */
export function validatePersistedRunState(value) {
    if (!isPlainObject(value))
        return { reason: "not a JSON object" };
    if (!isSafeRunId(value.runId))
        return { reason: "runId is missing or not a safe file-name id" };
    if (!isText(value.script))
        return { reason: "script is missing or not a string" };
    if (typeof value.status !== "string" || !RUN_STATUSES.has(value.status)) {
        return { reason: `status ${JSON.stringify(value.status)} is not a run status` };
    }
    const problems = [];
    const state = {
        runId: value.runId,
        script: value.script,
        status: value.status,
        workflowName: isText(value.workflowName) ? value.workflowName : "",
        phases: isTextArray(value.phases) ? value.phases : [],
        logs: isTextArray(value.logs) ? value.logs : [],
        agents: [],
        startedAt: isText(value.startedAt) ? value.startedAt : new Date(0).toISOString(),
        updatedAt: isText(value.updatedAt) ? value.updatedAt : new Date(0).toISOString(),
    };
    // args/result/journal[].result are free-form JSON by contract (whatever the
    // script passed or an agent returned), so they are carried as-is; everything
    // that steers execution or the UI is typed.
    state.args = value.args;
    state.result = value.result;
    for (const [key, accepts] of [
        ["sessionId", isText],
        ["pauseReason", isText],
        ["resetHint", isText],
        ["currentPhase", isText],
        ["completedAt", isText],
        ["durationMs", isFiniteNumber],
        ["autoResume", isBool],
        ["toolset", isText],
        ["maxAgents", isFiniteNumber],
        ["concurrency", isFiniteNumber],
        ["agentRetries", isFiniteNumber],
        ["autoResumeAttempts", isFiniteNumber],
        ["installId", isText],
        ["foreignSource", isText],
    ]) {
        takeField(state, value, key, accepts, problems);
    }
    // tokenBudget/agentTimeoutMs use null as a meaningful "explicitly none".
    for (const key of ["tokenBudget", "agentTimeoutMs"]) {
        takeField(state, value, key, (v) => v === null || isFiniteNumber(v), problems);
    }
    if (value.tokenUsage !== undefined) {
        const usage = validateTokenUsage(value.tokenUsage);
        if (!usage)
            problems.push("tokenUsage");
        else
            state.tokenUsage = usage;
    }
    if (value.agents !== undefined) {
        if (!Array.isArray(value.agents))
            problems.push("agents");
        else {
            const agents = [];
            for (const entry of value.agents) {
                const agent = validatePersistedAgent(entry);
                if (!agent) {
                    problems.push("agents[]");
                    break;
                }
                agents.push(agent);
            }
            state.agents = agents;
        }
    }
    if (value.journal !== undefined) {
        if (!Array.isArray(value.journal))
            problems.push("journal");
        else {
            const journal = [];
            for (const entry of value.journal) {
                if (!isPlainObject(entry) || !isFiniteNumber(entry.index) || !isText(entry.hash)) {
                    problems.push("journal[]");
                    break;
                }
                if (entry.runId !== undefined && !isText(entry.runId)) {
                    problems.push("journal[].runId");
                    break;
                }
                if (entry.storeDelta !== undefined && !isPlainObject(entry.storeDelta)) {
                    problems.push("journal[].storeDelta");
                    break;
                }
                journal.push({
                    index: entry.index,
                    runId: entry.runId,
                    hash: entry.hash,
                    result: entry.result,
                    storeDelta: entry.storeDelta,
                });
            }
            state.journal = journal;
        }
    }
    if (problems.length > 0)
        return { reason: `ill-typed field(s): ${[...new Set(problems)].join(", ")}` };
    return { state: state };
}
function validateTokenUsage(value) {
    if (!isPlainObject(value))
        return undefined;
    const keys = ["input", "output", "total", "cost", "cacheRead", "cacheWrite"];
    const usage = {};
    for (const key of keys) {
        const entry = value[key];
        if (entry === undefined)
            continue;
        if (!isFiniteNumber(entry))
            return undefined;
        usage[key] = entry;
    }
    return {
        input: usage.input ?? 0,
        output: usage.output ?? 0,
        total: usage.total ?? 0,
        ...(usage.cost !== undefined ? { cost: usage.cost } : {}),
        ...(usage.cacheRead !== undefined ? { cacheRead: usage.cacheRead } : {}),
        ...(usage.cacheWrite !== undefined ? { cacheWrite: usage.cacheWrite } : {}),
    };
}
function validatePersistedAgent(value) {
    if (!isPlainObject(value))
        return null;
    if (!isFiniteNumber(value.id))
        return null;
    if (typeof value.status !== "string" || !AGENT_STATUSES.has(value.status))
        return null;
    const problems = [];
    const agent = {
        id: value.id,
        status: value.status,
        label: isText(value.label) ? value.label : "",
        prompt: isText(value.prompt) ? value.prompt : "",
    };
    agent.result = value.result;
    for (const [key, accepts] of [
        ["callId", isText],
        ["phase", isText],
        ["resultPreview", isText],
        ["error", isText],
        ["errorCode", isText],
        ["recoverable", isBool],
        ["startedAt", isText],
        ["endedAt", isText],
        ["tokens", isFiniteNumber],
        ["model", isText],
    ]) {
        takeField(agent, value, key, accepts, problems);
    }
    takeField(agent, value, "history", (v) => Array.isArray(v) && v.every(isPlainObject), problems);
    takeField(agent, value, "tokenUsage", isPlainObject, problems);
    if (problems.length > 0)
        return null;
    return agent;
}
/**
 * Whether this install wrote this record and it lives in the global run store.
 * Both halves matter: the store location is unforgeable (nothing outside this
 * process writes there) and the install id is unguessable, so a run file that
 * travelled in with a repository satisfies neither.
 */
export function isInstallOwnedRun(run, installId) {
    return run.sourceStore === "global" && !run.foreignSource && run.installId === installId;
}
/**
 * Where a run's script came from when it is not this install's own work: the
 * project-local file it was read from, or the marker a relocated record carries
 * (see PersistedRunState.foreignSource). undefined means the script was written
 * by this install into its own store. Callers that copy a run's script somewhere
 * more durable — `/workflows save`, the navigator's save action — carry this
 * with it so a repo-supplied script does not become trusted by being saved.
 */
export function runScriptOrigin(run) {
    if (run.foreignSource)
        return run.foreignSource;
    if (run.sourceStore === "legacy")
        return run.sourcePath ?? "project store";
    return undefined;
}
/**
 * Whether a persisted run may be resumed with no human in the loop (see
 * UsageLimitScheduler). Auto-resume executes `script`, so it is restricted to
 * runs this install created; anything else stays listable, inspectable, and
 * resumable by explicit user action.
 */
export function isAutoResumeEligibleRun(run, installId) {
    return isInstallOwnedRun(run, installId) && run.autoResume !== false;
}
export function createRunPersistence(cwd, fsOverride, options) {
    const fs = resolvePersistenceFs(fsOverride);
    const _existsSync = fs.existsSync;
    const _readFileSync = fs.readFileSync;
    const _statSync = fs.statSync;
    const _unlinkSync = fs.unlinkSync;
    const _writeFileSync = fs.writeFileSync;
    const maxTerminalRunsOnDisk = options?.maxTerminalRunsOnDisk ?? DEFAULT_MAX_TERMINAL_RUNS_ON_DISK;
    const foreignLockStaleMs = Math.max(MIN_FOREIGN_LOCK_STALE_MS, options?.foreignLockStaleMs ?? DEFAULT_FOREIGN_LOCK_STALE_MS);
    const paths = workflowProjectPaths(cwd);
    const runsDir = paths.runsDir;
    const legacyRunsDir = paths.legacyRunsDir;
    const ensureDir = () => ensureDirFs(fs, runsDir);
    const runPath = (dir, runId) => join(dir, `${runId}.json`);
    const primaryRunPath = (runId) => runPath(runsDir, runId);
    const legacyRunPath = (runId) => runPath(legacyRunsDir, runId);
    const lockPath = (dir, runId) => join(dir, `${runId}.lock`);
    const primaryLockPath = (runId) => lockPath(runsDir, runId);
    const legacyLockPath = (runId) => lockPath(legacyRunsDir, runId);
    const candidateRunPaths = (runId) => [primaryRunPath(runId), legacyRunPath(runId)];
    const pidIsAlive = (pid) => {
        if (!Number.isInteger(pid) || pid <= 0)
            return false;
        try {
            process.kill(pid, 0);
            return true;
        }
        catch (err) {
            if (err.code === "EPERM")
                return true;
            return false;
        }
    };
    /**
     * The most recent moment `lock` showed any sign of life: its own heartbeat,
     * the file's mtime, or failing both the time it was written. mtime and
     * startedAt are what let a lock written before heartbeats existed still age
     * out rather than read as "never refreshed".
     *
     * Evidence dated further ahead than one stale window is discarded rather than
     * believed. A shared/synced run store is precisely where clocks disagree, and
     * a timestamp from the future can never fall outside the window — so trusting
     * one would put the run back where the staleness rule exists to stop it going:
     * held forever, by a machine nobody can ask. A holder whose clock is merely
     * skewed (by less than the window) is still safe; one whose clock is wrong by
     * more than that loses its claim, loudly, instead of keeping it for good.
     */
    const lockLastSeenAt = (lock, path) => {
        const horizon = Date.now() + foreignLockStaleMs;
        let seen = 0;
        const consider = (value) => {
            if (Number.isFinite(value) && value <= horizon)
                seen = Math.max(seen, value);
        };
        if (typeof lock.heartbeatAt === "number")
            consider(lock.heartbeatAt);
        try {
            consider(_statSync(path).mtimeMs);
        }
        catch {
            // Unreadable stat — fall back to what the lock itself claims.
        }
        if (typeof lock.startedAt === "string")
            consider(Date.parse(lock.startedAt));
        return seen;
    };
    /**
     * Whether the process that wrote `lock` is still running. A live pid is
     * necessary but not sufficient: a lock recorded before the current boot
     * cannot belong to a live process no matter what now holds its pid, so such a
     * lock is stale and gets broken instead of blocking the run forever.
     *
     * A lock from a DIFFERENT host (a run store on a shared/synced filesystem, or
     * one written before this machine was renamed) cannot be checked that way at
     * all — its pid describes a process we cannot see — so it is trusted only as
     * long as its heartbeat keeps arriving. Once it goes quiet for
     * foreignLockStaleMs the lock is reclaimed and said so out loud, because the
     * alternative is a run its owner can never resume again.
     */
    const lockOwnerIsAlive = (lock, path) => {
        if (lock.host && lock.host !== hostname()) {
            const lastSeen = lockLastSeenAt(lock, path);
            const quietFor = Date.now() - lastSeen;
            if (quietFor <= foreignLockStaleMs)
                return true;
            console.warn(`[workflow-runs] reclaiming the run lock for ${lock.runId}: it was taken by host "${lock.host}" ` +
                `(pid ${lock.pid}) and ${lastSeen > 0
                    ? `has not been refreshed for ${Math.round(quietFor / 60_000)}m`
                    : "carries no credible refresh time"}`);
            return false;
        }
        if (typeof lock.processStartedAt === "number" && Number.isFinite(lock.processStartedAt)) {
            // uptime() is seconds since boot; allow a minute of clock skew/rounding.
            const bootedAt = Date.now() - uptime() * 1000;
            if (lock.processStartedAt < bootedAt - 60_000)
                return false;
        }
        return pidIsAlive(lock.pid);
    };
    const readLockAt = (path) => {
        try {
            return JSON.parse(_readFileSync(path, "utf-8"));
        }
        catch {
            return null;
        }
    };
    const readLock = (runId) => readLockAt(primaryLockPath(runId));
    // Leases this instance currently holds, so their locks can be kept warm (see
    // LockFile.heartbeatAt) — a foreign reader has nothing else to go on.
    const heldLeases = new Map();
    const touchLeaseHeartbeat = (runId) => {
        const held = heldLeases.get(runId);
        if (!held)
            return;
        const now = Date.now();
        if (now - held.touchedAt < LOCK_HEARTBEAT_INTERVAL_MS)
            return;
        held.touchedAt = now;
        const path = primaryLockPath(runId);
        const existing = readLockAt(path);
        // Only ever refresh our OWN lock: if the file now carries someone else's
        // token, this lease has already been superseded and must not be revived.
        if (!existing || existing.token !== held.token)
            return;
        try {
            _writeFileSync(path, JSON.stringify({ ...existing, heartbeatAt: now }, null, 2), { mode: PRIVATE_FILE_MODE });
        }
        catch {
            // Heartbeats are best-effort; a missed one only shortens the window.
        }
    };
    const touchHeldLeases = () => {
        for (const runId of heldLeases.keys())
            touchLeaseHeartbeat(runId);
    };
    /** Whether any live process currently holds this run's lease (either store). */
    const runLeaseIsHeld = (runId) => {
        for (const dir of [runsDir, legacyRunsDir]) {
            const path = lockPath(dir, runId);
            const lock = readLockAt(path);
            if (lock && lockOwnerIsAlive(lock, path))
                return true;
        }
        return false;
    };
    // list() cache: recomputed lazily, invalidated synchronously by every
    // mutation this instance performs (save()/delete()) so a stale read can
    // never outlive a mutation this process made. A read from another process
    // (or a direct fs write bypassing this instance) is picked up once the TTL
    // elapses, same as before this cache existed on the next un-cached call.
    let listCache;
    let listCacheAt = 0;
    const invalidateListCache = () => {
        listCache = undefined;
    };
    // Per-file mtime+size+ino cache, keyed by absolute path: even once the
    // TTL-level listCache above expires (the active panel polls roughly every
    // 300ms, i.e. faster than or comparable to the TTL), most run files on
    // disk haven't changed since the last recompute. Re-stat is cheap; re-read
    // + re-JSON.parse is not, and scales with total lifetime run history, not
    // with what actually changed. A file whose (mtimeMs, size, ino) all match
    // what we last parsed is reused as-is instead of being re-read; entries
    // for files that vanished between recomputes are pruned so this cache
    // can't grow unbounded independent of what's actually on disk.
    //
    // ino is load-bearing, not redundant with mtime+size: save() writes via
    // tmp-write + rename (writeJsonAtomicWithBackup), and a rename onto an
    // existing path allocates a NEW inode for the replacement file. Two
    // consecutive saves landing in the same mtime tick (400ms-throttled
    // progress persists vs. 1-2s mtime granularity on HFS+/many network
    // mounts/some Docker volume drivers is entirely realistic) with
    // coincidentally equal byte length (e.g. "paused" and "failed" are the
    // same length) would otherwise be indistinguishable from "unchanged" by
    // (mtimeMs, size) alone — serving stale, previously-cached content
    // forever until something ELSE about the file changes. The inode always
    // changes on such a rename, so adding it closes that hole for free.
    const fileStateCache = new Map();
    // Paths already reported as unreadable/ill-typed, so a rejected file is
    // announced once instead of on every 300ms poll. Pruned with fileStateCache.
    const reportedInvalid = new Set();
    const reportInvalid = (path, reason) => {
        if (reportedInvalid.has(path))
            return;
        reportedInvalid.add(path);
        console.warn(`[workflow-runs] ignoring ${path}: ${reason}`);
    };
    // A record is tagged with where it was actually read from — the reader's
    // answer, never the file's own claim (see PersistedRunState.sourcePath).
    const readRunFile = (path, store) => {
        const raw = readJsonWithBackupRecovery(fs, path);
        if (raw === null)
            return null;
        const validated = validatePersistedRunState(raw);
        if ("reason" in validated) {
            reportInvalid(path, validated.reason);
            return null;
        }
        reportedInvalid.delete(path);
        return { ...validated.state, sourcePath: path, sourceStore: store };
    };
    const removeStaleLegacyLock = (runId) => {
        const lock = legacyLockPath(runId);
        const existing = readLockAt(lock);
        if (existing?.runId === runId && lockOwnerIsAlive(existing, lock))
            return false;
        try {
            if (_existsSync(lock))
                _unlinkSync(lock);
        }
        catch {
            return false;
        }
        return true;
    };
    const computeList = () => {
        const byRunId = new Map();
        const seenPaths = new Set();
        for (const dir of [runsDir, legacyRunsDir]) {
            const store = dir === runsDir ? "global" : "legacy";
            for (const file of listJsonFilesSafe(fs, dir)) {
                const path = join(dir, file);
                seenPaths.add(path);
                try {
                    const stat = _statSync(path);
                    const cached = fileStateCache.get(path);
                    // Reuse the last parse when the file is byte-identical (same
                    // mtime + size + inode) to what produced it — the dominant case
                    // on every poll tick once a run goes terminal and stops changing.
                    // ino is what actually rules out a false "unchanged" match on a
                    // coarse-mtime filesystem (see the field doc comment above).
                    if (cached && cached.mtimeMs === stat.mtimeMs && cached.size === stat.size && cached.ino === stat.ino) {
                        if (!byRunId.has(cached.state.runId))
                            byRunId.set(cached.state.runId, cached.state);
                        continue;
                    }
                    const state = readRunFile(path, store);
                    if (!state) {
                        fileStateCache.delete(path);
                        continue;
                    }
                    fileStateCache.set(path, { mtimeMs: stat.mtimeMs, size: stat.size, ino: stat.ino, state });
                    if (!byRunId.has(state.runId))
                        byRunId.set(state.runId, state);
                }
                catch {
                    // Skip corrupted/unreadable files; don't let a stale cache entry
                    // for a file that's now failing to read linger either.
                    fileStateCache.delete(path);
                }
            }
        }
        // Prune cache entries for files that no longer exist (deleted runs) so
        // this map's size tracks what's actually on disk, not lifetime history.
        for (const path of fileStateCache.keys()) {
            if (!seenPaths.has(path))
                fileStateCache.delete(path);
        }
        for (const path of reportedInvalid) {
            if (!seenPaths.has(path))
                reportedInvalid.delete(path);
        }
        return [...byRunId.values()].sort((a, b) => new Date(b.updatedAt).getTime() - new Date(a.updatedAt).getTime());
    };
    // Bound the number of terminal (completed/failed/aborted) runs kept on
    // disk (see DEFAULT_MAX_TERMINAL_RUNS_ON_DISK) — called after every save()
    // whose state is terminal, since that's the only time the terminal count
    // can grow. Running/paused runs are never candidates: they're filtered out
    // before the cap is even considered.
    const enforceRetention = () => {
        const terminal = computeList()
            .filter((r) => TERMINAL_RUN_STATUSES.has(r.status))
            .sort((a, b) => new Date(a.updatedAt).getTime() - new Date(b.updatedAt).getTime());
        const excess = terminal.length - maxTerminalRunsOnDisk;
        if (excess <= 0)
            return;
        for (const run of terminal.slice(0, excess)) {
            deleteRunFiles(run.runId);
        }
        invalidateListCache();
    };
    const deleteRunFiles = (runId) => {
        let deleted = false;
        for (const path of candidateRunPaths(runId)) {
            const dir = path === primaryRunPath(runId) ? runsDir : legacyRunsDir;
            // Best-effort cleanup of the sidecar files alongside the primary.
            for (const sidecar of [`${path}.bak`, `${path}.tmp`, lockPath(dir, runId)]) {
                unlinkIfExistsSafe(fs, sidecar);
                fileStateCache.delete(sidecar);
            }
            if (unlinkIfExistsSafe(fs, path))
                deleted = true;
            fileStateCache.delete(path);
        }
        return deleted;
    };
    return {
        save(state, options) {
            if (!isSafeRunId(state.runId))
                throw new Error(`Refusing to persist run with unsafe runId: ${state.runId}`);
            ensureDir();
            // A bookkeeping-only write keeps the timestamp the record already had (see
            // RunPersistence.save); anything else is progress and restamps it.
            if (!options?.preserveUpdatedAt || typeof state.updatedAt !== "string") {
                state.updatedAt = new Date().toISOString();
            }
            const path = primaryRunPath(state.runId);
            // Every write lands in the global store, so a record that came from a
            // project-local store is about to change location. Carry the original
            // path with it (and drop any install ownership) so relocating a run can
            // never launder a project-supplied script into an install-owned,
            // auto-resumable one. The reader-assigned provenance fields are the
            // reader's to set and are not part of the file.
            const { sourcePath, sourceStore, ...record } = state;
            let relocated = record;
            if (sourceStore === "legacy" || record.foreignSource) {
                const { installId: _notOurs, ...rest } = record;
                relocated = { ...rest, foreignSource: record.foreignSource ?? sourcePath ?? "project store" };
            }
            // Atomic write: a crash mid-write can't corrupt the live file (tmp+rename is
            // atomic on the same filesystem). A .bak from the previous good save is the
            // recovery fallback if the primary is somehow truncated.
            writeJsonAtomicWithBackup(fs, path, relocated);
            // Progress on a run this instance leases is also proof the holder is alive
            // — which is all a reader on another host has to go on (see LockFile).
            touchLeaseHeartbeat(state.runId);
            invalidateListCache();
            // Only a terminal write can grow the terminal-run count, so only check
            // the cap then — a "running"/"paused" save is on the hot path (every
            // progress tick) and must not pay for a retention scan.
            if (TERMINAL_RUN_STATUSES.has(state.status))
                enforceRetention();
        },
        load(runId) {
            if (!isSafeRunId(runId))
                return null;
            // Try the primary, then the .bak — so a corrupt primary doesn't lose the run.
            for (const path of candidateRunPaths(runId)) {
                const state = readRunFile(path, path === primaryRunPath(runId) ? "global" : "legacy");
                if (state && state.runId === runId)
                    return state;
            }
            return null;
        },
        list() {
            const now = Date.now();
            // A listing means this process's event loop is alive and still owns
            // whatever leases it holds, so it counts as a heartbeat too — that keeps a
            // long-running-but-quiet agent from looking abandoned to another host.
            touchHeldLeases();
            // Return a fresh array on every call (a cheap ref-copy) so a caller that
            // sorts/reverses/mutates the result in place can't corrupt the cache — the
            // pre-cache code re-parsed into a new array each call, preserve that.
            if (listCache && now - listCacheAt < LIST_CACHE_TTL_MS) {
                return [...listCache];
            }
            const result = computeList();
            listCache = result;
            listCacheAt = now;
            return [...result];
        },
        delete(runId) {
            if (!isSafeRunId(runId))
                return false;
            // `/workflows rm <id>` names a run id, so deletion needs the run to
            // actually be here (no id whose files don't exist gets to unlink
            // sidecars) and to be idle: a run another process is executing right now
            // would otherwise lose its record and lock from under it mid-write.
            if (!candidateRunPaths(runId).some((path) => _existsSync(path)))
                return false;
            if (runLeaseIsHeld(runId)) {
                console.warn(`[workflow-runs] refusing to delete ${runId}: its run lease is currently held`);
                return false;
            }
            try {
                return deleteRunFiles(runId);
            }
            finally {
                invalidateListCache();
            }
        },
        acquireRunLease(runId) {
            if (!isSafeRunId(runId))
                return null;
            ensureDir();
            const path = primaryRunPath(runId);
            const lock = primaryLockPath(runId);
            if (!removeStaleLegacyLock(runId))
                return null;
            for (let attempt = 0; attempt < 2; attempt++) {
                const now = Date.now();
                const token = `${process.pid}-${now.toString(36)}-${Math.random().toString(36).slice(2)}`;
                const payload = {
                    runId,
                    runPath: path,
                    pid: process.pid,
                    startedAt: new Date().toISOString(),
                    token,
                    // Identify the owning process, not just its pid (see LockFile).
                    processStartedAt: Math.round(now - process.uptime() * 1000),
                    host: hostname(),
                    heartbeatAt: now,
                };
                try {
                    _writeFileSync(lock, JSON.stringify(payload, null, 2), { flag: "wx", mode: PRIVATE_FILE_MODE });
                    heldLeases.set(runId, { token, touchedAt: now });
                    return { runId, token };
                }
                catch (err) {
                    const code = err.code;
                    if (code !== "EEXIST")
                        throw err;
                    const existing = readLock(runId);
                    if (existing && existing.runPath === path && lockOwnerIsAlive(existing, lock)) {
                        return null;
                    }
                    try {
                        _unlinkSync(lock);
                    }
                    catch {
                        return null;
                    }
                }
            }
            return null;
        },
        releaseRunLease(lease) {
            const held = heldLeases.get(lease.runId);
            if (held?.token === lease.token)
                heldLeases.delete(lease.runId);
            try {
                const existing = readLock(lease.runId);
                if (existing?.token === lease.token)
                    _unlinkSync(primaryLockPath(lease.runId));
            }
            catch {
                // Best-effort cleanup only.
            }
        },
        getRunsDir() {
            return runsDir;
        },
    };
}
/**
 * Generate a unique run ID.
 */
export function generateRunId() {
    const timestamp = Date.now().toString(36);
    const random = Math.random().toString(36).slice(2, 8);
    return `${timestamp}-${random}`;
}
