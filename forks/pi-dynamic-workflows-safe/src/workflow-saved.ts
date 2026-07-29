/**
 * Save and load reusable workflow commands.
 */

import { join } from "node:path";
import {
  ensureDir as ensureDirFs,
  listJsonFilesSafe,
  type PersistenceFsLayer,
  readJsonWithBackupRecovery,
  resolvePersistenceFs,
  unlinkIfExistsSafe,
  writeJsonAtomicWithBackup,
} from "./fs-persistence.js";
import { workflowProjectPaths, workflowUserSavedDir } from "./workflow-paths.js";
import { loadWorkflowSettings } from "./workflow-settings.js";

export interface SavedWorkflow {
  /** Command name (filename without extension). */
  name: string;
  /** Human-readable description. */
  description: string;
  /** The workflow script. */
  script: string;
  /** Optional parameter schema for parameterized workflows. */
  parameters?: Record<string, { type: string; description?: string; required?: boolean; default?: unknown }>;
  /** Where this workflow is saved. */
  location: "project" | "user";
  /** Full file path. */
  path: string;
  /** When it was saved. */
  savedAt: string;
  /**
   * True when this workflow was read from the project directory itself
   * (`<cwd>/.pi/workflows/saved`) rather than the user's workflow home, i.e. it
   * came with whatever repository is checked out. Assigned by the reader, never
   * taken from the file. Such a workflow stays listable and runnable, but only
   * behind a confirmation that names this `path` (see
   * WorkflowSettings.trustProjectLocalWorkflows).
   */
  repoLocal?: boolean;
  /**
   * Where this script came from when it was not authored in this install —
   * `/workflows save` and the navigator's save action copy the script out of a
   * run record, and that record may itself have come from the project's own run
   * store (see runScriptOrigin). Unlike `repoLocal`, which describes where the
   * saved FILE was read from, this travels WITH the record: landing in the
   * user's own storage is not what makes a repo-supplied script trustworthy, so
   * the command it becomes stays gated on a confirmation naming this origin.
   */
  scriptOrigin?: string;
}

export interface WorkflowStorage {
  /** Save a workflow. */
  save(workflow: Omit<SavedWorkflow, "path" | "savedAt">, location?: "project" | "user"): SavedWorkflow;
  /** Load a workflow by name. */
  load(name: string): SavedWorkflow | null;
  /** List all saved workflows. */
  list(): SavedWorkflow[];
  /** Delete a saved workflow. */
  delete(name: string, location?: "project" | "user"): boolean;
}

export function isSafeSavedWorkflowName(name: string): boolean {
  return (
    name.length > 0 &&
    name.length <= 128 &&
    name.trim() === name &&
    name !== "." &&
    name !== ".." &&
    !/[/\\\0]/.test(name)
  );
}

export function assertSafeSavedWorkflowName(name: string): void {
  if (!isSafeSavedWorkflowName(name)) {
    throw new Error("Saved workflow name must be a non-empty path-safe name without slashes.");
  }
}

export interface WorkflowStorageOptions {
  /**
   * Resolve project-local saved workflows (`<cwd>/.pi/workflows/saved`) by name
   * without asking anyone. Defaults to WorkflowSettings.trustProjectLocalWorkflows
   * for this cwd, which defaults to false.
   */
  trustRepoLocal?: boolean;
}

export function createWorkflowStorage(
  cwd: string,
  fsOverride?: Partial<PersistenceFsLayer>,
  options?: WorkflowStorageOptions,
): WorkflowStorage {
  const fs = resolvePersistenceFs(fsOverride);
  const paths = workflowProjectPaths(cwd);
  const projectDir = paths.savedDir;
  const legacyProjectDir = paths.legacySavedDir;
  const userDir = workflowUserSavedDir();

  const ensureDir = (dir: string) => ensureDirFs(fs, dir);

  const workflowPath = (name: string, location: "project" | "user") => {
    assertSafeSavedWorkflowName(name);
    const dir = location === "project" ? projectDir : userDir;
    return join(dir, `${name}.json`);
  };
  const legacyProjectWorkflowPath = (name: string) => {
    assertSafeSavedWorkflowName(name);
    return join(legacyProjectDir, `${name}.json`);
  };

  // Same atomic-write-with-backup + corrupt-file recovery contract as
  // run-persistence.ts (see fs-persistence.ts) — a saved workflow is a
  // user-authored artifact just as worth protecting from a crash mid-write
  // or a truncated file as a run's resumable state is.
  const loadFromFile = (path: string, location: "project" | "user", repoLocal = false): SavedWorkflow | null => {
    const data = readJsonWithBackupRecovery<Record<string, unknown>>(fs, path);
    if (!data || typeof data !== "object" || !isSafeSavedWorkflowName((data as { name?: string }).name ?? "")) {
      return null;
    }
    if (typeof (data as { script?: unknown }).script !== "string") return null;
    const origin = (data as { scriptOrigin?: unknown }).scriptOrigin;
    return {
      ...(data as Omit<SavedWorkflow, "location" | "path">),
      location,
      path,
      // After the spread: where the file was found is the reader's answer, so a
      // file claiming otherwise cannot present itself as trusted.
      repoLocal,
      // Recorded provenance is carried through, but only as text (it is shown to
      // a human in a confirmation prompt).
      scriptOrigin: typeof origin === "string" ? origin : undefined,
    };
  };

  // Only consulted when a project-local candidate actually exists, and read
  // lazily so flipping the setting takes effect without a restart.
  const repoLocalTrusted = () =>
    options?.trustRepoLocal ?? loadWorkflowSettings({ cwd }).trustProjectLocalWorkflows === true;

  return {
    save(workflow, location = "project") {
      assertSafeSavedWorkflowName(workflow.name);
      const dir = location === "project" ? projectDir : userDir;
      ensureDir(dir);

      const path = workflowPath(workflow.name, location);
      // repoLocal describes where a workflow was READ from, so it is never part
      // of what gets written (both destinations are the user's own storage).
      // scriptOrigin is the opposite: it describes the SCRIPT, so it is written.
      const { repoLocal: _ignored, ...fields } = workflow;
      const saved: SavedWorkflow = {
        ...fields,
        location,
        path,
        savedAt: new Date().toISOString(),
      };

      writeJsonAtomicWithBackup(fs, path, saved);
      return saved;
    },

    load(name: string): SavedWorkflow | null {
      if (!isSafeSavedWorkflowName(name)) return null;
      // Project takes precedence over user
      const projectPath = workflowPath(name, "project");
      const project = loadFromFile(projectPath, "project");
      if (project) return project;

      // A project-local file resolves by name only when the project is trusted:
      // this is the path the `workflow` tool's `name`, a nested
      // `workflow('name')`, and a built-in's shadow check all go through, and
      // none of them can ask a human. Untrusted, it stays visible via list()
      // and runnable through a confirmed slash command.
      const legacyPath = legacyProjectWorkflowPath(name);
      if (fs.existsSync(legacyPath) && repoLocalTrusted()) {
        const legacyProject = loadFromFile(legacyPath, "project", true);
        if (legacyProject) return legacyProject;
      }

      const userPath = workflowPath(name, "user");
      return loadFromFile(userPath, "user");
    },

    list(): SavedWorkflow[] {
      const workflows: SavedWorkflow[] = [];

      const seen = new Set<string>();
      const addDir = (dir: string, location: "project" | "user", repoLocal = false) => {
        // A missing or unreadable directory (not yet created, deleted
        // mid-race, permission-denied) degrades to "no files" here — same
        // guard run-persistence.ts's list() uses — rather than throwing and
        // taking down the whole listing over one bad storage location.
        for (const file of listJsonFilesSafe(fs, dir)) {
          const wf = loadFromFile(join(dir, file), location, repoLocal);
          if (wf && !seen.has(wf.name)) {
            seen.add(wf.name);
            workflows.push(wf);
          }
        }
      };

      // Priority order mirrors load(): project > legacy project > user. Listing
      // is not running, so project-local entries are always included — flagged,
      // so callers can gate them (see SavedWorkflow.repoLocal).
      addDir(projectDir, "project");
      addDir(legacyProjectDir, "project", true);
      addDir(userDir, "user");

      return workflows.sort((a, b) => a.name.localeCompare(b.name));
    },

    delete(name: string, location?: "project" | "user"): boolean {
      if (!isSafeSavedWorkflowName(name)) return false;
      const locations = location ? [location] : (["project", "user"] as const);
      let deleted = false;

      for (const loc of locations) {
        const path = workflowPath(name, loc);
        // Clean up the .bak sidecar too, mirroring run-persistence.ts's delete()
        // (sidecar cleanup does not by itself count as "deleted the workflow").
        unlinkIfExistsSafe(fs, `${path}.bak`);
        if (unlinkIfExistsSafe(fs, path)) {
          deleted = true;
        }
        if (loc === "project") {
          const legacyPath = legacyProjectWorkflowPath(name);
          unlinkIfExistsSafe(fs, `${legacyPath}.bak`);
          if (unlinkIfExistsSafe(fs, legacyPath)) {
            deleted = true;
          }
        }
      }

      return deleted;
    },
  };
}
