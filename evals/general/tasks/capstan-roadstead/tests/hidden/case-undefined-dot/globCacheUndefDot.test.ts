/**
 * Authored hidden case (capstan-roadstead): one glob is seen three times in
 * one process -- with {dot: undefined}, then {dot: false}, then with no
 * options at all. Every call must behave exactly as micromatch would for
 * that call; the upstream regression test only ever makes a single call
 * with {dot: undefined}.
 */
import micromatch from 'micromatch';
import globsToMatcher from '../globsToMatcher';

it('keeps {dot: undefined}, {dot: false} and option-less calls consistent on one glob', () => {
  const globs = ['*.hid-undef.js'];
  const path = '.hidden.hid-undef.js';

  // Explicit {dot: undefined} must behave as the dot default of true.
  expect(globsToMatcher(globs, {dot: undefined})(path)).toBe(
    micromatch([path], globs, {dot: true}).length > 0,
  );

  // Later, explicitly opt out of dot matching on the same glob.
  expect(globsToMatcher(globs, {dot: false})(path)).toBe(
    micromatch([path], globs, {dot: false}).length > 0,
  );

  // And a plain call with no options must still default to dot: true.
  expect(globsToMatcher(globs)(path)).toBe(
    micromatch([path], globs, {dot: true}).length > 0,
  );
});