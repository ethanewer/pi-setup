# Compile a LaTeX document to PDF

`/app/report.tex` is a small LaTeX document. Compile it to a PDF with **pdflatex**
(available in this environment under that name).

Run pdflatex on `/app/report.tex` so that it produces a PDF file at
`/app/report.pdf`. It is fine and common to run pdflatex more than once (a first
pass resolves references; a second pass finalizes them), but a single successful
pass is normally sufficient.

When done, confirm that `/app/report.pdf` exists and is a valid PDF (it will start
with the characters `%PDF-` and be larger than 2 KB).