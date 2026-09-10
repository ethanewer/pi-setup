#!/bin/bash
# Oracle for stanchion-bell. Installs the remediated components into /app/src
# (the real work: accessible header with skip link and live announcement,
# labelled form fields, textual status states, corrected roles/headings/alt
# text, and main-before-sidebar composition), then proves the fix by running
# the shipped visible check suite. It never looks at the mounted
# verifier fixtures.
set -eu

cp /solution/src/App.jsx /app/src/App.jsx
cp /solution/src/SiteHeader.jsx /app/src/components/SiteHeader.jsx
cp /solution/src/PageMain.jsx /app/src/components/PageMain.jsx
cp /solution/src/Sidebar.jsx /app/src/components/Sidebar.jsx
cp /solution/src/StatusDot.jsx /app/src/components/StatusDot.jsx
cp /solution/src/CardGrid.jsx /app/src/components/CardGrid.jsx
cp /solution/src/BookingForm.jsx /app/src/components/BookingForm.jsx
cp /solution/src/SiteFooter.jsx /app/src/components/SiteFooter.jsx

cd /app
node node_modules/vitest/vitest.mjs run visible

echo "oracle: remediated /app/src and visible suite is GREEN"