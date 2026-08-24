#!/bin/bash
set -euo pipefail
cat > /app/answer.tex <<'EOF'
\documentclass{article}
\begin{document}
The formula
\[
g(x) = \frac{x}{2} + 1
\]
\end{document}
EOF
echo "wrote answer.tex"