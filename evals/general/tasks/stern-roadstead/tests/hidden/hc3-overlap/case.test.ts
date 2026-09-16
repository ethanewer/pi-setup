/**
 * Hidden case 3: key precedence and dot neutrality.
 * - A pipe key that shares a prefix with a shorter key must win as a whole
 *   (`$x|y` → the `x|y` column, not `x` plus a literal `|y`), regardless of
 *   property insertion order.
 * - A dotted heading must not wildcard-match a different character: `$akb`
 *   must stay literal text, not match the `a.b` column through the dot-as-
 *   any-character hole.
 */
import each from '../';

const getGlobalTestMocks = (): any => {
  const globals: any = {
    describe: jest.fn(),
    fdescribe: jest.fn(),
    fit: jest.fn(),
    it: jest.fn(),
    test: jest.fn(),
    xdescribe: jest.fn(),
    xit: jest.fn(),
    xtest: jest.fn(),
  };
  globals.test.only = jest.fn();
  globals.test.skip = jest.fn();
  globals.test.concurrent = jest.fn();
  globals.test.concurrent.only = jest.fn();
  globals.test.concurrent.skip = jest.fn();
  globals.it.only = jest.fn();
  globals.it.skip = jest.fn();
  globals.describe.only = jest.fn();
  globals.describe.skip = jest.fn();
  return globals;
};

const noop = () => {};
const mocks = getGlobalTestMocks;

test('a pipe key wins over its own shorter prefix', () => {
  const g = mocks();
  const t = each.withGlobal(g as any)([
    {x: 'ex', 'x|y': 'pipe'},
    {x: 'ex2', 'x|y': 'pipe2'},
  ]).test;
  t('r=$x|y', noop);
  expect(g.test).toHaveBeenCalledTimes(2);
  expect(g.test).toHaveBeenNthCalledWith(
    1,
    'r=pipe',
    expect.any(Function),
    undefined,
  );
  expect(g.test).toHaveBeenNthCalledWith(
    2,
    'r=pipe2',
    expect.any(Function),
    undefined,
  );
});

test('a dotted key does not wildcard-match a different character', () => {
  const g = mocks();
  const t = each.withGlobal(g as any)([{'a.b': 'dot'}]).test;
  t('r=$akb', noop);
  expect(g.test).toHaveBeenCalledTimes(1);
  expect(g.test).toHaveBeenCalledWith(
    'r=$akb',
    expect.any(Function),
    undefined,
  );
});