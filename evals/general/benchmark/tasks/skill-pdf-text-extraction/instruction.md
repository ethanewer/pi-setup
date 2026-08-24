# Extract text from a PDF

`/app/doc.pdf` is a single-page PDF document that contains one sentence of readable
text.

Extract the textual content from the PDF using **pypdf** (the `pypdf` module; e.g.
`from pypdf import PdfReader`). Write the extracted sentence to `/app/extracted.txt`.

The extracted text must match the document's sentence exactly (this includes the
internal single spaces between words). Strip leading/trailing whitespace and newlines
(so the file contains only the sentence itself followed by a single trailing newline).

When done, confirm `/app/extracted.txt` exists and contains exactly one non-empty line
of the extracted sentence.