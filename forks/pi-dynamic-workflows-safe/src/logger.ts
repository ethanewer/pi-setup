/**
 * Workflow logger with file persistence.
 */

import { appendFileSync, mkdirSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { PRIVATE_DIR_MODE, PRIVATE_FILE_MODE } from "./fs-persistence.js";
import { isSafeRunId } from "./run-persistence.js";
import { workflowProjectPaths } from "./workflow-paths.js";

export interface WorkflowLogger {
  log(message: string): void;
  error(message: string): void;
  warn(message: string): void;
  getLogs(): string[];
  persist(): string | null;
}

export interface WorkflowLoggerOptions {
  /** Run ID for persistence. */
  runId?: string;
  /** Working directory for file paths. */
  cwd?: string;
  /** Whether to persist logs to disk. */
  persist?: boolean;
  /** Callback for each log entry. */
  onLog?: (message: string) => void;
}

/**
 * File-name-safe form of a run id. Log files are named after the run id, and a
 * run id can arrive from outside (the `workflow` tool's `resumeFromRunId`), so a
 * separator or `..` in one would put this write outside the run store. Kept
 * lossy-but-usable rather than fatal: losing a log must never fail a run.
 */
function logFileId(runId: string): string {
  const cleaned = runId
    .replace(/\.\.+/g, "-")
    .replace(/[^A-Za-z0-9._-]+/g, "-")
    .replace(/^[^A-Za-z0-9]+/, "")
    .slice(0, 200);
  if (isSafeRunId(runId)) return runId;
  return isSafeRunId(cleaned) ? cleaned : "run-unsafe-id";
}

export function createWorkflowLogger(options: WorkflowLoggerOptions = {}): WorkflowLogger {
  const logs: string[] = [];
  const persistLogs = options.persist ?? true;
  const cwd = options.cwd ?? process.cwd();
  const runId = logFileId(options.runId ?? `run-${Date.now()}`);
  const runsDir = workflowProjectPaths(cwd).runsDir;
  let logFile: string | null = null;

  const write = (level: string, message: string) => {
    const timestamp = new Date().toISOString();
    const entry = `[${timestamp}] [${level}] ${message}`;
    logs.push(entry);
    options.onLog?.(message);

    if (persistLogs && logFile) {
      try {
        appendFileSync(logFile, `${entry}\n`, { mode: PRIVATE_FILE_MODE });
      } catch {
        // Silent fail for log persistence
      }
    }
  };

  const logger: WorkflowLogger = {
    log(message: string) {
      write("INFO", message);
    },
    error(message: string) {
      write("ERROR", message);
    },
    warn(message: string) {
      write("WARN", message);
    },
    getLogs() {
      return [...logs];
    },
    persist() {
      if (!persistLogs) return null;
      try {
        mkdirSync(runsDir, { recursive: true, mode: PRIVATE_DIR_MODE });
        logFile = join(runsDir, `${runId}.log`);
        writeFileSync(logFile, `${logs.join("\n")}\n`, { mode: PRIVATE_FILE_MODE });
        return logFile;
      } catch {
        return null;
      }
    },
  };

  // Initialize log file if persisting
  if (persistLogs) {
    try {
      mkdirSync(runsDir, { recursive: true, mode: PRIVATE_DIR_MODE });
      logFile = join(runsDir, `${runId}.log`);
    } catch {
      // Silent fail
    }
  }

  return logger;
}
