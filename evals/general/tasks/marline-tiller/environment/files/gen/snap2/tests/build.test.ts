import { describe, expect, it } from 'vitest';
import { execFileSync } from 'node:child_process';
import { existsSync, readdirSync, readFileSync } from 'node:fs';

const REPO = process.cwd();

describe('library build contract', () => {
  it('npm run build exits 0', () => {
    execFileSync('npm', ['run', 'build'], { cwd: REPO, timeout: 600000 });
  });

  it('dist contains the ESM artifact marline-lib.mjs', () => {
    const p = `${REPO}/dist/marline-lib.mjs`;
    expect(existsSync(p)).toBe(true);
    const src = readFileSync(p, 'utf8');
    expect(src).toMatch(/\bexport\b/);
    expect(src).not.toMatch(/module\.exports/);
  });

  it('dist contains type declarations for every exported component', () => {
    const indexDts = `${REPO}/dist/index.d.ts`;
    expect(existsSync(indexDts)).toBe(true);
    const decl = readFileSync(indexDts, 'utf8');
    for (const name of ['Counter', 'QuantityInput', 'TagPicker']) {
      expect(decl).toContain(name);
    }

    const walk = (dir: string): string[] =>
      readdirSync(dir, { withFileTypes: true }).flatMap((de) =>
        de.isDirectory() ? walk(`${dir}/${de.name}`) :
        de.name.endsWith('.d.ts') ? [`${dir}/${de.name}`] : []);
    const dtsFiles = walk(`${REPO}/dist`);
    expect(dtsFiles.length).toBeGreaterThan(3);

  });
});
