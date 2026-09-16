#!/usr/bin/env node
// Escape-hatch scanner for the cistern strictness migration.
//
// Usage: node /tests/scan_escapes.mjs <REPO> <dir> [<dir> ...]
//
// Fails (exit 1) when any TypeScript file under the analysed directories
// contains one of the banned migration shortcuts:
//   * the `any` type (AST keyword, so comments/strings cannot trigger it),
//   * a cast through `any` (`x as any`),
//   * a cast through or to `unknown` (`as unknown`, `as unknown as T`),
//   * a `@ts-ignore`, `@ts-nocheck` or `@ts-expect-error` comment.
// Prints the offending file and line for each hit, then exits 1.

"use strict";

const fs = require("fs");
const path = require("path");

const repo = process.argv[2];
const dirs = process.argv.slice(3);
if (dirs.length === 0 || !fs.existsSync(path.join(repo, "node_modules", "typescript"))) {
  console.error("usage: scan_escapes.cjs <REPO> <dir>...");
  process.exit(2);
}

const ts = require(path.join(repo, "node_modules", "typescript"));

const TS_COMMENT = /@ts-(ignore|nocheck|expect-error)\b/;

function walk(node, file, report, srcText) {
  if (node === undefined || node === null) {
    return;
  }
  const kind = node.kind;
  if (kind === ts.SyntaxKind.AnyKeyword) {
    const pos = node.getStart ? node.getStart() : node.pos;
    report.push(`${file}:${lineOf(srcText, pos)}: use of the 'any' type`);
  }
  if (kind === ts.SyntaxKind.AsExpression) {
    const target = node.type;
    if (target !== undefined && (target.kind === ts.SyntaxKind.AnyKeyword
        || target.kind === ts.SyntaxKind.UnknownKeyword)) {
      const pos = node.getStart ? node.getStart() : node.pos;
      report.push(`${file}:${lineOf(srcText, pos)}: cast through any/unknown`);
    }
  }
  ts.forEachChild(node, (child) => walk(child, file, report, srcText));
}

function lineOf(text, pos) {
  let line = 1;
  for (let i = 0; i < pos && i < text.length; i += 1) {
    if (text.charCodeAt(i) === 10) {
      line += 1;
    }
  }
  return line;
}

let bad = 0;
for (const dir of dirs) {
  if (!fs.existsSync(dir)) {
    continue;
  }
  const stack = [dir];
  while (stack.length > 0) {
    const current = stack.pop();
    for (const name of fs.readdirSync(current)) {
      if (name === "node_modules" || name === ".git") {
        continue;
      }
      const full = path.join(current, name);
      const stat = fs.lstatSync(full);
      if (stat.isDirectory()) {
        stack.push(full);
        continue;
      }
      if (!name.endsWith(".ts") && !name.endsWith(".tsx")) {
        continue;
      }
      const text = fs.readFileSync(full, "utf8");
      if (TS_COMMENT.test(text)) {
        console.error(`${full}: @ts- escape comment present`);
        bad += 1;
        continue;
      }
      const file = ts.createSourceFile(full, text, ts.ScriptTarget.ES2022, /* setParentNodes */ true);
      const report = [];
      ts.forEachChild(file, (child) => walk(child, full, report, text));
      for (const hit of report) {
        console.error(`escape: ${hit}`);
        bad += 1;
      }
    }
  }
}

if (bad > 0) {
  console.error(`scan found ${bad} banned escape hatch(es)`);
  process.exit(1);
}
console.log("escape-hatch scan clean");
process.exit(0);