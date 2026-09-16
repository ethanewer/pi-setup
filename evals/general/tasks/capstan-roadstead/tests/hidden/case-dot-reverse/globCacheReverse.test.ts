/**
 * Authored hidden case (capstan-roadstead): same glob, options in the
 * reverse order of the upstream regression test -- first {dot: false},
 * then {dot: true} -- within one process, so only the second call can
 * expose the stale module-level matcher cache.
 */
import micromatch from 'micromatch';
import globsToMatcher from '../globsToMatcher';

it('recompiles a glob with dot:true after it was first used with dot:false', () => {
  const globs = ['*.hid-dot-rev.js'];

  // First call: {dot: false} -- a dotfile must not match.
  expect(globsToMatcher(globs, {dot: false})('.hidden.hid-dot-rev.js')).toBe(
    micromatch(['.hidden.hid-dot-rev.js'], globs, {dot: false}).length > 0,
  );

  // Second call, same glob, {dot: true} -- now the dotfile must match.
  expect(globsToMatcher(globs, {dot: true})('.hidden.hid-dot-rev.js')).toBe(
    micromatch(['.hidden.hid-dot-rev.js'], globs, {dot: true}).length > 0,
  );
});