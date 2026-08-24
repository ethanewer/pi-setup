# LaTeX

Write a LaTeX document to `/app/answer.tex` that, when compiled, produces a one-page article containing a single **display equation**:

$$ g(x) = \frac{x}{2} + 1 $$

Use a minimal but complete, correctly-syntaxed LaTeX source. Required elements:

1. A `\documentclass` declaration (e.g. `\documentclass{article}`).
2. `\begin{document}` … `\end{document}`.
3. Inside the document, the phrase "The formula" followed by the display equation typeset with `\frac` (use `\[` … `\]` or an equation environment).

A valid example:

```latex
\documentclass{article}
\begin{document}
The formula
\[
g(x) = \frac{x}{2} + 1
\]
\end{document}
```

The grader inspects the source text for `\documentclass`, `\begin{document}`, `\end{document}`, and a correct `\frac` usage; it does not compile. Make sure the tokens above appear verbatim.