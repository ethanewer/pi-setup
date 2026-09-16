const PALETTE = {
  open: '#2e7d32',
  busy: '#b26a00',
  closed: '#b3261e',
};

/**
 * Availability dot. Colour plus a screen-reader-visible text label; the
 * state is never conveyed by colour alone.
 */
export default function StatusDot({ state, stateLabel }) {
  const color = PALETTE[state] || '#6b6b6b';
  return (
    <span
      className="status-dot"
      data-state={state}
      style={{ background: color }}
    >
      <span className="sr-only">{stateLabel}</span>
    </span>
  );
}
