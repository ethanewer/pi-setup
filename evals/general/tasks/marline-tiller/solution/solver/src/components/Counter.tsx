import { useState } from 'react';
import { clamp } from '../utils/clamp';

/** A stepper that supports both controlled (`value`) and uncontrolled
 * (`defaultValue`) value modes. */
export interface CounterProps {
  label?: string;
  min?: number;
  max?: number;
  step?: number;
  /** Controlled mode: when a number is supplied the component never holds
   * its own value; it renders the clamped prop and reports every change
   * through `onChange`. */
  value?: number;
  /** Uncontrolled mode: starting value of the internal state. */
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
  const isControlled = typeof value === 'number';
  const [state, setState] = useState(
    typeof defaultValue === 'number' ? defaultValue : 0,
  );
  const current = isControlled ? clamp(value, min, max) : clamp(state, min, max);

  const stepBy = (dir: 1 | -1): void => {
    if (disabled) return;
    const next = clamp(current + dir * step, min, max);
    if (!isControlled) setState(next);
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
