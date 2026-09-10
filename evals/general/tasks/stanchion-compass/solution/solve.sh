#!/bin/bash
# Oracle for stanchion-compass. Applies the real solver: route-level code
# splitting via React.lazy in the app shell, and an explicit manualChunks rule
# that separates node_modules vendor code from the entry chunk. Then rebuilds
# to prove the outcome contract (the verifier rebuilds and scores the emitted
# chunk graph plus the running app).
set -eu

cp /solution/solver/App.tsx /app/src/App.tsx
cp /solution/solver/vite.config.ts /app/vite.config.ts

cd /app
npm run build

echo "oracle: lazy route views + vendor manualChunks applied; /app/package.json build green, /app/dist produced"