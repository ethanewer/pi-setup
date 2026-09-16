import { describe, expect, it, vi } from 'vitest';
import { render, fireEvent } from '@testing-library/react';
import { QuantityInput } from '../src/components/QuantityInput';

const findInput = (c: HTMLElement) => c.querySelector('input');

describe('QuantityInput', () => {
  it('commits typed values on blur and clamps', () => {
    const onChange = vi.fn();
    const { container } = render(
      <QuantityInput label="Qty" min={0} max={9} defaultValue={4} onChange={onChange} />,
    );
    const input = findInput(container);
    expect(input).toHaveValue('4');
    fireEvent.change(input, { target: { value: '7' } });
    fireEvent.blur(input);
    expect(onChange.mock.calls).toEqual([[7]]);
    expect(input).toHaveValue('7');
  });

  it('reverts invalid text without firing onChange', () => {
    const onChange = vi.fn();
    const { container } = render(
      <QuantityInput label="Qty" defaultValue={6} onChange={onChange} />,
    );
    const input = findInput(container);
    fireEvent.change(input, { target: { value: 'abc' } });
    fireEvent.blur(input);
    expect(onChange).not.toHaveBeenCalled();
    expect(input).toHaveValue('6');
  });

  it('arrow keys step by step and clamp at the boundary', () => {
    const onChange = vi.fn();
    const { container } = render(
      <QuantityInput label="Qty" min={0} max={5} defaultValue={4} onChange={onChange} />,
    );
    const input = findInput(container);
    fireEvent.keyDown(input, { key: 'ArrowUp' });
    fireEvent.keyDown(input, { key: 'ArrowUp' });
    expect(onChange.mock.calls).toEqual([[5], [5]]);
    expect(input).toHaveValue('5');
  });
});
