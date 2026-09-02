#!/bin/bash
# Oracle for tundra-quill: write the pure-JS pilot module (the actual work).
# Never reads /tests.
set -eu

PILOT="/app/pilot.js"

cat > "$PILOT" <<'JS'
function step(cell) {
    if (cell === null || typeof cell !== "object" || Array.isArray(cell)) return "hold";
    var grid = cell.grid;
    if (!Array.isArray(grid)) return "hold";
    var row = cell.row;
    var col = cell.col;
    if (typeof row !== "number" || typeof col !== "number") return "hold";
    if (!Number.isInteger(row) || !Number.isInteger(col)) return "hold";
    var battery = cell.battery;
    if (typeof battery === "number" && battery <= 0) return "hold";
    var rows = grid.length;
    if (row < 0 || row >= rows) return "hold";
    var curRow = grid[row];
    if (!Array.isArray(curRow)) return "hold";
    var cols = curRow.length;
    if (col < 0 || col >= cols) return "hold";
    var cur = grid[row][col];
    if (cur === null || typeof cur !== "object") return "hold";

    var dirs = [
        ["north", row - 1, col],
        ["south", row + 1, col],
        ["east", row, col + 1],
        ["west", row, col - 1]
    ];
    var best = null;
    for (var i = 0; i < dirs.length; i++) {
        var r = dirs[i][1];
        var c = dirs[i][2];
        if (r < 0 || r >= rows) continue;
        var nbRow = grid[r];
        if (!Array.isArray(nbRow)) continue;
        if (c < 0 || c >= nbRow.length) continue;
        var nb = nbRow[c];
        if (nb === null || typeof nb !== "object" || Array.isArray(nb)) continue;
        if (nb.blocked === true) continue;
        var cost = (typeof nb.cost === "number" && isFinite(nb.cost)) ? nb.cost : 0;
        if (best === null || cost < best.cost) {
            best = { name: dirs[i][0], cost: cost };
        }
    }
    return best === null ? "hold" : best.name;
}

module.exports = { step: step };
JS

chmod +x "$PILOT"

echo "solve.sh done -> $PILOT"
ls -l "$PILOT"
node -e "var m=require('/app/pilot.js'); console.log(typeof m.step, m.step({grid:[[{cost:0},{cost:0},{cost:0}]],row:0,col:1}));"
