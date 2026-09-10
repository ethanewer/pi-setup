import { describe, expect, it, vi } from 'vitest';
import { render, screen, fireEvent } from '@testing-library/react';
import { Counter } from '../src/components/Counter';

describe('Counter', () => {
  it('uncontrolled mode steps from defaultValue and reports onChange', () => {
    const onChange = vi.fn();
    const { container } = render(
      <Counter label="Portions" min={0} max={10} step={2} defaultValue={4} onChange={onChange} />,
    );
    expect(container.querySelector('[data-testid="counter-value"]')).toHaveTextContent('4');
    fireEvent.click(container.querySelector('button[aria-label="increment"]'));
    expect(container.querySelector('[data-testid="counter-value"]')).toHaveTextContent('6');
    fireEvent.click(container.querySelector('button[aria-label="decrement"]'));
    expect(container.querySelector('[data-testid="counter-value"]')).toHaveTextContent('4');
    expect(onChange.mock.calls).toEqual([[6], [4]]);
  });

  it('controlled mode renders the clamped prop and does not drift', () => {
    const onChange = vi.fn();
    const props = { label: 'Slices', min: 0, max: 5, step: 3, value: 7, onChange };
    const { container, rerender } = render(<Counter {...props} />);
    expect(container.querySelector('[data-testid="counter-value"]')).toHaveTextContent('5');
    fireEvent.click(container.querySelector('button[aria-label="increment"]'));
    expect(onChange.mock.calls).toEqual([[5]]);
    rerender(<Counter {...props} value={2} />);
    expect(container.querySelector('[data-testid="counter-value"]')).toHaveTextContent('2');
  });

  it('disabled blocks clicks', () => {
    const onChange = vi.fn();
    const { container } = render(
      <Counter defaultValue={3} disabled onChange={onChange} />,
    );
    fireEvent.click(container.querySelector('button[aria-label="increment"]'));
    expect(container.querySelector('[data-testid="counter-value"]')).toHaveTextContent('3');
    expect(onChange).not.toHaveBeenCalled();
  });
});
