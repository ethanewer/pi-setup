# Add Picdrome site support to gallery-dl

## Context

`/app/src` is a check-out of the real upstream project **gallery-dl**
(mikf/gallery-dl), an image-downloader that knows how to fetch galleries from
a long list of image sites. Per-site support lives *inside* the project
itself, in its extractor machinery; the tool is invoked as
`python3 -m gallery_dl` from `/app/src`.

The fictional site **Picdrome** exists nowhere on the internet. A loopback
mock of it ships in this container. Your job is to extend the gallery-dl
check-out so that the gallery-dl CLI itself can download Picdrome galleries:
given a Picdrome URL, the tool must recognize the site, fetch the gallery
page, download every media file it links, and report the gallery's metadata.

## Environment

- gallery-dl sources: `/app/src` (Python 3.12 + the `requests` library are
  already installed; do not pip-install the project).
- The trial has **no network access except loopback**. Anything not already
  in the container is unavailable.
- The mock site is served over plain HTTP on the loopback interface
  (`127.0.0.1`).
- The mock site lives at `/app/mock_site`. Start it with
  `python3 /app/mock_site/server.py` — it serves `/app/mock_site` on
  `http://127.0.0.1:8765`. The server accepts `--root` and `--port`
  options and can run on any local port; there is no fixed site port.
- The visible fixture has two galleries — `gallery/aurora/` and
  `gallery/tidepools/` — plus their media. Develop against them: start the
  server, fetch the pages, and read the HTML to learn the site's structure.
  Treat the mock site and its files as read-only input.

## Task

Make `python3 -m gallery_dl` (run from `/app/src`) handle Picdrome:

1. It must recognize gallery URLs of the form
   `http://127.0.0.1:<port>/gallery/<slug>/` (trailing slash optional;
   the port varies from run to run and must never be assumed).
2. For such a URL it must download **every media file the gallery page links
   to**, once each, in page order.
3. It must report gallery metadata through the CLI's metadata output (see the
   contract below).

The work happens inside `/app/src` and must survive through gallery-dl's own
normal machinery: the site must be discovered by the unmodified tool through
the same mechanism as all its other supported sites, so that
`python3 -m gallery_dl --list-extractors picdrome` (from `/app/src`) lists
your extractor.

## Output contract (the verifier checks exactly this)

The verifier runs three hidden Picdrome galleries. Each is served by its own
mock-server instance on a **different** loopback port than the development
one; the hidden galleries have different slugs, titles, image counts and file
types than the visible fixture.

1. **Discovery.** `cd /app/src && python3 -m gallery_dl --list-extractors picdrome`
   lists your extractor class.

2. **Download, naming, bytes.** With the mock server serving a gallery at
   `http://127.0.0.1:<port>/gallery/<slug>/`, running
   `cd /app/src && python3 -m gallery_dl -d <outdir> "<that url>"`
   must write exactly one file per linked media file, named `<NNN>.<ext>`
   where `<NNN>` is the 1-based position of the media link in the page,
   zero-padded to three digits, and `<ext>` is the extension of the linked
   media file's URL. Each written file must be byte-identical to the served
   media file.

3. **Metadata.** `cd /app/src && python3 -m gallery_dl -j "<that url>"`
   must print a picdrome gallery record whose `title` equals the text between
   the gallery page's `<title>` and `</title>` markers and whose `count`
   equals the number of media files the page links to.

Nothing may be hardcoded to a specific gallery: titles, slugs, image counts,
extensions and the port all differ in the hidden runs.

## Constraints

- No internet at run time. The mock server is the only HTTP endpoint; the
  extractor must not call any other host (and cannot).
- Do not change the mock site, the server, or anything outside `/app/src`.
- Do not restructure the gallery-dl check-out in a way that breaks its other
  sites; the verifier runs the tool in its normal configuration.

## Deliverable

- `/app/src/gallery_dl/extractor/picdrome.py` — the new extractor module for
  the Picdrome site (the interesting details — how the URL pattern looks, how
  the page is parsed, and how the module is wired into the project's
  discovery — are yours to figure out from the tree).