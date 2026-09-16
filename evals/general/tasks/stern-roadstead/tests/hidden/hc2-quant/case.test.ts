/**
 * Hidden case 2: quantifier-style metacharacters inside a heading.
 * `ab*` would match `$ab` plus a starred `b` (resolving key path a,b into a
 * pretty-printed object), and `d{2}` never matches so `$d{2}` is left
 * literal — the parent interpolates the wrong value or nothing at all. The
 * fixed interpolation escapes both headings and each interpolates its own
 * column's value.
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

test('interpolates the whole heading when it ends in a star', () => {
  const g = mocks();
  const t = each.withGlobal(g as any)([{'ab*': 'star'}]).test;
  t('value $ab*', noop);
  expect(g.test).toHaveBeenCalledTimes(1);
  expect(g.test).toHaveBeenCalledWith(
    'value star',
    expect.any(Function),
    undefined,
  );
});

test('interpolates a heading containing a brace quantifier literally', () => {
  const g = mocks();
  const t = each.withGlobal(g as any)([{'d{2}': 'twenty'}]).test;
  t('v $d{2}', noop);
  expect(g.test).toHaveBeenCalledTimes(1);
  expect(g.test).toHaveBeenCalledWith(
    'v twenty',
    expect.any(Function),
    undefined,
  );
});