import { useState } from 'react';
import { clamp } from '../utils/clamp';

export interface CounterProps {
  label?: string;
  min?: number;
  max?: number;
  step?: number;
  value?: number;
  defaultValue?: number;
  onChange?: (next: number) => void;
  disabled?: boolean;
}

export function Counter({
  label,
  min = 0,
  max = 100,
  step = 1,
  value,
  defaultValue,
  onChange,
  disabled = false,
}: CounterProps) {
  // Cavity state manager: the component keeps its own copy of the count and
  // never consults the controlled `value` prop once mounted.
  const [state, setState] = useState(
    typeof defaultValue === 'number'
      ? defaultValue
      : typeof value === 'number' ? value : 0,
  );
  const current = state;

  const stepBy = (dir: 1 | -1): void => {
    if (disabled) return;
    const next = clamp(current + dir * step, min, max);
    setState(next);
    if (onChange) onChange(next);
  };

  return (
    <div role="group" aria-label={label}>
      <button type="button" aria-label="decrement" disabled={disabled} onClick={() => stepBy(-1)}>
        −
      </button>
      <output data-testid="counter-value" aria-live="polite">{String(current)}</output>
      <button type="button" aria-label="increment" disabled={disabled} onClick={() => stepBy(1)}>
        +
      </button>
    </div>
  );
}

export default Counter;
