import { describe, expect, it, vi } from 'vitest';
import { render, fireEvent } from '@testing-library/react';
import { TagPicker } from '../src/components/TagPicker';

const OPTS = [
  { id: 'a', label: 'Alpha' },
  { id: 'b', label: 'Beta' },
  { id: 'c', label: 'Gamma' },
];

describe('TagPicker', () => {
  it('toggles chips in uncontrolled mode', () => {
    const onChange = vi.fn();
    const { container } = render(
      <TagPicker options={OPTS} defaultValue={['a']} onChange={onChange} />,
    );
    expect(container.querySelector('[data-testid="tag-summary"]')).toHaveTextContent('1 selected');
    fireEvent.click(container.querySelector('button[data-tag-id="b"]'));
    expect(container.querySelector('[data-testid="tag-summary"]')).toHaveTextContent('2 selected');
    fireEvent.click(container.querySelector('button[data-tag-id="a"]'));
    expect(container.querySelector('[data-testid="tag-summary"]')).toHaveTextContent('1 selected');
    expect(onChange.mock.calls.map((c) => c[0])).toEqual([['a', 'b'], ['b']]);
  });

  it('controlled mode never mutates the value prop and reports fresh arrays', () => {
    const onChange = vi.fn();
    const value = ['a'];
    const { container } = render(
      <TagPicker options={OPTS} value={value} onChange={onChange} />,
    );
    fireEvent.click(container.querySelector('button[data-tag-id="b"]'));
    expect(onChange).toHaveBeenCalledTimes(1);
    const reported = onChange.mock.calls[0][0];
    expect(reported).toEqual(['a', 'b']);
    expect(reported).not.toBe(value);
    expect(value).toEqual(['a']);
  });

  it('disabled picker ignores clicks', () => {
    const onChange = vi.fn();
    const { container } = render(
      <TagPicker options={OPTS} defaultValue={['a']} disabled onChange={onChange} />,
    );
    fireEvent.click(container.querySelector('button[data-tag-id="b"]'));
    expect(container.querySelector('[data-testid="tag-summary"]')).toHaveTextContent('1 selected');
    expect(onChange).not.toHaveBeenCalled();
  });
});
