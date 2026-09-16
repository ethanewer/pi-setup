import { useState } from 'react';
import { dedupe } from '../utils/dedupe';

export interface TagOption {
  id: string;
  label: string;
}

/** Chip multi-select in controlled or uncontrolled mode. */
export interface TagPickerProps {
  options: TagOption[];
  value?: string[];
  defaultValue?: string[];
  onChange?: (ids: string[]) => void;
  disabled?: boolean;
  emptyLabel?: string;
}

export function TagPicker({
  options,
  value,
  defaultValue,
  onChange,
  disabled = false,
  emptyLabel = 'Nothing selected',
}: TagPickerProps) {
  const [state, setState] = useState(defaultValue ? [...defaultValue] : []);
  const selected = typeof value !== 'undefined' ? value : state;

  const toggle = (id: string): void => {
    if (disabled) return;
    const next = dedupe(
      selected.includes(id)
        ? selected.filter((x) => x !== id)
        : [...selected, id],
    );
    if (typeof value === 'undefined') setState(next);
    if (onChange) onChange(next);
  };

  return (
    <div role="group" data-testid="tagpicker">
      <span data-testid="tag-summary">
        {selected.length === 0 ? emptyLabel : `${selected.length} selected`}
      </span>
      <ul className="tags">
        {options.map((opt) => {
          const isSel = selected.includes(opt.id);
          return (
            <li key={opt.id}>
              <button
                type="button"
                role="option"
                aria-selected={isSel ? 'true' : 'false'}
                data-tag-id={opt.id}
                className={isSel ? 'selected' : ''}
                disabled={disabled}
                onClick={() => toggle(opt.id)}
              >
                {opt.label}
              </button>
            </li>
          );
        })}
      </ul>
    </div>
  );
}

export default TagPicker;
