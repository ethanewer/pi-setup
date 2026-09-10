const PALETTE = {
  open: '#2e7d32',
  busy: '#b26a00',
  closed: '#b3261e',
};

/**
 * Small coloured dot conveying an availability state.
 */
export default function StatusDot({ state }) {
  const color = PALETTE[state] || '#6b6b6b';
  return <span className="status-dot" data-state={state} style={{ background: color }} />;
}
