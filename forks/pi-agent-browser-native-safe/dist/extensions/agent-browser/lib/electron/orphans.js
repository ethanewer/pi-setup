/**
 * Purpose: Reap wrapper-owned Electron launches whose pi process died before its shutdown hook could clean them up.
 * Responsibilities: Read launch adoption records left inside abandoned temp profile directories and route them through the normal verified cleanup path.
 * Scope: Host-side orphan recovery only; live-session status and cleanup stay in cleanup.js and the electron-host orchestration.
 * Usage: Called once per session start by the extension entrypoint; failures are reported, never thrown.
 * Invariants/Assumptions: Only records under a temp root whose owner process is provably gone are adopted, launches still visible in the restored branch stay untouched, and every signal keeps the command-line verification in cleanup.js.
 */
import { readFile } from "node:fs/promises";
import { join } from "node:path";
import { cleanupElectronLaunchResources } from "./cleanup.js";
import { ELECTRON_LAUNCH_ADOPTION_FILE_NAME, ELECTRON_LAUNCH_RECORD_VERSION, ELECTRON_PROFILE_DIR_PREFIX } from "./launch.js";
import { isRecord } from "../parsing.js";
import { listAbandonedSecureTempChildDirectories } from "../temp.js";
export const ORPHAN_ADOPTION_DISABLED_ENV = "PI_AGENT_BROWSER_SKIP_ORPHAN_ELECTRON_ADOPTION";
const MAX_ADOPTED_ORPHAN_LAUNCHES = 8;
const ORPHAN_ADOPTION_DEFAULT_TIMEOUT_MS = 5_000;
function isTruthyEnvValue(value) {
    const normalized = value?.trim().toLowerCase();
    return normalized === "1" || normalized === "true" || normalized === "yes";
}
/** @param {NodeJS.ProcessEnv} [env] */
export function isOrphanElectronAdoptionEnabled(env = process.env) {
    return !isTruthyEnvValue(env[ORPHAN_ADOPTION_DISABLED_ENV]);
}
function parseAdoptionRecord(value, userDataDir) {
    if (!isRecord(value) || value.version !== ELECTRON_LAUNCH_RECORD_VERSION || value.launchedByWrapper !== true)
        return undefined;
    if (typeof value.launchId !== "string" || value.launchId.length === 0)
        return undefined;
    if (value.userDataDir !== userDataDir)
        return undefined;
    if (typeof value.pid !== "number" || !Number.isSafeInteger(value.pid) || value.pid <= 0)
        return undefined;
    return {
        ...value,
        cleanupState: "active",
        port: typeof value.port === "number" && Number.isSafeInteger(value.port) && value.port > 0 ? value.port : 0,
        processGroupId: typeof value.processGroupId === "number" && Number.isSafeInteger(value.processGroupId) && value.processGroupId > 0
            ? value.processGroupId
            : undefined,
    };
}
async function readAdoptionRecord(userDataDir) {
    try {
        return parseAdoptionRecord(JSON.parse(await readFile(join(userDataDir, ELECTRON_LAUNCH_ADOPTION_FILE_NAME), "utf8")), userDataDir);
    }
    catch {
        return undefined;
    }
}
/**
 * @param {{ env?: NodeJS.ProcessEnv; preserveLaunchIds?: ReadonlySet<string>; timeoutMs?: number }} [options]
 */
export async function adoptOrphanedElectronLaunches(options = {}) {
    const env = options.env ?? process.env;
    if (!isOrphanElectronAdoptionEnabled(env))
        return { adopted: [], skippedCount: 0 };
    const timeoutMs = Number.isSafeInteger(options.timeoutMs) && (options.timeoutMs ?? 0) > 0
        ? options.timeoutMs
        : ORPHAN_ADOPTION_DEFAULT_TIMEOUT_MS;
    let profileDirs;
    try {
        profileDirs = await listAbandonedSecureTempChildDirectories(ELECTRON_PROFILE_DIR_PREFIX);
    }
    catch {
        return { adopted: [], skippedCount: 0 };
    }
    const adopted = [];
    let skippedCount = 0;
    for (const userDataDir of profileDirs) {
        if (adopted.length >= MAX_ADOPTED_ORPHAN_LAUNCHES) {
            skippedCount += 1;
            continue;
        }
        const record = await readAdoptionRecord(userDataDir);
        if (!record || options.preserveLaunchIds?.has(record.launchId)) {
            skippedCount += 1;
            continue;
        }
        try {
            adopted.push(await cleanupElectronLaunchResources({ record, timeoutMs }));
        }
        catch {
            skippedCount += 1;
        }
    }
    return { adopted, skippedCount };
}
