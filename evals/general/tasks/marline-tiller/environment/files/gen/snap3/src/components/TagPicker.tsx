import { useState } from 'react';

export interface TagOption {
  id: string;
  label: string;
}

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
    const idx = selected.indexOf(id);
    if (idx >= 0) {
      selected.splice(idx, 1);
    } else {
      selected.push(id);
    }
    setState(selected);
    if (onChange) onChange(selected);
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
