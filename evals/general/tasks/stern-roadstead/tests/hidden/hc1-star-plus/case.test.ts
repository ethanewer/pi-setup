/**
 * Hidden case 1: crash-mode metacharacters (leading `*` and `+`).
 * The parent alternation joins the keys verbatim, so a heading starting with
 * `*` or `+` yields a quantifier with nothing to repeat and constructing the
 * table throws SyntaxError before any test can run. The fixed interpolation
 * escapes the keys and both headings interpolate literally.
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

test('interpolates a heading that starts with a star', () => {
  const g = mocks();
  const t = each.withGlobal(g as any)([{'*x': 'starval'}]).test;
  t('star $*x', noop);
  expect(g.test).toHaveBeenCalledTimes(1);
  expect(g.test).toHaveBeenCalledWith(
    'star starval',
    expect.any(Function),
    undefined,
  );
});

test('interpolates a heading that starts with a plus', () => {
  const g = mocks();
  const t = each.withGlobal(g as any)([{'+x': 'plusval'}]).test;
  t('plus $+x', noop);
  expect(g.test).toHaveBeenCalledTimes(1);
  expect(g.test).toHaveBeenCalledWith(
    'plus plusval',
    expect.any(Function),
    undefined,
  );
});