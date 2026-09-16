/**
 * Authored hidden case (capstan-roadstead): the same glob is compiled
 * twice with opposite nocase values in one process and on paths whose case
 * differs from the glob, so honoring the per-call option is observable.
 * The upstream regression test uses nocase on a path whose letters match
 * the glob's own case; these inputs deliberately use the opposite case.
 */
import micromatch from 'micromatch';
import globsToMatcher from '../globsToMatcher';

it('applies nocase per call on the same uppercase glob', () => {
  const globs = ['*.HID-NOCASE.JS'];
  const path = 'some.hid-nocase.js';

  // nocase:true first (matches the lower-cased path), then nocase:false.
  expect(globsToMatcher(globs, {nocase: true})(path)).toBe(
    micromatch([path], globs, {nocase: true}).length > 0,
  );
  expect(globsToMatcher(globs, {nocase: false})(path)).toBe(
    micromatch([path], globs, {nocase: false}).length > 0,
  );
});

it('applies nocase per call on the same lowercase glob', () => {
  const globs = ['*.hid-nocase2.js'];
  const path = 'some.HID-NOCASE2.JS';

  expect(globsToMatcher(globs, {nocase: false})(path)).toBe(
    micromatch([path], globs, {nocase: false}).length > 0,
  );
  expect(globsToMatcher(globs, {nocase: true})(path)).toBe(
    micromatch([path], globs, {nocase: true}).length > 0,
  );
});