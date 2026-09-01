# Build a safe HTML markup sanitizer

You are hardening a markup sanitizer that will be used to allow untrusted users
to post small HTML fragments on a public site. Security review found that
several dangerous constructs can slip through, so you must write a program that
strips them and produces a safe fragment that can be rendered.

## Deliverable

Create the file **`/app/clean.py`**. It must be a standalone command-line tool:

```
python3 /app/clean.py INPUT OUTPUT
```

- `INPUT` — absolute path to a UTF-8 HTML fragment (plain text is also allowed).
- `OUTPUT` — absolute path where the sanitized fragment must be written.
- Behavior: read `INPUT`, sanitize it per the rules below, write the resulting
  fragment to `OUTPUT`. Exit `0` on success and any non-zero code on error.
- Do **never** modify or overwrite `INPUT`. Only ever write to `OUTPUT`.

Use Python's standard library only (you may use `html.parser`; other stdlib
modules are fine). The program must not make network requests and must run
offline.

## Sanitization rules (the contract)

Apply all of the following, in any order that yields the same result:

1. **Remove whole elements.** The following elements are removed **along with
   all of their content and closing tags**: `script`, `style`, `template`,
   `iframe`, `object`, `embed`, `svg`, `math`, `link`, `meta`, `base`,
   `title`, `frame`, `frameset`, `noscript`. Tag matching must be
   case-insensitive (`<SCRIPT>`, `<ScRiPt>`).

2. **Remove comments.** All HTML comments `<!-- ... -->` (and any
   surrounding leftover) are removed entirely.

3. **Remove a document type and processing instructions** (`<!DOCTYPE ...>`,
   `<?...?>`).

4. **Remove event-handler attributes.** Any attribute whose name **starts with
   `on`** (case-insensitive), e.g. `onclick`, `onload`, `onerror`, `onfocus`,
   `onmouseover`, is removed.

5. **Filter URL attributes.** For URL-carrying attributes (`href`, `src`,
   `action`, `formaction`, `poster`, `cite`): strip leading whitespace and
   control characters from the value first, then inspect the scheme. If the
   value has a scheme it must be one of the allowed set:
   `http`, `https`, `mailto`, `ftp`, `tel`, `sms`, `irc`, `urn`, `xmpp`,
   `news`, `nntp`. Any other scheme — most importantly `javascript:`,
   `data:`, `vbscript:` — causes that attribute to be **removed**. Values with
   no scheme (relative like `images/x.jpg`, protocol-relative like
   `//cdn.example.com/f.js`, or fragment-only `#top`) are **kept**.

6. **Whitelist attributes.** Keep only these attribute names (case-insensitive)
   on an element: `id`, `class`, `title`, `alt`, `href`, `src`, `rel`,
   `target`, `colspan`, `rowspan`, `name`, `value`. All other attributes —
   including `style`, `width`, `height`, `srcdoc`, `data-*` — are removed.

7. **Whitelist elements.** Keep the tags: `p`, `h1`–`h6`, `div`, `span`, `b`,
   `strong`, `i`, `em`, `u`, `s`, `sub`, `sup`, `mark`, `small`, `ul`, `ol`,
   `li`, `dl`, `dt`, `dd`, `blockquote`, `pre`, `code`, `abbr`, `cite`, `a`,
   `img`, `br`, `hr`, `table`, `caption`, `thead`, `tbody`, `tfoot`, `tr`,
   `td`, `th`. Any element tag not in this list is dropped as a tag, but its
   inner text content is preserved. Blocks from rule 1 are already excluded.

8. **Preserve text.** Ordinary character data is preserved. The characters
   `&`, `<`, `>` in text must be escaped (`&amp;`, `&lt;`, `&gt;`) so the
   fragment stays well-formed. Comments and removed-element content produce no
   text.

9. **Robustness.** The program must never crash on malformed or adversarial
   input. Empty input => empty output. Plain text with no tags => the text is
   kept (escaped). If `INPUT` cannot be read, exit non-zero.

## How output is compared

The verifier runs `/app/clean.py` on the visible case and several hidden cases
and compares each result against a canonical expected fragment. Canonicalization
performed by the verifier is: lowercase tag and attribute names, sort attributes
on an element, collapse all runs of whitespace in text to a single space, drop
empty text, and drop any stray leading/trailing whitespace. You do not need to
reproduce a specific serialization, only produce a **correct and safe**
sanitized fragment; formatting differences that do not affect the canonical form
are ignored.

## Otherwise

`/app` may contain whatever supporting files you need. Do not modify any input
files supplied to you. The verifier will supply its own adversarial inputs that
conform to the documented contract above, including edge cases such as: mixed
upper/lowercase tag and attribute names, `javascript:` / `data:` /
`vbscript:` hrefs, event-handler attributes in many spellings, and nested
`script`/`style`/`iframe` content that must be fully removed even when the
closing tag is present.