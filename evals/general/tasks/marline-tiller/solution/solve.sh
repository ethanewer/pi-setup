#!/bin/bash
# Oracle for marline-tiller. Applies the corrected component implementations
# and packaging config, then PROVES the shared outcome contract by running the
# repository's own build and test suite. This is the real solver: the fixed
# sources contain the state-manager and controlled/uncontrolled logic fixes,
# and the fixed configs make the lib mode emit ESM plus declarations.
set -eu

cp /solution/solver/src/components/Counter.tsx       /app/src/components/Counter.tsx
cp /solution/solver/src/components/QuantityInput.tsx /app/src/components/QuantityInput.tsx
cp /solution/solver/src/components/TagPicker.tsx     /app/src/components/TagPicker.tsx
cp /solution/solver/vite.config.ts                   /app/vite.config.ts
cp /solution/solver/tsconfig.build.json              /app/tsconfig.build.json

cd /app
npm run build
npm test

echo "oracle: /app/package.json build scripts and /app/dist produced by a green suite"
