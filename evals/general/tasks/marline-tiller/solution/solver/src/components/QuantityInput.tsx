import { useState } from 'react';
import { clamp } from '../utils/clamp';

/** A numeric text input with up/down stepping, in controlled or
 * uncontrolled mode. Commits on Enter or blur. */
export interface QuantityInputProps {
  label?: string;
  min?: number;
  max?: number;
  step?: number;
  value?: number;
  defaultValue?: number;
  onChange?: (next: number) => void;
  disabled?: boolean;
}

export function QuantityInput({
  label,
  min = 0,
  max = 100,
  step = 1,
  value,
  defaultValue,
  onChange,
  disabled = false,
}: QuantityInputProps) {
  const isControlled = typeof value === 'number';
  const [state, setState] = useState(
    typeof defaultValue === 'number' ? defaultValue : 0,
  );
  const [draft, setDraft] = useState<string | null>(null);
  const current = isControlled ? clamp(value, min, max) : clamp(state, min, max);
  const text = draft ?? String(current);

  const commit = (): void => {
    if (disabled) return;
    const raw = draft ?? String(current);
    const parsed = Number(raw);
    if (!Number.isFinite(parsed)) {
      // invalid draft: revert to the last valid value, fire nothing
      setDraft(null);
      return;
    }
    const next = clamp(parsed, min, max);
    setDraft(null);
    if (!isControlled) setState(next);
    if (onChange) onChange(next);
  };

  const nudge = (dir: 1 | -1): void => {
    if (disabled) return;
    const next = clamp(current + dir * step, min, max);
    setDraft(null);
    if (!isControlled) setState(next);
    if (onChange) onChange(next);
  };

  return (
    <span className="qty">
      <input
        type="text"
        inputMode="numeric"
        aria-label={label}
        disabled={disabled}
        value={text}
        onChange={(e) => setDraft(e.target.value)}
        onKeyDown={(e) => {
          if (e.key === 'ArrowUp') {
            e.preventDefault();
            nudge(1);
          } else if (e.key === 'ArrowDown') {
            e.preventDefault();
            nudge(-1);
          } else if (e.key === 'Enter') {
            e.preventDefault();
            commit();
          }
        }}
        onBlur={commit}
      />
    </span>
  );
}

export default QuantityInput;
