import { describe, expect, test } from "bun:test";
import { mkdtempSync, readFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import {
  addPowerShellPiCommand,
  bunCandidates,
  findGitBash,
  isUsableWindowsBash,
  posixPath,
  writeExec,
} from "../lib/install.mjs";

describe("posixPath", () => {
  test("converts backslashes so Git Bash wrappers can exec the path", () => {
    expect(posixPath("C:\\Users\\Ethan\\.pi\\agent")).toBe("C:/Users/Ethan/.pi/agent");
  });
});

describe("isUsableWindowsBash", () => {
  test("rejects WSL's System32 bash.exe", () => {
    expect(isUsableWindowsBash("C:\\Windows\\System32\\bash.exe")).toBe(false);
    expect(isUsableWindowsBash("C:/Windows/System32/bash.exe")).toBe(false);
    expect(isUsableWindowsBash("C:\\Windows\\Sysnative\\bash.exe")).toBe(false);
  });

  test("accepts Git for Windows", () => {
    expect(isUsableWindowsBash("C:\\Program Files\\Git\\bin\\bash.exe")).toBe(true);
  });
});

describe("writeExec", () => {
  test("writes CRLF for .cmd and LF otherwise", () => {
    const dir = mkdtempSync(join(tmpdir(), "pi-setup-write-exec-"));
    try {
      const cmd = join(dir, "pi.cmd");
      const sh = join(dir, "pi");
      writeExec(cmd, "@echo off\nexit /b 0\n");
      writeExec(sh, "#!/bin/sh\nexit 0\n");
      expect(readFileSync(cmd, "utf8")).toBe("@echo off\r\nexit /b 0\r\n");
      expect(readFileSync(sh, "utf8")).toBe("#!/bin/sh\nexit 0\n");
    } finally {
      rmSync(dir, { recursive: true, force: true });
    }
  });
});

describe("bunCandidates", () => {
  test("includes bun.exe on Windows", () => {
    const found = bunCandidates(join("C:", "Users", "me", ".bun"));
    if (process.platform === "win32") {
      expect(found.some((p) => p.endsWith("bun.exe"))).toBe(true);
    } else {
      expect(found.every((p) => !p.endsWith("bun.exe"))).toBe(true);
    }
  });
});

describe("findGitBash", () => {
  test("locates Git Bash on this Windows machine and never returns WSL bash", () => {
    const bash = findGitBash();
    if (process.platform !== "win32") {
      expect(bash).toBe("");
      return;
    }
    expect(bash.toLowerCase()).toContain("git");
    expect(bash.toLowerCase()).toContain("bash.exe");
    expect(isUsableWindowsBash(bash)).toBe(true);
  });

  test("honors GIT_BASH when it points at a usable Git Bash", () => {
    if (process.platform !== "win32") return;
    const gitBash = "C:\\Program Files\\Git\\bin\\bash.exe";
    const prevPi = process.env.PI_BASH;
    const prevGit = process.env.GIT_BASH;
    process.env.PI_BASH = "";
    process.env.GIT_BASH = gitBash;
    try {
      expect(findGitBash()).toBe(gitBash);
    } finally {
      if (prevPi === undefined) delete process.env.PI_BASH;
      else process.env.PI_BASH = prevPi;
      if (prevGit === undefined) delete process.env.GIT_BASH;
      else process.env.GIT_BASH = prevGit;
    }
  });

  test("skips GIT_BASH when it is WSL's System32 bash", () => {
    const prevPi = process.env.PI_BASH;
    const prevGit = process.env.GIT_BASH;
    process.env.PI_BASH = "";
    process.env.GIT_BASH = "C:\\Windows\\System32\\bash.exe";
    try {
      const bash = findGitBash();
      expect(bash.toLowerCase()).not.toContain("\\windows\\system32\\bash.exe");
    } finally {
      if (prevPi === undefined) delete process.env.PI_BASH;
      else process.env.PI_BASH = prevPi;
      if (prevGit === undefined) delete process.env.GIT_BASH;
      else process.env.GIT_BASH = prevGit;
    }
  });
});

describe("addPowerShellPiCommand", () => {
  test("clears the lean p profile before launching pi.exe", () => {
    const dir = mkdtempSync(join(tmpdir(), "pi-setup-ps-pi-"));
    try {
      const profile = join(dir, "Microsoft.PowerShell_profile.ps1");
      addPowerShellPiCommand(profile, "C:\\pi.exe", "C:\\pi.cmd");
      const body = readFileSync(profile, "utf8");
      expect(body).toContain("# pi-setup: pi-command");
      expect(body).toContain("# pi-setup: end-pi-command");
      expect(body).toContain("Join-Path $env:USERPROFILE '.pi\\agent-p'");
      expect(body).toContain("Join-Path $env:USERPROFILE '.pi\\agent-wf'");
      expect(body).toContain("Remove-Item Env:PI_CODING_AGENT_DIR, Env:PI_CODING_AGENT_SESSION_DIR, Env:PI_SKIP_VERSION_CHECK");
      expect(body).toContain("C:\\pi.exe");
    } finally {
      rmSync(dir, { recursive: true, force: true });
    }
  });
});
