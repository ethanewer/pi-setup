#!/usr/bin/env bash
# Oracle for gale-bridge. Author the Gale spectral-analysis dev-tooling harness.
set -euo pipefail

# ---------------------------------------------------------------------------
# 1) Skeleton analysis notebook (markdown + plotting code cell)
# ---------------------------------------------------------------------------
python3 - <<'PY'
import json
nb = {
    "cells": [
        {
            "cell_type": "markdown",
            "metadata": {},
            "source": [
                "# Gale spectral workbook\n\n",
                "Notes on ranking the strongest **spectral** frames of wind-gust recordings.\n",
                "This page documents the peak-ranking toy pipeline."
            ]
        },
        {
            "cell_type": "code",
            "execution_count": None,
            "metadata": {},
            "outputs": [],
            "source": [
                "import matplotlib\n",
                "matplotlib.use('Agg')\n",
                "import matplotlib.pyplot as plt\n",
                "x = list(range(10))\n",
                "y = [i * i for i in x]\n",
                "plt.plot(x, y)\n",
                "plt.title('gust spectrum study')\n",
                "plt.savefig('/tmp/spectral_plot.png')\n",
                "print('plot done')"
            ]
        }
    ],
    "metadata": {
        "kernelspec": {
            "display_name": "Python 3",
            "language": "python",
            "name": "python3"
        },
        "language_info": {
            "name": "python",
            "version": "3.12"
        }
    },
    "nbformat": 4,
    "nbformat_minor": 5
}
with open("/app/workbook.ipynb", "w") as fh:
    json.dump(nb, fh, indent=1)
print("workbook written")
PY

# ---------------------------------------------------------------------------
# 2) Vim plugin inspecting the active session window layout
# ---------------------------------------------------------------------------
cat > /app/plugin.vim <<'VIM'
" Gale window-layout inspector plugin.
" Provides :GaleLayout <outfile> which writes the current window layout report.
if exists('g:gale_layout_loaded')
  finish
endif
let g:gale_layout_loaded = 1

function! s:DescribeWindow(win) abort
  return printf('window=%d:rows=%d:cols=%d', a:win, winheight(a:win), winwidth(a:win))
endfunction

function! s:LayoutLines() abort
  let l:lines = ['windows=' . winnr('$')]
  let l:i = 1
  while l:i <= winnr('$')
    call add(l:lines, s:DescribeWindow(l:i))
    let l:i += 1
  endwhile
  return l:lines
endfunction

function! GaleLayoutReport(outfile) abort
  let l:lines = s:LayoutLines()
  call writefile(l:lines, a:outfile)
  echohl Comment
  echomsg join(l:lines, ' | ')
  echohl None
endfunction

command! -nargs=1 -bang GaleReport call GaleLayoutReport(<f-args>)
VIM

# ---------------------------------------------------------------------------
# 3) gawk top-k peak ranking across frames
# ---------------------------------------------------------------------------
cat > /app/topk.awk <<'AWK'
BEGIN {
    FS = ","
    if (k == "") k = 3
    PROCINFO["sorted_in"] = "@ind_num_asc"
}
FNR == 1 { next }
NF < 3 { next }              # tolerate blank / short (malformed) rows
{
    frame = $1 + 0
    bin   = $2 + 0
    mag   = $3 + 0
    mags[frame] = mags[frame] sprintf("%d,%d\n", bin, mag)
}
END {
    print "frame,bin,magnitude,rank"
    for (frame in mags) {
        delete b_arr; delete m_val; delete used
        nf = 0
        n = split(mags[frame], rows, "\n")
        for (i = 1; i <= n; i++) {
            if (rows[i] == "") continue
            split(rows[i], f, ",")
            b_arr[++nf] = f[1] + 0
            m_val[nf]   = f[2] + 0
        }
        limit = (nf < k) ? nf : k
        if (limit <= 0) continue
        for (pass = 1; pass <= limit; pass++) {
            best = -900000; bestbin = 2000000000; besti = -1
            for (i = 1; i <= nf; i++) {
                if (b_arr[i] < 0) continue
                if (m_val[i] > best ||
                    (m_val[i] == best && b_arr[i] < bestbin)) {
                    best = m_val[i]; bestbin = b_arr[i]; besti = i
                }
            }
            b_arr[besti] = -1          # mark chosen (bin id >= 0 always)
            printf "%d,%d,%d,%d\n", frame, bestbin, best, pass
        }
    }
}
AWK

# ---------------------------------------------------------------------------
# 4) jq filter pipeline
# ---------------------------------------------------------------------------
cat > /app/filter.jq <<'JQ'
[ .[]
  | select(.status == "ok")
  | { id: .id,
      hue: .colour,
      day: (.timestamp | split("T")[0]),
      tagcount: (.tags | length),
      firsttag: .tags[0] }
] | sort_by(.day, .id)
JQ

# ---------------------------------------------------------------------------
# 5) Orchestrator shell pipeline (full python stage vs awk-only subset mode)
# ---------------------------------------------------------------------------
cat > /app/pipeline.sh <<'SH'
#!/usr/bin/env bash
# Gale spectral pipeline orchestrator.
#   pipeline.sh full <outdir>              synthesis+STFT (python) -> peaks.csv
#   pipeline.sh subset <magcsv> <out>      awk-only peak ranking from a magnitude CSV
set -euo pipefail

K="${TOPK_K:-3}"
MODE="${1:-}"

case "$MODE" in
  full)
    OUT="${2:?full mode needs OUTDIR}"
    mkdir -p "$OUT"
    python3 - "$OUT" <<'PY'
import os, sys
out = sys.argv[1]
frames = 5
bins = 6
rows = []
for f in range(frames):
    for b in range(bins):
        mag = (f * 7 + b * 11) % 29   # deterministic non-negative integer magnitudes
        rows.append("%d,%d,%d" % (f, b, mag))
with open(os.path.join(out, "magnitudes.csv"), "w") as fh:
    fh.write("frame,bin,magnitude\n")
    fh.write("\n".join(rows))
    fh.write("\n")
PY
    awk -f /app/topk.awk -v k="$K" "$OUT/magnitudes.csv" > "$OUT/peaks.csv"
    ;;
  subset)
    MAGCSV="${2:?subset mode needs MAGCSV}"
    OUTP="${3:?subset mode needs OUTCSV}"
    awk -f /app/topk.awk -v k="$K" "$MAGCSV" > "$OUTP"
    ;;
  *)
    echo "usage: pipeline.sh full OUTDIR | pipeline.sh subset MAGCSV OUTCSV" >&2
    exit 2
    ;;
esac
SH
chmod +x /app/pipeline.sh

# ---------------------------------------------------------------------------
# 6) Visible fixture to demonstrate / exercise the tools
# ---------------------------------------------------------------------------
mkdir -p /app/fixtures
cat > /app/fixtures/magnitudes.csv <<'CSV'
frame,bin,magnitude
0,0,12
0,1,48
0,2,33
1,3,7
1,1,99
1,2,3
1,0,41
CSV

echo "gale-bridge oracle complete"