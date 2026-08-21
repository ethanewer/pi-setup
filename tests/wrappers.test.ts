import { describe, expect, test } from "bun:test";
import { readFileSync } from "node:fs";
import { join } from "node:path";

const root = join(import.meta.dir, "..");

function parseAllowlist(text: string) {
  const lines = text.split(/\r?\n/).map((line) => line.trim());
  return {
    noExtensions: lines.filter((line) => line === "--no-extensions \\").length,
    noSkills: lines.filter((line) => line === "--no-skills \\").length,
    extensions: lines.flatMap((line) => {
      const match = line.match(/^--extension\s+"([^"]+)"(?:\s+\\)?$/);
      return match ? [match[1]] : [];
    }),
  };
}

describe("lean p wrapper contract", () => {
  const sh = parseAllowlist(readFileSync(join(root, "lib/wrappers/p.sh"), "utf8"));

  test("disables extensions and skills exactly once", () => {
    expect(sh.noExtensions).toBe(1);
    expect(sh.noSkills).toBe(1);
  });

  test("loads only the lean extension allowlist", () => {
    expect(sh.extensions).toEqual([
      "$MAIN_DIR/local/pi-voice-stt-safe/extensions/voice-stt/index.js",
      "$MAIN_DIR/local/pi-context-handoff/extensions/context-handoff/index.js",
      "$MAIN_DIR/local/pi-codex-compaction/extensions/codex-compaction/index.js",
      "$MAIN_DIR/local/pi-btw-side/extensions/btw/index.js",
      "$MAIN_DIR/extensions/mlx/index.js",
      "$MAIN_DIR/p/remove-pi-documentation.js",
    ]);
  });

  test("the Windows cmd shim names the same local packages", () => {
    const cmd = readFileSync(join(root, "lib/wrappers/p.cmd"), "utf8");
    for (const name of [
      "pi-voice-stt-safe",
      "pi-context-handoff",
      "pi-codex-compaction",
      "pi-btw-side",
      "remove-pi-documentation.js",
      "mlx",
    ]) {
      expect(cmd).toContain(name);
    }
    expect(cmd).toContain("--no-extensions");
    expect(cmd).toContain("--no-skills");
    expect(cmd).not.toContain("pi-agent-browser-native-safe");
    expect(cmd).not.toContain("pi-process-monitor-safe");
    expect(cmd).not.toContain("pi-dynamic-workflows-safe");
    expect(cmd).toContain("BUN_INSTALL");
  });
});

describe("compiled extension entries", () => {
  test("TypeScript forks advertise the install-time JS bundle, not the jiti TS entry", () => {
    const vendor = JSON.parse(readFileSync(join(root, "vendor.json"), "utf8"));
    for (const [name, meta] of Object.entries(vendor.forks as Record<string, { live?: unknown }>)) {
      const live = meta.live;
      if (typeof live !== "string" || !live.endsWith(".ts")) continue;
      const pkg = JSON.parse(readFileSync(join(root, "forks", name, "package.json"), "utf8"));
      expect(pkg.pi.extensions).toEqual([`./${live.replace(/\.ts$/i, ".js")}`]);
    }
  });
});

describe("lib/versions.json", () => {
  test("pins Pi and agent-browser", () => {
    const versions = JSON.parse(readFileSync(join(root, "lib/versions.json"), "utf8"));
    expect(versions.pi).toMatch(/^\d+\.\d+\.\d+/);
    expect(versions.agentBrowser).toMatch(/^\d+\.\d+\.\d+/);
  });
});

describe("Windows cmd shims", () => {
  test("every cmd wrapper honors BUN_INSTALL before the default ~/.bun path", () => {
    for (const name of ["pi.cmd", "p.cmd", "piwf.cmd", "agent-browser.cmd", "pi-agent-browser-cli.cmd"]) {
      const body = readFileSync(join(root, "lib/wrappers", name), "utf8");
      const installIdx = body.indexOf("%BUN_INSTALL%\\bin\\bun.exe");
      const homeIdx = body.indexOf("%USERPROFILE%\\.bun\\bin\\bun.exe");
      expect(installIdx).toBeGreaterThan(-1);
      expect(homeIdx).toBeGreaterThan(installIdx);
    }
  });

  test("pi.cmd prefers the compiled Windows binary when it exists", () => {
    const body = readFileSync(join(root, "lib/wrappers/pi.cmd"), "utf8");
    expect(body).toContain("%USERPROFILE%\\.local\\lib\\pi-coding-agent\\pi.exe");
    expect(body).toContain('if /I "%PI_CODING_AGENT_DIR%"=="%USERPROFILE%\\.pi\\agent-p"');
    expect(body).toContain('if /I "%PI_CODING_AGENT_DIR%"=="%USERPROFILE%\\.pi\\agent-wf"');
  });
});
