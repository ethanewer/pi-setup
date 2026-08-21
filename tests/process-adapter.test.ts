import { describe, expect, test } from "bun:test";
import { findBashCommand } from "../forks/pi-process-monitor-safe/extensions/monitor/adapters.ts";

describe("process adapter shell", () => {
  test("finds a bash executable", () => {
    const bash = findBashCommand();
    expect(bash.length).toBeGreaterThan(0);
    if (process.platform === "win32") {
      expect(bash).not.toBe("bash");
      expect(bash.toLowerCase()).toContain("bash.exe");
      expect(bash.toLowerCase()).toContain("git");
      expect(bash.toLowerCase()).not.toContain("system32");
    } else {
      expect(bash).toBe("bash");
    }
  });
});
