/**
 * Shared filesystem primitives for JSON-backed persistence.
 *
 * Both run-persistence.ts (workflow runs) and workflow-saved.ts (saved
 * workflow commands) persist plain-JSON records to per-record files under a
 * project/user directory, and both need the same three guarantees:
 *
 *  1. Atomic writes with a recovery backup — a crash mid-write must never
 *     corrupt the live file, and a later-discovered-truncated primary must
 *     still be recoverable from the last good write.
 *  2. Corrupt-file recovery on read — a truncated/corrupt primary falls back
 *     to its `.bak` sidecar instead of losing the record.
 *  3. A missing or unreadable directory degrades to "no files" rather than
 *     throwing — a listing must never crash because one storage location is
 *     temporarily inaccessible (not yet created, deleted mid-race, EACCES).
 *  4. Owner-only permissions. A run record holds the workflow script, every
 *     agent prompt and every agent result verbatim, and a saved workflow holds
 *     a script — none of it is redacted, so on a shared machine the file mode
 *     is the whole protection. Directories are created 0700 and files 0600.
 *
 * This module is the single implementation of all four; run-persistence.ts
 * and workflow-saved.ts both call into it rather than maintaining parallel
 * copies.
 */
import { existsSync, mkdirSync, readdirSync, readFileSync, renameSync, statSync, unlinkSync, writeFileSync, } from "node:fs";
/** The real node:fs implementations. */
export function defaultPersistenceFs() {
    return { existsSync, mkdirSync, readdirSync, readFileSync, renameSync, statSync, unlinkSync, writeFileSync };
}
/** Merge a partial test override on top of the real node:fs implementations. */
export function resolvePersistenceFs(overrides) {
    const base = defaultPersistenceFs();
    return overrides ? { ...base, ...overrides } : base;
}
/** Owner-only directory mode for every store this module creates. */
export const PRIVATE_DIR_MODE = 0o700;
/** Owner-only file mode for every record this module writes. */
export const PRIVATE_FILE_MODE = 0o600;
/**
 * Ensure `dir` exists (recursive mkdir, owner-only), idempotent. A directory
 * that already exists is left alone — its mode is the user's to choose once it
 * is there; only what this module creates is forced to 0700.
 */
export function ensureDir(fs, dir) {
    if (!fs.existsSync(dir))
        fs.mkdirSync(dir, { recursive: true, mode: PRIVATE_DIR_MODE });
}
/**
 * Atomically write JSON to `path`: tmp-write + rename (atomic on the same
 * filesystem, so a crash mid-write can't corrupt the live file), then
 * best-effort refresh a `.bak` sidecar from the just-written good state —
 * the recovery fallback readJsonWithBackupRecovery() uses if the primary is
 * later found truncated (e.g. a rename that itself got interrupted by a
 * power loss on a filesystem/OS combination where rename isn't fully atomic).
 */
export function writeJsonAtomicWithBackup(fs, path, data) {
    const json = JSON.stringify(data, null, 2);
    // mode applies on creation, and the tmp file is always created fresh, so the
    // renamed-into-place record carries 0600 even when the destination existed.
    fs.writeFileSync(`${path}.tmp`, json, { mode: PRIVATE_FILE_MODE });
    fs.renameSync(`${path}.tmp`, path);
    try {
        fs.writeFileSync(`${path}.bak`, json, { mode: PRIVATE_FILE_MODE });
    }
    catch {
        // Backup is best-effort; the primary write already succeeded.
    }
}
/**
 * Read JSON from `path`, falling back to `path.bak` if the primary is
 * missing or fails to parse. Returns null if neither candidate parses.
 */
export function readJsonWithBackupRecovery(fs, path) {
    for (const candidate of [path, `${path}.bak`]) {
        try {
            if (!fs.existsSync(candidate))
                continue;
            return JSON.parse(fs.readFileSync(candidate, "utf-8"));
        }
        catch {
            // Corrupt candidate -> fall through to the next candidate.
        }
    }
    return null;
}
/**
 * List `.json` record files in `dir`. A missing directory (never created
 * yet) or an unreadable one (deleted between the existsSync check and
 * readdirSync, permission-denied, etc.) both degrade to an empty list
 * rather than throwing — callers (run listings, saved-workflow listings)
 * must never crash a navigator/listing because one storage location is
 * temporarily inaccessible.
 */
export function listJsonFilesSafe(fs, dir) {
    try {
        if (!fs.existsSync(dir))
            return [];
        return fs.readdirSync(dir).filter((f) => f.endsWith(".json"));
    }
    catch {
        return [];
    }
}
/** Best-effort unlink; ignores missing-file/permission errors, reports whether it deleted anything. */
export function unlinkIfExistsSafe(fs, path) {
    try {
        if (fs.existsSync(path)) {
            fs.unlinkSync(path);
            return true;
        }
    }
    catch {
        // ignore
    }
    return false;
}
